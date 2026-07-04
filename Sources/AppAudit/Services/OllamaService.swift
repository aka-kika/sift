import Foundation

/// Single source of truth for Ollama defaults and generation tuning. Tuned for
/// the best, most consistent structured output rather than raw speed: low
/// temperature for deterministic scoring, a roomy context window so link
/// evidence and the workflow profile fit, and keep_alive so the model stays
/// resident across the scan instead of reloading per app.
enum OllamaDefaults {
    /// Default local model for this personal edition. Picked by benchmarking the
    /// installed models on this exact task: it follows the required structured
    /// format reliably, gives good explanations and scoring, and is reasonably
    /// fast. Pure "thinking" models (e.g. qwen3.6) are avoided as the default —
    /// they spend their token budget reasoning and can return an empty answer.
    /// Change it any time in Settings → Models (the picker lists what you have).
    static let model = "kika-ohllama:latest"

    static let baseURL = "http://localhost:11434"

    /// Generation options sent to Ollama for every analysis request.
    static let options = Options()

    /// How long Ollama keeps the model loaded after a request. Keeping it warm
    /// for the duration of a scan avoids a multi-second reload before each app.
    static let keepAlive = "30m"

    struct Options: Encodable {
        let temperature: Double = 0.15
        let top_p: Double = 0.9
        let top_k: Int = 40
        let repeat_penalty: Double = 1.1
        let num_ctx: Int = 8192
        /// Output cap. The structured answer is short, but reasoning-capable
        /// models (e.g. qwen3) spend tokens thinking first, so leave headroom —
        /// the parser scans for the EXPLANATION/SCORE/REASON/BEST_USE lines and
        /// ignores any reasoning that precedes them.
        let num_predict: Int = 1024
    }
}

actor OllamaService: AnalysisService {

    typealias OllamaResult = AnalysisResult

    struct OllamaRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool = false
        let options: OllamaDefaults.Options = OllamaDefaults.options
        let keep_alive: String = OllamaDefaults.keepAlive

        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    struct OllamaResponse: Decodable {
        let message: Message
        struct Message: Decodable {
            let content: String
        }
    }

    private var baseURL: String {
        UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? OllamaDefaults.baseURL
    }

    private var model: String {
        UserDefaults.standard.string(forKey: "ollamaModel") ?? OllamaDefaults.model
    }

    /// Optional API key. When set, sent as a Bearer token so cloud models
    /// (e.g. via https://ollama.com) authenticate. Ignored by a local server.
    private var apiKey: String {
        (UserDefaults.standard.string(forKey: "ollamaApiKey") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let systemPrompt = AppAnalysisPrompt.system + "\nAlways respond in the exact structured format requested. No extra commentary before or after."

    private func chat(messages: [OllamaRequest.Message]) async -> OllamaResult {
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            return .unavailable("Invalid Ollama URL")
        }

        let allMessages = [OllamaRequest.Message(role: "system", content: systemPrompt)] + messages
        let requestBody = OllamaRequest(model: model, messages: allMessages)

        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = apiKey
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(OllamaResponse.self, from: data)
            return .success(response.message.content.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .networkConnectionLost {
            return .unavailable("Ollama is not running. Start it with: ollama serve")
        } catch {
            return .unavailable("Ollama error: \(error.localizedDescription)")
        }
    }

    /// Single request returning explanation, score, reason, and best use — 3x faster than separate calls.
    func analyze(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil, linkEvidence: String? = nil, userNotes: String? = nil) async -> OllamaResult {
        let prompt = AppAnalysisPrompt.build(
            app: app,
            profile: profile,
            appURL: appURL,
            linkEvidence: linkEvidence,
            includeResponseFormat: true,
            styleNotes: AppAnalysisPrompt.currentStyleNotes,
            userNotes: userNotes ?? ""
        )
        return await chat(messages: [.init(role: "user", content: prompt)])
    }

    func complete(prompt: String) async -> AnalysisResult {
        await chat(messages: [.init(role: "user", content: prompt)])
    }

    func parseAnalysis(from response: String) -> (explanation: String, score: Int, reason: String, bestUse: String)? {
        var explanation: String?
        var score: Int?
        var reason: String?
        var bestUse: String?

        // Strip any leading markdown noise from a label line so "**EXPLANATION:**"
        // and "- EXPLANATION:" match the same way "EXPLANATION:" does.
        func normalizedLabel(_ line: String, _ label: String) -> String? {
            var s = line.trimmingCharacters(in: .whitespaces)
            while let first = s.first, "*#>-•".contains(first) || first == " " {
                s.removeFirst()
            }
            guard s.uppercased().hasPrefix(label) else { return nil }
            var value = String(s.dropFirst(label.count))
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: " *:#"))
            return value.trimmingCharacters(in: .whitespaces)
        }

        // First 1–5 digit anywhere in the value: handles "4", "4/5", "Score 4 of 5".
        func firstScore(in value: String) -> Int? {
            for ch in value where ch.isNumber {
                if let n = Int(String(ch)), (1...5).contains(n) { return n }
            }
            return nil
        }

        for line in stripThinking(from: response).components(separatedBy: .newlines) {
            if let v = normalizedLabel(line, "EXPLANATION") {
                explanation = v
            } else if let v = normalizedLabel(line, "SCORE") {
                score = firstScore(in: v)
            } else if let v = normalizedLabel(line, "REASON") {
                reason = v
            } else if let v = normalizedLabel(line, "BEST_USE") {
                bestUse = v
            }
        }

        guard let e = explanation, !e.isEmpty,
              let s = score, (1...5).contains(s),
              let r = reason, !r.isEmpty,
              let b = bestUse else { return nil }
        return (e, s, r, b)
    }

    /// Remove any inline `<think>…</think>` reasoning some models emit before the
    /// structured answer, so it never leaks into a parsed field.
    private func stripThinking(from response: String) -> String {
        guard response.localizedCaseInsensitiveContains("<think>") else { return response }
        var out = response
        while let open = out.range(of: "<think>", options: .caseInsensitive) {
            if let close = out.range(of: "</think>", options: .caseInsensitive, range: open.upperBound..<out.endIndex) {
                out.removeSubrange(open.lowerBound..<close.upperBound)
            } else {
                out.removeSubrange(open.lowerBound..<out.endIndex)
                break
            }
        }
        return out
    }

    // Keep for legacy compatibility
    func explain(app: AppInfo) async -> OllamaResult { await analyze(app: app, profile: .generic(), linkEvidence: nil) }
    func score(app: AppInfo, profile: WorkflowProfile) async -> OllamaResult { await analyze(app: app, profile: profile, linkEvidence: nil) }
    func bestUse(app: AppInfo, profile: WorkflowProfile) async -> OllamaResult { await analyze(app: app, profile: profile, linkEvidence: nil) }
    func parseScore(from response: String) -> (score: Int, reason: String)? {
        if let parsed = parseAnalysis(from: response) {
            return (parsed.score, parsed.reason)
        }

        var score: Int?
        var reason: String?

        for line in response.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("SCORE:") {
                let raw = trimmed.dropFirst("SCORE:".count).trimmingCharacters(in: .whitespaces)
                score = Int(raw.prefix(1))
            } else if trimmed.hasPrefix("REASON:") {
                reason = trimmed.dropFirst("REASON:".count).trimmingCharacters(in: .whitespaces)
            }
        }

        guard let score, (1...5).contains(score), let reason, !reason.isEmpty else { return nil }
        return (score, reason)
    }

    var currentModel: String { model }

    func fetchModels() async -> ModelFetchResult {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            return .failure("Invalid URL")
        }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "GET"
        let key = apiKey
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failure("Ollama returned an error response")
            }
            struct TagsResponse: Decodable {
                struct Model: Decodable { let name: String }
                let models: [Model]
            }
            let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
            return .models(decoded.models.map(\.name))
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .timedOut {
            return .failure("Cannot connect — is Ollama running? Try: ollama serve")
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

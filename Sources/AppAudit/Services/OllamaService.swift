import Foundation

actor OllamaService {

    struct OllamaRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool = false

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

    enum OllamaResult: Sendable {
        case success(String)
        case unavailable(String)
    }

    private var baseURL: String {
        UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
    }

    private var model: String {
        UserDefaults.standard.string(forKey: "ollamaModel") ?? "llama3.2"
    }

    private let systemPrompt = AppAnalysisPrompt.system + "\nAlways respond in the exact structured format requested. No extra commentary before or after."

    private func chat(messages: [OllamaRequest.Message]) async -> OllamaResult {
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            return .unavailable("Invalid Ollama URL")
        }

        let allMessages = [OllamaRequest.Message(role: "system", content: systemPrompt)] + messages
        let requestBody = OllamaRequest(model: model, messages: allMessages)

        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

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
    func analyze(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil) async -> OllamaResult {
        let prompt = AppAnalysisPrompt.build(
            app: app,
            profile: profile,
            appURL: appURL,
            includeResponseFormat: true
        )
        return await chat(messages: [.init(role: "user", content: prompt)])
    }

    func parseAnalysis(from response: String) -> (explanation: String, score: Int, reason: String, bestUse: String)? {
        var explanation: String?
        var score: Int?
        var reason: String?
        var bestUse: String?

        func after(_ prefix: String, in line: String) -> String {
            String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }

        for line in response.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("EXPLANATION:") {
                explanation = after("EXPLANATION:", in: trimmed)
            } else if trimmed.hasPrefix("SCORE:") {
                let raw = after("SCORE:", in: trimmed)
                score = Int(raw.prefix(1))
            } else if trimmed.hasPrefix("REASON:") {
                reason = after("REASON:", in: trimmed)
            } else if trimmed.hasPrefix("BEST_USE:") {
                bestUse = after("BEST_USE:", in: trimmed)
            }
        }

        guard let e = explanation, !e.isEmpty,
              let s = score, (1...5).contains(s),
              let r = reason, !r.isEmpty,
              let b = bestUse else { return nil }
        return (e, s, r, b)
    }

    // Keep for legacy compatibility
    func explain(app: AppInfo) async -> OllamaResult { await analyze(app: app, profile: .generic()) }
    func score(app: AppInfo, profile: WorkflowProfile) async -> OllamaResult { await analyze(app: app, profile: profile) }
    func bestUse(app: AppInfo, profile: WorkflowProfile) async -> OllamaResult { await analyze(app: app, profile: profile) }
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
}

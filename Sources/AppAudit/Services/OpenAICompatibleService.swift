import Foundation

/// One transport for every provider that speaks the OpenAI Chat Completions
/// dialect: OpenAI itself, Google Gemini (its OpenAI-compatible endpoint), and
/// OpenRouter. Only the base URL, the credentials keys, and how the model list
/// is tidied differ — so they are data, not three copies of the same actor.
actor OpenAICompatibleService: AnalysisService {

    struct Endpoint: Sendable {
        let kind: AnalysisProviderKind
        /// Base URL up to (not including) `/chat/completions` and `/models`.
        let defaultBaseURL: String
        /// UserDefaults key for a user-overridden base URL, if the provider allows one.
        let baseURLDefaultsKey: String?
        /// Extra headers the provider asks for (OpenRouter attributes traffic by app).
        let extraHeaders: [String: String]

        static func forKind(_ kind: AnalysisProviderKind) -> Endpoint {
            switch kind {
            case .openAI:
                return Endpoint(kind: kind,
                                defaultBaseURL: "https://api.openai.com/v1",
                                baseURLDefaultsKey: "openAIBaseURL",
                                extraHeaders: [:])
            case .gemini:
                return Endpoint(kind: kind,
                                defaultBaseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
                                baseURLDefaultsKey: nil,
                                extraHeaders: [:])
            case .openRouter:
                return Endpoint(kind: kind,
                                defaultBaseURL: "https://openrouter.ai/api/v1",
                                baseURLDefaultsKey: nil,
                                extraHeaders: ["HTTP-Referer": "https://sift.akakika.com",
                                               "X-Title": "Sift"])
            case .ollama, .anthropic:
                preconditionFailure("\(kind.displayName) has its own service")
            }
        }
    }

    private let endpoint: Endpoint

    init(kind: AnalysisProviderKind) {
        endpoint = Endpoint.forKind(kind)
    }

    private var name: String { endpoint.kind.displayName }

    private var apiKey: String {
        (UserDefaults.standard.string(forKey: endpoint.kind.apiKeyDefaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var model: String {
        UserDefaults.standard.string(forKey: endpoint.kind.modelDefaultsKey) ?? endpoint.kind.defaultModel
    }

    /// The stored OpenAI base URL predates the `/v1` convention used here, so a bare
    /// host is completed and a trailing slash is dropped.
    private var baseURL: String {
        var base = endpoint.defaultBaseURL
        if let key = endpoint.baseURLDefaultsKey,
           let custom = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            base = custom
        }
        while base.hasSuffix("/") { base.removeLast() }
        if endpoint.kind == .openAI, !base.hasSuffix("/v1") { base += "/v1" }
        return base
    }

    private struct Request: Encodable {
        let model: String
        let messages: [Message]
        struct Message: Encodable { let role: String; let content: String }
    }

    private struct Response: Decodable {
        let choices: [Choice]
        struct Choice: Decodable {
            let message: Message
            struct Message: Decodable { let content: String? }
        }
    }

    private func makeRequest(path: String, method: String, timeout: TimeInterval, key: String) -> URLRequest? {
        guard let url = URL(string: "\(baseURL)/\(path)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        for (header, value) in endpoint.extraHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }
        return request
    }

    private func chat(prompt: String) async -> AnalysisResult {
        let key = apiKey
        guard !key.isEmpty else {
            return .unavailable("Add a \(name) API key in Settings → Models.")
        }
        guard var request = makeRequest(path: "chat/completions", method: "POST", timeout: 90, key: key) else {
            return .unavailable("Invalid \(name) URL")
        }

        let body = Request(
            model: model,
            messages: [
                .init(role: "system", content: AnalysisHTTP.systemPrompt),
                .init(role: "user", content: prompt)
            ]
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return .unavailable(Self.describe(status: http.statusCode, provider: name))
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            let text = decoded.choices.first?.message.content ?? ""
            return .success(text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return .unavailable("\(name) error: \(error.localizedDescription)")
        }
    }

    /// Free tiers fail in one specific way — a quota hit — and that deserves a
    /// message that says so instead of "check your key".
    static func describe(status: Int, provider: String) -> String {
        switch status {
        case 401, 403: return "\(provider) rejected the API key (\(status))."
        case 404: return "\(provider) does not know this model (404). Pick another in Settings → Models."
        case 429: return "\(provider) rate limit or daily free quota reached (429). Try again later or pick a smaller model."
        default: return "\(provider) error (\(status)). Check your API key and model."
        }
    }

    func analyze(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil, linkEvidence: String? = nil, userNotes: String? = nil, docsEvidence: String? = nil) async -> AnalysisResult {
        let prompt = AppAnalysisPrompt.build(app: app, profile: profile, appURL: appURL, linkEvidence: linkEvidence, includeResponseFormat: true, styleNotes: AppAnalysisPrompt.currentStyleNotes, userNotes: userNotes ?? "", docsEvidence: docsEvidence ?? "")
        return await chat(prompt: prompt)
    }

    func complete(prompt: String) async -> AnalysisResult {
        await chat(prompt: prompt)
    }

    func fetchModels() async -> ModelFetchResult {
        let key = apiKey
        guard !key.isEmpty else { return .failure("Add a \(name) API key first.") }
        guard let request = makeRequest(path: "models", method: "GET", timeout: 8, key: key) else {
            return .failure("Invalid URL")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                return .failure(Self.describe(status: status, provider: name))
            }
            struct ModelsResponse: Decodable {
                struct Model: Decodable { let id: String }
                let data: [Model]
            }
            let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
            return .models(Self.tidyModelIDs(decoded.data.map { $0.id }, for: endpoint.kind))
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Provider-specific tidying of a raw `/models` list so the picker shows the
    /// useful entries first: chat-capable families for OpenAI, `models/`-stripped
    /// IDs for Gemini, and free models ahead of paid ones for OpenRouter.
    static func tidyModelIDs(_ ids: [String], for kind: AnalysisProviderKind) -> [String] {
        switch kind {
        case .openAI:
            let chat = ids
                .filter { $0.hasPrefix("gpt") || $0.hasPrefix("o1") || $0.hasPrefix("o3") || $0.hasPrefix("chatgpt") }
                .sorted()
            return chat.isEmpty ? ids.sorted() : chat
        case .gemini:
            return ids
                .map { $0.hasPrefix("models/") ? String($0.dropFirst("models/".count)) : $0 }
                .filter { $0.hasPrefix("gemini") }
                .sorted()
        case .openRouter:
            let router = ids.filter { $0 == "openrouter/free" }
            let free = ids.filter { $0.hasSuffix(":free") }.sorted()
            let paid = ids.filter { !$0.hasSuffix(":free") && $0 != "openrouter/free" }.sorted()
            return router + free + paid
        case .ollama, .anthropic:
            return ids.sorted()
        }
    }
}

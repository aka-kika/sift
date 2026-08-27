import Foundation

/// Anthropic (Claude) provider via the Messages API. API key + model are read from
/// app preferences (set in Settings).
actor AnthropicService: AnalysisService {

    private let kind = AnalysisProviderKind.anthropic

    private var apiKey: String {
        (UserDefaults.standard.string(forKey: kind.apiKeyDefaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var model: String {
        UserDefaults.standard.string(forKey: kind.modelDefaultsKey) ?? kind.defaultModel
    }

    private var baseURL: String {
        UserDefaults.standard.string(forKey: "anthropicBaseURL") ?? "https://api.anthropic.com"
    }

    private struct Request: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
        struct Message: Encodable { let role: String; let content: String }
    }

    private struct Response: Decodable {
        let content: [Block]
        struct Block: Decodable { let type: String; let text: String? }
    }

    private func makeRequest(path: String, method: String, timeout: TimeInterval, key: String) -> URLRequest? {
        guard let url = URL(string: "\(baseURL)/\(path)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        return request
    }

    /// One transport for both the structured analysis and free-form completions;
    /// only the output budget differs.
    private func send(prompt: String, maxTokens: Int) async -> AnalysisResult {
        let key = apiKey
        guard !key.isEmpty else {
            return .unavailable("Add an Anthropic API key in Settings → Models.")
        }
        guard var request = makeRequest(path: "v1/messages", method: "POST", timeout: 90, key: key) else {
            return .unavailable("Invalid Anthropic URL")
        }

        let body = Request(
            model: model,
            max_tokens: maxTokens,
            system: AnalysisHTTP.systemPrompt,
            messages: [.init(role: "user", content: prompt)]
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return .unavailable(AnalysisHTTP.describe(status: http.statusCode, provider: kind.displayName))
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            let text = decoded.content.compactMap(\.text).joined()
            return .success(text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return .unavailable("Anthropic error: \(error.localizedDescription)")
        }
    }

    func analyze(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil, linkEvidence: String? = nil, userNotes: String? = nil, docsEvidence: String? = nil) async -> AnalysisResult {
        let prompt = AppAnalysisPrompt.build(app: app, profile: profile, appURL: appURL, linkEvidence: linkEvidence, includeResponseFormat: true, styleNotes: AppAnalysisPrompt.currentStyleNotes, userNotes: userNotes ?? "", docsEvidence: docsEvidence ?? "")
        return await send(prompt: prompt, maxTokens: 600)
    }

    func complete(prompt: String) async -> AnalysisResult {
        await send(prompt: prompt, maxTokens: 400)
    }

    func fetchModels() async -> ModelFetchResult {
        let key = apiKey
        guard !key.isEmpty else { return .failure("Add an Anthropic API key first.") }
        guard let request = makeRequest(path: "v1/models", method: "GET", timeout: 8, key: key) else {
            return .failure("Invalid URL")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                return .failure(AnalysisHTTP.describe(status: status, provider: kind.displayName))
            }
            let decoded = try JSONDecoder().decode(AnalysisHTTP.ModelsResponse.self, from: data)
            return .models(decoded.data.map(\.id))
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

import Foundation

/// Anthropic (Claude) provider via the Messages API. API key + model are read from
/// app preferences (set in Settings).
actor AnthropicService: AnalysisService {

    private var apiKey: String {
        (UserDefaults.standard.string(forKey: "anthropicApiKey") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var model: String {
        UserDefaults.standard.string(forKey: "anthropicModel") ?? "claude-3-5-haiku-latest"
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

    func analyze(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil, linkEvidence: String? = nil, userNotes: String? = nil) async -> AnalysisResult {
        let prompt = AppAnalysisPrompt.build(app: app, profile: profile, appURL: appURL, linkEvidence: linkEvidence, includeResponseFormat: true, styleNotes: AppAnalysisPrompt.currentStyleNotes, userNotes: userNotes ?? "")
        let key = apiKey
        guard !key.isEmpty else {
            return .unavailable("Add an Anthropic API key in Settings → Models.")
        }
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            return .unavailable("Invalid Anthropic URL")
        }

        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = Request(
            model: model,
            max_tokens: 600,
            system: AnalysisHTTP.systemPrompt,
            messages: [.init(role: "user", content: prompt)]
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return .unavailable("Anthropic error (\(http.statusCode)). Check your API key and model.")
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            let text = decoded.content.compactMap(\.text).joined()
            return .success(text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return .unavailable("Anthropic error: \(error.localizedDescription)")
        }
    }

    func fetchModels() async -> ModelFetchResult {
        let key = apiKey
        guard !key.isEmpty else { return .failure("Add an Anthropic API key first.") }
        guard let url = URL(string: "\(baseURL)/v1/models") else { return .failure("Invalid URL") }

        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failure("Anthropic rejected the request. Check your API key.")
            }
            struct ModelsResponse: Decodable {
                struct Model: Decodable { let id: String }
                let data: [Model]
            }
            let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
            return .models(decoded.data.map(\.id))
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

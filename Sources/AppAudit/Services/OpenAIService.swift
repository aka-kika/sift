import Foundation

/// OpenAI provider via the Chat Completions API. API key + model are read from app
/// preferences (set in Settings).
actor OpenAIService: AnalysisService {

    private var apiKey: String {
        (UserDefaults.standard.string(forKey: "openAIApiKey") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var model: String {
        UserDefaults.standard.string(forKey: "openAIModel") ?? "gpt-4o-mini"
    }

    private var baseURL: String {
        UserDefaults.standard.string(forKey: "openAIBaseURL") ?? "https://api.openai.com"
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
            struct Message: Decodable { let content: String }
        }
    }

    func analyze(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil) async -> AnalysisResult {
        let prompt = AppAnalysisPrompt.build(app: app, profile: profile, appURL: appURL, includeResponseFormat: true)
        let key = apiKey
        guard !key.isEmpty else {
            return .unavailable("Add an OpenAI API key in Settings → Models.")
        }
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            return .unavailable("Invalid OpenAI URL")
        }

        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

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
                return .unavailable("OpenAI error (\(http.statusCode)). Check your API key and model.")
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            let text = decoded.choices.first?.message.content ?? ""
            return .success(text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return .unavailable("OpenAI error: \(error.localizedDescription)")
        }
    }

    func fetchModels() async -> ModelFetchResult {
        let key = apiKey
        guard !key.isEmpty else { return .failure("Add an OpenAI API key first.") }
        guard let url = URL(string: "\(baseURL)/v1/models") else { return .failure("Invalid URL") }

        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failure("OpenAI rejected the request. Check your API key.")
            }
            struct ModelsResponse: Decodable {
                struct Model: Decodable { let id: String }
                let data: [Model]
            }
            let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
            // Chat-capable models only: keep gpt* and o* families, newest-ish first.
            let ids = decoded.data.map(\.id)
                .filter { $0.hasPrefix("gpt") || $0.hasPrefix("o1") || $0.hasPrefix("o3") || $0.hasPrefix("chatgpt") }
                .sorted()
            return .models(ids.isEmpty ? decoded.data.map(\.id).sorted() : ids)
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

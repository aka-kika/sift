import Foundation

/// Analysis provider. Ollama (local or ollama.com cloud) is the default and the
/// focus of this personal edition; Anthropic and OpenAI remain as optional cloud
/// providers. The model identifier embeds the selected model so the cache
/// invalidates appropriately when it changes.
enum AnalysisProviderKind: String, CaseIterable, Identifiable, Sendable {
    case ollama
    case anthropic
    case openAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .anthropic: return "Anthropic"
        case .openAI: return "OpenAI"
        }
    }

    /// UserDefaults key holding the selected model name for this provider.
    var modelDefaultsKey: String {
        switch self {
        case .ollama: return "ollamaModel"
        case .anthropic: return "anthropicModel"
        case .openAI: return "openAIModel"
        }
    }

    /// UserDefaults key holding the API key for this provider (cloud only).
    var apiKeyDefaultsKey: String {
        switch self {
        case .ollama: return "ollamaApiKey"
        case .anthropic: return "anthropicApiKey"
        case .openAI: return "openAIApiKey"
        }
    }

    var defaultModel: String {
        switch self {
        case .ollama: return OllamaDefaults.model
        case .anthropic: return "claude-3-5-haiku-latest"
        case .openAI: return "gpt-4o-mini"
        }
    }

    var modelIdentifier: String {
        modelIdentifier()
    }

    func modelIdentifier(userDefaults: UserDefaults = .standard) -> String {
        let model = userDefaults.string(forKey: modelDefaultsKey) ?? defaultModel
        return "\(rawValue):\(model)"
    }

    static let storageKey = "analysisProviderKind"

    static func current(userDefaults: UserDefaults = .standard) -> AnalysisProviderKind {
        let rawValue = userDefaults.string(forKey: storageKey) ?? Self.ollama.rawValue
        return AnalysisProviderKind(rawValue: rawValue) ?? .ollama
    }
}

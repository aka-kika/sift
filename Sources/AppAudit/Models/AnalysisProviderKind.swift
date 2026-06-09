import Foundation

/// Analysis provider. Ollama (local or ollama.com cloud) plus hosted cloud
/// providers. The model identifier embeds the selected model so the cache
/// invalidates appropriately when it changes.
enum AnalysisProviderKind: String, CaseIterable, Identifiable, Sendable {
    case ollama
    case anthropic
    case openAI
    case appleIntelligence

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .anthropic: return "Anthropic"
        case .openAI: return "OpenAI"
        case .appleIntelligence: return "Apple Intelligence"
        }
    }

    /// UserDefaults key holding the selected model name for this provider.
    var modelDefaultsKey: String {
        switch self {
        case .ollama: return "ollamaModel"
        case .anthropic: return "anthropicModel"
        case .openAI: return "openAIModel"
        case .appleIntelligence: return "appleIntelligenceModel"
        }
    }

    /// UserDefaults key holding the API key for this provider (cloud only).
    var apiKeyDefaultsKey: String {
        switch self {
        case .ollama: return "ollamaApiKey"
        case .anthropic: return "anthropicApiKey"
        case .openAI: return "openAIApiKey"
        case .appleIntelligence: return "appleIntelligenceApiKey" // unused; no key needed
        }
    }

    var defaultModel: String {
        switch self {
        case .ollama: return "llama3.2"
        case .anthropic: return "claude-3-5-haiku-latest"
        case .openAI: return "gpt-4o-mini"
        case .appleIntelligence: return "system-language-model"
        }
    }

    var modelIdentifier: String {
        modelIdentifier()
    }

    func modelIdentifier(userDefaults: UserDefaults = .standard) -> String {
        // Pinned to the pre-1.1.0 identifier so old cached analyses stay valid.
        // There is exactly one on-device system model, so it never varies.
        if self == .appleIntelligence {
            return "apple-intelligence:foundation-models"
        }
        let model = userDefaults.string(forKey: modelDefaultsKey) ?? defaultModel
        return "\(rawValue):\(model)"
    }

    static let storageKey = "analysisProviderKind"

    static func current(userDefaults: UserDefaults = .standard) -> AnalysisProviderKind {
        let rawValue = userDefaults.string(forKey: storageKey) ?? Self.ollama.rawValue
        return AnalysisProviderKind(rawValue: rawValue) ?? .ollama
    }
}

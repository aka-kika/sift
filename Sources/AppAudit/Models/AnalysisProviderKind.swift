import Foundation

/// Analysis provider. Ollama (local or ollama.com cloud) is the default and the
/// focus of this personal edition; the cloud providers are optional, under the
/// user's own key. Gemini and OpenRouter both have free tiers, so a Mac without a
/// local model can still get a full audit at no cost. The model identifier embeds
/// the selected model so the cache invalidates appropriately when it changes.
enum AnalysisProviderKind: String, CaseIterable, Identifiable, Sendable {
    case ollama
    case anthropic
    case openAI
    case gemini
    case openRouter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .anthropic: return "Anthropic"
        case .openAI: return "OpenAI"
        case .gemini: return "Google Gemini"
        case .openRouter: return "OpenRouter"
        }
    }

    /// UserDefaults key holding the selected model name for this provider.
    var modelDefaultsKey: String {
        switch self {
        case .ollama: return "ollamaModel"
        case .anthropic: return "anthropicModel"
        case .openAI: return "openAIModel"
        case .gemini: return "geminiModel"
        case .openRouter: return "openRouterModel"
        }
    }

    /// UserDefaults key holding the API key for this provider (cloud only).
    var apiKeyDefaultsKey: String {
        switch self {
        case .ollama: return "ollamaApiKey"
        case .anthropic: return "anthropicApiKey"
        case .openAI: return "openAIApiKey"
        case .gemini: return "geminiApiKey"
        case .openRouter: return "openRouterApiKey"
        }
    }

    var defaultModel: String {
        switch self {
        case .ollama: return OllamaDefaults.model
        case .anthropic: return "claude-3-5-haiku-latest"
        case .openAI: return "gpt-4o-mini"
        // The free tier's most generous daily quota; the model picker lists the rest.
        case .gemini: return "gemini-2.5-flash-lite"
        // OpenRouter's router alias for whatever is free right now — individual
        // `:free` models come and go, the alias stays.
        case .openRouter: return "openrouter/free"
        }
    }

    /// Where to get a key, shown under the API key field in Settings.
    var apiKeyHint: String {
        switch self {
        case .ollama: return "Optional. Only needed for ollama.com cloud models."
        case .anthropic: return "Anthropic API key (console.anthropic.com). Stored in app preferences."
        case .openAI: return "OpenAI API key (platform.openai.com). Stored in app preferences."
        case .gemini: return "Gemini API key (aistudio.google.com/apikey). The free tier covers a daily allowance of calls — enough for a full audit. Stored in app preferences."
        case .openRouter: return "OpenRouter API key (openrouter.ai/keys). Models ending in :free cost nothing. Stored in app preferences."
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

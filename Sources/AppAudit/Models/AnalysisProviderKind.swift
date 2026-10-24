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

    /// Keychain account for this provider's API key (see `APIKeyStore`).
    var apiKeyAccount: String { rawValue }

    /// Where builds up to 1.12.3 kept the API key, in plain text in the
    /// preferences plist. Read only to migrate it into the Keychain.
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
        case .anthropic: return "Anthropic API key (console.anthropic.com). Stored in the macOS Keychain."
        case .openAI: return "OpenAI API key (platform.openai.com). Stored in the macOS Keychain."
        case .gemini: return "Gemini API key (aistudio.google.com/apikey). The free tier covers a daily allowance of calls — enough for a full audit. Stored in the macOS Keychain."
        case .openRouter: return "OpenRouter API key (openrouter.ai/keys). Models ending in :free cost nothing. Stored in the macOS Keychain."
        }
    }

    var modelIdentifier: String {
        modelIdentifier()
    }

    func modelIdentifier(userDefaults: UserDefaults = .standard) -> String {
        let model = userDefaults.string(forKey: modelDefaultsKey) ?? defaultModel
        return "\(rawValue):\(model)"
    }

    /// After fetching a provider's model list: the model to store, or nil when the
    /// effective choice (stored value, else this provider's default) is already
    /// available. Never replaces a working default just because nothing was stored.
    func modelToSelect(from models: [String], userDefaults: UserDefaults = .standard) -> String? {
        let stored = userDefaults.string(forKey: modelDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let effective = stored.isEmpty ? defaultModel : stored
        if models.contains(effective) { return nil }
        // Ollama lists "llama3.2" as "llama3.2:latest"; both name the same model.
        if self == .ollama, !effective.contains(":"), models.contains(effective + ":latest") { return nil }
        // Embedding models (nomic-embed-text, mxbai-embed-large) cannot chat.
        return models.first { !$0.lowercased().contains("embed") } ?? models.first
    }

    /// The model list entry that names `stored`. Ollama lists "llama3.2" as
    /// "llama3.2:latest"; the picker would show nothing for the bare name.
    static func pickerSelection(stored: String, models: [String]) -> String {
        if models.contains(stored) { return stored }
        if !stored.contains(":"), models.contains(stored + ":latest") { return stored + ":latest" }
        return stored
    }

    /// True only when prompts stay on this Mac: Ollama pointed at a local
    /// server. Ollama can also reach ollama.com cloud models, and every other
    /// provider is a cloud API.
    func runsOnThisMac(userDefaults: UserDefaults = .standard) -> Bool {
        guard self == .ollama else { return false }
        let base = userDefaults.string(forKey: "ollamaBaseURL") ?? OllamaDefaults.baseURL
        guard let host = URL(string: base)?.host()?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    var runsOnThisMac: Bool { runsOnThisMac() }

    static let storageKey = "analysisProviderKind"

    static func current(userDefaults: UserDefaults = .standard) -> AnalysisProviderKind {
        let rawValue = userDefaults.string(forKey: storageKey) ?? Self.ollama.rawValue
        return AnalysisProviderKind(rawValue: rawValue) ?? .ollama
    }
}

/// A model list belongs to the engine it was fetched for. Switching engine
/// while it loads used to save the old engine's model under the new one.
enum ModelFetchOwner {
    static func stillCurrent(fetchedFor: AnalysisProviderKind, current: AnalysisProviderKind) -> Bool {
        fetchedFor == current
    }
}

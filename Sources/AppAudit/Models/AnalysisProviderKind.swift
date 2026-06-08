import Foundation

/// Analysis provider. Currently Ollama only — the enum is retained (rather than
/// removed) so stored preferences and the cache's model identifiers stay stable.
enum AnalysisProviderKind: String, CaseIterable, Identifiable, Sendable {
    case ollama

    var id: String { rawValue }

    var displayName: String { "Ollama" }

    var modelIdentifier: String {
        modelIdentifier()
    }

    func modelIdentifier(userDefaults: UserDefaults = .standard) -> String {
        let model = userDefaults.string(forKey: "ollamaModel") ?? "llama3.2"
        return "ollama:\(model)"
    }

    static let storageKey = "analysisProviderKind"

    static func current(userDefaults: UserDefaults = .standard) -> AnalysisProviderKind {
        .ollama
    }
}

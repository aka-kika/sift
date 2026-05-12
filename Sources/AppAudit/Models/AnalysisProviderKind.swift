import Foundation

enum AnalysisProviderKind: String, CaseIterable, Identifiable, Sendable {
    case ollama
    case appleIntelligence

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama:
            return "Ollama"
        case .appleIntelligence:
            return "Apple Intelligence"
        }
    }

    var modelIdentifier: String {
        modelIdentifier()
    }

    func modelIdentifier(userDefaults: UserDefaults = .standard) -> String {
        switch self {
        case .ollama:
            let model = userDefaults.string(forKey: "ollamaModel") ?? "llama3.2"
            return "ollama:\(model)"
        case .appleIntelligence:
            return "apple-intelligence:foundation-models"
        }
    }

    static let storageKey = "analysisProviderKind"

    static func current(userDefaults: UserDefaults = .standard) -> AnalysisProviderKind {
        let rawValue = userDefaults.string(forKey: storageKey) ?? Self.ollama.rawValue
        return AnalysisProviderKind(rawValue: rawValue) ?? .ollama
    }
}

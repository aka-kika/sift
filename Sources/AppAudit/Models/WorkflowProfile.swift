import Foundation

struct WorkflowProfile: Sendable {
    let customDescription: String

    var promptDescription: String {
        customDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let storageKey = "workflowProfileText"

    static let defaultProfileText = """
    SwiftUI, macOS apps, Ollama, Codex, local-first tools, project cleanup, app packaging, native Apple development, terminal workflows
    """

    /// Used when the user clears their profile: score on general usefulness
    /// instead of silently resurrecting the built-in personal default.
    static let neutralProfileText = """
    A general Mac user with a broad mix of apps and no specific workflow. Judge each app on its general usefulness, popularity of purpose, and upkeep cost.
    """

    static func current(digest: String? = nil, userDefaults: UserDefaults = .standard) -> WorkflowProfile {
        let stored = (userDefaults.string(forKey: storageKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty { return local(text: stored) }
        if let digest, !digest.isEmpty {
            return WorkflowProfile(customDescription: digest)
        }
        return local(text: nil)
    }

    static func local(text: String?) -> WorkflowProfile {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return WorkflowProfile(customDescription: trimmed.isEmpty ? neutralProfileText : trimmed)
    }
}

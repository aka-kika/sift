import Foundation

struct WorkflowProfile: Sendable {
    let languages: [String]
    let tools: [String]
    let domains: [String]
    let projectKeywords: [String]
    let customDescription: String?

    var promptDescription: String {
        if let customDescription,
           !customDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var parts: [String] = []
        if !languages.isEmpty { parts.append("Languages: \(languages.joined(separator: ", "))") }
        if !tools.isEmpty { parts.append("Tools: \(tools.joined(separator: ", "))") }
        if !domains.isEmpty { parts.append("Domains: \(domains.joined(separator: ", "))") }
        if !projectKeywords.isEmpty { parts.append("Projects: \(projectKeywords.joined(separator: ", "))") }
        return parts.joined(separator: ". ")
    }

    static let storageKey = "workflowProfileText"

    static let defaultProfileText = """
    SwiftUI, macOS apps, Ollama, Codex, local-first tools, project cleanup, app packaging, native Apple development, terminal workflows
    """

    static func current(userDefaults: UserDefaults = .standard) -> WorkflowProfile {
        let stored = userDefaults.string(forKey: storageKey)
        return local(text: stored)
    }

    static func local(text: String?) -> WorkflowProfile {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return WorkflowProfile(
            languages: [],
            tools: [],
            domains: [],
            projectKeywords: [],
            customDescription: trimmed.isEmpty ? defaultProfileText : trimmed
        )
    }

    static func generic() -> WorkflowProfile {
        WorkflowProfile(
            languages: ["Swift", "Python", "TypeScript", "JavaScript"],
            tools: ["Xcode", "VS Code", "Terminal", "Git"],
            domains: ["iOS development", "macOS development", "web development"],
            projectKeywords: ["app development", "software engineering"],
            customDescription: nil
        )
    }
}

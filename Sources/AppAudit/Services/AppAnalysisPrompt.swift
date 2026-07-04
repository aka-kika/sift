import Foundation

enum AppAnalysisPrompt {
    static let system = """
    You are an expert macOS app analyst helping a developer audit installed applications.
    Give honest, specific, actionable assessments. Do not write marketing copy.
    Be direct, concise, practical, readable, friendly, and professional.
    Prefer short sentences. Avoid filler, hype, and long paragraphs.
    State what the app is directly and confidently, grounded in the evidence. Do not hedge.
    Never use the phrase "appears to be" or "seems to be". When evidence is genuinely missing or conflicting, name the most likely purpose plainly and keep the score conservative, or say the purpose is unclear — but do not pad every sentence with hedges.
    """

    static func build(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil, linkEvidence: String? = nil, includeResponseFormat: Bool, styleNotes: String = "", userNotes: String = "") -> String {
        let categoryHint = AppCategory.humanName(for: app.category).map { "\nCategory: \($0)" } ?? ""
        let descriptionHint = app.humanReadableDescription.map { "\nApp description hint: \($0)" } ?? ""
        let linkContext = referenceURLContext(from: appURL, fetched: linkEvidence)
        let responseFormat = includeResponseFormat ? """

        Respond in EXACTLY this format with no extra text before or after:
        EXPLANATION: [1-2 short sentences, max 35 words. State directly what the app does and who uses it, grounded in the evidence. Do NOT write "appears to be" or "seems to be". If evidence is missing, say the purpose is unclear rather than inventing a category from the name alone.]
        SCORE: [1-5]
        REASON: [1 short sentence, max 22 words. Explain why this score fits the developer's specific workflow.]
        BEST_USE: [1 short actionable sentence, max 22 words. If irrelevant or unclear, write: Not applicable to your workflow.]
        """ : ""

        let trimmedNotes = styleNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let styleBlock = trimmedNotes.isEmpty
            ? ""
            : "\n\nAdditional style notes from the user (follow them):\n\(trimmedNotes)"

        let trimmedUserNotes = userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesBlock = trimmedUserNotes.isEmpty
            ? ""
            : "\n\nThe user's own notes about this app (their raw words — treat as the strongest evidence for how THEY use it):\n\(trimmedUserNotes)"
        let notesEvidenceRule = trimmedUserNotes.isEmpty
            ? ""
            : "\n- The user's own notes outrank URL and metadata evidence when scoring and writing BEST_USE, but never invent product facts the notes do not state."

        return """
        Analyze this installed macOS app:
        Name: \(app.name)
        Bundle ID: \(app.bundleID)
        Version: \(app.version.isEmpty ? "Unknown" : app.version)
        Path: \(app.path)\(categoryHint)\(descriptionHint)\(linkContext)

        Developer workflow context:
        \(profile.promptDescription)\(notesBlock)

        Evidence rules:
        - Prefer bundle ID, reference URL context, app description, and installed path over the display name.
        - When "Fetched from the reference URL" content is present, treat it as the primary evidence for what the app is.
        - The URL string alone (host, slug, TLD) is only a weak hint. Never infer what an app does from a domain name or TLD — a ".fit" domain does not imply fitness.
        - Do not claim to have browsed beyond what is quoted here.
        - If the URL conflicts with the app name, bundle ID, or path, mention the uncertainty and score conservatively.
        - Do not infer a specific product category from a generic name alone.
        - If you are unsure what the app does, say its purpose is unclear instead of making up details. Do not use the phrase "appears to be".
        - Score unclear apps conservatively unless the metadata clearly matches the workflow.\(notesEvidenceRule)
        \(responseFormat)

        Scoring guide:
        5 = Daily driver for this workflow; uninstalling would break their work
        4 = Regularly useful; removes friction in their specific stack
        3 = Occasionally useful; nice to have but not essential
        2 = Rarely useful; unlikely to serve this workflow
        1 = No overlap; safe to uninstall\(styleBlock)
        """
    }

    /// The user's global analysis style notes from Settings (Profile tab),
    /// trimmed. Empty when unset. Passed into `build(...)` for the non-Apple
    /// engines; Apple Intelligence reads the same key directly.
    static var currentStyleNotes: String {
        (UserDefaults.standard.string(forKey: "analysisStyleNotes") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func referenceURLContext(from appURL: String?, fetched: String? = nil) -> String {
        guard let rawURL = appURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURL.isEmpty else {
            return ""
        }

        guard let url = URL(string: rawURL),
              let host = url.host(percentEncoded: false) else {
            return "\nReference URL: \(rawURL)\nReference URL context: Provided but not parseable. Use cautiously; do not invent page contents."
        }

        let path = url.path(percentEncoded: false)
        let pathSegments = path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        let readablePath = pathSegments.isEmpty ? "(root)" : pathSegments.joined(separator: " / ")
        let sourceKind = referenceSourceKind(host: host, pathSegments: pathSegments)
        let slugHint = readableSlugHint(from: pathSegments)

        var block = """

        Reference URL: \(rawURL)
        Reference URL context:
        - Host: \(host)
        - Source type: \(sourceKind)
        - Path context: \(readablePath)
        - Slug keywords: \(slugHint)
        """

        if let fetched, !fetched.isEmpty {
            block += """

        Fetched from the reference URL (the page's own words — treat as the primary link evidence):
        \(fetched)
        """
        }

        return block
    }

    private static func referenceSourceKind(host: String, pathSegments: [String]) -> String {
        let normalizedHost = host.lowercased()
        if normalizedHost.contains("github.com") {
            return pathSegments.count >= 2 ? "GitHub repository" : "GitHub page"
        }
        if normalizedHost.contains("apps.apple.com") || normalizedHost.contains("itunes.apple.com") {
            return "App Store product page"
        }
        if normalizedHost.contains("docs.") || pathSegments.contains(where: { $0.localizedCaseInsensitiveContains("docs") }) {
            return "Documentation page"
        }
        return "Vendor or product website"
    }

    private static func readableSlugHint(from pathSegments: [String]) -> String {
        let tokens = pathSegments
            .suffix(4)
            .flatMap { segment in
                segment
                    .replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: "_", with: " ")
                    .split(separator: " ")
                    .map(String.init)
            }
            .filter { token in
                let lowercased = token.lowercased()
                return !lowercased.hasPrefix("id") && lowercased != "app" && lowercased != "apps"
            }

        return tokens.isEmpty ? "(none)" : tokens.joined(separator: ", ")
    }
}

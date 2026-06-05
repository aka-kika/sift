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

    static func build(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil, includeResponseFormat: Bool) -> String {
        let descriptionHint = app.humanReadableDescription.map { "\nApp description hint: \($0)" } ?? ""
        let linkContext = referenceURLContext(from: appURL)
        let responseFormat = includeResponseFormat ? """

        Respond in EXACTLY this format with no extra text before or after:
        EXPLANATION: [1-2 short sentences, max 35 words. State directly what the app does and who uses it, grounded in the evidence. Do NOT write "appears to be" or "seems to be". If evidence is missing, say the purpose is unclear rather than inventing a category from the name alone.]
        SCORE: [1-5]
        REASON: [1 short sentence, max 22 words. Explain why this score fits the developer's specific workflow.]
        BEST_USE: [1 short actionable sentence, max 22 words. If irrelevant or unclear, write: Not applicable to your workflow.]
        """ : ""

        return """
        Analyze this installed macOS app:
        Name: \(app.name)
        Bundle ID: \(app.bundleID)
        Version: \(app.version.isEmpty ? "Unknown" : app.version)
        Path: \(app.path)\(descriptionHint)\(linkContext)

        Developer workflow context:
        \(profile.promptDescription)

        Evidence rules:
        - Prefer bundle ID, reference URL context, app description, and installed path over the display name.
        - If a reference URL is provided, use its host and path/slug as strong evidence for what the app is. A GitHub repo slug, App Store product slug, vendor domain, docs path, or product page path can identify the app's real purpose.
        - Do not claim you opened, fetched, read, or verified the URL contents. You only know the URL string and context shown in this prompt.
        - If the URL conflicts with the app name, bundle ID, or path, mention the uncertainty and score conservatively.
        - Do not infer a specific product category from a generic name alone.
        - If you are unsure what the app does, say its purpose is unclear instead of making up details. Do not use the phrase "appears to be".
        - Score unclear apps conservatively unless the metadata clearly matches the workflow.
        \(responseFormat)

        Scoring guide:
        5 = Daily driver for this workflow; uninstalling would break their work
        4 = Regularly useful; removes friction in their specific stack
        3 = Occasionally useful; nice to have but not essential
        2 = Rarely useful; unlikely to serve this workflow
        1 = No overlap; safe to uninstall
        """
    }

    private static func referenceURLContext(from appURL: String?) -> String {
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

        return """

        Reference URL: \(rawURL)
        Reference URL context:
        - Host: \(host)
        - Source type: \(sourceKind)
        - Path context: \(readablePath)
        - Slug keywords: \(slugHint)
        """
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

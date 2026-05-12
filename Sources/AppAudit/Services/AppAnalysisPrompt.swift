import Foundation

enum AppAnalysisPrompt {
    static let system = """
    You are an expert macOS app analyst helping a developer audit installed applications.
    Give honest, specific, actionable assessments. Do not write marketing copy.
    Be direct, concise, and practical.
    Avoid guessing. When metadata is sparse or ambiguous, say what the app appears to be and keep the score conservative.
    """

    static func build(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil, includeResponseFormat: Bool) -> String {
        let descriptionHint = app.humanReadableDescription.map { "\nApp description hint: \($0)" } ?? ""
        let urlHint = appURL.map { "\nReference URL: \($0)" } ?? ""
        let responseFormat = includeResponseFormat ? """

        Respond in EXACTLY this format with no extra text before or after:
        EXPLANATION: [2 clear sentences. Explain what the app does and who uses it. If metadata is sparse, write "appears to" and avoid inventing a category from the name alone.]
        SCORE: [1-5]
        REASON: [1 sentence. Explain why this score fits the developer's specific workflow.]
        BEST_USE: [1 actionable sentence. If irrelevant or unclear, write: Not applicable to your workflow.]
        """ : ""

        return """
        Analyze this installed macOS app:
        Name: \(app.name)
        Bundle ID: \(app.bundleID)
        Version: \(app.version.isEmpty ? "Unknown" : app.version)
        Path: \(app.path)\(descriptionHint)\(urlHint)

        Developer workflow context:
        \(profile.promptDescription)

        Evidence rules:
        - Prefer bundle ID, reference URL, app description, and installed path over the display name.
        - Do not infer a specific product category from a generic name alone.
        - If you are unsure what the app does, say it appears to be unknown or unclear instead of making up details.
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
}

import Foundation

/// Result of a single analysis request from any provider.
enum AnalysisResult: Sendable {
    case success(String)
    case unavailable(String)
}

extension AnalysisResult {
    /// The text of a `.success`, or an empty string otherwise.
    var successText: String {
        if case .success(let text) = self { return text }
        return ""
    }
}

/// Result of fetching the list of available models from a provider.
enum ModelFetchResult: Sendable {
    case models([String])
    case failure(String)
}

/// A provider that analyzes an app and returns the structured text described by
/// `AppAnalysisPrompt`. All providers share the same prompt and the same parser
/// (`OllamaService.parseAnalysis`), so only the transport differs.
protocol AnalysisService: Sendable {
    func analyze(app: AppInfo, profile: WorkflowProfile, appURL: String?, linkEvidence: String?, userNotes: String?, docsEvidence: String?) async -> AnalysisResult
    func fetchModels() async -> ModelFetchResult
    /// A free-form completion for auxiliary features (e.g. finding similar apps).
    /// Returns the model's raw text, or `.unavailable` on error.
    func complete(prompt: String) async -> AnalysisResult
}

/// Shared helpers for HTTP-based analysis providers.
enum AnalysisHTTP {
    /// System prompt shared by every provider.
    static let systemPrompt = AppAnalysisPrompt.system
        + "\nAlways respond in the exact structured format requested. No extra commentary before or after."
}

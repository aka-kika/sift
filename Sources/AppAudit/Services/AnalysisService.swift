import Foundation

/// Result of a single analysis request from any provider.
enum AnalysisResult: Sendable {
    case success(String)
    case unavailable(String)
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
    func analyze(app: AppInfo, profile: WorkflowProfile, appURL: String?) async -> AnalysisResult
    func fetchModels() async -> ModelFetchResult
}

/// Shared helpers for HTTP-based analysis providers.
enum AnalysisHTTP {
    /// System prompt shared by every provider.
    static let systemPrompt = AppAnalysisPrompt.system
        + "\nAlways respond in the exact structured format requested. No extra commentary before or after."
}

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable
private struct AppleIntelligenceAppAnalysis {
    @Guide(description: "Two clear sentences explaining what the app does and who uses it.")
    var explanation: String

    @Guide(description: "Relevance score from 1 to 5 for this developer workflow.", .range(1...5))
    var score: Int

    @Guide(description: "One sentence explaining why this score fits the workflow.")
    var reason: String

    @Guide(description: "One actionable sentence describing the best use for this developer. If irrelevant, say not applicable.")
    var bestUse: String
}
#endif

actor AppleIntelligenceService: AnalysisService {

    private let systemPrompt = AppAnalysisPrompt.system

    private func availabilityMessage() -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(let reason):
                return "Apple Intelligence is unavailable: \(Self.describeAvailabilityReason(reason))"
            @unknown default:
                return "Apple Intelligence is unavailable on this Mac."
            }
        }
        return "Apple Intelligence requires macOS 26 or later."
        #else
        return "Apple Intelligence requires an SDK with Foundation Models."
        #endif
    }

    func analyze(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil) async -> AnalysisResult {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            return .unavailable("Apple Intelligence requires macOS 26 or later.")
        }

        if let message = availabilityMessage() {
            return .unavailable(message)
        }

        let prompt = AppAnalysisPrompt.build(
            app: app,
            profile: profile,
            appURL: appURL,
            // @Generable provides structured output; the text format instructions are not needed.
            includeResponseFormat: false
        )

        do {
            let session = LanguageModelSession {
                systemPrompt
            }
            let response = try await session.respond(
                to: prompt,
                generating: AppleIntelligenceAppAnalysis.self
            )
            let analysis = response.content
            return .success("""
            EXPLANATION: \(analysis.explanation)
            SCORE: \(analysis.score)
            REASON: \(analysis.reason)
            BEST_USE: \(analysis.bestUse)
            """)
        } catch {
            return .unavailable("Apple Intelligence error: \(error.localizedDescription)")
        }
        #else
        return .unavailable("Apple Intelligence requires an SDK with Foundation Models.")
        #endif
    }

    /// There is exactly one on-device system model. "Fetching models" doubles
    /// as the availability check for the Settings status row.
    func fetchModels() async -> ModelFetchResult {
        if let message = availabilityMessage() {
            return .failure(message)
        }
        return .models(["system-language-model"])
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func describeAvailabilityReason(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is not enabled in Settings"
        case .modelNotReady:
            return "the on-device model is still downloading or preparing"
        case .deviceNotEligible:
            return "this Mac is not eligible"
        @unknown default:
            return String(describing: reason)
        }
    }
    #endif
}

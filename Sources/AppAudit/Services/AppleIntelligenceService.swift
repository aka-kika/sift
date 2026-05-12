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

actor AppleIntelligenceService {

    private let systemPrompt = """
    You are an expert macOS app analyst helping a developer audit installed applications.
    Give honest, specific, actionable assessments. Do not write marketing copy.
    Be direct, concise, and practical.
    """

    func availabilityMessage() -> String? {
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

    func analyze(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil) async -> OllamaService.OllamaResult {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            return .unavailable("Apple Intelligence requires macOS 26 or later.")
        }

        if let message = availabilityMessage() {
            return .unavailable(message)
        }

        let hint = app.humanReadableDescription.map { "\nApp description hint: \($0)" } ?? ""
        let urlHint = appURL.map { "\nReference URL: \($0)" } ?? ""
        let prompt = """
        Analyze the macOS app "\(app.name)" (bundle ID: \(app.bundleID))\(hint)\(urlHint)

        Developer workflow context:
        \(profile.promptDescription)

        Scoring guide:
        5 = Daily driver for this workflow; uninstalling would break their work
        4 = Regularly useful; removes friction in their specific stack
        3 = Occasionally useful; nice to have but not essential
        2 = Rarely useful; unlikely to serve this workflow
        1 = No overlap; safe to uninstall
        """

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

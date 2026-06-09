import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable
private struct AppleIntelligenceAppAnalysis {
    @Guide(description: "Two clear sentences explaining what the app does and who uses it.")
    var explanation: String

    @Guide(description: "Relevance score: 1 = no overlap with this workflow, safe to uninstall; 3 = occasionally useful; 5 = a daily driver this workflow depends on.", .range(1...5))
    var score: Int

    @Guide(description: "One sentence explaining why this score fits the workflow.")
    var reason: String

    @Guide(description: "One actionable sentence describing the best use for this developer. If irrelevant, say not applicable.")
    var bestUse: String
}
#endif

actor AppleIntelligenceService: AnalysisService {

    /// Short instructions tuned for small models; the long shared system prompt
    /// overwhelms them and the @Generable schema already carries field guidance.
    private let compactInstructions = """
    You are a macOS app analyst helping a developer decide what to keep.
    Be direct and factual. State what the app is, grounded only in the facts given.
    If the facts don't identify the app, say its purpose is unclear. Never guess from the name alone.
    """

    /// Prefer Apple's Private Cloud Compute model (macOS 27+) when the user has it
    /// enabled — much higher quality than the on-device model, still private.
    private var usePrivateCloudCompute: Bool {
        UserDefaults.standard.object(forKey: "appleIntelligenceUsePCC") as? Bool ?? true
    }

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

        let prompt = AppAnalysisPrompt.compactFacts(app: app, profile: profile, appURL: appURL)
        let options = GenerationOptions(samplingMode: .greedy, temperature: 0, maximumResponseTokens: 220)

        // Private Cloud Compute first (macOS 27+, opt-out in Settings): a far larger
        // model, still private. Any failure falls through to the on-device model.
        if #available(macOS 27.0, *), usePrivateCloudCompute {
            let cloudModel = PrivateCloudComputeLanguageModel()
            if case .available = cloudModel.availability {
                do {
                    let session = LanguageModelSession(model: cloudModel, instructions: compactInstructions)
                    let response = try await session.respond(
                        to: prompt,
                        generating: AppleIntelligenceAppAnalysis.self,
                        options: options
                    )
                    return .success(Self.structuredText(from: response.content))
                } catch {
                    // Quota, network, or service failure — use the on-device model instead.
                }
            }
        }

        do {
            let session = LanguageModelSession {
                compactInstructions
            }
            let response = try await session.respond(
                to: prompt,
                generating: AppleIntelligenceAppAnalysis.self,
                options: options
            )
            return .success(Self.structuredText(from: response.content))
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
    private static func structuredText(from analysis: AppleIntelligenceAppAnalysis) -> String {
        """
        EXPLANATION: \(analysis.explanation)
        SCORE: \(analysis.score)
        REASON: \(analysis.reason)
        BEST_USE: \(analysis.bestUse)
        """
    }

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

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

    @Guide(description: "One actionable sentence describing the best use for this developer. Start with a specific verb other than \"Use\". If irrelevant or unclear, say: Not applicable to your workflow.")
    var bestUse: String
}
#endif

actor AppleIntelligenceService: AnalysisService {

    /// Short instructions tuned for small models; the long shared system prompt
    /// overwhelms them and the @Generable schema already carries field guidance.
    private let compactInstructions = """
    You are a macOS app analyst helping a developer decide what to keep.
    Be direct and factual. State what the app is, grounded only in the facts given.
    If the facts don't identify the app, say its purpose is unclear and keep the score low. Never guess from the name alone.
    Never begin bestUse with the word "Use" — start with a varied, specific verb.

    Example for a file-automation app:
    explanation: Hazel watches folders and runs user-defined rules to move, rename, or clean up files automatically.
    score: 4
    reason: Automated file cleanup directly supports this developer's project-hygiene workflow.
    bestUse: Automate Downloads cleanup with rules that file disk images and installers as they arrive.

    Example for an app whose facts are insufficient:
    explanation: The available facts do not identify what this app does; its purpose is unclear.
    score: 2
    reason: Unidentified apps cannot be matched to the workflow, so the score stays conservative.
    bestUse: Not applicable to your workflow.
    """

    /// Optional user-authored style notes from Settings, appended to the
    /// instructions so the owner can tune phrasing without a rebuild.
    private var styleNotes: String {
        (UserDefaults.standard.string(forKey: "appleIntelligenceStyleNotes") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var instructionsText: String {
        let notes = styleNotes
        guard !notes.isEmpty else { return compactInstructions }
        return compactInstructions + "\n\nAdditional style notes from the user (follow them):\n" + notes
    }

    /// Set after the first failed Private Cloud Compute call so a long scan
    /// doesn't pay a doomed network round-trip per app. Resets on relaunch.
    private var privateCloudComputeFailedThisSession = false

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
        // Lab-validated: few-shot + seeded nucleus sampling removes the "Use it…"
        // monotony that greedy decoding produces, while a fixed seed keeps results
        // reproducible run-to-run.
        let options = GenerationOptions(
            samplingMode: .random(probabilityThreshold: 0.9, seed: 42),
            temperature: 0.7,
            maximumResponseTokens: 220
        )
        let retryOptions = GenerationOptions(
            samplingMode: .random(probabilityThreshold: 0.9, seed: 137),
            temperature: 0.7,
            maximumResponseTokens: 220
        )

        // Private Cloud Compute first (macOS 27+, opt-out in Settings): a far larger
        // model, still private. Any failure falls through to the on-device model.
        if #available(macOS 27.0, *), usePrivateCloudCompute, !privateCloudComputeFailedThisSession {
            let cloudModel = PrivateCloudComputeLanguageModel()
            if case .available = cloudModel.availability {
                do {
                    let session = LanguageModelSession(model: cloudModel, instructions: instructionsText)
                    var analysis = try await session.respond(
                        to: prompt,
                        generating: AppleIntelligenceAppAnalysis.self,
                        options: options
                    ).content
                    if Self.soundsMonotonous(analysis) {
                        let retrySession = LanguageModelSession(model: cloudModel, instructions: instructionsText)
                        analysis = try await retrySession.respond(
                            to: prompt,
                            generating: AppleIntelligenceAppAnalysis.self,
                            options: retryOptions
                        ).content
                    }
                    return .success(Self.structuredText(from: analysis))
                } catch {
                    // Quota, network, or service failure — remember and use the on-device model instead.
                    privateCloudComputeFailedThisSession = true
                }
            }
        }

        do {
            let session = LanguageModelSession {
                instructionsText
            }
            var analysis = try await session.respond(
                to: prompt,
                generating: AppleIntelligenceAppAnalysis.self,
                options: options
            ).content
            if Self.soundsMonotonous(analysis) {
                let retrySession = LanguageModelSession {
                    instructionsText
                }
                analysis = try await retrySession.respond(
                    to: prompt,
                    generating: AppleIntelligenceAppAnalysis.self,
                    options: retryOptions
                ).content
            }
            return .success(Self.structuredText(from: analysis))
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

    /// One real round-trip to Private Cloud Compute. `.availability` lies on some
    /// betas (reports available while every call fails), so only an actual respond
    /// proves it works.
    func probePrivateCloudCompute() async -> String {
        #if canImport(FoundationModels)
        guard #available(macOS 27.0, *) else {
            return "Private Cloud Compute requires macOS 27."
        }
        let cloudModel = PrivateCloudComputeLanguageModel()
        guard case .available = cloudModel.availability else {
            return "Private Cloud Compute: not available on this Mac."
        }
        do {
            let session = LanguageModelSession(model: cloudModel, instructions: "Reply with the single word OK.")
            _ = try await session.respond(
                to: "OK?",
                options: GenerationOptions(maximumResponseTokens: 4)
            )
            privateCloudComputeFailedThisSession = false
            return "Private Cloud Compute: working — analyses use Apple's larger private server model."
        } catch {
            privateCloudComputeFailedThisSession = true
            return "Private Cloud Compute: not responding (beta) — analyses use the on-device model."
        }
        #else
        return "Private Cloud Compute requires an SDK with Foundation Models."
        #endif
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

    /// One retry with a different seed when the canned "Use …" opener slips
    /// through; the second draw almost always phrases differently.
    @available(macOS 26.0, *)
    private static func soundsMonotonous(_ analysis: AppleIntelligenceAppAnalysis) -> Bool {
        analysis.bestUse.hasPrefix("Use ") || analysis.bestUse.hasPrefix("Use it")
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

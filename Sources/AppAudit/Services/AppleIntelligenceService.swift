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
    /// instructions so the owner can tune phrasing without a rebuild. Shares the
    /// single source of truth with the other engines.
    private var styleNotes: String { AppAnalysisPrompt.currentStyleNotes }

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

    func analyze(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil, linkEvidence: String? = nil) async -> AnalysisResult {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            return .unavailable("Apple Intelligence requires macOS 26 or later.")
        }

        if let message = availabilityMessage() {
            return .unavailable(message)
        }

        let prompt = AppAnalysisPrompt.compactFacts(app: app, profile: profile, appURL: appURL, linkEvidence: linkEvidence)
        // Scoring is a factual task: greedy (deterministic) decoding keeps the
        // answer grounded in the supplied facts and gives the same app the same
        // score run-to-run. The @Guide schema forbids a "Use …" opener; on the
        // rare miss we re-roll once with low-temperature sampling (greedy would
        // reproduce the same text). 500 tokens leaves room so the four-field
        // answer is never truncated into a parse failure.
        let options = GenerationOptions(
            samplingMode: .greedy,
            maximumResponseTokens: 500
        )
        let retryOptions = GenerationOptions(
            samplingMode: .random(probabilityThreshold: 0.9, seed: 137),
            temperature: 0.4,
            maximumResponseTokens: 500
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

        // Permissive content guardrails: the default guardrails block a large
        // share of benign prompts (security tools, networking apps, etc.),
        // returning blank or degraded analyses. This is the on-device path that
        // actually runs on Macs without working Private Cloud Compute.
        let onDeviceModel = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        do {
            let analysis = try await Self.generate(
                model: onDeviceModel,
                instructions: instructionsText,
                prompt: prompt,
                options: options,
                retryOptions: retryOptions
            )
            return .success(Self.structuredText(from: analysis))
        } catch {
            return .unavailable(Self.describeGenerationError(error))
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

    /// One retry with sampling when the canned "Use …" opener slips through; the
    /// sampled draw almost always phrases differently (greedy would not).
    @available(macOS 26.0, *)
    private static func soundsMonotonous(_ analysis: AppleIntelligenceAppAnalysis) -> Bool {
        analysis.bestUse.hasPrefix("Use ") || analysis.bestUse.hasPrefix("Use it")
    }

    private enum GenerationFailure: Error { case empty }

    /// One grounded analysis: greedy first, then a single sampled re-roll if the
    /// "Use …" opener slips through. Each call is retried on transient model
    /// errors; guardrail/refusal errors propagate immediately.
    @available(macOS 26.0, *)
    private static func generate(
        model: SystemLanguageModel,
        instructions: String,
        prompt: String,
        options: GenerationOptions,
        retryOptions: GenerationOptions
    ) async throws -> AppleIntelligenceAppAnalysis {
        var analysis = try await respondWithRetry(model: model, instructions: instructions, prompt: prompt, options: options)
        if soundsMonotonous(analysis) {
            analysis = try await respondWithRetry(model: model, instructions: instructions, prompt: prompt, options: retryOptions)
        }
        return analysis
    }

    /// Retries transient failures (model busy / assets loading) and empty output
    /// with short backoff; rethrows guardrail/refusal immediately (they won't
    /// change on a retry).
    @available(macOS 26.0, *)
    private static func respondWithRetry(
        model: SystemLanguageModel,
        instructions: String,
        prompt: String,
        options: GenerationOptions
    ) async throws -> AppleIntelligenceAppAnalysis {
        let backoff: [Duration] = [.milliseconds(300), .seconds(1)]
        var attempt = 0
        while true {
            do {
                let session = LanguageModelSession(model: model, instructions: instructions)
                let analysis = try await session.respond(
                    to: prompt,
                    generating: AppleIntelligenceAppAnalysis.self,
                    options: options
                ).content
                guard !analysis.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw GenerationFailure.empty
                }
                return analysis
            } catch {
                if isNonRetryable(error) || attempt >= backoff.count {
                    throw error
                }
                try? await Task.sleep(for: backoff[attempt])
                attempt += 1
            }
        }
    }

    /// Guardrail blocks and outright refusals are deterministic — don't retry them.
    private static func isNonRetryable(_ error: Error) -> Bool {
        let d = error.localizedDescription.lowercased()
        return d.contains("guardrail") || d.contains("safety") || d.contains("unsafe")
            || d.contains("content policy") || d.contains("refus") || d.contains("declined")
    }

    /// A user-facing reason that names a safety block distinctly from a generic failure.
    private static func describeGenerationError(_ error: Error) -> String {
        if case GenerationFailure.empty = error {
            return "Apple Intelligence returned an empty analysis — try re-analyzing."
        }
        let d = error.localizedDescription.lowercased()
        if d.contains("guardrail") || d.contains("safety") || d.contains("unsafe") || d.contains("content policy") {
            return "Apple Intelligence blocked this app's analysis (content guardrail)."
        }
        if d.contains("refus") || d.contains("declined") {
            return "Apple Intelligence declined to analyze this app."
        }
        return "Apple Intelligence error: \(error.localizedDescription)"
    }

    @available(macOS 26.0, *)
    private static func describeAvailabilityReason(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is off — turn it on in System Settings › Apple Intelligence & Siri"
        case .modelNotReady:
            return "the on-device model is still downloading or preparing (~a few GB) — try again shortly"
        case .deviceNotEligible:
            return "this Mac is not eligible (Apple Intelligence needs an Apple Silicon Mac) — choose another engine in Advanced"
        @unknown default:
            return String(describing: reason)
        }
    }
    #endif
}

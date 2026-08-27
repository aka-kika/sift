import Testing
import Foundation
import SwiftData
@testable import Sift

@Suite("WorkflowProfile Tests")
struct WorkflowProfileTests {

    @Test("Custom profile text is used directly")
    func customProfileText() {
        let profile = WorkflowProfile.local(text: "SwiftUI, Codex, local-first tools")
        #expect(profile.promptDescription == "SwiftUI, Codex, local-first tools")
    }

    @Test("Blank custom profile falls back to neutral (not personal default)")
    func blankCustomProfileFallsBack() {
        let profile = WorkflowProfile.local(text: "   ")
        #expect(profile.promptDescription == WorkflowProfile.neutralProfileText.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(profile.promptDescription != WorkflowProfile.defaultProfileText)
    }
}

@Suite("AnalysisProviderKind Tests")
struct AnalysisProviderKindTests {

    @Test("Defaults to Ollama when unset or invalid")
    func defaultsToOllama() {
        let defaults = UserDefaults(suiteName: "AppAuditTests.AnalysisProviderKind.defaults")!
        defaults.removeObject(forKey: AnalysisProviderKind.storageKey)
        #expect(AnalysisProviderKind.current(userDefaults: defaults) == .ollama)

        defaults.set("unknown-provider", forKey: AnalysisProviderKind.storageKey)
        #expect(AnalysisProviderKind.current(userDefaults: defaults) == .ollama)
    }

    @Test("Provider set is Ollama plus the optional cloud providers")
    func providerCases() {
        // Personal edition: Ollama is the default and focus; Apple Intelligence
        // has been removed. Anthropic, OpenAI, Gemini and OpenRouter are optional
        // cloud providers — the last two chosen for their free tiers.
        #expect(AnalysisProviderKind.allCases.count == 5)
        #expect(Set(AnalysisProviderKind.allCases) == [.ollama, .anthropic, .openAI, .gemini, .openRouter])
        #expect(AnalysisProviderKind.ollama.defaultModel == OllamaDefaults.model)
        #expect(AnalysisProviderKind.gemini.defaultModel.hasPrefix("gemini"))
        #expect(AnalysisProviderKind.openRouter.defaultModel == "openrouter/free")
    }

    @Test("Every provider has distinct storage keys")
    func distinctKeys() {
        let modelKeys = AnalysisProviderKind.allCases.map(\.modelDefaultsKey)
        let apiKeys = AnalysisProviderKind.allCases.map(\.apiKeyDefaultsKey)
        #expect(Set(modelKeys).count == modelKeys.count)
        #expect(Set(apiKeys).count == apiKeys.count)
        #expect(Set(modelKeys).isDisjoint(with: apiKeys))
    }

    @Test("Builds stable cache identifiers per provider and model")
    func modelIdentifiers() {
        let defaults = UserDefaults(suiteName: "AppAuditTests.AnalysisProviderKind.models")!
        defaults.removeObject(forKey: "ollamaModel")
        defaults.removeObject(forKey: "anthropicModel")
        defaults.removeObject(forKey: "openAIModel")

        #expect(AnalysisProviderKind.ollama.modelIdentifier(userDefaults: defaults) == "ollama:\(OllamaDefaults.model)")
        #expect(AnalysisProviderKind.anthropic.modelIdentifier(userDefaults: defaults) == "anthropic:claude-3-5-haiku-latest")
        #expect(AnalysisProviderKind.openAI.modelIdentifier(userDefaults: defaults) == "openAI:gpt-4o-mini")

        defaults.set("mistral", forKey: "ollamaModel")
        defaults.set("gpt-4o", forKey: "openAIModel")
        #expect(AnalysisProviderKind.ollama.modelIdentifier(userDefaults: defaults) == "ollama:mistral")
        #expect(AnalysisProviderKind.openAI.modelIdentifier(userDefaults: defaults) == "openAI:gpt-4o")
    }
}

@Suite("AppInfo Tests")
struct AppInfoTests {

    @Test("AIState score returns correct value when loaded")
    func aiStateScoreLoaded() {
        let state = AppInfo.AIState.loaded(explanation: "Test", score: 4, reason: "Good", bestUse: "Use it")
        #expect(state.score == 4)
    }

    @Test("AIState score returns nil when pending")
    func aiStateScorePending() {
        let state = AppInfo.AIState.pending
        #expect(state.score == nil)
    }

    @Test("AIState score returns nil when unavailable")
    func aiStateScoreUnavailable() {
        let state = AppInfo.AIState.unavailable("error")
        #expect(state.score == nil)
    }

    @Test("Link-help callout shows only for weak, unlinked, unlocked analyses")
    func needsLinkHelp() {
        #expect(AppInfo.needsLinkHelp(score: 2, hasAppURL: false, isLocked: false))
        #expect(AppInfo.needsLinkHelp(score: 1, hasAppURL: false, isLocked: false))
        #expect(!AppInfo.needsLinkHelp(score: 3, hasAppURL: false, isLocked: false))
        #expect(!AppInfo.needsLinkHelp(score: 2, hasAppURL: true, isLocked: false))
        #expect(!AppInfo.needsLinkHelp(score: 2, hasAppURL: false, isLocked: true))
    }
}

@Suite("Analysis Lock Tests")
struct AnalysisLockTests {

    @Test("Locked records are not considered stale")
    @MainActor
    func lockedRecordIsNotStale() throws {
        let container = try ModelContainer(
            for: AppRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let cache = CacheService(context: context)
        let record = AppRecord(
            bundleID: "com.example.locked",
            appName: "Locked",
            explanation: "Keep this",
            relevanceScore: 4,
            relevanceReason: "Useful",
            bestUse: "Use it",
            ollamaModel: "ollama:old"
        )
        record.isAnalysisLocked = true

        context.insert(record)

        #expect(!cache.isStale(record, currentModel: "apple-intelligence:foundation-models", currentAppURL: "https://example.com/locked"))
    }

    @Test("Save does not overwrite locked analysis")
    @MainActor
    func savePreservesLockedAnalysis() throws {
        let container = try ModelContainer(
            for: AppRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let cache = CacheService(context: context)
        let record = AppRecord(
            bundleID: "com.example.locked",
            appName: "Locked",
            explanation: "Original",
            relevanceScore: 5,
            relevanceReason: "Original reason",
            bestUse: "Original use",
            ollamaModel: "ollama:old"
        )
        record.isAnalysisLocked = true
        context.insert(record)

        cache.save(
            bundleID: "com.example.locked",
            appName: "Locked",
            explanation: "New",
            score: 1,
            reason: "New reason",
            bestUse: "New use",
            ollamaModel: "apple-intelligence:foundation-models"
        )

        #expect(record.explanation == "Original")
        #expect(record.relevanceScore == 5)
        #expect(record.ollamaModel == "ollama:old")
    }

    @Test("Changing app link makes cached analysis stale")
    @MainActor
    func changingAppLinkMakesCachedAnalysisStale() throws {
        let container = try ModelContainer(
            for: AppRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let cache = CacheService(context: context)
        let record = AppRecord(
            bundleID: "com.example.linked",
            appName: "Linked",
            explanation: "Old",
            relevanceScore: 3,
            relevanceReason: "Old reason",
            bestUse: "Old use",
            ollamaModel: "ollama:llama3.2"
        )
        record.analysisAppURL = nil
        context.insert(record)

        #expect(cache.isStale(record, currentModel: "ollama:llama3.2", currentAppURL: "https://example.com/linked"))
    }

    @Test("Save records app link used for analysis")
    @MainActor
    func saveRecordsAppLinkUsedForAnalysis() throws {
        let container = try ModelContainer(
            for: AppRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let cache = CacheService(context: context)

        cache.save(
            bundleID: "com.example.linked",
            appName: "Linked",
            explanation: "New",
            score: 4,
            reason: "New reason",
            bestUse: "New use",
            ollamaModel: "ollama:llama3.2",
            analysisAppURL: "  https://example.com/linked  "
        )

        let record = cache.load(bundleID: "com.example.linked")
        #expect(record?.analysisAppURL == "https://example.com/linked")
        #expect(!cache.isStale(record!, currentModel: "ollama:llama3.2", currentAppURL: "https://example.com/linked"))
    }

    @Test("Changing the model alone does not make analysis stale")
    @MainActor
    func modelChangeDoesNotMakeAnalysisStale() throws {
        let container = try ModelContainer(
            for: AppRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let cache = CacheService(context: context)
        let record = AppRecord(
            bundleID: "com.example.model",
            appName: "Model",
            explanation: "Existing analysis",
            relevanceScore: 4,
            relevanceReason: "Reason",
            bestUse: "Use",
            ollamaModel: "ollama:llama3.2"
        )
        record.analysisAppURL = "https://example.com/model"
        context.insert(record)

        // Different model, same link -> NOT stale (we no longer auto-wipe on model change).
        #expect(!cache.isStale(record, currentModel: "ollama:mistral", currentAppURL: "https://example.com/model"))
        // ...but the drift is detectable so the UI can offer a re-analyze.
        #expect(cache.wasAnalyzedWithDifferentModel(record, currentModel: "ollama:mistral"))
        #expect(!cache.wasAnalyzedWithDifferentModel(record, currentModel: "ollama:llama3.2"))
    }

    @Test("Model drift is ignored for locked or empty analyses")
    @MainActor
    func modelDriftIgnoredForLockedOrEmpty() throws {
        let container = try ModelContainer(
            for: AppRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let cache = CacheService(context: container.mainContext)

        let locked = AppRecord(
            bundleID: "com.example.locked", appName: "Locked",
            explanation: "Analysis", relevanceScore: 5, relevanceReason: "r",
            bestUse: "u", ollamaModel: "ollama:old"
        )
        locked.isAnalysisLocked = true
        #expect(!cache.wasAnalyzedWithDifferentModel(locked, currentModel: "ollama:new"))

        let empty = AppRecord(
            bundleID: "com.example.empty", appName: "Empty",
            explanation: "", relevanceScore: 0, relevanceReason: "",
            bestUse: "", ollamaModel: "ollama:old"
        )
        #expect(!cache.wasAnalyzedWithDifferentModel(empty, currentModel: "ollama:new"))
    }

    @Test("New records start with no suggested or approved app link")
    func newRecordsStartWithoutAppLinks() {
        let record = AppRecord(
            bundleID: "com.example.new",
            appName: "New",
            explanation: "",
            relevanceScore: 0,
            relevanceReason: "",
            bestUse: "",
            ollamaModel: ""
        )

        #expect(record.appURL == nil)
        #expect(record.suggestedAppURL == nil)
        #expect(record.analysisAppURL == nil)
    }
}

@Suite("AppAnalysisPrompt Tests")
struct AppAnalysisPromptTests {

    @Test("Prompt includes app evidence and ambiguity guardrails")
    func promptIncludesEvidenceAndGuardrails() {
        let app = AppInfo(
            id: "com.example.glyph",
            name: "Glyph",
            version: "0.3.0",
            bundleID: "com.example.glyph",
            path: "/Applications/Glyph.app",
            humanReadableDescription: nil,
            sparkleFeedURL: nil,
            isAppStoreInstall: false,
            icon: nil
        )

        let prompt = AppAnalysisPrompt.build(
            app: app,
            profile: .local(text: "SwiftUI, macOS apps"),
            appURL: nil,
            includeResponseFormat: true
        )

        #expect(prompt.contains("Path: /Applications/Glyph.app"))
        #expect(prompt.contains("Do not infer a specific product category from a generic name alone."))
        #expect(prompt.contains("Score unclear apps conservatively"))
        #expect(prompt.contains("EXPLANATION:"))
    }

    @Test("Prompt asks for short professional descriptions")
    func promptAsksForShortProfessionalDescriptions() {
        let app = AppInfo(
            id: "com.example.brief",
            name: "Brief",
            version: "1.0",
            bundleID: "com.example.brief",
            path: "/Applications/Brief.app",
            humanReadableDescription: nil,
            sparkleFeedURL: nil,
            isAppStoreInstall: false,
            icon: nil
        )

        let prompt = AppAnalysisPrompt.build(
            app: app,
            profile: .local(text: "SwiftUI, macOS apps"),
            appURL: nil,
            includeResponseFormat: true
        )

        #expect(prompt.contains("1-2 short sentences, max 35 words"))
        #expect(prompt.contains("1 short sentence, max 22 words"))
        #expect(AppAnalysisPrompt.system.contains("readable, friendly, and professional"))
    }

    @Test("Prompt includes reference URL when provided")
    func promptIncludesReferenceURL() {
        let app = AppInfo(
            id: "com.example.linked",
            name: "Linked",
            version: "1.0",
            bundleID: "com.example.linked",
            path: "/Applications/Linked.app",
            humanReadableDescription: nil,
            sparkleFeedURL: nil,
            isAppStoreInstall: false,
            icon: nil
        )

        let prompt = AppAnalysisPrompt.build(
            app: app,
            profile: .local(text: "SwiftUI, macOS apps"),
            appURL: "https://example.com/linked",
            includeResponseFormat: true
        )

        #expect(prompt.contains("Reference URL: https://example.com/linked"))
        #expect(prompt.contains("Prefer bundle ID, reference URL context"))
        #expect(prompt.contains("Host: example.com"))
        #expect(prompt.contains("Slug keywords: linked"))
        #expect(prompt.contains("Do not claim to have browsed beyond what is quoted here."))
    }

    @Test("Prompt identifies GitHub link context")
    func promptIdentifiesGitHubLinkContext() {
        let app = AppInfo(
            id: "com.example.repoapp",
            name: "Repo App",
            version: "1.0",
            bundleID: "com.example.repoapp",
            path: "/Applications/Repo App.app",
            humanReadableDescription: nil,
            sparkleFeedURL: nil,
            isAppStoreInstall: false,
            icon: nil
        )

        let prompt = AppAnalysisPrompt.build(
            app: app,
            profile: .local(text: "SwiftUI, macOS apps"),
            appURL: "https://github.com/example-owner/local-agent-tools",
            includeResponseFormat: true
        )

        #expect(prompt.contains("Source type: GitHub repository"))
        #expect(prompt.contains("Path context: example-owner / local-agent-tools"))
        #expect(prompt.contains("Slug keywords: example, owner, local, agent, tools"))
    }

    @Test("Parses markdown-wrapped labels and N/5 scores")
    func parseMarkdownAndSlashScore() async {
        let service = OllamaService()
        // Mirrors how some models (e.g. ministral) bold the labels and write 4/5.
        let response = """
        **EXPLANATION:** Open-source local LLM server.
        **SCORE:** **4/5**
        **REASON:** Local-first AI fits the workflow.
        **BEST_USE:** Host models locally and call the API from SwiftUI.
        """
        let parsed = await service.parseAnalysis(from: response)
        #expect(parsed?.score == 4)
        #expect(parsed?.explanation == "Open-source local LLM server.")
    }

    @Test("Strips <think> reasoning before the structured answer")
    func parseStripsThinking() async {
        let service = OllamaService()
        let response = """
        <think>
        SCORE: 1 — scratchpad, ignore.
        </think>
        EXPLANATION: A terminal emulator for macOS.
        SCORE: 5
        REASON: Daily driver for terminal workflows.
        BEST_USE: Keep it as the primary terminal.
        """
        let parsed = await service.parseAnalysis(from: response)
        #expect(parsed?.score == 5)
        #expect(parsed?.explanation == "A terminal emulator for macOS.")
    }
}

@Suite("LicenseKeyStore Tests")
struct LicenseKeyStoreTests {

    @Test("Saves trims and reads license keys")
    func saveTrimRead() {
        let backend = MemorySecretStoreBackend()
        let store = LicenseKeyStore(backend: backend)

        store.save("  ABC-123  ", bundleID: "com.example.app")
        let resolution = store.resolveKey(bundleID: "com.example.app", legacyValue: nil)

        #expect(resolution.value == "ABC-123")
        #expect(!resolution.didMigrateLegacyValue)
    }

    @Test("Blank save deletes the key")
    func blankSaveDeletes() {
        let backend = MemorySecretStoreBackend()
        let store = LicenseKeyStore(backend: backend)

        store.save("ABC-123", bundleID: "com.example.app")
        store.save("   ", bundleID: "com.example.app")

        #expect(store.resolveKey(bundleID: "com.example.app", legacyValue: nil).value == nil)
    }

    @Test("Legacy key migrates into secure storage")
    func legacyKeyMigrates() {
        let backend = MemorySecretStoreBackend()
        let store = LicenseKeyStore(backend: backend)

        let resolution = store.resolveKey(bundleID: "com.example.app", legacyValue: " OLD-KEY ")

        #expect(resolution.value == "OLD-KEY")
        #expect(resolution.didMigrateLegacyValue)
        #expect(backend.read(account: "com.example.app") == "OLD-KEY")
    }

    @Test("hasKey reflects stored keys for the License Vault")
    func hasKeyReflectsStoredKeys() {
        let backend = MemorySecretStoreBackend()
        let store = LicenseKeyStore(backend: backend)

        #expect(!store.hasKey(bundleID: "com.example.app"))

        store.save("ABC-123", bundleID: "com.example.app")
        #expect(store.hasKey(bundleID: "com.example.app"))

        store.delete(bundleID: "com.example.app")
        #expect(!store.hasKey(bundleID: "com.example.app"))
    }

    @Test("Legacy plaintext key migrates only when no secure key exists")
    func migrateLegacyKeyBehavior() {
        let backend = MemorySecretStoreBackend()
        let store = LicenseKeyStore(backend: backend)

        // No existing key: legacy value is moved into secure storage.
        #expect(store.migrateLegacyKey("  LEGACY  ", bundleID: "com.example.app"))
        #expect(backend.read(account: "com.example.app") == "LEGACY")

        // Existing secure key is never overwritten by a legacy value.
        store.save("SECURE", bundleID: "com.example.other")
        #expect(store.migrateLegacyKey("LEGACY", bundleID: "com.example.other"))
        #expect(backend.read(account: "com.example.other") == "SECURE")

        // Empty legacy value with no stored key: nothing to migrate.
        #expect(!store.migrateLegacyKey("   ", bundleID: "com.example.empty"))
        #expect(!store.hasKey(bundleID: "com.example.empty"))
    }
}

@Suite("CSVExporter Tests")
struct CSVExporterTests {

    @Test("Fields are quoted only when they contain special characters")
    func fieldQuoting() {
        #expect(CSVExporter.field("plain") == "plain")
        #expect(CSVExporter.field("has,comma") == "\"has,comma\"")
        #expect(CSVExporter.field("has \"quote\"") == "\"has \"\"quote\"\"\"")
        #expect(CSVExporter.field("line1\nline2") == "\"line1\nline2\"")
    }

    @Test("CSV joins header and rows with CRLF and a trailing newline")
    func makeStructure() {
        let csv = CSVExporter.make(
            header: ["Name", "Notes"],
            rows: [["Mole", "great, app"], ["Eagle", "plain"]]
        )
        #expect(csv == "Name,Notes\r\nMole,\"great, app\"\r\nEagle,plain\r\n")
    }
}

@Suite("UpdateChecker Tests")
struct UpdateCheckerTests {

    @Test("Numeric version comparison treats newer semantic version as update")
    func comparesSemanticVersions() {
        #expect(UpdateChecker.isVersion("1.10", newerThan: "1.9"))
        #expect(UpdateChecker.isVersion("2.0", newerThan: "1.9.9"))
        #expect(!UpdateChecker.isVersion("1.0", newerThan: "1.0"))
        #expect(!UpdateChecker.isVersion("1.0", newerThan: "1.0.1"))
    }

    @Test("Parses App Store lookup version and URL")
    func parsesAppStoreLookupMetadata() throws {
        let data = Data("""
        {
          "resultCount": 1,
          "results": [
            {
              "bundleId": "com.example.MyApp",
              "trackId": 123456789,
              "version": "3.4.1",
              "trackViewUrl": "https://apps.apple.com/app/id123456789"
            }
          ]
        }
        """.utf8)

        let metadata = try UpdateChecker.parseAppStoreMetadata(from: data, preferredBundleID: "com.example.MyApp")
        #expect(metadata?.version == "3.4.1")
        #expect(metadata?.url == "macappstore://itunes.apple.com/app/id123456789")
    }

    @Test("Parses newest Sparkle version from appcast")
    func parsesSparkleAppcastVersion() throws {
        let data = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <item>
              <enclosure url="https://example.com/download-1.2.zip" sparkle:shortVersionString="1.2" sparkle:version="12" />
            </item>
            <item>
              <enclosure url="https://example.com/download-1.10.zip" sparkle:shortVersionString="1.10" sparkle:version="110" />
            </item>
          </channel>
        </rss>
        """.utf8)

        let metadata = try UpdateChecker.parseSparkleMetadata(from: data)
        #expect(metadata?.version == "1.10")
        #expect(metadata?.url == "https://example.com/download-1.10.zip")
    }

    @Test("Parses Homebrew outdated cask metadata")
    func parsesHomebrewOutdatedCasks() throws {
        let data = Data("""
        {
          "casks": [
            {
              "name": "betterdisplay",
              "installed_versions": ["4.3.0"],
              "current_version": "4.4.0"
            }
          ]
        }
        """.utf8)

        let casks = HomebrewService.parseOutdatedCasks(from: data)
        #expect(casks == [
            HomebrewCaskInfo(token: "betterdisplay", latestVersion: "4.4.0")
        ])
    }

    @Test("Parses Homebrew Caskroom path token")
    func parsesHomebrewCaskroomToken() throws {
        let token = HomebrewService.caskTokenFromCaskroomPath("/opt/homebrew/Caskroom/betterdisplay/4.3.0/BetterDisplay.app")

        #expect(token == "betterdisplay")
    }

    @Test("Acknowledging an update immediately changes in-memory state")
    @MainActor
    func acknowledgingUpdateChangesState() throws {
        let container = try ModelContainer(
            for: AppRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let viewModel = AppListViewModel()
        viewModel.cacheService = CacheService(context: context)
        viewModel.apps = [
            AppInfo(
                id: "com.example.myapp",
                name: "MyApp",
                version: "1.0",
                bundleID: "com.example.myapp",
                path: "/Applications/MyApp.app",
                humanReadableDescription: nil,
                sparkleFeedURL: "https://example.com/appcast.xml",
                isAppStoreInstall: false,
                icon: nil,
                updateState: .updateAvailable(latestVersion: "2.0", source: .sparkle, actionURL: "https://example.com/download.zip")
            )
        ]

        viewModel.acknowledgeUpdate(
            bundleID: "com.example.myapp",
            updateState: .updateAvailable(latestVersion: "2.0", source: .sparkle, actionURL: "https://example.com/download.zip")
        )

        #expect(viewModel.apps.first?.updateState == .upToDate(source: .sparkle))
        #expect(viewModel.cacheService?.load(bundleID: "com.example.myapp")?.acknowledgedUpdateVersion == "2.0")
    }

    @Test("Available update count ignores non-actionable states")
    @MainActor
    func availableUpdateCountIgnoresNonActionableStates() {
        let viewModel = AppListViewModel()
        viewModel.apps = [
            AppInfo(
                id: "com.example.one",
                name: "One",
                version: "1.0",
                bundleID: "com.example.one",
                path: "/Applications/One.app",
                humanReadableDescription: nil,
                sparkleFeedURL: nil,
                isAppStoreInstall: false,
                icon: nil,
                updateState: .updateAvailable(latestVersion: "2.0", source: .sparkle, actionURL: nil)
            ),
            AppInfo(
                id: "com.example.two",
                name: "Two",
                version: "1.0",
                bundleID: "com.example.two",
                path: "/Applications/Two.app",
                humanReadableDescription: nil,
                sparkleFeedURL: nil,
                isAppStoreInstall: false,
                icon: nil,
                updateState: .upToDate(source: .appStore)
            ),
            AppInfo(
                id: "com.example.three",
                name: "Three",
                version: "1.0",
                bundleID: "com.example.three",
                path: "/Applications/Three.app",
                humanReadableDescription: nil,
                sparkleFeedURL: nil,
                isAppStoreInstall: false,
                icon: nil,
                updateState: .checking
            )
        ]

        #expect(viewModel.availableUpdateCount == 1)
    }

    @Test("Updates filter keeps checking rows visible")
    @MainActor
    func updatesFilterKeepsCheckingRowsVisible() {
        let viewModel = AppListViewModel()
        viewModel.sortOrder = .updates
        viewModel.apps = [
            AppInfo(
                id: "com.example.checking",
                name: "Checking",
                version: "1.0",
                bundleID: "com.example.checking",
                path: "/Applications/Checking.app",
                humanReadableDescription: nil,
                sparkleFeedURL: "https://example.com/appcast.xml",
                isAppStoreInstall: false,
                icon: nil,
                updateState: .checking
            ),
            AppInfo(
                id: "com.example.current",
                name: "Current",
                version: "1.0",
                bundleID: "com.example.current",
                path: "/Applications/Current.app",
                humanReadableDescription: nil,
                sparkleFeedURL: "https://example.com/appcast.xml",
                isAppStoreInstall: false,
                icon: nil,
                updateState: .upToDate(source: .sparkle)
            )
        ]

        #expect(viewModel.filteredApps.map(\.id) == ["com.example.checking"])
    }

    @Test("Showing available updates selects the first update row")
    @MainActor
    func showAvailableUpdatesSelectsFirstUpdateRow() {
        let viewModel = AppListViewModel()
        viewModel.apps = [
            AppInfo(
                id: "com.example.zed",
                name: "Zed",
                version: "1.0",
                bundleID: "com.example.zed",
                path: "/Applications/Zed.app",
                humanReadableDescription: nil,
                sparkleFeedURL: nil,
                isAppStoreInstall: false,
                icon: nil,
                updateState: .updateAvailable(latestVersion: "2.0", source: .sparkle, actionURL: nil)
            ),
            AppInfo(
                id: "com.example.alpha",
                name: "Alpha",
                version: "1.0",
                bundleID: "com.example.alpha",
                path: "/Applications/Alpha.app",
                humanReadableDescription: nil,
                sparkleFeedURL: nil,
                isAppStoreInstall: false,
                icon: nil,
                updateState: .updateAvailable(latestVersion: "2.0", source: .appStore, actionURL: nil)
            ),
            AppInfo(
                id: "com.example.other",
                name: "Other",
                version: "1.0",
                bundleID: "com.example.other",
                path: "/Applications/Other.app",
                humanReadableDescription: nil,
                sparkleFeedURL: nil,
                isAppStoreInstall: false,
                icon: nil,
                updateState: .upToDate(source: .sparkle)
            )
        ]
        viewModel.searchText = "nothing matches this"

        viewModel.showAvailableUpdates()

        #expect(viewModel.searchText.isEmpty)
        #expect(viewModel.sortOrder == .updates)
        #expect(viewModel.selectedAppID == "com.example.alpha")
    }

    @Test("Changing filters moves hidden selection to first visible app")
    @MainActor
    func changingFiltersMovesHiddenSelectionToFirstVisibleApp() {
        let viewModel = AppListViewModel()
        viewModel.apps = [
            AppInfo(
                id: "com.example.alpha",
                name: "Alpha",
                version: "1.0",
                bundleID: "com.example.alpha",
                path: "/Applications/Alpha.app",
                humanReadableDescription: nil,
                sparkleFeedURL: nil,
                isAppStoreInstall: false,
                icon: nil,
                updateState: .updateAvailable(latestVersion: "2.0", source: .appStore, actionURL: nil)
            ),
            AppInfo(
                id: "com.example.zed",
                name: "Zed",
                version: "1.0",
                bundleID: "com.example.zed",
                path: "/Applications/Zed.app",
                humanReadableDescription: nil,
                sparkleFeedURL: nil,
                isAppStoreInstall: false,
                icon: nil,
                updateState: .upToDate(source: .sparkle)
            )
        ]
        viewModel.selectedAppID = "com.example.zed"

        viewModel.setSortOrder(.updates)

        #expect(viewModel.selectedAppID == "com.example.alpha")
    }

    @Test("Filter with no visible apps clears selection")
    @MainActor
    func filterWithNoVisibleAppsClearsSelection() {
        let viewModel = AppListViewModel()
        viewModel.apps = [
            AppInfo(
                id: "com.example.alpha",
                name: "Alpha",
                version: "1.0",
                bundleID: "com.example.alpha",
                path: "/Applications/Alpha.app",
                humanReadableDescription: nil,
                sparkleFeedURL: nil,
                isAppStoreInstall: false,
                icon: nil
            )
        ]
        viewModel.selectedAppID = "com.example.alpha"

        viewModel.setSearchText("missing")

        #expect(viewModel.selectedAppID == nil)
    }

    @Test("Sidebar empty state reports search misses before filter misses")
    @MainActor
    func sidebarEmptyStateReportsSearchMissesBeforeFilterMisses() {
        let viewModel = AppListViewModel()
        viewModel.apps = [
            AppInfo(
                id: "com.example.alpha",
                name: "Alpha",
                version: "1.0",
                bundleID: "com.example.alpha",
                path: "/Applications/Alpha.app",
                humanReadableDescription: nil,
                sparkleFeedURL: nil,
                isAppStoreInstall: false,
                icon: nil,
                updateState: .upToDate(source: .sparkle)
            )
        ]

        viewModel.setSortOrder(.updates)
        viewModel.setSearchText("missing")

        #expect(viewModel.sidebarEmptyState == .noResults)
    }

    @Test("Sidebar empty state reports no updates")
    @MainActor
    func sidebarEmptyStateReportsNoUpdates() {
        let viewModel = AppListViewModel()
        viewModel.apps = [
            AppInfo(
                id: "com.example.alpha",
                name: "Alpha",
                version: "1.0",
                bundleID: "com.example.alpha",
                path: "/Applications/Alpha.app",
                humanReadableDescription: nil,
                sparkleFeedURL: nil,
                isAppStoreInstall: false,
                icon: nil,
                updateState: .upToDate(source: .sparkle)
            )
        ]

        viewModel.setSortOrder(.updates)

        #expect(viewModel.sidebarEmptyState == .noUpdates)
    }
}

@Suite("AppLinkResolver Tests")
struct AppLinkResolverTests {

    @Test("Parses preferred App Store link from lookup response")
    func parsesAppStoreLink() throws {
        let data = Data("""
        {
          "resultCount": 2,
          "results": [
            {
              "bundleId": "com.example.Other",
              "trackViewUrl": "https://apps.apple.com/app/other/id111"
            },
            {
              "bundleId": "com.example.MyApp",
              "trackViewUrl": "https://apps.apple.com/app/myapp/id222"
            }
          ]
        }
        """.utf8)

        let url = try AppLinkResolver.parseAppStoreLink(from: data, preferredBundleID: "com.example.MyApp")
        #expect(url == "https://apps.apple.com/app/myapp/id222")
    }

    @Test("Parses Sparkle channel website")
    func parsesSparkleWebsite() throws {
        let data = Data("""
        <rss>
          <channel>
            <title>Example App</title>
            <link>https://example.com/app</link>
            <item>
              <link>https://example.com/app/release-notes</link>
            </item>
          </channel>
        </rss>
        """.utf8)

        let url = try AppLinkResolver.parseSparkleWebsite(
            from: data,
            feedURL: URL(string: "https://updates.example.com/appcast.xml")!
        )

        #expect(url == "https://example.com/app")
    }

    @Test("Falls back to Sparkle feed host when website is missing")
    func sparkleHostFallback() throws {
        let data = Data("<rss><channel><title>No Link</title></channel></rss>".utf8)

        let url = try AppLinkResolver.parseSparkleWebsite(
            from: data,
            feedURL: URL(string: "https://updates.example.com/appcast.xml")!
        )

        #expect(url == "https://updates.example.com")
    }

}

@Suite("Grounded Profile Tests")
struct GroundedProfileTests {

    private func app(_ name: String, category: String? = nil, lastUsed: Date? = nil, running: Bool = false) -> AppInfo {
        AppInfo(
            id: "com.test.\(name)", name: name, version: "1.0",
            bundleID: "com.test.\(name)", path: "/Applications/\(name).app",
            humanReadableDescription: nil, sparkleFeedURL: nil,
            isAppStoreInstall: false, icon: nil,
            category: category, lastUsedDate: lastUsed, isRunning: running
        )
    }

    @Test("Category raw values map to readable names")
    func categoryNames() {
        #expect(AppCategory.humanName(for: "public.app-category.developer-tools") == "Developer Tools")
        #expect(AppCategory.humanName(for: "public.app-category.productivity") == "Productivity")
        #expect(AppCategory.humanName(for: "com.example.custom") == nil)
        #expect(AppCategory.humanName(for: nil) == nil)
    }

    @Test("Digest counts categories, lists recent and running apps")
    func digestContents() {
        let now = Date()
        let apps = [
            app("Xcode", category: "public.app-category.developer-tools", lastUsed: now, running: true),
            app("Ghostty", category: "public.app-category.developer-tools", lastUsed: now.addingTimeInterval(-60)),
            app("Figma", category: "public.app-category.graphics-design", lastUsed: now.addingTimeInterval(-120)),
            app("Mystery"),
        ]
        let digest = WorkflowDigest.build(from: apps)
        #expect(digest.contains("Installed apps: 4."))
        #expect(digest.contains("Developer Tools (2)"))
        #expect(digest.contains("Graphics Design (1)"))
        #expect(digest.contains("other (1)"))
        #expect(digest.contains("Most recently used: Xcode, Ghostty, Figma."))
        #expect(digest.contains("Open right now: Xcode."))
    }

    @Test("Digest of no apps is empty")
    func digestEmpty() {
        #expect(WorkflowDigest.build(from: []) == "")
    }

    @Test("Profile resolution: custom override beats digest beats neutral")
    func profileResolution() {
        let defaults = UserDefaults(suiteName: "AppAuditTests.GroundedProfile")!
        defaults.set("my custom workflow", forKey: WorkflowProfile.storageKey)
        #expect(WorkflowProfile.current(digest: "digest text", userDefaults: defaults).promptDescription == "my custom workflow")

        defaults.removeObject(forKey: WorkflowProfile.storageKey)
        #expect(WorkflowProfile.current(digest: "digest text", userDefaults: defaults).promptDescription == "digest text")
        #expect(WorkflowProfile.current(digest: "", userDefaults: defaults).promptDescription
            == WorkflowProfile.neutralProfileText.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

@Suite("LinkEvidence Tests")
struct LinkEvidenceTests {

    @Test("Extracts title and meta description")
    func extractsTitleAndDescription() {
        let html = """
        <html><head><title>Mole — Clean up your Mac</title>
        <meta name="description" content="A lightweight Mac cleaner &amp; uninstaller.">
        </head><body></body></html>
        """
        let evidence = LinkEvidence.extract(fromHTML: html)
        #expect(evidence?.contains("Title: Mole — Clean up your Mac") == true)
        #expect(evidence?.contains("Description: A lightweight Mac cleaner & uninstaller.") == true)
    }

    @Test("Falls back to og:description and handles attribute order")
    func ogDescriptionFallback() {
        let html = """
        <head><meta content="Plant trees while you focus." property="og:description"><title>Bloom</title></head>
        """
        let evidence = LinkEvidence.extract(fromHTML: html)
        #expect(evidence?.contains("Title: Bloom") == true)
        #expect(evidence?.contains("Description: Plant trees while you focus.") == true)
    }

    @Test("No title or description yields nil")
    func emptyYieldsNil() {
        #expect(LinkEvidence.extract(fromHTML: "<html><body>hi</body></html>") == nil)
    }
}

final class MemorySecretStoreBackend: SecretStoreBackend, @unchecked Sendable {
    private var values: [String: String] = [:]

    func read(account: String) -> String? {
        values[account]
    }

    @discardableResult
    func write(_ value: String, account: String) -> Bool {
        values[account] = value
        return true
    }

    func delete(account: String) {
        values.removeValue(forKey: account)
    }
}

@Suite("Subscription Math")
struct SubscriptionMathTests {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test("Future renewal is returned unchanged")
    func futureUnchanged() {
        let stored = day(2026, 7, 1)
        let next = SubscriptionMath.nextRenewal(from: stored, cycle: .monthly, now: day(2026, 6, 13), calendar: utc)
        #expect(next == stored)
    }

    @Test("Today's renewal is returned unchanged")
    func todayUnchanged() {
        let stored = day(2026, 6, 13)
        let next = SubscriptionMath.nextRenewal(from: stored, cycle: .monthly, now: day(2026, 6, 13), calendar: utc)
        #expect(next == stored)
    }

    @Test("Past monthly rolls forward to the first future month")
    func pastMonthlyRolls() {
        let next = SubscriptionMath.nextRenewal(from: day(2026, 1, 10), cycle: .monthly, now: day(2026, 6, 13), calendar: utc)
        #expect(next == day(2026, 7, 10))
    }

    @Test("Past yearly rolls forward to the first future year")
    func pastYearlyRolls() {
        let next = SubscriptionMath.nextRenewal(from: day(2024, 3, 1), cycle: .yearly, now: day(2026, 6, 13), calendar: utc)
        #expect(next == day(2027, 3, 1))
    }

    @Test("daysUntil counts calendar days")
    func daysUntil() {
        #expect(SubscriptionMath.daysUntil(day(2026, 6, 20), now: day(2026, 6, 13), calendar: utc) == 7)
    }

    @Test("Countdown copy")
    func countdownCopy() {
        #expect(SubscriptionMath.countdownText(daysUntil: 0) == "renews today")
        #expect(SubscriptionMath.countdownText(daysUntil: 1) == "renews tomorrow")
        #expect(SubscriptionMath.countdownText(daysUntil: 5) == "renews in 5 days")
        #expect(SubscriptionMath.countdownText(daysUntil: -1) == "overdue")
    }

    @Test("Near threshold is 0...7 inclusive")
    func nearThreshold() {
        #expect(SubscriptionMath.isNear(daysUntil: 0))
        #expect(SubscriptionMath.isNear(daysUntil: 7))
        #expect(!SubscriptionMath.isNear(daysUntil: 8))
        #expect(!SubscriptionMath.isNear(daysUntil: -1))
    }

    @Test("isoDate formats yyyy-MM-dd")
    func iso() {
        #expect(SubscriptionMath.isoDate(day(2026, 6, 13), calendar: utc) == "2026-06-13")
    }

    @Test("BillingCycle round-trips its rawValue")
    func cycleRawValue() {
        #expect(BillingCycle(rawValue: "monthly") == .monthly)
        #expect(BillingCycle(rawValue: "yearly") == .yearly)
        #expect(BillingCycle(rawValue: "garbage") == nil)
        #expect(BillingCycle.monthly.abbreviation == "mo")
        #expect(BillingCycle.yearly.abbreviation == "yr")
    }
}

@Suite("AppRecord Subscription Fields")
struct AppRecordSubscriptionTests {
    @Test("A new record has empty subscription fields")
    func defaults() {
        let r = AppRecord(bundleID: "com.x", appName: "X", explanation: "",
                          relevanceScore: 0, relevanceReason: "", bestUse: "", ollamaModel: "")
        #expect(r.hasSubscription == false)
        #expect(r.subscriptionPrice == nil)
        #expect(r.subscriptionCurrency == nil)
        #expect(r.subscriptionCycle == nil)
        #expect(r.subscriptionRenewalDate == nil)
        #expect(r.subscriptionEmail == nil)
    }
}

@Suite("Install Source Label")
struct InstallSourceLabelTests {
    private func make(appStore: Bool, sparkle: String?, cask: String?) -> AppInfo {
        AppInfo(
            id: "com.x", name: "X", version: "1", bundleID: "com.x",
            path: "/Applications/X.app", humanReadableDescription: nil,
            sparkleFeedURL: sparkle, isAppStoreInstall: appStore,
            homebrewCaskToken: cask, icon: nil
        )
    }

    @Test("App Store wins over other signals")
    func appStoreWins() {
        #expect(make(appStore: true, sparkle: "https://feed", cask: "x").installSourceLabel == "App Store")
    }

    @Test("Sparkle when only a feed URL")
    func sparkle() {
        #expect(make(appStore: false, sparkle: "https://feed", cask: nil).installSourceLabel == "Sparkle")
    }

    @Test("Homebrew when only a cask token")
    func homebrew() {
        #expect(make(appStore: false, sparkle: nil, cask: "the-cask").installSourceLabel == "Homebrew")
    }

    @Test("Other when no signal")
    func other() {
        #expect(make(appStore: false, sparkle: nil, cask: nil).installSourceLabel == "Other")
    }
}

@Suite("AppRecord Paid Flag")
struct AppRecordPaidTests {
    @Test("A new record is not marked paid")
    func defaultsFalse() {
        let r = AppRecord(bundleID: "com.x", appName: "X", explanation: "",
                          relevanceScore: 0, relevanceReason: "", bestUse: "", ollamaModel: "")
        #expect(r.isPaidApp == false)
    }
}

@MainActor
@Suite("CSV Source and Paid Columns")
struct CSVSourceColumnsTests {
    @Test("Header includes Source and Paid before Notes; Source reflects install origin")
    func sourceAndPaidColumns() {
        let vm = AppListViewModel()
        vm.apps = [
            AppInfo(id: "a", name: "AStore", version: "1", bundleID: "a",
                    path: "/Applications/AStore.app", humanReadableDescription: nil,
                    sparkleFeedURL: nil, isAppStoreInstall: true, icon: nil),
            AppInfo(id: "b", name: "Brew", version: "1", bundleID: "b",
                    path: "/Applications/Brew.app", humanReadableDescription: nil,
                    sparkleFeedURL: nil, isAppStoreInstall: false,
                    homebrewCaskToken: "brew-cask", icon: nil)
        ]
        let csv = vm.exportCSV()
        let lines = csv.split(separator: "\r\n", omittingEmptySubsequences: false)
        // Header: Source and Paid immediately before Notes
        #expect(lines[0].contains("Source,Paid,Notes"))
        // AStore row → App Store; Brew row → Homebrew; Paid blank (no record)
        #expect(csv.contains("App Store"))
        #expect(csv.contains("Homebrew"))
    }
}

@Suite("Analysis Prompt Style Notes")
struct AnalysisPromptStyleNotesTests {
    private var app: AppInfo {
        AppInfo(id: "com.x", name: "X", version: "1", bundleID: "com.x",
                path: "/Applications/X.app", humanReadableDescription: nil,
                sparkleFeedURL: nil, isAppStoreInstall: false, icon: nil)
    }

    @Test("Style notes are appended when provided")
    func appended() {
        let prompt = AppAnalysisPrompt.build(app: app, profile: .local(text: nil),
                                             includeResponseFormat: false,
                                             styleNotes: "Mention alternatives.")
        #expect(prompt.contains("Additional style notes from the user (follow them):"))
        #expect(prompt.contains("Mention alternatives."))
    }

    @Test("No style block when notes are empty or whitespace")
    func emptyOmits() {
        let prompt = AppAnalysisPrompt.build(app: app, profile: .local(text: nil),
                                             includeResponseFormat: false,
                                             styleNotes: "   ")
        #expect(!prompt.contains("Additional style notes"))
    }
}

@Suite("Analysis Prompt User Notes")
struct AnalysisPromptUserNotesTests {
    private var app: AppInfo {
        AppInfo(id: "com.x", name: "X", version: "1", bundleID: "com.x",
                path: "/Applications/X.app", humanReadableDescription: nil,
                sparkleFeedURL: nil, isAppStoreInstall: false, icon: nil)
    }

    @Test("User notes appear as strongest personal-usage evidence")
    func notesIncluded() {
        let prompt = AppAnalysisPrompt.build(app: app, profile: .local(text: nil),
                                             includeResponseFormat: true,
                                             userNotes: "I use this daily to cut release videos.")
        #expect(prompt.contains("The user's own notes about this app"))
        #expect(prompt.contains("I use this daily to cut release videos."))
        #expect(prompt.contains("The user's own notes outrank URL and metadata evidence"))
    }

    @Test("No notes block when notes are empty or whitespace")
    func emptyOmits() {
        let empty = AppAnalysisPrompt.build(app: app, profile: .local(text: nil),
                                            includeResponseFormat: true)
        let whitespace = AppAnalysisPrompt.build(app: app, profile: .local(text: nil),
                                                 includeResponseFormat: true,
                                                 userNotes: "  \n ")
        #expect(!empty.contains("The user's own notes"))
        #expect(!whitespace.contains("The user's own notes"))
        #expect(empty == whitespace)
    }

    @Test("Notes coexist with style notes without collision")
    func coexistsWithStyleNotes() {
        let prompt = AppAnalysisPrompt.build(app: app, profile: .local(text: nil),
                                             includeResponseFormat: false,
                                             styleNotes: "Mention alternatives.",
                                             userNotes: "Learning this app's features.")
        #expect(prompt.contains("Learning this app's features."))
        #expect(prompt.contains("Mention alternatives."))
    }
}

@Suite("Notes Change Detection")
struct NotesChangeDetectionTests {
    @Test("Different text is a change")
    func differentText() {
        #expect(NotesChange.changed(previous: "old", current: "new"))
        #expect(NotesChange.changed(previous: nil, current: "new note"))
        #expect(NotesChange.changed(previous: "had a note", current: nil))
    }

    @Test("Nil, empty, and whitespace are all 'no note' — not a change")
    func noNoteEquivalence() {
        #expect(!NotesChange.changed(previous: nil, current: ""))
        #expect(!NotesChange.changed(previous: "", current: "   \n"))
        #expect(!NotesChange.changed(previous: nil, current: nil))
    }

    @Test("Whitespace-only edits are not a change")
    func whitespaceEditsIgnored() {
        #expect(!NotesChange.changed(previous: "same note", current: "same note  \n"))
        #expect(!NotesChange.changed(previous: " same note", current: "same note"))
    }
}

@Suite("License Type")
struct LicenseTypeTests {
    @Test("Raw values round-trip")
    func rawValues() {
        #expect(LicenseType(rawValue: "lifetime") == .lifetime)
        #expect(LicenseType(rawValue: "one-time") == .oneTime)
        #expect(LicenseType(rawValue: "annual") == .annual)
        #expect(LicenseType(rawValue: "other") == .other)
        #expect(LicenseType(rawValue: "bogus") == nil)
    }

    @Test("Lifetime and one-time cover the app forever; annual and other do not")
    func coversForever() {
        #expect(LicenseType.lifetime.coversForever)
        #expect(LicenseType.oneTime.coversForever)
        #expect(!LicenseType.annual.coversForever)
        #expect(!LicenseType.other.coversForever)
    }

    @Test("Display names are human-readable")
    func displayNames() {
        #expect(LicenseType.lifetime.displayName == "Lifetime")
        #expect(LicenseType.oneTime.displayName == "One-time")
        #expect(LicenseType.annual.displayName == "Annual")
        #expect(LicenseType.other.displayName == "Other")
    }
}

@Suite("Pricing Fields")
struct PricingFieldsTests {
    @MainActor
    @Test("New records default to not-free with no license type")
    func defaults() throws {
        let container = try ModelContainer(
            for: AppRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let record = AppRecord(bundleID: "com.x", appName: "X", explanation: "",
                               relevanceScore: 0, relevanceReason: "",
                               bestUse: "", ollamaModel: "")
        container.mainContext.insert(record)
        #expect(record.isFreeApp == false)
        #expect(record.licenseType == nil)
    }
}

@Suite("Utility Card Rules")
struct UtilityCardRulesTests {
    @Test("License card disabled for My Apps and free apps only")
    func licenseRule() {
        #expect(UtilityCardRules.licenseDisabled(isMyApp: true, isFreeApp: false))
        #expect(UtilityCardRules.licenseDisabled(isMyApp: false, isFreeApp: true))
        #expect(UtilityCardRules.licenseDisabled(isMyApp: true, isFreeApp: true))
        #expect(!UtilityCardRules.licenseDisabled(isMyApp: false, isFreeApp: false))
    }

    @Test("Subscription card disabled for My Apps, free apps, and forever licenses")
    func subscriptionRule() {
        #expect(UtilityCardRules.subscriptionDisabled(isMyApp: true, isFreeApp: false, licenseType: nil))
        #expect(UtilityCardRules.subscriptionDisabled(isMyApp: false, isFreeApp: true, licenseType: nil))
        #expect(UtilityCardRules.subscriptionDisabled(isMyApp: false, isFreeApp: false, licenseType: .lifetime))
        #expect(UtilityCardRules.subscriptionDisabled(isMyApp: false, isFreeApp: false, licenseType: .oneTime))
        #expect(!UtilityCardRules.subscriptionDisabled(isMyApp: false, isFreeApp: false, licenseType: .annual))
        #expect(!UtilityCardRules.subscriptionDisabled(isMyApp: false, isFreeApp: false, licenseType: .other))
        #expect(!UtilityCardRules.subscriptionDisabled(isMyApp: false, isFreeApp: false, licenseType: nil))
    }

    @Test("Disabled reason priority: your app, then free, then license type")
    func reasonPriority() {
        #expect(UtilityCardRules.disabledReason(isMyApp: true, isFreeApp: true, licenseType: .lifetime) == "Your app")
        #expect(UtilityCardRules.disabledReason(isMyApp: false, isFreeApp: true, licenseType: .lifetime) == "Free app")
        #expect(UtilityCardRules.disabledReason(isMyApp: false, isFreeApp: false, licenseType: .lifetime) == "Lifetime license")
        #expect(UtilityCardRules.disabledReason(isMyApp: false, isFreeApp: false, licenseType: .oneTime) == "One-time license")
        #expect(UtilityCardRules.disabledReason(isMyApp: false, isFreeApp: false, licenseType: .annual) == nil)
        #expect(UtilityCardRules.disabledReason(isMyApp: false, isFreeApp: false, licenseType: nil) == nil)
    }
}

@Suite("Pricing Marks")
struct PricingMarksTests {
    @MainActor
    @Test("Marking free clears paid, and vice versa")
    func mutualExclusion() throws {
        let container = try ModelContainer(
            for: AppRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let record = AppRecord(bundleID: "com.x", appName: "X", explanation: "",
                               relevanceScore: 0, relevanceReason: "",
                               bestUse: "", ollamaModel: "")
        container.mainContext.insert(record)

        PricingMarks.setPaid(record, to: true)
        #expect(record.isPaidApp && !record.isFreeApp)
        PricingMarks.setFree(record, to: true)
        #expect(record.isFreeApp && !record.isPaidApp)
        PricingMarks.setPaid(record, to: true)
        #expect(record.isPaidApp && !record.isFreeApp)
    }

    @MainActor
    @Test("Unmarking one does not set the other")
    func unmarkIsNotToggle() throws {
        let container = try ModelContainer(
            for: AppRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let record = AppRecord(bundleID: "com.x", appName: "X", explanation: "",
                               relevanceScore: 0, relevanceReason: "",
                               bestUse: "", ollamaModel: "")
        container.mainContext.insert(record)

        PricingMarks.setFree(record, to: true)
        PricingMarks.setFree(record, to: false)
        #expect(!record.isFreeApp && !record.isPaidApp)
        PricingMarks.setPaid(record, to: true)
        PricingMarks.setPaid(record, to: false)
        #expect(!record.isPaidApp && !record.isFreeApp)
    }
}

@Suite("Similar Apps Prompt")
struct SimilarAppsPromptTests {
    @Test("Parse keeps only valid indices and extracts reasons")
    func parseValid() {
        let reply = """
        3: Both are AI-assisted code editors
        7: Terminal AI coding agent
        """
        let picks = SimilarAppsPrompt.parse(reply, validIndices: [1, 3, 7])
        #expect(picks.count == 2)
        #expect(picks[0].index == 3)
        #expect(picks[0].reason == "Both are AI-assisted code editors")
        #expect(picks[1].index == 7)
    }

    @Test("Out-of-range or invented indices are dropped (grounding)")
    func parseRejectsInvalid() {
        // 99 is not a real candidate; a bare app name is not an index.
        let reply = """
        99: Invented app the user does not have
        Raycast: also a launcher
        2: A real overlapping app
        """
        let picks = SimilarAppsPrompt.parse(reply, validIndices: [1, 2])
        #expect(picks.map(\.index) == [2])
    }

    @Test("NONE and empty replies yield no picks")
    func parseNone() {
        #expect(SimilarAppsPrompt.parse("NONE", validIndices: [1, 2]).isEmpty)
        #expect(SimilarAppsPrompt.parse("", validIndices: [1, 2]).isEmpty)
    }

    @Test("Duplicate indices are collapsed")
    func parseDedup() {
        let picks = SimilarAppsPrompt.parse("2: reason a\n2: reason b", validIndices: [2])
        #expect(picks.count == 1)
    }

    @Test("Prompt lists candidates by number and never leaks beyond the list")
    func promptStructure() {
        let prompt = SimilarAppsPrompt.build(
            targetName: "Cursor",
            targetCategory: "Developer Tools",
            targetExplanation: "AI code editor",
            candidates: [
                .init(index: 1, name: "Goose", category: "Developer Tools", explanation: "AI agent"),
                .init(index: 2, name: "Zed", category: "Developer Tools", explanation: "Fast editor")
            ]
        )
        #expect(prompt.contains("1. Goose"))
        #expect(prompt.contains("2. Zed"))
        #expect(prompt.contains("Choose ONLY from the numbered list"))
        #expect(prompt.contains("Cursor"))
    }
}

@Suite("Docs Evidence")
struct DocsEvidenceTests {
    private func tempFolder() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docsev-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Reads README text and lists detected manifests")
    func readsReadmeAndManifests() throws {
        let dir = tempFolder()
        try "# MyTool\nA menu-bar batch renamer.".write(
            to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "{}".write(to: dir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let result = DocsEvidence.extract(fromFolder: dir.path)
        #expect(result?.contains("A menu-bar batch renamer.") == true)
        #expect(result?.contains("Detected project files:") == true)
        #expect(result?.contains("package.json") == true)
    }

    @Test("Manifest-only folder still returns the stack hint")
    func manifestOnly() throws {
        let dir = tempFolder()
        try "".write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let result = DocsEvidence.extract(fromFolder: dir.path)
        #expect(result?.contains("Package.swift") == true)
    }

    @Test("Empty or irrelevant folder returns nil")
    func emptyFolder() throws {
        let dir = tempFolder()
        try "x".write(to: dir.appendingPathComponent("notes.rtf"), atomically: true, encoding: .utf8)
        #expect(DocsEvidence.extract(fromFolder: dir.path) == nil)
        #expect(DocsEvidence.extract(fromFolder: "/no/such/folder/here") == nil)
    }

    @Test("Oversize README is truncated to the cap")
    func truncatesReadme() throws {
        let dir = tempFolder()
        let big = String(repeating: "A", count: DocsEvidence.maxReadmeChars + 500)
        try big.write(to: dir.appendingPathComponent("README"), atomically: true, encoding: .utf8)
        let result = DocsEvidence.extract(fromFolder: dir.path) ?? ""
        #expect(result.count <= DocsEvidence.maxReadmeChars + 200) // room for hint/labels
        #expect(!result.contains(big))
    }

    @Test("Xcode project folder with only a .xcodeproj is detected")
    func xcodeProjectOnly() throws {
        let dir = tempFolder()
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("MyApp.xcodeproj"), withIntermediateDirectories: true)
        let result = DocsEvidence.extract(fromFolder: dir.path)
        #expect(result?.contains("MyApp.xcodeproj") == true)
    }
}

@Suite("Analysis Prompt Docs Evidence")
struct AnalysisPromptDocsEvidenceTests {
    private var app: AppInfo {
        AppInfo(id: "com.x", name: "X", version: "1", bundleID: "com.x",
                path: "/Applications/X.app", humanReadableDescription: nil,
                sparkleFeedURL: nil, isAppStoreInstall: false, icon: nil)
    }

    @Test("Docs evidence appears as primary evidence when provided")
    func docsIncluded() {
        let prompt = AppAnalysisPrompt.build(app: app, profile: .local(text: nil),
                                             includeResponseFormat: true,
                                             docsEvidence: "A menu-bar batch renamer.\nDetected project files: Package.swift")
        #expect(prompt.contains("From the app's own project files"))
        #expect(prompt.contains("A menu-bar batch renamer."))
        #expect(prompt.contains("the app's own project files outrank"))
    }

    @Test("No docs block when evidence is empty or whitespace")
    func emptyOmits() {
        let empty = AppAnalysisPrompt.build(app: app, profile: .local(text: nil), includeResponseFormat: true)
        let whitespace = AppAnalysisPrompt.build(app: app, profile: .local(text: nil),
                                                 includeResponseFormat: true, docsEvidence: "   \n")
        #expect(!empty.contains("From the app's own project files"))
        #expect(empty == whitespace)
    }
}

@Suite("Money Cube State")
struct MoneyCubeStateTests {
    @Test("Precedence: subscription > App Store > licensed > free > none")
    func precedence() {
        // Subscription wins over everything.
        #expect(MoneyCubeState.derive(isAppStoreInstall: true, hasLicenseKey: true, isPaidApp: true,
                                      hasSubscription: true, renewalNear: false, isFreeApp: true)
                == .subscription(renewalNear: false))
        // App Store beats licensed/paid and free.
        #expect(MoneyCubeState.derive(isAppStoreInstall: true, hasLicenseKey: false, isPaidApp: true,
                                      hasSubscription: false, renewalNear: false, isFreeApp: false)
                == .appStore)
        // ...until you record what kind of purchase it was.
        #expect(MoneyCubeState.derive(isAppStoreInstall: true, hasLicenseKey: false, isPaidApp: false,
                                      hasSubscription: false, renewalNear: false, isFreeApp: false,
                                      licenseType: .lifetime)
                == .licensed(.lifetime))
        // A license type alone is enough to count as licensed — no key needed.
        #expect(MoneyCubeState.derive(isAppStoreInstall: false, hasLicenseKey: false, isPaidApp: false,
                                      hasSubscription: false, renewalNear: false, isFreeApp: false,
                                      licenseType: .oneTime)
                == .licensed(.oneTime))
        // Subscription still outranks a typed App Store purchase.
        #expect(MoneyCubeState.derive(isAppStoreInstall: true, hasLicenseKey: false, isPaidApp: false,
                                      hasSubscription: true, renewalNear: false, isFreeApp: false,
                                      licenseType: .lifetime)
                == .subscription(renewalNear: false))
        // Key or paid mark → licensed, carrying the license type.
        #expect(MoneyCubeState.derive(isAppStoreInstall: false, hasLicenseKey: true, isPaidApp: false,
                                      hasSubscription: false, renewalNear: false, isFreeApp: false)
                == .licensed(nil))
        #expect(MoneyCubeState.derive(isAppStoreInstall: false, hasLicenseKey: false, isPaidApp: true,
                                      hasSubscription: false, renewalNear: false, isFreeApp: false,
                                      licenseType: .lifetime)
                == .licensed(.lifetime))
        // Free mark, nothing else.
        #expect(MoneyCubeState.derive(isAppStoreInstall: false, hasLicenseKey: false, isPaidApp: false,
                                      hasSubscription: false, renewalNear: false, isFreeApp: true)
                == .free)
        // Nothing at all.
        #expect(MoneyCubeState.derive(isAppStoreInstall: false, hasLicenseKey: false, isPaidApp: false,
                                      hasSubscription: false, renewalNear: false, isFreeApp: false)
                == .none)
    }

    @Test("Renewal-near flag flows through")
    func renewalNear() {
        #expect(MoneyCubeState.derive(isAppStoreInstall: false, hasLicenseKey: false, isPaidApp: false,
                                      hasSubscription: true, renewalNear: true, isFreeApp: false)
                == .subscription(renewalNear: true))
    }

    @Test("Symbols and active flag per state")
    func faces() {
        #expect(MoneyCubeState.subscription(renewalNear: false).symbol == "creditcard.fill")
        #expect(MoneyCubeState.appStore.symbol == "checkmark.seal.fill")
        #expect(MoneyCubeState.free.symbol == "gift")
        #expect(MoneyCubeState.none.symbol == "dollarsign.circle")
        #expect(MoneyCubeState.subscription(renewalNear: true).isActive)
        #expect(MoneyCubeState.appStore.isActive)
        #expect(MoneyCubeState.licensed(nil).isActive)
        #expect(MoneyCubeState.free.isActive)
        #expect(!MoneyCubeState.none.isActive)
    }

    @Test("Licensed cube wears its license type on the face")
    func licensedFaces() {
        #expect(MoneyCubeState.licensed(.lifetime).symbol == "infinity")
        #expect(MoneyCubeState.licensed(.oneTime).symbol == "1.circle")
        #expect(MoneyCubeState.licensed(.annual).symbol == "calendar")
        #expect(MoneyCubeState.licensed(.other).symbol == "key.horizontal")
        #expect(MoneyCubeState.licensed(nil).symbol == "key.horizontal")
    }
}

@Suite("App Facts")
struct AppFactsTests {
    private static let now = Date(timeIntervalSince1970: 1_770_000_000)

    private func facts(sizeBytes: Int64? = 12_345_678,
                       lastUsed: Date? = nil,
                       source: String = "App Store",
                       analyzedAt: Date? = nil) -> [AppFact] {
        AppFacts.build(sizeBytes: sizeBytes, lastUsed: lastUsed, now: Self.now,
                       installSource: source, analyzedAt: analyzedAt)
    }

    @Test("Unknown facts are left out rather than shown empty")
    func omitsUnknowns() {
        let row = facts(sizeBytes: nil)
        #expect(!row.contains { $0.label == "On disk" })
        #expect(!row.contains { $0.label == "Analyzed" })
        // Last used and Source always have an answer.
        #expect(row.map(\.label) == ["Last used", "Source"])
    }

    @Test("A zero or missing size is not a fact")
    func zeroSize() {
        #expect(!facts(sizeBytes: 0).contains { $0.label == "On disk" })
    }

    @Test("Never-opened apps say so — the most useful cell for an audit")
    func lastUsed() {
        #expect(AppFacts.lastUsedText(nil, now: Self.now) == "Never")
        #expect(AppFacts.lastUsedText(Self.now, now: Self.now) == "Today")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Self.now)!
        #expect(AppFacts.lastUsedText(yesterday, now: Self.now) == "Yesterday")
    }

    @Test("\"Other\" is named as what actually happened")
    func source() {
        #expect(AppFacts.sourceText("Other") == "Direct download")
        #expect(AppFacts.sourceText("Homebrew") == "Homebrew")
        #expect(AppFacts.sourceText("App Store") == "App Store")
    }

    /// Four cells is the cap that lets the row stay on one line.
    @Test("A full row is four cells in reading order")
    func order() {
        let row = facts(lastUsed: Self.now, analyzedAt: Self.now)
        #expect(row.map(\.label) == ["On disk", "Last used", "Source", "Analyzed"])
        #expect(row.count <= 4)
    }
}

@Suite("Trash Service")
struct TrashServiceTests {
    /// The exact error a root-owned Mac App Store bundle produces.
    @Test("A permission refusal is recognised, so it can be routed to Finder")
    func permissionErrors() {
        #expect(TrashService.isPermissionDenied(
            NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)))
        #expect(TrashService.isPermissionDenied(
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)))
        #expect(TrashService.isPermissionDenied(
            NSError(domain: NSCocoaErrorDomain, code: NSFileWriteVolumeReadOnlyError)))
    }

    @Test("Other failures are not mistaken for permission problems")
    func otherErrors() {
        #expect(!TrashService.isPermissionDenied(
            NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)))
        #expect(!TrashService.isPermissionDenied(
            NSError(domain: NSOSStatusErrorDomain, code: -5000)))
    }

    @Test("A plain path becomes a Finder delete command")
    func scriptShape() {
        #expect(TrashService.finderDeleteScript(for: "/Applications/Bear.app")
                == "tell application \"Finder\" to delete POSIX file \"/Applications/Bear.app\"")
    }

    @Test("Quotes and backslashes in a path survive into the script")
    func scriptEscaping() {
        let script = TrashService.finderDeleteScript(for: #"/Applications/We"ird\App.app"#)
        #expect(script.contains(#"We\"ird"#))
        #expect(script.contains(#"\\App.app"#))
        #expect(script.hasSuffix("\""))
    }

    @Test("A failure always carries a readable reason")
    func reasons() {
        let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        #expect(TrashService.reason(for: denied).contains("Finder"))
        let missing = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        #expect(!TrashService.reason(for: missing).isEmpty)
    }
}

@Suite("Vault Link")
struct VaultLinkTests {
    @Test("A saved link wins over a suggestion")
    func savedWins() {
        let destination = VaultLink.destination(appURL: "https://raycast.com",
                                                suggestedAppURL: "https://example.com",
                                                appName: "Raycast")
        #expect(destination == .saved(URL(string: "https://raycast.com")!))
    }

    @Test("The suggestion is followed when nothing is saved")
    func suggestionFallback() {
        let destination = VaultLink.destination(appURL: nil,
                                                suggestedAppURL: "https://kosshi.app",
                                                appName: "Kosshi")
        #expect(destination == .suggested(URL(string: "https://kosshi.app")!))
        #expect(!destination.isSearch)
    }

    @Test("Blank and whitespace-only links do not count as links")
    func blankLinks() {
        let destination = VaultLink.destination(appURL: "  ", suggestedAppURL: "",
                                                appName: "Kosshi")
        #expect(destination.isSearch)
    }

    @Test("A bare host gets an https scheme so it actually opens")
    func schemeless() {
        let destination = VaultLink.destination(appURL: "raycast.com", suggestedAppURL: nil,
                                                appName: "Raycast")
        #expect(destination == .saved(URL(string: "https://raycast.com")!))
    }

    @Test("No link on record falls back to a web search for the app name")
    func searchFallback() {
        let destination = VaultLink.destination(appURL: nil, suggestedAppURL: nil,
                                                appName: "Folder Quick Look")
        #expect(destination.isSearch)
        #expect(destination.url.absoluteString.contains("Folder"))
        #expect(destination.url.host() == "www.google.com")
    }

    @Test("Help text names the destination")
    func helpText() {
        let saved = VaultLink.destination(appURL: "https://raycast.com", suggestedAppURL: nil,
                                          appName: "Raycast")
        #expect(VaultLink.help(for: saved, appName: "Raycast") == "Open raycast.com")
        let search = VaultLink.destination(appURL: nil, suggestedAppURL: nil, appName: "Kosshi")
        #expect(VaultLink.help(for: search, appName: "Kosshi").contains("Kosshi"))
    }
}

@Suite("License Draft Rules")
struct LicenseDraftRulesTests {
    @Test("Nothing typed and nothing changed is not saveable")
    func emptyDraft() {
        #expect(!LicenseDraftRules.hasSomethingToSave(key: "", email: "", type: nil,
                                                      hasKey: false, currentType: nil))
        #expect(!LicenseDraftRules.hasSomethingToSave(key: "   ", email: "  ", type: .lifetime,
                                                      hasKey: false, currentType: .lifetime))
    }

    @Test("A license type saves on its own — the App Store case")
    func typeOnly() {
        #expect(LicenseDraftRules.hasSomethingToSave(key: "", email: "", type: .lifetime,
                                                     hasKey: false, currentType: nil))
    }

    @Test("Correcting or clearing a wrong type is saveable")
    func changingType() {
        #expect(LicenseDraftRules.hasSomethingToSave(key: "", email: "", type: .annual,
                                                     hasKey: false, currentType: .lifetime))
        #expect(LicenseDraftRules.hasSomethingToSave(key: "", email: "", type: nil,
                                                     hasKey: false, currentType: .lifetime))
    }

    @Test("A key, an existing key, or an email all keep Save live")
    func otherPayloads() {
        #expect(LicenseDraftRules.hasSomethingToSave(key: "ABC-123", email: "", type: nil,
                                                     hasKey: false, currentType: nil))
        #expect(LicenseDraftRules.hasSomethingToSave(key: "", email: "", type: nil,
                                                     hasKey: true, currentType: nil))
        #expect(LicenseDraftRules.hasSomethingToSave(key: "", email: "me@example.com", type: nil,
                                                     hasKey: false, currentType: nil))
    }
}

@Suite("Money Cube + Dev Mode Rules")
struct MoneyDevRulesTests {
    @Test("Money cube is disabled only for My Apps")
    func moneyRule() {
        #expect(UtilityCardRules.moneyDisabled(isMyApp: true))
        #expect(!UtilityCardRules.moneyDisabled(isMyApp: false))
    }

    @Test("My App UI shows only when marked AND developer mode is on")
    func showsMyAppUI() {
        #expect(DevModeRules.showsMyAppUI(isMyApp: true, developerMode: true))
        #expect(!DevModeRules.showsMyAppUI(isMyApp: true, developerMode: false))
        #expect(!DevModeRules.showsMyAppUI(isMyApp: false, developerMode: true))
        #expect(!DevModeRules.showsMyAppUI(isMyApp: false, developerMode: false))
    }

    @Test("Leaving developer mode clears the My Apps filter")
    func filterClears() {
        #expect(DevModeRules.filterMyApps(current: true, developerMode: true))
        #expect(!DevModeRules.filterMyApps(current: true, developerMode: false))
        #expect(!DevModeRules.filterMyApps(current: false, developerMode: true))
    }
}

@Suite("Uninstall Rules")
struct UninstallRulesTests {
    @Test("Apple system apps, Sift, and the side-build are protected")
    func protection() {
        #expect(UninstallRules.isProtected(bundleID: "com.apple.finder"))
        #expect(UninstallRules.isProtected(bundleID: "com.apple.dt.Xcode"))
        #expect(UninstallRules.isProtected(bundleID: "com.kikaapp.appaudit"))
        #expect(UninstallRules.isProtected(bundleID: "com.kikaapp.sift2"))
        #expect(!UninstallRules.isProtected(bundleID: "com.asiafu.Bloom"))
        #expect(!UninstallRules.isProtected(bundleID: "net.shinyfrog.bear"))
    }
}

@Suite("Leftover Matcher")
struct LeftoverMatcherTests {
    @Test("Bundle-identifier shapes match")
    func identifierShapes() {
        let id = "com.asiafu.Bloom"
        #expect(LeftoverMatcher.matches(name: "com.asiafu.Bloom", bundleID: id))
        #expect(LeftoverMatcher.matches(name: "com.asiafu.Bloom.plist", bundleID: id))
        #expect(LeftoverMatcher.matches(name: "com.asiafu.Bloom.plist.lockfile", bundleID: id))
        #expect(LeftoverMatcher.matches(name: "com.asiafu.Bloom.helper", bundleID: id))
        #expect(LeftoverMatcher.matches(name: "com.asiafu.Bloom.savedState", bundleID: id))
        // ByHost shape: <id>.<uuid>.plist
        #expect(LeftoverMatcher.matches(name: "com.asiafu.Bloom.ABC-123.plist", bundleID: id))
    }

    @Test("Unrelated identifiers do not match")
    func unrelated() {
        let id = "com.asiafu.Bloom"
        #expect(!LeftoverMatcher.matches(name: "com.other.app", bundleID: id))
        #expect(!LeftoverMatcher.matches(name: "org.bloom.tools", bundleID: id))
        #expect(!LeftoverMatcher.matches(name: "Bloom", bundleID: id)) // bare names need the name-match path
    }

    @Test("Display-name match is gated by category and length")
    func displayName() {
        #expect(LeftoverMatcher.nameMatchAllowed(for: .applicationSupport))
        #expect(LeftoverMatcher.nameMatchAllowed(for: .logs))
        #expect(!LeftoverMatcher.nameMatchAllowed(for: .caches))
        #expect(!LeftoverMatcher.nameMatchAllowed(for: .preferences))
        #expect(LeftoverMatcher.matchesDisplayName("bloom", appName: "Bloom"))
        #expect(LeftoverMatcher.matchesDisplayName("Bloom", appName: "Bloom"))
        #expect(!LeftoverMatcher.matchesDisplayName("Bloomberg", appName: "Bloom"))
        #expect(!LeftoverMatcher.matchesDisplayName("IINA", appName: "IINA") == false) // 4 chars passes
        #expect(!LeftoverMatcher.matchesDisplayName("Mo", appName: "Mo"))   // too short, generic
    }
}


@Suite("OpenAICompatibleService model list tidying")
struct OpenAICompatibleModelListTests {

    @Test("Gemini IDs lose the models/ prefix and non-Gemini entries")
    func geminiTidy() {
        let raw = ["models/gemini-2.5-flash", "models/gemini-2.5-flash-lite", "models/embedding-001", "models/imagen-3"]
        let tidy = OpenAICompatibleService.tidyModelIDs(raw, for: .gemini)
        #expect(tidy == ["gemini-2.5-flash", "gemini-2.5-flash-lite"])
    }

    @Test("OpenRouter lists the free router first, then free models, then paid, each sorted")
    func openRouterTidy() {
        let raw = ["openai/gpt-4o", "meta-llama/llama-3.3-70b-instruct:free", "openrouter/free", "anthropic/claude-3.5-sonnet", "deepseek/deepseek-chat:free"]
        let tidy = OpenAICompatibleService.tidyModelIDs(raw, for: .openRouter)
        #expect(tidy == ["openrouter/free", "deepseek/deepseek-chat:free", "meta-llama/llama-3.3-70b-instruct:free",
                         "anthropic/claude-3.5-sonnet", "openai/gpt-4o"])
    }

    @Test("OpenAI keeps chat families, falling back to everything when none match")
    func openAITidy() {
        #expect(OpenAICompatibleService.tidyModelIDs(["gpt-4o-mini", "whisper-1", "o3-mini"], for: .openAI) == ["gpt-4o-mini", "o3-mini"])
        #expect(OpenAICompatibleService.tidyModelIDs(["whisper-1", "dall-e-3"], for: .openAI) == ["dall-e-3", "whisper-1"])
    }

    @Test("Quota exhaustion is named, not blamed on the key")
    func describeStatus() {
        #expect(OpenAICompatibleService.describe(status: 429, provider: "Google Gemini").contains("quota"))
        #expect(OpenAICompatibleService.describe(status: 401, provider: "OpenRouter").contains("API key"))
        #expect(OpenAICompatibleService.describe(status: 404, provider: "OpenAI").contains("model"))
    }
}

// MARK: - Pre-launch audit fixes (2026-08-27)

@Suite("Leftover matcher respects sibling apps")
struct LeftoverMatcherSiblingTests {
    @Test("A sibling app's files are not swept as leftovers of the shorter bundle ID")
    func siblingExcluded() {
        let others = ["com.google.Chrome.canary", "com.google.Chrome.beta", "com.other.app"]
        #expect(!LeftoverMatcher.matches(name: "com.google.Chrome.canary.plist", bundleID: "com.google.Chrome", otherBundleIDs: others))
        #expect(!LeftoverMatcher.matches(name: "com.google.Chrome.canary", bundleID: "com.google.Chrome", otherBundleIDs: others))
        #expect(!LeftoverMatcher.matches(name: "com.google.Chrome.beta.savedState", bundleID: "com.google.Chrome", otherBundleIDs: others))
    }

    @Test("The app's own files still match with siblings present")
    func ownFilesStillMatch() {
        let others = ["com.google.Chrome.canary"]
        #expect(LeftoverMatcher.matches(name: "com.google.Chrome.plist", bundleID: "com.google.Chrome", otherBundleIDs: others))
        #expect(LeftoverMatcher.matches(name: "com.google.Chrome.helper", bundleID: "com.google.Chrome", otherBundleIDs: others))
        #expect(LeftoverMatcher.matches(name: "com.google.Chrome", bundleID: "com.google.Chrome", otherBundleIDs: others))
    }

    @Test("Uninstalling the sibling itself is unaffected")
    func siblingOwnSweep() {
        let others = ["com.google.Chrome"]
        #expect(LeftoverMatcher.matches(name: "com.google.Chrome.canary.plist", bundleID: "com.google.Chrome.canary", otherBundleIDs: others))
    }
}

@Suite("Settings model auto-selection")
struct ModelAutoSelectionTests {
    @Test("Keeps the provider default when it is available and nothing is stored")
    func keepsDefault() {
        let defaults = UserDefaults(suiteName: "AppAuditTests.ModelAutoSelection.keep")!
        defaults.removeObject(forKey: AnalysisProviderKind.gemini.modelDefaultsKey)
        let pick = AnalysisProviderKind.gemini.modelToSelect(from: ["gemini-2.5-pro", AnalysisProviderKind.gemini.defaultModel], userDefaults: defaults)
        #expect(pick == nil)
    }

    @Test("Keeps a stored choice that is available")
    func keepsStored() {
        let defaults = UserDefaults(suiteName: "AppAuditTests.ModelAutoSelection.stored")!
        defaults.set("gemini-2.5-pro", forKey: AnalysisProviderKind.gemini.modelDefaultsKey)
        #expect(AnalysisProviderKind.gemini.modelToSelect(from: ["gemini-2.5-flash", "gemini-2.5-pro"], userDefaults: defaults) == nil)
    }

    @Test("Falls back to the first listed model only when the effective choice is missing")
    func fallsBack() {
        let defaults = UserDefaults(suiteName: "AppAuditTests.ModelAutoSelection.fallback")!
        defaults.removeObject(forKey: AnalysisProviderKind.gemini.modelDefaultsKey)
        #expect(AnalysisProviderKind.gemini.modelToSelect(from: ["gemini-2.5-pro"], userDefaults: defaults) == "gemini-2.5-pro")
        defaults.set("gone-model", forKey: AnalysisProviderKind.gemini.modelDefaultsKey)
        #expect(AnalysisProviderKind.gemini.modelToSelect(from: ["gemini-2.5-pro"], userDefaults: defaults) == "gemini-2.5-pro")
        #expect(AnalysisProviderKind.gemini.modelToSelect(from: [], userDefaults: defaults) == nil)
    }
}

@Suite("Sparkle feed configuration")
struct SparkleFeedConfigurationTests {
    @Test("Only a non-empty feed string counts as configured")
    func feedConfigured() {
        #expect(!UpdateService.feedIsConfigured(nil))
        #expect(!UpdateService.feedIsConfigured(""))
        #expect(!UpdateService.feedIsConfigured("   "))
        #expect(!UpdateService.feedIsConfigured(42))
        #expect(UpdateService.feedIsConfigured("https://sift.akakika.com/appcast.xml"))
    }
}

@Suite("Cache ensureRecord")
struct CacheEnsureRecordTests {
    @Test("ensureRecord returns the existing analysed record instead of inserting a blank twin")
    @MainActor
    func returnsExisting() throws {
        let container = try ModelContainer(for: AppRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let cache = CacheService(context: container.mainContext)
        cache.save(bundleID: "com.example.real", appName: "Real", explanation: "A real analysis",
                   score: 4, reason: "Useful", bestUse: "Daily", ollamaModel: "ollama:x")

        let record = cache.ensureRecord(bundleID: "com.example.real", appName: "Real")

        #expect(record.explanation == "A real analysis")
        #expect(record.relevanceScore == 4)
        #expect(cache.allRecords().count == 1)
    }

    @Test("ensureRecord creates a stub when nothing exists, once")
    @MainActor
    func createsOnce() throws {
        let container = try ModelContainer(for: AppRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let cache = CacheService(context: container.mainContext)
        let first = cache.ensureRecord(bundleID: "com.example.new", appName: "New")
        let second = cache.ensureRecord(bundleID: "com.example.new", appName: "New")
        #expect(first.explanation.isEmpty)
        #expect(first === second)
        #expect(cache.allRecords().count == 1)
    }
}

@Suite("Homebrew outcome")
struct HomebrewOutcomeTests {
    @Test("A non-zero exit or missing brew is a failure, never a success")
    func outcome() {
        #expect(HomebrewService.BrewOutcome(exitStatus: 0, output: "==> Uninstalling Cask x").succeeded)
        #expect(!HomebrewService.BrewOutcome(exitStatus: 1, output: "Error: Cask 'x' is not installed.").succeeded)
        #expect(!HomebrewService.BrewOutcome(exitStatus: nil, output: "").succeeded)
        #expect(HomebrewService.BrewOutcome(exitStatus: 1, output: "Error: Cask 'x' is not installed.").message.contains("not installed"))
    }
}

// MARK: - Audit tier B (2026-08-27)

@Suite("Homebrew cask token collisions")
struct HomebrewCaskCollisionTests {
    @Test("Two installed casks that normalise to the same token do not trap")
    func collidingTokens() {
        let casks = ["google-chrome-beta", "google-chrome@beta", "google-chrome"]
        let token = HomebrewService().caskToken(forAppName: "Google Chrome",
                                                path: "/Applications/Google Chrome.app",
                                                installedCasks: casks)
        #expect(token == "google-chrome")
    }
}

@Suite("Sparkle appcast precedence")
struct SparkleAppcastPrecedenceTests {
    @Test("An item's shortVersionString wins over the enclosure's build number")
    func shortVersionWins() throws {
        let xml = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><title>1.2.3</title>
          <sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>
          <sparkle:version>2045</sparkle:version>
          <enclosure url="https://example.com/App-1.2.3.zip" sparkle:version="2045" length="1" type="application/octet-stream"/>
        </item>
        </channel></rss>
        """
        let meta = try UpdateChecker.parseSparkleMetadata(from: Data(xml.utf8))
        #expect(meta?.version == "1.2.3")
        #expect(meta?.url == "https://example.com/App-1.2.3.zip")
    }

    @Test("Items on a named channel (beta) are ignored")
    func betaChannelIgnored() throws {
        let xml = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><title>2.0 beta</title>
          <sparkle:channel>beta</sparkle:channel>
          <enclosure url="https://example.com/App-2.0b1.zip" sparkle:shortVersionString="2.0b1" sparkle:version="300"/>
        </item>
        <item><title>1.9</title>
          <enclosure url="https://example.com/App-1.9.zip" sparkle:shortVersionString="1.9" sparkle:version="290"/>
        </item>
        </channel></rss>
        """
        let meta = try UpdateChecker.parseSparkleMetadata(from: Data(xml.utf8))
        #expect(meta?.version == "1.9")
        #expect(meta?.url == "https://example.com/App-1.9.zip")
    }
}

/// A backend whose writes vanish — what a denied or locked Keychain looks like.
final class DroppingSecretStoreBackend: SecretStoreBackend, @unchecked Sendable {
    func read(account: String) -> String? { nil }
    @discardableResult func write(_ value: String, account: String) -> Bool { false }
    func delete(account: String) {}
}

@Suite("License key migration honesty")
struct LicenseKeyMigrationHonestyTests {
    @Test("resolveKey does not claim a migration the backend did not perform")
    func noFalseMigrationClaim() {
        let store = LicenseKeyStore(backend: DroppingSecretStoreBackend())
        let resolution = store.resolveKey(bundleID: "com.example.app", legacyValue: "LEGACY-KEY")
        #expect(!resolution.didMigrateLegacyValue)
        #expect(resolution.value == "LEGACY-KEY")   // still usable this session, from the legacy field
    }

    @Test("migrateLegacyKey reports absence when the write failed")
    func migrationReportsFailure() {
        let store = LicenseKeyStore(backend: DroppingSecretStoreBackend())
        #expect(!store.migrateLegacyKey("LEGACY-KEY", bundleID: "com.example.app"))
    }
}

@Suite("Shared provider error wording")
struct SharedProviderErrorTests {
    @Test("All HTTP providers share one status vocabulary")
    func sharedDescribe() {
        #expect(AnalysisHTTP.describe(status: 429, provider: "Ollama").contains("quota"))
        #expect(AnalysisHTTP.describe(status: 404, provider: "Anthropic").contains("model"))
        #expect(AnalysisHTTP.describe(status: 401, provider: "Anthropic").contains("API key"))
    }
}

import Testing
import Foundation
import SwiftData
@testable import Sift

@Suite("WorkflowProfile Tests")
struct WorkflowProfileTests {

    @Test("Generic profile has expected defaults")
    func genericProfile() {
        let profile = WorkflowProfile.generic()
        #expect(profile.languages.contains("Swift"))
        #expect(profile.tools.contains("Xcode"))
        #expect(profile.promptDescription.contains("software engineering"))
    }

    @Test("Prompt description includes all non-empty fields")
    func promptDescription() {
        let profile = WorkflowProfile(
            languages: ["Swift"],
            tools: ["Xcode"],
            domains: [],
            projectKeywords: ["AppAudit"],
            customDescription: nil
        )
        let desc = profile.promptDescription
        #expect(desc.contains("Swift"))
        #expect(desc.contains("Xcode"))
        #expect(desc.contains("AppAudit"))
        #expect(!desc.contains("Domains"))
    }

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

@Suite("OllamaService Score Parsing Tests")
struct OllamaScoreParsingTests {

    @Test("Parses valid score response")
    func parseValidScore() async {
        let service = OllamaService()
        let response = """
        SCORE: 4
        REASON: Essential IDE for Swift development
        """
        let result = await service.parseScore(from: response)
        #expect(result?.score == 4)
        #expect(result?.reason == "Essential IDE for Swift development")
    }

    @Test("Returns nil for invalid score")
    func parseInvalidScore() async {
        let service = OllamaService()
        let response = "This is not a valid response"
        let result = await service.parseScore(from: response)
        #expect(result == nil)
    }

    @Test("Returns nil for out-of-range score")
    func parseOutOfRangeScore() async {
        let service = OllamaService()
        let response = """
        SCORE: 7
        REASON: Very relevant
        """
        let result = await service.parseScore(from: response)
        #expect(result == nil)
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

    @Test("Provider set is Ollama plus the two optional cloud providers")
    func providerCases() {
        // Personal edition: Ollama is the default and focus; Apple Intelligence
        // has been removed. Anthropic and OpenAI remain as optional cloud providers.
        #expect(AnalysisProviderKind.allCases.count == 3)
        #expect(Set(AnalysisProviderKind.allCases) == [.ollama, .anthropic, .openAI])
        #expect(AnalysisProviderKind.ollama.defaultModel == OllamaDefaults.model)
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
            HomebrewCaskInfo(token: "betterdisplay", installedVersion: "4.3.0", latestVersion: "4.4.0")
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

    func write(_ value: String, account: String) {
        values[account] = value
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
        let prompt = AppAnalysisPrompt.build(app: app, profile: .generic(),
                                             includeResponseFormat: false,
                                             styleNotes: "Mention alternatives.")
        #expect(prompt.contains("Additional style notes from the user (follow them):"))
        #expect(prompt.contains("Mention alternatives."))
    }

    @Test("No style block when notes are empty or whitespace")
    func emptyOmits() {
        let prompt = AppAnalysisPrompt.build(app: app, profile: .generic(),
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
        let prompt = AppAnalysisPrompt.build(app: app, profile: .generic(),
                                             includeResponseFormat: true,
                                             userNotes: "I use this daily to cut release videos.")
        #expect(prompt.contains("The user's own notes about this app"))
        #expect(prompt.contains("I use this daily to cut release videos."))
        #expect(prompt.contains("The user's own notes outrank URL and metadata evidence"))
    }

    @Test("No notes block when notes are empty or whitespace")
    func emptyOmits() {
        let empty = AppAnalysisPrompt.build(app: app, profile: .generic(),
                                            includeResponseFormat: true)
        let whitespace = AppAnalysisPrompt.build(app: app, profile: .generic(),
                                                 includeResponseFormat: true,
                                                 userNotes: "  \n ")
        #expect(!empty.contains("The user's own notes"))
        #expect(!whitespace.contains("The user's own notes"))
        #expect(empty == whitespace)
    }

    @Test("Notes coexist with style notes without collision")
    func coexistsWithStyleNotes() {
        let prompt = AppAnalysisPrompt.build(app: app, profile: .generic(),
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

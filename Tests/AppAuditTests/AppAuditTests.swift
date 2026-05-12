import Testing
import Foundation
import SwiftData
@testable import AppAudit

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

    @Test("Blank custom profile falls back to default")
    func blankCustomProfileFallsBack() {
        let profile = WorkflowProfile.local(text: "   ")
        #expect(profile.promptDescription == WorkflowProfile.defaultProfileText)
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

    @Test("Builds stable cache identifiers for each provider")
    func modelIdentifiers() {
        let defaults = UserDefaults(suiteName: "AppAuditTests.AnalysisProviderKind.models")!
        defaults.removeObject(forKey: "ollamaModel")
        #expect(AnalysisProviderKind.ollama.modelIdentifier(userDefaults: defaults) == "ollama:llama3.2")

        defaults.set("mistral", forKey: "ollamaModel")
        #expect(AnalysisProviderKind.ollama.modelIdentifier(userDefaults: defaults) == "ollama:mistral")
        #expect(AnalysisProviderKind.appleIntelligence.modelIdentifier(userDefaults: defaults) == "apple-intelligence:foundation-models")
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

        #expect(!cache.isStale(record, currentModel: "apple-intelligence:foundation-models"))
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
        #expect(prompt.contains("Prefer bundle ID, reference URL"))
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

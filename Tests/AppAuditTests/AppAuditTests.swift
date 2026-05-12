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

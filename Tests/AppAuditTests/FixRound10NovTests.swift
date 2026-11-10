import Testing
import Foundation
import SwiftData
@testable import Sift

/// The 10 Nov review fixes (Runway card "Sift": 5d16, 5745, 380e, 5486, b3b1).

@Suite("Copy Key from the right-click menu does not open an empty License panel (5d16)")
struct CopyKeyPanelTests {
    @Test("The panel comes back after Touch ID only when it was open")
    func reopensOnlyWhenOpen() {
        #expect(CopyKeyPanel.reopensAfterCopy(panelWasOpen: true))
        #expect(!CopyKeyPanel.reopensAfterCopy(panelWasOpen: false))
    }
}

@Suite("An emptied API key field keeps the saved key (5745)")
@MainActor
struct EmptiedAPIKeyFieldTests {
    @Test("Typing a letter, deleting it and leaving the field keeps the key")
    func strayKeystrokeKeepsKey() {
        let backend = MemorySecretStoreBackend()
        backend.write("sk-ant-saved", account: AnalysisProviderKind.anthropic.apiKeyAccount)
        let defaults = UserDefaults(suiteName: "sift-tests-\(UUID().uuidString)")!
        let field = APIKeyField(store: APIKeyStore(backend: backend, defaults: defaults))
        field.load(.anthropic)
        field.update("x")
        field.update("")
        field.commit()
        #expect(backend.read(account: AnalysisProviderKind.anthropic.apiKeyAccount) == "sk-ant-saved")
        #expect(field.hasStoredKey)
        #expect(!field.saveFailed)
        #expect(field.text.isEmpty)
    }

    @Test("Spaces only count as empty too")
    func spacesKeepKey() {
        let backend = MemorySecretStoreBackend()
        backend.write("gem-saved", account: AnalysisProviderKind.gemini.apiKeyAccount)
        let defaults = UserDefaults(suiteName: "sift-tests-\(UUID().uuidString)")!
        let field = APIKeyField(store: APIKeyStore(backend: backend, defaults: defaults))
        field.load(.gemini)
        field.update("   ")
        field.commit()
        #expect(backend.read(account: AnalysisProviderKind.gemini.apiKeyAccount) == "gem-saved")
    }
}

@Suite("A subscription-only row in the License Vault (380e)")
@MainActor
struct VaultSubscriptionRowTests {
    @Test("It reads as a subscription, not Paid")
    func label() {
        #expect(VaultPurchase.label(licenseType: nil, isPaidApp: false, hasSubscription: true) == .subscription)
        #expect(VaultPurchase.label(licenseType: nil, isPaidApp: true, hasSubscription: false) == .paid)
        #expect(VaultPurchase.label(licenseType: nil, isPaidApp: true, hasSubscription: true) == .paid)
        #expect(VaultPurchase.label(licenseType: .annual, isPaidApp: false, hasSubscription: true) == .licenseType(.annual))
    }

    @Test("The trash removes it from the vault")
    func trashRemovesRow() throws {
        let container = try ModelContainer(for: AppRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let monthly = AppRecord(stub: "com.example.monthly", appName: "Monthly")
        monthly.hasSubscription = true
        monthly.subscriptionPrice = 9.99
        monthly.subscriptionCycle = "monthly"
        monthly.subscriptionEmail = "me@example.com"
        context.insert(monthly)
        try context.save()
        #expect(try context.fetch(FetchDescriptor(predicate: VaultMembership.predicate)).count == 1)

        VaultPurchase.clear(monthly)
        try context.save()
        #expect(try context.fetch(FetchDescriptor(predicate: VaultMembership.predicate)).isEmpty)
        #expect(monthly.subscriptionPrice == nil)
        #expect(monthly.subscriptionEmail == nil)
    }
}

@Suite("A cask named unlike its app is found from brew's install record (5486)")
struct CaskTokenFromReceiptTests {
    /// Goose 1.58.1's real receipt: cask block-goose, `"app":["Goose.app"]`,
    /// landing in the appdir from config.json.
    private static let receipt = Data(#"{"uninstall_artifacts":[{"app":["Goose.app"]},{"zap":[{"trash":["~/Library/Application Support/Goose"]}]}]}"#.utf8)

    @Test("Goose.app maps to block-goose, so brew's update is seen")
    func gooseFound() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "SiftGoose-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let caskroom = root.appending(path: "Caskroom")
        let appdir = root.appending(path: "Applications")
        let goose = appdir.appending(path: "Goose.app")
        let metadata = caskroom.appending(path: "block-goose/.metadata")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: goose, withIntermediateDirectories: true)
        try Self.receipt.write(to: metadata.appending(path: "INSTALL_RECEIPT.json"))
        try Data(#"{"default":{"appdir":"\#(appdir.path)"},"explicit":{}}"#.utf8)
            .write(to: metadata.appending(path: "config.json"))

        let index = HomebrewService.caskTokensByAppPath(installedCasks: ["block-goose", "firefox"],
                                                         caskroomRoots: [caskroom.path])
        let service = HomebrewService()
        // The name alone never matches: "goose" is not "blockgoose".
        #expect(service.caskToken(forAppName: "Goose", path: goose.path, installedCasks: ["block-goose"]) == nil)
        #expect(service.caskToken(forAppName: "Goose", path: goose.path, installedCasks: ["block-goose"],
                                  receiptIndex: index) == "block-goose")
        // A copy brew did not put there is not claimed by the record.
        #expect(service.caskToken(forAppName: "Goose", path: "/Users/me/Downloads/Goose.app",
                                  installedCasks: ["block-goose"], receiptIndex: index) == nil)
    }

    @Test("A cask with no record adds nothing, and the name match still works")
    func noRecord() {
        let index = HomebrewService.caskTokensByAppPath(installedCasks: ["firefox"], caskroomRoots: ["/nonexistent-caskroom"])
        #expect(index.isEmpty)
        #expect(HomebrewService().caskToken(forAppName: "Firefox", path: "/Applications/Firefox.app",
                                            installedCasks: ["firefox"], receiptIndex: index) == "firefox")
    }
}

private final class CannedUpdateClient: UpdateMetadataClient, @unchecked Sendable {
    private let responses: [String: Data]
    init(_ responses: [String: String]) { self.responses = responses.mapValues { Data($0.utf8) } }
    func data(for url: URL) async throws -> Data {
        guard let data = responses[url.absoluteString] else { throw URLError(.badServerResponse) }
        return data
    }
    func redirectLocation(for url: URL) async throws -> URL? { nil }
}

@Suite("The App Store update check asks this Mac's storefront too (b3b1)")
struct StorefrontUpdateCheckTests {
    private static let bundleID = "com.example.LocalOnly"
    private static let empty = #"{"resultCount":0,"results":[]}"#
    private static let ilAnswer = #"{"resultCount":1,"results":[{"bundleId":"com.example.LocalOnly","trackId":42,"version":"2.0","trackViewUrl":"https://apps.apple.com/il/app/local-only/id42"}]}"#

    @Test("The US store first, then the Mac's region; no repeat for a US Mac")
    func lookupOrder() {
        let il = UpdateChecker.appStoreLookupURLs(for: Self.bundleID, region: "IL").map(\.absoluteString)
        #expect(il.count == 2)
        #expect(!il[0].contains("country="))
        #expect(il[1].contains("country=il"))
        #expect(UpdateChecker.appStoreLookupURLs(for: Self.bundleID, region: "US").count == 1)
        #expect(UpdateChecker.appStoreLookupURLs(for: Self.bundleID, region: nil).count == 1)
    }

    @Test("An app not sold in the US store gets its update from the Mac's storefront")
    func regionOnlyApp() async throws {
        let urls = UpdateChecker.appStoreLookupURLs(for: Self.bundleID, region: "IL")
        let client = CannedUpdateClient([urls[0].absoluteString: Self.empty, urls[1].absoluteString: Self.ilAnswer])
        let app = AppInfo(id: Self.bundleID, name: "Local Only", version: "1.0", bundleID: Self.bundleID,
                          path: "/Applications/Local Only.app", humanReadableDescription: nil,
                          sparkleFeedURL: nil, isAppStoreInstall: true, icon: nil)
        let state = await UpdateChecker(client: client, region: "IL").check(app: app)
        #expect(state.isUpdateAvailable)
        let link = await AppLinkResolver(client: client, region: "IL").resolve(app: app)
        #expect(link?.url.contains("id42") == true)
    }
}

@Suite("Locking during a re-analyze shows the saved analysis, not a spinner (b3b1)")
struct LockedReanalysisStateTests {
    @Test("A saved analysis comes back as loaded")
    func savedComesBack() {
        guard case .loaded(let explanation, let score, _, let bestUse) =
                AppInfo.AIState.saved(explanation: "Edits photos.", score: 4, reason: "fits", bestUse: nil) else {
            Issue.record("expected the saved analysis"); return
        }
        #expect(explanation == "Edits photos.")
        #expect(score == 4)
        #expect(bestUse == "")
    }

    @Test("No saved analysis means pending, never loading")
    func nothingSaved() {
        if case .pending = AppInfo.AIState.saved(explanation: nil, score: 0, reason: "", bestUse: nil) {} else {
            Issue.record("expected pending")
        }
        if case .pending = AppInfo.AIState.saved(explanation: "", score: 0, reason: "", bestUse: nil) {} else {
            Issue.record("expected pending")
        }
    }
}

@Suite("Cancel after brew uninstall drops the removed app (b3b1)")
struct CancelAfterBrewTests {
    @Test("Cancel reports the app removed only when brew removed it")
    func cancelReports() {
        #expect(BrewUninstallFooter.cancelReportsRemoved(homebrewRemovedTheApp: true))
        #expect(!BrewUninstallFooter.cancelReportsRemoved(homebrewRemovedTheApp: false))
        // With leftovers still checked the footer offers Cancel, not Done.
        #expect(BrewUninstallFooter.action(homebrewRemovedTheApp: true, anythingChecked: true) == .moveToTrash)
    }
}

@Suite("No Analyzed date for an app that was never analyzed (b3b1)")
struct AnalyzedDateTests {
    @Test("A record holding only marks shows no Analyzed date")
    func stubHasNone() {
        let stub = AppRecord(stub: "com.example.app", appName: "Example")
        #expect(AppFacts.analyzedDate(generatedAt: stub.generatedAt, explanation: stub.explanation) == nil)
        let now = Date()
        #expect(AppFacts.analyzedDate(generatedAt: now, explanation: "A notes app.") == now)
        #expect(AppFacts.analyzedDate(generatedAt: nil, explanation: "A notes app.") == nil)
    }
}

@Suite("A big linked file is not read in full (b3b1)")
struct CappedDownloadTests {
    private func stream(_ count: Int) -> AsyncStream<UInt8> {
        AsyncStream { continuation in
            for i in 0..<count { continuation.yield(UInt8(i % 256)) }
            continuation.finish()
        }
    }

    @Test("A page stops at the limit")
    func truncates() async throws {
        let data = try await CappedDownload.collect(stream(5_000), limit: 1_000, overLimit: .truncate)
        #expect(data.count == 1_000)
    }

    @Test("A feed over the limit is refused, one under it is whole")
    func failsOverLimit() async throws {
        await #expect(throws: URLError.self) {
            _ = try await CappedDownload.collect(stream(5_000), limit: 1_000, overLimit: .fail)
        }
        let whole = try await CappedDownload.collect(stream(900), limit: 1_000, overLimit: .fail)
        #expect(whole.count == 900)
        let exact = try await CappedDownload.collect(stream(1_000), limit: 1_000, overLimit: .fail)
        #expect(exact.count == 1_000)
    }
}

@Suite("A failed page fetch is tried again when the user asks (b3b1)")
struct LinkEvidenceRetryTests {
    @Test("Never fetched: fetch. Worked: keep. Failed: only when the user asked")
    func rules() {
        #expect(LinkEvidenceService.shouldFetch(cached: nil, retryingFailure: false))
        #expect(!LinkEvidenceService.shouldFetch(cached: .some("Words"), retryingFailure: true))
        #expect(!LinkEvidenceService.shouldFetch(cached: .some(nil), retryingFailure: false))
        #expect(LinkEvidenceService.shouldFetch(cached: .some(nil), retryingFailure: true))
    }
}

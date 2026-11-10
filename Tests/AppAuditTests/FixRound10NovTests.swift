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

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

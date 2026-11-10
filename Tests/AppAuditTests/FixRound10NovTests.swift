import Testing
import Foundation
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

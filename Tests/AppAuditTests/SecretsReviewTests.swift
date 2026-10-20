import Testing
import Foundation
@testable import Sift

/// Fixes from the 2026-10-20 review of how Sift keeps secrets. Every test here
/// runs on in-memory backends: none of them touches the login Keychain.

@Suite("License key save honesty")
struct LicenseKeySaveHonestyTests {
    @Test("save reports a Keychain write that failed")
    func refusedWriteIsNotSaved() {
        let store = LicenseKeyStore(backend: DroppingSecretStoreBackend())
        #expect(!store.save("ABC-123", bundleID: "com.example.app"))
        #expect(!store.hasKey(bundleID: "com.example.app"))
    }

    @Test("save reports a stored key, trimmed")
    func storedWriteIsSaved() {
        let backend = MemorySecretStoreBackend()
        let store = LicenseKeyStore(backend: backend)
        #expect(store.save("  ABC-123  ", bundleID: "com.example.app"))
        #expect(backend.read(account: "com.example.app") == "ABC-123")
    }

    @Test("A blank save deletes and counts as done")
    func blankSaveDeletes() {
        let backend = MemorySecretStoreBackend()
        let store = LicenseKeyStore(backend: backend)
        store.save("ABC-123", bundleID: "com.example.app")
        #expect(store.save("   ", bundleID: "com.example.app"))
        #expect(backend.read(account: "com.example.app") == nil)
    }
}

/// Counts how often the secret itself is read, so a test can prove that a
/// check never touched a key value.
final class ReadCountingSecretStoreBackend: SecretStoreBackend, @unchecked Sendable {
    private var values: [String: String] = [:]
    private(set) var secretReads = 0

    func read(account: String) -> String? {
        secretReads += 1
        return values[account]
    }

    func exists(account: String) -> Bool { values[account] != nil }

    @discardableResult
    func write(_ value: String, account: String) -> Bool {
        values[account] = value
        return true
    }

    func delete(account: String) { values.removeValue(forKey: account) }
}

@Suite("No license key read without Touch ID")
struct LicenseKeyAttributeOnlyTests {
    @Test("hasKey answers from attributes and never reads the key")
    func hasKeyIsAttributeOnly() {
        let backend = ReadCountingSecretStoreBackend()
        let store = LicenseKeyStore(backend: backend)
        #expect(!store.hasKey(bundleID: "com.example.app"))
        store.save("ABC-123", bundleID: "com.example.app")
        #expect(store.hasKey(bundleID: "com.example.app"))
        #expect(backend.secretReads == 0)
    }

    @Test("The launch migration of a legacy key reads no stored key")
    func migrationIsAttributeOnly() {
        let backend = ReadCountingSecretStoreBackend()
        let store = LicenseKeyStore(backend: backend)
        store.save("SECURE", bundleID: "com.example.kept")

        #expect(store.migrateLegacyKey("LEGACY", bundleID: "com.example.moved"))
        #expect(store.migrateLegacyKey("LEGACY", bundleID: "com.example.kept"))
        #expect(backend.secretReads == 0)
    }

    @Test("Only resolveKey, called after Touch ID, reads the key")
    func resolveReads() {
        let backend = ReadCountingSecretStoreBackend()
        let store = LicenseKeyStore(backend: backend)
        store.save("ABC-123", bundleID: "com.example.app")
        #expect(store.resolveKey(bundleID: "com.example.app", legacyValue: nil).value == "ABC-123")
        #expect(backend.secretReads == 1)
    }
}

/// A fresh, empty UserDefaults suite per test, standing in for the plist.
private func scratchDefaults(_ name: String = #function) -> UserDefaults {
    let suite = "SiftTests.APIKeys.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Suite("Cloud API keys in the Keychain")
struct APIKeyStoreTests {
    @Test("A plist key moves into the Keychain and leaves the plist")
    func migratesPlistKey() {
        let defaults = scratchDefaults()
        defaults.set("  sk-ant-123  ", forKey: AnalysisProviderKind.anthropic.apiKeyDefaultsKey)
        defaults.set("gem-456", forKey: AnalysisProviderKind.gemini.apiKeyDefaultsKey)
        let backend = MemorySecretStoreBackend()
        let store = APIKeyStore(backend: backend, defaults: defaults)

        let moved = store.migrateFromDefaults()

        #expect(Set(moved) == [.anthropic, .gemini])
        #expect(backend.read(account: AnalysisProviderKind.anthropic.apiKeyAccount) == "sk-ant-123")
        #expect(defaults.object(forKey: AnalysisProviderKind.anthropic.apiKeyDefaultsKey) == nil)
        #expect(defaults.object(forKey: AnalysisProviderKind.gemini.apiKeyDefaultsKey) == nil)
        #expect(store.key(for: .anthropic) == "sk-ant-123")
    }

    @Test("A failed Keychain write leaves the plist key, and it keeps working")
    func failedWriteKeepsPlistKey() {
        let defaults = scratchDefaults()
        defaults.set("sk-openai", forKey: AnalysisProviderKind.openAI.apiKeyDefaultsKey)
        let store = APIKeyStore(backend: DroppingSecretStoreBackend(), defaults: defaults)

        #expect(store.migrateFromDefaults().isEmpty)
        #expect(defaults.string(forKey: AnalysisProviderKind.openAI.apiKeyDefaultsKey) == "sk-openai")
        #expect(store.key(for: .openAI) == "sk-openai")
    }

    @Test("An emptied plist field is dropped without a Keychain write")
    func emptyPlistValueDropped() {
        let defaults = scratchDefaults()
        defaults.set("  ", forKey: AnalysisProviderKind.openRouter.apiKeyDefaultsKey)
        let backend = MemorySecretStoreBackend()
        let store = APIKeyStore(backend: backend, defaults: defaults)

        #expect(store.migrateFromDefaults().isEmpty)
        #expect(defaults.object(forKey: AnalysisProviderKind.openRouter.apiKeyDefaultsKey) == nil)
        #expect(backend.read(account: AnalysisProviderKind.openRouter.apiKeyAccount) == nil)
    }

    @Test("Settings writes to the Keychain only, and a blank field removes the key")
    func setKeyWritesKeychainOnly() {
        let defaults = scratchDefaults()
        let backend = MemorySecretStoreBackend()
        let store = APIKeyStore(backend: backend, defaults: defaults)

        #expect(store.setKey(" ollama-cloud ", for: .ollama))
        #expect(backend.read(account: AnalysisProviderKind.ollama.apiKeyAccount) == "ollama-cloud")
        #expect(defaults.object(forKey: AnalysisProviderKind.ollama.apiKeyDefaultsKey) == nil)
        #expect(store.key(for: .ollama) == "ollama-cloud")

        #expect(store.setKey("", for: .ollama))
        #expect(store.key(for: .ollama) == "")
    }

    @Test("A blank field also clears a plist key a failed migration left behind")
    func blankClearsLeftoverPlistKey() {
        let defaults = scratchDefaults()
        defaults.set("old", forKey: AnalysisProviderKind.anthropic.apiKeyDefaultsKey)
        let store = APIKeyStore(backend: MemorySecretStoreBackend(), defaults: defaults)

        store.setKey("", for: .anthropic)

        #expect(store.key(for: .anthropic) == "")
        #expect(defaults.object(forKey: AnalysisProviderKind.anthropic.apiKeyDefaultsKey) == nil)
    }

    @Test("Each provider has its own Keychain account, and each build its own service")
    func distinctAccountsAndServices() {
        let accounts = AnalysisProviderKind.allCases.map(\.apiKeyAccount)
        #expect(Set(accounts).count == accounts.count)
        #expect(BuildVariant.primary.apiKeyKeychainService != BuildVariant.sift2.apiKeyKeychainService)
        #expect(BuildVariant.primary.apiKeyKeychainService != BuildVariant.primary.keychainService)
    }
}

@Suite("Settings API key field")
@MainActor
struct APIKeyFieldTests {
    @Test("The field loads per provider and saves each edit to the Keychain")
    func loadsAndSaves() {
        let backend = MemorySecretStoreBackend()
        backend.write("gem-1", account: AnalysisProviderKind.gemini.apiKeyAccount)
        let field = APIKeyField(store: APIKeyStore(backend: backend, defaults: scratchDefaults()))

        field.load(.gemini)
        #expect(field.text == "gem-1")

        field.load(.openAI)
        #expect(field.text == "")
        field.update("sk-new")
        #expect(!field.saveFailed)
        #expect(backend.read(account: AnalysisProviderKind.openAI.apiKeyAccount) == "sk-new")
        #expect(backend.read(account: AnalysisProviderKind.gemini.apiKeyAccount) == "gem-1")
    }

    @Test("A refused write is shown, not hidden")
    func refusedWriteShows() {
        let field = APIKeyField(store: APIKeyStore(backend: DroppingSecretStoreBackend(), defaults: scratchDefaults()))
        field.load(.anthropic)
        field.update("sk-ant")
        #expect(field.saveFailed)
    }
}

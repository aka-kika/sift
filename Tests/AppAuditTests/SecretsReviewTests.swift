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

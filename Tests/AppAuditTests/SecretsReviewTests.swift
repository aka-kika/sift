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

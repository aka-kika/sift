import Foundation
import Security

protocol SecretStoreBackend: Sendable {
    func read(account: String) -> String?
    /// Returns whether the value is now stored. A denied ACL prompt or a locked
    /// keychain must not read as success — callers delete plaintext on that basis.
    @discardableResult
    func write(_ value: String, account: String) -> Bool
    func delete(account: String)
}

final class KeychainSecretStoreBackend: SecretStoreBackend, @unchecked Sendable {
    private let service: String

    init(service: String = KeychainSecretStoreBackend.defaultService) {
        self.service = service
    }

    /// Keychain service name for license keys. Side-builds (e.g. the AppAudit2 test
    /// app) use their own service so they never read or prompt for the primary app's
    /// keys. The primary app keeps the historical service name.
    static var defaultService: String { BuildVariant.current.keychainService }

    func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    @discardableResult
    func write(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Device-bound: not synced to iCloud Keychain, only available while unlocked.
        let accessibility = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var createQuery = query
            createQuery[kSecValueData as String] = data
            createQuery[kSecAttrAccessible as String] = accessibility
            return SecItemAdd(createQuery as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct LicenseKeyResolution: Equatable {
    let value: String?
    let didMigrateLegacyValue: Bool
}

final class LicenseKeyStore: @unchecked Sendable {
    static let shared = LicenseKeyStore()

    private let backend: SecretStoreBackend

    init(backend: SecretStoreBackend = KeychainSecretStoreBackend()) {
        self.backend = backend
    }

    func resolveKey(bundleID: String, legacyValue: String?) -> LicenseKeyResolution {
        if let existing = backend.read(account: bundleID), !existing.isEmpty {
            return LicenseKeyResolution(value: existing, didMigrateLegacyValue: false)
        }

        let trimmedLegacy = legacyValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedLegacy.isEmpty else {
            return LicenseKeyResolution(value: nil, didMigrateLegacyValue: false)
        }

        let migrated = backend.write(trimmedLegacy, account: bundleID) && hasKey(bundleID: bundleID)
        return LicenseKeyResolution(value: trimmedLegacy, didMigrateLegacyValue: migrated)
    }

    func save(_ value: String?, bundleID: String) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            backend.delete(account: bundleID)
        } else {
            backend.write(trimmed, account: bundleID)
        }
    }

    func delete(bundleID: String) {
        backend.delete(account: bundleID)
    }

    /// True when a non-empty key is stored for this bundle ID. Reads the Keychain
    /// item; for the app that owns the items this does not prompt.
    func hasKey(bundleID: String) -> Bool {
        guard let value = backend.read(account: bundleID) else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Moves a legacy plaintext value into secure storage if no key exists yet.
    /// Returns whether a key is present afterwards, so the caller can clear the
    /// legacy field.
    @discardableResult
    func migrateLegacyKey(_ legacyValue: String?, bundleID: String) -> Bool {
        let trimmed = legacyValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !hasKey(bundleID: bundleID), !trimmed.isEmpty {
            save(trimmed, bundleID: bundleID)
        }
        return hasKey(bundleID: bundleID)
    }
}

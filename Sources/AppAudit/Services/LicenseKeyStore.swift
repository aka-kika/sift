import Foundation
import Security

/// What an attribute-only Keychain lookup actually answered.
/// `unknown` is a locked or denied keychain: that is not the same as no item.
enum SecretPresence: Equatable, Sendable {
    case present
    case absent
    case unknown
}

protocol SecretStoreBackend: Sendable {
    /// Reads the secret itself. License keys call this only after Touch ID.
    func read(account: String) -> String?
    /// Whether an item exists, from its attributes alone: the secret is never
    /// read, so this is safe at launch and at render time.
    func exists(account: String) -> Bool
    /// Same lookup as `exists`, but a Keychain error stays `unknown` instead
    /// of looking like a missing item. Default treats a bool backend as sure.
    func presence(account: String) -> SecretPresence
    /// Returns whether the value is now stored. A denied ACL prompt or a locked
    /// keychain must not read as success — callers delete plaintext on that basis.
    @discardableResult
    func write(_ value: String, account: String) -> Bool
    func delete(account: String)
}

extension SecretStoreBackend {
    func presence(account: String) -> SecretPresence {
        exists(account: account) ? .present : .absent
    }
}

/// Items live in the login (file-based) keychain, without a SecAccessControl.
/// Sift is a Developer ID app with no provisioning profile, so it has no
/// keychain access group: the data protection keychain, and a userPresence
/// access control on any keychain, both fail with errSecMissingEntitlement
/// (-34018; checked on macOS 26.6 with a hardened-runtime Developer ID build).
/// Touch ID is therefore Sift's own gate before it reads a key, not a lock on
/// the item, and every "is there a key" check must stay attribute-only.
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

    func exists(account: String) -> Bool {
        presence(account: account) == .present
    }

    func presence(account: String) -> SecretPresence {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return Self.presence(for: status)
    }

    /// Only `errSecItemNotFound` means there is no key. A locked keychain
    /// (`errSecInteractionNotAllowed`) or a denied lookup must not clear it.
    static func presence(for status: OSStatus) -> SecretPresence {
        switch status {
        case errSecSuccess: return .present
        case errSecItemNotFound: return .absent
        default: return .unknown
        }
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

    /// Returns whether the Keychain now holds the key. A failed write must not
    /// read as saved: callers flip the record's flag and drop the typed key on
    /// `true` only, or the key is lost. A blank value deletes and counts as done.
    @discardableResult
    func save(_ value: String?, bundleID: String) -> Bool {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            backend.delete(account: bundleID)
            return true
        }
        return backend.write(trimmed, account: bundleID)
    }

    func delete(bundleID: String) {
        backend.delete(account: bundleID)
    }

    /// True when a key is stored for this bundle ID. Looks at the item's
    /// attributes only and never reads the key, so the launch sweep and the
    /// vault can call it without Touch ID. `save` never stores a blank key, so
    /// an existing item is a real one.
    func hasKey(bundleID: String) -> Bool {
        keyPresence(bundleID: bundleID) == .present
    }

    /// Launch sync uses this. `unknown` means leave the saved flag alone.
    func keyPresence(bundleID: String) -> SecretPresence {
        backend.presence(account: bundleID)
    }

    /// The flag to store after a launch lookup. An error keeps whatever the
    /// record already says, so a locked keychain cannot hide a purchase.
    static func flag(current: Bool, presence: SecretPresence) -> Bool {
        switch presence {
        case .present: return true
        case .absent: return false
        case .unknown: return current
        }
    }

    /// Moves a legacy plaintext value into secure storage if no key exists yet.
    /// Returns whether a key is present afterwards, so the caller can clear the
    /// legacy field.
    @discardableResult
    func migrateLegacyKey(_ legacyValue: String?, bundleID: String) -> Bool {
        let trimmed = legacyValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !hasKey(bundleID: bundleID), !trimmed.isEmpty {
            guard save(trimmed, bundleID: bundleID) else { return false }
        }
        return hasKey(bundleID: bundleID)
    }
}

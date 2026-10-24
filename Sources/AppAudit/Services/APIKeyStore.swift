import Foundation
import Observation

/// Cloud API keys (Anthropic, OpenAI, Gemini, OpenRouter, ollama.com) in the
/// Keychain, one item per provider under this build's own service. No Touch ID:
/// the app reads a key each time it calls the provider. Builds up to 1.12.3 kept
/// them in plain text in the preferences plist; `migrateFromDefaults` moves them.
final class APIKeyStore: @unchecked Sendable {
    static let shared = APIKeyStore()

    private let backend: SecretStoreBackend
    private let defaults: UserDefaults

    init(backend: SecretStoreBackend = KeychainSecretStoreBackend(service: BuildVariant.current.apiKeyKeychainService),
         defaults: UserDefaults = .standard) {
        self.backend = backend
        self.defaults = defaults
    }

    /// The provider's key, trimmed, or "" when none is set. A plist key that
    /// could not move into the Keychain yet keeps working until it does.
    func key(for kind: AnalysisProviderKind) -> String {
        let stored = backend.read(account: kind.apiKeyAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stored.isEmpty { return stored }
        return (defaults.string(forKey: kind.apiKeyDefaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Stores a key typed in Settings; a blank one removes it. Returns whether
    /// the Keychain now holds what was typed. Any old plist copy goes once the
    /// Keychain has the new key, or with a removal, so it can never come back.
    @discardableResult
    func setKey(_ value: String, for kind: AnalysisProviderKind) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            backend.delete(account: kind.apiKeyAccount)
            defaults.removeObject(forKey: kind.apiKeyDefaultsKey)
            return true
        }
        guard backend.write(trimmed, account: kind.apiKeyAccount) else { return false }
        defaults.removeObject(forKey: kind.apiKeyDefaultsKey)
        return true
    }

    /// Runs at launch: moves keys an older build left in the preferences plist
    /// into the Keychain. The plist copy is removed only once the Keychain
    /// verifiably holds the same key; a failed write leaves it where it was.
    /// A plist key wins over a Keychain one, because only an older build writes
    /// the plist, so it is the newer of the two. Returns the providers moved.
    @discardableResult
    func migrateFromDefaults() -> [AnalysisProviderKind] {
        var moved: [AnalysisProviderKind] = []
        for kind in AnalysisProviderKind.allCases {
            guard let legacy = defaults.string(forKey: kind.apiKeyDefaultsKey) else { continue }
            let trimmed = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                // An emptied field: nothing secret to move.
                defaults.removeObject(forKey: kind.apiKeyDefaultsKey)
                continue
            }
            guard backend.write(trimmed, account: kind.apiKeyAccount),
                  backend.read(account: kind.apiKeyAccount) == trimmed else { continue }
            defaults.removeObject(forKey: kind.apiKeyDefaultsKey)
            moved.append(kind)
        }
        return moved
    }
}

/// The API key field in Settings. The stored key is never shown. Typing
/// changes a draft only; the Keychain is written when the field is left or
/// Return is pressed, so one Backspace cannot save a cut-off key.
@MainActor
@Observable
final class APIKeyField {
    private(set) var text = ""
    private(set) var saveFailed = false
    private(set) var hasStoredKey = false
    private(set) var kind: AnalysisProviderKind = .ollama
    private var edited = false
    private let store: APIKeyStore

    init(store: APIKeyStore = .shared) {
        self.store = store
    }

    /// The field starts empty. `hasStoredKey` is how the screen says a key
    /// is already saved, without putting that key in the field.
    func load(_ kind: AnalysisProviderKind) {
        self.kind = kind
        text = ""
        edited = false
        hasStoredKey = !store.key(for: kind).isEmpty
        saveFailed = false
    }

    /// The draft. Does not touch the Keychain.
    func update(_ newValue: String) {
        guard newValue != text else { return }
        text = newValue
        edited = true
        saveFailed = false
    }

    /// Write the draft. An untouched empty field does not remove a saved key.
    func commit() {
        guard edited else { return }
        let ok = store.setKey(text, for: kind)
        saveFailed = !ok
        guard ok else { return }
        edited = false
        hasStoredKey = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        text = ""
    }

    /// Remove Key: deletes the saved key and drops any draft.
    func remove() {
        store.setKey("", for: kind)
        text = ""
        edited = false
        saveFailed = false
        hasStoredKey = !store.key(for: kind).isEmpty
    }
}

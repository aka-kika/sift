import Foundation

/// Pure availability rules for the utility cards in the app detail view.
/// A disabled card stays visible (grayed) and keeps its data; these rules
/// only decide interactivity and the reason hint shown on the card.
enum UtilityCardRules {
    static func licenseDisabled(isMyApp: Bool, isFreeApp: Bool) -> Bool {
        isMyApp || isFreeApp
    }

    static func subscriptionDisabled(isMyApp: Bool, isFreeApp: Bool, licenseType: LicenseType?) -> Bool {
        isMyApp || isFreeApp || (licenseType?.coversForever ?? false)
    }

    /// The one-line reason shown on a grayed card. The app being yours beats
    /// free, which beats the license type.
    static func disabledReason(isMyApp: Bool, isFreeApp: Bool, licenseType: LicenseType?) -> String? {
        if isMyApp { return "Your app" }
        if isFreeApp { return "Free app" }
        if let licenseType, licenseType.coversForever {
            return "\(licenseType.displayName) license"
        }
        return nil
    }
}

/// What counts as a saveable license edit. The key is not the only payload:
/// the license type stands on its own, so an App Store purchase — which never
/// carries a key — can still be recorded as Lifetime, and a wrong type can be
/// corrected or cleared back to Not set.
enum LicenseDraftRules {
    static func hasSomethingToSave(key: String,
                                   email: String,
                                   type: LicenseType?,
                                   hasKey: Bool,
                                   currentType: LicenseType?) -> Bool {
        if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if hasKey { return true }
        if type != currentType { return true }
        if !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }

    enum KeyAction: Equatable {
        /// Leave the saved key (or the absence of one) as it is.
        case keep
        case save(String)
    }

    /// What Save does to the Keychain. A saved key stays locked until the
    /// panel unlocks it (Reveal or Replace, each after Touch ID), and a locked
    /// field says nothing about the key, so it is kept. An empty field never
    /// deletes a key: removing one is the trash button, behind Touch ID.
    static func keyAction(draft: String, hasSavedKey: Bool, keyEditable: Bool) -> KeyAction {
        guard keyEditable || !hasSavedKey else { return .keep }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .keep : .save(trimmed)
    }
}

/// A revealed licence key stays in memory only while the panel is open.
/// Touch ID closes the panel for a moment; that gap is not a close.
enum RevealedLicenseKey {
    static func shouldForget(popoverOpen: Bool, waitingForTouchID: Bool) -> Bool {
        !popoverOpen && !waitingForTouchID
    }
}

/// A first key typed for an app with no saved key, kept when the panel closes
/// before Save so a click outside does not lose it. It comes back for that
/// same app only. A revealed or replacing key is never kept.
struct UnsavedLicenseKeyDraft: Equatable {
    let bundleID: String
    let key: String

    static func keep(draft: String, hasSavedKey: Bool, bundleID: String) -> UnsavedLicenseKeyDraft? {
        guard !hasSavedKey, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return UnsavedLicenseKeyDraft(bundleID: bundleID, key: draft)
    }

    func restored(for bundleID: String, hasSavedKey: Bool) -> String? {
        guard bundleID == self.bundleID, !hasSavedKey else { return nil }
        return key
    }
}

/// Replace on a saved licence key. Touch ID has to succeed before the field
/// opens empty; otherwise Save could overwrite the key from an unlocked Mac.
enum LicenseKeyReplace {
    static func mayUnlock(authenticated: Bool) -> Bool {
        authenticated
    }
}

/// Free and Paid are mutually exclusive marks; applying one clears the other.
/// Unmarking never sets the opposite.
enum PricingMarks {
    static func setFree(_ record: AppRecord, to free: Bool) {
        record.isFreeApp = free
        if free { record.isPaidApp = false }
    }

    static func setPaid(_ record: AppRecord, to paid: Bool) {
        record.isPaidApp = paid
        if paid { record.isFreeApp = false }
    }
}


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


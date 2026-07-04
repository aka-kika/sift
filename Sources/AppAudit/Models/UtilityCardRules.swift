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

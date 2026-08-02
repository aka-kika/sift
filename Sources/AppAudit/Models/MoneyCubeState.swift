import Foundation

/// The face of the merged License cube — one cube owns App Store ownership,
/// license keys, paid/free marks, and subscriptions. Precedence:
/// subscription > App Store > licensed/paid > free > none. App Store
/// outranks licensed because store installs never carry license keys —
/// unless you have recorded what kind of purchase it was, in which case
/// "Lifetime" is the more useful face and the seal moves to the popover.
enum MoneyCubeState: Equatable {
    case subscription(renewalNear: Bool)
    case appStore
    case licensed(LicenseType?)
    case free
    case none

    static func derive(isAppStoreInstall: Bool,
                       hasLicenseKey: Bool,
                       isPaidApp: Bool,
                       hasSubscription: Bool,
                       renewalNear: Bool,
                       isFreeApp: Bool,
                       licenseType: LicenseType? = nil) -> MoneyCubeState {
        if hasSubscription { return .subscription(renewalNear: renewalNear) }
        if isAppStoreInstall {
            if let licenseType { return .licensed(licenseType) }
            return .appStore
        }
        if hasLicenseKey || isPaidApp || licenseType != nil { return .licensed(licenseType) }
        if isFreeApp { return .free }
        return .none
    }

    /// Licensed apps wear their license type on the cube face, so the kind
    /// of purchase is readable at a glance without opening the popover.
    var symbol: String {
        switch self {
        case .subscription: return "creditcard.fill"
        case .appStore: return "checkmark.seal.fill"
        case .licensed(let type):
            switch type {
            case .lifetime: return "infinity"
            case .oneTime: return "1.circle"
            case .annual: return "calendar"
            case .other, .none: return "key.horizontal"
            }
        case .free: return "gift"
        case .none: return "dollarsign.circle"
        }
    }

    /// Active states fill the cube with their tint; only "nothing known
    /// yet" stays quiet — a Free mark is information worth showing.
    var isActive: Bool {
        switch self {
        case .subscription, .appStore, .licensed, .free: return true
        case .none: return false
        }
    }
}

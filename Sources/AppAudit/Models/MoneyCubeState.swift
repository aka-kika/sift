import Foundation

/// The face of the merged Money cube — one cube owns App Store ownership,
/// license keys, paid/free marks, and subscriptions. Precedence:
/// subscription > App Store > licensed/paid > free > none. App Store
/// outranks licensed because store installs never carry license keys.
enum MoneyCubeState: Equatable {
    case subscription(renewalNear: Bool)
    case appStore
    case licensed
    case free
    case none

    static func derive(isAppStoreInstall: Bool,
                       hasLicenseKey: Bool,
                       isPaidApp: Bool,
                       hasSubscription: Bool,
                       renewalNear: Bool,
                       isFreeApp: Bool) -> MoneyCubeState {
        if hasSubscription { return .subscription(renewalNear: renewalNear) }
        if isAppStoreInstall { return .appStore }
        if hasLicenseKey || isPaidApp { return .licensed }
        if isFreeApp { return .free }
        return .none
    }

    var symbol: String {
        switch self {
        case .subscription: return "creditcard.fill"
        case .appStore: return "checkmark.seal.fill"
        case .licensed: return "key.horizontal"
        case .free: return "gift"
        case .none: return "dollarsign.circle"
        }
    }

    /// Active states fill the cube with their tint; free/none stay quiet.
    var isActive: Bool {
        switch self {
        case .subscription, .appStore, .licensed: return true
        case .free, .none: return false
        }
    }
}

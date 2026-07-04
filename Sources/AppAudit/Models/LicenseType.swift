import Foundation

/// How an app's license was purchased. Drives the subscription card's
/// availability in the detail view: a license that covers the app forever
/// makes a subscription moot.
enum LicenseType: String, CaseIterable, Identifiable {
    case lifetime
    case oneTime = "one-time"
    case annual
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lifetime: return "Lifetime"
        case .oneTime: return "One-time"
        case .annual: return "Annual"
        case .other: return "Other"
        }
    }

    /// True when this license covers the app permanently, so a subscription
    /// cannot apply on top of it.
    var coversForever: Bool {
        self == .lifetime || self == .oneTime
    }
}

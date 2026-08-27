import Foundation

/// Which build this process is: the daily Sift, or the throwaway Sift2 side-build
/// that must never touch the primary app's data, Keychain items, or itself.
enum BuildVariant: Equatable {
    case primary
    case sift2

    static let primaryBundleID = "com.kikaapp.appaudit"   // historical; kept for data continuity
    static let sift2BundleID = "com.kikaapp.sift2"

    static var current: BuildVariant { BuildVariant(bundleIdentifier: Bundle.main.bundleIdentifier) }

    init(bundleIdentifier: String?) {
        self = bundleIdentifier == Self.sift2BundleID ? .sift2 : .primary
    }

    /// Folder under Application Support for the SwiftData store.
    var dataFolderName: String {
        switch self {
        case .primary: return "AppAudit"
        case .sift2: return "Sift2"
        }
    }

    /// Keychain service for stored license keys — separate per variant so the
    /// side-build never reads or prompts for the primary app's keys.
    var keychainService: String {
        switch self {
        case .primary: return "com.kikaapp.appaudit.licensekeys"
        case .sift2: return "com.kikaapp.sift2.licensekeys"
        }
    }

    /// Both Sift bundles: the uninstaller refuses to remove either.
    static func isSiftItself(_ bundleID: String) -> Bool {
        bundleID == primaryBundleID || bundleID == sift2BundleID
    }
}

import Foundation

#if canImport(AppKit)
import AppKit
#endif

/// Wrap a platform image so `AppInfo` stays sendable without forcing AppKit everywhere.
struct SendableImage: @unchecked Sendable {
#if canImport(AppKit)
    let image: NSImage
#endif
}

struct AppInfo: Identifiable {
    let id: String          // bundleID
    let name: String
    let version: String
    let bundleID: String
    let path: String
    let humanReadableDescription: String?
    let sparkleFeedURL: String?
    let isAppStoreInstall: Bool
    let icon: SendableImage?

    var aiState: AIState = .pending
    var updateState: UpdateState = .unknown
    var isMyApp: Bool = false
    var isFavorite: Bool = false

    enum AIState: Sendable {
        case pending
        case loading
        case loaded(explanation: String, score: Int, reason: String, bestUse: String)
        case unavailable(String)
    }

    enum UpdateSource: String, Sendable {
        case appStore = "App Store"
        case sparkle = "Sparkle"
    }

    enum UpdateState: Sendable, Equatable {
        case unknown
        case checking
        case upToDate(source: UpdateSource)
        case updateAvailable(latestVersion: String, source: UpdateSource, actionURL: String?)
        case unavailable
    }
}

extension AppInfo.AIState {
    var score: Int? {
        if case .loaded(_, let s, _, _) = self { return s }
        return nil
    }
}

extension AppInfo.UpdateState {
    var actionURL: URL? {
        guard case .updateAvailable(_, _, let actionURLString) = self,
              let actionURLString,
              let url = URL(string: actionURLString) else {
            return nil
        }
        return url
    }
}

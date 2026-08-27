import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

/// Sift's own updater — Sparkle 2, fed by https://sift.akakika.com/appcast.xml.
///
/// One controller for the whole app, created before launch finishes so Sparkle can
/// run its scheduled check. The feed URL and the EdDSA public key live in Info.plist
/// (written by Scripts/package_app.sh); this type only exposes the two things the
/// UI needs — "check now" and whether a check is currently possible.
///
/// Debug builds run from `swift run` carry no Info.plist keys, so the controller is
/// created with `startingUpdater: false` there and `checkForUpdates()` is a no-op;
/// the packaged app (Sift.app / Sift2.app) is the only place updates are real.
@MainActor
final class UpdateService {
    static let shared = UpdateService()

    #if canImport(Sparkle)
    private let controller: SPUStandardUpdaterController
    #endif

    private init() {
        #if canImport(Sparkle)
        let hasFeed = Self.feedIsConfigured(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL"))
        controller = SPUStandardUpdaterController(startingUpdater: hasFeed,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        #endif
    }

    /// True when the app was packaged with a feed (i.e. not a bare `swift run`).
    var isAvailable: Bool {
        Self.feedIsConfigured(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL"))
    }

    /// An Info.plist value counts as a feed only when it is a non-blank string —
    /// the packaging script may write the key with an empty value.
    nonisolated static func feedIsConfigured(_ value: Any?) -> Bool {
        guard let string = value as? String else { return false }
        return !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether Sparkle would accept a user-initiated check right now.
    var canCheck: Bool {
        #if canImport(Sparkle)
        return isAvailable && controller.updater.canCheckForUpdates
        #else
        return false
        #endif
    }

    /// User-initiated check: always shows a result, including "up to date".
    func checkForUpdates() {
        #if canImport(Sparkle)
        guard isAvailable else { return }
        controller.checkForUpdates(nil)
        #endif
    }
}

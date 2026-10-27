import Foundation
import AppKit

/// Wrap a platform image so `AppInfo` stays sendable without forcing AppKit everywhere.
struct SendableImage: @unchecked Sendable {
    let image: NSImage
}

extension SendableImage {
    /// Small PNG of the app icon, cached on records that hold a license key so
    /// the Vault can still show the icon after the app is uninstalled.
    func pngData(side: CGFloat = 64) -> Data? {
        let target = NSImage(size: NSSize(width: side, height: side))
        target.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                   from: .zero, operation: .copy, fraction: 1.0)
        target.unlockFocus()
        guard let tiff = target.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

struct AppInfo: Identifiable {
    /// Unique per installed copy (the scanner passes the bundle path). Row
    /// identity and selection only — records are keyed by `bundleID`.
    let id: String
    let name: String
    let version: String
    /// `CFBundleVersion`. Only used to tell two releases apart when the vendor
    /// ships a new build under an unchanged marketing version.
    let build: String?
    let bundleID: String
    let path: String
    let humanReadableDescription: String?
    let sparkleFeedURL: String?
    let isAppStoreInstall: Bool
    let homebrewCaskToken: String?
    let icon: SendableImage?
    let category: String?
    let lastUsedDate: Date?
    /// When the app arrived in its folder (Spotlight's "Date Added"), for the
    /// Last Added sort.
    let addedDate: Date?
    let runtime: AppRuntime?

    var isRunning: Bool = false
    var aiState: AIState = .pending
    var updateState: UpdateState = .unknown
    var isMyApp: Bool = false
    var isFavorite: Bool = false
    var isSubscribed: Bool = false
    var isPaidApp: Bool = false
    var isAnalysisLocked: Bool = false
    var isFreeApp: Bool = false
    var licenseTypeRaw: String? = nil
    /// Mirrors `AppRecord.hasLicenseKey` so a sidebar row can show its badge
    /// without a SwiftData fetch or a Keychain read on every render.
    var hasLicenseKey: Bool = false

    var licenseType: LicenseType? {
        licenseTypeRaw.flatMap(LicenseType.init(rawValue:))
    }

    init(
        id: String,
        name: String,
        version: String,
        build: String? = nil,
        bundleID: String,
        path: String,
        humanReadableDescription: String?,
        sparkleFeedURL: String?,
        isAppStoreInstall: Bool,
        homebrewCaskToken: String? = nil,
        icon: SendableImage?,
        category: String? = nil,
        lastUsedDate: Date? = nil,
        addedDate: Date? = nil,
        runtime: AppRuntime? = nil,
        isRunning: Bool = false,
        aiState: AIState = .pending,
        updateState: UpdateState = .unknown,
        isMyApp: Bool = false,
        isFavorite: Bool = false,
        isSubscribed: Bool = false,
        isPaidApp: Bool = false,
        isAnalysisLocked: Bool = false
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.build = build
        self.bundleID = bundleID
        self.path = path
        self.humanReadableDescription = humanReadableDescription
        self.sparkleFeedURL = sparkleFeedURL
        self.isAppStoreInstall = isAppStoreInstall
        self.homebrewCaskToken = homebrewCaskToken
        self.icon = icon
        self.category = category
        self.lastUsedDate = lastUsedDate
        self.addedDate = addedDate
        self.runtime = runtime
        self.isRunning = isRunning
        self.aiState = aiState
        self.updateState = updateState
        self.isMyApp = isMyApp
        self.isFavorite = isFavorite
        self.isSubscribed = isSubscribed
        self.isPaidApp = isPaidApp
        self.isAnalysisLocked = isAnalysisLocked
    }

    enum AIState: Sendable {
        case pending
        case loading
        case loaded(explanation: String, score: Int, reason: String, bestUse: String)
        case unavailable(String)
    }

    enum UpdateSource: String, Sendable {
        case appStore = "App Store"
        case sparkle = "Sparkle"
        case homebrew = "Homebrew"
        case github = "GitHub"

        /// The action button's symbol — the same in the sidebar row and the detail page.
        var actionSymbol: String {
            switch self {
            case .appStore: return "bag.fill"
            case .sparkle: return "arrow.down.circle.fill"
            case .homebrew: return "terminal.fill"
            case .github: return "chevron.left.forwardslash.chevron.right"
            }
        }

        func actionHelp(appName: String, latestVersion: String, brewCommand: String?) -> String {
            switch self {
            case .appStore: return "Open \(appName) in the App Store to update to \(latestVersion)."
            case .sparkle: return "Open \(appName) so its own updater installs \(latestVersion) in place. If it does not offer the update, use Check for Updates… in its menu."
            case .homebrew: return "Run or copy \(brewCommand ?? "brew upgrade --cask ...")"
            case .github: return "Open \(appName)'s GitHub release page for \(latestVersion)."
            }
        }

        /// Sparkle apps update themselves in place, so opening the app beats
        /// downloading a copy the user then has to swap in by hand.
        var opensAppToUpdate: Bool { self == .sparkle }

        func accessibilityLabel(appName: String, latestVersion: String) -> String {
            switch self {
            case .appStore: return "Open \(appName) in App Store, version \(latestVersion)"
            case .sparkle: return "Open \(appName) to update to version \(latestVersion)"
            case .homebrew: return "Homebrew update for \(appName), version \(latestVersion)"
            case .github: return "Open \(appName) release on GitHub, version \(latestVersion)"
            }
        }
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
    var isUpdateAvailable: Bool {
        if case .updateAvailable = self { return true }
        return false
    }

    var belongsInUpdatesList: Bool {
        isUpdateAvailable || self == .checking
    }

    var actionURL: URL? {
        guard case .updateAvailable(_, _, let actionURLString) = self,
              let actionURLString,
              let url = URL(string: actionURLString) else {
            return nil
        }
        return url
    }
}

extension AppInfo {
    /// Where this app was installed from, for display/export. App Store takes
    /// precedence (a `_MASReceipt` is authoritative); then a Sparkle feed, then
    /// a Homebrew cask; otherwise "Other".
    var installSourceLabel: String {
        if isAppStoreInstall { return "App Store" }
        if sparkleFeedURL != nil { return "Sparkle" }
        if homebrewCaskToken != nil { return "Homebrew" }
        return "Other"
    }

    var canCheckForUpdates: Bool {
        isAppStoreInstall || sparkleFeedURL != nil || homebrewCaskToken != nil
    }

    /// A paid app's next major version often needs a new license, so the jump
    /// gets one quiet line before the click. Store copies are left out — the
    /// store settles that itself — and so are apps the user never paid for.
    func majorUpgradeNote(latestVersion: String, hasLicenseKey: Bool) -> String? {
        guard !isAppStoreInstall, isPaidApp || hasLicenseKey,
              VersionComparator.isMajorUpgrade(from: version, to: latestVersion) else { return nil }
        return "Major upgrade — your current license may not cover \(latestVersion)."
    }

    var homebrewUpdateCommand: String? {
        guard let homebrewCaskToken, !homebrewCaskToken.isEmpty else { return nil }
        return "brew upgrade --cask \(homebrewCaskToken)"
    }
}

extension AppInfo {
    /// Drives the "couldn't confidently identify this app" callout: a weak score
    /// with no link to ground it (and not deliberately locked) is the one state
    /// the user can directly improve by adding a link.
    static func needsLinkHelp(score: Int, hasAppURL: Bool, isLocked: Bool) -> Bool {
        score <= 2 && !hasAppURL && !isLocked
    }
}

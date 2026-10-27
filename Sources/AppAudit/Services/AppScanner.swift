import Foundation
import CoreServices
import AppKit

actor AppScanner {

    private let skipPaths = ["/System/", "/Library/Frameworks/", "/private/"]

    /// A blank CFBundleName is not a name. Fall back to the display name,
    /// the executable, then the file name, so the app is not dropped.
    static func appName(from plist: NSDictionary, path: String) -> String? {
        func nonempty(_ key: String) -> String? {
            guard let value = plist[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let name = nonempty("CFBundleName") ?? nonempty("CFBundleDisplayName") ?? nonempty("CFBundleExecutable") {
            return name
        }
        let file = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return file.isEmpty ? nil : file
    }

    /// Hidden with Apple's own apps unless that toggle is on. Microsoft Edge
    /// Canary is not one of them.
    static func isHiddenAsSystemApp(_ bundleID: String) -> Bool {
        bundleID.hasPrefix("com.apple.")
    }
    private let homebrew = HomebrewService()

    func scan(includeApple: Bool? = nil, includeUtilities: Bool? = nil, runningBundleIDs: Set<String> = []) async -> [AppInfo] {
        let shouldIncludeApple = includeApple ?? UserDefaults.standard.bool(forKey: "includeAppleApps")
        let shouldIncludeUtilities = includeUtilities ?? (UserDefaults.standard.object(forKey: "includeUtilityApps") as? Bool ?? true)

        var scanDirs = ["/Applications", "\(NSHomeDirectory())/Applications"]
        // Utilities is a subfolder of /Applications, so the walk below reaches it;
        // when it is off, it is skipped instead of added.
        var skippedDirs: Set<String> = shouldIncludeUtilities ? [] : ["/Applications/Utilities"]

        // Check for debug override
        if let override = ProcessInfo.processInfo.environment["APPAUDIT_SCAN_DIR"] {
            scanDirs = [override]
            skippedDirs = []
        }

        let installedCasks = homebrew.installedCasks()
        var apps: [AppInfo] = []

        for dir in scanDirs {
            for fullPath in Self.appBundlePaths(in: dir, skipping: skippedDirs) {
                // Skip system paths
                if skipPaths.contains(where: { fullPath.hasPrefix($0) }) { continue }

                if let appInfo = makeAppInfo(
                    from: fullPath,
                    includeApple: shouldIncludeApple,
                    installedCasks: installedCasks,
                    runningBundleIDs: runningBundleIDs
                ) {
                    apps.append(appInfo)
                }
            }
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Every .app in `dir` and in its plain subfolders, two levels down, which is
    /// where suites put theirs ("Adobe Photoshop 2025/Photoshop.app", "Setapp/…").
    /// Never looks inside an app bundle, never follows a symlinked folder (no loops),
    /// and skips hidden folders and the ones in `skipping`.
    static func appBundlePaths(in dir: String, skipping: Set<String> = [], maxDepth: Int = 2) -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        var paths: [String] = []
        for item in contents.sorted() where !item.hasPrefix(".") {
            let fullPath = (dir as NSString).appendingPathComponent(item)
            if item.hasSuffix(".app") {
                paths.append(fullPath)
                continue
            }
            guard maxDepth > 0, !skipping.contains(fullPath),
                  let attributes = try? fm.attributesOfItem(atPath: fullPath),
                  attributes[.type] as? FileAttributeType == .typeDirectory else { continue }
            paths += appBundlePaths(in: fullPath, skipping: skipping, maxDepth: maxDepth - 1)
        }
        return paths
    }

    private func makeAppInfo(from path: String, includeApple: Bool, installedCasks: [String], runningBundleIDs: Set<String> = []) -> AppInfo? {
        let plistPath = (path as NSString).appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOfFile: plistPath),
              let name = Self.appName(from: plist, path: path),
              let bundleID = plist["CFBundleIdentifier"] as? String,
              !bundleID.isEmpty else { return nil }

        // Filter Apple system apps unless toggled
        if !includeApple && Self.isHiddenAsSystemApp(bundleID) { return nil }

        let version = plist["CFBundleShortVersionString"] as? String ?? ""
        let humanDesc = plist["NSHumanReadableDescription"] as? String
                     ?? plist["CFBundleGetInfoString"] as? String
        let sparkleFeedURL = plist["SUFeedURL"] as? String
        let isAppStoreInstall = FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent("Contents/_MASReceipt/receipt"))
        let homebrewCaskToken = homebrew.caskToken(forAppName: name, path: path, installedCasks: installedCasks)

        let icon: SendableImage?
        icon = SendableImage(image: NSWorkspace.shared.icon(forFile: path))

        let category = plist["LSApplicationCategoryType"] as? String

        // The path, not the bundle ID: two installed copies of one app share a
        // bundle ID, and a list with two rows of one identity draws ghost rows.
        return AppInfo(
            id: path,
            name: name,
            version: version,
            build: plist["CFBundleVersion"] as? String,
            bundleID: bundleID,
            path: path,
            humanReadableDescription: humanDesc,
            sparkleFeedURL: sparkleFeedURL,
            isAppStoreInstall: isAppStoreInstall,
            homebrewCaskToken: homebrewCaskToken,
            icon: icon,
            category: category,
            lastUsedDate: lastUsedDate(forPath: path),
            addedDate: addedDate(forPath: path),
            runtime: AppRuntimeDetector.detect(bundlePath: path, infoPlist: plist as? [String: Any] ?? [:]),
            isRunning: runningBundleIDs.contains(bundleID)
        )
    }

    /// Reads Spotlight's last-used timestamp for an app bundle. Returns nil when
    /// Spotlight has no record (e.g. never launched, or indexing disabled).
    ///
    /// Surfacing last-used (and the running-app indicator alongside it) is an
    /// idea taken from Mole (https://github.com/tw93/Mole, GPL-3.0) — the
    /// implementation is our own against Apple's API, no Mole source involved.
    private func lastUsedDate(forPath path: String) -> Date? {
        guard let item = MDItemCreate(nil, path as CFString),
              let value = MDItemCopyAttribute(item, kMDItemLastUsedDate) else {
            return nil
        }
        return value as? Date
    }

    /// When the bundle was added to its folder: Spotlight's Date Added, or the
    /// bundle's creation date when Spotlight has none. An installer or a drag
    /// to /Applications sets both; an in-place update keeps them.
    private func addedDate(forPath path: String) -> Date? {
        if let item = MDItemCreate(nil, path as CFString),
           let value = MDItemCopyAttribute(item, kMDItemDateAdded) as? Date {
            return value
        }
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.creationDate] as? Date
    }
}

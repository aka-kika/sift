import Foundation
import CoreServices

#if canImport(AppKit)
import AppKit
#endif

actor AppScanner {

    private let systemPrefixes = ["com.apple.", "com.microsoft.edgemac.Canary"]
    private let skipPaths = ["/System/", "/Library/Frameworks/", "/private/"]
    private let homebrew = HomebrewService()

    func scan(includeApple: Bool? = nil, includeUtilities: Bool? = nil) async -> [AppInfo] {
        let shouldIncludeApple = includeApple ?? UserDefaults.standard.bool(forKey: "includeAppleApps")
        let shouldIncludeUtilities = includeUtilities ?? (UserDefaults.standard.object(forKey: "includeUtilityApps") as? Bool ?? true)

        var scanDirs = ["/Applications", "\(NSHomeDirectory())/Applications"]
        if shouldIncludeUtilities { scanDirs.append("/Applications/Utilities") }

        // Check for debug override
        if let override = ProcessInfo.processInfo.environment["APPAUDIT_SCAN_DIR"] {
            scanDirs = [override]
        }

        let installedCasks = homebrew.installedCasks()
        var apps: [AppInfo] = []
        let fm = FileManager.default

        for dir in scanDirs {
            guard fm.fileExists(atPath: dir) else { continue }
            guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { continue }

            for item in contents {
                guard item.hasSuffix(".app") else { continue }
                let fullPath = (dir as NSString).appendingPathComponent(item)

                // Skip system paths
                if skipPaths.contains(where: { fullPath.hasPrefix($0) }) { continue }

                if let appInfo = makeAppInfo(
                    from: fullPath,
                    includeApple: shouldIncludeApple,
                    installedCasks: installedCasks
                ) {
                    apps.append(appInfo)
                }
            }
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func makeAppInfo(from path: String, includeApple: Bool, installedCasks: [String]) -> AppInfo? {
        let plistPath = (path as NSString).appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOfFile: plistPath),
              let name = plist["CFBundleName"] as? String ?? plist["CFBundleDisplayName"] as? String,
              let bundleID = plist["CFBundleIdentifier"] as? String else { return nil }

        // Filter Apple system apps unless toggled
        if !includeApple && systemPrefixes.contains(where: { bundleID.hasPrefix($0) }) { return nil }

        let version = plist["CFBundleShortVersionString"] as? String ?? ""
        let humanDesc = plist["NSHumanReadableDescription"] as? String
                     ?? plist["CFBundleGetInfoString"] as? String
        let sparkleFeedURL = plist["SUFeedURL"] as? String
        let isAppStoreInstall = FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent("Contents/_MASReceipt/receipt"))
        let homebrewCaskToken = homebrew.caskToken(forAppName: name, path: path, installedCasks: installedCasks)

        let icon: SendableImage?
#if canImport(AppKit)
        icon = SendableImage(image: NSWorkspace.shared.icon(forFile: path))
#else
        icon = nil
#endif

        return AppInfo(
            id: bundleID,
            name: name,
            version: version,
            bundleID: bundleID,
            path: path,
            humanReadableDescription: humanDesc,
            sparkleFeedURL: sparkleFeedURL,
            isAppStoreInstall: isAppStoreInstall,
            homebrewCaskToken: homebrewCaskToken,
            icon: icon,
            lastUsedDate: lastUsedDate(forPath: path)
        )
    }

    /// Reads Spotlight's last-used timestamp for an app bundle. Returns nil when
    /// Spotlight has no record (e.g. never launched, or indexing disabled).
    private func lastUsedDate(forPath path: String) -> Date? {
        guard let item = MDItemCreate(nil, path as CFString),
              let value = MDItemCopyAttribute(item, kMDItemLastUsedDate) else {
            return nil
        }
        return value as? Date
    }
}

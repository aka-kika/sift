import Foundation
import Security

/// Discovers everything on disk that belongs to an app: the bundle itself
/// plus leftovers across the user-level Library roots, matched identifier-
/// first via `LeftoverMatcher` with a recorded reason per hit.
///
/// Scanning strategy adapted from uninstally's AssociatedFileScanner
/// (https://github.com/gostonx/uninstally, MIT License © 2026 Codenta).
/// A Launch Agent plist has to be unloaded before it is trashed, or the
/// helper keeps running until logout.
enum LaunchAgentUnload {
    static func needsUnload(_ category: LeftoverCategory) -> Bool {
        category == .launchAgents
    }

    static func arguments(plistPath: String, uid: uid_t = getuid()) -> [String] {
        ["bootout", "gui/\(uid)", plistPath]
    }

    static func bootout(plistPath: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments(plistPath: plistPath)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}

struct LeftoverScanner: Sendable {

    /// `otherAppNames` are the names of the other installed apps (other bundle
    /// IDs). A folder matched only by name that one of them could own is
    /// listed unchecked rather than taken.
    func scan(appName: String, bundleID: String, appPath: String,
              otherBundleIDs: [String] = [], otherAppNames: [String] = []) async -> [LeftoverItem] {
        let fm = FileManager.default
        let library = fm.homeDirectoryForCurrentUser
            .appending(path: "Library", directoryHint: .isDirectory)

        func lib(_ parts: String...) -> URL {
            parts.reduce(library) { $0.appending(path: $1, directoryHint: .isDirectory) }
        }

        let roots: [(LeftoverCategory, URL)] = [
            (.applicationSupport, lib("Application Support")),
            (.caches, lib("Caches")),
            (.preferences, lib("Preferences")),
            (.preferences, lib("Preferences", "ByHost")),
            (.logs, lib("Logs")),
            (.containers, lib("Containers")),
            (.groupContainers, lib("Group Containers")),
            (.savedState, lib("Saved Application State")),
            (.webKit, lib("WebKit")),
            (.httpStorages, lib("HTTPStorages")),
            (.launchAgents, lib("LaunchAgents")),
            (.applicationScripts, lib("Application Scripts")),
            (.cookies, lib("Cookies")),
        ]

        // App Group folders can carry the signing team's prefix.
        let teamID = Self.teamIdentifier(ofAppAt: appPath)
        // Apps whose name a name-only folder could equally stand for.
        let nameSharers = LeftoverMatcher.nameSharers(appName: appName, otherAppNames: otherAppNames)

        var items: [LeftoverItem] = []

        // The bundle itself always leads the list.
        let bundleURL = URL(fileURLWithPath: appPath)
        items.append(LeftoverItem(
            id: bundleURL.standardizedFileURL.path,
            url: bundleURL,
            category: .application,
            sizeBytes: Self.size(of: bundleURL),
            reason: "The application bundle",
            isAppBundle: true
        ))

        for (category, root) in roots {
            guard let children = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children {
                let name = child.lastPathComponent
                var reason: String?
                var startsUnchecked = false
                if LeftoverMatcher.matches(name: name, bundleID: bundleID, otherBundleIDs: otherBundleIDs) {
                    reason = "Matches \(bundleID)"
                } else if LeftoverMatcher.appGroupMatchAllowed(for: category),
                          LeftoverMatcher.matchesAppGroup(name: name, bundleID: bundleID, teamID: teamID, otherBundleIDs: otherBundleIDs) {
                    reason = "App group of \(bundleID)"
                } else if LeftoverMatcher.nameMatchAllowed(for: category),
                          LeftoverMatcher.matchesDisplayName(name, appName: appName) {
                    if nameSharers.isEmpty {
                        reason = "Folder named after \(appName)"
                    } else {
                        reason = LeftoverMatcher.sharedNameReason(appName: appName, sharers: nameSharers)
                        startsUnchecked = true
                    }
                }
                guard let matchReason = reason else { continue }
                items.append(LeftoverItem(
                    id: child.standardizedFileURL.path,
                    url: child,
                    category: category,
                    sizeBytes: Self.size(of: child),
                    reason: matchReason,
                    startsUnchecked: startsUnchecked
                ))
            }
        }

        // De-duplicate by path; keep the bundle first, rest by size.
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.id).inserted }
        let bundle = unique.filter(\.isAppBundle)
        let rest = unique.filter { !$0.isAppBundle }.sorted { $0.sizeBytes > $1.sizeBytes }
        return bundle + rest
    }

    /// The Team ID from the bundle's code signature, or nil when it is unsigned
    /// or ad-hoc signed. Reads the signature only, with no validation pass, so
    /// it stays cheap.
    static func teamIdentifier(ofAppAt path: String) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String,
              !teamID.isEmpty else { return nil }
        return teamID
    }

    /// Recursive on-disk size; a single file answers directly. Shared with the
    /// detail view's facts row, which measures the bundle the same way.
    static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }
}

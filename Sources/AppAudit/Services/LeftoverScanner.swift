import Foundation

/// Discovers everything on disk that belongs to an app: the bundle itself
/// plus leftovers across the user-level Library roots, matched identifier-
/// first via `LeftoverMatcher` with a recorded reason per hit.
///
/// Scanning strategy adapted from uninstally's AssociatedFileScanner
/// (https://github.com/gostonx/uninstally, MIT License © 2026 Codenta).
struct LeftoverScanner: Sendable {

    func scan(appName: String, bundleID: String, appPath: String) async -> [LeftoverItem] {
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
                if LeftoverMatcher.matches(name: name, bundleID: bundleID) {
                    reason = "Matches \(bundleID)"
                } else if LeftoverMatcher.nameMatchAllowed(for: category),
                          LeftoverMatcher.matchesDisplayName(name, appName: appName) {
                    reason = "Folder named after \(appName)"
                }
                guard let matchReason = reason else { continue }
                items.append(LeftoverItem(
                    id: child.standardizedFileURL.path,
                    url: child,
                    category: category,
                    sizeBytes: Self.size(of: child),
                    reason: matchReason
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

    /// Recursive on-disk size; a single file answers directly.
    private static func size(of url: URL) -> Int64 {
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

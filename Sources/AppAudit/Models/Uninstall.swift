import Foundation

/// One sweepable artefact — the app bundle itself or a leftover file/folder
/// discovered under the user's Library. `reason` explains the match so the
/// sweep sheet never lists a mystery row.
struct LeftoverItem: Identifiable, Equatable {
    let id: String            // standardized path
    let url: URL
    let category: LeftoverCategory
    let sizeBytes: Int64
    let reason: String
    var isAppBundle: Bool = false
}

enum LeftoverCategory: String {
    case application = "Application"
    case applicationSupport = "Application Support"
    case caches = "Caches"
    case preferences = "Preferences"
    case logs = "Logs"
    case containers = "Containers"
    case groupContainers = "Group Containers"
    case savedState = "Saved State"
    case webKit = "WebKit"
    case httpStorages = "HTTP Storages"
    case launchAgents = "Launch Agents"
    case applicationScripts = "App Scripts"
    case cookies = "Cookies"
}

/// Apps Sift refuses to uninstall: the system's and its own.
enum UninstallRules {
    static func isProtected(bundleID: String) -> Bool {
        bundleID.hasPrefix("com.apple.")
            || bundleID == "com.kikaapp.appaudit"
            || bundleID == "com.kikaapp.sift2"
    }
}

/// Pure matching rules for leftover discovery. Identifier-first — a name
/// matches when it equals, extends, or embeds the app's bundle identifier —
/// with display-name equality allowed only where macOS vendors conventionally
/// name folders after the app. Matching semantics adapted from uninstally
/// (MIT © 2026 Codenta).
enum LeftoverMatcher {
    static func identifierCandidates(bundleID: String) -> [String] {
        [bundleID]
    }

    /// True when `name` (a directory entry) belongs to `bundleID`:
    /// exact, `<id>.<anything>` (helpers, plists, ByHost, lockfiles),
    /// or extension-stripped equality.
    static func matches(name: String, bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        let bare = (name as NSString).deletingPathExtension
        for id in identifierCandidates(bundleID: bundleID) {
            if name == id || bare == id { return true }
            if name.hasPrefix(id + ".") { return true }
        }
        return false
    }

    /// Vendor-conventional name folders exist only under Application Support
    /// and Logs; everywhere else a bare app name is too risky to trust.
    static func nameMatchAllowed(for category: LeftoverCategory) -> Bool {
        category == .applicationSupport || category == .logs
    }

    /// Case-insensitive equality, refusing tiny generic names.
    static func matchesDisplayName(_ name: String, appName: String) -> Bool {
        guard appName.count > 3 else { return false }
        return name.compare(appName, options: .caseInsensitive) == .orderedSame
    }
}

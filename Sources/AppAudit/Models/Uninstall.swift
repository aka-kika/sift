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
    /// The match could belong to another installed app, so the sheet lists
    /// it unchecked and the reason says why.
    var startsUnchecked: Bool = false
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

/// Words for the uninstall sheet once a sweep has finished with nothing left behind.
enum UninstallDoneCopy {
    /// `homebrewRemovedTheApp` is true after `brew uninstall` deleted the bundle.
    /// That copy is gone for good. It is not sitting in the Trash.
    static func success(homebrewRemovedTheApp: Bool) -> String {
        if homebrewRemovedTheApp {
            return "Removed by Homebrew — not in the Trash. Anything else you swept is in the Trash, and the license record stays in your vault."
        }
        return "Moved to Trash — recoverable there, and the license record stays in your vault."
    }
}

/// The uninstall sheet after `brew uninstall`, and while brew is still running.
enum BrewUninstallFooter {
    enum Action: Equatable { case moveToTrash, doneRemoved }

    /// Brew deleted the app and nothing else is checked: Move to Trash would
    /// be grey, and Cancel would leave the removed app in the sidebar.
    /// Done reports the app as removed.
    static func action(homebrewRemovedTheApp: Bool, anythingChecked: Bool) -> Action {
        if homebrewRemovedTheApp && !anythingChecked { return .doneRemoved }
        return .moveToTrash
    }

    static func brewButtonEnabled(running: Bool) -> Bool { !running }
}

/// Apps Sift refuses to uninstall: the system's and its own.
enum UninstallRules {
    static func isProtected(bundleID: String) -> Bool {
        bundleID.hasPrefix("com.apple.") || BuildVariant.isSiftItself(bundleID)
    }
}

/// Pure matching rules for leftover discovery. Identifier-first — a name
/// matches when it equals, extends, or embeds the app's bundle identifier —
/// with display-name equality allowed only where macOS vendors conventionally
/// name folders after the app. Matching semantics adapted from uninstally
/// (MIT © 2026 Codenta).
enum LeftoverMatcher {
    /// True when `name` (a directory entry) belongs to `bundleID`:
    /// exact, `<id>.<anything>` (helpers, plists, ByHost, lockfiles),
    /// or extension-stripped equality.
    ///
    /// `otherBundleIDs` are the other installed apps. A name that belongs to one
    /// of them is never claimed — `com.google.Chrome.canary.plist` is Canary's,
    /// not stable Chrome's, even though it starts with `com.google.Chrome.`.
    /// A bundle ID can claim Library files only when it has at least three
    /// parts (`com.vendor.app`). `com.apple` and `com.google` would otherwise
    /// pre-check other apps' files. `com.apple` itself never matches.
    static func isSpecificBundleID(_ bundleID: String) -> Bool {
        if bundleID == "com.apple" { return false }
        return bundleID.split(separator: ".").filter { !$0.isEmpty }.count >= 3
    }

    static func matches(name: String, bundleID: String, otherBundleIDs: [String] = []) -> Bool {
        guard isSpecificBundleID(bundleID) else { return false }
        let bare = (name as NSString).deletingPathExtension
        let own = name == bundleID || bare == bundleID || name.hasPrefix(bundleID + ".")
        guard own else { return false }
        let claimedBySibling = otherBundleIDs.contains { other in
            other != bundleID && other.count > bundleID.count && other.hasPrefix(bundleID + ".")
                && (name == other || bare == other || name.hasPrefix(other + "."))
        }
        return !claimedBySibling
    }

    /// App Group folders carry the group's identifier, not the bundle ID:
    /// `group.<id>`, or team-prefixed `<TEAMID>.<id>` and `<TEAMID>.group.<id>`.
    /// The prefix is stripped and the usual identifier rules run on the rest,
    /// so `group.com.foo.bar` matches `com.foo.bar` but `group.com.foo.barbaz`
    /// does not. Team prefixes count only for the app's own signing team.
    static func matchesAppGroup(name: String, bundleID: String, teamID: String?, otherBundleIDs: [String] = []) -> Bool {
        var prefixes = ["group."]
        if let teamID, !teamID.isEmpty {
            prefixes += [teamID + ".group.", teamID + "."]
        }
        return prefixes.contains { prefix in
            name.hasPrefix(prefix)
                && matches(name: String(name.dropFirst(prefix.count)), bundleID: bundleID, otherBundleIDs: otherBundleIDs)
        }
    }

    /// App Group folders live under Group Containers, and macOS gives each
    /// group an Application Scripts folder of the same name.
    static func appGroupMatchAllowed(for category: LeftoverCategory) -> Bool {
        category == .groupContainers || category == .applicationScripts
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

    /// Other installed apps a name-only folder could just as well belong to:
    /// the same name, or one name starting with the other ("1Password" and
    /// "1Password 7"), ignoring case. Pass only apps with another bundle ID;
    /// a second copy of this app is handled on its own.
    static func nameSharers(appName: String, otherAppNames: [String]) -> [String] {
        let own = appName.lowercased()
        var seen = Set<String>()
        return otherAppNames.filter { other in
            let lower = other.lowercased()
            guard !lower.isEmpty, lower.hasPrefix(own) || own.hasPrefix(lower) else { return false }
            return seen.insert(lower).inserted
        }
    }

    /// The row text for a name-only folder another app may share.
    static func sharedNameReason(appName: String, sharers: [String]) -> String {
        let names = sharers.prefix(2).joined(separator: " and ")
        let more = sharers.count > 2 ? " and others" : ""
        return "Folder named after \(appName), left unchecked: \(names)\(more) is installed too and may use it"
    }
}

/// The order and stop rule of one uninstall sweep, kept apart from the sheet
/// so it can be tested without touching the disk.
///
/// The bundle goes first. If it cannot be moved, the sweep stops there: the
/// app is still installed, so its settings and data are still in use, and
/// trashing them would leave a working app with its data gone.
enum UninstallSweep {
    struct Outcome: Equatable {
        var failures: [TrashService.Failure] = []
        var removedBundle = false
        /// The bundle stayed on disk, so the checked data was left alone.
        var stoppedAtBundle = false
        /// Checked items never attempted because the sweep stopped.
        var skipped = 0
    }

    /// What starts checked: everything, except shared data when another copy
    /// of the app exists (only its bundle then) and rows another installed
    /// app may own.
    static func initiallyChecked(_ items: [LeftoverItem], hasOtherCopy: Bool) -> Set<String> {
        Set(items.filter { item in
            if item.isAppBundle { return true }
            return !hasOtherCopy && !item.startsUnchecked
        }.map(\.id))
    }

    /// The checked items in sweep order: the bundle first, the rest as listed.
    static func ordered(_ targets: [LeftoverItem]) -> [LeftoverItem] {
        targets.filter(\.isAppBundle) + targets.filter { !$0.isAppBundle }
    }

    @MainActor
    static func run(_ targets: [LeftoverItem],
                    progress: (LeftoverItem) -> Void = { _ in },
                    trash: (URL) async -> TrashService.Failure?) async -> Outcome {
        var outcome = Outcome()
        let queue = ordered(targets)
        for (index, item) in queue.enumerated() {
            progress(item)
            if let failure = await trash(item.url) {
                outcome.failures.append(failure)
                if item.isAppBundle {
                    outcome.stoppedAtBundle = true
                    outcome.skipped = queue.count - index - 1
                    break
                }
            } else if item.isAppBundle {
                outcome.removedBundle = true
            }
        }
        return outcome
    }
}

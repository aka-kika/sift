import Foundation
import CoreServices
import os

/// Finds every copy of an app on this Mac, not just the ones in the folders
/// Sift scans. A second copy in ~/Downloads, a JetBrains Toolbox folder or
/// Setapp shares the same settings and data folders, and the uninstall sheet
/// must not pre-check them while that copy still runs from there.
enum AppCopyFinder {
    /// What the sheet knows about other copies.
    enum Result: Equatable {
        /// Spotlight found this copy and no other.
        case onlyThisCopy
        /// Other copies, by path.
        case others([String])
        /// Spotlight gave no usable answer (off, still indexing, too slow).
        /// Treated like another copy: data starts unchecked, never blocked.
        case unknown
    }

    /// Sorts Spotlight's answer. `found` is nil when the query failed. An answer
    /// that does not include this very copy is not trusted either: Spotlight is
    /// off for that volume or has not indexed it, so it would miss others too.
    static func classify(found: [String]?, thisPath: String, knownOtherPaths: [String] = []) -> Result {
        let this = canonical(thisPath)
        let known = knownOtherPaths.map(canonical).filter { $0 != this }
        guard let found else {
            return known.isEmpty ? .unknown : .others(known.sorted())
        }
        let paths = found.map(canonical)
        let others = paths.filter { path in
            path != this
                // A helper bundled inside this app goes with it.
                && !path.hasPrefix(this + "/")
                // Spotlight can still list something already in the Trash.
                && !path.contains("/.Trash/")
        }
        var merged = known
        for path in others where !merged.contains(path) { merged.append(path) }
        if !merged.isEmpty { return .others(merged.sorted()) }
        return paths.contains(this) ? .onlyThisCopy : .unknown
    }

    /// The Spotlight query for application bundles with this identifier. Quotes
    /// and backslashes are escaped so an odd identifier cannot break the query.
    static func queryString(bundleID: String) -> String {
        let escaped = bundleID
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "kMDItemContentType == \"com.apple.application-bundle\" && kMDItemCFBundleIdentifier == \"\(escaped)\""
    }

    /// Asks Spotlight for every copy, giving up after `timeout` so a slow
    /// index never holds up the sheet. Nil means no answer.
    static func spotlightPaths(bundleID: String, timeout: Duration = .seconds(2)) async -> [String]? {
        guard !bundleID.isEmpty else { return nil }
        let resumed = OSAllocatedUnfairLock(initialState: false)
        return await withCheckedContinuation { continuation in
            let finish: @Sendable ([String]?) -> Void = { value in
                let first = resumed.withLock { done -> Bool in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(returning: value) }
            }
            // MDQuery's synchronous run blocks its thread; the timer below
            // answers first when it takes too long.
            Task.detached(priority: .userInitiated) {
                finish(runQuery(bundleID: bundleID))
            }
            Task.detached {
                try? await Task.sleep(for: timeout)
                finish(nil)
            }
        }
    }

    private static func runQuery(bundleID: String) -> [String]? {
        guard let query = MDQueryCreate(kCFAllocatorDefault, queryString(bundleID: bundleID) as CFString, nil, nil) else {
            return nil
        }
        MDQuerySetMaxCount(query, 50)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return nil }
        var paths: [String] = []
        for index in 0..<MDQueryGetResultCount(query) {
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            if let path = MDItemCopyAttribute(item, kMDItemPath) as? String {
                paths.append(path)
            }
        }
        return paths
    }

    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

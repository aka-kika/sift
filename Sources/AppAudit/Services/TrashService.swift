import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Moves one item to the Trash, and explains itself when it can't.
///
/// `FileManager.trashItem` renames the item into `~/.Trash`, and POSIX asks for
/// write permission on the *directory being renamed* — not just on its parent.
/// A Mac App Store bundle is `drwxr-xr-x root:wheel`, so the rename is refused
/// (NSCocoaErrorDomain 513) no matter that `/Applications` itself is writable.
/// That is why store-bought apps used to land in "could not be moved" every
/// time. Finder can do the move, so a permission refusal is handed to Finder
/// rather than reported as a dead end.
enum TrashService {
    struct Failure: Equatable {
        let path: String
        let reason: String
    }

    /// Cocoa's permission errors — the shape a root-owned bundle produces.
    static func isPermissionDenied(_ error: NSError) -> Bool {
        guard error.domain == NSCocoaErrorDomain else { return false }
        return error.code == NSFileWriteNoPermissionError
            || error.code == NSFileReadNoPermissionError
            || error.code == NSFileWriteVolumeReadOnlyError
    }

    /// AppleScript is a quoted-string language: backslashes and quotes in a
    /// path have to survive the trip or the script fails on unrelated syntax.
    static func finderDeleteScript(for path: String) -> String {
        let escaped = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "tell application \"Finder\" to delete POSIX file \"\(escaped)\""
    }

    /// A human sentence for the failure list — Cocoa's own wording, minus the
    /// noise, so a row never reads as a mystery.
    static func reason(for error: NSError) -> String {
        if isPermissionDenied(error) {
            return "macOS refused the move — Finder could not take it either"
        }
        return error.localizedDescription
    }

    /// Returns nil when the item reached the Trash.
    @MainActor
    static func trash(_ url: URL) async -> Failure? {
        do {
            try await Task.detached {
                var resulting: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            }.value
            return nil
        } catch {
            let nsError = error as NSError
            guard isPermissionDenied(nsError) else {
                return Failure(path: url.path, reason: nsError.localizedDescription)
            }
            if finderDelete(url) { return nil }
            return Failure(path: url.path, reason: reason(for: nsError))
        }
    }

    /// Ask Finder to do the move. Finder owns the privileged path and puts up
    /// its own authorization prompt when one is needed, so no password ever
    /// passes through Sift. AppleScript is main-thread only.
    @MainActor
    private static func finderDelete(_ url: URL) -> Bool {
        #if canImport(AppKit)
        guard let script = NSAppleScript(source: finderDeleteScript(for: url.path)) else { return false }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        // A script can report success and still leave the item in place, so
        // trust the disk rather than the reply.
        return !FileManager.default.fileExists(atPath: url.path)
        #else
        return false
        #endif
    }
}

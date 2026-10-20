import Foundation
import AppKit

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

    /// How long Sift waits for Finder. Finder may be waiting on its own
    /// password prompt or on the Automation consent prompt.
    static let finderTimeout: TimeInterval = 30

    /// What came of handing an item to Finder.
    enum FinderOutcome: Equatable {
        case moved
        case refused
        case timedOut
    }

    /// The Apple Event `tell application "Finder" to delete POSIX file …`
    /// sends: Core Suite `delete`, with the file URL as the direct object.
    /// Built as a descriptor, so no path ever has to be quoted into a script.
    static func finderDeleteEvent(for url: URL) -> NSAppleEventDescriptor {
        let finder = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kAECoreSuite),
            eventID: AEEventID(kAEDelete),
            targetDescriptor: finder,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(NSAppleEventDescriptor(fileURL: url), forKeyword: keyDirectObject)
        return event
    }

    /// A human sentence for the failure list — Cocoa's own wording, minus the
    /// noise, so a row never reads as a mystery.
    static func reason(for error: NSError) -> String {
        if isPermissionDenied(error) {
            return "macOS refused the move — Finder could not take it either"
        }
        return error.localizedDescription
    }

    /// The row for an item Finder did not finish in time.
    static let timeoutReason = "Finder did not finish within \(Int(finderTimeout)) seconds, so Sift stopped waiting. If you approve a Finder prompt later, the item may still reach the Trash."

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
            switch await finderDelete(url) {
            case .moved: return nil
            case .timedOut: return Failure(path: url.path, reason: timeoutReason)
            case .refused: return Failure(path: url.path, reason: reason(for: nsError))
            }
        }
    }

    /// Ask Finder to do the move. Finder owns the privileged path and puts up
    /// its own authorization prompt when one is needed, so no password ever
    /// passes through Sift. The event is sent from a background thread, so the
    /// window stays live while Finder or macOS waits on the user.
    static func finderDelete(_ url: URL, timeout: TimeInterval = finderTimeout) async -> FinderOutcome {
        // The event carries its own timeout; the outer deadline is a backstop
        // for a send that blocks before the event leaves (a consent prompt).
        let answered = await waitAtMost(timeout + 5) { () -> Bool in
            do {
                _ = try finderDeleteEvent(for: url).sendEvent(
                    options: [.waitForReply, .canInteract, .canSwitchLayer],
                    timeout: timeout
                )
                return true
            } catch {
                return (error as NSError).code != Int(errAETimeout)
            }
        }
        // Finder can reply and still leave the item in place, so trust the
        // disk rather than the reply.
        if !FileManager.default.fileExists(atPath: url.path) { return .moved }
        return answered == true ? .refused : .timedOut
    }

    /// Runs `work` on a background thread and stops waiting after `seconds`,
    /// returning nil. The work is not cancelled (a sent Apple Event cannot be);
    /// a late answer is dropped.
    static func waitAtMost<T: Sendable>(_ seconds: TimeInterval, _ work: @escaping @Sendable () -> T) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let once = ResumeOnce(continuation)
            DispatchQueue.global(qos: .userInitiated).async { once.resume(work()) }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + seconds) { once.resume(nil) }
        }
    }

    /// Resumes a continuation exactly once, from whichever side gets there first.
    private final class ResumeOnce<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T?, Never>?

        init(_ continuation: CheckedContinuation<T?, Never>) {
            self.continuation = continuation
        }

        func resume(_ value: T?) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
        }
    }
}

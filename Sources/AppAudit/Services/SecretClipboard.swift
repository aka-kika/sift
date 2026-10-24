import AppKit

/// Copies a license key so it does not linger. The key is marked concealed and
/// transient (the nspasteboard.org markers clipboard managers honor: hide it,
/// do not keep it in history), and the clipboard is cleared after a minute,
/// but only if it still holds that key. Anything copied since is left alone.
enum SecretClipboard {
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let clearDelay: Duration = .seconds(60)
    /// The change count of a key still waiting out its minute. Quit clears it
    /// early, if the clipboard still holds that key.
    @MainActor private static var pendingChangeCount: Int?

    /// Writes `secret` with the markers and returns the clipboard's change
    /// count, the token `clearIfUnchanged` checks against.
    @discardableResult
    static func write(_ secret: String, to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(secret, forType: .string)
        pasteboard.setData(Data(), forType: concealedType)
        pasteboard.setData(Data(), forType: transientType)
        return pasteboard.changeCount
    }

    /// True when nothing has been copied since the write that returned `changeCount`.
    static func shouldClear(currentChangeCount: Int, copiedChangeCount: Int) -> Bool {
        currentChangeCount == copiedChangeCount
    }

    /// Clears the clipboard when it still holds what was written at `changeCount`.
    @discardableResult
    static func clearIfUnchanged(_ pasteboard: NSPasteboard, changeCount: Int) -> Bool {
        guard shouldClear(currentChangeCount: pasteboard.changeCount, copiedChangeCount: changeCount) else { return false }
        pasteboard.clearContents()
        return true
    }

    /// Copies to the general clipboard and schedules the clear.
    @MainActor
    static func copy(_ secret: String) {
        let pasteboard = NSPasteboard.general
        let changeCount = write(secret, to: pasteboard)
        pendingChangeCount = changeCount
        Task { @MainActor in
            try? await Task.sleep(for: clearDelay)
            if clearIfUnchanged(pasteboard, changeCount: changeCount) {
                pendingChangeCount = nil
            }
        }
    }

    /// Quit within the minute. Clears only when the clipboard still holds the key.
    @MainActor
    static func clearOnQuit() {
        _ = clearRemembered(on: .general)
    }

    /// Test hook and the body of `clearOnQuit`. A private pasteboard keeps the
    /// test off the real clipboard.
    @MainActor
    static func remember(_ changeCount: Int) {
        pendingChangeCount = changeCount
    }

    @MainActor
    @discardableResult
    static func clearRemembered(on pasteboard: NSPasteboard) -> Bool {
        guard let changeCount = pendingChangeCount else { return false }
        let cleared = clearIfUnchanged(pasteboard, changeCount: changeCount)
        if cleared { pendingChangeCount = nil }
        return cleared
    }
}

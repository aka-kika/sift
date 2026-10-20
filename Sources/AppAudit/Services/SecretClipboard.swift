import AppKit

/// Copies a license key so it does not linger. The key is marked concealed and
/// transient (the nspasteboard.org markers clipboard managers honor: hide it,
/// do not keep it in history), and the clipboard is cleared after a minute,
/// but only if it still holds that key. Anything copied since is left alone.
enum SecretClipboard {
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let clearDelay: Duration = .seconds(60)

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
        Task { @MainActor in
            try? await Task.sleep(for: clearDelay)
            clearIfUnchanged(pasteboard, changeCount: changeCount)
        }
    }
}

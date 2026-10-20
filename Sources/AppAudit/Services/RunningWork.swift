import Foundation

/// Work that must not be cut off halfway: an uninstall sweep moving items to
/// the Trash, and a running `brew` command. While any of it runs, Sift refuses
/// to quit (with a plain alert), and closing the last window does not quit
/// either; that quit is held until the work ends.
@MainActor
final class RunningWork {
    enum Kind: Hashable {
        case trashSweep
        case homebrew
    }

    static let shared = RunningWork()

    private(set) var counts: [Kind: Int] = [:]
    /// The last window closed while work ran; quit once it ends.
    private(set) var quitWhenIdle = false
    /// Called when held work ends after the last window closed.
    var onIdleAfterLastWindowClosed: (() -> Void)?

    init() {}

    var isBusy: Bool { !counts.isEmpty }
    var kinds: Set<Kind> { Set(counts.keys) }

    func begin(_ kind: Kind) {
        counts[kind, default: 0] += 1
    }

    func end(_ kind: Kind) {
        guard let count = counts[kind] else { return }
        counts[kind] = count > 1 ? count - 1 : nil
        if !isBusy && quitWhenIdle {
            quitWhenIdle = false
            onIdleAfterLastWindowClosed?()
        }
    }

    /// Runs `body` counted as `kind`, ending the count however it returns.
    func run<T>(_ kind: Kind, _ body: () async -> T) async -> T {
        begin(kind)
        defer { end(kind) }
        return await body()
    }

    /// Answer for `applicationShouldTerminateAfterLastWindowClosed`: quit now
    /// when idle, otherwise hold the quit until the work ends.
    func shouldQuitAfterLastWindowClosed() -> Bool {
        guard isBusy else { return true }
        quitWhenIdle = true
        return false
    }

    /// The alert shown when a quit is refused. The sweep is named first: a
    /// half-done sweep is the harder one to pick up again.
    static func refusalText(for kinds: Set<Kind>) -> (title: String, message: String) {
        if kinds.contains(.trashSweep) {
            return ("Sift is still moving items to the Trash",
                    "Wait for the uninstall to finish, then quit.")
        }
        return ("Sift is still running Homebrew",
                "Wait for brew to finish, then quit. Stopping it halfway can leave the app half updated or half removed.")
    }
}

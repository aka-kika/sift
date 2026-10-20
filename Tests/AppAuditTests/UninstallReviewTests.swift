import Testing
import Foundation
import AppKit
@testable import Sift

/// Fixes from the 2026-10-20 code review.

@Suite("App Group leftovers")
struct AppGroupLeftoverTests {
    @Test("group.<id> and team-prefixed group folders match")
    func groupShapes() {
        let id = "com.foo.bar"
        #expect(LeftoverMatcher.matchesAppGroup(name: "group.com.foo.bar", bundleID: id, teamID: nil))
        #expect(LeftoverMatcher.matchesAppGroup(name: "group.com.foo.bar.shared", bundleID: id, teamID: nil))
        #expect(LeftoverMatcher.matchesAppGroup(name: "ABCDE12345.com.foo.bar", bundleID: id, teamID: "ABCDE12345"))
        #expect(LeftoverMatcher.matchesAppGroup(name: "ABCDE12345.group.com.foo.bar", bundleID: id, teamID: "ABCDE12345"))
        #expect(LeftoverMatcher.matchesAppGroup(name: "ABCDE12345.com.foo.bar.helper", bundleID: id, teamID: "ABCDE12345"))
    }

    @Test("A longer identifier is not this app's group")
    func noPrefixBleed() {
        let id = "com.foo.bar"
        #expect(!LeftoverMatcher.matchesAppGroup(name: "group.com.foo.barbaz", bundleID: id, teamID: nil))
        #expect(!LeftoverMatcher.matchesAppGroup(name: "ABCDE12345.com.foo.barbaz", bundleID: id, teamID: "ABCDE12345"))
        #expect(!LeftoverMatcher.matchesAppGroup(name: "ABCDE12345.group.com.foo.barbaz", bundleID: id, teamID: "ABCDE12345"))
        #expect(!LeftoverMatcher.matchesAppGroup(name: "group.com.other.app", bundleID: id, teamID: nil))
    }

    @Test("Team prefixes count only for the app's own team")
    func otherTeam() {
        let id = "com.foo.bar"
        #expect(!LeftoverMatcher.matchesAppGroup(name: "ZZZZZ99999.com.foo.bar", bundleID: id, teamID: "ABCDE12345"))
        #expect(!LeftoverMatcher.matchesAppGroup(name: "ABCDE12345.com.foo.bar", bundleID: id, teamID: nil))
        #expect(!LeftoverMatcher.matchesAppGroup(name: "ABCDE12345.com.foo.bar", bundleID: id, teamID: ""))
    }

    @Test("A sibling app's group is left alone")
    func siblingGroup() {
        let others = ["com.google.Chrome.canary"]
        #expect(!LeftoverMatcher.matchesAppGroup(name: "group.com.google.Chrome.canary", bundleID: "com.google.Chrome", teamID: nil, otherBundleIDs: others))
        #expect(LeftoverMatcher.matchesAppGroup(name: "group.com.google.Chrome", bundleID: "com.google.Chrome", teamID: nil, otherBundleIDs: others))
    }

    @Test("Group matching runs only where App Group folders live")
    func categories() {
        #expect(LeftoverMatcher.appGroupMatchAllowed(for: .groupContainers))
        #expect(LeftoverMatcher.appGroupMatchAllowed(for: .applicationScripts))
        #expect(!LeftoverMatcher.appGroupMatchAllowed(for: .preferences))
        #expect(!LeftoverMatcher.appGroupMatchAllowed(for: .applicationSupport))
    }

    @Test("No Team ID for an unsigned folder or a missing path")
    func teamIDUnsigned() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "SiftTests-\(UUID().uuidString).app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(LeftoverScanner.teamIdentifier(ofAppAt: dir.path) == nil)
        #expect(LeftoverScanner.teamIdentifier(ofAppAt: "/nonexistent/Nothing.app") == nil)
    }
}

@Suite("Copied license keys do not linger")
struct SecretClipboardTests {
    private func scratchPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("com.kikaapp.SiftTests.\(UUID().uuidString)"))
    }

    @Test("The key is written with the concealed and transient markers")
    func markers() {
        let pasteboard = scratchPasteboard()
        defer { pasteboard.releaseGlobally() }
        SecretClipboard.write("KEY-1234", to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "KEY-1234")
        let types = pasteboard.types ?? []
        #expect(types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")))
        #expect(types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")))
    }

    @Test("The clear runs only while the clipboard still holds the key")
    func clearOnlyIfUnchanged() {
        let pasteboard = scratchPasteboard()
        defer { pasteboard.releaseGlobally() }
        let copied = SecretClipboard.write("KEY-1234", to: pasteboard)
        #expect(SecretClipboard.clearIfUnchanged(pasteboard, changeCount: copied))
        #expect(pasteboard.string(forType: .string) == nil)

        let again = SecretClipboard.write("KEY-1234", to: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("something copied later", forType: .string)
        #expect(!SecretClipboard.clearIfUnchanged(pasteboard, changeCount: again))
        #expect(pasteboard.string(forType: .string) == "something copied later")
    }

    @Test("Change-count rule and delay")
    func shouldClear() {
        #expect(SecretClipboard.shouldClear(currentChangeCount: 7, copiedChangeCount: 7))
        #expect(!SecretClipboard.shouldClear(currentChangeCount: 8, copiedChangeCount: 7))
        #expect(SecretClipboard.clearDelay == .seconds(60))
    }
}

@Suite("Quitting waits for running work")
@MainActor
struct RunningWorkTests {
    @Test("Idle by default; busy while any work runs, counted per kind")
    func counting() {
        let work = RunningWork()
        #expect(!work.isBusy)
        work.begin(.trashSweep)
        work.begin(.homebrew)
        work.begin(.homebrew)
        #expect(work.kinds == [.trashSweep, .homebrew])
        work.end(.homebrew)
        #expect(work.kinds == [.trashSweep, .homebrew])
        work.end(.homebrew)
        work.end(.trashSweep)
        #expect(!work.isBusy)
        work.end(.trashSweep)   // an extra end never goes negative
        #expect(!work.isBusy)
    }

    @Test("run counts the work and always ends it")
    func runWrapper() async {
        let work = RunningWork()
        let seenBusy = await work.run(.homebrew) { work.isBusy }
        #expect(seenBusy)
        #expect(!work.isBusy)
    }

    @Test("Closing the last window quits only when idle, else after the work ends")
    func windowCloseHeld() {
        let work = RunningWork()
        var quits = 0
        work.onIdleAfterLastWindowClosed = { quits += 1 }
        #expect(work.shouldQuitAfterLastWindowClosed())

        work.begin(.trashSweep)
        #expect(!work.shouldQuitAfterLastWindowClosed())
        #expect(quits == 0)
        work.end(.trashSweep)
        #expect(quits == 1)

        // Work that ends without a window close does not quit.
        work.begin(.homebrew)
        work.end(.homebrew)
        #expect(quits == 1)
    }

    @Test("The refusal names the sweep first, then brew")
    func refusalText() {
        #expect(RunningWork.refusalText(for: [.trashSweep]).title == "Sift is still moving items to the Trash")
        #expect(RunningWork.refusalText(for: [.trashSweep, .homebrew]).title == "Sift is still moving items to the Trash")
        #expect(RunningWork.refusalText(for: [.homebrew]).title == "Sift is still running Homebrew")
    }
}

@Suite("Name-only folders another app may own")
struct SharedNameLeftoverTests {
    @Test("Same name or one name starting with the other is shared")
    func sharers() {
        #expect(LeftoverMatcher.nameSharers(appName: "1Password", otherAppNames: ["1Password 7", "Bear"]) == ["1Password 7"])
        #expect(LeftoverMatcher.nameSharers(appName: "1Password 7", otherAppNames: ["1Password"]) == ["1Password"])
        #expect(LeftoverMatcher.nameSharers(appName: "Notion", otherAppNames: ["notion"]) == ["notion"])
    }

    @Test("Unrelated names are not shared")
    func unrelated() {
        #expect(LeftoverMatcher.nameSharers(appName: "1Password", otherAppNames: ["Bear", "Password Hub", ""]).isEmpty)
        #expect(LeftoverMatcher.nameSharers(appName: "Bloom", otherAppNames: []).isEmpty)
    }

    @Test("The reason names who else may use the folder")
    func reasonText() {
        let one = LeftoverMatcher.sharedNameReason(appName: "1Password", sharers: ["1Password 7"])
        #expect(one.contains("1Password 7"))
        #expect(one.contains("unchecked"))
        let many = LeftoverMatcher.sharedNameReason(appName: "Foo", sharers: ["Foo A", "Foo B", "Foo C"])
        #expect(many.contains("Foo A and Foo B and others"))
    }

    @Test("Shared-name rows start unchecked; the rest stays as before")
    func initialChecks() {
        let url = URL(fileURLWithPath: "/tmp/x")
        let bundle = LeftoverItem(id: "bundle", url: url, category: .application, sizeBytes: 1, reason: "", isAppBundle: true)
        let own = LeftoverItem(id: "own", url: url, category: .caches, sizeBytes: 1, reason: "")
        let shared = LeftoverItem(id: "shared", url: url, category: .applicationSupport, sizeBytes: 1, reason: "", startsUnchecked: true)
        #expect(UninstallSweep.initiallyChecked([bundle, own, shared], hasOtherCopy: false) == ["bundle", "own"])
        #expect(UninstallSweep.initiallyChecked([bundle, own, shared], hasOtherCopy: true) == ["bundle"])
    }
}

@Suite("Finder handoff does not block the window")
struct FinderHandoffTests {
    @Test("A quick answer comes back")
    func quickAnswer() async {
        let value = await TrashService.waitAtMost(5) { 42 }
        #expect(value == 42)
    }

    @Test("A slow answer is given up on at the deadline")
    func deadline() async {
        let start = Date()
        let value = await TrashService.waitAtMost(0.2) { () -> Int in
            Thread.sleep(forTimeInterval: 2)
            return 42
        }
        #expect(value == nil)
        #expect(Date().timeIntervalSince(start) < 1.5)
    }

    @Test("The work runs off the main thread")
    func offMain() async {
        let onMain = await TrashService.waitAtMost(5) { Thread.isMainThread }
        #expect(onMain == false)
    }

    @Test("A timeout is reported in plain words")
    func timeoutReason() {
        #expect(TrashService.finderTimeout == 30)
        #expect(TrashService.timeoutReason.contains("30 seconds"))
    }
}

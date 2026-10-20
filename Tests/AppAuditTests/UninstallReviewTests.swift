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

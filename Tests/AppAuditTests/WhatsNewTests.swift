import Testing
import Foundation
@testable import Sift

/// The What's new sheet: shown once after an update, never on a first install.
@Suite("What's new")
struct WhatsNewTests {
    @Test("Sift's notes: bold headings and bullets, the sentences around them left out")
    func parsesSiftNotes() {
        let notes = """
        Sift 1.12.3 keeps your license keys locked until you ask for them.

        **License panel**
        - Opening an app no longer reads its license key.
        - **Reveal:** asks for Touch ID first.

        Your data and license keys carry over untouched.
        """
        let lines = WhatsNew.parse(notes)
        #expect(lines.count == 3)
        #expect(lines.first == .heading("License panel"))
        if case .bullet(let text) = lines[2] {
            #expect(String(text.characters) == "Reveal: asks for Touch ID first.")
        } else {
            Issue.record("expected a bullet")
        }
    }

    @Test("Template headings still work, long ones too")
    func parsesTemplateHeadings() {
        let long = WhatsNew.parse("Fixes in 0.5.2 (the second Argon code review, all 15 items, plus one freeze found while testing)\n- **One:** fix.")
        #expect(long.first == .heading("Fixes in 0.5.2 (the second Argon code review, all 15 items, plus one freeze found while testing)"))
    }

    @Test("Nothing shows on a first install or without notes")
    func shownOnlyAfterUpdate() throws {
        let defaults = try #require(UserDefaults(suiteName: "sift-whatsnew-\(UUID().uuidString)"))
        // The test bundle has no version and no notes: nothing to show, ever.
        #expect(!WhatsNew.shouldShow(defaults: defaults))
        defaults.set("0.0.1", forKey: WhatsNew.lastSeenKey)
        #expect(!WhatsNew.shouldShow(defaults: defaults))
    }

    @Test("Every release notes file parses to something")
    func releaseNotesParse() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/releases")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
        #expect(!files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!WhatsNew.parse(text).isEmpty, "\(file.lastPathComponent) shows nothing")
        }
    }
}

import Testing
import Foundation
@testable import Sift

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

/// Fixes from the 2026-10-24 review card. One suite per finding.

@Suite("Brew uninstall is not the Trash")
struct BrewUninstallCopyTests {
    @Test("A brew removal says removed by Homebrew, not in the Trash")
    func brewRemoval() {
        let line = UninstallDoneCopy.success(homebrewRemovedTheApp: true)
        #expect(line.contains("Removed by Homebrew"))
        #expect(line.contains("not in the Trash"))
        #expect(!line.contains("Moved to Trash"))
    }

    @Test("A normal sweep still says the files went to the Trash")
    func trashSweep() {
        let line = UninstallDoneCopy.success(homebrewRemovedTheApp: false)
        #expect(line.contains("Moved to Trash"))
        #expect(line.contains("license record"))
    }

    @Test("The README no longer says a brew removal deletes nothing")
    func readme() throws {
        let text = try String(contentsOf: repoRoot.appending(path: "README.md"), encoding: .utf8)
        #expect(text.contains("not in the Trash"))
        #expect(!text.localizedCaseInsensitiveContains("nothing is deleted"))
    }
}

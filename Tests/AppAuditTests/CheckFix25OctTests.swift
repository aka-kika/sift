import Testing
import Foundation
import AppKit
@testable import Sift

/// Fixes from the 2026-10-25 second check of the 24 Oct review branch.
/// One suite per finding.

@Suite("A change saved during a scan is analyzed after it")
@MainActor
struct QueuedReanalysisTests {
    @Test("A saved link during an analysis waits in the queue instead of being dropped")
    func queuedWhileBusy() async {
        let viewModel = AppListViewModel()
        viewModel.scanState = .enriching(completed: 1, total: 4)
        await viewModel.reanalyze(bundleID: "com.example.notes", appURL: "https://example.com")
        #expect(viewModel.queuedReanalysis.map(\.bundleID) == ["com.example.notes"])
        #expect(viewModel.queuedReanalysis.first?.appURL == "https://example.com")
    }

    @Test("Saving twice keeps one entry with the newest link")
    func newestLinkWins() async {
        let viewModel = AppListViewModel()
        viewModel.scanState = .scanning
        await viewModel.reanalyze(bundleID: "com.example.notes", appURL: "https://old.example.com")
        await viewModel.reanalyze(bundleID: "com.example.other")
        await viewModel.reanalyze(bundleID: "com.example.notes", appURL: "https://new.example.com")
        #expect(viewModel.queuedReanalysis.map(\.bundleID) == ["com.example.other", "com.example.notes"])
        #expect(viewModel.queuedReanalysis.last?.appURL == "https://new.example.com")
    }

    @Test("With no scan running nothing is queued")
    func notQueuedWhenIdle() async {
        let viewModel = AppListViewModel()
        viewModel.scanState = .done
        await viewModel.reanalyze(bundleID: "com.example.notes")
        #expect(viewModel.queuedReanalysis.isEmpty)
    }
}

@Suite("An app with a dot in its name can still go to Finder")
struct DottedAppBundleTests {
    @Test("The sweep hands zoom.us.app over as the app bundle")
    func dottedNameIsTheBundle() async {
        let zoom = URL(fileURLWithPath: "/Applications/zoom.us.app")
        let cache = URL(fileURLWithPath: "/Users/me/Library/Caches/us.zoom.xos")
        let items = [
            LeftoverItem(id: cache.path, url: cache, category: .caches, sizeBytes: 1, reason: "cache"),
            LeftoverItem(id: zoom.path, url: zoom, category: .application, sizeBytes: 1, reason: "bundle", isAppBundle: true),
        ]
        var handed: [(String, Bool)] = []
        _ = await UninstallSweep.run(items) { item in
            handed.append((item.url.lastPathComponent, item.isAppBundle))
            return nil
        }
        #expect(handed.map(\.0) == ["zoom.us.app", "us.zoom.xos"])
        #expect(handed.map(\.1) == [true, false])
        let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        #expect(TrashService.shouldAskFinder(isAppBundle: handed[0].1, error: denied))
    }
}

@Suite("A brew warning does not turn every cask Up to date")
struct BrewOutdatedStdoutTests {
    private let json = Data(#"{"formulae":[],"casks":[{"name":"ghostty","installed_versions":["1.1.0"],"current_version":"1.2.0"}]}"#.utf8)

    @Test("Clean JSON on stdout lists the outdated casks")
    func clean() {
        #expect(HomebrewService.outdatedAnswer(exitStatus: 0, standardOutput: json)
                == .list([HomebrewCaskInfo(token: "ghostty", latestVersion: "1.2.0")]))
    }

    @Test("Output that is not JSON is a failed check, not an empty list")
    func garbled() {
        let mixed = Data("Warning: Calling brew from a Rosetta shell\n".utf8) + json
        #expect(HomebrewService.outdatedAnswer(exitStatus: 0, standardOutput: mixed) == .failed)
    }

    @Test("A non-zero exit is a failed check")
    func nonZero() {
        #expect(HomebrewService.outdatedAnswer(exitStatus: 1, standardOutput: json) == .failed)
        #expect(HomebrewService.outdatedAnswer(exitStatus: nil, standardOutput: Data()) == .failed)
    }
}

@Suite("A Homebrew build after the comma only breaks a tie")
struct CaskBuildVersionTests {
    @Test("1.3.0,999 is current for an installed 1.3.0 build 999")
    func sameBuild() {
        #expect(!UpdateChecker.isCaskVersion("1.3.0,999", newerThanVersion: "1.3.0", build: "999"))
    }

    @Test("1.3.0,999 is current when the app states no build")
    func noBuild() {
        #expect(!UpdateChecker.isCaskVersion("1.3.0,999", newerThanVersion: "1.3.0", build: nil))
    }

    @Test("A newer build under the same version is an update")
    func newerBuild() {
        #expect(UpdateChecker.isCaskVersion("1.3.0,999", newerThanVersion: "1.3.0", build: "998"))
    }

    @Test("A newer version is an update whatever the build")
    func newerVersion() {
        #expect(UpdateChecker.isCaskVersion("1.4.0,1", newerThanVersion: "1.3.0", build: "999"))
        #expect(UpdateChecker.isCaskVersion("1.4.0", newerThanVersion: "1.3.0", build: nil))
        #expect(!UpdateChecker.isCaskVersion("1.3.0", newerThanVersion: "1.3.0", build: nil))
    }
}

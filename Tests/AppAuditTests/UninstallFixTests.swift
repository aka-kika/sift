import Testing
import Foundation
@testable import Sift

/// Fixes from the 2026-10-20 uninstall review.

/// The repo root, found from this file's own path (Tests/AppAuditTests/…).
private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

@Suite("Finder handoff signing")
struct FinderHandoffSigningTests {
    @Test("The signed app may send Apple Events, or hardened runtime blocks Finder")
    func appleEventsEntitlement() throws {
        let url = repoRoot.appending(path: "Sources/AppAudit/AppAudit.entitlements")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        #expect(plist?["com.apple.security.automation.apple-events"] as? Bool == true)
    }

    @Test("Info.plist explains the Finder prompt")
    func usageDescription() throws {
        let script = try String(contentsOf: repoRoot.appending(path: "Scripts/package_app.sh"), encoding: .utf8)
        #expect(script.contains("<key>NSAppleEventsUsageDescription</key>"))
        // Both signing modes sign the app with the entitlements file.
        #expect(script.contains("--entitlements \"$ENTITLEMENTS\" \"$APP\""))
    }
}

@Suite("brew uninstall only for the cask's own bundle")
struct CaskOwnershipTests {
    private let receipt = Data("""
    {"uninstall_artifacts": [
      {"app": ["Ghostty.app"]},
      {"manpage": ["/Applications/Ghostty.app/Contents/Resources/man/man1/ghostty.1"]},
      {"app": ["Payload/Beta Tool.app", {"target": "Tool Beta.app"}]},
      {"app": ["Other.app", {"target": "~/Apps/Other.app"}]},
      {"zap": [{"trash": ["~/Library/Caches/com.mitchellh.ghostty"]}]}
    ]}
    """.utf8)

    @Test("App artifacts resolve to their installed paths")
    func appPaths() {
        let paths = HomebrewService.appPaths(fromReceipt: receipt, appdir: "/Applications")
        #expect(paths == ["/Applications/Ghostty.app",
                          "/Applications/Tool Beta.app",
                          NSHomeDirectory() + "/Apps/Other.app"])
    }

    @Test("An explicit --appdir wins over brew's default")
    func appdir() {
        let config = Data(#"{"default":{"appdir":"/Applications"},"explicit":{"appdir":"/Users/me/Applications"}}"#.utf8)
        #expect(HomebrewService.installedAppdir(fromConfig: config) == "/Users/me/Applications")
        #expect(HomebrewService.installedAppdir(fromConfig: Data(#"{"default":{"appdir":"/Apps"},"explicit":{}}"#.utf8)) == "/Apps")
        #expect(HomebrewService.installedAppdir(fromConfig: nil) == "/Applications")
    }

    @Test("Only the bundle brew installed belongs to the cask")
    func ownership() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SiftCaskroom-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let caskroom = root.appending(path: "Caskroom")
        let appdir = root.appending(path: "Applications")
        let metadata = caskroom.appending(path: "ghostty/.metadata")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appdir.appending(path: "Ghostty.app"), withIntermediateDirectories: true)
        try receipt.write(to: metadata.appending(path: "INSTALL_RECEIPT.json"))
        try Data(#"{"default":{"appdir":"\#(appdir.path)"},"explicit":{}}"#.utf8)
            .write(to: metadata.appending(path: "config.json"))
        let roots = [caskroom.path]

        // The copy brew put in the appdir is the cask's.
        #expect(HomebrewService.caskOwnsBundle(token: "ghostty", bundlePath: appdir.appending(path: "Ghostty.app").path,
                                               caskroomRoots: roots))
        // A manual copy with the same name elsewhere is not.
        #expect(!HomebrewService.caskOwnsBundle(token: "ghostty", bundlePath: "/Users/me/Downloads/Ghostty.app",
                                                caskroomRoots: roots))
        // Nor is a beta whose name only normalises to the token.
        #expect(!HomebrewService.caskOwnsBundle(token: "ghostty", bundlePath: appdir.appending(path: "Ghostty Beta.app").path,
                                                caskroomRoots: roots))
        // No install record: never offer brew.
        #expect(!HomebrewService.caskOwnsBundle(token: "firefox", bundlePath: appdir.appending(path: "Firefox.app").path,
                                                caskroomRoots: roots))
        // An app left inside the Caskroom is the cask's by location.
        #expect(HomebrewService.caskOwnsBundle(token: "ghostty", bundlePath: caskroom.appending(path: "ghostty/1.0/Ghostty.app").path,
                                               caskroomRoots: roots))
    }
}

@Suite("Copies outside the scanned folders")
struct AppCopyFinderTests {
    private let this = "/Applications/Reed.app"

    @Test("Spotlight finding only this copy means data can be pre-checked")
    func onlyThisCopy() {
        #expect(AppCopyFinder.classify(found: [this], thisPath: this) == .onlyThisCopy)
    }

    @Test("A copy in Downloads is another copy")
    func downloadsCopy() {
        let downloads = "/Users/me/Downloads/Reed.app"
        #expect(AppCopyFinder.classify(found: [this, downloads], thisPath: this) == .others([downloads]))
    }

    @Test("Scanned and Spotlight copies merge without repeats")
    func merge() {
        let test = "/Applications/Reed Test.app"
        let toolbox = "/Users/me/Applications/JetBrains Toolbox/Reed.app"
        #expect(AppCopyFinder.classify(found: [this, test, toolbox], thisPath: this, knownOtherPaths: [test])
                == .others([test, toolbox]))
    }

    @Test("Helpers inside this app and copies in the Trash do not count")
    func ignoredPaths() {
        let found = [this, this + "/Contents/Helpers/Reed Helper.app", "/Users/me/.Trash/Reed.app"]
        #expect(AppCopyFinder.classify(found: found, thisPath: this) == .onlyThisCopy)
    }

    @Test("No answer, or an answer missing this copy, is a maybe")
    func failSafe() {
        #expect(AppCopyFinder.classify(found: nil, thisPath: this) == .unknown)
        #expect(AppCopyFinder.classify(found: [], thisPath: this) == .unknown)
        // A failed query still reports the copies Sift scanned itself.
        #expect(AppCopyFinder.classify(found: nil, thisPath: this, knownOtherPaths: ["/Applications/Reed Test.app"])
                == .others(["/Applications/Reed Test.app"]))
    }

    @Test("The query escapes quotes in the bundle ID")
    func queryEscaping() {
        #expect(AppCopyFinder.queryString(bundleID: "com.example.reed")
                == #"kMDItemContentType == "com.apple.application-bundle" && kMDItemCFBundleIdentifier == "com.example.reed""#)
        #expect(AppCopyFinder.queryString(bundleID: #"a"b\c"#).hasSuffix(#"== "a\"b\\c""#))
    }

    @Test("Spotlight answers or gives up in time")
    func timeout() async {
        let start = ContinuousClock.now
        _ = await AppCopyFinder.spotlightPaths(bundleID: "com.example.sift-test-none", timeout: .milliseconds(500))
        #expect(ContinuousClock.now - start < .seconds(2))
        #expect(await AppCopyFinder.spotlightPaths(bundleID: "") == nil)
    }
}

@Suite("Uninstall sweep stops at a stuck bundle")
@MainActor
struct UninstallSweepTests {
    private func item(_ path: String, bundle: Bool = false) -> LeftoverItem {
        LeftoverItem(id: path, url: URL(fileURLWithPath: path),
                     category: bundle ? .application : .applicationSupport,
                     sizeBytes: 1, reason: "test", isAppBundle: bundle)
    }

    private var targets: [LeftoverItem] {
        [item("/Users/me/Library/Application Support/com.example.reed"),
         item("/Applications/Reed.app", bundle: true),
         item("/Users/me/Library/Caches/com.example.reed")]
    }

    @Test("The bundle is tried first, wherever it sits in the list")
    func bundleFirst() {
        #expect(UninstallSweep.ordered(targets).first?.isAppBundle == true)
        #expect(UninstallSweep.ordered(targets).count == 3)
    }

    @Test("A bundle that stays put keeps every piece of data")
    func stopsWhenBundleFails() async {
        var tried: [String] = []
        let outcome = await UninstallSweep.run(targets) { item in
            tried.append(item.url.path)
            return item.isAppBundle ? TrashService.Failure(path: item.url.path, reason: "locked") : nil
        }
        #expect(tried == ["/Applications/Reed.app"])
        #expect(outcome.stoppedAtBundle)
        #expect(!outcome.removedBundle)
        #expect(outcome.skipped == 2)
        #expect(outcome.failures.map(\.path) == ["/Applications/Reed.app"])
    }

    @Test("A moved bundle lets the data follow")
    func continuesWhenBundleMoves() async {
        var tried: [String] = []
        let outcome = await UninstallSweep.run(targets) { item in
            tried.append(item.url.path)
            return nil
        }
        #expect(tried.count == 3)
        #expect(outcome.removedBundle)
        #expect(!outcome.stoppedAtBundle)
    }

    @Test("A stuck data folder does not stop the rest")
    func dataFailureContinues() async {
        let outcome = await UninstallSweep.run(targets) { item in
            item.url.path.contains("Application Support") ? TrashService.Failure(path: item.url.path, reason: "busy") : nil
        }
        #expect(outcome.removedBundle)
        #expect(!outcome.stoppedAtBundle)
        #expect(outcome.failures.count == 1)
    }

    // The sheet asks before a data-only sweep (needsDataOnlyConfirmation);
    // once confirmed, the sweep itself moves the data.
    @Test("Data alone, confirmed with the bundle unchecked, sweeps")
    func dataOnly() async {
        let outcome = await UninstallSweep.run(targets.filter { !$0.isAppBundle }) { _ in nil }
        #expect(!outcome.removedBundle)
        #expect(!outcome.stoppedAtBundle)
        #expect(outcome.failures.isEmpty)
    }
}

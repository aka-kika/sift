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
        let outcome = await UninstallSweep.run(targets) { url in
            tried.append(url.path)
            return url.pathExtension == "app" ? TrashService.Failure(path: url.path, reason: "locked") : nil
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
        let outcome = await UninstallSweep.run(targets) { url in
            tried.append(url.path)
            return nil
        }
        #expect(tried.count == 3)
        #expect(outcome.removedBundle)
        #expect(!outcome.stoppedAtBundle)
    }

    @Test("A stuck data folder does not stop the rest")
    func dataFailureContinues() async {
        let outcome = await UninstallSweep.run(targets) { url in
            url.path.contains("Application Support") ? TrashService.Failure(path: url.path, reason: "busy") : nil
        }
        #expect(outcome.removedBundle)
        #expect(!outcome.stoppedAtBundle)
        #expect(outcome.failures.count == 1)
    }

    @Test("Data alone, with the bundle unchecked, still sweeps")
    func dataOnly() async {
        let outcome = await UninstallSweep.run(targets.filter { !$0.isAppBundle }) { _ in nil }
        #expect(!outcome.removedBundle)
        #expect(!outcome.stoppedAtBundle)
        #expect(outcome.failures.isEmpty)
    }
}

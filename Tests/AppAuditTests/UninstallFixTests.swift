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

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

@Suite("Replace a saved licence key")
struct LicenseKeyReplaceTests {
    @Test("A cancelled Touch ID prompt does not unlock the field")
    func denied() {
        #expect(!LicenseKeyReplace.mayUnlock(authenticated: false))
    }

    @Test("Touch ID success is what opens the empty field")
    func allowed() {
        #expect(LicenseKeyReplace.mayUnlock(authenticated: true))
    }

    @Test("The Replace button does not unlock the field itself")
    func buttonAsksFirst() throws {
        let source = try String(contentsOf: repoRoot.appending(path: "Sources/AppAudit/Views/MoneyPopover.swift"), encoding: .utf8)
        guard let start = source.range(of: "Button(\"Replace\")") else {
            Issue.record("Replace button missing")
            return
        }
        let window = source[start.upperBound...].prefix(180)
        #expect(window.contains("onReplaceKey()"))
        #expect(!window.contains("keyUnlocked"))
    }
}

@Suite("No link fetch when update checks are off")
struct ScanNetworkTests {
    @Test("The switch off means the saved link page is not fetched")
    func off() {
        #expect(!ScanNetwork.fetchesSavedLinkPage(checksUpdatesOnScan: false))
    }

    @Test("The switch on still fetches the saved link page")
    func on() {
        #expect(ScanNetwork.fetchesSavedLinkPage(checksUpdatesOnScan: true))
    }

    @Test("Analysis uses that decision before it fetches")
    func wired() throws {
        let source = try String(contentsOf: repoRoot.appending(path: "Sources/AppAudit/ViewModels/AppListViewModel.swift"), encoding: .utf8)
        #expect(source.contains("ScanNetwork.fetchesSavedLinkPage(checksUpdatesOnScan: Self.checksUpdatesOnScan())"))
    }
}

@Suite("Keychain errors do not clear licence flags")
struct LicenseFlagOnKeychainErrorTests {
    @Test("Item not found is the only answer that clears the flag")
    func absent() {
        #expect(LicenseKeyStore.flag(current: true, presence: .absent) == false)
        #expect(KeychainSecretStoreBackend.presence(for: errSecItemNotFound) == .absent)
    }

    @Test("A locked or denied keychain leaves the flag as it was")
    func unknown() {
        #expect(LicenseKeyStore.flag(current: true, presence: .unknown) == true)
        #expect(LicenseKeyStore.flag(current: false, presence: .unknown) == false)
        #expect(KeychainSecretStoreBackend.presence(for: errSecInteractionNotAllowed) == .unknown)
        #expect(KeychainSecretStoreBackend.presence(for: errSecAuthFailed) == .unknown)
    }

    @Test("A found item sets the flag")
    func present() {
        #expect(LicenseKeyStore.flag(current: false, presence: .present) == true)
        #expect(KeychainSecretStoreBackend.presence(for: errSecSuccess) == .present)
    }
}

@Suite("Subscriptions belong in the License Vault")
struct VaultSubscriptionTests {
    @Test("A subscription alone is a purchase")
    func subscriptionOnly() {
        #expect(VaultMembership.includes(hasLicenseKey: false, isPaidApp: false, hasLicenseType: false, hasSubscription: true))
    }

    @Test("Nothing bought stays out")
    func empty() {
        #expect(!VaultMembership.includes(hasLicenseKey: false, isPaidApp: false, hasLicenseType: false, hasSubscription: false))
    }

    @Test("The vault query includes hasSubscription")
    func query() throws {
        let source = try String(contentsOf: repoRoot.appending(path: "Sources/AppAudit/Views/LicenseVaultView.swift"), encoding: .utf8)
        #expect(source.contains("$0.hasSubscription"))
    }
}

@Suite("Subscription renewal stays empty until picked")
struct SubscriptionRenewalDraftTests {
    @Test("An untouched draft stores no date")
    func untouched() {
        #expect(SubscriptionMath.renewalToStore(draft: nil) == nil)
    }

    @Test("A date the user picked is the one stored")
    func picked() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(SubscriptionMath.renewalToStore(draft: date) == date)
    }

    @Test("Opening the panel does not invent today")
    func noDefaultToday() throws {
        let source = try String(contentsOf: repoRoot.appending(path: "Sources/AppAudit/Views/AppDetailView.swift"), encoding: .utf8)
        #expect(!source.contains("subscriptionRenewalDate ?? Date()"))
        #expect(source.contains("SubscriptionMath.renewalToStore(draft: draftSubRenewal)"))
    }
}

@Suite("Cloud prompts hide the account name in paths")
struct PromptPathTests {
    @Test("A path under the home folder is written with a tilde")
    func home() {
        let path = NSHomeDirectory() + "/Applications/Example.app"
        #expect(AppAnalysisPrompt.promptPath(path) == "~/Applications/Example.app")
        #expect(!AppAnalysisPrompt.promptPath(path).contains(NSUserName()))
    }

    @Test("A path outside the home folder stays as it is")
    func applications() {
        #expect(AppAnalysisPrompt.promptPath("/Applications/Example.app") == "/Applications/Example.app")
    }
}

@Suite("The sidebar list stays during a rescan")
struct SidebarDuringScanTests {
    @Test("A loaded list is not replaced by the spinner")
    func rescan() {
        #expect(!SidebarDuringScan.showsSpinner(hasApps: true, phase: .waiting))
    }

    @Test("The first scan, with nothing loaded, still shows the spinner")
    func firstScan() {
        #expect(SidebarDuringScan.showsSpinner(hasApps: false, phase: .waiting))
    }

    @Test("A finished scan with no apps shows the empty state, not the spinner")
    func emptyDone() {
        #expect(!SidebarDuringScan.showsSpinner(hasApps: false, phase: .ready))
    }
}

@Suite("Rescan waits while an analysis is running")
struct ScanCommandsBusyTests {
    @Test("Scanning and analyzing block another rescan")
    func busy() {
        #expect(AppListViewModel.ScanCommands.isBusy(.scanning))
        #expect(AppListViewModel.ScanCommands.isBusy(.enriching(completed: 1, total: 4)))
        #expect(!AppListViewModel.ScanCommands.busyReason.isEmpty)
    }

    @Test("An idle or finished scan can be started")
    func free() {
        #expect(!AppListViewModel.ScanCommands.isBusy(.idle))
        #expect(!AppListViewModel.ScanCommands.isBusy(.done))
        #expect(!AppListViewModel.ScanCommands.isBusy(.error("x")))
    }
}

@Suite("Brew uninstall can finish the sheet")
struct BrewUninstallFooterTests {
    @Test("Nothing left to sweep offers Done and reports the app removed")
    func done() {
        #expect(BrewUninstallFooter.action(homebrewRemovedTheApp: true, anythingChecked: false) == .doneRemoved)
    }

    @Test("Checked leftovers still go to the Trash")
    func leftovers() {
        #expect(BrewUninstallFooter.action(homebrewRemovedTheApp: true, anythingChecked: true) == .moveToTrash)
        #expect(BrewUninstallFooter.action(homebrewRemovedTheApp: false, anythingChecked: false) == .moveToTrash)
    }

    @Test("The brew button is disabled while brew runs")
    func running() {
        #expect(!BrewUninstallFooter.brewButtonEnabled(running: true))
        #expect(BrewUninstallFooter.brewButtonEnabled(running: false))
    }
}

@Suite("Edge Canary is not an Apple system app")
struct EdgeCanaryScanTests {
    @Test("Edge Canary stays in the list")
    func edge() {
        #expect(!AppScanner.isHiddenAsSystemApp("com.microsoft.edgemac.Canary"))
    }

    @Test("Apple's own apps stay hidden behind the existing toggle")
    func apple() {
        #expect(AppScanner.isHiddenAsSystemApp("com.apple.Safari"))
        #expect(!AppScanner.isHiddenAsSystemApp("com.example.app"))
    }
}

@Suite("A Sparkle build number is not a marketing version")
struct SparkleBuildOnlyTests {
    private let xml = """
    <rss><channel><item>
      <enclosure url="https://example.com/App.zip" sparkle:version="2045" length="1" type="application/octet-stream"/>
    </item></channel></rss>
    """

    @Test("Only sparkle:version is stored as the build")
    func parsed() throws {
        let meta = try UpdateChecker.parseSparkleMetadata(from: Data(xml.utf8))
        #expect(meta?.version.isEmpty == true)
        #expect(meta?.build == "2045")
    }

    @Test("It is newer only than an older build, and the label keeps the installed version")
    func compared() throws {
        let meta = try UpdateChecker.parseSparkleMetadata(from: Data(xml.utf8))
        let item = try #require(meta)
        #expect(!UpdateChecker.isRelease(item, newerThanVersion: "1.2.3", build: "3000"))
        #expect(!UpdateChecker.isRelease(item, newerThanVersion: "1.2.3", build: nil))
        #expect(UpdateChecker.isRelease(item, newerThanVersion: "1.2.3", build: "100"))
        #expect(item.displayVersion(installedVersion: "1.2.3") == "1.2.3 (2045)")
        #expect(item.displayVersion(installedVersion: "1.2.3") != "2045")
    }
}

@Suite("App Store skips a release this Mac cannot run")
struct AppStoreMinimumOSTests {
    private func json(minimum: String) -> Data {
        Data("""
        {"results":[{"bundleId":"com.example.Bloom","version":"9.0","trackId":1,"minimumOsVersion":"\(minimum)"}]}
        """.utf8)
    }

    @Test("A release that needs a newer macOS is not offered")
    func tooNew() throws {
        let meta = try UpdateChecker.parseAppStoreMetadata(from: json(minimum: "99.0"), preferredBundleID: "com.example.Bloom", systemVersion: "15.0.0")
        #expect(meta == nil)
        #expect(!UpdateChecker.runsOnThisMac(minimumOS: "99.0", systemVersion: "15.0.0"))
    }

    @Test("A release this Mac can run is still offered")
    func runnable() throws {
        let meta = try UpdateChecker.parseAppStoreMetadata(from: json(minimum: "14.0"), preferredBundleID: "com.example.Bloom", systemVersion: "15.0.0")
        #expect(meta?.version == "9.0")
        #expect(UpdateChecker.runsOnThisMac(minimumOS: nil, systemVersion: "15.0.0"))
    }
}

@Suite("The crash guide does not delete the store")
struct StoreRecoveryGuideTests {
    @Test("It says move the store to the Desktop")
    func desktop() throws {
        let text = try String(contentsOf: repoRoot.appending(path: "docs/README.md"), encoding: .utf8)
        #expect(text.contains("mv ~/Library/Application\\ Support/AppAudit/AppAudit.store* ~/Desktop/"))
        #expect(!text.contains("rm ~/Library/Application\\ Support/AppAudit/AppAudit.store*"))
    }
}

@Suite("Lifetime, Free and My App outrank a leftover subscription")
struct SubscriptionOutrankedTests {
    @Test("Lifetime, one-time, Free and My App hide the subscription face")
    func hidden() {
        #expect(MoneyCubeState.derive(isAppStoreInstall: false, hasLicenseKey: false, isPaidApp: false,
                                      hasSubscription: true, renewalNear: false, isFreeApp: false,
                                      licenseType: .lifetime) == .licensed(.lifetime))
        #expect(MoneyCubeState.derive(isAppStoreInstall: false, hasLicenseKey: false, isPaidApp: false,
                                      hasSubscription: true, renewalNear: false, isFreeApp: false,
                                      licenseType: .oneTime) == .licensed(.oneTime))
        #expect(MoneyCubeState.derive(isAppStoreInstall: false, hasLicenseKey: false, isPaidApp: false,
                                      hasSubscription: true, renewalNear: false, isFreeApp: true) == .free)
        #expect(MoneyCubeState.derive(isAppStoreInstall: false, hasLicenseKey: false, isPaidApp: false,
                                      hasSubscription: true, renewalNear: false, isFreeApp: false,
                                      isMyApp: true) == .none)
    }

    @Test("Remove subscription is outside the disabled section")
    func removeStays() throws {
        let source = try String(contentsOf: repoRoot.appending(path: "Sources/AppAudit/Views/MoneyPopover.swift"), encoding: .utf8)
        guard let disabled = source.range(of: ".disabled(subscriptionDisabled)"),
              let remove = source.range(of: "Remove subscription") else {
            Issue.record("subscription section markers missing")
            return
        }
        #expect(remove.lowerBound > disabled.upperBound)
    }
}

@Suite("Short bundle IDs do not claim other apps' files")
struct ShortBundleIDTests {
    @Test("Two-part IDs, including com.apple and com.google, match nothing")
    func short() {
        #expect(!LeftoverMatcher.isSpecificBundleID("com.apple"))
        #expect(!LeftoverMatcher.isSpecificBundleID("com.google"))
        #expect(!LeftoverMatcher.matches(name: "com.apple.Safari.plist", bundleID: "com.apple"))
        #expect(!LeftoverMatcher.matches(name: "com.google.Chrome", bundleID: "com.google"))
    }

    @Test("A normal three-part ID still matches its own files")
    func normal() {
        #expect(LeftoverMatcher.isSpecificBundleID("com.example.app"))
        #expect(LeftoverMatcher.matches(name: "com.example.app.plist", bundleID: "com.example.app"))
    }
}

@Suite("Finder is only for the app bundle")
struct FinderOnlyForAppBundleTests {
    private var denied: NSError {
        NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
    }

    @Test("A root-owned app bundle may go to Finder")
    func app() {
        let url = URL(fileURLWithPath: "/Applications/Example.app")
        #expect(TrashService.shouldAskFinder(url: url, error: denied))
    }

    @Test("A leftover does not, even when its folder name ends in .app")
    func leftover() {
        let url = URL(fileURLWithPath: "/Users/me/Library/Caches/com.example.app")
        #expect(TrashService.isAppBundlePath("/Applications/Example.app"))
        #expect(!TrashService.isAppBundlePath(url.path))
        #expect(!TrashService.shouldAskFinder(url: url, error: denied))
        let other = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        #expect(!TrashService.shouldAskFinder(url: URL(fileURLWithPath: "/Applications/Example.app"), error: other))
    }
}

@Suite("Launch Agents are unloaded before they are trashed")
struct LaunchAgentUnloadTests {
    @Test("Only a Launch Agent plist is unloaded")
    func category() {
        #expect(LaunchAgentUnload.needsUnload(.launchAgents))
        #expect(!LaunchAgentUnload.needsUnload(.preferences))
    }

    @Test("bootout targets this user's gui domain and the plist")
    func arguments() {
        let args = LaunchAgentUnload.arguments(plistPath: "/Users/me/Library/LaunchAgents/com.example.app.plist", uid: 501)
        #expect(args == ["bootout", "gui/501", "/Users/me/Library/LaunchAgents/com.example.app.plist"])
    }

    @Test("The sweep asks to unload before it trashes")
    func order() async {
        let plist = URL(fileURLWithPath: "/Users/me/Library/LaunchAgents/com.example.app.plist")
        let item = LeftoverItem(id: plist.path, url: plist, category: .launchAgents, sizeBytes: 1, reason: "agent")
        var events: [String] = []
        _ = await UninstallSweep.run([item], beforeTrash: { _ in events.append("unload") }, trash: { _ in
            events.append("trash")
            return nil
        })
        #expect(events == ["unload", "trash"])
    }
}

@Suite("Homebrew's comma is a version separator")
struct HomebrewCommaVersionTests {
    @Test("1.3.0,999 is newer than 1.3.0")
    func newer() {
        #expect(VersionComparator.isNewer("1.3.0,999", than: "1.3.0"))
        #expect(!VersionComparator.isNewer("1.3.0", than: "1.3.0,999"))
    }

    @Test("The same version and build still match")
    func same() {
        #expect(VersionComparator.compare("1.3.0,999", "1.3.0,999") == .orderedSame)
    }
}

@Suite("Cmd-R matches the Updates sort")
struct ScanShortcutTests {
    @Test("The Updates sort refreshes updates")
    func updates() {
        #expect(AppListViewModel.ScanCommands.shortcut(sortIsUpdates: true) == .refreshUpdates)
        #expect(AppListViewModel.ScanCommands.shortcutTitle(sortIsUpdates: true) == "Refresh Updates")
    }

    @Test("Every other sort rescans")
    func rescan() {
        #expect(AppListViewModel.ScanCommands.shortcut(sortIsUpdates: false) == .rescan)
    }
}

@Suite("Licence keys are not called device-bound")
struct LicenseKeyWordingTests {
    @Test("The README matches the login keychain")
    func readme() throws {
        let text = try String(contentsOf: repoRoot.appending(path: "README.md"), encoding: .utf8)
        #expect(text.contains("does not honor a this-device-only flag"))
        #expect(!text.contains("device-bound"))
    }
}

@Suite("Release docs match the release script")
struct ReleaseDocsTests {
    @Test("RELEASE.md uses the identity release.sh signs with")
    func identity() throws {
        let script = try String(contentsOf: repoRoot.appending(path: "Scripts/release.sh"), encoding: .utf8)
        let notes = try String(contentsOf: repoRoot.appending(path: "docs/RELEASE.md"), encoding: .utf8)
        let hash = "7E3E9BC6656A41A13F77F5C05E1663E77419388E"
        #expect(script.contains(hash))
        #expect(notes.contains(hash))
        #expect(!notes.contains("D833417579CBB62121FD344B1513AE5D44A36762"))
    }

    @Test("SECURITY.md supports the current release")
    func supported() throws {
        let text = try String(contentsOf: repoRoot.appending(path: "SECURITY.md"), encoding: .utf8)
        #expect(text.contains("1.12.x"))
        #expect(!text.contains("1.10.x"))
    }
}

@Suite("Analysis labels need a colon")
struct AnalysisLabelTests {
    @Test("A sentence that starts with Reason does not replace the reason")
    func noColon() async {
        let response = """
        EXPLANATION: A notes app.
        SCORE: 4
        REASON: It fits the writing workflow.
        Reason this score is conservative.
        BEST_USE: Keep it for drafts.
        """
        let parsed = await OllamaService().parseAnalysis(from: response)
        #expect(parsed?.reason == "It fits the writing workflow. Reason this score is conservative.")
    }

    @Test("A label on its own line keeps the text on the next line")
    func nextLine() async {
        let response = """
        EXPLANATION:
        A notes app for long writing.
        SCORE:
        3
        REASON:
        Useful once a week.
        BEST_USE:
        Open it for essays.
        """
        let parsed = await OllamaService().parseAnalysis(from: response)
        #expect(parsed?.explanation == "A notes app for long writing.")
        #expect(parsed?.score == 3)
        #expect(parsed?.reason == "Useful once a week.")
        #expect(parsed?.bestUse == "Open it for essays.")
    }
}

@Suite("An app with no name keys still has a name")
struct AppNameFallbackTests {
    @Test("An empty CFBundleName falls through")
    func empty() {
        let plist: NSDictionary = ["CFBundleName": "  ", "CFBundleDisplayName": "Shown"]
        #expect(AppScanner.appName(from: plist, path: "/Applications/Shown.app") == "Shown")
    }

    @Test("No name keys use the file name")
    func file() {
        let plist = NSDictionary()
        #expect(AppScanner.appName(from: plist, path: "/Applications/Tool.app") == "Tool")
    }

    @Test("The executable is used before the file name")
    func executable() {
        let plist: NSDictionary = ["CFBundleExecutable": "Helper"]
        #expect(AppScanner.appName(from: plist, path: "/Applications/Wrapper.app") == "Helper")
    }
}

@Suite("Reserved Library folders are never a name match")
struct ReservedFolderNameTests {
    @Test("CloudDocs, MobileSync and AppAudit stay even if an app has that name")
    func reserved() {
        #expect(!LeftoverMatcher.matchesDisplayName("CloudDocs", appName: "CloudDocs"))
        #expect(!LeftoverMatcher.matchesDisplayName("MobileSync", appName: "MobileSync"))
        #expect(!LeftoverMatcher.matchesDisplayName("AppAudit", appName: "AppAudit"))
    }

    @Test("A normal app name still matches")
    func normal() {
        #expect(LeftoverMatcher.matchesDisplayName("Bloom", appName: "Bloom"))
    }
}

@Suite("A feed of only betas is not an update")
struct SparkleBetaFallbackTests {
    @Test("The fallback does not offer a beta when every item is on a channel")
    func allBeta() throws {
        let xml = """
        <rss><channel>
        <item>
          <sparkle:channel>beta</sparkle:channel>
          <enclosure url="https://example.com/App-2.0b1.zip" sparkle:shortVersionString="2.0" sparkle:version="300"/>
        </item>
        </channel></rss>
        """
        #expect(try UpdateChecker.parseSparkleMetadata(from: Data(xml.utf8)) == nil)
    }
}

@Suite("A symlink is another copy")
struct SymlinkCopyTests {
    @Test("The link and the real app stay different paths")
    func distinct() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "SiftSym-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appending(path: "Real.app")
        let link = root.appending(path: "Link.app")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let result = AppCopyFinder.classify(found: [real.path, link.path], thisPath: link.path)
        #expect(result == .others([AppCopyFinder.canonical(real.path)]))
    }
}

@Suite("Project excerpts go out only for My App")
struct DocsPromptTests {
    @Test("Unmarking My App stops the excerpt, without deleting it from the decision")
    func unmarked() {
        #expect(DocsPrompt.evidenceToSend(isMyApp: false, stored: "README text") == nil)
        #expect(DocsPrompt.evidenceToSend(isMyApp: true, stored: "README text") == "README text")
        #expect(DocsPrompt.evidenceToSend(isMyApp: true, stored: "  ") == nil)
    }
}

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

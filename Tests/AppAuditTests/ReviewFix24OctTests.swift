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

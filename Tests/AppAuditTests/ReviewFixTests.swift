import Testing
import Foundation
import SwiftData
@testable import Sift

/// Fixes from the 2026-10-14 code review.

@Suite("App link input")
struct AppLinkInputTests {
    @Test("A bare host or path gets https")
    func bareHost() {
        #expect(AppLinkInput.normalized("raycast.com") == "https://raycast.com")
        #expect(AppLinkInput.normalized("  github.com/org/repo ") == "https://github.com/org/repo")
        #expect(AppLinkInput.normalized("https://kosshi.app") == "https://kosshi.app")
    }

    @Test("Only web links with a host count")
    func rejectsNonWeb() {
        #expect(AppLinkInput.normalized("ftp://example.com") == nil)
        #expect(AppLinkInput.normalized("https://") == nil)
        #expect(AppLinkInput.normalized("not a link") == nil)
        #expect(AppLinkInput.normalized("") == nil)
    }

    @Test("An empty field is acceptable because it clears the link")
    func emptyIsAcceptable() {
        #expect(AppLinkInput.isAcceptable("  "))
        #expect(AppLinkInput.isAcceptable("raycast.com"))
        #expect(!AppLinkInput.isAcceptable("not a link"))
    }

    @Test("A schemeless GitHub link still finds its releases")
    func schemelessGitHub() {
        #expect(UpdateChecker.gitHubLatestReleaseURL(forAppURL: "github.com/author/bloom")
                == URL(string: "https://github.com/author/bloom/releases/latest"))
    }
}

@Suite("CSV paid column")
struct PaidColumnTests {
    @Test("Any trace of a purchase reads yes, whatever the install source")
    func anyPurchase() {
        #expect(AppListViewModel.paidColumn(isPaidApp: true, hasLicenseKey: false, licenseType: nil) == "yes")
        #expect(AppListViewModel.paidColumn(isPaidApp: false, hasLicenseKey: true, licenseType: nil) == "yes")
        #expect(AppListViewModel.paidColumn(isPaidApp: false, hasLicenseKey: false, licenseType: "lifetime") == "yes")
        #expect(AppListViewModel.paidColumn(isPaidApp: false, hasLicenseKey: false, licenseType: nil) == "")
    }
}

@Suite("Local AI label")
struct RunsOnThisMacTests {
    @Test("Only Ollama on a local server counts as local")
    func localOnly() {
        let defaults = UserDefaults(suiteName: "AppAuditTests.RunsOnThisMac")!
        defaults.removeObject(forKey: "ollamaBaseURL")
        #expect(AnalysisProviderKind.ollama.runsOnThisMac(userDefaults: defaults))
        defaults.set("http://127.0.0.1:11434", forKey: "ollamaBaseURL")
        #expect(AnalysisProviderKind.ollama.runsOnThisMac(userDefaults: defaults))
        defaults.set("https://ollama.com", forKey: "ollamaBaseURL")
        #expect(!AnalysisProviderKind.ollama.runsOnThisMac(userDefaults: defaults))
        for cloud in [AnalysisProviderKind.anthropic, .openAI, .gemini, .openRouter] {
            #expect(!cloud.runsOnThisMac(userDefaults: defaults))
        }
        defaults.removePersistentDomain(forName: "AppAuditTests.RunsOnThisMac")
    }
}

@Suite("Two copies of one app")
@MainActor
struct DuplicateCopyStateTests {
    private func twoCopies() -> AppListViewModel {
        let viewModel = AppListViewModel()
        viewModel.apps = ["/Applications/Reed.app", "/Applications/Reed Test.app"].map { path in
            AppInfo(id: path, name: "Reed", version: "1.0", bundleID: "com.example.reed", path: path,
                    humanReadableDescription: nil, sparkleFeedURL: nil, isAppStoreInstall: false, icon: nil)
        }
        return viewModel
    }

    @Test("Record-backed state reaches both copies")
    func mirroredState() {
        let viewModel = twoCopies()
        viewModel.setFavorite(bundleID: "com.example.reed", value: true)
        viewModel.setHasLicenseKey(bundleID: "com.example.reed", value: true)
        #expect(viewModel.apps.allSatisfy { $0.isFavorite && $0.hasLicenseKey })
    }

    @Test("Uninstalling one copy keeps the other in the sidebar")
    func removeOneCopy() {
        let viewModel = twoCopies()
        viewModel.selectedAppID = "/Applications/Reed Test.app"
        viewModel.removeApp(id: "/Applications/Reed Test.app")
        #expect(viewModel.apps.map(\.id) == ["/Applications/Reed.app"])
        #expect(viewModel.selectedAppID == "/Applications/Reed.app")
    }

    @Test("Marking an update done only touches copies showing that update")
    func acknowledgeOneCopy() throws {
        let container = try ModelContainer(for: AppRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let viewModel = twoCopies()
        viewModel.cacheService = CacheService(context: container.mainContext)
        let available = AppInfo.UpdateState.updateAvailable(latestVersion: "2.0", source: .github, actionURL: nil)
        viewModel.apps[0].updateState = available
        viewModel.apps[1].updateState = .upToDate(source: .github)

        viewModel.acknowledgeUpdate(bundleID: "com.example.reed", updateState: available)

        #expect(viewModel.apps.allSatisfy { $0.updateState == .upToDate(source: .github) })
    }
}

@Suite("Model changed banner")
@MainActor
struct StaleModelCountTests {
    @Test("Counts analyses from another model, and stays dismissed until the model changes")
    func recount() throws {
        let container = try ModelContainer(for: AppRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let cache = CacheService(context: container.mainContext)
        cache.save(bundleID: "com.example.reed", appName: "Reed", explanation: "Notes.", score: 4,
                   reason: "Fits.", bestUse: "Writing", ollamaModel: "test:some-older-model")
        let viewModel = AppListViewModel()
        viewModel.cacheService = cache
        viewModel.apps = [AppInfo(id: "/Applications/Reed.app", name: "Reed", version: "1.0",
                                  bundleID: "com.example.reed", path: "/Applications/Reed.app",
                                  humanReadableDescription: nil, sparkleFeedURL: nil,
                                  isAppStoreInstall: false, icon: nil,
                                  aiState: .loaded(explanation: "Notes.", score: 4, reason: "Fits.", bestUse: "Writing"))]

        viewModel.recomputeStaleModelCount(force: true)
        #expect(viewModel.staleModelCount == 1)

        viewModel.dismissModelChangeBanner()
        viewModel.recomputeStaleModelCount()   // an unrelated defaults change: same model
        #expect(viewModel.staleModelCount == 0)
    }
}

@Suite("Locked license key")
struct LockedLicenseKeyTests {
    @Test("A locked saved key is kept, whatever the field holds")
    func lockedKeeps() {
        #expect(LicenseDraftRules.keyAction(draft: "", hasSavedKey: true, keyEditable: false) == .keep)
        #expect(LicenseDraftRules.keyAction(draft: "STRAY", hasSavedKey: true, keyEditable: false) == .keep)
    }

    @Test("An unlocked field saves what it holds, and an empty field never deletes")
    func unlockedSaves() {
        #expect(LicenseDraftRules.keyAction(draft: " NEW-KEY ", hasSavedKey: true, keyEditable: true) == .save("NEW-KEY"))
        #expect(LicenseDraftRules.keyAction(draft: "  ", hasSavedKey: true, keyEditable: true) == .keep)
    }

    @Test("Without a saved key the field is open")
    func noSavedKey() {
        #expect(LicenseDraftRules.keyAction(draft: "ABC-123", hasSavedKey: false, keyEditable: false) == .save("ABC-123"))
        #expect(LicenseDraftRules.keyAction(draft: "", hasSavedKey: false, keyEditable: true) == .keep)
    }
}

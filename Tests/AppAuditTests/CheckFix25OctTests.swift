import Testing
import Foundation
import AppKit
import SwiftData
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

@Suite("Another machine's .local name is not this Mac")
struct LocalNameIsNotThisMacTests {
    @Test("http to another .local host keeps the key")
    func otherMachine() {
        #expect(!APIKeyTransport.maySendKey(to: "http://the-zen.local:11434/v1", localHostName: "Kikas-MacBook-Pro"))
        #expect(!APIKeyTransport.maySendKey(to: "http://nas.local/v1", localHostName: nil))
        #expect(APIKeyTransport.maySendKey(to: "https://the-zen.local:11434/v1", localHostName: "Kikas-MacBook-Pro"))
    }

    @Test("This Mac's own .local name may use http")
    func ownName() {
        #expect(APIKeyTransport.isThisMac("kikas-macbook-pro.local.", localHostName: "Kikas-MacBook-Pro"))
        #expect(APIKeyTransport.maySendKey(to: "http://Kikas-MacBook-Pro.local:11434", localHostName: "Kikas-MacBook-Pro"))
    }
}

@Suite("A first licence key typed before a click outside comes back")
struct UnsavedLicenseKeyDraftTests {
    @Test("A typed first key is kept for the same app")
    func keptForSameApp() {
        let kept = UnsavedLicenseKeyDraft.keep(draft: "ABCD-1234", hasSavedKey: false, bundleID: "com.example.one")
        #expect(kept?.restored(for: "com.example.one", hasSavedKey: false) == "ABCD-1234")
    }

    @Test("It never comes back for another app")
    func notForAnotherApp() {
        let kept = UnsavedLicenseKeyDraft.keep(draft: "ABCD-1234", hasSavedKey: false, bundleID: "com.example.one")
        #expect(kept?.restored(for: "com.example.two", hasSavedKey: false) == nil)
    }

    @Test("A revealed or replacing key is not kept, nor an empty field")
    func notKept() {
        #expect(UnsavedLicenseKeyDraft.keep(draft: "SAVED-KEY", hasSavedKey: true, bundleID: "com.example.one") == nil)
        #expect(UnsavedLicenseKeyDraft.keep(draft: "  ", hasSavedKey: false, bundleID: "com.example.one") == nil)
    }

    @Test("Once a key is saved, the old draft does not come back")
    func savedMeanwhile() {
        let kept = UnsavedLicenseKeyDraft.keep(draft: "ABCD-1234", hasSavedKey: false, bundleID: "com.example.one")
        #expect(kept?.restored(for: "com.example.one", hasSavedKey: true) == nil)
    }
}

@Suite("Closing chatter stays out of Best use")
struct AnalysisSignOffTests {
    @Test("A sign-off after a blank line is not appended")
    func afterBlankLine() async {
        let response = """
        EXPLANATION: A text editor.
        SCORE: 4
        REASON: Fits a writing workflow.
        BEST_USE: Drafting notes.

        Let me know if you want more detail.
        """
        let parsed = await OllamaService().parseAnalysis(from: response)
        #expect(parsed?.bestUse == "Drafting notes.")
    }

    @Test("A sign-off straight after the answer is not appended")
    func sameBlock() async {
        let response = """
        EXPLANATION: A text editor.
        SCORE: 4
        REASON: Fits a writing workflow.
        BEST_USE: Drafting notes.
        I hope this helps!
        """
        let parsed = await OllamaService().parseAnalysis(from: response)
        #expect(parsed?.bestUse == "Drafting notes.")
    }

    @Test("A Best use on the line under its label is still read")
    func labelOnItsOwnLine() async {
        let response = """
        EXPLANATION: A text editor.
        SCORE: 4
        REASON: Fits a writing workflow.
        BEST_USE:

        Drafting notes.
        """
        let parsed = await OllamaService().parseAnalysis(from: response)
        #expect(parsed?.bestUse == "Drafting notes.")
    }
}

@Suite("launchctl that does not start is not waited on")
struct LaunchAgentProcessTests {
    @Test("A tool that cannot launch returns at once")
    func missingTool() async {
        let started = await LaunchAgentUnload.run(executable: "/nonexistent/launchctl", arguments: ["bootout"])
        #expect(!started)
    }

    @Test("A tool that launches is waited on")
    func realTool() async {
        let started = await LaunchAgentUnload.run(executable: "/usr/bin/true", arguments: [])
        #expect(started)
    }
}

@Suite("A dotted Sparkle build reads as the version")
struct SparkleDottedBuildLabelTests {
    @Test("A build-only item 1.5.2 reads Update to 1.5.2, not 1.5.1 (1.5.2)")
    func dotted() {
        let item = UpdateChecker.UpdateMetadata(version: "", url: nil, build: "1.5.2")
        #expect(item.displayVersion(installedVersion: "1.5.1") == "1.5.2")
    }

    @Test("A plain build number keeps the installed version beside it")
    func plainNumber() {
        let item = UpdateChecker.UpdateMetadata(version: "", url: nil, build: "2045")
        #expect(item.displayVersion(installedVersion: "1.2.3") == "1.2.3 (2045)")
    }
}

@Suite("A data-only sweep asks first")
struct DataOnlySweepConfirmationTests {
    private let bundle = LeftoverItem(id: "/Applications/Reed.app", url: URL(fileURLWithPath: "/Applications/Reed.app"),
                                      category: .application, sizeBytes: 1, reason: "bundle", isAppBundle: true)
    private let support = LeftoverItem(id: "/Users/me/Library/Application Support/Reed",
                                       url: URL(fileURLWithPath: "/Users/me/Library/Application Support/Reed"),
                                       category: .applicationSupport, sizeBytes: 1, reason: "data")

    @Test("App row unticked with data checked asks")
    func asks() {
        #expect(UninstallSweep.needsDataOnlyConfirmation(items: [bundle, support], checked: [support.id]))
    }

    @Test("The app checked too does not ask")
    func appChecked() {
        #expect(!UninstallSweep.needsDataOnlyConfirmation(items: [bundle, support], checked: [bundle.id, support.id]))
    }

    @Test("After brew removed the app there is nothing to ask")
    func brewRemoved() {
        #expect(!UninstallSweep.needsDataOnlyConfirmation(items: [support], checked: [support.id]))
    }

    @Test("The question says the app stays")
    func wording() {
        #expect(UninstallSweep.DataOnlyConfirmation.title == "The app stays installed. Delete only its data?")
        #expect(UninstallSweep.DataOnlyConfirmation.message(appName: "Reed").contains("Reed stays"))
    }
}

@Suite("Run Update says what brew really did")
struct HomebrewUpgradeReportTests {
    @Test("A failed brew never reads as finished")
    func failed() {
        let outcome = HomebrewService.BrewOutcome(exitStatus: 1, output: "Error: Download failed")
        let message = HomebrewService.UpgradeReport.message(for: outcome)
        #expect(!message.contains("finished"))
        #expect(message.contains("Download failed"))
    }

    @Test("A clean brew run says finished")
    func succeeded() {
        let outcome = HomebrewService.BrewOutcome(exitStatus: 0, output: "==> Upgrading 1 outdated package")
        #expect(HomebrewService.UpgradeReport.message(for: outcome).hasPrefix("Homebrew finished"))
    }

    @Test("A copy brew did not install is not brew's to update")
    func notBrewsCopy() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "sift-caskroom-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "ghostty/.metadata"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!HomebrewService.caskOwnsBundle(token: "ghostty", bundlePath: "/Users/me/Downloads/Ghostty.app", caskroomRoots: [root.path]))
    }
}

@Suite("A stuck brew is stopped after a deadline")
struct BrewDeadlineTests {
    @Test("A tool past its deadline is stopped and reported as timed out")
    func stopsAStuckTool() {
        let started = Date()
        let result = TimedProcess.run(executable: "/bin/sleep", arguments: ["30"], mergeStandardError: true, timeout: 0.5)
        #expect(result.timedOut)
        #expect(result.exitStatus == nil)
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test("A tool that finishes in time keeps its output and exit status")
    func finishes() {
        let result = TimedProcess.run(executable: "/bin/sh", arguments: ["-c", "echo out; echo err >&2; exit 3"],
                                      mergeStandardError: false, timeout: 10)
        #expect(!result.timedOut)
        #expect(result.exitStatus == 3)
        #expect(String(data: result.output, encoding: .utf8) == "out\n")
    }

    @Test("A large output does not block the tool")
    func largeOutput() {
        let result = TimedProcess.run(executable: "/bin/sh", arguments: ["-c", "head -c 300000 /dev/zero"],
                                      mergeStandardError: true, timeout: 10)
        #expect(result.exitStatus == 0)
        #expect(result.output.count == 300_000)
    }

    @Test("A timed-out brew is a failure that says so")
    func outcome() {
        let outcome = HomebrewService.BrewOutcome(exitStatus: nil, output: "", timedOut: true)
        #expect(!outcome.succeeded)
        #expect(outcome.message.contains("did not finish in time"))
        #expect(HomebrewService.deadline(for: ["outdated", "--cask"]) < HomebrewService.deadline(for: ["upgrade", "--cask", "x"]))
    }
}

@Suite("Quit & Continue waits until the app is gone")
@MainActor
struct QuitWaitTests {
    @Test("An app that quits after a few looks counts as quit")
    func quitsLater() async {
        var looks = 0
        let quit = await QuitWait.untilQuit(interval: .milliseconds(5), limit: .seconds(2)) {
            looks += 1
            return looks < 4
        }
        #expect(quit)
        #expect(looks == 4)
    }

    @Test("An app still running at the limit does not count as quit")
    func stillRunning() async {
        let quit = await QuitWait.untilQuit(interval: .milliseconds(5), limit: .milliseconds(50)) { true }
        #expect(!quit)
    }
}

@Suite("An app locked before analysis says why")
struct LockedWithoutAnalysisTests {
    @Test("Locked and never analyzed shows the lock note, not Waiting")
    func lockedPending() {
        #expect(LockedWithoutAnalysis.applies(aiState: .pending, isLocked: true))
    }

    @Test("An unlocked wait, or a locked analysis, is unchanged")
    func others() {
        #expect(!LockedWithoutAnalysis.applies(aiState: .pending, isLocked: false))
        #expect(!LockedWithoutAnalysis.applies(aiState: .loaded(explanation: "x", score: 3, reason: "y", bestUse: ""), isLocked: true))
    }
}

@Suite("A public name pointing at this Mac or the local network is not fetched")
struct LinkHostResolutionTests {
    @Test("A name that resolves to loopback or a private address is refused")
    func privateAddress() async {
        #expect(!(await LinkEvidence.resolvesToPublicAddresses("evil.example.com") { _ in ["127.0.0.1"] }))
        #expect(!(await LinkEvidence.resolvesToPublicAddresses("evil.example.com") { _ in ["93.184.216.34", "192.168.1.10"] }))
        #expect(!(await LinkEvidence.resolvesToPublicAddresses("evil.example.com") { _ in ["::1"] }))
    }

    @Test("A name that resolves only to public addresses passes")
    func publicAddress() async {
        #expect(await LinkEvidence.resolvesToPublicAddresses("example.com") { _ in ["93.184.216.34", "2606:2800:220:1::1"] })
    }

    @Test("A name that does not resolve is not fetched")
    func noAnswer() async {
        #expect(!(await LinkEvidence.resolvesToPublicAddresses("nothing.example.com") { _ in [] }))
    }

    @Test("A local name never reaches the resolver")
    func localName() async {
        #expect(!(await LinkEvidence.resolvesToPublicAddresses("nas.local") { _ in ["93.184.216.34"] }))
    }

    @Test("The system resolver answers for localhost with loopback")
    func realResolver() async {
        let addresses = await LinkEvidence.resolvedAddresses("localhost")
        #expect(addresses.contains { $0 == "127.0.0.1" || $0 == "::1" })
    }
}

@Suite("Update feeds follow only https redirects to public hosts")
struct UpdateRedirectGuardTests {
    @Test("A redirect to plain http is refused")
    func http() async {
        #expect(!(await UpdateFetchGuard.allows(URL(string: "http://93.184.216.34/appcast.xml")!)))
    }

    @Test("A redirect to this Mac or the local network is refused")
    func local() async {
        #expect(!(await UpdateFetchGuard.allows(URL(string: "https://localhost/appcast.xml")!)))
        #expect(!(await UpdateFetchGuard.allows(URL(string: "https://192.168.1.2/appcast.xml")!)))
        #expect(!(await UpdateFetchGuard.allows(URL(string: "https://nas.local/appcast.xml")!)))
    }

    @Test("https to a public address passes")
    func publicHTTPS() async {
        #expect(await UpdateFetchGuard.allows(URL(string: "https://93.184.216.34/appcast.xml")!))
    }
}

@Suite("A failed save is shown, not hidden")
@MainActor
struct SaveFailuresTests {
    @Test("A reported failure shows until dismissed")
    func reportAndDismiss() {
        let failures = SaveFailures()
        #expect(failures.message == nil)
        failures.report(CocoaError(.fileWriteOutOfSpace))
        #expect(failures.message?.contains("could not save") == true)
        failures.dismiss()
        #expect(failures.message == nil)
    }

    @Test("A save that works reports nothing")
    func cleanSave() throws {
        let container = try ModelContainer(for: AppRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let failures = SaveFailures()
        container.mainContext.insert(AppRecord(stub: "com.example.app", appName: "Example"))
        container.mainContext.saveReportingFailure(to: failures)
        #expect(failures.message == nil)
    }
}

@Suite("The model picker matches Ollama's :latest and the engine it was fetched for")
struct ModelPickerTests {
    @Test("llama3.2 selects llama3.2:latest in the list")
    func latest() {
        #expect(AnalysisProviderKind.pickerSelection(stored: "llama3.2", models: ["mistral:latest", "llama3.2:latest"]) == "llama3.2:latest")
        #expect(AnalysisProviderKind.pickerSelection(stored: "qwen3:8b", models: ["qwen3:8b"]) == "qwen3:8b")
    }

    @Test("A list fetched for another engine is dropped")
    func engineChanged() {
        #expect(!ModelFetchOwner.stillCurrent(fetchedFor: .ollama, current: .gemini))
        #expect(ModelFetchOwner.stillCurrent(fetchedFor: .gemini, current: .gemini))
    }
}

@Suite("The Notes sheet saves on Save only")
struct NotesDraftTests {
    @Test("An emptied note is stored as no note")
    func emptied() {
        #expect(NotesDraft.stored("   \n") == nil)
        #expect(NotesDraft.stored("I use it daily") == "I use it daily")
    }

    @Test("Saving the same text again starts no re-analysis")
    func unchanged() {
        #expect(!NotesChange.changed(previous: "I use it daily", current: NotesDraft.stored("I use it daily")))
        #expect(NotesChange.changed(previous: nil, current: NotesDraft.stored("New note")))
    }
}

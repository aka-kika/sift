import Testing
import Foundation
@testable import Sift

/// Answers from fixed tables, and remembers what was asked.
private final class StubUpdateClient: UpdateMetadataClient, @unchecked Sendable {
    private let responses: [String: Data]
    private let redirects: [String: String]
    private let lock = NSLock()
    private var requested: [String] = []

    init(_ responses: [String: String] = [:], redirects: [String: String] = [:]) {
        self.responses = responses.mapValues { Data($0.utf8) }
        self.redirects = redirects
    }

    var requestedURLs: [String] {
        lock.withLock { requested }
    }

    func data(for url: URL) async throws -> Data {
        lock.withLock { requested.append(url.absoluteString) }
        guard let data = responses[url.absoluteString] else { throw URLError(.badServerResponse) }
        return data
    }

    func redirectLocation(for url: URL) async throws -> URL? {
        lock.withLock { requested.append(url.absoluteString) }
        guard let location = redirects[url.absoluteString] else { throw URLError(.badServerResponse) }
        return URL(string: location)
    }
}

private func makeApp(version: String,
                     sparkleFeedURL: String? = nil,
                     isAppStoreInstall: Bool = false,
                     runtime: AppRuntime? = nil) -> AppInfo {
    AppInfo(id: "com.example.Bloom", name: "Bloom", version: version, bundleID: "com.example.Bloom",
            path: "/Applications/Bloom.app", humanReadableDescription: nil,
            sparkleFeedURL: sparkleFeedURL, isAppStoreInstall: isAppStoreInstall, icon: nil,
            runtime: runtime)
}

private func tagPage(_ tag: String) -> String {
    "https://github.com/author/bloom/releases/tag/\(tag)"
}

private let bloomLatest = "https://github.com/author/bloom/releases/latest"

@Suite("GitHub release source")
struct GitHubReleaseSourceTests {

    @Test("A repo link becomes the latest-release API URL")
    func repoLinkToAPIURL() {
        let expected = URL(string: bloomLatest)
        #expect(UpdateChecker.gitHubLatestReleaseURL(forAppURL: "https://github.com/author/bloom") == expected)
        #expect(UpdateChecker.gitHubLatestReleaseURL(forAppURL: "  https://www.github.com/author/bloom/  ") == expected)
        #expect(UpdateChecker.gitHubLatestReleaseURL(forAppURL: "https://github.com/author/bloom/releases/tag/v2") == expected)
        #expect(UpdateChecker.gitHubLatestReleaseURL(forAppURL: "https://github.com/author/bloom.git") == expected)
    }

    @Test("Links that are not a GitHub repo give no URL")
    func nonRepoLinks() {
        #expect(UpdateChecker.gitHubLatestReleaseURL(forAppURL: nil) == nil)
        #expect(UpdateChecker.gitHubLatestReleaseURL(forAppURL: "") == nil)
        #expect(UpdateChecker.gitHubLatestReleaseURL(forAppURL: "https://bloom.example.com") == nil)
        #expect(UpdateChecker.gitHubLatestReleaseURL(forAppURL: "https://github.com/author") == nil)
        #expect(UpdateChecker.gitHubLatestReleaseURL(forAppURL: "https://github.com/orgs/author/repositories") == nil)
        #expect(UpdateChecker.gitHubLatestReleaseURL(forAppURL: "https://gist.github.com/author/abc123") == nil)
        #expect(UpdateChecker.gitHubLatestReleaseURL(forAppURL: "https://notgithub.com/author/bloom") == nil)
    }

    @Test("Versions are read out of common tag shapes")
    func tagShapes() {
        #expect(UpdateChecker.version(fromGitHubTag: "v1.2.3") == "1.2.3")
        #expect(UpdateChecker.version(fromGitHubTag: "1.10") == "1.10")
        #expect(UpdateChecker.version(fromGitHubTag: "release-2.0.1") == "2.0.1")
        #expect(UpdateChecker.version(fromGitHubTag: "desktop/v2024.10.1") == "2024.10.1")
    }

    @Test("A tag with no dotted version is not a version")
    func tagsWithoutVersions() {
        #expect(UpdateChecker.version(fromGitHubTag: "nightly") == nil)
        #expect(UpdateChecker.version(fromGitHubTag: "build-4521") == nil)
        #expect(UpdateChecker.version(fromGitHubTag: "") == nil)
    }

    @Test("Reads the release out of the redirect; no releases is no answer")
    func parsesRedirect() throws {
        let release = UpdateChecker.parseGitHubMetadata(fromRedirect: try #require(URL(string: tagPage("v2.1.0"))))
        #expect(release?.version == "2.1.0")
        #expect(release?.url == tagPage("v2.1.0"))

        let slashed = UpdateChecker.parseGitHubMetadata(fromRedirect: try #require(URL(string: tagPage("desktop/v2024.10.1"))))
        #expect(slashed?.version == "2024.10.1")

        // A repo with no releases redirects to the plain releases page.
        #expect(UpdateChecker.parseGitHubMetadata(fromRedirect: try #require(URL(string: "https://github.com/author/bloom/releases"))) == nil)
        #expect(UpdateChecker.parseGitHubMetadata(fromRedirect: try #require(URL(string: tagPage("nightly")))) == nil)
        #expect(UpdateChecker.parseGitHubMetadata(fromRedirect: try #require(URL(string: "https://evil.example.com/author/bloom/releases/tag/v9.9.9"))) == nil)
    }

    @Test("An app with only a GitHub link gets an update from its releases")
    func updateFromGitHub() async {
        let checker = UpdateChecker(client: StubUpdateClient(redirects: [bloomLatest: tagPage("v2.1.0")]))
        let state = await checker.check(app: makeApp(version: "2.0"), appURL: "https://github.com/author/bloom")
        #expect(state == .updateAvailable(latestVersion: "2.1.0", source: .github,
                                          actionURL: tagPage("v2.1.0")))
    }

    @Test("Same or older release reads as up to date on GitHub")
    func upToDateOnGitHub() async {
        let checker = UpdateChecker(client: StubUpdateClient(redirects: [bloomLatest: tagPage("v2.1.0")]))
        #expect(await checker.check(app: makeApp(version: "2.1.0"), appURL: "https://github.com/author/bloom")
                == .upToDate(source: .github))
        #expect(await checker.check(app: makeApp(version: "2.2"), appURL: "https://github.com/author/bloom")
                == .upToDate(source: .github))
    }

    @Test("An acknowledged GitHub version stays quiet")
    func acknowledgedVersion() async {
        let checker = UpdateChecker(client: StubUpdateClient(redirects: [bloomLatest: tagPage("v2.1.0")]))
        let state = await checker.check(app: makeApp(version: "2.0"), acknowledgedVersion: "2.1.0",
                                        appURL: "https://github.com/author/bloom")
        #expect(state == .upToDate(source: .github))
    }

    @Test("No link, a website link, or a failed request is unavailable, not a guess")
    func unavailableCases() async {
        let checker = UpdateChecker(client: StubUpdateClient())
        #expect(await checker.check(app: makeApp(version: "2.0")) == .unavailable)
        #expect(await checker.check(app: makeApp(version: "2.0"), appURL: "https://bloom.example.com") == .unavailable)
        // Missing repo or no network: the stub throws for unknown URLs.
        #expect(await checker.check(app: makeApp(version: "2.0"), appURL: "https://github.com/author/bloom") == .unavailable)
    }

    @Test("A working Sparkle feed answers before GitHub is asked")
    func sparkleWinsOverGitHub() async {
        let feed = "https://example.com/appcast.xml"
        let appcast = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
        <enclosure url="https://example.com/bloom-2.0.zip" sparkle:shortVersionString="2.0" sparkle:version="20" />
        </item></channel></rss>
        """
        let client = StubUpdateClient([feed: appcast], redirects: [bloomLatest: tagPage("v9.9.9")])
        let checker = UpdateChecker(client: client)
        let state = await checker.check(app: makeApp(version: "2.0", sparkleFeedURL: feed),
                                        appURL: "https://github.com/author/bloom")
        #expect(state == .upToDate(source: .sparkle))
        #expect(!client.requestedURLs.contains(bloomLatest))
    }

    @Test("A dead Sparkle feed falls through to GitHub")
    func deadSparkleFallsToGitHub() async {
        let checker = UpdateChecker(client: StubUpdateClient(redirects: [bloomLatest: tagPage("v2.1.0")]))
        let state = await checker.check(app: makeApp(version: "2.0", sparkleFeedURL: "https://dead.example.com/feed.xml"),
                                        appURL: "https://github.com/author/bloom")
        #expect(state.isUpdateAvailable)
    }

    @Test("An App Store copy is never answered by GitHub")
    func appStoreCopyIgnoresGitHub() async {
        let client = StubUpdateClient(redirects: [bloomLatest: tagPage("v9.9.9")])
        let checker = UpdateChecker(client: client)
        let state = await checker.check(app: makeApp(version: "2.0", isAppStoreInstall: true),
                                        appURL: "https://github.com/author/bloom")
        #expect(state == .unavailable)
        #expect(!client.requestedURLs.contains(bloomLatest))
    }

    @Test("GitHub has its own symbol and copy")
    func presentation() {
        #expect(AppInfo.UpdateSource.github.actionSymbol == "chevron.left.forwardslash.chevron.right")
        let help = AppInfo.UpdateSource.github.actionHelp(appName: "Bloom", latestVersion: "2.1", brewCommand: nil)
        #expect(help.contains("Bloom") && help.contains("2.1") && help.contains("GitHub"))
        #expect(AppInfo.UpdateSource.github.accessibilityLabel(appName: "Bloom", latestVersion: "2.1").contains("2.1"))
    }
}

@Suite("App runtime detection")
struct AppRuntimeDetectorTests {

    /// A throwaway `.app` with the given files (paths relative to `Contents`).
    private func makeBundle(files: [String] = [], directories: [String] = []) throws -> URL {
        let bundle = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiftRuntimeTests-\(UUID().uuidString)")
            .appendingPathComponent("Bloom.app")
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: contents.appendingPathComponent("MacOS/Bloom"))
        for directory in directories {
            try FileManager.default.createDirectory(at: contents.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        for file in files {
            let url = contents.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        return bundle
    }

    private func cleanUp(_ bundle: URL) {
        try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent())
    }

    private func detect(_ bundle: URL, plist: [String: Any] = [:], links: [String] = []) -> AppRuntime? {
        AppRuntimeDetector.detect(bundlePath: bundle.path, infoPlist: plist,
                                  loadCommands: { _ in Data(links.joined(separator: "\0").utf8) })
    }

    private let appKit = "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"
    private let swiftUI = "/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI"
    private let webKit = "/System/Library/Frameworks/WebKit.framework/Versions/A/WebKit"
    private let catalystUIKit = "/System/iOSSupport/System/Library/Frameworks/UIKit.framework/Versions/A/UIKit"

    @Test("Electron by framework, by asar, or by unpacked payload")
    func electron() throws {
        for bundle in [
            try makeBundle(directories: ["Frameworks/Electron Framework.framework"]),
            try makeBundle(files: ["Resources/app.asar"]),
            try makeBundle(files: ["Resources/app/package.json"], directories: ["Frameworks/QQNT.framework"]),
        ] {
            defer { cleanUp(bundle) }
            #expect(detect(bundle, links: [appKit]) == .electron)
        }
    }

    @Test("Flutter, Qt, Java and embedded Chromium by their bundle markers")
    func otherBundledRuntimes() throws {
        let flutter = try makeBundle(directories: ["Frameworks/FlutterMacOS.framework"])
        defer { cleanUp(flutter) }
        #expect(detect(flutter, links: [appKit]) == .flutter)

        let qt = try makeBundle(directories: ["Frameworks/QtCore.framework"])
        defer { cleanUp(qt) }
        #expect(detect(qt) == .qt)

        let java = try makeBundle(directories: ["runtime"])
        defer { cleanUp(java) }
        #expect(detect(java) == .java)

        let javaStub = try makeBundle()
        defer { cleanUp(javaStub) }
        #expect(detect(javaStub, plist: ["CFBundleExecutable": "JavaAppLauncher"]) == .java)

        let cef = try makeBundle(directories: ["Frameworks/Chromium Embedded Framework.framework"])
        defer { cleanUp(cef) }
        #expect(detect(cef, links: [appKit]) == .chromium)

        let browser = try makeBundle(directories: ["Frameworks/Google Chrome Framework.framework"])
        defer { cleanUp(browser) }
        #expect(detect(browser, links: [appKit]) == .chromium)
    }

    @Test("Qt wins over embedded Chromium when an app ships both")
    func qtBeforeChromium() throws {
        let bundle = try makeBundle(directories: ["Frameworks/QtCore.framework",
                                                  "Frameworks/Chromium Embedded Framework.framework"])
        defer { cleanUp(bundle) }
        #expect(detect(bundle) == .qt)
    }

    @Test("Native apps are told apart by what the executable links")
    func nativeByLinkedFrameworks() throws {
        let bundle = try makeBundle()
        defer { cleanUp(bundle) }
        #expect(detect(bundle, links: [appKit]) == .appKit)
        #expect(detect(bundle, links: [appKit, swiftUI]) == .swiftUI)
        #expect(detect(bundle, links: [appKit, catalystUIKit]) == .catalyst)
    }

    @Test("Nothing recognisable is nil, not a guess")
    func unknownIsNil() throws {
        let bundle = try makeBundle()
        defer { cleanUp(bundle) }
        #expect(detect(bundle, links: ["/usr/lib/libSystem.B.dylib"]) == nil)
        #expect(AppRuntimeDetector.detect(bundlePath: bundle.path, infoPlist: [:], loadCommands: { _ in nil }) == nil)
        #expect(AppRuntimeDetector.detect(bundlePath: "/nonexistent/Ghost.app", infoPlist: [:]) == nil)
    }

    @Test("Tauri needs its plist keys, WebKit, and the crate name in the binary")
    func tauri() throws {
        let tauriPlist: [String: Any] = ["LSRequiresCarbon": true, "CSResourcesFileMapped": true]

        let bundle = try makeBundle()
        defer { cleanUp(bundle) }
        let binary = bundle.appendingPathComponent("Contents/MacOS/Bloom")
        try Data("…/registry/src/index.crates.io/tauri-2.1.0/src/app.rs…".utf8).write(to: binary)
        #expect(detect(bundle, plist: tauriPlist, links: [appKit, webKit]) == .tauri)
        // Without the plist gate the same binary is just an AppKit app.
        #expect(detect(bundle, links: [appKit, webKit]) == .appKit)

        // The gate alone is not proof.
        try Data("no crate here".utf8).write(to: binary)
        #expect(detect(bundle, plist: tauriPlist, links: [appKit, webKit]) == .appKit)
    }

    @Test("A garbage executable reads as no load commands")
    func garbageExecutable() throws {
        let bundle = try makeBundle()
        defer { cleanUp(bundle) }
        #expect(AppRuntimeDetector.loadCommands(of: bundle.appendingPathComponent("Contents/MacOS/Bloom")) == nil)
    }

    @Test("Reads a real system app's executable as native")
    func realSystemApp() throws {
        let path = "/System/Applications/TextEdit.app"
        guard let plist = NSDictionary(contentsOfFile: path + "/Contents/Info.plist") as? [String: Any] else { return }
        let runtime = AppRuntimeDetector.detect(bundlePath: path, infoPlist: plist)
        #expect(runtime == .appKit || runtime == .swiftUI)
    }
}

@Suite("Built-with fact and prompt hint")
struct BuiltWithPresentationTests {

    @Test("The facts row gains a Built with cell only when the runtime is known")
    func factsRow() {
        let now = Date()
        let with = AppFacts.build(sizeBytes: 1_000, lastUsed: nil, now: now, installSource: "Other",
                                  analyzedAt: nil, builtWith: .electron)
        #expect(with.contains(AppFact(label: "Built with", value: "Electron")))

        let without = AppFacts.build(sizeBytes: 1_000, lastUsed: nil, now: now, installSource: "Other", analyzedAt: nil)
        #expect(!without.contains(where: { $0.label == "Built with" }))
    }

    @Test("Every runtime has a label and a summary")
    func copy() {
        for runtime in AppRuntime.allCases {
            #expect(!runtime.label.isEmpty)
            #expect(!runtime.summary.isEmpty)
        }
        #expect(AppRuntime.electron.bundlesOwnRuntime)
        #expect(!AppRuntime.swiftUI.bundlesOwnRuntime)
    }

    @Test("The analysis prompt names the runtime when known")
    func promptHint() {
        let profile = WorkflowProfile.local(text: "SwiftUI developer")
        let electron = AppAnalysisPrompt.build(app: makeApp(version: "1.0", runtime: .electron),
                                               profile: profile, includeResponseFormat: true)
        #expect(electron.contains("Built with: Electron"))

        let unknown = AppAnalysisPrompt.build(app: makeApp(version: "1.0"), profile: profile, includeResponseFormat: true)
        #expect(!unknown.contains("Built with:"))
    }
}

@Suite("Version comparator")
struct VersionComparatorTests {

    @Test("Trailing zeros and a leading v change nothing")
    func equalVersions() {
        #expect(VersionComparator.compare("2.0.0", "2.0") == .orderedSame)
        #expect(VersionComparator.compare("v1.2.3", "1.2.3") == .orderedSame)
        #expect(VersionComparator.compare(" 1.2 ", "1.2") == .orderedSame)
        #expect(!UpdateChecker.isVersion("2.0.0", newerThan: "2.0"))
        #expect(!UpdateChecker.isVersion("2.0", newerThan: "2.0.0"))
    }

    @Test("Numbers compare as numbers")
    func numericOrder() {
        #expect(VersionComparator.isNewer("1.10", than: "1.9"))
        #expect(VersionComparator.isNewer("1.2.10", than: "1.2.9"))
        #expect(VersionComparator.isNewer("2.0.1", than: "2.0"))
        #expect(!VersionComparator.isNewer("1.9", than: "1.10"))
        #expect(VersionComparator.isNewer("1.0.99999999999999999999", than: "1.0.9"))
    }

    @Test("A prerelease is older than its release")
    func prereleaseOrder() {
        #expect(VersionComparator.isNewer("1.2.3", than: "1.2.3-beta"))
        #expect(!VersionComparator.isNewer("1.2.3-beta", than: "1.2.3"))
        #expect(VersionComparator.isNewer("1.2.3-beta2", than: "1.2.3-beta1"))
        #expect(VersionComparator.isNewer("1.2.4-beta", than: "1.2.3"))
    }

    @Test("Same marketing version, newer build in brackets")
    func buildNumbers() {
        #expect(VersionComparator.isNewer("1.0 (390)", than: "1.0 (374)"))
        #expect(VersionComparator.compare("1.0 (374)", "1.0 (374)") == .orderedSame)
    }

    @Test("Major upgrades are flagged; calendar years are not")
    func majorUpgrade() {
        #expect(VersionComparator.isMajorUpgrade(from: "1.9.4", to: "2.0"))
        #expect(VersionComparator.isMajorUpgrade(from: "v4.7", to: "v5.0.1"))
        #expect(!VersionComparator.isMajorUpgrade(from: "2.1", to: "2.9"))
        #expect(!VersionComparator.isMajorUpgrade(from: "2025.3", to: "2026.1"))
        #expect(!VersionComparator.isMajorUpgrade(from: "", to: "2.0"))
    }
}

@Suite("Major upgrade note")
struct MajorUpgradeNoteTests {
    private func app(version: String, paid: Bool, appStore: Bool = false) -> AppInfo {
        AppInfo(id: "com.example.Bloom", name: "Bloom", version: version, bundleID: "com.example.Bloom",
                path: "/Applications/Bloom.app", humanReadableDescription: nil, sparkleFeedURL: nil,
                isAppStoreInstall: appStore, icon: nil, isPaidApp: paid)
    }

    @Test("A paid or licensed app gets the note on a major jump")
    func paidMajorJump() {
        #expect(app(version: "1.9", paid: true).majorUpgradeNote(latestVersion: "2.0", hasLicenseKey: false)?.contains("2.0") == true)
        #expect(app(version: "1.9", paid: false).majorUpgradeNote(latestVersion: "2.0", hasLicenseKey: true) != nil)
    }

    @Test("Free apps, minor updates and store copies stay quiet")
    func quietCases() {
        #expect(app(version: "1.9", paid: false).majorUpgradeNote(latestVersion: "2.0", hasLicenseKey: false) == nil)
        #expect(app(version: "2.1", paid: true).majorUpgradeNote(latestVersion: "2.9", hasLicenseKey: true) == nil)
        #expect(app(version: "1.9", paid: true, appStore: true).majorUpgradeNote(latestVersion: "2.0", hasLicenseKey: true) == nil)
    }
}

@Suite("Same version, newer build")
struct BuildNumberUpdateTests {
    private let feed = "https://example.com/appcast.xml"

    private func appcast(version: String, build: String) -> String {
        """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
        <enclosure url="https://example.com/amp.zip" sparkle:shortVersionString="\(version)" sparkle:version="\(build)" />
        </item></channel></rss>
        """
    }

    private func app(version: String, build: String?) -> AppInfo {
        AppInfo(id: "com.example.Amp", name: "Amp", version: version, build: build, bundleID: "com.example.Amp",
                path: "/Applications/Amp.app", humanReadableDescription: nil, sparkleFeedURL: feed,
                isAppStoreInstall: false, icon: nil)
    }

    @Test("A newer build under the same version is an update, shown with its build")
    func newerBuild() async {
        let checker = UpdateChecker(client: StubUpdateClient([feed: appcast(version: "1.0", build: "390")]))
        let state = await checker.check(app: app(version: "1.0", build: "374"))
        #expect(state == .updateAvailable(latestVersion: "1.0 (390)", source: .sparkle, actionURL: "https://example.com/amp.zip"))
    }

    @Test("Same build, older build, or an unknown installed build is up to date")
    func noFalseUpdates() async {
        let checker = UpdateChecker(client: StubUpdateClient([feed: appcast(version: "1.0", build: "390")]))
        #expect(await checker.check(app: app(version: "1.0", build: "390")) == .upToDate(source: .sparkle))
        #expect(await checker.check(app: app(version: "1.0", build: "401")) == .upToDate(source: .sparkle))
        #expect(await checker.check(app: app(version: "1.0", build: nil)) == .upToDate(source: .sparkle))
    }

    @Test("The build never overrules the version")
    func versionWins() async {
        // Installed 2.0 build 5; the feed's 1.9 has a bigger build number.
        let checker = UpdateChecker(client: StubUpdateClient([feed: appcast(version: "1.9", build: "900")]))
        #expect(await checker.check(app: app(version: "2.0", build: "5")) == .upToDate(source: .sparkle))

        // A real version bump shows the plain version, no build.
        let bump = UpdateChecker(client: StubUpdateClient([feed: appcast(version: "1.1", build: "400")]))
        #expect(await bump.check(app: app(version: "1.0", build: "374"))
                == .updateAvailable(latestVersion: "1.1", source: .sparkle, actionURL: "https://example.com/amp.zip"))
    }

    @Test("Marking a build-only update done keeps it quiet")
    func acknowledgedBuild() async {
        let checker = UpdateChecker(client: StubUpdateClient([feed: appcast(version: "1.0", build: "390")]))
        #expect(await checker.check(app: app(version: "1.0", build: "374"), acknowledgedVersion: "1.0 (390)")
                == .upToDate(source: .sparkle))
    }

    @Test("Among feed items with one version, the highest build is the newest")
    func newestItemByBuild() throws {
        let xml = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><enclosure url="https://example.com/a.zip" sparkle:shortVersionString="1.0" sparkle:version="374" /></item>
        <item><enclosure url="https://example.com/b.zip" sparkle:shortVersionString="1.0" sparkle:version="390" /></item>
        <item><enclosure url="https://example.com/c.zip" sparkle:shortVersionString="1.0" sparkle:version="381" /></item>
        </channel></rss>
        """
        let meta = try UpdateChecker.parseSparkleMetadata(from: Data(xml.utf8))
        #expect(meta?.build == "390")
        #expect(meta?.url == "https://example.com/b.zip")
    }
}

@Suite("Open app to update")
struct OpenAppToUpdateTests {
    @Test("Only Sparkle apps are opened to update themselves")
    func onlySparkle() {
        #expect(AppInfo.UpdateSource.sparkle.opensAppToUpdate)
        #expect(!AppInfo.UpdateSource.appStore.opensAppToUpdate)
        #expect(!AppInfo.UpdateSource.homebrew.opensAppToUpdate)
        #expect(!AppInfo.UpdateSource.github.opensAppToUpdate)
    }

    @Test("Sparkle's help says what opening the app will do")
    func help() {
        let help = AppInfo.UpdateSource.sparkle.actionHelp(appName: "Bloom", latestVersion: "2.1", brewCommand: nil)
        #expect(help.contains("Bloom") && help.contains("2.1") && help.contains("Check for Updates"))
    }
}

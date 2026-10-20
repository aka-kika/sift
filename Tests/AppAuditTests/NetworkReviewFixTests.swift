import Testing
import Foundation
@testable import Sift

/// Network fixes from the 2026-10-20 code review.

@Suite("Link evidence stays on public hosts")
struct LinkEvidenceHostTests {
    @Test("Local names and private IPv4 literals are refused")
    func refusesLocalAndPrivateIPv4() {
        for host in ["localhost", "LOCALHOST.", "dev.localhost", "nas.local", "router", "printer.lan",
                     "127.0.0.1", "127.1", "2130706433", "0x7f000001", "0.0.0.0",
                     "10.0.0.8", "172.16.0.1", "172.31.255.255", "192.168.1.1",
                     "169.254.169.254", "100.100.1.1"] {
            #expect(!LinkEvidence.isPublicHost(host), "\(host) should be refused")
        }
    }

    @Test("Private IPv6 literals are refused")
    func refusesPrivateIPv6() {
        for host in ["::1", "[::1]", "::", "fe80::1", "fe80::1%en0", "fd12:3456::1", "fc00::1",
                     "::ffff:127.0.0.1", "::ffff:192.168.0.1"] {
            #expect(!LinkEvidence.isPublicHost(host), "\(host) should be refused")
        }
    }

    @Test("Public names and addresses pass, including neighbours of the private ranges")
    func allowsPublic() {
        for host in ["raycast.com", "github.com", "8.8.8.8", "172.32.0.1", "192.169.0.1",
                     "2606:4700:4700::1111", "::ffff:8.8.8.8"] {
            #expect(LinkEvidence.isPublicHost(host), "\(host) should pass")
        }
    }

    @Test("The fetched link loses its query, fragment and credentials")
    func stripsQueryAndFragment() {
        #expect(LinkEvidence.fetchableURL(from: "https://user:pw@example.com/app?token=abc#top")
                == URL(string: "https://example.com/app"))
        #expect(LinkEvidence.fetchableURL(from: "http://example.com") == URL(string: "http://example.com"))
    }

    @Test("Links to this Mac, the local network or another scheme are not fetched")
    func refusesLocalLinks() {
        #expect(LinkEvidence.fetchableURL(from: "http://localhost:3000/admin") == nil)
        #expect(LinkEvidence.fetchableURL(from: "http://192.168.1.1/") == nil)
        #expect(LinkEvidence.fetchableURL(from: "http://[::1]:8080/") == nil)
        #expect(LinkEvidence.fetchableURL(from: "file:///etc/hosts") == nil)
        #expect(!LinkEvidence.isAllowedTarget(URL(string: "https://10.0.0.1/redirected")!))
    }

    @Test("A local link never reaches the network")
    func serviceSkipsLocalLink() async {
        let service = LinkEvidenceService()
        #expect(await service.evidence(for: "http://127.0.0.1:9/") == nil)
    }

    @Test("The prompt names the link without its query or fragment")
    func promptDropsQuery() {
        let app = AppInfo(id: "com.example.app", name: "Example", version: "1.0", bundleID: "com.example.app",
                          path: "/Applications/Example.app", humanReadableDescription: nil,
                          sparkleFeedURL: nil, isAppStoreInstall: false, icon: nil)
        let prompt = AppAnalysisPrompt.build(app: app, profile: .local(text: "macOS apps"),
                                             appURL: "https://example.com/app?token=secret#x",
                                             includeResponseFormat: true)
        #expect(prompt.contains("Reference URL: https://example.com/app"))
        #expect(!prompt.contains("secret"))
    }
}

/// Answers from a fixed table and records what was asked.
private final class RecordingUpdateClient: UpdateMetadataClient, @unchecked Sendable {
    private let responses: [String: Data]
    private let lock = NSLock()
    private var requested: [String] = []

    init(_ responses: [String: String] = [:]) {
        self.responses = responses.mapValues { Data($0.utf8) }
    }

    var requestedURLs: [String] { lock.withLock { requested } }

    func data(for url: URL) async throws -> Data {
        lock.withLock { requested.append(url.absoluteString) }
        guard let data = responses[url.absoluteString] else { throw URLError(.badServerResponse) }
        return data
    }

    func redirectLocation(for url: URL) async throws -> URL? {
        lock.withLock { requested.append(url.absoluteString) }
        throw URLError(.badServerResponse)
    }
}

private func feedApp(version: String = "1.0", feed: String?) -> AppInfo {
    AppInfo(id: "com.example.Bloom", name: "Bloom", version: version, bundleID: "com.example.Bloom",
            path: "/Applications/Bloom.app", humanReadableDescription: nil,
            sparkleFeedURL: feed, isAppStoreInstall: false, icon: nil)
}

private func appcast(url: String, version: String = "2.0") -> String {
    """
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
    <enclosure url="\(url)" sparkle:shortVersionString="\(version)" sparkle:version="20" />
    </item></channel></rss>
    """
}

@Suite("Update links are https only")
struct HTTPSOnlyUpdateTests {
    @Test("Only https links with a host pass")
    func httpsURL() {
        #expect(UpdateChecker.httpsURL("https://example.com/a.zip") == URL(string: "https://example.com/a.zip"))
        #expect(UpdateChecker.httpsURL("HTTPS://example.com/a.zip") != nil)
        #expect(UpdateChecker.httpsURL("http://example.com/a.zip") == nil)
        #expect(UpdateChecker.httpsURL("file:///Applications/Calculator.app") == nil)
        #expect(UpdateChecker.httpsURL("macappstore://itunes.apple.com/app/id1") == nil)
        #expect(UpdateChecker.httpsURL(nil) == nil)
    }

    @Test("An http or file: feed is never fetched")
    func insecureFeedNotFetched() async {
        for feed in ["http://example.com/appcast.xml", "file:///tmp/appcast.xml"] {
            let client = RecordingUpdateClient([feed: appcast(url: "https://example.com/a.zip")])
            let state = await UpdateChecker(client: client).check(app: feedApp(feed: feed))
            #expect(state == .unavailable)
            #expect(client.requestedURLs.isEmpty)
        }
    }

    @Test("A non-https download keeps the update but loses the link")
    func insecureDownloadDropped() async throws {
        for download in ["http://example.com/a.zip", "file:///Applications/Calculator.app"] {
            let meta = try UpdateChecker.parseSparkleMetadata(from: Data(appcast(url: download).utf8))
            #expect(meta?.version == "2.0")
            #expect(meta?.url == nil)
        }

        // The Download button then points at the https feed itself, never the bad link.
        let feed = "https://example.com/appcast.xml"
        let client = RecordingUpdateClient([feed: appcast(url: "http://example.com/a.zip")])
        let state = await UpdateChecker(client: client).check(app: feedApp(feed: feed))
        #expect(state == .updateAvailable(latestVersion: "2.0", source: .sparkle, actionURL: feed))
    }

    @Test("A bare enclosure fallback drops a non-https link too")
    func enclosureFallback() throws {
        let xml = #"<rss><enclosure url="http://example.com/a.zip" sparkle:shortVersionString="3.0"/></rss>"#
        let meta = try UpdateChecker.parseSparkleMetadata(from: Data(xml.utf8))
        #expect(meta?.version == "3.0")
        #expect(meta?.url == nil)
    }

    @Test("A GitHub release redirect must stay on https")
    func gitHubHTTPS() {
        #expect(UpdateChecker.parseGitHubMetadata(fromRedirect: URL(string: "http://github.com/a/b/releases/tag/v1.2")!) == nil)
        #expect(UpdateChecker.parseGitHubMetadata(fromRedirect: URL(string: "https://github.com/a/b/releases/tag/v1.2")!)?.version == "1.2")
    }

    @Test("An App Store page link must be https")
    func appStorePageHTTPS() throws {
        let json = #"{"results":[{"bundleId":"com.example.Bloom","version":"2.0","trackViewUrl":"http://apps.apple.com/app/id1"}]}"#
        let meta = try UpdateChecker.parseAppStoreMetadata(from: Data(json.utf8), preferredBundleID: "com.example.Bloom")
        #expect(meta?.version == "2.0")
        #expect(meta?.url == nil)
    }

    @Test("The link finder does not read an http feed")
    func resolverSkipsInsecureFeed() async {
        let feed = "http://updates.example.com/appcast.xml"
        let client = RecordingUpdateClient([feed: "<rss><channel><link>https://example.com</link></channel></rss>"])
        let link = await AppLinkResolver(client: client).resolve(app: feedApp(feed: feed))
        #expect(client.requestedURLs.isEmpty)
        #expect(link?.url == "http://updates.example.com")
        #expect(await AppLinkResolver(client: client).resolve(app: feedApp(feed: "file:///tmp/appcast.xml")) == nil)
    }
}

@Suite("App Store lookup needs the same bundle ID")
struct AppStoreBundleMatchTests {
    private let otherAppOnly = Data("""
    {"resultCount":1,"results":[{"bundleId":"com.example.Other","trackId":111,"version":"9.0",
    "trackViewUrl":"https://apps.apple.com/app/other/id111"}]}
    """.utf8)

    @Test("Another app's version is not taken as this app's update")
    func noVersionFromOtherApp() throws {
        #expect(try UpdateChecker.parseAppStoreMetadata(from: otherAppOnly, preferredBundleID: "com.example.Bloom") == nil)
    }

    @Test("Another app's store page is not suggested as this app's link")
    func noLinkFromOtherApp() throws {
        #expect(try AppLinkResolver.parseAppStoreLink(from: otherAppOnly, preferredBundleID: "com.example.Bloom") == nil)
    }

    @Test("The matching result wins wherever it sits, and case does not matter")
    func matchingResult() throws {
        let data = Data("""
        {"results":[{"bundleId":"com.example.Other","trackId":111,"version":"9.0"},
        {"bundleId":"com.example.bloom","trackId":222,"version":"2.1","trackViewUrl":"https://apps.apple.com/app/bloom/id222"}]}
        """.utf8)
        let meta = try UpdateChecker.parseAppStoreMetadata(from: data, preferredBundleID: "com.example.Bloom")
        #expect(meta?.version == "2.1")
        #expect(meta?.url == "macappstore://itunes.apple.com/app/id222")
        #expect(try AppLinkResolver.parseAppStoreLink(from: data, preferredBundleID: "com.example.Bloom")
                == "https://apps.apple.com/app/bloom/id222")
    }

    @Test("A store copy with no matching result offers no update")
    func storeCopyWithoutMatch() async throws {
        let bundleID = "com.example.Bloom"
        let lookup = try #require(UpdateChecker.appStoreLookupURL(for: bundleID))
        let client = RecordingUpdateClient([lookup.absoluteString: String(decoding: otherAppOnly, as: UTF8.self)])
        let app = AppInfo(id: bundleID, name: "Bloom", version: "1.0", bundleID: bundleID,
                          path: "/Applications/Bloom.app", humanReadableDescription: nil,
                          sparkleFeedURL: nil, isAppStoreInstall: true, icon: nil)
        #expect(await UpdateChecker(client: client).check(app: app) == .unavailable)
    }
}

@Suite("Sparkle minimum macOS")
struct SparkleMinimumSystemTests {
    /// 3.0 needs macOS 27, 2.5 needs 15.0, 2.0 states no minimum.
    private let feedXML = """
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
    <item><title>3.0</title><sparkle:minimumSystemVersion>27.0</sparkle:minimumSystemVersion>
      <enclosure url="https://example.com/3.0.zip" sparkle:shortVersionString="3.0" sparkle:version="300"/></item>
    <item><title>2.5</title><sparkle:minimumSystemVersion> 15.0 </sparkle:minimumSystemVersion>
      <enclosure url="https://example.com/2.5.zip" sparkle:shortVersionString="2.5" sparkle:version="250"/></item>
    <item><title>2.0</title>
      <enclosure url="https://example.com/2.0.zip" sparkle:shortVersionString="2.0" sparkle:version="200"/></item>
    </channel></rss>
    """

    @Test("The newest release this Mac can run is chosen")
    func newestRunnable() throws {
        let data = Data(feedXML.utf8)
        #expect(try UpdateChecker.parseSparkleMetadata(from: data, systemVersion: "27.0.0")?.version == "3.0")
        #expect(try UpdateChecker.parseSparkleMetadata(from: data, systemVersion: "26.1.0")?.version == "2.5")
        #expect(try UpdateChecker.parseSparkleMetadata(from: data, systemVersion: "15.0.0")?.url == "https://example.com/2.5.zip")
        #expect(try UpdateChecker.parseSparkleMetadata(from: data, systemVersion: "14.7.1")?.version == "2.0")
    }

    @Test("The older attribute form counts too")
    func attributeForm() {
        let item = #"<item><enclosure url="https://example.com/a.zip" sparkle:minimumSystemVersion="26.2"/></item>"#
        #expect(!UpdateChecker.runs(item, onSystemVersion: "26.1.0"))
        #expect(UpdateChecker.runs(item, onSystemVersion: "26.2.0"))
        #expect(UpdateChecker.runs("<item></item>", onSystemVersion: "14.0.0"))
    }

    @Test("When no release runs here, the looser scans do not bring one back")
    func nothingRunnable() throws {
        let xml = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><sparkle:minimumSystemVersion>27.0</sparkle:minimumSystemVersion>
          <enclosure url="https://example.com/3.0.zip" sparkle:shortVersionString="3.0"/></item>
        </channel></rss>
        """
        #expect(try UpdateChecker.parseSparkleFeed(from: Data(xml.utf8), systemVersion: "26.0.0") == .nothingThisMacCanRun)
        #expect(try UpdateChecker.parseSparkleMetadata(from: Data(xml.utf8), systemVersion: "26.0.0") == nil)
    }

    @Test("An app whose new release needs a newer macOS reads as up to date")
    func checkerSkipsTooNew() async {
        let feed = "https://example.com/appcast.xml"
        let xml = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><sparkle:minimumSystemVersion>999.0</sparkle:minimumSystemVersion>
          <enclosure url="https://example.com/9.0.zip" sparkle:shortVersionString="9.0"/></item>
        </channel></rss>
        """
        let client = RecordingUpdateClient([feed: xml])
        let state = await UpdateChecker(client: client).check(app: feedApp(version: "1.0", feed: feed),
                                                              appURL: "https://github.com/author/bloom")
        #expect(state == .upToDate(source: .sparkle))
        // GitHub is not asked: it would offer the same release.
        #expect(client.requestedURLs == [feed])
    }
}

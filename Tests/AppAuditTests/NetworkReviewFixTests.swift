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

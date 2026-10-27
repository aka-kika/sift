import Testing
import Foundation
@testable import Sift

/// Kika's polish round of 2026-10-28 (Runway card "Sift": 0c5e, fffa, 458f, b234).

@Suite("An App Store app is analyzed from its listing, not the store page")
struct AppStoreListingTests {
    /// Apple's lookup answer for Localpage on 28 Oct: a universal purchase, so "software".
    private static let localpage = """
    {"resultCount":1,"results":[{"kind":"software","bundleId":"com.akakika.localpage","trackId":6821429256,
    "trackName":"Localpage","sellerName":"Veronica Loren","primaryGenreName":"Productivity","version":"2.0.1",
    "trackViewUrl":"https://apps.apple.com/us/app/localpage/id6821429256?uo=4",
    "description":"Localpage shows your own HTML pages\\n\\non the Mac and iPad."}]}
    """

    @Test("Store links are told apart from other links")
    func storeLinks() {
        #expect(AppStoreListing.isStoreLink("https://apps.apple.com/us/app/localpage/id6821429256"))
        #expect(AppStoreListing.isStoreLink("apps.apple.com/il/app/x/id1"))
        #expect(!AppStoreListing.isStoreLink("https://localpage.app"))
        #expect(!AppStoreListing.isStoreLink(nil))
    }

    @Test("The store number and storefront come from the link")
    func linkParts() {
        let link = "https://apps.apple.com/il/app/localpage/id6821429256?uo=4"
        #expect(AppStoreListing.trackID(fromLink: link) == "6821429256")
        #expect(AppStoreListing.country(fromLink: link) == "il")
        #expect(AppStoreListing.country(fromLink: "https://apps.apple.com/app/id6821429256") == nil)
    }

    @Test("The lookup asks by store number in the link's storefront, then this Mac's region")
    func lookupOrder() {
        let urls = AppStoreListing.lookupURLs(bundleID: "com.akakika.localpage",
                                              link: "https://apps.apple.com/il/app/localpage/id6821429256",
                                              region: "DE").map(\.absoluteString)
        #expect(urls == ["https://itunes.apple.com/lookup?id=6821429256&country=il",
                         "https://itunes.apple.com/lookup?id=6821429256&country=de"])
        let noLink = AppStoreListing.lookupURLs(bundleID: "com.akakika.localpage", link: nil, region: "US").map(\.absoluteString)
        #expect(noLink == ["https://itunes.apple.com/lookup?bundleId=com.akakika.localpage",
                           "https://itunes.apple.com/lookup?bundleId=com.akakika.localpage&country=us"])
    }

    @Test("A universal purchase's description reaches the prompt, folded to one line")
    func readsUniversalPurchase() throws {
        let found = try #require(AppStoreListing.evidence(fromLookup: Data(Self.localpage.utf8),
                                                          bundleID: "com.akakika.localpage", trackID: nil))
        #expect(found.text.contains("Description: Localpage shows your own HTML pages on the Mac and iPad."))
        #expect(found.text.contains("Seller: Veronica Loren"))
        #expect(found.pageURL == "https://apps.apple.com/us/app/localpage/id6821429256")
    }

    @Test("Another app's result is not this app's listing")
    func otherAppIgnored() {
        #expect(AppStoreListing.evidence(fromLookup: Data(Self.localpage.utf8),
                                         bundleID: "com.example.other", trackID: "1") == nil)
        #expect(AppStoreListing.evidence(fromLookup: Data(#"{"resultCount":0,"results":[]}"#.utf8),
                                         bundleID: "com.akakika.localpage", trackID: nil) == nil)
    }

    @Test("A long description is cut")
    func longDescriptionCut() throws {
        let long = String(repeating: "word ", count: 600)
        let json = #"{"results":[{"bundleId":"a.b","description":"\#(long)"}]}"#
        let found = try #require(AppStoreListing.evidence(fromLookup: Data(json.utf8), bundleID: "a.b", trackID: nil))
        #expect(found.text.count < AppStoreListing.descriptionLimit + 40)
        #expect(found.text.hasSuffix("…"))
    }

    @Test("The service tries the next storefront when the first has nothing")
    func fallsBackToRegion() async {
        let client = ListingClient([
            "https://itunes.apple.com/lookup?bundleId=com.akakika.localpage": #"{"results":[]}"#,
            "https://itunes.apple.com/lookup?bundleId=com.akakika.localpage&country=il": Self.localpage
        ])
        let service = AppStoreListingService(client: client)
        let found = await service.listing(bundleID: "com.akakika.localpage", link: nil, region: "IL")
        #expect(found?.text.contains("Localpage shows") == true)
    }

    @Test("No storefront has it: nil, and the prompt says not found instead of empty")
    func notFound() async {
        let service = AppStoreListingService(client: ListingClient([:]))
        #expect(await service.listing(bundleID: "com.akakika.localpage", link: nil, region: "US") == nil)
        #expect(AppStoreListing.notFoundNote.contains("do not claim the listing has no description"))
    }

    @Test("The prompt labels the listing as the App Store listing")
    func promptLabel() {
        let app = AppInfo(id: "com.akakika.localpage", name: "Localpage", version: "2.1.0", bundleID: "com.akakika.localpage",
                          path: "/Applications/Localpage.app", humanReadableDescription: nil,
                          sparkleFeedURL: nil, isAppStoreInstall: true, icon: nil)
        let prompt = AppAnalysisPrompt.build(app: app, profile: .local(text: "macOS apps"),
                                             appURL: "https://apps.apple.com/us/app/localpage/id6821429256",
                                             linkEvidence: "Description: Localpage shows your own HTML pages.",
                                             includeResponseFormat: true)
        #expect(prompt.contains("App Store listing, read through Apple's public lookup"))
        #expect(!prompt.contains("Fetched from the reference URL (the page's own words"))
    }
}

/// Answers from a fixed table.
private struct ListingClient: UpdateMetadataClient {
    let responses: [String: String]
    init(_ responses: [String: String]) { self.responses = responses }

    func data(for url: URL) async throws -> Data {
        guard let body = responses[url.absoluteString] else { throw URLError(.badServerResponse) }
        return Data(body.utf8)
    }

    func redirectLocation(for url: URL) async throws -> URL? { nil }
}

private func app(_ name: String, added: Date? = nil, used: Date? = nil, myApp: Bool = false) -> AppInfo {
    AppInfo(id: "/Applications/\(name).app", name: name, version: "1.0", bundleID: "com.example.\(name.lowercased())",
            path: "/Applications/\(name).app", humanReadableDescription: nil, sparkleFeedURL: nil,
            isAppStoreInstall: false, icon: nil, lastUsedDate: used, addedDate: added, isMyApp: myApp)
}

@Suite("Last Added sort")
@MainActor
struct LastAddedSortTests {
    @Test("Newest added first, apps with no date last, then by name")
    func newestFirst() {
        let viewModel = AppListViewModel()
        let now = Date()
        viewModel.apps = [app("Old", added: now.addingTimeInterval(-86_400 * 30)),
                          app("Zed"), app("New", added: now), app("Abe")]
        viewModel.setSortOrder(.lastAdded)
        #expect(viewModel.filteredApps.map(\.name) == ["New", "Old", "Abe", "Zed"])
    }

    @Test("The sort menu offers Last Added")
    func inMenu() {
        #expect(AppListViewModel.SortOrder.allCases.contains(.lastAdded))
        #expect(AppListViewModel.SortOrder.lastAdded.rawValue == "Last Added")
    }
}

@Suite("Search palette")
@MainActor
struct SearchPaletteTests {
    @Test("Names starting with the query come first, then names containing it")
    func ordering() {
        let apps = [app("Docker"), app("Kartina"), app("Karabiner"), app("Sidekar")]
        #expect(PaletteSearch.matches(in: apps, query: "kar").map(\.name) == ["Karabiner", "Kartina", "Sidekar"])
        #expect(PaletteSearch.matches(in: apps, query: "  ").isEmpty)
    }

    @Test("At most eight results")
    func limit() {
        let apps = (1...20).map { app("App\($0)") }
        #expect(PaletteSearch.matches(in: apps, query: "app").count == PaletteSearch.limit)
    }

    @Test("Opening an app hidden by a filter brings the full list back and selects it")
    func opensHiddenApp() {
        let viewModel = AppListViewModel()
        viewModel.apps = [app("Mine", myApp: true), app("Other")]
        viewModel.setFilterMyApps(true)
        viewModel.showingSearchPalette = true
        viewModel.openFromSearch(appID: "/Applications/Other.app")
        #expect(viewModel.selectedAppID == "/Applications/Other.app")
        #expect(!viewModel.filterMyApps)
        #expect(!viewModel.showingSearchPalette)
        #expect(viewModel.filteredApps.contains { $0.name == "Other" })
    }
}

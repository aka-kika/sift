import Foundation

/// What Apple's public lookup says about an App Store app, for the analysis
/// prompt. The store's web page only carries a generic "Download X on the App
/// Store. See screenshots, ratings and reviews" line, so reading the page told
/// the model the listing had no description (Localpage, 28 Oct). The lookup
/// returns the developer's own description.
enum AppStoreListing {
    /// What the prompt gets when the lookup finds nothing. It must never read
    /// as "the listing is empty".
    static let notFoundNote = """
    Not found. Apple's lookup returned no listing for this app, or could not be reached: it may be a TestFlight build, not sold in this storefront, or removed from the store. This says nothing about what the listing contains, so do not claim the listing has no description; rely on the other evidence.
    """

    /// Longest description passed on; the opening paragraphs say what the app is.
    static let descriptionLimit = 1_200

    static func isStoreLink(_ urlString: String?) -> Bool {
        guard let normalized = AppLinkInput.normalized(urlString),
              let host = URL(string: normalized)?.host(percentEncoded: false)?.lowercased() else { return false }
        return host == "apps.apple.com" || host == "itunes.apple.com"
    }

    /// `apps.apple.com/us/app/localpage/id6821429256` → "6821429256".
    static func trackID(fromLink urlString: String?) -> String? {
        guard isStoreLink(urlString), let normalized = AppLinkInput.normalized(urlString),
              let url = URL(string: normalized) else { return nil }
        let segment = url.path(percentEncoded: false).split(separator: "/").last { $0.hasPrefix("id") }
        guard let digits = segment?.dropFirst(2), !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        return String(digits)
    }

    /// The storefront in the link's path (`/il/app/...` → "il").
    static func country(fromLink urlString: String?) -> String? {
        guard isStoreLink(urlString), let normalized = AppLinkInput.normalized(urlString),
              let first = URL(string: normalized)?.path(percentEncoded: false).split(separator: "/").first,
              first.count == 2, first.allSatisfy(\.isLetter) else { return nil }
        return first.lowercased()
    }

    /// The lookups to try, in order: the link's storefront (or the default,
    /// the US store), then this Mac's region. An app missing from one
    /// storefront is often sold in another.
    static func lookupURLs(bundleID: String, link: String?, region: String?) -> [URL] {
        var countries: [String?] = [country(fromLink: link)]
        if let region = region?.lowercased(), region.count == 2, !countries.contains(region) {
            countries.append(region)
        }
        let id = trackID(fromLink: link)
        return countries.compactMap { country in
            var components = URLComponents(string: "https://itunes.apple.com/lookup")
            var items = id.map { [URLQueryItem(name: "id", value: $0)] }
                ?? [URLQueryItem(name: "bundleId", value: bundleID)]
            if let country { items.append(URLQueryItem(name: "country", value: country)) }
            components?.queryItems = items
            return components?.url
        }
    }

    struct Found: Equatable {
        /// The listing's words for the prompt.
        let text: String
        /// The store page, without the query, for an app with no saved link.
        let pageURL: String?
    }

    /// The listing as prompt evidence, or nil when the answer holds no result
    /// for this app. A result counts when its bundle ID or its store number
    /// matches; a universal purchase ("software" for iPhone and Mac) counts too.
    static func evidence(fromLookup data: Data, bundleID: String, trackID: String?) -> Found? {
        guard let response = try? JSONDecoder().decode(LookupResponse.self, from: data) else { return nil }
        let match = response.results.first { result in
            UpdateChecker.isSameBundleID(result.bundleId, bundleID)
                || (trackID != nil && result.trackId.map(String.init) == trackID)
        }
        guard let match else { return nil }

        var lines: [String] = []
        if let name = clean(match.trackName) { lines.append("Name: \(name)") }
        if let seller = clean(match.sellerName ?? match.artistName) { lines.append("Seller: \(seller)") }
        if let genre = clean(match.primaryGenreName) { lines.append("Category: \(genre)") }
        if let description = clean(match.description) {
            let short = description.count > descriptionLimit
                ? String(description.prefix(descriptionLimit)) + "…"
                : description
            lines.append("Description: \(short)")
        }
        guard !lines.isEmpty else { return nil }
        let page = UpdateChecker.httpsURL(match.trackViewUrl).flatMap(LinkEvidence.withoutQueryOrFragment)
        return Found(text: lines.joined(separator: "\n"), pageURL: page?.absoluteString)
    }

    /// Whitespace and line breaks folded to single spaces; nil when empty.
    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let folded = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return folded.isEmpty ? nil : folded
    }

    private struct LookupResponse: Decodable {
        let results: [Result]
    }

    private struct Result: Decodable {
        let bundleId: String?
        let trackId: Int?
        let trackName: String?
        let sellerName: String?
        let artistName: String?
        let primaryGenreName: String?
        let description: String?
        let trackViewUrl: String?
    }
}

/// Reads and caches App Store listings for the lifetime of the app run.
actor AppStoreListingService {
    private var cache: [String: AppStoreListing.Found] = [:]
    private let client: any UpdateMetadataClient

    init(client: any UpdateMetadataClient = LiveUpdateMetadataClient()) {
        self.client = client
    }

    /// The listing, or nil when no storefront has it.
    func listing(bundleID: String, link: String?, region: String? = Locale.current.region?.identifier) async -> AppStoreListing.Found? {
        let key = "\(bundleID)|\(link ?? "")"
        if let cached = cache[key] { return cached }
        let trackID = AppStoreListing.trackID(fromLink: link)
        for url in AppStoreListing.lookupURLs(bundleID: bundleID, link: link, region: region) {
            guard let data = try? await client.data(for: url),
                  let found = AppStoreListing.evidence(fromLookup: data, bundleID: bundleID, trackID: trackID) else { continue }
            cache[key] = found
            return found
        }
        // Not cached: a lookup that failed for want of network may work on the next try.
        return nil
    }
}

import Foundation

actor AppLinkResolver {
    struct ResolvedLink: Equatable {
        let url: String
        let source: Source

        enum Source: String {
            case appStore = "App Store"
            case sparkle = "Sparkle"
        }
    }

    private let client: any UpdateMetadataClient

    init(client: any UpdateMetadataClient = LiveUpdateMetadataClient()) {
        self.client = client
    }

    func resolve(app: AppInfo) async -> ResolvedLink? {
        if app.isAppStoreInstall,
           let appStoreLink = await fetchAppStoreLink(bundleID: app.bundleID) {
            return ResolvedLink(url: appStoreLink, source: .appStore)
        }

        if let sparkleLink = await fetchSparkleWebsite(feedURLString: app.sparkleFeedURL) {
            return ResolvedLink(url: sparkleLink, source: .sparkle)
        }

        return nil
    }

    private func fetchAppStoreLink(bundleID: String) async -> String? {
        guard let lookupURL = UpdateChecker.appStoreLookupURL(for: bundleID) else { return nil }

        do {
            let data = try await client.data(for: lookupURL)
            return try Self.parseAppStoreLink(from: data, preferredBundleID: bundleID)
        } catch {
            return nil
        }
    }

    private func fetchSparkleWebsite(feedURLString: String?) async -> String? {
        guard let feedURLString,
              let feedURL = URL(string: feedURLString) else { return nil }

        do {
            let data = try await client.data(for: feedURL)
            return try Self.parseSparkleWebsite(from: data, feedURL: feedURL)
        } catch {
            return Self.rootWebsite(from: feedURL)
        }
    }

    static func parseAppStoreLink(from data: Data, preferredBundleID: String? = nil) throws -> String? {
        let response = try JSONDecoder().decode(AppStoreLinkLookupResponse.self, from: data)
        let result =
            response.results.first(where: {
                $0.bundleID == preferredBundleID && ($0.trackViewURL ?? "").isEmpty == false
            }) ??
            response.results.first(where: { ($0.trackViewURL ?? "").isEmpty == false })

        return result?.trackViewURL
    }

    static func parseSparkleWebsite(from data: Data, feedURL: URL) throws -> String? {
        guard let xml = String(data: data, encoding: .utf8) else {
            return rootWebsite(from: feedURL)
        }

        let channelBody = firstCapturedValue(for: #"<channel\b[^>]*>([\s\S]*?)</channel>"#, in: xml) ?? xml
        if let link = firstCapturedValue(for: #"<link>\s*([^<]+?)\s*</link>"#, in: channelBody),
           let normalized = normalizeWebsite(link, relativeTo: feedURL) {
            return normalized
        }

        return rootWebsite(from: feedURL)
    }

    private static func normalizeWebsite(_ value: String, relativeTo baseURL: URL) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url.absoluteString
        }

        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL.absoluteString
    }

    private static func rootWebsite(from url: URL) -> String? {
        guard let scheme = url.scheme,
              let host = url.host else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        return components.url?.absoluteString
    }

    private static func firstCapturedValue(for pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[captureRange])
    }
}

private struct AppStoreLinkLookupResponse: Decodable {
    let results: [AppStoreLinkLookupResult]
}

private struct AppStoreLinkLookupResult: Decodable {
    let bundleID: String?
    let trackViewURL: String?

    enum CodingKeys: String, CodingKey {
        case bundleID = "bundleId"
        case trackViewURL = "trackViewUrl"
    }
}

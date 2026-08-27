import Foundation

protocol UpdateMetadataClient: Sendable {
    func data(for url: URL) async throws -> Data
}

struct LiveUpdateMetadataClient: UpdateMetadataClient {
    func data(for url: URL) async throws -> Data {
        // Abandoned apps have dead feeds; 60 s per host would stall the whole refresh.
        let request = URLRequest(url: url, timeoutInterval: 15)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

actor UpdateChecker {
    struct UpdateMetadata: Equatable {
        let version: String
        let url: String?
    }

    private let client: any UpdateMetadataClient
    private let homebrew = HomebrewService()
    private var outdatedCasksCache: [HomebrewCaskInfo]?

    init(client: any UpdateMetadataClient = LiveUpdateMetadataClient()) {
        self.client = client
    }

    func resetHomebrewCache() {
        outdatedCasksCache = nil
    }

    func check(app: AppInfo, acknowledgedVersion: String? = nil) async -> AppInfo.UpdateState {
        if app.isAppStoreInstall,
           let appStoreMetadata = await fetchAppStoreMetadata(bundleID: app.bundleID) {
            if Self.isVersion(appStoreMetadata.version, newerThan: app.version) {
                if acknowledgedVersion == appStoreMetadata.version {
                    return .upToDate(source: .appStore)
                }
                return .updateAvailable(
                    latestVersion: appStoreMetadata.version,
                    source: .appStore,
                    actionURL: appStoreMetadata.url
                )
            }
            return .upToDate(source: .appStore)
        }

        if let homebrewMetadata = fetchHomebrewMetadata(caskToken: app.homebrewCaskToken),
           let latestVersion = homebrewMetadata.latestVersion,
           Self.isVersion(latestVersion, newerThan: app.version) {
            if acknowledgedVersion == latestVersion {
                return .upToDate(source: .homebrew)
            }
            return .updateAvailable(
                latestVersion: latestVersion,
                source: .homebrew,
                actionURL: nil
            )
        }

        if let sparkleMetadata = await fetchSparkleMetadata(feedURLString: app.sparkleFeedURL) {
            if Self.isVersion(sparkleMetadata.version, newerThan: app.version) {
                if acknowledgedVersion == sparkleMetadata.version {
                    return .upToDate(source: .sparkle)
                }
                return .updateAvailable(
                    latestVersion: sparkleMetadata.version,
                    source: .sparkle,
                    actionURL: sparkleMetadata.url ?? app.sparkleFeedURL
                )
            }
            return .upToDate(source: .sparkle)
        }

        // Precedence: App Store > Homebrew (only when brew reports it outdated) >
        // Sparkle > "brew-installed and current". A current cask app that also has
        // a Sparkle feed therefore takes Sparkle's verdict — deliberate, since
        // many casks lag the vendor's own feed.
        if app.homebrewCaskToken != nil {
            return .upToDate(source: .homebrew)
        }

        return .unavailable
    }

    private func fetchAppStoreMetadata(bundleID: String) async -> UpdateMetadata? {
        guard let lookupURL = Self.appStoreLookupURL(for: bundleID) else { return nil }

        do {
            let data = try await client.data(for: lookupURL)
            return try Self.parseAppStoreMetadata(from: data, preferredBundleID: bundleID)
        } catch {
            return nil
        }
    }

    private func fetchSparkleMetadata(feedURLString: String?) async -> UpdateMetadata? {
        guard let feedURLString,
              let feedURL = URL(string: feedURLString) else { return nil }

        do {
            let data = try await client.data(for: feedURL)
            return try Self.parseSparkleMetadata(from: data)
        } catch {
            return nil
        }
    }

    private func fetchHomebrewMetadata(caskToken: String?) -> HomebrewCaskInfo? {
        guard let caskToken else { return nil }
        if outdatedCasksCache == nil {
            outdatedCasksCache = homebrew.outdatedCasks()
        }
        return outdatedCasksCache?.first { $0.token == caskToken }
    }

    static func appStoreLookupURL(for bundleID: String) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "entity", value: "macSoftware")
        ]
        return components?.url
    }

    static func isVersion(_ candidate: String, newerThan installed: String) -> Bool {
        let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let installed = installed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !installed.isEmpty else { return false }
        return candidate.compare(installed, options: [.numeric, .caseInsensitive]) == .orderedDescending
    }

    static func parseAppStoreMetadata(
        from data: Data,
        preferredBundleID: String? = nil
    ) throws -> UpdateMetadata? {
        let response = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
        let result =
            response.results.first(where: {
                $0.bundleID == preferredBundleID && ($0.version ?? "").isEmpty == false
            }) ??
            response.results.first(where: { ($0.version ?? "").isEmpty == false })

        guard let result, let version = result.version, !version.isEmpty else {
            return nil
        }

        let url = result.trackID.map { "macappstore://itunes.apple.com/app/id\($0)" } ?? result.trackViewURL
        return UpdateMetadata(version: version, url: url)
    }

    static func parseSparkleMetadata(from data: Data) throws -> UpdateMetadata? {
        guard let xml = String(data: data, encoding: .utf8) else { return nil }

        // Per <item>: the human version (shortVersionString, attribute or element)
        // beats the build number (sparkle:version), and anything on a named
        // channel (beta, nightly) is not an update for a release install.
        let items = matches(for: #"(?s)(<item\b.*?</item>)"#, in: xml).compactMap(\.first)
        let itemVersions = items.compactMap(parseSparkleItem)
        if let newestItem = newestMetadata(in: itemVersions) {
            return newestItem
        }

        let enclosureVersions = enclosureTags(in: xml).compactMap(parseSparkleEnclosure)
        if let newestEnclosure = newestMetadata(in: enclosureVersions) {
            return newestEnclosure
        }

        let versions =
            matches(for: #"sparkle:shortVersionString="([^"]+)""#, in: xml).map(\.first) +
            matches(for: #"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>"#, in: xml).map(\.first)

        let normalizedVersions = versions.compactMap { $0 }
        guard let newestVersion = newestVersion(in: normalizedVersions) else { return nil }

        let fallbackURL = matches(
            for: #"<enclosure\b[^>]*url="([^"]+)""#,
            in: xml
        ).compactMap(\.first).first

        return UpdateMetadata(version: newestVersion, url: fallbackURL)
    }

    private static func newestMetadata(in candidates: [UpdateMetadata]) -> UpdateMetadata? {
        guard var newest = candidates.first else { return nil }
        for candidate in candidates.dropFirst() where isVersion(candidate.version, newerThan: newest.version) {
            newest = candidate
        }
        return newest
    }

    private static func newestVersion(in versions: [String]) -> String? {
        guard var newest = versions.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !newest.isEmpty else {
            return nil
        }

        for version in versions.dropFirst() {
            let cleaned = version.trimmingCharacters(in: .whitespacesAndNewlines)
            if isVersion(cleaned, newerThan: newest) {
                newest = cleaned
            }
        }

        return newest
    }

    private static func matches(for pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)

        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }

            var captures: [String] = []
            for rangeIndex in 1..<match.numberOfRanges {
                guard let captureRange = Range(match.range(at: rangeIndex), in: text) else {
                    return nil
                }
                captures.append(String(text[captureRange]))
            }
            return captures
        }
    }

    private static func enclosureTags(in xml: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<enclosure\b[^>]*\/?>"#) else { return [] }
        let range = NSRange(xml.startIndex..., in: xml)

        return regex.matches(in: xml, range: range).compactMap { match in
            guard let tagRange = Range(match.range(at: 0), in: xml) else { return nil }
            return String(xml[tagRange])
        }
    }

    private static func parseSparkleItem(_ item: String) -> UpdateMetadata? {
        if let channel = firstCapturedValue(for: #"<sparkle:channel>\s*([^<]+?)\s*</sparkle:channel>"#, in: item),
           !channel.isEmpty {
            return nil
        }
        let enclosure = enclosureTags(in: item).first
        let version =
            enclosure.flatMap { firstCapturedValue(for: #"sparkle:shortVersionString="([^"]+)""#, in: $0) } ??
            firstCapturedValue(for: #"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>"#, in: item) ??
            enclosure.flatMap { firstCapturedValue(for: #"sparkle:version="([^"]+)""#, in: $0) } ??
            firstCapturedValue(for: #"<sparkle:version>([^<]+)</sparkle:version>"#, in: item)
        guard let version = version?.trimmingCharacters(in: .whitespacesAndNewlines), !version.isEmpty else {
            return nil
        }
        let url = enclosure.flatMap { firstCapturedValue(for: #"url="([^"]+)""#, in: $0) }
        return UpdateMetadata(version: version, url: url)
    }

    private static func parseSparkleEnclosure(from tag: String) -> UpdateMetadata? {
        guard let url = firstCapturedValue(for: #"url="([^"]+)""#, in: tag),
              let version =
                firstCapturedValue(for: #"sparkle:shortVersionString="([^"]+)""#, in: tag) ??
                firstCapturedValue(for: #"sparkle:version="([^"]+)""#, in: tag) else {
            return nil
        }

        return UpdateMetadata(version: version, url: url)
    }

    private static func firstCapturedValue(for pattern: String, in text: String) -> String? {
        matches(for: pattern, in: text).first?.first
    }
}

private struct AppStoreLookupResponse: Decodable {
    let results: [AppStoreLookupResult]
}

private struct AppStoreLookupResult: Decodable {
    let bundleID: String?
    let trackID: Int?
    let version: String?
    let trackViewURL: String?

    enum CodingKeys: String, CodingKey {
        case bundleID = "bundleId"
        case trackID = "trackId"
        case version
        case trackViewURL = "trackViewUrl"
    }
}

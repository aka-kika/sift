import Foundation

protocol UpdateMetadataClient: Sendable {
    func data(for url: URL) async throws -> Data
    /// Where `url` redirects to, without following it. Nil when it does not redirect.
    func redirectLocation(for url: URL) async throws -> URL?
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

    func redirectLocation(for url: URL) async throws -> URL? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: request, delegate: RedirectStopper())
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (300..<400).contains(httpResponse.statusCode) else {
            if (200..<300).contains(httpResponse.statusCode) { return nil }
            throw URLError(.badServerResponse)
        }
        return httpResponse.value(forHTTPHeaderField: "Location").flatMap { URL(string: $0, relativeTo: url)?.absoluteURL }
    }
}

/// Refuses the redirect, so the 3xx response itself comes back with its Location.
private final class RedirectStopper: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}

actor UpdateChecker {
    struct UpdateMetadata: Equatable {
        let version: String
        let url: String?
        /// The feed's build number (`sparkle:version`), when it states one.
        var build: String? = nil

        /// What the update button shows: the build joins the version only when
        /// the version alone would read as "no change".
        func displayVersion(installedVersion: String) -> String {
            guard let build, VersionComparator.compare(version, installedVersion) == .orderedSame else { return version }
            return "\(version) (\(build))"
        }
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

    /// `appURL` is the link the user saved for the app. When it points at a
    /// GitHub repo, that repo's latest release is the last source asked.
    func check(app: AppInfo, acknowledgedVersion: String? = nil, appURL: String? = nil) async -> AppInfo.UpdateState {
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
            if Self.isRelease(sparkleMetadata, newerThanVersion: app.version, build: app.build) {
                let latestVersion = sparkleMetadata.displayVersion(installedVersion: app.version)
                if acknowledgedVersion == latestVersion {
                    return .upToDate(source: .sparkle)
                }
                return .updateAvailable(
                    latestVersion: latestVersion,
                    source: .sparkle,
                    actionURL: sparkleMetadata.url ?? app.sparkleFeedURL
                )
            }
            return .upToDate(source: .sparkle)
        }

        // A store copy is answered by the store or by nobody: a GitHub build of
        // the same app is a different install, not an update for this one.
        if !app.isAppStoreInstall,
           let githubMetadata = await fetchGitHubMetadata(appURL: appURL) {
            if Self.isVersion(githubMetadata.version, newerThan: app.version) {
                if acknowledgedVersion == githubMetadata.version {
                    return .upToDate(source: .github)
                }
                return .updateAvailable(
                    latestVersion: githubMetadata.version,
                    source: .github,
                    actionURL: githubMetadata.url
                )
            }
            return .upToDate(source: .github)
        }

        // Precedence: App Store > Homebrew (only when brew reports it outdated) >
        // Sparkle > GitHub releases > "brew-installed and current". A current cask
        // app that also has a Sparkle feed or a GitHub link therefore takes that
        // verdict — deliberate, since many casks lag the vendor's own feed.
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

    private func fetchGitHubMetadata(appURL: String?) async -> UpdateMetadata? {
        guard let releaseURL = Self.gitHubLatestReleaseURL(forAppURL: appURL) else { return nil }

        do {
            guard let location = try await client.redirectLocation(for: releaseURL) else { return nil }
            return Self.parseGitHubMetadata(fromRedirect: location)
        } catch {
            // A missing repo or no network: no answer is better than a wrong one.
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

    /// `https://github.com/owner/repo[/anything]` → that repo's `/releases/latest`
    /// page, which redirects to the newest release's tag and already leaves out
    /// drafts and prereleases.
    ///
    /// The web page, not `api.github.com`, on purpose: the API allows an app
    /// with no token 60 requests an hour, and — measured 2026-09-19 — a `304`
    /// still spends one of them, so conditional requests buy nothing here. The
    /// redirect carries the tag in its `Location` header and is not counted
    /// against that limit, so a shelf full of GitHub links stays checkable.
    static func gitHubLatestReleaseURL(forAppURL appURL: String?) -> URL? {
        guard let appURL = AppLinkInput.normalized(appURL),
              let components = URLComponents(string: appURL),
              let host = components.host?.lowercased(),
              host == "github.com" || host == "www.github.com" else { return nil }

        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let owner = parts[0]
        var repo = parts[1]
        if repo.hasSuffix(".git") { repo.removeLast(4) }

        // github.com/orgs/…, /settings/…, /sponsors/… are not repos.
        let reservedOwners: Set<String> = ["orgs", "settings", "sponsors", "marketplace", "topics", "features", "about"]
        guard !owner.isEmpty, !repo.isEmpty, !reservedOwners.contains(owner.lowercased()) else { return nil }
        return URL(string: "https://github.com/\(owner)/\(repo)/releases/latest")
    }

    /// The version inside a release tag: `v1.2.3`, `release-1.2.3`, `app/2.0.1`.
    /// A tag with no dotted number (`nightly`, `build-4521`) gives nil — comparing
    /// a build counter with a marketing version would invent updates.
    static func version(fromGitHubTag tag: String) -> String? {
        matches(for: #"(\d+(?:\.\d+)+)"#, in: tag).first?.first
    }

    /// `…/releases/tag/<tag>` → the release. A repo with no releases redirects
    /// to plain `…/releases`, which is no answer. Tags may contain slashes.
    static func parseGitHubMetadata(fromRedirect location: URL) -> UpdateMetadata? {
        let marker = "/releases/tag/"
        guard let host = location.host()?.lowercased(), host == "github.com" || host == "www.github.com",
              let range = location.path.range(of: marker) else { return nil }
        let tag = String(location.path[range.upperBound...])
        guard !tag.isEmpty, let version = version(fromGitHubTag: tag) else { return nil }
        return UpdateMetadata(version: version, url: location.absoluteString)
    }

    static func isVersion(_ candidate: String, newerThan installed: String) -> Bool {
        let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let installed = installed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !installed.isEmpty else { return false }
        return VersionComparator.isNewer(candidate, than: installed)
    }

    /// Newer by version — or, when the vendor ships a new build under an
    /// unchanged version (Amp: `1.0` build 374 → 390), newer by build. The build
    /// only ever breaks a tie: feeds and bundles do not always number builds the
    /// same way, so it never overrules the version.
    static func isRelease(_ candidate: UpdateMetadata, newerThanVersion installedVersion: String, build installedBuild: String?) -> Bool {
        if isVersion(candidate.version, newerThan: installedVersion) { return true }
        guard VersionComparator.compare(candidate.version, installedVersion) == .orderedSame,
              let candidateBuild = candidate.build, let installedBuild,
              !installedVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return isVersion(candidateBuild, newerThan: installedBuild)
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
        for candidate in candidates.dropFirst()
        where isRelease(candidate, newerThanVersion: newest.version, build: newest.build) {
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
        let build =
            enclosure.flatMap { firstCapturedValue(for: #"sparkle:version="([^"]+)""#, in: $0) } ??
            firstCapturedValue(for: #"<sparkle:version>([^<]+)</sparkle:version>"#, in: item)
        return UpdateMetadata(version: version, url: url,
                              build: build?.trimmingCharacters(in: .whitespacesAndNewlines))
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

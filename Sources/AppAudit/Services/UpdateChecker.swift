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
        /// the version alone would read as "no change". A feed that names only
        /// a build keeps the installed version in the label, so it does not
        /// read as "Update to 2045".
        func displayVersion(installedVersion: String) -> String {
            let marketing = version.trimmingCharacters(in: .whitespacesAndNewlines)
            if marketing.isEmpty {
                guard let build, !build.isEmpty else { return installedVersion }
                let installed = installedVersion.trimmingCharacters(in: .whitespacesAndNewlines)
                return installed.isEmpty ? build : "\(installed) (\(build))"
            }
            guard let build, VersionComparator.compare(marketing, installedVersion) == .orderedSame else { return marketing }
            return "\(marketing) (\(build))"
        }
    }

    private let client: any UpdateMetadataClient
    private let homebrew = HomebrewService()
    private var outdatedCasksCache: HomebrewOutdatedAnswer?

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

        let brew = caskStatus(token: app.homebrewCaskToken)
        if case .outdated(let latestVersion) = brew,
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

        switch await fetchSparkleFeed(feedURLString: app.sparkleFeedURL) {
        case .release(let sparkleMetadata)?:
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
        case .nothingThisMacCanRun?:
            // What the app's own updater says too. Asking GitHub next would
            // offer the same release this Mac cannot run.
            return .upToDate(source: .sparkle)
        case nil:
            break
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
            // Brew did not answer. "Up to date" would be a guess.
            if case .unavailable = brew { return .unavailable }
            return .upToDate(source: .homebrew)
        }

        return .unavailable
    }

    private func fetchAppStoreMetadata(bundleID: String) async -> UpdateMetadata? {
        guard let lookupURL = Self.appStoreLookupURL(for: bundleID) else { return nil }

        do {
            let data = try await client.data(for: lookupURL)
            return try Self.parseAppStoreMetadata(from: data, preferredBundleID: bundleID, systemVersion: Self.currentSystemVersion)
        } catch {
            return nil
        }
    }

    private func fetchSparkleFeed(feedURLString: String?) async -> SparkleFeedAnswer? {
        guard let feedURL = Self.httpsURL(feedURLString) else { return nil }

        do {
            let data = try await client.data(for: feedURL)
            return try Self.parseSparkleFeed(from: data)
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

    /// What `brew outdated` said about one cask.
    enum CaskStatus: Equatable {
        case outdated(String)
        case notOutdated
        case unavailable
    }

    /// `notOutdated` only when brew answered and this cask was not in the list.
    static func caskStatus(token: String?, answer: HomebrewOutdatedAnswer) -> CaskStatus {
        guard token != nil else { return .notOutdated }
        switch answer {
        case .failed:
            return .unavailable
        case .list(let casks):
            guard let token else { return .notOutdated }
            if let version = casks.first(where: { $0.token == token })?.latestVersion, !version.isEmpty {
                return .outdated(version)
            }
            return .notOutdated
        }
    }

    private func caskStatus(token: String?) -> CaskStatus {
        guard token != nil else { return .notOutdated }
        if outdatedCasksCache == nil {
            outdatedCasksCache = homebrew.outdatedCasks()
        }
        return Self.caskStatus(token: token, answer: outdatedCasksCache ?? .failed)
    }

    /// Feeds and download links count only over https: an http feed can be
    /// swapped on the way, and a file: or http link would be opened as is
    /// under the Download button.
    static func httpsURL(_ string: String?) -> URL? {
        guard let string = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: string),
              url.scheme?.lowercased() == "https",
              let host = url.host(), !host.isEmpty else { return nil }
        return url
    }

    /// Bundle IDs compare without case, as the store's lookup does.
    static func isSameBundleID(_ result: String?, _ installed: String) -> Bool {
        guard let result, !installed.isEmpty else { return false }
        return result.caseInsensitiveCompare(installed) == .orderedSame
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
        guard location.scheme?.lowercased() == "https",
              let host = location.host()?.lowercased(), host == "github.com" || host == "www.github.com",
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
        let marketing = candidate.version.trimmingCharacters(in: .whitespacesAndNewlines)
        if marketing.isEmpty {
            // The feed named a build and no marketing version. Compare that
            // build with the app's build, never with the marketing version.
            guard let candidateBuild = candidate.build, let installedBuild else { return false }
            return isVersion(candidateBuild, newerThan: installedBuild)
        }
        if isVersion(marketing, newerThan: installedVersion) { return true }
        guard VersionComparator.compare(marketing, installedVersion) == .orderedSame,
              let candidateBuild = candidate.build, let installedBuild,
              !installedVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return isVersion(candidateBuild, newerThan: installedBuild)
    }

    /// Only a result for this very bundle ID counts: the lookup can return a
    /// related app, and its version or store page would be the wrong answer.
    static func parseAppStoreMetadata(
        from data: Data,
        preferredBundleID: String,
        systemVersion: String = currentSystemVersion
    ) throws -> UpdateMetadata? {
        let response = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
        let result = response.results.first(where: {
            isSameBundleID($0.bundleID, preferredBundleID) && ($0.version ?? "").isEmpty == false
        })

        guard let result, let version = result.version, !version.isEmpty else {
            return nil
        }
        // The store still lists a release this Mac cannot run. The README
        // says those are skipped.
        guard runsOnThisMac(minimumOS: result.minimumOsVersion, systemVersion: systemVersion) else {
            return nil
        }

        // The macappstore: link is built here from a number, so it is safe to open.
        let url = result.trackID.map { "macappstore://itunes.apple.com/app/id\($0)" }
            ?? httpsURL(result.trackViewURL)?.absoluteString
        return UpdateMetadata(version: version, url: url)
    }

    /// False when the store's `minimumOsVersion` is newer than this Mac.
    /// No minimum: the release is offered.
    static func runsOnThisMac(minimumOS: String?, systemVersion: String) -> Bool {
        guard let minimum = minimumOS?.trimmingCharacters(in: .whitespacesAndNewlines), !minimum.isEmpty else { return true }
        return !VersionComparator.isNewer(minimum, than: systemVersion)
    }

    /// This Mac's macOS version, as `26.1.0`.
    static var currentSystemVersion: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    enum SparkleFeedAnswer: Equatable {
        case release(UpdateMetadata)
        /// The feed has releases, but each needs a newer macOS than this Mac has.
        case nothingThisMacCanRun
    }

    /// The newest release this Mac can run, nil when the feed names none.
    static func parseSparkleMetadata(from data: Data, systemVersion: String = currentSystemVersion) throws -> UpdateMetadata? {
        guard case .release(let metadata)? = try parseSparkleFeed(from: data, systemVersion: systemVersion) else { return nil }
        return metadata
    }

    /// `systemVersion` is the macOS to judge `sparkle:minimumSystemVersion`
    /// against; tests pass their own.
    static func parseSparkleFeed(from data: Data, systemVersion: String = currentSystemVersion) throws -> SparkleFeedAnswer? {
        guard let xml = String(data: data, encoding: .utf8) else { return nil }

        // Per <item>: the human version (shortVersionString, attribute or element)
        // beats the build number (sparkle:version), and anything on a named
        // channel (beta, nightly) is not an update for a release install.
        // An item that needs a newer macOS than this Mac has is not offered:
        // the newest item this Mac can run is the answer.
        let items = matches(for: #"(?s)(<item\b.*?</item>)"#, in: xml).compactMap(\.first)
        let runnableItems = items.filter { runs($0, onSystemVersion: systemVersion) }
        let itemVersions = runnableItems.compactMap(parseSparkleItem)
        if let newestItem = newestMetadata(in: itemVersions) {
            return .release(newestItem)
        }
        // Every item was on a channel (beta, nightly). The looser scan below
        // cannot see that, and would offer the beta.
        if !runnableItems.isEmpty && runnableItems.allSatisfy(isOnUpdateChannel) {
            return nil
        }
        // The looser scans below cannot see which item an enclosure belongs to,
        // so they would bring a skipped release back.
        guard runnableItems.count == items.count else { return .nothingThisMacCanRun }

        let enclosureVersions = enclosureTags(in: xml).compactMap(parseSparkleEnclosure)
        if let newestEnclosure = newestMetadata(in: enclosureVersions) {
            return .release(newestEnclosure)
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

        return .release(UpdateMetadata(version: newestVersion, url: httpsURL(fallbackURL)?.absoluteString))
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

    /// False when the item's `sparkle:minimumSystemVersion` (element, or the
    /// older attribute form) is newer than `systemVersion`. No minimum: it runs.
    static func runs(_ item: String, onSystemVersion systemVersion: String) -> Bool {
        let minimum =
            firstCapturedValue(for: #"<sparkle:minimumSystemVersion>\s*([^<]+?)\s*</sparkle:minimumSystemVersion>"#, in: item) ??
            firstCapturedValue(for: #"sparkle:minimumSystemVersion="([^"]+)""#, in: item)
        guard let minimum = minimum?.trimmingCharacters(in: .whitespacesAndNewlines), !minimum.isEmpty else { return true }
        return !VersionComparator.isNewer(minimum, than: systemVersion)
    }

    private static func isOnUpdateChannel(_ item: String) -> Bool {
        guard let channel = firstCapturedValue(for: #"<sparkle:channel>\s*([^<]+?)\s*</sparkle:channel>"#, in: item) else {
            return false
        }
        return !channel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func parseSparkleItem(_ item: String) -> UpdateMetadata? {
        if isOnUpdateChannel(item) { return nil }
        let enclosure = enclosureTags(in: item).first
        let shortVersion =
            enclosure.flatMap { firstCapturedValue(for: #"sparkle:shortVersionString="([^"]+)""#, in: $0) } ??
            firstCapturedValue(for: #"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>"#, in: item)
        let build =
            enclosure.flatMap { firstCapturedValue(for: #"sparkle:version="([^"]+)""#, in: $0) } ??
            firstCapturedValue(for: #"<sparkle:version>([^<]+)</sparkle:version>"#, in: item)
        let marketing = shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let buildNumber = build?.trimmingCharacters(in: .whitespacesAndNewlines)
        // A build number on its own is not a marketing version. "2045" must
        // not be offered as "Update to 2045".
        guard !marketing.isEmpty || (buildNumber?.isEmpty == false) else { return nil }
        // A download that is not https is no link at all: the update still counts.
        let url = httpsURL(enclosure.flatMap { firstCapturedValue(for: #"url="([^"]+)""#, in: $0) })?.absoluteString
        return UpdateMetadata(version: marketing, url: url, build: buildNumber?.isEmpty == true ? nil : buildNumber)
    }

    private static func parseSparkleEnclosure(from tag: String) -> UpdateMetadata? {
        guard let url = firstCapturedValue(for: #"url="([^"]+)""#, in: tag) else { return nil }
        let shortVersion = firstCapturedValue(for: #"sparkle:shortVersionString="([^"]+)""#, in: tag)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let build = firstCapturedValue(for: #"sparkle:version="([^"]+)""#, in: tag)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !shortVersion.isEmpty || (build?.isEmpty == false) else { return nil }
        return UpdateMetadata(version: shortVersion, url: httpsURL(url)?.absoluteString,
                              build: build?.isEmpty == true ? nil : build)
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
    let minimumOsVersion: String?

    enum CodingKeys: String, CodingKey {
        case bundleID = "bundleId"
        case trackID = "trackId"
        case version
        case trackViewURL = "trackViewUrl"
        case minimumOsVersion
    }
}

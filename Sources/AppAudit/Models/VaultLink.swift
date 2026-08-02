import Foundation

/// Where the app name in the License Vault takes you. A vault entry often
/// outlives the app itself, and the reason you kept it — the key, the receipt,
/// the reinstall — usually lives on the maker's site. So the name is always a
/// way out to the web: the link you saved, else the one Sift guessed, else a
/// search, so a row never dead-ends into "go and google it".
enum VaultLink {
    enum Destination: Equatable {
        /// The link you confirmed on the app's Link cube.
        case saved(URL)
        /// Sift's auto-suggested link — good enough to follow, not confirmed.
        case suggested(URL)
        /// Nothing on record; hand the name to a web search.
        case search(URL)

        var url: URL {
            switch self {
            case .saved(let url), .suggested(let url), .search(let url): return url
            }
        }

        /// Drives the trailing glyph: a search reads as a lookup, a real link
        /// as a jump off to the web.
        var isSearch: Bool {
            if case .search = self { return true }
            return false
        }
    }

    static func destination(appURL: String?, suggestedAppURL: String?, appName: String) -> Destination {
        if let url = normalized(appURL) { return .saved(url) }
        if let url = normalized(suggestedAppURL) { return .suggested(url) }
        return .search(searchURL(for: appName))
    }

    static func help(for destination: Destination, appName: String) -> String {
        switch destination {
        case .saved(let url):
            return "Open \(url.host() ?? url.absoluteString)"
        case .suggested(let url):
            return "Open \(url.host() ?? url.absoluteString) — Sift's suggested link"
        case .search:
            return "No link saved — search the web for \(appName)"
        }
    }

    /// Records hold whatever you typed, so a bare host like "raycast.com" is
    /// normal. Without a scheme `URL(string:)` yields a relative URL that no
    /// browser will open, so assume https.
    private static func normalized(_ raw: String?) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil, url.host() != nil { return url }
        return URL(string: "https://\(trimmed)").flatMap { $0.host() == nil ? nil : $0 }
    }

    private static func searchURL(for appName: String) -> URL {
        let query = "\(appName) mac app"
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? appName
        return URL(string: "https://www.google.com/search?q=\(encoded)")
            ?? URL(string: "https://www.google.com")!
    }
}

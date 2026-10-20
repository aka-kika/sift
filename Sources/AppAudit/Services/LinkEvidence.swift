import Foundation

/// Extracts lightweight, factual evidence (page title + description) from raw
/// HTML, so the analysis prompt can ground "what is this app" in what the app's
/// own website says — instead of guessing from the domain name.
enum LinkEvidence {

    static func extract(fromHTML html: String) -> String? {
        let title = firstCapture(in: html, pattern: "<title[^>]*>\\s*([^<]{1,300}?)\\s*</title>")
        let description = firstCapture(in: html, pattern: "<meta[^>]+(?:name|property)=[\"'](?:og:)?description[\"'][^>]*content=[\"']([^\"']{1,500})[\"']")
            ?? firstCapture(in: html, pattern: "<meta[^>]+content=[\"']([^\"']{1,500})[\"'][^>]*(?:name|property)=[\"'](?:og:)?description[\"']")

        var parts: [String] = []
        if let title, !title.isEmpty { parts.append("Title: \(decodeEntities(title))") }
        if let description, !description.isEmpty { parts.append("Description: \(decodeEntities(description))") }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    // MARK: - What may be fetched

    /// The saved link as Sift may fetch it and name it in the prompt: http(s) on a
    /// public host, with the query, fragment and any user:password removed, since
    /// those can carry tokens. Nil for a link to this Mac or the local network:
    /// a router or dev server page must never end up in a cloud model's prompt.
    static func fetchableURL(from urlString: String) -> URL? {
        guard let url = URL(string: urlString), isAllowedTarget(url) else { return nil }
        return withoutQueryOrFragment(url)
    }

    /// `url` with the query, fragment and user:password dropped.
    static func withoutQueryOrFragment(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }

    /// http(s) to a public host. Checked on the link, on every redirect, and on
    /// the final response.
    static func isAllowedTarget(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(percentEncoded: false) else { return false }
        return isPublicHost(host)
    }

    /// False for localhost, local-network names, and IP literals that are
    /// loopback, private, link-local, unique-local or unspecified. Names are not
    /// resolved here, so a public name pointing at a private address still passes.
    static func isPublicHost(_ rawHost: String) -> Bool {
        var host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return false }

        if host.contains(":") {
            // IPv6 literal; one with a zone ("fe80::1%en0") is link-local by definition.
            guard !host.contains("%") else { return false }
            var address = in6_addr()
            guard inet_pton(AF_INET6, host, &address) == 1 else { return false }
            return isPublicIPv6(withUnsafeBytes(of: address) { Array($0) })
        }

        // inet_aton reads every IPv4 form the resolver does: "127.1", "0x7f000001", "2130706433".
        var v4 = in_addr()
        if inet_aton(host, &v4) != 0 {
            return isPublicIPv4(UInt32(bigEndian: v4.s_addr))
        }

        // A name with no dot ("nas", "router") is looked up on the local network.
        guard host.contains(".") else { return false }
        let localSuffixes = [".localhost", ".local", ".lan", ".internal", ".home.arpa"]
        return host != "localhost" && !localSuffixes.contains { host.hasSuffix($0) }
    }

    private static func isPublicIPv4(_ address: UInt32) -> Bool {
        let blocked: [(network: UInt32, prefix: UInt32)] = [
            (0x0000_0000, 8),   // 0.0.0.0/8, "this host"
            (0x0A00_0000, 8),   // 10/8
            (0x6440_0000, 10),  // 100.64/10, carrier NAT and Tailscale
            (0x7F00_0000, 8),   // 127/8, loopback
            (0xA9FE_0000, 16),  // 169.254/16, link-local
            (0xAC10_0000, 12),  // 172.16/12
            (0xC0A8_0000, 16),  // 192.168/16
            (0xE000_0000, 4),   // multicast
            (0xF000_0000, 4)    // reserved and broadcast
        ]
        return !blocked.contains { address >> (32 - $0.prefix) == $0.network >> (32 - $0.prefix) }
    }

    private static func isPublicIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }
        if bytes.allSatisfy({ $0 == 0 }) { return false }                            // ::
        if bytes[0..<15].allSatisfy({ $0 == 0 }) && bytes[15] == 1 { return false } // ::1
        if bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80 { return false }             // fe80::/10
        if bytes[0] & 0xFE == 0xFC { return false }                                 // fc00::/7
        if bytes[0] == 0xFF { return false }                                        // multicast

        // ::ffff:a.b.c.d and ::a.b.c.d carry an IPv4 address; judge that one.
        let mapped = bytes[0..<10].allSatisfy { $0 == 0 } && bytes[10] == 0xFF && bytes[11] == 0xFF
        let compatible = bytes[0..<12].allSatisfy { $0 == 0 }
        if mapped || compatible {
            let v4 = bytes[12..<16].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            return isPublicIPv4(v4)
        }
        return true
    }
}

/// Lets a redirect through only when it stays on a public http(s) host.
private final class LinkEvidenceRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let url = request.url, LinkEvidence.isAllowedTarget(url) else { return nil }
        return request
    }
}

/// Fetches and caches link evidence per URL for the lifetime of the app run, so
/// bulk re-analyzes do not refetch the same page.
actor LinkEvidenceService {
    private var cache: [String: String?] = [:]

    func evidence(for urlString: String?) async -> String? {
        // Older records may hold a bare host ("raycast.com") saved before links were normalized.
        guard let urlString = AppLinkInput.normalized(urlString) else { return nil }
        if let cached = cache[urlString] { return cached }

        guard let url = LinkEvidence.fetchableURL(from: urlString) else {
            cache[urlString] = nil as String?
            return nil
        }

        var request = URLRequest(url: url, timeoutInterval: 6)
        request.setValue("Mozilla/5.0 (Macintosh) Sift", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request, delegate: LinkEvidenceRedirectGuard())
            // A refused redirect comes back as the 3xx itself, so the 200 check drops it too.
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let finalURL = http.url, LinkEvidence.isAllowedTarget(finalURL) else {
                cache[urlString] = nil as String?
                return nil
            }
            let html = String(decoding: data.prefix(131_072), as: UTF8.self)
            let evidence = LinkEvidence.extract(fromHTML: html)
            cache[urlString] = evidence
            return evidence
        } catch {
            cache[urlString] = nil as String?
            return nil
        }
    }
}

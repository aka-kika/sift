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
}

/// Fetches and caches link evidence per URL for the lifetime of the app run, so
/// bulk re-analyzes do not refetch the same page.
actor LinkEvidenceService {
    private var cache: [String: String?] = [:]

    func evidence(for urlString: String?) async -> String? {
        guard let urlString = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty else { return nil }
        if let cached = cache[urlString] { return cached }

        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            cache[urlString] = nil as String?
            return nil
        }

        var request = URLRequest(url: url, timeoutInterval: 6)
        request.setValue("Mozilla/5.0 (Macintosh) Sift", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
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

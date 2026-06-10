import Foundation

/// Maps `LSApplicationCategoryType` raw values ("public.app-category.developer-tools")
/// to readable names ("Developer Tools"). Deterministic slug formatting — no lookup
/// table to maintain; unknown or missing values yield nil.
enum AppCategory {
    static func humanName(for raw: String?) -> String? {
        let prefix = "public.app-category."
        guard let raw, raw.hasPrefix(prefix) else { return nil }
        let slug = raw.dropFirst(prefix.count)
        guard !slug.isEmpty else { return nil }
        return slug.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

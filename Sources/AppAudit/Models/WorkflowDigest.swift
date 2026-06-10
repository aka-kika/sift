import Foundation

/// Deterministic, evidence-only summary of the user's installed apps, used as the
/// automatic workflow profile. Pure code — nothing here is AI-generated, so there
/// is nothing for a small model to hallucinate from.
enum WorkflowDigest {
    static func build(from apps: [AppInfo]) -> String {
        guard !apps.isEmpty else { return "" }

        var counts: [String: Int] = [:]
        var uncategorized = 0
        for app in apps {
            if let name = AppCategory.humanName(for: app.category) {
                counts[name, default: 0] += 1
            } else {
                uncategorized += 1
            }
        }
        let top = counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(5)
            .map { "\($0.key) (\($0.value))" }
        var categories = top.joined(separator: ", ")
        if uncategorized > 0 {
            categories += categories.isEmpty ? "uncategorized (\(uncategorized))" : ", other (\(uncategorized))"
        }

        let recent = apps
            .compactMap { app in app.lastUsedDate.map { (app.name, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(8)
            .map(\.0)
        let running = apps.filter(\.isRunning).map(\.name).sorted().prefix(8)

        var parts = ["Installed apps: \(apps.count). Categories: \(categories)."]
        if !recent.isEmpty { parts.append("Most recently used: \(recent.joined(separator: ", ")).") }
        if !running.isEmpty { parts.append("Open right now: \(running.joined(separator: ", ")).") }
        return parts.joined(separator: " ")
    }
}

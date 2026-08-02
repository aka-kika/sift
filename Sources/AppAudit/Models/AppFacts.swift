import Foundation

/// The quiet line of facts under the analysis. Everything here is something
/// Sift already knows and the AI prose does not say: how much room the app
/// takes, when you last opened it, where it came from, what it costs you.
///
/// A fact you don't have is left out rather than shown empty — an "Unknown"
/// cell is noise, and the row should read as a short sentence of numbers.
struct AppFact: Identifiable, Equatable {
    let label: String
    let value: String
    var id: String { label }
}

enum AppFacts {
    /// Four cells at most, so the row always fits one line. Cost is left out
    /// on purpose — the License cube already tells that story in colour.
    static func build(sizeBytes: Int64?,
                      lastUsed: Date?,
                      now: Date,
                      installSource: String,
                      analyzedAt: Date?) -> [AppFact] {
        var facts: [AppFact] = []

        if let sizeBytes, sizeBytes > 0 {
            facts.append(AppFact(label: "On disk", value: sizeText(sizeBytes)))
        }
        facts.append(AppFact(label: "Last used", value: lastUsedText(lastUsed, now: now)))
        facts.append(AppFact(label: "Source", value: sourceText(installSource)))
        if let analyzedAt {
            facts.append(AppFact(label: "Analyzed", value: relative(analyzedAt, now: now)))
        }
        return facts
    }

    static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// "Never" is the honest answer for an app macOS has no record of opening,
    /// and it is the most useful cell on the row for an audit tool.
    /// Day comparisons run against the passed `now`, not the system clock —
    /// `isDateInToday` would quietly answer for a different day than the rest
    /// of the row is measured from.
    static func lastUsedText(_ date: Date?, now: Date) -> String {
        guard let date else { return "Never" }
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return relative(date, now: now)
    }

    /// `AppInfo.installSourceLabel` speaks in update-mechanism terms; "Other"
    /// means nothing to a reader, so name what actually happened.
    static func sourceText(_ label: String) -> String {
        label == "Other" ? "Direct download" : label
    }

    private static func relative(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

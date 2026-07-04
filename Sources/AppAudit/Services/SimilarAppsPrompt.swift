import Foundation

/// Builds and parses the "find similar apps" request. The model is only ever
/// shown a numbered list of the user's OWN installed apps and asked to pick
/// from it — it can never surface an app the user does not have, so the result
/// is grounded and free of invented apps or dead links.
enum SimilarAppsPrompt {
    struct Candidate {
        let index: Int
        let name: String
        let category: String
        let explanation: String
    }

    struct Pick {
        let index: Int
        let reason: String
    }

    static func build(targetName: String,
                      targetCategory: String,
                      targetExplanation: String,
                      candidates: [Candidate]) -> String {
        let targetLine = line(name: targetName, category: targetCategory, explanation: targetExplanation)
        let list = candidates
            .map { "\($0.index). " + line(name: $0.name, category: $0.category, explanation: $0.explanation) }
            .joined(separator: "\n")

        return """
        From the user's OWN installed apps, find which ones overlap in function with a target app — apps they might treat as alternatives or that do a similar job.

        Rules:
        - Choose ONLY from the numbered list below. Never name an app that is not in the list.
        - Order by how strongly they overlap, most similar first.
        - Return up to 4. If fewer than 4 genuinely overlap, return fewer. If none overlap, reply with exactly: NONE
        - One line per pick: the app's number, a colon, then a reason of at most 8 words.

        Target app:
        \(targetLine)

        The user's other installed apps:
        \(list)

        Respond with only the lines, for example:
        5: Same dual-pane file transfer workflow
        12: Also an AI-assisted code editor
        """
    }

    /// Parse the reply into (index, reason) pairs, keeping only indices that
    /// map to a real candidate. Non-numeric or out-of-range lines are dropped,
    /// so an invented pick cannot leak through.
    static func parse(_ response: String, validIndices: Set<Int>) -> [Pick] {
        var picks: [Pick] = []
        var seen: Set<Int> = []
        for rawLine in response.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Take the leading run of digits as the index.
            let digits = trimmed.prefix { $0.isNumber }
            guard let index = Int(digits), validIndices.contains(index), !seen.contains(index) else { continue }
            seen.insert(index)
            let rest = trimmed.dropFirst(digits.count)
            let reason = rest
                .drop { $0 == ":" || $0 == ")" || $0 == "." || $0 == " " || $0 == "-" }
                .trimmingCharacters(in: .whitespaces)
            picks.append(Pick(index: index, reason: reason))
        }
        return picks
    }

    private static func line(name: String, category: String, explanation: String) -> String {
        let cat = category.isEmpty ? "" : " (\(category))"
        let expl = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = expl.count > 120 ? String(expl.prefix(120)) + "…" : expl
        return clipped.isEmpty ? "\(name)\(cat)" : "\(name)\(cat): \(clipped)"
    }
}

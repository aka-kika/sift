import Foundation

/// Compares version strings the way a person reads them: `2.0.0` equals `2.0`,
/// `1.2.3-beta` is older than `1.2.3`, and a leading `v` means nothing.
///
/// The token approach (numbers against numbers, a missing component counts as
/// zero, words rank below numbers) follows DuoUpdater's `VersionComparator`
/// (https://github.com/jizhi0v0/duo-updater, MIT License © jizhi0v0).
enum VersionComparator {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = tokenize(lhs)
        let b = tokenize(rhs)
        for i in 0..<max(a.count, b.count) {
            let l = i < a.count ? a[i] : .number("0")
            let r = i < b.count ? b[i] : .number("0")
            let result = l.compared(to: r)
            if result != .orderedSame { return result }
        }
        return .orderedSame
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    /// The first number in the version: `4` for `v4.7.3`.
    static func majorComponent(_ version: String) -> Int? {
        for token in tokenize(version) {
            if case let .number(digits) = token { return Int(digits) }
        }
        return nil
    }

    /// True for `1.9 → 2.0`. Calendar versions (`2025.3 → 2026.1`) are not a
    /// major upgrade in the licensing sense — the year just rolled over.
    static func isMajorUpgrade(from current: String, to candidate: String) -> Bool {
        guard let a = majorComponent(current), let b = majorComponent(candidate) else { return false }
        if (2000...2099).contains(a) && (2000...2099).contains(b) { return false }
        return b > a
    }

    private enum Token {
        case number(String)
        case text(String)

        func compared(to other: Token) -> ComparisonResult {
            switch (self, other) {
            case let (.number(a), .number(b)):
                // Digit strings, not Int: build numbers overflow.
                let x = a.drop { $0 == "0" }
                let y = b.drop { $0 == "0" }
                if x.count != y.count { return x.count < y.count ? .orderedAscending : .orderedDescending }
                if x == y { return .orderedSame }
                return x < y ? .orderedAscending : .orderedDescending
            case let (.text(a), .text(b)):
                return a.caseInsensitiveCompare(b)
            case (.number, .text):
                return .orderedDescending
            case (.text, .number):
                return .orderedAscending
            }
        }
    }

    private static func tokenize(_ rawVersion: String) -> [Token] {
        var version = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = version.first, first == "v" || first == "V",
           version.dropFirst().first?.isNumber == true {
            version.removeFirst()
        }

        var tokens: [Token] = []
        var current = ""
        var currentIsDigit: Bool?
        func flush() {
            guard !current.isEmpty else { return }
            tokens.append(currentIsDigit == true ? .number(current) : .text(current))
            current = ""
        }
        for character in version {
            if ".-_+ ()".contains(character) {
                flush()
                currentIsDigit = nil
                continue
            }
            let isDigit = character.isASCII && character.isNumber
            if let previous = currentIsDigit, previous != isDigit { flush() }
            current.append(character)
            currentIsDigit = isDigit
        }
        flush()
        return tokens
    }
}

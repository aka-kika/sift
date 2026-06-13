import Foundation

/// How often a subscription renews. Stored on `AppRecord` as the rawValue string.
enum BillingCycle: String, CaseIterable, Identifiable {
    case monthly
    case yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    /// Short suffix for the detail row, e.g. "€9.99 / mo".
    var abbreviation: String {
        switch self {
        case .monthly: return "mo"
        case .yearly: return "yr"
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .monthly: return .month
        case .yearly: return .year
        }
    }
}

/// Pure subscription date/billing math. No UI, no I/O — every function takes
/// `now`/`calendar` so it is deterministic and unit-testable.
enum SubscriptionMath {

    /// If `stored` is before today, advance it by `cycle` until it lands on or
    /// after today; otherwise return it unchanged. Display-only — callers do not
    /// persist the result.
    static func nextRenewal(from stored: Date, cycle: BillingCycle, now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        var date = stored
        var guardCount = 0
        while calendar.startOfDay(for: date) < today, guardCount < 1200 {
            guard let advanced = calendar.date(byAdding: cycle.calendarComponent, value: 1, to: date) else { break }
            date = advanced
            guardCount += 1
        }
        return date
    }

    /// Whole calendar days from today to `renewal` (negative if in the past).
    static func daysUntil(_ renewal: Date, now: Date, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: renewal)
        return calendar.dateComponents([.day], from: today, to: target).day ?? 0
    }

    static func countdownText(daysUntil days: Int) -> String {
        switch days {
        case ..<0: return "overdue"
        case 0: return "renews today"
        case 1: return "renews tomorrow"
        default: return "renews in \(days) days"
        }
    }

    /// True when a renewal is close enough to highlight (within a week).
    static func isNear(daysUntil days: Int) -> Bool {
        days >= 0 && days <= 7
    }

    /// `yyyy-MM-dd` in the given calendar's timezone, for CSV export.
    static func isoDate(_ date: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

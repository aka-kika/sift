# Subscription Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Sift's subscription flag into structured data — price, currency, cycle, next renewal date, and billing email — surfaced as a 💳 detail-panel row with a live "renews in X days" countdown, plus CSV export.

**Architecture:** A new pure `Subscription.swift` holds the `BillingCycle` enum and `SubscriptionMath` (renewal roll-forward + countdown + ISO date), fully unit-tested. `AppRecord` gains five optional fields (non-secret, SwiftData). `AppDetailView` gets a `subscriptionSection` row and `SubscriptionSheet` editor mirroring the existing License Key row/sheet (hover-reveal, **no Touch ID**). `AppListViewModel.exportCSV()` expands its subscription column into a small group. Renewal roll-forward is **display-only** — the stored date is never mutated on render.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing (`@Test`/`@Suite`/`#expect`). All builds/tests run with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (standalone CLT is broken on macOS 27).

---

## Environment note

Every `swift` command in this plan MUST be prefixed:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```

Run it once per shell. SourceKit/IDE diagnostics on this machine are stale-index noise — only real `swift build` / `swift test` output counts.

## File Structure

- **Create** `Sources/AppAudit/Models/Subscription.swift` — `BillingCycle` enum + `SubscriptionMath` enum (pure logic: `nextRenewal`, `daysUntil`, `countdownText`, `isNear`, `isoDate`). One responsibility: subscription date/billing math, no UI, no I/O. Keeps logic out of the already-large `AppDetailView`.
- **Modify** `Sources/AppAudit/Models/AppRecord.swift` — five new optional fields + initializer defaults.
- **Modify** `Sources/AppAudit/Views/AppDetailView.swift` — new `subscriptionSection` row, `SubscriptionSheet` view + `SubscriptionSheetAction` enum, draft/hover `@State`, sheet wiring, insertion into `utilitySection`, `beginEditingSubscription()` / `clearSubscription()` / `formattedPrice(_:currencyCode:)` helpers.
- **Modify** `Sources/AppAudit/ViewModels/AppListViewModel.swift` — expand `exportCSV()` header + rows.
- **Modify** `Tests/AppAuditTests/AppAuditTests.swift` — new `@Suite` blocks for `SubscriptionMath` and `AppRecord` subscription defaults. (This project keeps all tests in one file across multiple suites.)

## Testing philosophy for this plan

This codebase unit-tests **pure logic** and verifies **SwiftUI views by build + manual check** (there is no ViewInspector). Accordingly:
- Task 1 (the math) and Task 2 (model defaults) are TDD with real `#expect` assertions.
- Tasks 3–4 (sheet + row) are verified by `swift build` + a manual checklist — no fake view unit tests.
- Task 5 (CSV) reuses the tested `isoDate` helper; column wiring is build-verified.

---

### Task 1: BillingCycle + SubscriptionMath (pure logic, TDD)

**Files:**
- Create: `Sources/AppAudit/Models/Subscription.swift`
- Test: `Tests/AppAuditTests/AppAuditTests.swift` (append a new suite)

- [ ] **Step 1: Write the failing tests**

Append this suite to the end of `Tests/AppAuditTests/AppAuditTests.swift`:

```swift
@Suite("Subscription Math")
struct SubscriptionMathTests {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test("Future renewal is returned unchanged")
    func futureUnchanged() {
        let stored = day(2026, 7, 1)
        let next = SubscriptionMath.nextRenewal(from: stored, cycle: .monthly, now: day(2026, 6, 13), calendar: utc)
        #expect(next == stored)
    }

    @Test("Today's renewal is returned unchanged")
    func todayUnchanged() {
        let stored = day(2026, 6, 13)
        let next = SubscriptionMath.nextRenewal(from: stored, cycle: .monthly, now: day(2026, 6, 13), calendar: utc)
        #expect(next == stored)
    }

    @Test("Past monthly rolls forward to the first future month")
    func pastMonthlyRolls() {
        let next = SubscriptionMath.nextRenewal(from: day(2026, 1, 10), cycle: .monthly, now: day(2026, 6, 13), calendar: utc)
        #expect(next == day(2026, 7, 10))
    }

    @Test("Past yearly rolls forward to the first future year")
    func pastYearlyRolls() {
        let next = SubscriptionMath.nextRenewal(from: day(2024, 3, 1), cycle: .yearly, now: day(2026, 6, 13), calendar: utc)
        #expect(next == day(2027, 3, 1))
    }

    @Test("daysUntil counts calendar days")
    func daysUntil() {
        #expect(SubscriptionMath.daysUntil(day(2026, 6, 20), now: day(2026, 6, 13), calendar: utc) == 7)
    }

    @Test("Countdown copy")
    func countdownCopy() {
        #expect(SubscriptionMath.countdownText(daysUntil: 0) == "renews today")
        #expect(SubscriptionMath.countdownText(daysUntil: 1) == "renews tomorrow")
        #expect(SubscriptionMath.countdownText(daysUntil: 5) == "renews in 5 days")
        #expect(SubscriptionMath.countdownText(daysUntil: -1) == "overdue")
    }

    @Test("Near threshold is 0...7 inclusive")
    func nearThreshold() {
        #expect(SubscriptionMath.isNear(daysUntil: 0))
        #expect(SubscriptionMath.isNear(daysUntil: 7))
        #expect(!SubscriptionMath.isNear(daysUntil: 8))
        #expect(!SubscriptionMath.isNear(daysUntil: -1))
    }

    @Test("isoDate formats yyyy-MM-dd")
    func iso() {
        #expect(SubscriptionMath.isoDate(day(2026, 6, 13), calendar: utc) == "2026-06-13")
    }

    @Test("BillingCycle round-trips its rawValue")
    func cycleRawValue() {
        #expect(BillingCycle(rawValue: "monthly") == .monthly)
        #expect(BillingCycle(rawValue: "yearly") == .yearly)
        #expect(BillingCycle(rawValue: "garbage") == nil)
        #expect(BillingCycle.monthly.abbreviation == "mo")
        #expect(BillingCycle.yearly.abbreviation == "yr")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -5`
Expected: FAIL — compile error, `cannot find 'SubscriptionMath' in scope` / `cannot find 'BillingCycle'`.

- [ ] **Step 3: Write the implementation**

Create `Sources/AppAudit/Models/Subscription.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`
Expected: PASS — test count rises from 57 to 65 (8 new tests), all green.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Models/Subscription.swift Tests/AppAuditTests/AppAuditTests.swift
git commit -m "Add BillingCycle + SubscriptionMath (renewal roll-forward, countdown)"
```

---

### Task 2: AppRecord subscription fields

**Files:**
- Modify: `Sources/AppAudit/Models/AppRecord.swift`
- Test: `Tests/AppAuditTests/AppAuditTests.swift` (append a suite)

- [ ] **Step 1: Write the failing test**

Append to `Tests/AppAuditTests/AppAuditTests.swift`:

```swift
@Suite("AppRecord Subscription Fields")
struct AppRecordSubscriptionTests {
    @Test("A new record has empty subscription fields")
    func defaults() {
        let r = AppRecord(bundleID: "com.x", appName: "X", explanation: "",
                          relevanceScore: 0, relevanceReason: "", bestUse: "", ollamaModel: "")
        #expect(r.hasSubscription == false)
        #expect(r.subscriptionPrice == nil)
        #expect(r.subscriptionCurrency == nil)
        #expect(r.subscriptionCycle == nil)
        #expect(r.subscriptionRenewalDate == nil)
        #expect(r.subscriptionEmail == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -5`
Expected: FAIL — `value of type 'AppRecord' has no member 'subscriptionPrice'`.

- [ ] **Step 3: Add the fields**

In `Sources/AppAudit/Models/AppRecord.swift`, after the existing `var licenseEmail: String? = nil` (line 20), add:

```swift
    var subscriptionPrice: Double? = nil
    var subscriptionCurrency: String? = nil
    var subscriptionCycle: String? = nil
    var subscriptionRenewalDate: Date? = nil
    var subscriptionEmail: String? = nil
```

Then in the `init(...)`, after the existing `self.licenseEmail = nil` line, add:

```swift
        self.subscriptionPrice = nil
        self.subscriptionCurrency = nil
        self.subscriptionCycle = nil
        self.subscriptionRenewalDate = nil
        self.subscriptionEmail = nil
```

(All optional with `= nil` defaults, so existing SwiftData stores migrate automatically — no schema version bump needed.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`
Expected: PASS — 66 tests green.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Models/AppRecord.swift Tests/AppAuditTests/AppAuditTests.swift
git commit -m "AppRecord: add subscription price/currency/cycle/renewal/email fields"
```

---

### Task 3: SubscriptionSheet editor + state + wiring

**Files:**
- Modify: `Sources/AppAudit/Views/AppDetailView.swift`

- [ ] **Step 1: Add draft + hover state**

In `AppDetailView`, after the existing `@State private var urlHovered = false` (line 26), add:

```swift
    @State private var subHovered = false
    @State private var editingSubscription = false
    @State private var draftSubPrice = ""
    @State private var draftSubCurrency = ""
    @State private var draftSubCycle: BillingCycle = .monthly
    @State private var draftSubRenewal = Date()
    @State private var draftSubEmail = ""
```

- [ ] **Step 2: Add the `SubscriptionSheet` view + action enum**

At the end of `AppDetailView.swift` (after `DetailLicenseKeySheet`, before/after the other sheet structs — file scope, not inside `AppDetailView`), add:

```swift
// MARK: - Subscription Sheet

enum SubscriptionSheetAction { case cancel, save, clear }

struct SubscriptionSheet: View {
    let appName: String
    @Binding var price: String
    @Binding var currency: String
    @Binding var cycle: BillingCycle
    @Binding var renewal: Date
    @Binding var email: String
    let onDone: (SubscriptionSheetAction) -> Void

    @FocusState private var focused: Bool

    private static let currencies = ["USD", "EUR", "GBP", "ILS", "CAD", "AUD", "JPY", "CHF"]

    /// Always include the record's current currency even if it is not in the
    /// short list, so the picker can display it without losing the value.
    static func currencyOptions(including current: String) -> [String] {
        if current.isEmpty || currencies.contains(current) { return currencies }
        return [current] + currencies
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Subscription for \(appName)")
                .font(.headline)
            Text("Track what you pay and when it renews next.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Amount", text: $price)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
                    .focused($focused)
                Picker("", selection: $currency) {
                    ForEach(Self.currencyOptions(including: currency), id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 110)
            }

            Picker("Billing", selection: $cycle) {
                ForEach(BillingCycle.allCases) { c in
                    Text(c.label).tag(c)
                }
            }
            .pickerStyle(.segmented)

            DatePicker("Next renewal", selection: $renewal, displayedComponents: .date)

            TextField("Billing email (optional)", text: $email)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { onDone(.cancel) }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Clear") { onDone(.clear) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Button("Save") { onDone(.save) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { focused = true }
    }
}
```

- [ ] **Step 3: Wire the sheet + helpers**

In `AppDetailView`, add the sheet after the existing `.sheet(isPresented: $editingURL) { ... }` block (around line 83+). Add this modifier:

```swift
        .sheet(isPresented: $editingSubscription) {
            SubscriptionSheet(
                appName: app.name,
                price: $draftSubPrice,
                currency: $draftSubCurrency,
                cycle: $draftSubCycle,
                renewal: $draftSubRenewal,
                email: $draftSubEmail
            ) { action in
                switch action {
                case .cancel:
                    break
                case .save:
                    let ensured = ensureRecord()
                    ensured.subscriptionPrice = Double(draftSubPrice.replacingOccurrences(of: ",", with: "."))
                    ensured.subscriptionCurrency = draftSubCurrency.isEmpty ? nil : draftSubCurrency
                    ensured.subscriptionCycle = draftSubCycle.rawValue
                    ensured.subscriptionRenewalDate = draftSubRenewal
                    let email = draftSubEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                    ensured.subscriptionEmail = email.isEmpty ? nil : email
                    ensured.hasSubscription = true
                    if ensured.iconPNG == nil { ensured.iconPNG = app.icon?.pngData() }
                    viewModel.setSubscription(bundleID: app.bundleID, value: true)
                    saveRecord()
                case .clear:
                    clearSubscription()
                }
                editingSubscription = false
            }
        }
```

Then add these helpers next to `ensureRecord()` / `saveRecord()` (around line 685):

```swift
    private func beginEditingSubscription() {
        draftSubPrice = record?.subscriptionPrice.map { String(format: "%.2f", $0) } ?? ""
        draftSubCurrency = record?.subscriptionCurrency
            ?? (Locale.current.currency?.identifier ?? "USD")
        draftSubCycle = BillingCycle(rawValue: record?.subscriptionCycle ?? "") ?? .monthly
        draftSubRenewal = record?.subscriptionRenewalDate ?? Date()
        draftSubEmail = record?.subscriptionEmail
            ?? record?.licenseEmail
            ?? UserDefaults.standard.string(forKey: "defaultLicenseEmail") ?? ""
        editingSubscription = true
    }

    private func clearSubscription() {
        let ensured = ensureRecord()
        ensured.subscriptionPrice = nil
        ensured.subscriptionCurrency = nil
        ensured.subscriptionCycle = nil
        ensured.subscriptionRenewalDate = nil
        ensured.subscriptionEmail = nil
        ensured.hasSubscription = false
        viewModel.setSubscription(bundleID: app.bundleID, value: false)
        saveRecord()
    }

    private func formattedPrice(_ amount: Double, currencyCode: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: amount))
            ?? String(format: "%.2f %@", amount, currencyCode)
    }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build 2>&1 | tail -5`
Expected: `Compiling` … `Build complete!` with no errors. (The sheet is not shown anywhere yet — that's Task 4 — but everything must compile.)

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Views/AppDetailView.swift
git commit -m "AppDetailView: add SubscriptionSheet editor, draft state, save/clear helpers"
```

---

### Task 4: Subscription row in the detail panel

**Files:**
- Modify: `Sources/AppAudit/Views/AppDetailView.swift`

- [ ] **Step 1: Add the `subscriptionSection` row + detail-line helper**

In `AppDetailView`, add after the `licenseKeySection` computed property (ends ~line 597, before `urlSection`):

```swift
    private var subscriptionSection: some View {
        HStack(spacing: 8) {
            utilityChip("creditcard", tint: .green)
            Text("Subscription")
                .font(.subheadline.weight(.medium))
            if record?.hasSubscription == true, let renewal = record?.subscriptionRenewalDate {
                subscriptionDetailLine(renewal: renewal)
            } else if record?.hasSubscription == true {
                Text("Marked · add details")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("None yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Group {
                Button {
                    beginEditingSubscription()
                } label: {
                    Image(systemName: record?.hasSubscription == true ? "pencil" : "plus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(record?.hasSubscription == true ? "Edit subscription" : "Add subscription")

                if record?.hasSubscription == true {
                    Button(role: .destructive) {
                        clearSubscription()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove subscription")
                }
            }
            .opacity(subHovered ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                subHovered = hovering
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The price + countdown (+ optional email) shown when a subscription has a
    /// renewal date. A plain function (not a ViewBuilder property) so it can use
    /// `let` bindings for the math before returning the view.
    private func subscriptionDetailLine(renewal: Date) -> some View {
        let cycle = BillingCycle(rawValue: record?.subscriptionCycle ?? "") ?? .monthly
        let next = SubscriptionMath.nextRenewal(from: renewal, cycle: cycle, now: Date())
        let days = SubscriptionMath.daysUntil(next, now: Date())
        let countdownStyle: AnyShapeStyle = SubscriptionMath.isNear(daysUntil: days)
            ? AnyShapeStyle(.orange)
            : AnyShapeStyle(.secondary)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let price = record?.subscriptionPrice {
                    Text(formattedPrice(price, currencyCode: record?.subscriptionCurrency ?? "USD"))
                        .font(.body)
                    Text("/ \(cycle.abbreviation)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("· " + SubscriptionMath.countdownText(daysUntil: days))
                    .font(.caption)
                    .foregroundStyle(countdownStyle)
            }
            if let email = record?.subscriptionEmail, !email.isEmpty {
                Text(email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
```

- [ ] **Step 2: Insert the row into `utilitySection`**

In `utilitySection` (line ~420), insert the subscription row + a divider between `licenseKeySection` and `urlSection`. Change:

```swift
            licenseKeySection
            UtilityRowDivider()
            urlSection
```

to:

```swift
            licenseKeySection
            UtilityRowDivider()
            subscriptionSection
            UtilityRowDivider()
            urlSection
```

- [ ] **Step 3: Build to verify it compiles**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build 2>&1 | tail -5`
Expected: `Build complete!` with no errors. Common pitfall: the `AnyShapeStyle` ternary is required because `.orange` (Color) and `.secondary` (HierarchicalShapeStyle) are different types — do not simplify it to a bare `? .orange : .secondary`.

- [ ] **Step 4: Manual visual verification in Sift2**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash Scripts/build_sift2.sh 2>&1 | tail -1`
Then open Sift2 and check, on any app:
- A **Subscription** row appears below License Key with a green 💳 chip, showing `None yet`.
- Hover reveals a `+`; clicking opens the sheet (amount + currency, Monthly/Yearly segmented, date picker, email, Cancel/Clear/Save).
- Save a price (e.g. 9.99 EUR, Monthly, renewal ~10 days out, an email). Row shows `€9.99 / mo · renews in 10 days` + the email; chip/buttons reveal on hover; the `+` became a pencil and a trash appeared.
- Set a renewal date within 7 days → the countdown turns **amber**.
- Set a renewal date in the past → it shows a future "renews in N days" (roll-forward), not a negative/overdue number.
- Trash clears the row back to `None yet`.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Views/AppDetailView.swift
git commit -m "AppDetailView: add Subscription row with price + renewal countdown"
```

---

### Task 5: CSV export columns

**Files:**
- Modify: `Sources/AppAudit/ViewModels/AppListViewModel.swift`

- [ ] **Step 1: Expand the header**

In `exportCSV()` (line ~484), change the header array. Replace:

```swift
            "Explanation", "Update Status", "My App", "Favorite", "Subscription", "Notes"
```

with:

```swift
            "Explanation", "Update Status", "My App", "Favorite",
            "Subscription", "Sub Price", "Sub Cycle", "Sub Renewal", "Notes"
```

- [ ] **Step 2: Expand the row**

In the same method's row closure, replace:

```swift
                app.isSubscribed ? "yes" : "no",
                record?.notes ?? ""
```

with:

```swift
                app.isSubscribed ? "yes" : "no",
                record?.subscriptionPrice.map { String(format: "%.2f", $0) } ?? "",
                record?.subscriptionCycle ?? "",
                record?.subscriptionRenewalDate.map { SubscriptionMath.isoDate($0) } ?? "",
                record?.notes ?? ""
```

(`record` is already loaded at the top of this closure as `let record = cacheService?.load(...)`. The billing email is intentionally omitted, matching how license emails stay out of CSV.)

- [ ] **Step 3: Build to verify it compiles**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build 2>&1 | tail -3`
Expected: `Build complete!` — header and row arrays must still have equal counts (the `CSVExporter` does not enforce this, so a mismatch would silently misalign columns; visually confirm both gained exactly the same shape: one column became four, inserted at the same position).

- [ ] **Step 4: Manual verification**

In Sift2 (or main app), with one app carrying a saved subscription, run an export (the existing CSV export action). Open the file and confirm `Sub Price`, `Sub Cycle`, `Sub Renewal` columns sit between `Subscription` and `Notes`, populated for the subscribed app and blank for others, with no email column.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/ViewModels/AppListViewModel.swift
git commit -m "CSV: export subscription price, cycle, and renewal date"
```

---

### Task 6: Full verification

- [ ] **Step 1: Run the whole suite**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`
Expected: PASS — 66 tests (57 original + 8 SubscriptionMath + 1 AppRecord defaults), all green.

- [ ] **Step 2: Build Sift2 and do the end-to-end manual pass**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash Scripts/build_sift2.sh 2>&1 | tail -1`
Walk the Task 4 Step 4 checklist once more on a real app, plus: quit and relaunch Sift2 and confirm the saved subscription persists (SwiftData round-trip), and that an app marked via the context menu "Mark as Subscription" (no details) shows `Marked · add details` and opens the sheet cleanly.

- [ ] **Step 3: Final commit if any fixups were needed**

```bash
git add -A
git commit -m "Subscription tracking: verification fixups" || echo "nothing to commit"
```

This feature does **not** bump the app version or cut a release — that is a separate decision after you've lived with it in Sift2 (it would fold into the next tagged release alongside anything else queued).

---

## Self-Review

**Spec coverage:**
- Data model (6 fields incl. existing `hasSubscription`) → Task 2. ✓
- Subscription row below License Key, hover-reveal, no Touch ID → Task 4. ✓
- 💳 green chip, None yet / Marked / filled states → Task 4. ✓
- Price + currency picker, Monthly/Yearly, renewal DatePicker, optional email → Task 3 (`SubscriptionSheet`). ✓
- Email pre-fills from licenseEmail / default → Task 3 (`beginEditingSubscription`). ✓
- Renewal roll-forward, pure + tested, display-only → Task 1 + Task 4. ✓
- Countdown "renews in X days", amber within 7 → Task 1 (`countdownText`/`isNear`) + Task 4. ✓
- CSV: Subscription + Sub Price + Sub Cycle + Sub Renewal, email excluded → Task 5. ✓
- Context-menu quick toggle preserved → unchanged; row handles the `Marked` state (Task 4). ✓
- Non-goals (notifications, spend summary, Touch ID) → none implemented. ✓

**Placeholder scan:** No TBD/TODO; all steps contain real code and exact commands. ✓

**Type consistency:** `BillingCycle` (rawValue `monthly`/`yearly`, `abbreviation`, `label`, `calendarComponent`, `allCases`, `Identifiable`) and `SubscriptionMath` (`nextRenewal`, `daysUntil`, `countdownText`, `isNear`, `isoDate`) are used identically across Tasks 1, 4, 5. `SubscriptionSheetAction` (`cancel`/`save`/`clear`) matches between the view (Task 3 Step 2) and the wiring switch (Task 3 Step 3). Draft state names (`draftSubPrice`/`Currency`/`Cycle`/`Renewal`/`Email`, `editingSubscription`, `subHovered`) are consistent across Tasks 3–4. ✓

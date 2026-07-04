# Utility Cards + Pricing Semantics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the app detail view's four stacked utility rows with a 2×2 card grid driven by new pricing facts (Free app marker, license type) and pure gray-out rules.

**Architecture:** Pure logic first (`LicenseType`, `UtilityCardRules`, `PricingMarks` — all unit-tested), then the license sheet gains a type picker, then the notes editor moves from inline expander to a sheet, and finally the stacked rows become cards. The existing sheets (`DetailLicenseKeySheet`, `SubscriptionSheet`, `EditURLSheet`) are reused as-is or minimally extended; the notes re-analysis session logic is preserved unchanged.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData, Swift Testing (`@Suite`/`@Test`/`#expect`), macOS 14+.

**Spec:** `docs/superpowers/specs/2026-07-04-utility-cards-pricing-design.md`

## Global Constraints

- Product is **Sift**; sources live under `Sources/AppAudit/` and identifiers are never renamed.
- Run tests with `swift test` from the repo root. All existing tests must stay green after every task (suite is 81 tests before Task 1; each task adds its own).
- Tests are appended to the single `Tests/AppAuditTests/AppAuditTests.swift`, matching the existing `@Suite`/`@Test`/`#expect` style.
- New `AppRecord` fields must have defaults (`isFreeApp: Bool = false`, `licenseType: String? = nil`) so the SwiftData store migrates lightweight — no schema versioning.
- Graying never deletes data: stored keys, subscription details, and license type survive disable/enable round-trips.
- Gray-out rules (verbatim from the spec): license card disabled when `isMyApp || isFreeApp`; subscription card disabled when `isMyApp || isFreeApp || licenseType ∈ {lifetime, one-time}`. Hint priority: "Your app" → "Free app" → "<Type> license".
- The notes session/re-analysis behavior (`notesSessionBundleID`, `endNotesSession`, `reanalyzeAfterNotesChange`) keeps working exactly as today — only the presentation moves into a sheet.
- CSV export unchanged. Scoring/ranking unchanged.

## File Structure

- Create: `Sources/AppAudit/Models/LicenseType.swift` — the license-type enum.
- Create: `Sources/AppAudit/Models/UtilityCardRules.swift` — pure disable rules + `PricingMarks` mutual exclusion.
- Modify: `Sources/AppAudit/Models/AppRecord.swift` — two new fields.
- Modify: `Sources/AppAudit/Views/AppDetailView.swift` — license sheet picker, notes sheet, card grid.
- Modify: `FEATURES.md`, `README.md` — one section / one line.
- Test: `Tests/AppAuditTests/AppAuditTests.swift`.

---

### Task 1: LicenseType enum + AppRecord pricing fields

**Files:**
- Create: `Sources/AppAudit/Models/LicenseType.swift`
- Modify: `Sources/AppAudit/Models/AppRecord.swift` (fields after `isPaidApp` at line 26; init assignments after `self.isPaidApp = false` at line 59)
- Test: `Tests/AppAuditTests/AppAuditTests.swift` (append)

**Interfaces:**
- Produces: `LicenseType: String, CaseIterable, Identifiable` with cases `.lifetime`, `.oneTime` (raw `"one-time"`), `.annual`, `.other`; `displayName: String`; `coversForever: Bool` (true for lifetime/oneTime). `AppRecord.isFreeApp: Bool` (default false), `AppRecord.licenseType: String?` (default nil).

- [ ] **Step 1: Write the failing tests**

Append to `Tests/AppAuditTests/AppAuditTests.swift`:

```swift
@Suite("License Type")
struct LicenseTypeTests {
    @Test("Raw values round-trip")
    func rawValues() {
        #expect(LicenseType(rawValue: "lifetime") == .lifetime)
        #expect(LicenseType(rawValue: "one-time") == .oneTime)
        #expect(LicenseType(rawValue: "annual") == .annual)
        #expect(LicenseType(rawValue: "other") == .other)
        #expect(LicenseType(rawValue: "bogus") == nil)
    }

    @Test("Lifetime and one-time cover the app forever; annual and other do not")
    func coversForever() {
        #expect(LicenseType.lifetime.coversForever)
        #expect(LicenseType.oneTime.coversForever)
        #expect(!LicenseType.annual.coversForever)
        #expect(!LicenseType.other.coversForever)
    }

    @Test("Display names are human-readable")
    func displayNames() {
        #expect(LicenseType.lifetime.displayName == "Lifetime")
        #expect(LicenseType.oneTime.displayName == "One-time")
        #expect(LicenseType.annual.displayName == "Annual")
        #expect(LicenseType.other.displayName == "Other")
    }
}

@Suite("Pricing Fields")
struct PricingFieldsTests {
    @MainActor
    @Test("New records default to not-free with no license type")
    func defaults() throws {
        let container = try ModelContainer(
            for: AppRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let record = AppRecord(bundleID: "com.x", appName: "X", explanation: "",
                               relevanceScore: 0, relevanceReason: "",
                               bestUse: "", ollamaModel: "")
        container.mainContext.insert(record)
        #expect(record.isFreeApp == false)
        #expect(record.licenseType == nil)
    }
}
```

(If the existing suites construct their in-memory `ModelContainer` differently — check the "Analysis Lock Tests" suite around line 157 — mirror that exact construction instead.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LicenseTypeTests`
Expected: COMPILE ERROR — `cannot find 'LicenseType' in scope`.

- [ ] **Step 3: Implement**

Create `Sources/AppAudit/Models/LicenseType.swift`:

```swift
import Foundation

/// How an app's license was purchased. Drives the subscription card's
/// availability in the detail view: a license that covers the app forever
/// makes a subscription moot.
enum LicenseType: String, CaseIterable, Identifiable {
    case lifetime
    case oneTime = "one-time"
    case annual
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lifetime: return "Lifetime"
        case .oneTime: return "One-time"
        case .annual: return "Annual"
        case .other: return "Other"
        }
    }

    /// True when this license covers the app permanently, so a subscription
    /// cannot apply on top of it.
    var coversForever: Bool {
        self == .lifetime || self == .oneTime
    }
}
```

In `Sources/AppAudit/Models/AppRecord.swift`, after `var isPaidApp: Bool = false` (line 26) add:

```swift
    var isFreeApp: Bool = false
    var licenseType: String? = nil
```

and in `init`, after `self.isPaidApp = false` (line 59) add:

```swift
        self.isFreeApp = false
        self.licenseType = nil
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LicenseTypeTests && swift test --filter PricingFieldsTests` — Expected: 4 PASS.
Then: `swift test` — Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Models/LicenseType.swift Sources/AppAudit/Models/AppRecord.swift Tests/AppAuditTests/AppAuditTests.swift
git commit -m "feat: add LicenseType enum and isFreeApp/licenseType record fields"
```

---

### Task 2: UtilityCardRules + PricingMarks (pure logic)

**Files:**
- Create: `Sources/AppAudit/Models/UtilityCardRules.swift`
- Test: `Tests/AppAuditTests/AppAuditTests.swift` (append)

**Interfaces:**
- Consumes: `LicenseType` from Task 1; `AppRecord` (for `PricingMarks`).
- Produces:
  - `UtilityCardRules.licenseDisabled(isMyApp: Bool, isFreeApp: Bool) -> Bool`
  - `UtilityCardRules.subscriptionDisabled(isMyApp: Bool, isFreeApp: Bool, licenseType: LicenseType?) -> Bool`
  - `UtilityCardRules.disabledReason(isMyApp: Bool, isFreeApp: Bool, licenseType: LicenseType?) -> String?`
  - `PricingMarks.setFree(_ record: AppRecord, to: Bool)` / `PricingMarks.setPaid(_ record: AppRecord, to: Bool)` — mutually exclusive marks.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/AppAuditTests/AppAuditTests.swift`:

```swift
@Suite("Utility Card Rules")
struct UtilityCardRulesTests {
    @Test("License card disabled for My Apps and free apps only")
    func licenseRule() {
        #expect(UtilityCardRules.licenseDisabled(isMyApp: true, isFreeApp: false))
        #expect(UtilityCardRules.licenseDisabled(isMyApp: false, isFreeApp: true))
        #expect(UtilityCardRules.licenseDisabled(isMyApp: true, isFreeApp: true))
        #expect(!UtilityCardRules.licenseDisabled(isMyApp: false, isFreeApp: false))
    }

    @Test("Subscription card disabled for My Apps, free apps, and forever licenses")
    func subscriptionRule() {
        #expect(UtilityCardRules.subscriptionDisabled(isMyApp: true, isFreeApp: false, licenseType: nil))
        #expect(UtilityCardRules.subscriptionDisabled(isMyApp: false, isFreeApp: true, licenseType: nil))
        #expect(UtilityCardRules.subscriptionDisabled(isMyApp: false, isFreeApp: false, licenseType: .lifetime))
        #expect(UtilityCardRules.subscriptionDisabled(isMyApp: false, isFreeApp: false, licenseType: .oneTime))
        #expect(!UtilityCardRules.subscriptionDisabled(isMyApp: false, isFreeApp: false, licenseType: .annual))
        #expect(!UtilityCardRules.subscriptionDisabled(isMyApp: false, isFreeApp: false, licenseType: .other))
        #expect(!UtilityCardRules.subscriptionDisabled(isMyApp: false, isFreeApp: false, licenseType: nil))
    }

    @Test("Disabled reason priority: your app, then free, then license type")
    func reasonPriority() {
        #expect(UtilityCardRules.disabledReason(isMyApp: true, isFreeApp: true, licenseType: .lifetime) == "Your app")
        #expect(UtilityCardRules.disabledReason(isMyApp: false, isFreeApp: true, licenseType: .lifetime) == "Free app")
        #expect(UtilityCardRules.disabledReason(isMyApp: false, isFreeApp: false, licenseType: .lifetime) == "Lifetime license")
        #expect(UtilityCardRules.disabledReason(isMyApp: false, isFreeApp: false, licenseType: .oneTime) == "One-time license")
        #expect(UtilityCardRules.disabledReason(isMyApp: false, isFreeApp: false, licenseType: .annual) == nil)
        #expect(UtilityCardRules.disabledReason(isMyApp: false, isFreeApp: false, licenseType: nil) == nil)
    }
}

@Suite("Pricing Marks")
struct PricingMarksTests {
    @MainActor
    private func makeRecord() throws -> AppRecord {
        let container = try ModelContainer(
            for: AppRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let record = AppRecord(bundleID: "com.x", appName: "X", explanation: "",
                               relevanceScore: 0, relevanceReason: "",
                               bestUse: "", ollamaModel: "")
        container.mainContext.insert(record)
        return record
    }

    @MainActor
    @Test("Marking free clears paid, and vice versa")
    func mutualExclusion() throws {
        let record = try makeRecord()
        PricingMarks.setPaid(record, to: true)
        #expect(record.isPaidApp && !record.isFreeApp)
        PricingMarks.setFree(record, to: true)
        #expect(record.isFreeApp && !record.isPaidApp)
        PricingMarks.setPaid(record, to: true)
        #expect(record.isPaidApp && !record.isFreeApp)
    }

    @MainActor
    @Test("Unmarking one does not set the other")
    func unmarkIsNotToggle() throws {
        let record = try makeRecord()
        PricingMarks.setFree(record, to: true)
        PricingMarks.setFree(record, to: false)
        #expect(!record.isFreeApp && !record.isPaidApp)
        PricingMarks.setPaid(record, to: true)
        PricingMarks.setPaid(record, to: false)
        #expect(!record.isPaidApp && !record.isFreeApp)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter UtilityCardRulesTests`
Expected: COMPILE ERROR — `cannot find 'UtilityCardRules' in scope`.

- [ ] **Step 3: Implement**

Create `Sources/AppAudit/Models/UtilityCardRules.swift`:

```swift
import Foundation

/// Pure availability rules for the utility cards in the app detail view.
/// A disabled card stays visible (grayed) and keeps its data; these rules
/// only decide interactivity and the reason hint shown on the card.
enum UtilityCardRules {
    static func licenseDisabled(isMyApp: Bool, isFreeApp: Bool) -> Bool {
        isMyApp || isFreeApp
    }

    static func subscriptionDisabled(isMyApp: Bool, isFreeApp: Bool, licenseType: LicenseType?) -> Bool {
        isMyApp || isFreeApp || (licenseType?.coversForever ?? false)
    }

    /// The one-line reason shown on a grayed card. The app being yours beats
    /// free, which beats the license type.
    static func disabledReason(isMyApp: Bool, isFreeApp: Bool, licenseType: LicenseType?) -> String? {
        if isMyApp { return "Your app" }
        if isFreeApp { return "Free app" }
        if let licenseType, licenseType.coversForever {
            return "\(licenseType.displayName) license"
        }
        return nil
    }
}

/// Free and Paid are mutually exclusive marks; applying one clears the other.
/// Unmarking never sets the opposite.
enum PricingMarks {
    static func setFree(_ record: AppRecord, to free: Bool) {
        record.isFreeApp = free
        if free { record.isPaidApp = false }
    }

    static func setPaid(_ record: AppRecord, to paid: Bool) {
        record.isPaidApp = paid
        if paid { record.isFreeApp = false }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter UtilityCardRulesTests && swift test --filter PricingMarksTests` — Expected: 5 PASS.
Then: `swift test` — Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Models/UtilityCardRules.swift Tests/AppAuditTests/AppAuditTests.swift
git commit -m "feat: add utility card gray-out rules and Free/Paid mutual exclusion"
```

---

### Task 3: License type picker in the license sheet

**Files:**
- Modify: `Sources/AppAudit/Views/AppDetailView.swift` — state block (~line 22), license sheet save handler (lines 73–91), license row edit button (~line 690), key delete button (~line 703), `DetailLicenseKeySheet` (line 1067)

**Interfaces:**
- Consumes: `LicenseType` from Task 1.
- Produces: `@State private var draftLicenseType: LicenseType?` on `AppDetailView`; `DetailLicenseKeySheet` gains `@Binding var licenseType: LicenseType?` (parameter order: `appName, draft, emailDraft, licenseType, onDone`); saving writes `record.licenseType`; deleting the key clears it.

There is no view-level unit test seam; this task verifies by build + suite + the record-level persistence being trivial (`rawValue` string, already tested in Task 1).

- [ ] **Step 1: Add the draft state**

In `AppDetailView`'s state block, after `@State private var currentLicenseKey: String? = nil` (line 22), add:

```swift
    @State private var draftLicenseType: LicenseType? = nil
```

- [ ] **Step 2: Extend DetailLicenseKeySheet**

In `struct DetailLicenseKeySheet` (line 1067), add the binding after `@Binding var emailDraft: String`:

```swift
    @Binding var licenseType: LicenseType?
```

and in its `body`, directly after the `TextField("Registered email (optional)", ...)` line, add:

```swift
            Picker("License type", selection: $licenseType) {
                Text("Not set").tag(LicenseType?.none)
                ForEach(LicenseType.allCases) { type in
                    Text(type.displayName).tag(LicenseType?.some(type))
                }
            }
            .pickerStyle(.menu)
```

- [ ] **Step 3: Wire the sheet call site**

In the `.sheet(isPresented: $editingLicenseKey)` block (line 73), pass the new binding:

```swift
            DetailLicenseKeySheet(appName: app.name, draft: $draftLicenseKey, emailDraft: $draftLicenseEmail, licenseType: $draftLicenseType) { saved in
```

and inside the `if saved` body, after the `ensuredRecord.licenseEmail = ...` line, add:

```swift
                    ensuredRecord.licenseType = draftLicenseType?.rawValue
```

In the license row's edit button (the one that sets `editingLicenseKey = true`, ~line 690), add before `editingLicenseKey = true`:

```swift
                    draftLicenseType = record?.licenseType.flatMap(LicenseType.init(rawValue:))
```

In the key delete button handler (the `Button(role: .destructive)` that calls `licenseKeyStore.delete`, ~line 703), after `record?.licenseEmail = nil` add:

```swift
                        record?.licenseType = nil
```

- [ ] **Step 4: Build and run the full suite**

Run: `swift build && swift test`
Expected: builds cleanly, all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Views/AppDetailView.swift
git commit -m "feat: license type picker (Lifetime/One-time/Annual/Other) in the license sheet"
```

---

### Task 4: Notes editor becomes a sheet

**Files:**
- Modify: `Sources/AppAudit/Views/AppDetailView.swift` — state (~line 23), body sheets (after line 139), `notesSection` (line 474), `NotesEditor` usage; add `NotesSheet` struct next to the other sheet structs (~line 1067)

**Interfaces:**
- Consumes: existing `NotesEditor`, `endNotesSession()`, `notesSessionBundleID`/`notesSessionInitialNotes`.
- Produces: `@State private var notesSheetPresented = false`; `NotesSheet(appName:text:onClose:)` struct; the notes row opens the sheet. Session semantics identical: presenting captures the session, dismissing (any way) ends it and may trigger re-analysis.

- [ ] **Step 1: Replace the expansion state**

In the state block, replace `@State private var notesExpanded = false` with:

```swift
    @State private var notesSheetPresented = false
```

(`notesHovered` stays for now; it is removed with the card grid in Task 5.)

- [ ] **Step 2: Add the sheet struct**

Add next to the other sheet structs (before `struct DetailLicenseKeySheet`):

```swift
struct NotesSheet: View {
    let appName: String
    @Binding var text: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes for \(appName)")
                .font(.headline)
            Text("Your words feed the next analysis — say how you actually use this app.")
                .font(.caption)
                .foregroundStyle(.secondary)
            NotesEditor(text: $text)
                .frame(minHeight: 140)
            HStack {
                Button("Clear") {
                    text = ""
                    onClose()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove the note and close")
                Spacer()
                Button("Save") { onClose() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .help("Save and re-analyze with this note (⌘↩)")
            }
        }
        .padding(20)
        .frame(width: 440)
        .onExitCommand { onClose() }
    }
}
```

- [ ] **Step 3: Present the sheet and move the session hooks**

In `body`, after the `.sheet(isPresented: $editingSubscription)` block (line 139), add:

```swift
        .sheet(isPresented: $notesSheetPresented) {
            NotesSheet(
                appName: app.name,
                text: Binding(
                    get: { record?.notes ?? "" },
                    set: { ensureRecord().notes = $0.isEmpty ? nil : $0; saveRecord() }
                )
            ) {
                notesSheetPresented = false
            }
        }
        .onChange(of: notesSheetPresented) { _, presented in
            if presented {
                notesSessionBundleID = app.bundleID
                notesSessionInitialNotes = record?.notes
            } else {
                endNotesSession()
            }
        }
```

- [ ] **Step 4: Simplify the notes row**

Replace the whole `notesSection` computed property (line 474 through its closing brace — it currently contains the expander, the inline `NotesEditor`, the Save/Clear HStack, and `.onChange`/`.onDisappear` modifiers) with:

```swift
    private var notesSection: some View {
        HStack(spacing: 8) {
            utilityChip("note.text", tint: .yellow)
            Text("Notes")
                .font(.subheadline.weight(.medium))
            if let notes = record?.notes, !notes.isEmpty {
                Text(notes.components(separatedBy: .newlines).first ?? notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("None yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: (record?.notes?.isEmpty == false) ? "pencil" : "plus.circle")
                .foregroundStyle(.secondary)
                .opacity(notesHovered ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { notesSheetPresented = true }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                notesHovered = hovering
            }
        }
        .onDisappear {
            endNotesSession()
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
```

Note: the `.onDisappear { endNotesSession() }` safety net moves with the row; the old `.onChange(of: app.bundleID) { notesExpanded = false }` is no longer needed because a presented sheet blocks selection changes — but keep a defensive equivalent by adding to the existing `.task(id: app.bundleID)` block in `body` (line 57): nothing to add there; the sheet cannot remain open across a bundleID change.

- [ ] **Step 5: Build, test, commit**

Run: `swift build && swift test` — Expected: all PASS.

```bash
git add Sources/AppAudit/Views/AppDetailView.swift
git commit -m "feat: notes editor opens as a sheet with Save/Clear and Esc"
```

---

### Task 5: The 2×2 card grid

**Files:**
- Modify: `Sources/AppAudit/Views/AppDetailView.swift` — `utilitySection` (line 459), the four row properties, hover state vars, `togglePaidApp` (line 898); add `UtilityCard` container struct
- Modify: `FEATURES.md`, `README.md`

**Interfaces:**
- Consumes: `UtilityCardRules`, `PricingMarks`, `LicenseType`, `draftLicenseType` (Task 3), `notesSheetPresented` (Task 4), existing helpers `utilityChip`, `subscriptionDetailLine`, `hasSuggestedLink`, `beginEditingSubscription`, `ensureRecord`, `saveRecord`, `viewModel.setPaidApp`.
- Produces: `utilitySection` as a `LazyVGrid`; card views `notesCard`, `licenseCard`, `subscriptionCard`, `linkCard`; `UtilityCard<Content>` container; `togglePaid()`/`toggleFree()` replacing `togglePaidApp()`.

- [ ] **Step 1: Add the card container**

Add a private struct at the bottom of `AppDetailView.swift` (file scope, near `UtilityRowDivider`):

```swift
/// Glass card container for the utility grid. Disabled cards stay visible
/// but ignore the primary tap; buttons inside the content stay interactive
/// (that is how the Free/Paid chips remain reachable on a grayed card).
struct UtilityCard<Content: View>: View {
    var disabled: Bool = false
    var action: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .padding(12)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.separator.opacity(hovered && !disabled ? 0.8 : 0), lineWidth: 1)
            )
            .opacity(disabled ? 0.55 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                if !disabled { action?() }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    hovered = hovering
                }
            }
    }
}
```

- [ ] **Step 2: Replace utilitySection with the grid**

Replace the `utilitySection` property (line 459) with:

```swift
    private var utilitySection: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            alignment: .leading, spacing: 10
        ) {
            notesCard
            licenseCard
            subscriptionCard
            linkCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
```

- [ ] **Step 3: The notes card**

Replace the Task 4 `notesSection` row with a card (delete `notesSection` and `notesHovered`; keep the `.onDisappear` safety net by moving it onto the card):

```swift
    private var notesCard: some View {
        UtilityCard(action: { notesSheetPresented = true }) {
            HStack(spacing: 8) {
                utilityChip("note.text", tint: .yellow)
                Text("Notes")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: (record?.notes?.isEmpty == false) ? "pencil" : "plus.circle")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
            }
            if let notes = record?.notes, !notes.isEmpty {
                Text(notes.components(separatedBy: .newlines).first ?? notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("None yet — your words feed the analysis")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .onDisappear {
            endNotesSession()
        }
    }
```

- [ ] **Step 4: The license card**

Replace `licenseKeySection`, `appStoreOwnershipRowContent`, and `licenseKeyRowContent` (lines 574–721) with one card. The reveal/copy/delete buttons keep their exact existing action closures — copy them verbatim from the current `licenseKeyRowContent`:

```swift
    private var licenseCard: some View {
        let isFree = record?.isFreeApp == true
        let disabled = UtilityCardRules.licenseDisabled(isMyApp: app.isMyApp, isFreeApp: isFree)
        let reason = UtilityCardRules.disabledReason(isMyApp: app.isMyApp, isFreeApp: isFree, licenseType: nil)

        return UtilityCard(disabled: disabled, action: {
            guard !app.isAppStoreInstall else { return }
            draftLicenseKey = currentLicenseKey ?? ""
            draftLicenseEmail = record?.licenseEmail
                ?? UserDefaults.standard.string(forKey: "defaultLicenseEmail") ?? ""
            draftLicenseType = record?.licenseType.flatMap(LicenseType.init(rawValue:))
            editingLicenseKey = true
        }) {
            HStack(spacing: 8) {
                utilityChip(app.isAppStoreInstall ? "bag.fill" : "key.horizontal",
                            tint: app.isAppStoreInstall ? .blue : .indigo)
                Text(app.isAppStoreInstall ? "Mac App Store" : "License")
                    .font(.subheadline.weight(.medium))
                Spacer()
                pricingChips
            }
            if let reason {
                Text(reason)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else if app.isAppStoreInstall {
                Text(record?.isPaidApp == true ? "Paid · tied to your Apple ID" : "Tied to your Apple ID")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if let key = currentLicenseKey, !key.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Saved")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let type = record?.licenseType.flatMap(LicenseType.init(rawValue:)) {
                            Text(type.displayName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.indigo)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.indigo.opacity(0.14), in: Capsule())
                        }
                        licenseKeyActions(key: key)
                    }
                    if let email = record?.licenseEmail, !email.isEmpty {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } else {
                Text("Add key")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
```

Add `licenseKeyActions(key:)` as a small helper containing the reveal (eye), copy (doc.on.doc), and delete (trash) buttons — bodies copied verbatim from the current `licenseKeyRowContent` (lines 654–717), including the `LicenseKeyGuard.authenticate` flows, `keyCopied` feedback, and the delete handler with the Task 3 `record?.licenseType = nil` line. Remove the `.opacity(licenseHovered ? 1 : 0)` wrappers (chips and actions are always visible on cards) and delete the `licenseHovered` state var.

Add the pricing chips property:

```swift
    private var pricingChips: some View {
        HStack(spacing: 4) {
            Button {
                togglePaid()
            } label: {
                Image(systemName: record?.isPaidApp == true ? "checkmark.seal.fill" : "checkmark.seal")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(record?.isPaidApp == true ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
            .help(record?.isPaidApp == true ? "Marked as paid — click to unmark" : "Mark as paid")

            Button {
                toggleFree()
            } label: {
                Image(systemName: record?.isFreeApp == true ? "gift.fill" : "gift")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(record?.isFreeApp == true ? AnyShapeStyle(.blue) : AnyShapeStyle(.secondary))
            .help(record?.isFreeApp == true ? "Marked as free — click to unmark" : "Mark as free app")
        }
        .imageScale(.small)
    }
```

Replace `togglePaidApp()` (line 898) with:

```swift
    private func togglePaid() {
        let ensured = ensureRecord()
        PricingMarks.setPaid(ensured, to: !ensured.isPaidApp)
        viewModel.setPaidApp(bundleID: app.bundleID, value: ensured.isPaidApp)
        saveRecord()
    }

    private func toggleFree() {
        let ensured = ensureRecord()
        PricingMarks.setFree(ensured, to: !ensured.isFreeApp)
        viewModel.setPaidApp(bundleID: app.bundleID, value: ensured.isPaidApp)
        saveRecord()
    }
```

- [ ] **Step 5: The subscription card**

Replace `subscriptionSection` (lines 723–771) with (keep `subscriptionDetailLine` unchanged; the row's trash button is dropped — the sheet's Clear action covers deletion):

```swift
    private var subscriptionCard: some View {
        let isFree = record?.isFreeApp == true
        let licenseType = record?.licenseType.flatMap(LicenseType.init(rawValue:))
        let disabled = UtilityCardRules.subscriptionDisabled(isMyApp: app.isMyApp, isFreeApp: isFree, licenseType: licenseType)
        let reason = UtilityCardRules.disabledReason(isMyApp: app.isMyApp, isFreeApp: isFree, licenseType: licenseType)

        return UtilityCard(disabled: disabled, action: { beginEditingSubscription() }) {
            HStack(spacing: 8) {
                utilityChip("creditcard", tint: .green)
                Text("Subscription")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: record?.hasSubscription == true ? "pencil" : "plus.circle")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
            }
            if let reason {
                Text(reason)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else if record?.hasSubscription == true, let renewal = record?.subscriptionRenewalDate {
                subscriptionDetailLine(renewal: renewal)
            } else if record?.hasSubscription == true {
                Text("Marked · add details")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Add subscription")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
```

Delete the `subHovered` state var.

- [ ] **Step 6: The link card**

Replace `urlSection` (lines 808–865) with:

```swift
    private var linkCard: some View {
        UtilityCard(action: {
            if let urlString = record?.appURL, !urlString.isEmpty, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            } else {
                draftURL = record?.appURL ?? record?.suggestedAppURL ?? ""
                editingURL = true
            }
        }) {
            HStack(spacing: 8) {
                utilityChip("link", tint: .blue)
                Text("App Link")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    draftURL = record?.appURL ?? record?.suggestedAppURL ?? ""
                    editingURL = true
                } label: {
                    Image(systemName: record?.appURL != nil ? "pencil" : "plus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .imageScale(.small)
                .help(record?.appURL != nil ? "Edit app link" : (hasSuggestedLink ? "Add app link (a suggestion is prefilled)" : "Add app link"))
                if record?.appURL != nil {
                    Button(role: .destructive) {
                        record?.appURL = nil
                        saveRecord()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove app link")
                }
            }
            if let urlString = record?.appURL, !urlString.isEmpty {
                Text(URL(string: urlString)?.host() ?? urlString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if hasSuggestedLink {
                Text("Add link · suggestion ready")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Add link")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
```

Delete the `urlHovered` state var and the now-unused `UtilityRowDivider` struct (grep first: `grep -n UtilityRowDivider Sources/AppAudit/Views/*.swift` — remove only if this was its last use).

- [ ] **Step 7: Docs**

In `FEATURES.md`, in the detail-view/utilities area, add:

```markdown
- Utility card grid: Notes, License, Subscription, and App Link as 2×2 cards. Cards gray out when they cannot apply — license & subscription for **Free apps** (the explicit opposite of Paid) and **My Apps**, subscription also when the license type is **Lifetime** or **One-time** — always showing why, never deleting stored data. Clicking the link card opens the URL; the license sheet records the license type.
```

In `README.md`, extend the tags bullet `- Tags apps you **build**, **favorite**, or pay a **subscription** for` to:

```markdown
- Tags apps you **build**, **favorite**, pay a **subscription** for, or mark **free**/**paid**; license keys can carry a type (lifetime, one-time, annual)
```

- [ ] **Step 8: Build, full suite, side-build smoke**

Run: `swift build && swift test` — Expected: all PASS.
Run: `bash Scripts/build_sift2.sh` — Expected: installs /Applications/Sift2.app for manual verification.

- [ ] **Step 9: Commit**

```bash
git add Sources/AppAudit/Views/AppDetailView.swift FEATURES.md README.md
git commit -m "feat: 2x2 utility card grid with pricing-aware gray-out rules"
```

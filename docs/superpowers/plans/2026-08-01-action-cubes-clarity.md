# Action Cubes Clarity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shrink the detail-view header from 10 utility cubes to 7 by merging license + subscription into one Money cube with a popover, add an instant hover label strip, and gate all My App UI behind a Developer Mode toggle.

**Architecture:** Pure state logic lives in small model enums (`MoneyCubeState`, additions to `UtilityCardRules`) that are unit-tested; SwiftUI views consume them. The Money popover replaces the two existing edit sheets but reuses the exact same `AppRecord` fields and draft-`@State` pattern — no data migration. Developer Mode is a single `@AppStorage("developerMode")` flag read at each My App UI site.

**Tech Stack:** SwiftUI (macOS), SwiftData, SwiftPM executable `Sift`, Swift Testing (`import Testing`, `@Test`, `#expect`) in target `SiftTests`.

**Spec:** `docs/superpowers/specs/2026-08-01-action-cubes-clarity-design.md`

## Global Constraints

- No data migration: Money cube reads/writes the existing `AppRecord` fields (`isPaidApp`, `isFreeApp`, `hasLicenseKey`, keychain key via `licenseKeyStore`, `licenseType`, `licenseEmail`, `hasSubscription`, `subscriptionPrice/Currency/Cycle/RenewalDate/Email`).
- Developer Mode hides UI only — it never rewrites records. `isMyApp` data survives toggling.
- Developer Mode default is **OFF** (`@AppStorage("developerMode") = false`).
- Cube grid stays 34pt cubes, 5 fixed columns, 8pt spacing, in the header's right side.
- Label strip has reserved fixed height — hovering must not shift layout.
- Tests run with `swift test` from the repo root. Build check: `swift build`.
- All work on branch `claude/button-actions-clarity-879c6e`; commit after every task.

---

### Task 1: `MoneyCubeState` model

**Files:**
- Create: `Sources/AppAudit/Models/MoneyCubeState.swift`
- Test: `Tests/AppAuditTests/AppAuditTests.swift` (append a new suite)

**Interfaces:**
- Consumes: nothing new.
- Produces: `MoneyCubeState` enum with `static func derive(isAppStoreInstall:hasLicenseKey:isPaidApp:hasSubscription:renewalNear:isFreeApp:) -> MoneyCubeState`, `var symbol: String`, `var isActive: Bool`. Task 4 renders the cube from these.

State precedence (from spec, with one refinement): **subscription > App Store > licensed/paid > free > none**. App Store outranks licensed because store installs never have license keys (the license section is hidden for them today) — only the `isPaidApp` mark could collide, and the existing UI shows the blue seal for paid App Store apps.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/AppAuditTests/AppAuditTests.swift`:

```swift
@Suite("Money Cube State")
struct MoneyCubeStateTests {
    @Test("Precedence: subscription > App Store > licensed > free > none")
    func precedence() {
        // Subscription wins over everything.
        #expect(MoneyCubeState.derive(isAppStoreInstall: true, hasLicenseKey: true, isPaidApp: true,
                                      hasSubscription: true, renewalNear: false, isFreeApp: true)
                == .subscription(renewalNear: false))
        // App Store beats licensed/paid and free.
        #expect(MoneyCubeState.derive(isAppStoreInstall: true, hasLicenseKey: false, isPaidApp: true,
                                      hasSubscription: false, renewalNear: false, isFreeApp: false)
                == .appStore)
        // Key or paid mark → licensed.
        #expect(MoneyCubeState.derive(isAppStoreInstall: false, hasLicenseKey: true, isPaidApp: false,
                                      hasSubscription: false, renewalNear: false, isFreeApp: false)
                == .licensed)
        #expect(MoneyCubeState.derive(isAppStoreInstall: false, hasLicenseKey: false, isPaidApp: true,
                                      hasSubscription: false, renewalNear: false, isFreeApp: false)
                == .licensed)
        // Free mark, nothing else.
        #expect(MoneyCubeState.derive(isAppStoreInstall: false, hasLicenseKey: false, isPaidApp: false,
                                      hasSubscription: false, renewalNear: false, isFreeApp: true)
                == .free)
        // Nothing at all.
        #expect(MoneyCubeState.derive(isAppStoreInstall: false, hasLicenseKey: false, isPaidApp: false,
                                      hasSubscription: false, renewalNear: false, isFreeApp: false)
                == .none)
    }

    @Test("Renewal-near flag flows through")
    func renewalNear() {
        #expect(MoneyCubeState.derive(isAppStoreInstall: false, hasLicenseKey: false, isPaidApp: false,
                                      hasSubscription: true, renewalNear: true, isFreeApp: false)
                == .subscription(renewalNear: true))
    }

    @Test("Symbols and active flag per state")
    func faces() {
        #expect(MoneyCubeState.subscription(renewalNear: false).symbol == "creditcard.fill")
        #expect(MoneyCubeState.appStore.symbol == "checkmark.seal.fill")
        #expect(MoneyCubeState.licensed.symbol == "key.horizontal")
        #expect(MoneyCubeState.free.symbol == "gift")
        #expect(MoneyCubeState.none.symbol == "dollarsign.circle")
        #expect(MoneyCubeState.subscription(renewalNear: true).isActive)
        #expect(MoneyCubeState.appStore.isActive)
        #expect(MoneyCubeState.licensed.isActive)
        #expect(!MoneyCubeState.free.isActive)
        #expect(!MoneyCubeState.none.isActive)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MoneyCubeStateTests`
Expected: compile FAILURE — `MoneyCubeState` not defined.

- [ ] **Step 3: Write the implementation**

Create `Sources/AppAudit/Models/MoneyCubeState.swift`:

```swift
import Foundation

/// The face of the merged Money cube — one cube owns App Store ownership,
/// license keys, paid/free marks, and subscriptions. Precedence:
/// subscription > App Store > licensed/paid > free > none. App Store
/// outranks licensed because store installs never carry license keys.
enum MoneyCubeState: Equatable {
    case subscription(renewalNear: Bool)
    case appStore
    case licensed
    case free
    case none

    static func derive(isAppStoreInstall: Bool,
                       hasLicenseKey: Bool,
                       isPaidApp: Bool,
                       hasSubscription: Bool,
                       renewalNear: Bool,
                       isFreeApp: Bool) -> MoneyCubeState {
        if hasSubscription { return .subscription(renewalNear: renewalNear) }
        if isAppStoreInstall { return .appStore }
        if hasLicenseKey || isPaidApp { return .licensed }
        if isFreeApp { return .free }
        return .none
    }

    var symbol: String {
        switch self {
        case .subscription: return "creditcard.fill"
        case .appStore: return "checkmark.seal.fill"
        case .licensed: return "key.horizontal"
        case .free: return "gift"
        case .none: return "dollarsign.circle"
        }
    }

    /// Active states fill the cube with their tint; free/none stay quiet.
    var isActive: Bool {
        switch self {
        case .subscription, .appStore, .licensed: return true
        case .free, .none: return false
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MoneyCubeStateTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Models/MoneyCubeState.swift Tests/AppAuditTests/AppAuditTests.swift
git commit -m "feat: MoneyCubeState — merged money-cube face derivation"
```

---

### Task 2: `moneyDisabled` + `DevModeRules`

**Files:**
- Modify: `Sources/AppAudit/Models/UtilityCardRules.swift`
- Test: `Tests/AppAuditTests/AppAuditTests.swift` (append to existing `UtilityCardRulesTests` area)

**Interfaces:**
- Consumes: nothing new.
- Produces: `UtilityCardRules.moneyDisabled(isMyApp:) -> Bool`; `DevModeRules.showsMyAppUI(isMyApp:developerMode:) -> Bool` and `DevModeRules.filterMyApps(current:developerMode:) -> Bool`. Tasks 4 and 6 call these. The existing `licenseDisabled` / `subscriptionDisabled` / `disabledReason` stay unchanged (the popover uses them internally).

- [ ] **Step 1: Write the failing tests**

Append to `Tests/AppAuditTests/AppAuditTests.swift`:

```swift
@Suite("Money Cube + Dev Mode Rules")
struct MoneyDevRulesTests {
    @Test("Money cube is disabled only for My Apps")
    func moneyRule() {
        #expect(UtilityCardRules.moneyDisabled(isMyApp: true))
        #expect(!UtilityCardRules.moneyDisabled(isMyApp: false))
    }

    @Test("My App UI shows only when marked AND developer mode is on")
    func showsMyAppUI() {
        #expect(DevModeRules.showsMyAppUI(isMyApp: true, developerMode: true))
        #expect(!DevModeRules.showsMyAppUI(isMyApp: true, developerMode: false))
        #expect(!DevModeRules.showsMyAppUI(isMyApp: false, developerMode: true))
        #expect(!DevModeRules.showsMyAppUI(isMyApp: false, developerMode: false))
    }

    @Test("Leaving developer mode clears the My Apps filter")
    func filterClears() {
        #expect(DevModeRules.filterMyApps(current: true, developerMode: true))
        #expect(!DevModeRules.filterMyApps(current: true, developerMode: false))
        #expect(!DevModeRules.filterMyApps(current: false, developerMode: true))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MoneyDevRulesTests`
Expected: compile FAILURE — `moneyDisabled` / `DevModeRules` not defined.

- [ ] **Step 3: Write the implementation**

In `Sources/AppAudit/Models/UtilityCardRules.swift`, add inside `enum UtilityCardRules`:

```swift
    /// The merged Money cube: only your own app has no money story.
    /// Free apps stay clickable — the popover is where Free gets unmarked.
    static func moneyDisabled(isMyApp: Bool) -> Bool {
        isMyApp
    }
```

And at file scope (below `PricingMarks`):

```swift
/// Developer Mode hides all My App UI without touching any records.
enum DevModeRules {
    /// Whether a My App marker (hammer badge, cube, score treatment) shows.
    static func showsMyAppUI(isMyApp: Bool, developerMode: Bool) -> Bool {
        isMyApp && developerMode
    }

    /// The My Apps filter cannot stay on invisibly when dev mode turns off.
    static func filterMyApps(current: Bool, developerMode: Bool) -> Bool {
        developerMode ? current : false
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MoneyDevRulesTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Models/UtilityCardRules.swift Tests/AppAuditTests/AppAuditTests.swift
git commit -m "feat: money-cube disable rule + DevModeRules gating logic"
```

---

### Task 3: `MoneyPopover` view

**Files:**
- Create: `Sources/AppAudit/Views/MoneyPopover.swift`

**Interfaces:**
- Consumes: `LicenseType` (`displayName`, `allCases`), `BillingCycle` (`label`, `allCases`), `UtilityCardRules.licenseDisabled/subscriptionDisabled/disabledReason`, `LicenseKeyGuard.authenticate(reason:)`, `PricingMarks` semantics via callbacks.
- Produces: `struct MoneyPopover: View` with the exact initializer below. Task 4 presents it from the Money cube.

Pure UI: drafts come in as bindings, every mutation goes out through a callback. No model access. Sections mirror the two deleted sheets plus the paid/free marks.

- [ ] **Step 1: Write the view**

Create `Sources/AppAudit/Views/MoneyPopover.swift`:

```swift
import SwiftUI

/// One panel for everything money: paid/free marks, license key, and
/// subscription. Replaces the separate license and subscription sheets.
/// Dumb view — state arrives as values/bindings, changes leave as callbacks.
struct MoneyPopover: View {
    let appName: String
    let isAppStoreInstall: Bool
    let isMyApp: Bool
    let isPaid: Bool
    let isFree: Bool
    let hasKey: Bool
    let hasSubscription: Bool
    let currentLicenseType: LicenseType?

    @Binding var draftLicenseKey: String
    @Binding var draftLicenseEmail: String
    @Binding var draftLicenseType: LicenseType?
    @Binding var draftSubPrice: String
    @Binding var draftSubCurrency: String
    @Binding var draftSubCycle: BillingCycle
    @Binding var draftSubRenewal: Date
    @Binding var draftSubEmail: String

    let onTogglePaid: () -> Void
    let onToggleFree: () -> Void
    let onSaveLicense: () -> Void
    let onCopyKey: () -> Void
    let onRemoveKey: () -> Void
    let onSaveSubscription: () -> Void
    let onRemoveSubscription: () -> Void

    @State private var revealed = false

    private static let currencies = ["USD", "EUR", "GBP", "ILS", "CAD", "AUD", "JPY", "CHF"]

    /// Always include the record's current currency even if it is not in the
    /// short list, so the picker can display it without losing the value.
    static func currencyOptions(including current: String) -> [String] {
        if current.isEmpty || currencies.contains(current) { return currencies }
        return [current] + currencies
    }

    private var parsedAmount: Double? {
        Double(draftSubPrice.replacingOccurrences(of: ",", with: "."))
    }

    private var licenseDisabled: Bool {
        UtilityCardRules.licenseDisabled(isMyApp: isMyApp, isFreeApp: isFree)
    }

    private var subscriptionDisabled: Bool {
        UtilityCardRules.subscriptionDisabled(isMyApp: isMyApp, isFreeApp: isFree,
                                              licenseType: currentLicenseType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Money — \(appName)")
                .font(.headline)

            marksSection
            Divider()
            if isAppStoreInstall {
                Label(isPaid ? "Mac App Store — paid, tied to your Apple ID"
                             : "Mac App Store — tied to your Apple ID",
                      systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                licenseSection
            }
            Divider()
            subscriptionSection
        }
        .padding(16)
        .frame(width: 360)
    }

    private var marksSection: some View {
        HStack(spacing: 8) {
            Toggle("Paid", isOn: Binding(get: { isPaid }, set: { _ in onTogglePaid() }))
            Toggle("Free", isOn: Binding(get: { isFree }, set: { _ in onToggleFree() }))
            Spacer()
            if let reason = UtilityCardRules.disabledReason(isMyApp: isMyApp, isFreeApp: isFree,
                                                            licenseType: currentLicenseType) {
                Text(reason).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .toggleStyle(.button)
        .controlSize(.small)
    }

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("License key").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Group {
                    if revealed {
                        TextField("Enter license key", text: $draftLicenseKey)
                    } else {
                        SecureField("Enter license key", text: $draftLicenseKey)
                    }
                }
                .textFieldStyle(.roundedBorder)

                Button {
                    if revealed {
                        revealed = false
                    } else {
                        Task { @MainActor in
                            if await LicenseKeyGuard.authenticate(reason: "reveal the license key for \(appName)") {
                                revealed = true
                            }
                        }
                    }
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(revealed ? "Hide license key" : "Reveal license key (Touch ID)")
            }

            TextField("Registered email (optional)", text: $draftLicenseEmail)
                .textFieldStyle(.roundedBorder)

            Picker("License type", selection: $draftLicenseType) {
                Text("Not set").tag(LicenseType?.none)
                ForEach(LicenseType.allCases) { type in
                    Text(type.displayName).tag(LicenseType?.some(type))
                }
            }
            .pickerStyle(.menu)

            HStack {
                if hasKey {
                    Button("Copy (Touch ID)") { onCopyKey() }
                        .controlSize(.small)
                    Button("Remove", role: .destructive) { onRemoveKey() }
                        .controlSize(.small)
                }
                Spacer()
                Button("Save Key") { onSaveLicense() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(draftLicenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasKey)
            }
        }
        .disabled(licenseDisabled)
        .opacity(licenseDisabled ? 0.5 : 1)
    }

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subscription").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack {
                TextField("Amount", text: $draftSubPrice)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                Picker("", selection: $draftSubCurrency) {
                    ForEach(Self.currencyOptions(including: draftSubCurrency), id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 100)
            }
            Picker("Billing", selection: $draftSubCycle) {
                ForEach(BillingCycle.allCases) { c in
                    Text(c.label).tag(c)
                }
            }
            .pickerStyle(.segmented)
            DatePicker("Next renewal", selection: $draftSubRenewal, displayedComponents: .date)
            TextField("Billing email (optional)", text: $draftSubEmail)
                .textFieldStyle(.roundedBorder)

            HStack {
                if hasSubscription {
                    Button("Remove", role: .destructive) { onRemoveSubscription() }
                        .controlSize(.small)
                }
                Spacer()
                Button(hasSubscription ? "Save" : "Mark Subscribed") { onSaveSubscription() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draftSubPrice.isEmpty && parsedAmount == nil)
            }
        }
        .disabled(subscriptionDisabled)
        .opacity(subscriptionDisabled ? 0.5 : 1)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build complete, no errors. (View is not yet referenced — that's Task 4.)

- [ ] **Step 3: Commit**

```bash
git add Sources/AppAudit/Views/MoneyPopover.swift
git commit -m "feat: MoneyPopover — one panel for marks, license, subscription"
```

---

### Task 4: Wire the Money cube into `AppDetailView`

**Files:**
- Modify: `Sources/AppAudit/Views/AppDetailView.swift`

**Interfaces:**
- Consumes: `MoneyCubeState` (Task 1), `UtilityCardRules.moneyDisabled` (Task 2), `MoneyPopover` (Task 3), existing helpers `ensureRecord()`, `saveRecord()`, `togglePaid()`, `toggleFree()`, `copyLicenseKey(_:)`, `removeLicenseKey()`, `clearSubscription()`, `subscriptionRenewalIsNear`, `subscriptionBadgeText`, `licenseKeyStore`, `SubscriptionMath`.
- Produces: `moneyCard` cube + `moneyPopoverPresented` state; `saveLicenseFromDrafts()` and `saveSubscriptionFromDrafts()`; deletes `licenseCard`, `subscriptionCard`, `DetailLicenseKeySheet`, `SubscriptionSheet`, `editingLicenseKey`, `editingSubscription`, and their two `.sheet` blocks. Task 5 hovers over the resulting cubes.

- [ ] **Step 1: Replace state vars**

In the `@State` block (around `AppDetailView.swift:20-30`): delete `editingLicenseKey` and `editingSubscription`; add:

```swift
    @State private var moneyPopoverPresented = false
```

Keep every draft var (`draftLicenseKey`, `draftLicenseEmail`, `draftLicenseType`, `draftSubPrice`, `draftSubCurrency`, `draftSubCycle`, `draftSubRenewal`, `draftSubEmail`) — the popover binds to them.

- [ ] **Step 2: Add the money cube and popover**

Replace both `licenseCard` (lines ~785-808) and `subscriptionCard` (lines ~877-911) with one `moneyCard`. Keep `licenseHelp`, `licenseContextMenu`, `subscriptionHelp`, `subscriptionBadgeText`, `subscriptionRenewalIsNear`, `markSubscription()` (still used); delete nothing else yet.

```swift
    private var moneyCard: some View {
        let state = MoneyCubeState.derive(
            isAppStoreInstall: app.isAppStoreInstall,
            hasLicenseKey: currentLicenseKey?.isEmpty == false,
            isPaidApp: record?.isPaidApp == true,
            hasSubscription: record?.hasSubscription == true,
            renewalNear: subscriptionRenewalIsNear,
            isFreeApp: record?.isFreeApp == true
        )
        let disabled = UtilityCardRules.moneyDisabled(isMyApp: app.isMyApp)
        let tint = moneyTint(for: state)

        return UtilityCard(tint: tint, active: state.isActive, disabled: disabled, action: {
            prepareMoneyDrafts()
            moneyPopoverPresented = true
        }) {
            cardIcon(state.symbol, tint: state.isActive ? tint : .secondary)
        }
        .help(moneyHelp(for: state))
        .contextMenu { moneyContextMenu }
        .popover(isPresented: $moneyPopoverPresented, arrowEdge: .bottom) {
            MoneyPopover(
                appName: app.name,
                isAppStoreInstall: app.isAppStoreInstall,
                isMyApp: app.isMyApp,
                isPaid: record?.isPaidApp == true,
                isFree: record?.isFreeApp == true,
                hasKey: currentLicenseKey?.isEmpty == false,
                hasSubscription: record?.hasSubscription == true,
                currentLicenseType: record?.licenseType.flatMap(LicenseType.init(rawValue:)),
                draftLicenseKey: $draftLicenseKey,
                draftLicenseEmail: $draftLicenseEmail,
                draftLicenseType: $draftLicenseType,
                draftSubPrice: $draftSubPrice,
                draftSubCurrency: $draftSubCurrency,
                draftSubCycle: $draftSubCycle,
                draftSubRenewal: $draftSubRenewal,
                draftSubEmail: $draftSubEmail,
                onTogglePaid: { togglePaid() },
                onToggleFree: { toggleFree() },
                onSaveLicense: { saveLicenseFromDrafts() },
                onCopyKey: { if let key = currentLicenseKey { copyLicenseKey(key) } },
                onRemoveKey: { removeLicenseKey() },
                onSaveSubscription: { saveSubscriptionFromDrafts() },
                onRemoveSubscription: { clearSubscription() }
            )
        }
    }

    private func moneyTint(for state: MoneyCubeState) -> Color {
        switch state {
        case .subscription(let near): return near ? .orange : .green
        case .appStore: return .blue
        case .licensed: return .indigo
        case .free, .none: return .secondary
        }
    }

    private func moneyHelp(for state: MoneyCubeState) -> String {
        switch state {
        case .subscription: return subscriptionHelp
        case .appStore, .licensed: return licenseHelp
        case .free: return "Free app — click for money details"
        case .none: return "Money — paid/free, license key, subscription"
        }
    }

    /// Populate every draft from the record so the popover opens current.
    private func prepareMoneyDrafts() {
        draftLicenseKey = currentLicenseKey ?? ""
        draftLicenseEmail = record?.licenseEmail
            ?? UserDefaults.standard.string(forKey: "defaultLicenseEmail") ?? ""
        draftLicenseType = record?.licenseType.flatMap(LicenseType.init(rawValue:))
        draftSubPrice = record?.subscriptionPrice.map { String(format: "%.2f", $0) } ?? ""
        draftSubCurrency = record?.subscriptionCurrency
            ?? (Locale.current.currency?.identifier ?? "USD")
        draftSubCycle = BillingCycle(rawValue: record?.subscriptionCycle ?? "") ?? .monthly
        draftSubRenewal = record?.subscriptionRenewalDate ?? Date()
        draftSubEmail = record?.subscriptionEmail
            ?? record?.licenseEmail
            ?? UserDefaults.standard.string(forKey: "defaultLicenseEmail") ?? ""
    }

    /// Merged right-click: the quick actions from both old cubes.
    @ViewBuilder
    private var moneyContextMenu: some View {
        Button {
            togglePaid()
        } label: {
            Label(record?.isPaidApp == true ? "Unmark Paid" : "Mark as Paid",
                  systemImage: record?.isPaidApp == true ? "checkmark.seal.fill" : "checkmark.seal")
        }
        Button {
            toggleFree()
        } label: {
            Label(record?.isFreeApp == true ? "Unmark Free" : "Mark as Free App",
                  systemImage: record?.isFreeApp == true ? "gift.fill" : "gift")
        }
        if let key = currentLicenseKey, !key.isEmpty {
            Divider()
            Button {
                copyLicenseKey(key)
            } label: {
                Label("Copy Key (Touch ID)", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                removeLicenseKey()
            } label: {
                Label("Remove Key", systemImage: "trash")
            }
        }
        if record?.hasSubscription == true {
            Divider()
            Button(role: .destructive) {
                clearSubscription()
            } label: {
                Label("Remove Subscription", systemImage: "trash")
            }
        }
    }
```

- [ ] **Step 3: Add the two save helpers**

Move the save logic out of the deleted sheet closures (they were at `AppDetailView.swift:77-96` and `115-144`), verbatim:

```swift
    private func saveLicenseFromDrafts() {
        let trimmed = draftLicenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let ensuredRecord = ensureRecord()
        licenseKeyStore.save(trimmed, bundleID: app.bundleID)
        currentLicenseKey = trimmed.isEmpty ? nil : trimmed
        ensuredRecord.licenseKey = nil
        ensuredRecord.hasLicenseKey = !trimmed.isEmpty
        let email = draftLicenseEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        ensuredRecord.licenseEmail = (trimmed.isEmpty || email.isEmpty) ? nil : email
        ensuredRecord.licenseType = draftLicenseType?.rawValue
        if !trimmed.isEmpty, ensuredRecord.iconPNG == nil {
            ensuredRecord.iconPNG = app.icon?.pngData()
        }
        saveRecord()
    }

    private func saveSubscriptionFromDrafts() {
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
    }
```

- [ ] **Step 4: Update the grid and delete the old pieces**

1. In `headerUtilities` (line ~241): replace the two entries `licenseCard` and `subscriptionCard` with the single `moneyCard`, so the order is: `reanalyzeChip` (conditional), `crossAppCard`, `notesCard`, `moneyCard`, `linkCard`, `lockCard`, `favoriteCard`, `docsCard`, `myAppCard`.
2. Delete the whole `licenseCard` and `subscriptionCard` properties, and `licenseContextMenu` (its items now live in `moneyContextMenu`). Keep `licenseHelp`, `subscriptionHelp`, `subscriptionBadgeText`, `subscriptionRenewalIsNear` (used by `moneyHelp`), and `markSubscription()` — check: `markSubscription()` is now unused (the popover's "Mark Subscribed" goes through `saveSubscriptionFromDrafts`); delete it and `beginEditingSubscription()` too.
3. Delete the `.sheet(isPresented: $editingLicenseKey)` block (~lines 77-96) and `.sheet(isPresented: $editingSubscription)` block (~lines 115-144).
4. Delete the `DetailLicenseKeySheet` struct (~lines 1249-1323) and the `SubscriptionSheet` struct + `SubscriptionSheetAction` enum (~lines 1325-1404). (No other file references them — verified.)

- [ ] **Step 5: Build and test**

Run: `swift build && swift test`
Expected: build clean, all tests pass (nothing referenced the deleted sheets).

- [ ] **Step 6: Visual check**

Run: `swift run Sift` (or `Scripts/compile_and_run.sh`). In any app's detail view: the grid shows 9 cubes (dev gating comes in Task 6); the money cube reflects state; click opens the popover; save a fake subscription on a test app, remove it; right-click shows the merged menu. Quit.

- [ ] **Step 7: Commit**

```bash
git add Sources/AppAudit/Views/AppDetailView.swift
git commit -m "feat: merge license + subscription cubes into one Money cube with popover"
```

---

### Task 5: Instant hover label strip

**Files:**
- Modify: `Sources/AppAudit/Views/AppDetailView.swift`

**Interfaces:**
- Consumes: the cube properties from Task 4; existing help strings (`crossAppHelp`, `notesHelp`, `linkHelp`, `docsHelp`, `moneyHelp(for:)`).
- Produces: `hoveredCubeInfo: String?` state + a caption line under the grid. Task 6 must keep the strip when it hides cubes.

- [ ] **Step 1: Add hover state and helper**

```swift
    @State private var hoveredCubeInfo: String? = nil
```

And a helper that tags any cube with its strip text (first line only, so multiline help stays tooltip-only):

```swift
    /// Feeds the label strip: hovering shows the text instantly, leaving
    /// clears it only if another cube hasn't already claimed the strip.
    private func stripInfo<V: View>(_ view: V, _ text: String) -> some View {
        let line = text.components(separatedBy: "\n").first ?? text
        return view.onHover { hovering in
            if hovering {
                hoveredCubeInfo = line
            } else if hoveredCubeInfo == line {
                hoveredCubeInfo = nil
            }
        }
    }
```

- [ ] **Step 2: Wrap the grid in a VStack with the reserved caption line**

Replace `headerUtilities` body:

```swift
    private var headerUtilities: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(34), spacing: 8), count: 5),
                spacing: 8
            ) {
                if case .loaded = app.aiState {
                    stripInfo(reanalyzeChip, "Re-analyze the AI description")
                }
                stripInfo(crossAppCard, crossAppHelp)
                stripInfo(notesCard, notesHelp)
                stripInfo(moneyCard, moneyStripLabel)
                stripInfo(linkCard, linkHelp)
                stripInfo(lockCard, app.isAnalysisLocked
                          ? "Lock — analysis frozen, click to unlock"
                          : "Lock — freeze the analysis")
                stripInfo(favoriteCard, app.isFavorite ? "Favorite — click to unmark" : "Mark as favorite")
                stripInfo(docsCard, docsHelp)
                stripInfo(myAppCard, app.isMyApp
                          ? "My App — you build this, click to unmark"
                          : "Mark as My App (a project you build)")
            }
            Text(hoveredCubeInfo ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 5 * 34 + 4 * 8, alignment: .leading)
        }
        .frame(width: 5 * 34 + 4 * 8)
    }

    /// The money cube's strip line, prefixed so the cube is namable at a glance.
    private var moneyStripLabel: String {
        let state = MoneyCubeState.derive(
            isAppStoreInstall: app.isAppStoreInstall,
            hasLicenseKey: currentLicenseKey?.isEmpty == false,
            isPaidApp: record?.isPaidApp == true,
            hasSubscription: record?.hasSubscription == true,
            renewalNear: subscriptionRenewalIsNear,
            isFreeApp: record?.isFreeApp == true
        )
        return "Money — \(moneyHelp(for: state))"
    }
```

Note: `Text(" ")` (a space, not empty) keeps the line's height reserved — no layout jump.

- [ ] **Step 3: Build and visual check**

Run: `swift build && swift run Sift`
Expected: hover any cube → caption appears instantly under the grid; move off → clears; header height never shifts. Long strings truncate with an ellipsis.

- [ ] **Step 4: Commit**

```bash
git add Sources/AppAudit/Views/AppDetailView.swift
git commit -m "feat: instant hover label strip under the utility cube grid"
```

---

### Task 6: Developer Mode

**Files:**
- Modify: `Sources/AppAudit/Views/SettingsView.swift` (Developer section in `ScanningSettingsTab`)
- Modify: `Sources/AppAudit/Views/AppDetailView.swift` (gate docs + hammer cubes)
- Modify: `Sources/AppAudit/Views/AppRow.swift` (badge, context-menu item, score badge)
- Modify: `Sources/AppAudit/AppAuditApp.swift` (hide My Apps filter command)
- Modify: `Sources/AppAudit/Views/ContentView.swift` (clear filter when leaving dev mode)

**Interfaces:**
- Consumes: `DevModeRules` (Task 2), `viewModel.setFilterMyApps(_:)` (exists at `AppListViewModel.swift:158`).
- Produces: `@AppStorage("developerMode")` read at each site. Nothing later depends on this task.

- [ ] **Step 1: Settings toggle**

In `ScanningSettingsTab` (`SettingsView.swift:294`), add the storage var:

```swift
    @AppStorage("developerMode") private var developerMode = false
```

and a new section after "Directories":

```swift
            Section("Developer") {
                Toggle("Developer Mode", isOn: $developerMode)
                SettingsFooter("Shows the My App tools: the hammer and docs cubes, sidebar hammer badges, and the My Apps filter. Marks are kept when this is off.")
            }
```

- [ ] **Step 2: Gate the detail-view cubes**

In `AppDetailView`, add:

```swift
    @AppStorage("developerMode") private var developerMode = false
```

In `headerUtilities`' grid (as rewritten in Task 5), wrap the last two entries:

```swift
                if developerMode {
                    stripInfo(docsCard, docsHelp)
                    stripInfo(myAppCard, app.isMyApp
                              ? "My App — you build this, click to unmark"
                              : "Mark as My App (a project you build)")
                }
```

- [ ] **Step 3: Gate the sidebar row**

In `AppRow.swift`, add the same `@AppStorage("developerMode")` var to the row view struct, then:

1. The hammer badge (`if app.isMyApp {` around line 50) becomes `if DevModeRules.showsMyAppUI(isMyApp: app.isMyApp, developerMode: developerMode) {`.
2. The score badge call (line ~114) becomes `ScoreBadgeView(state: app.aiState, isMyApp: DevModeRules.showsMyAppUI(isMyApp: app.isMyApp, developerMode: developerMode))`.
3. The context-menu "Mark as My App" button (line ~152 area) gets wrapped in `if developerMode { ... }`.

- [ ] **Step 4: Gate the filter command and clear stale filter**

In `AppAuditApp.swift`, add `@AppStorage("developerMode") private var developerMode = false` to the app struct, and wrap the toggle at lines 102-105:

```swift
                if developerMode {
                    Toggle("Filter: My Apps", isOn: Binding(
                        get: { viewModel.filterMyApps },
                        set: { viewModel.setFilterMyApps($0) }
                    ))
                }
```

In `ContentView.swift`, add `@AppStorage("developerMode") private var developerMode = false` and on the outermost view:

```swift
        .onChange(of: developerMode) { _, enabled in
            viewModel.setFilterMyApps(
                DevModeRules.filterMyApps(current: viewModel.filterMyApps, developerMode: enabled)
            )
        }
```

- [ ] **Step 5: Build and test**

Run: `swift build && swift test`
Expected: clean build, all suites pass (including `MoneyDevRulesTests` from Task 2).

- [ ] **Step 6: Visual check**

Run: `swift run Sift`.
- Default (dev off): 7 cubes, no hammer badges anywhere, no "Filter: My Apps" in the View menu, row context menu has no My App item.
- Settings → Scanning → Developer Mode ON: hammer + docs cubes return, badges return, filter returns, previously marked My Apps show their marks again.
- Turn it ON and leave it on (this machine is the developer machine).

- [ ] **Step 7: Commit**

```bash
git add Sources/AppAudit/Views/SettingsView.swift Sources/AppAudit/Views/AppDetailView.swift Sources/AppAudit/Views/AppRow.swift Sources/AppAudit/AppAuditApp.swift Sources/AppAudit/Views/ContentView.swift
git commit -m "feat: Developer Mode — gate all My App UI behind a settings toggle"
```

---

### Task 7: Full verification + changelog

**Files:**
- Modify: `CHANGELOG.md` (new Unreleased entry, following the file's existing house style)

**Interfaces:**
- Consumes: everything above.
- Produces: a verified, documented feature ready for the next release cut.

- [ ] **Step 1: Full test suite**

Run: `swift test`
Expected: every suite passes, zero failures.

- [ ] **Step 2: Side-build visual pass**

Run: `Scripts/build_sift2.sh` and open the produced Sift2 app (the testing side-build, per the release flow). Walk one app of each kind: an App Store install, a licensed app, a subscribed app, a free-marked app, and a My App (with dev mode on and off). Confirm: money cube face matches state, popover round-trips all fields, label strip is instant, no layout jumps.

- [ ] **Step 3: Changelog entry**

Add at the top of `CHANGELOG.md`, matching the existing entry format (keep the file's own heading/version style — read it first):

- Money cube: license, subscription, and paid/free merged into one cube with a single popover; right-click keeps the quick marks.
- Instant label strip under the utility cubes — hover shows name + state with no tooltip delay.
- Developer Mode (Settings → Scanning): the My App tools (hammer, docs, badges, filter) now hide unless enabled; all marks are preserved.
- Detail header now shows 7 cubes (9 in Developer Mode), down from 10.

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for action-cubes clarity (money cube, label strip, developer mode)"
```

---

## Self-Review Notes

- **Spec coverage:** grid composition → Tasks 4-6; money cube states/popover/context menu → Tasks 1, 3, 4; label strip → Task 5; developer mode incl. filter/badges/score badge → Task 6; testing section → Tasks 1, 2, 7. Precedence refinement (App Store above licensed) documented in Task 1.
- **Deletion safety:** `DetailLicenseKeySheet`, `SubscriptionSheet`, `SubscriptionSheetAction` have no references outside `AppDetailView.swift` (verified by grep); tests do not reference them.
- **Type consistency:** `MoneyCubeState.derive` signature identical in Tasks 1, 4, 5; `DevModeRules` names identical in Tasks 2, 6; draft binding names match the existing `@State` vars.

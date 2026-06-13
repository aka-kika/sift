# App Store Ownership Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show Mac App Store provenance in place of the (nonexistent) license key for App Store apps, let the user optionally mark them Paid, and add `Source` + `Paid` columns to CSV export.

**Architecture:** Reuse the existing `AppInfo.isAppStoreInstall` flag (already set from the `_MASReceipt` file). Add a tested `AppInfo.installSourceLabel` computed property and one `AppRecord.isPaidApp` field. The `licenseKeySection` in `AppDetailView` branches on `app.isAppStoreInstall`: App Store apps render an ownership variant (badge + Paid toggle, no key field, no Touch ID); everything else is unchanged. CSV reads both off the existing per-app `record`.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing. All builds/tests prefixed `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (standalone CLT broken on macOS 27).

---

## Environment note

Prefix every `swift` command: `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`. SourceKit/IDE diagnostics are stale-index noise — only real `swift build`/`swift test` output counts. Baseline suite: 67 tests.

## File Structure

- **Modify** `Sources/AppAudit/Models/AppInfo.swift` — add computed `installSourceLabel` (pure provenance string).
- **Modify** `Sources/AppAudit/Models/AppRecord.swift` — add `isPaidApp: Bool = false` + init default.
- **Modify** `Sources/AppAudit/Views/AppDetailView.swift` — split `licenseKeySection` into a branch over `app.isAppStoreInstall`; add `appStoreOwnershipRowContent`, refactor existing body into `licenseKeyRowContent`, add `togglePaidApp()`.
- **Modify** `Sources/AppAudit/ViewModels/AppListViewModel.swift` — `Source` + `Paid` CSV columns.
- **Modify** `Tests/AppAuditTests/AppAuditTests.swift` — `installSourceLabel` + `isPaidApp` default tests.

## Testing philosophy

Pure logic (`installSourceLabel`, model default) is TDD'd with real assertions. The SwiftUI row variant is verified by `swift build` + manual Sift2 check (no ViewInspector in this project).

---

### Task 1: AppInfo.installSourceLabel (pure logic, TDD)

**Files:**
- Modify: `Sources/AppAudit/Models/AppInfo.swift`
- Test: append a suite to `Tests/AppAuditTests/AppAuditTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to the END of `Tests/AppAuditTests/AppAuditTests.swift`:

```swift
@Suite("Install Source Label")
struct InstallSourceLabelTests {
    private func make(appStore: Bool, sparkle: String?, cask: String?) -> AppInfo {
        AppInfo(
            id: "com.x", name: "X", version: "1", bundleID: "com.x",
            path: "/Applications/X.app", humanReadableDescription: nil,
            sparkleFeedURL: sparkle, isAppStoreInstall: appStore,
            homebrewCaskToken: cask, icon: nil
        )
    }

    @Test("App Store wins over other signals")
    func appStoreWins() {
        #expect(make(appStore: true, sparkle: "https://feed", cask: "x").installSourceLabel == "App Store")
    }

    @Test("Sparkle when only a feed URL")
    func sparkle() {
        #expect(make(appStore: false, sparkle: "https://feed", cask: nil).installSourceLabel == "Sparkle")
    }

    @Test("Homebrew when only a cask token")
    func homebrew() {
        #expect(make(appStore: false, sparkle: nil, cask: "the-cask").installSourceLabel == "Homebrew")
    }

    @Test("Other when no signal")
    func other() {
        #expect(make(appStore: false, sparkle: nil, cask: nil).installSourceLabel == "Other")
    }
}
```

- [ ] **Step 2: Run tests, verify they FAIL**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -5`
Expected: compile error, `value of type 'AppInfo' has no member 'installSourceLabel'`.

- [ ] **Step 3: Add the computed property**

In `Sources/AppAudit/Models/AppInfo.swift`, add this computed property to the `AppInfo` struct (place it after the stored properties / near the existing computed members like the one at line ~146; anywhere inside the struct body is fine):

```swift
    /// Where this app was installed from, for display/export. App Store takes
    /// precedence (a `_MASReceipt` is authoritative); then a Sparkle feed, then
    /// a Homebrew cask; otherwise "Other".
    var installSourceLabel: String {
        if isAppStoreInstall { return "App Store" }
        if sparkleFeedURL != nil { return "Sparkle" }
        if homebrewCaskToken != nil { return "Homebrew" }
        return "Other"
    }
```

- [ ] **Step 4: Run tests, verify they PASS**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`
Expected: 71 tests pass (67 + 4 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Models/AppInfo.swift Tests/AppAuditTests/AppAuditTests.swift
git commit -m "AppInfo: add installSourceLabel (App Store / Sparkle / Homebrew / Other)"
```

---

### Task 2: AppRecord.isPaidApp field

**Files:**
- Modify: `Sources/AppAudit/Models/AppRecord.swift`
- Test: append a suite to `Tests/AppAuditTests/AppAuditTests.swift`

- [ ] **Step 1: Write the failing test**

Append to the END of `Tests/AppAuditTests/AppAuditTests.swift`:

```swift
@Suite("AppRecord Paid Flag")
struct AppRecordPaidTests {
    @Test("A new record is not marked paid")
    func defaultsFalse() {
        let r = AppRecord(bundleID: "com.x", appName: "X", explanation: "",
                          relevanceScore: 0, relevanceReason: "", bestUse: "", ollamaModel: "")
        #expect(r.isPaidApp == false)
    }
}
```

- [ ] **Step 2: Run the test, verify it FAILS**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -5`
Expected: compile error, `value of type 'AppRecord' has no member 'isPaidApp'`.

- [ ] **Step 3: Add the field**

In `Sources/AppAudit/Models/AppRecord.swift`, immediately AFTER the line `var subscriptionEmail: String? = nil` (added by the subscription feature), add:

```swift
    var isPaidApp: Bool = false
```

Then in `init(...)`, immediately AFTER `self.subscriptionEmail = nil`, add:

```swift
        self.isPaidApp = false
```

(Optional with a default → existing SwiftData stores migrate automatically.)

- [ ] **Step 4: Run the test, verify it PASSES**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`
Expected: 72 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Models/AppRecord.swift Tests/AppAuditTests/AppAuditTests.swift
git commit -m "AppRecord: add isPaidApp flag for App Store purchases"
```

---

### Task 3: Adaptive License Key row (App Store ownership variant)

**Files:**
- Modify: `Sources/AppAudit/Views/AppDetailView.swift`

Currently `licenseKeySection` is a single `HStack { ... }` (the key field + Touch-ID controls) followed by `.contentShape`/`.onHover`/`.padding`/`.frame` modifiers. We split it: the existing HStack body moves verbatim into `licenseKeyRowContent`, a new `appStoreOwnershipRowContent` is added, and `licenseKeySection` becomes a `Group` that picks one and applies the shared modifiers.

- [ ] **Step 1: Rename the existing body to `licenseKeyRowContent`**

In `Sources/AppAudit/Views/AppDetailView.swift`, find `private var licenseKeySection: some View {`. It opens with `HStack(spacing: 8) {` and that HStack closes (its matching `}`) right before `.contentShape(Rectangle())`. Change ONLY the declaration line and the trailing modifiers:

Change the opening:
```swift
    private var licenseKeySection: some View {
        HStack(spacing: 8) {
```
to:
```swift
    private var licenseKeyRowContent: some View {
        HStack(spacing: 8) {
```

And change the tail — replace:
```swift
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                licenseHovered = hovering
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
```
with just the HStack's closing brace + property close:
```swift
        }
    }
```

So `licenseKeyRowContent` is now exactly the original HStack with no outer modifiers.

- [ ] **Step 2: Add `appStoreOwnershipRowContent` and the new `licenseKeySection`**

Immediately BEFORE `licenseKeyRowContent` (or right after — order doesn't matter, but keep them adjacent), add the new section wrapper and the ownership variant:

```swift
    private var licenseKeySection: some View {
        Group {
            if app.isAppStoreInstall {
                appStoreOwnershipRowContent
            } else {
                licenseKeyRowContent
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                licenseHovered = hovering
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appStoreOwnershipRowContent: some View {
        HStack(spacing: 8) {
            utilityChip("bag.fill", tint: .blue)
            Text("Mac App Store")
                .font(.subheadline.weight(.medium))
            Text("Tied to your Apple ID")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            if record?.isPaidApp == true {
                Text("Paid")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.14), in: Capsule())
            }
            Spacer()
            Button {
                togglePaidApp()
            } label: {
                Image(systemName: record?.isPaidApp == true ? "checkmark.seal.fill" : "checkmark.seal")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(record?.isPaidApp == true ? "Marked as paid — click to unmark" : "Mark as paid")
            .opacity(licenseHovered ? 1 : 0)
        }
    }
```

- [ ] **Step 3: Add the `togglePaidApp()` helper**

Next to `ensureRecord()`/`saveRecord()` in `AppDetailView`, add:

```swift
    private func togglePaidApp() {
        let ensured = ensureRecord()
        ensured.isPaidApp.toggle()
        saveRecord()
    }
```

- [ ] **Step 4: Build + test**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build 2>&1 | tail -8`
Expected: `Build complete!` no errors.
Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`
Expected: 72 tests pass.

Pitfall: `licenseKeyRowContent` must still reference all the same state it did before (`currentLicenseKey`, `isKeyRevealed`, `keyCopied`, `licenseHovered`, `record`, etc.) — only the wrapping changed, no inner edits. If the build complains about `licenseHovered` being unused, it isn't (the Group uses it).

- [ ] **Step 5: Manual visual verification in Sift2**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash Scripts/build_sift2.sh 2>&1 | tail -1`
Then in Sift2:
- On a **non-App-Store** app (e.g. a Homebrew/Sparkle app or Sift itself): the License Key row is unchanged — key field, reveal/copy/edit behind Touch ID.
- On an **App Store** app (e.g. a known MAS install): the row shows the 🛍️ `bag.fill` blue chip, "Mac App Store", "Tied to your Apple ID", no key field. Hover reveals a seal button; clicking it adds a green "Paid" badge and switches the seal to filled; clicking again unmarks. No Touch ID prompt.
- Quit & relaunch → Paid state persists.

- [ ] **Step 6: Commit**

```bash
git add Sources/AppAudit/Views/AppDetailView.swift
git commit -m "AppDetailView: App Store apps show ownership row with Paid toggle"
```

---

### Task 4: CSV Source + Paid columns

**Files:**
- Modify: `Sources/AppAudit/ViewModels/AppListViewModel.swift`

- [ ] **Step 1: Expand the header**

In `exportCSV()`, the header currently ends:
```swift
            "Subscription", "Sub Price", "Sub Cycle", "Sub Renewal", "Notes"
```
Change to:
```swift
            "Subscription", "Sub Price", "Sub Cycle", "Sub Renewal",
            "Source", "Paid", "Notes"
```

- [ ] **Step 2: Expand the row**

In the row-mapping closure, the returned array currently ends:
```swift
                record?.subscriptionRenewalDate.map { SubscriptionMath.isoDate($0) } ?? "",
                record?.notes ?? ""
```
Change to:
```swift
                record?.subscriptionRenewalDate.map { SubscriptionMath.isoDate($0) } ?? "",
                app.installSourceLabel,
                record?.isPaidApp == true ? "yes" : "",
                record?.notes ?? ""
```

(`app` and `record` are both already in scope in this closure. `Source` is always populated; `Paid` is `yes` only when marked, blank otherwise.)

- [ ] **Step 3: Build + test + alignment check**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build 2>&1 | tail -3`
Expected: `Build complete!`.
Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`
Expected: 72 tests pass.
Manually confirm the header gained exactly 2 entries (Source, Paid) and the row gained exactly 2 — both arrays were 15, now 17, with Source/Paid inserted at the same position (just before Notes). State both counts in the report to prove alignment.

- [ ] **Step 4: Commit**

```bash
git add Sources/AppAudit/ViewModels/AppListViewModel.swift
git commit -m "CSV: export install Source and Paid columns"
```

---

### Task 5: Full verification

- [ ] **Step 1: Run the whole suite**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`
Expected: 72 tests (67 baseline + 4 installSourceLabel + 1 isPaidApp), all green.

- [ ] **Step 2: Build Sift2 + end-to-end manual pass**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash Scripts/build_sift2.sh 2>&1 | tail -1`
Re-walk Task 3 Step 5. Plus: export a CSV and confirm `Source` shows App Store / Sparkle / Homebrew / Other correctly across apps, and `Paid` is `yes` only for App Store apps you marked.

- [ ] **Step 3: Final commit if any fixups were needed**

```bash
git add -A
git commit -m "App Store ownership: verification fixups" || echo "nothing to commit"
```

This feature does not bump the version or cut a release — it folds into the next tagged release alongside the subscription feature.

---

## Self-Review

**Spec coverage:**
- Provenance auto-shown where the key row sits → Task 3 (`appStoreOwnershipRowContent`). ✓
- Reuse `isAppStoreInstall`, no scanner change → Tasks 1 & 3 read the existing flag. ✓
- Optional Paid mark, defaults off → Task 2 (`isPaidApp = false`) + Task 3 (`togglePaidApp`). ✓
- No key field / no Touch ID for App Store apps → Task 3 variant omits both. ✓
- "Tied to your Apple ID" caption + green Paid badge → Task 3. ✓
- `bag.fill` blue chip → Task 3. ✓
- CSV `Source` (auto, via `installSourceLabel`) + `Paid` → Tasks 1 & 4. ✓
- `installSourceLabel` testable in isolation → Task 1 (4 tests). ✓
- Non-goals (no price, no Vault entry, App-Store-only Paid, detail-only, no Touch ID) → nothing added beyond the above. ✓

**Placeholder scan:** No TBD/TODO; every step has real code + exact commands.

**Type consistency:** `installSourceLabel` (String, values "App Store"/"Sparkle"/"Homebrew"/"Other") used identically in Tasks 1 & 4. `isPaidApp` (Bool) defined in Task 2, read in Tasks 3 & 4, toggled in Task 3. `appStoreOwnershipRowContent` / `licenseKeyRowContent` / `togglePaidApp` names consistent within Task 3. The Task 3 refactor preserves all existing license-key state references (only the wrapping `Group` and outer modifiers move).

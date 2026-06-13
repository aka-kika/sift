# Style → Profile (global) + Vault Purchases Ledger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Style note to the Profile tab and make it shape every engine's analysis; turn the License Vault into a purchases ledger that also lists paid App Store apps as keyless rows.

**Architecture:** Part A threads optional `styleNotes` through the shared `AppAnalysisPrompt.build` (for Ollama/cloud) and switches `AppleIntelligenceService` to a new global `analysisStyleNotes` UserDefaults key, with a one-time migration from the old `appleIntelligenceStyleNotes`; the Settings field relocates from Models to Profile. Part B broadens the Vault's `@Query` to `hasLicenseKey || isPaidApp` and adds a keyless row variant. No SwiftData schema changes.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing. Builds prefixed `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (standalone CLT broken on macOS 27).

---

## Environment note

Prefix every `swift` command: `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`. SourceKit/IDE diagnostics are stale-index noise — only real `swift build`/`swift test` output counts. Baseline suite: 73 tests.

## File Structure

- **Part A:** `AppAnalysisPrompt.swift` (styleNotes param + helper), `AppleIntelligenceService.swift` (key rename), `OllamaService.swift`/`OpenAIService.swift`/`AnthropicService.swift` (pass styleNotes), `AppListViewModel.swift` + `ContentView.swift` (migration), `SettingsView.swift` (remove from Models, add to Profile), `AppAuditTests.swift` (prompt test).
- **Part B:** `LicenseVaultView.swift` (query + row variant + unmark).

---

### Task 1 (Part A): AppAnalysisPrompt gains a styleNotes parameter (TDD)

**Files:**
- Modify: `Sources/AppAudit/Services/AppAnalysisPrompt.swift`
- Test: append a suite to `Tests/AppAuditTests/AppAuditTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to the END of `Tests/AppAuditTests/AppAuditTests.swift`:

```swift
@Suite("Analysis Prompt Style Notes")
struct AnalysisPromptStyleNotesTests {
    private var app: AppInfo {
        AppInfo(id: "com.x", name: "X", version: "1", bundleID: "com.x",
                path: "/Applications/X.app", humanReadableDescription: nil,
                sparkleFeedURL: nil, isAppStoreInstall: false, icon: nil)
    }

    @Test("Style notes are appended when provided")
    func appended() {
        let prompt = AppAnalysisPrompt.build(app: app, profile: .generic(),
                                             includeResponseFormat: false,
                                             styleNotes: "Mention alternatives.")
        #expect(prompt.contains("Additional style notes from the user (follow them):"))
        #expect(prompt.contains("Mention alternatives."))
    }

    @Test("No style block when notes are empty or whitespace")
    func emptyOmits() {
        let prompt = AppAnalysisPrompt.build(app: app, profile: .generic(),
                                             includeResponseFormat: false,
                                             styleNotes: "   ")
        #expect(!prompt.contains("Additional style notes"))
    }
}
```

- [ ] **Step 2: Run tests, verify they FAIL**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -5`
Expected: compile error — `build` has no `styleNotes:` parameter.

- [ ] **Step 3: Add the parameter + helper**

In `Sources/AppAudit/Services/AppAnalysisPrompt.swift`, change the `build` signature from:

```swift
    static func build(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil, linkEvidence: String? = nil, includeResponseFormat: Bool) -> String {
```
to (add a trailing defaulted `styleNotes`):
```swift
    static func build(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil, linkEvidence: String? = nil, includeResponseFormat: Bool, styleNotes: String = "") -> String {
```

Immediately after the `let responseFormat = ...` assignment inside `build` (before the final `return """`), add:

```swift
        let trimmedNotes = styleNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let styleBlock = trimmedNotes.isEmpty
            ? ""
            : "\n\nAdditional style notes from the user (follow them):\n\(trimmedNotes)"
```

Then in the returned multi-line string, change the final line from:

```swift
        1 = No overlap; safe to uninstall
        """
```
to:
```swift
        1 = No overlap; safe to uninstall\(styleBlock)
        """
```

Also add this static helper to the `AppAnalysisPrompt` enum (e.g. right after the `build` function):

```swift
    /// The user's global analysis style notes from Settings (Profile tab),
    /// trimmed. Empty when unset. Passed into `build(...)` for the non-Apple
    /// engines; Apple Intelligence reads the same key directly.
    static var currentStyleNotes: String {
        (UserDefaults.standard.string(forKey: "analysisStyleNotes") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
```

- [ ] **Step 4: Run tests, verify they PASS**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`
Expected: 75 tests pass (73 + 2 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Services/AppAnalysisPrompt.swift Tests/AppAuditTests/AppAuditTests.swift
git commit -m "AppAnalysisPrompt: optional global styleNotes appended to the prompt"
```

---

### Task 2 (Part A): Wire styleNotes into every engine + migrate the key

**Files:**
- Modify: `Sources/AppAudit/Services/AppleIntelligenceService.swift`
- Modify: `Sources/AppAudit/Services/OllamaService.swift`, `OpenAIService.swift`, `AnthropicService.swift`
- Modify: `Sources/AppAudit/ViewModels/AppListViewModel.swift`, `Sources/AppAudit/Views/ContentView.swift`

- [ ] **Step 1: Apple Intelligence reads the new key**

In `Sources/AppAudit/Services/AppleIntelligenceService.swift`, the `styleNotes` computed property reads `"appleIntelligenceStyleNotes"`. Change that key to `"analysisStyleNotes"`:

```swift
    private var styleNotes: String {
        (UserDefaults.standard.string(forKey: "analysisStyleNotes") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
```

(The surrounding `instructionsText` append logic is unchanged.)

- [ ] **Step 2: Pass styleNotes at the three non-AI build sites**

`OpenAIService.swift` — change:
```swift
        let prompt = AppAnalysisPrompt.build(app: app, profile: profile, appURL: appURL, linkEvidence: linkEvidence, includeResponseFormat: true)
```
to:
```swift
        let prompt = AppAnalysisPrompt.build(app: app, profile: profile, appURL: appURL, linkEvidence: linkEvidence, includeResponseFormat: true, styleNotes: AppAnalysisPrompt.currentStyleNotes)
```

`AnthropicService.swift` — make the identical change to its `AppAnalysisPrompt.build(...)` call (add `, styleNotes: AppAnalysisPrompt.currentStyleNotes` before the closing paren).

`OllamaService.swift` — its call (around line 72) is multi-line:
```swift
        let prompt = AppAnalysisPrompt.build(
            app: app,
            profile: profile,
            appURL: appURL,
            linkEvidence: linkEvidence,
            includeResponseFormat: true
        )
```
Add the `styleNotes` argument:
```swift
        let prompt = AppAnalysisPrompt.build(
            app: app,
            profile: profile,
            appURL: appURL,
            linkEvidence: linkEvidence,
            includeResponseFormat: true,
            styleNotes: AppAnalysisPrompt.currentStyleNotes
        )
```
(If the actual call's argument set differs slightly, just insert `styleNotes: AppAnalysisPrompt.currentStyleNotes` as the final argument.)

- [ ] **Step 3: One-time migration of the old key**

In `Sources/AppAudit/ViewModels/AppListViewModel.swift`, next to `migrateDefaultProfileToAutomatic()`, add:

```swift
    /// One-time: the Style note moved from an Apple-Intelligence-only key to a
    /// global `analysisStyleNotes` key. Carry any existing value across so it
    /// keeps working for every engine. No-op once the new key exists.
    func migrateStyleNotesKey() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "analysisStyleNotes") == nil else { return }
        let old = (defaults.string(forKey: "appleIntelligenceStyleNotes") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !old.isEmpty {
            defaults.set(old, forKey: "analysisStyleNotes")
        }
    }
```

In `Sources/AppAudit/Views/ContentView.swift`, find where `viewModel.migrateDefaultProfileToAutomatic()` is called (around line 39) and add a call right after it:

```swift
            viewModel.migrateDefaultProfileToAutomatic()
            viewModel.migrateStyleNotesKey()
```

- [ ] **Step 4: Build + test**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build 2>&1 | tail -5`
Expected: `Build complete!`.
Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`
Expected: 75 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Services/AppleIntelligenceService.swift Sources/AppAudit/Services/OllamaService.swift Sources/AppAudit/Services/OpenAIService.swift Sources/AppAudit/Services/AnthropicService.swift Sources/AppAudit/ViewModels/AppListViewModel.swift Sources/AppAudit/Views/ContentView.swift
git commit -m "Style notes: global analysisStyleNotes key feeds every engine, migrated from the old key"
```

---

### Task 3 (Part A): Move the Style field from Models to Profile

**Files:**
- Modify: `Sources/AppAudit/Views/SettingsView.swift`

- [ ] **Step 1: Remove the Style field from the Models tab**

In `AnalysisSettingsTab`, delete the now-unused storage line:
```swift
    @AppStorage("appleIntelligenceStyleNotes") private var appleIntelligenceStyleNotes = ""
```

Then in `appleIntelligenceConfig`, delete the Style block. Find:
```swift
        if appleIntelligenceUsePCC, let pccStatus {
            SettingsFooter(pccStatus)
        }

        Divider()

        HStack(alignment: .top) {
            Text("Style")
                .frame(width: 64, alignment: .leading)
            TextField("e.g. Mention alternatives. Keep best-use under 12 words.", text: $appleIntelligenceStyleNotes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .controlSize(.small)
        }

        SettingsFooter("Appended to the analysis instructions. Experiment freely — applies to the next re-analyze.")
    }
```
Replace it with just the PCC-status block and the closing brace:
```swift
        if appleIntelligenceUsePCC, let pccStatus {
            SettingsFooter(pccStatus)
        }
    }
```

- [ ] **Step 2: Add the Style field to the Profile tab**

In `ProfileSettingsTab`, add the storage property after the existing `@AppStorage` lines:
```swift
    @AppStorage("analysisStyleNotes") private var styleNotes = ""
```

Then add a new `Section` to the `Form`, after the existing `Section { Button("Clear Override") ... }` block (i.e. as the last section before the `Form` closes):
```swift
            Section("Analysis style") {
                TextField("e.g. Mention alternatives. Keep best-use under 12 words.", text: $styleNotes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)

                SettingsFooter("Appended to every analysis, whichever engine runs it. Applies to the next re-analyze.")
            }
```

- [ ] **Step 3: Give the Profile tab room for the new section**

In `SettingsView.tabHeight`, change the `.profile` case from `300` to `380`:
```swift
        case .profile: return 380
```

- [ ] **Step 4: Build**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build 2>&1 | tail -3`
Expected: `Build complete!`. (No reference to `appleIntelligenceStyleNotes` should remain in `SettingsView.swift` — grep to confirm: `grep -n appleIntelligenceStyleNotes Sources/AppAudit/Views/SettingsView.swift` returns nothing.)

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Views/SettingsView.swift
git commit -m "Settings: move Style note from Models to Profile as a global analysis style"
```

---

### Task 4 (Part B): Vault includes paid App Store apps as keyless rows

**Files:**
- Modify: `Sources/AppAudit/Views/LicenseVaultView.swift`

- [ ] **Step 1: Broaden the query + rename**

Change the `@Query`:
```swift
    @Query(filter: #Predicate<AppRecord> { $0.hasLicenseKey }, sort: \AppRecord.appName)
    private var keyedRecords: [AppRecord]
```
to:
```swift
    @Query(filter: #Predicate<AppRecord> { $0.hasLicenseKey || $0.isPaidApp }, sort: \AppRecord.appName)
    private var ownedRecords: [AppRecord]
```

Update the two computed properties to use the new name:
```swift
    private var installedRecords: [AppRecord] {
        ownedRecords.filter { installedBundleIDs.contains($0.bundleID) }
    }

    private var missingRecords: [AppRecord] {
        ownedRecords.filter { !installedBundleIDs.contains($0.bundleID) }
    }
```

And update the empty-state check `if keyedRecords.isEmpty {` → `if ownedRecords.isEmpty {`.

- [ ] **Step 2: Update header + empty-state copy**

Change the header subtitle:
```swift
                    Text("All your license keys in one place")
```
to:
```swift
                    Text("Everything you've bought in one place")
```

Change the empty-state `ContentUnavailableView`:
```swift
                ContentUnavailableView {
                    Label("No License Keys Yet", systemImage: "key.horizontal")
                } description: {
                    Text("Save a license key to any app — from its detail panel or right-click menu — and it appears here. Keys for apps you later uninstall stay safe in this vault.")
                }
```
to:
```swift
                ContentUnavailableView {
                    Label("Nothing Bought Yet", systemImage: "bag")
                } description: {
                    Text("Save a license key to an app, or mark a Mac App Store app as paid, and it appears here. Items stay in this vault even after you uninstall the app.")
                }
```

- [ ] **Step 3: Branch `vaultRow` for keyless paid apps**

Replace the whole `vaultRow(_:)` body. The icon-fallback and the trailing controls become variant-aware:

```swift
    private func vaultRow(_ record: AppRecord) -> some View {
        HStack(spacing: 10) {
            if let data = record.iconPNG, let icon = NSImage(data: data) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .cornerRadius(6)
            } else {
                Image(systemName: record.hasLicenseKey ? "key.horizontal.fill" : "bag.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(record.appName).font(.body)
                Text(record.bundleID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let email = record.licenseEmail, !email.isEmpty {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if record.hasLicenseKey {
                if copiedBundleID == record.bundleID {
                    Text("Copied")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    copyKey(for: record.bundleID)
                } label: {
                    Label("Copy Key", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                Button(role: .destructive) {
                    deleteKey(for: record)
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .help("Remove this key from the vault")
            } else {
                Text("Mac App Store · Paid")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.14), in: Capsule())
                Button(role: .destructive) {
                    unmarkPaid(record)
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .help("Remove from your purchases")
            }
        }
        .padding(.vertical, 2)
    }
```

(A record with a key takes the key variant even if also `isPaidApp` — keys win.)

- [ ] **Step 4: Add `unmarkPaid`**

Next to `deleteKey(for:)`, add:
```swift
    private func unmarkPaid(_ record: AppRecord) {
        record.isPaidApp = false
        try? modelContext.save()
    }
```

- [ ] **Step 5: Build + test**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build 2>&1 | tail -3`
Expected: `Build complete!`.
Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`
Expected: 75 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/AppAudit/Views/LicenseVaultView.swift
git commit -m "Vault: list paid App Store apps as keyless 'Mac App Store · Paid' rows"
```

---

### Task 5: Full verification

- [ ] **Step 1: Full suite**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`
Expected: 75 tests pass.

- [ ] **Step 2: Build Sift2 + manual pass**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash Scripts/build_sift2.sh 2>&1 | tail -1`
Then in Sift2:
- **Settings → Models:** no Style field anymore. **Settings → Profile:** a new "Analysis style" field at the bottom; the Profile tab isn't clipped at height 380.
- Type a style note in Profile, re-analyze an app, and confirm it still works (the note shapes output regardless of engine; not visually asserted, just no crash/regression).
- **Vault (⌘⇧L):** mark an App Store app as Paid (detail panel), open the Vault → it appears as a keyless "Mac App Store · Paid" row in the right Installed / No longer installed section, with a trash that unmarks it (not a key delete). License-key apps still show Copy Key.

- [ ] **Step 3: Final commit if any fixups were needed**

```bash
git add -A
git commit -m "Style/Vault: verification fixups" || echo "nothing to commit"
```

This folds into the next tagged release alongside the earlier work.

---

## Self-Review

**Spec coverage:**
- Part A: Style relocated to Profile → Task 3. Global key `analysisStyleNotes` → Tasks 1–3. Migration → Task 2 Step 3. Wired into AI (key rename) + Ollama/cloud (build param) → Tasks 1–2. Prompt test → Task 1. ✓
- Part B: query broadened `hasLicenseKey || isPaidApp` → Task 4 Step 1. Keyless "Mac App Store · Paid" row with unmark, no copy → Task 4 Steps 3–4. Installed/missing split unchanged, key-precedence defined → Task 4. Empty-state/header copy → Task 4 Step 2. ✓
- Non-goals (no price, no CSV change, no change to how isPaidApp is set) → nothing added beyond the above. ✓

**Placeholder scan:** No TBD/TODO; every code step shows real code. The Ollama call-site note ("if the argument set differs, insert as final argument") is a robustness instruction, not a placeholder — the exact current call is shown.

**Type consistency:** `styleNotes` param (defaulted `String`) on `build` is defined in Task 1 and passed in Task 2; `AppAnalysisPrompt.currentStyleNotes` defined in Task 1, used in Task 2. The `analysisStyleNotes` key string is identical across `AppAnalysisPrompt.currentStyleNotes`, `AppleIntelligenceService`, the migration, and the Profile `@AppStorage`. `ownedRecords` rename is applied consistently across query, `installedRecords`, `missingRecords`, and the empty check in Task 4. `unmarkPaid`/`deleteKey`/`copyKey` names consistent.

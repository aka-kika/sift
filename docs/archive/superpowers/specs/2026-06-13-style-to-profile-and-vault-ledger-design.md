# Sift — Style → Profile (global) + Vault as Purchases Ledger

**Date:** 2026-06-13
**Status:** Approved, ready for implementation plan
**Author:** Veronica Loren (aka-kika) + Claude

Two small, independent polish items decided together.

---

## Part A — Move the Style field to Profile and make it global

### Problem
The "Style" note (free-text guidance appended to analysis instructions) lives in
the Models tab under Apple Intelligence and is wired **only** into
`AppleIntelligenceService` (it reads `UserDefaults` key
`appleIntelligenceStyleNotes`). So it's an engine-specific knob sitting in engine
config, even though it expresses a *preference* about how analyses should read.
It also doesn't affect Ollama or the cloud engines at all.

### Goal
- Relocate the Style field to the **Profile** tab (`ProfileSettingsTab`), next to
  the workflow profile — where output preferences belong.
- Make it **global**: the notes feed **every** engine's prompt, not just Apple
  Intelligence.
- Preserve any existing value (migrate the old key).

### Design
- **New storage key:** `analysisStyleNotes` (replaces `appleIntelligenceStyleNotes`
  as the live key).
- **One-time migration:** on launch, if `analysisStyleNotes` is unset and
  `appleIntelligenceStyleNotes` has a non-empty value, copy it across (mirrors the
  existing `migrateDefaultProfileToAutomatic()` one-shot pattern in
  `AppListViewModel`, invoked from `ContentView`).
- **Wiring — Apple Intelligence:** `AppleIntelligenceService.styleNotes` reads the
  new `analysisStyleNotes` key (same append logic, unchanged wording).
- **Wiring — Ollama/cloud:** `AppAnalysisPrompt.build(...)` gains a defaulted
  `styleNotes: String = ""` parameter; when non-empty it appends the same
  "Additional style notes from the user (follow them):\n<notes>" block it uses for
  Apple Intelligence. The view-model call sites that build prompts for the non-AI
  engines pass the trimmed `analysisStyleNotes` value. The defaulted parameter
  keeps existing `AppAnalysisPrompt.build` tests compiling unchanged.
- **UI:** remove the Style `HStack` + its footer from `appleIntelligenceConfig` in
  `SettingsView`. Add a "Style" field (same `TextField(axis: .vertical)`,
  2–4 lines, + footer) to `ProfileSettingsTab`, bound to
  `@AppStorage("analysisStyleNotes")`. Footer reworded to be engine-neutral, e.g.
  "Appended to every analysis, whichever engine runs it. Applies to the next
  re-analyze."
- The now-unused `@AppStorage("appleIntelligenceModel")` left by the earlier
  declutter stays as-is (out of scope); the `appleIntelligenceStyleNotes`
  `@AppStorage` is removed from `SettingsView` (its value lives on only through
  the migration).

### Testing
- **`AppAnalysisPrompt.build` test:** with a non-empty `styleNotes`, the built
  prompt contains the notes and the "Additional style notes" lead-in; with empty
  notes, the prompt is unchanged from today (regression guard). Deterministic —
  pure function.
- Migration + Profile field verified by build + manual (consistent with untested
  Settings views).

---

## Part B — Vault includes paid App Store apps (keyless ledger)

### Problem
The License Vault (`LicenseVaultView`) queries `@Query(filter: hasLicenseKey)`, so
paid App Store apps — which have `isPaidApp == true` but no key — never appear.
The user wants the Vault to be the single "what I've bought" record.

### Goal
Turn the Vault from a key locker into a purchases ledger: show license-key apps
**and** paid App Store apps, the latter as keyless informational rows, keeping the
existing Installed / No longer installed split.

### Design
- **Broaden the query:** `@Query(filter: #Predicate<AppRecord> { $0.hasLicenseKey
  || $0.isPaidApp })`. Rename the bound array (e.g. `keyedRecords` →
  `ownedRecords`) and any "no keys yet" empty-state copy to reflect purchases.
- **Installed / No longer installed** split is unchanged (it keys off whether the
  bundle is currently installed, not off the key).
- **Row variants** in `vaultRow(_:)`:
  - **Has a license key** (`hasLicenseKey == true`): the existing row — icon, name,
    bundleID, registered email, Copied indicator, copy + delete. Unchanged.
  - **Paid App Store, no key** (`!hasLicenseKey && isPaidApp`): a keyless row —
    icon, name, bundleID, and a green **"Mac App Store · Paid"** badge in place of
    the key/copy controls. A trailing remove control that **unmarks paid**
    (`isPaidApp = false`, save) rather than deleting a key. No copy button, no key
    reveal. (No email — paid App Store apps don't capture one.)
- A record that somehow has *both* a key and isPaidApp shows the key variant (keys
  take precedence) — unlikely but defined.
- Empty-state copy updated to mention both: keys and paid App Store apps.

### Testing
- Pure-UI Vault change — verified by build + manual in Sift2 (mark an App Store
  app Paid → it appears in the Vault as a keyless "Mac App Store · Paid" row;
  uninstalling such an app moves it to "No longer installed"; remove unmarks it).
- Existing suite stays green.

---

## Affected Files

- **Part A:** `Sources/AppAudit/Services/AppAnalysisPrompt.swift` (styleNotes param),
  `Sources/AppAudit/Services/AppleIntelligenceService.swift` (key rename),
  `Sources/AppAudit/ViewModels/AppListViewModel.swift` (migration + pass styleNotes
  at non-AI build sites), `Sources/AppAudit/Views/SettingsView.swift` (remove from
  Models, add to Profile), `Tests/AppAuditTests/AppAuditTests.swift` (prompt test).
- **Part B:** `Sources/AppAudit/Views/LicenseVaultView.swift` (query + row variant).

## Non-Goals

- No price/spend tracking for paid App Store apps (the receipt doesn't expose it).
- No CSV change (Source + Paid columns already cover provenance/paid).
- No change to how `isPaidApp` is set (still the detail-panel toggle / context menu).

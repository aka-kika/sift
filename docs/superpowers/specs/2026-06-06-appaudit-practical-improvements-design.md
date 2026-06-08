# AppAudit Practical Improvements — Design

**Date:** 2026-06-06
**Status:** Approved design, pending spec review
**Branch:** `claude/jolly-poincare-38dcc2`

## Context

AppAudit is a native SwiftUI / SwiftData macOS app that audits installed apps,
analyzes them with a local LLM (Ollama), tracks updates, stores license keys in
the Keychain, and keeps notes. The owner uses it heavily and wants it to be more
practical and useful day to day. This pass focuses on correctness, trust, and a
calmer UI. Public release (GitHub Releases) and re-testing happen **at the end**,
after the app feels right — not as a gating concern up front.

## Goals

1. Stop destroying existing analyses when the Ollama model changes.
2. Add an explicit, opt-in bulk re-analyze.
3. Make license-key storage demonstrably safe (no lingering plaintext).
4. Keep a usable record of license keys for apps that have been uninstalled.
5. Add CSV export of the audit (without license keys).
6. Reduce memory/CPU footprint during background AI analysis.
7. Declutter the app detail panel (recommendation-first).
8. Remove features that add weight without value.

## Non-Goals (explicitly out of scope)

- **No "no-AI" provider mode.** AI (Ollama) remains required for analysis.
- **No manual vault entry.** The license vault only retains keys AppAudit already
  recorded for apps that were later uninstalled.
- **No license keys in CSV export**, in any form, including masked.
- No new analysis providers; Apple Intelligence is being *removed*, not extended.

## Decisions (from brainstorming)

| Topic | Decision |
|---|---|
| Model change → existing analyses | Keep them. Prompt once per scan to re-analyze; never auto-wipe. |
| Bulk re-analyze | Yes — explicit action + the model-change banner button. |
| No-AI mode | Dropped. AI stays required. |
| License vault | Auto-retain only (uninstalled apps that had a key). No manual add. |
| CSV export | Full audit data, **no** license keys. |
| Trim | Remove Apple Intelligence provider; remove suggested-link approval flow; fold My Apps & Favorites from sorts into filters. |
| "Light" | Prioritize low memory/CPU during background analysis. |
| Top UX fix | Declutter the detail panel → Option A (recommendation-first). |

---

## Status (2026-06-06)

**Shipped: all spec items (1–14).** Items 1 (no auto-wipe on model change + drift
banner), 2 (bulk re-analyze), 3 (license hardening), 4 (License Vault), 5 (CSV
export), 6 (lower enrichment concurrency 4→2), 7 (detail-panel redesign, Option A),
8 (trims), and 9–14 (subscription marker, de-hedged prompt, Settings size,
Last-Used sort, side-build isolation, Ollama API key). **Remaining:** none —
ready for release (version bump + signed/notarized DMG + GitHub release).

### Item 15 — Cloud providers: Anthropic + OpenAI (shipped 2026-06-06)
- `AnalysisProviderKind` re-expanded to `.ollama / .anthropic / .openAI`. Per-provider
  model + API-key UserDefaults keys; model identifier is `provider:model`.
- `AnalysisService` protocol + shared `AnalysisResult` / `ModelFetchResult`.
  `OllamaService` conforms (and gained `fetchModels()`); new `AnthropicService`
  (Messages API, `x-api-key`) and `OpenAIService` (Chat Completions, `Bearer`).
  All share the prompt and `OllamaService.parseAnalysis`.
- `enrichSingle` routes to the selected provider's service.
- Settings → Models: provider picker + per-provider config. Cloud providers show an
  API-key field and a **fetched** model picker (`GET /v1/models`). Keys live in app
  preferences (per the decision — avoids the side-build's Keychain prompts).
- OpenRouter was offered but not included this round.

### Item 16 — License Vault in the menu bar (shipped 2026-06-06)
`showingVault` moved onto the view model (app-wide). Presented by `AppListView`;
openable from the toolbar ⋯ menu **and** the menu bar (**File → License Vault…**,
⇧⌘L). Fixes discoverability — the vault was previously only in the toolbar ⋯.

### Item 8 — Trims (shipped 2026-06-06)
- **8a Remove Apple Intelligence.** `AnalysisProviderKind` collapsed to a single
  `.ollama` case (enum kept for stored-pref/cache-id stability);
  `AppleIntelligenceService.swift` deleted; the provider branch removed from
  `enrichSingle`; the Settings provider picker + availability check removed (the
  Models tab is now Ollama-only).
- **8b Drop the link-approval flow.** The App Link is a plain editable field. A
  resolved suggestion (still stored in `suggestedAppURL`) only **pre-fills the
  editor** and takes effect when the user saves — no green-check approve button, no
  "Suggested:" pseudo-link, no silent auto-commit. The row shows a quiet
  "suggestion available" hint when one exists.
- **8c My Apps / Favorites → filters.** `SortOrder` is now Relevance / Updates /
  Last Used / Name. My Apps and Favorites are filter toggles (toolbar filter menu)
  applied on top of the sort, via `filterMyApps` / `filterFavorites`.

### Item 5 — CSV export (shipped 2026-06-06)
`CSVExporter` (pure, RFC-4180 quoting, CRLF) + `AppListViewModel.exportCSV()` build
the full audit (Name, Bundle ID, Version, Score, Recommendation, Explanation,
Update Status, My App, Favorite, Subscription, Notes) sorted by name —
**no license keys**. Sidebar ⋯ menu → "Export to CSV…" opens an `NSSavePanel`
(default `AppAudit-YYYY-MM-DD.csv`). Unit-tested quoting + structure.

### Item 3 — License-key hardening (shipped 2026-06-06)
- Keychain writes now set `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
  (device-bound, not iCloud-synced).
- `LicenseKeyStore.migrateLegacyKey(_:bundleID:)` moves a legacy plaintext value
  into the Keychain only when no secure key exists (never overwrites).
- `AppListViewModel.migrateLegacyLicenseKeys()` runs a one-time launch sweep
  (UserDefaults-gated) over all records, purging any lingering plaintext into the
  Keychain and nulling `AppRecord.licenseKey`. Reads the owning app's own items,
  so it does not prompt. Unit-tested migration behavior.

### Item 4 — License Vault (shipped 2026-06-06)
- `AppRecord.hasLicenseKey` (additive) tracks whether a key is stored, set on
  save/delete and reconciled at launch via `AppListViewModel.syncLicenseFlags()`
  (reads the owning app's own Keychain items — no prompts).
- `LicenseKeyStore.hasKey(bundleID:)` and `CacheService.allRecords()` support it.
- `LicenseVaultView` (sheet from the sidebar ⋯ menu → "License Vault…") lists
  records with a key whose app is **not currently installed**: app name, bundle ID,
  **Copy Key** (reads the secret on demand), and **Delete** (removes the Keychain
  item + clears the flag). Records already survive uninstalls, so no data plumbing
  was needed beyond the flag.

### Item 14 — Ollama API key for cloud models (shipped 2026-06-06)
Settings → Models gains an **API Key** field (`@AppStorage "ollamaApiKey"`). When
set, `OllamaService` and the model-fetch call send it as `Authorization: Bearer`,
enabling ollama.com cloud models (set Base URL to `https://ollama.com`). Blank = a
local server as before. Stored in app preferences (not Keychain) to avoid the
ad-hoc side-build's Keychain prompts.

### Item 7 — Detail-panel redesign (shipped 2026-06-06)
Reworked `AppDetailView` to the approved Option A layout:
- **Header:** icon, name · version inline, small tag badges (favorite/My App/
  subscription/lock), bundle ID, and a compact **update pill** ("Update to X" +
  quiet "Mark done"). A single **⋯ overflow menu** replaces the scattered buttons.
- **Recommendation first:** score dots + label, best-use headline, then reason —
  above the explanation (previously buried below it).
- **What is this?:** explanation (and the user's custom description card when set).
- **Calm utility rows:** Notes, License, App Link — unchanged behavior, quieter chrome.
- The **⋯ menu** consolidates Re-analyze, Lock/Unlock, Customize/Remove description,
  and now also Favorite / My App / **Subscription** toggles (the item-9 follow-up),
  plus Show in Finder / Open App / Copy Bundle ID. Sheets moved to the top level.
- App-link approval was kept intact for now; fully dropping it remains item 8b.
- *Follow-up (deferred, lower risk than splitting now): extract utility rows into a
  separate view file to shrink `AppDetailView`. The redesign was kept in one
  cohesive file to avoid risky state-plumbing during the layout change.*

## Work Items

### 1. Stop auto-wiping analyses on model change

**Problem.** `CacheService.isStale` returns `true` whenever
`record.ollamaModel != currentModel`. On the next scan after switching models,
every unlocked analysis is treated as stale and silently regenerated.

**Change.**
- `isStale` no longer considers a model mismatch stale. It keeps only the
  app-link comparison (`analysisAppURL` change) and the lock short-circuit.
- Add a read-only helper to detect model drift without mutating anything, e.g.
  `CacheService.wasAnalyzedWithDifferentModel(_ record:, currentModel:) -> Bool`.
- `AppListViewModel.runFullScan` counts unlocked, already-loaded apps whose
  `ollamaModel` differs from the current model into a new observable property,
  e.g. `staleModelCount: Int`.
- The UI shows a dismissible banner when `staleModelCount > 0`:
  *"Model changed since N apps were analyzed. Re-analyze them?"* with
  **Re-analyze** (runs item 2 scoped to those apps) and **Dismiss**.

**Acceptance.** Switching the Ollama model and rescanning preserves existing
analyses and shows the banner. Dismissing keeps the old analyses. App-link
changes still trigger re-analysis as today.

### 2. Bulk re-analyze

**Change.**
- `AppListViewModel.reanalyzeAll(scope:)` where scope is `.allUnlocked` or
  `.modelChangedUnlocked`. Iterates via the existing `enrichConcurrently` path,
  skipping locked records.
- Surfaced as a toolbar/menu action **"Re-analyze all"** and from the item-1
  banner (scoped to model-changed apps).
- Guard against concurrent runs (reuse `scanState` / a busy flag).

**Acceptance.** "Re-analyze all" refreshes every unlocked app; locked apps are
untouched; running it twice does not double-spawn work.

### 3. License-key hardening

**Problem.** Plaintext `AppRecord.licenseKey` is only migrated to Keychain when
its app's row/detail is opened (`resolveKey`). A record never viewed could retain
plaintext in the SwiftData store. Keychain items use default accessibility.

**Change.**
- Add a one-time launch migration (`LicenseKeyStore.migrateAllLegacyKeys(records:)`
  or a small migrator invoked from `AppAuditApp`): for every `AppRecord` with a
  non-empty `licenseKey`, write it to Keychain (if not already present) and set
  `licenseKey = nil`, then save the context once.
- Set explicit Keychain accessibility on write:
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (device-bound, non-syncing).
- Gate the migration behind a `UserDefaults` flag so it runs once.

**Acceptance.** After launch, no `AppRecord.licenseKey` holds plaintext; keys are
readable from Keychain; new writes carry the explicit accessibility attribute.

### 4. License Vault (retain keys for uninstalled apps)

**Foundation.** Cache records already survive uninstalls (nothing prunes them).
Keys live in Keychain under the bundle ID.

**Change.**
- Add a sidebar destination / sort entry **"Vault"** that lists apps which:
  (a) have an `AppRecord`, (b) are **not** in the current scan results, and
  (c) have a license key in Keychain.
- Each vault row shows: app name, masked key, **Copy**, **Delete** (removes the
  Keychain entry; optionally the orphan record).
- Determining "has a key": query Keychain per candidate bundle ID, or maintain a
  lightweight `hasLicenseKey` boolean on `AppRecord` kept in sync on save/delete
  to avoid Keychain reads during list rendering. **Chosen:** add
  `AppRecord.hasLicenseKey` (default `false`), set by `LicenseKeyStore` callers,
  backfilled by the item-3 migration.

**Acceptance.** Uninstalling an app that had a saved key keeps it retrievable in
the Vault; copying returns the real key; deleting removes it from Keychain.

### 5. CSV export

**Change.**
- Toolbar/menu **"Export…"** opens an `NSSavePanel` (default
  `AppAudit-YYYY-MM-DD.csv`).
- Columns: `name, bundleID, version, relevanceScore, bestUse, explanation,
  updateStatus, isMyApp, isFavorite, notes`.
- **No license key columns** of any kind.
- RFC-4180 quoting (escape quotes, wrap fields containing comma/quote/newline).
- A dedicated `CSVExporter` type (pure, testable) builds the string from
  `[AppInfo]` + records; the view layer only handles the save panel + write.

**Acceptance.** Export produces a well-formed CSV that opens cleanly in Numbers/
Excel, contains every scanned app, and contains no license keys.

### 6. Lower-memory enrichment

**Change.**
- Reduce default enrichment concurrency from 4 to 2 (named constant, e.g.
  `enrichmentConcurrency`).
- Ensure per-app request/response payloads are not retained beyond use in
  `enrichSingle` / `enrichConcurrently` (release captured strings promptly).
- No behavior change to results — purely footprint.

**Acceptance.** Background analysis of a large `/Applications` completes with
lower peak memory; results are unchanged.

### 7. Detail panel redesign — Option A (recommendation-first)

**Layout (top → bottom).**
1. **Header:** icon, name · version inline, bundle ID; update collapses to a
   single pill (e.g. "Update to 1.7.2") with source + "Mark done" as quiet
   secondary text; a single **⋯** overflow menu.
2. **Ranking first:** score dots + label, then best-use as the headline line,
   then the relevance reason.
3. **What is this?:** the explanation (and user description when present).
4. **Quiet utility rows:** Notes (disclosure), License (value + hover actions),
   Link (editable field). License & Notes stay visible (not behind tabs).

**Overflow ⋯ menu** consolidates: Lock/Unlock, Re-analyze, Customize description,
Remove custom description.

**Refactor.** Split `AppDetailView.swift` (~842 lines) into focused subviews:
`AppDetailHeader`, `AppDetailAnalysis`, `AppDetailUtilityRows` (+ existing sheets).
Each owns one section and is independently readable. No behavior change beyond the
reorganization and the link-field simplification (item 8).

**Acceptance.** Detail panel shows ranking before explanation, exposes one ⋯ menu
instead of scattered buttons, and keeps license/notes one glance away. The file is
split into single-purpose subviews.

### 8. Trims

**8a. Remove Apple Intelligence provider.**
- Collapse `AnalysisProviderKind` to `.ollama` only (or keep the enum with one
  case for storage stability). Delete `AppleIntelligenceService.swift` and its
  branch in `enrichSingle`. Remove the provider picker from `SettingsView`.
- `modelIdentifier` stays (Ollama model still varies → drives item-1 drift).

**8b. Remove suggested-link approval flow.**
- App Link becomes a single editable field. The resolver still runs, but its
  result simply **pre-fills the editable App Link field** as a suggestion; it
  takes effect only when the user saves the field — exactly like manual entry.
  No separate approve button, no separate `suggestedAppURL` state, and no silent
  auto-commit (so no surprise re-analyze without the user saving).
- Remove `AppRecord.suggestedAppURL` usage and the green-check approve button.
  Keep the field on the model for store-migration safety but stop writing it.
- Saving/changing a link still triggers `reanalyzeAfterLinkChange` (unchanged) —
  i.e. re-analysis happens on an explicit save, consistent with item 1's
  "no surprise regeneration" principle.

**8c. Sort orders → filters.**
- Sorts become **Relevance / Name / Updates / Vault**.
- **My Apps** and **Favorites** become filter toggles applied on top of the
  current sort, rather than their own sort modes.
- Update `SortOrder`, `filteredApps`, and `sidebarEmptyState` accordingly.

**Acceptance.** No Apple Intelligence UI or code path remains; the link field has
no approve step; My Apps/Favorites are filters; Vault is reachable.

---

## Live Fixes From Testing (shipped 2026-06-06)

Surfaced while the owner used the AppAudit2 side-build. Implemented immediately,
ahead of the main plan, because they were fast and high-value.

- **Item 9 — Subscription marker.** New `AppRecord.hasSubscription` /
  `AppInfo.isSubscribed`, mirroring the My App / Favorite pattern. Toggle via the
  row context menu ("Mark as Subscription"); a teal `creditcard.fill` badge shows
  on flagged rows. Lets the owner remember which apps cost a recurring
  subscription. *Follow-up (next session): expose it in the detail panel redesign
  and add a "Subscriptions" filter alongside My Apps / Favorites.*
- **Item 10 — De-hedge the analysis prompt.** The system/format/evidence prompt
  in `AppAnalysisPrompt` explicitly told the model to write "appears to be" when
  metadata was sparse, so nearly every card hedged. Reworked to state purpose
  directly, banning "appears to be"/"seems to be" and only allowing "unclear" when
  evidence is genuinely absent. *Cached analyses keep their old wording until
  re-analyzed — the bulk re-analyze (item 2) will refresh them.*
- **Item 11 — Settings window text overflow.** Bumped the fixed Settings size from
  430×220 to 480×340 so footer/status text is no longer clipped. (The Models tab
  shrinks further once Apple Intelligence is removed per item 8a.)
- **Item 13 — Isolate the AppAudit2 side-build.** The SwiftData store folder and
  the Keychain service name now derive from the bundle identifier. The primary app
  (`com.kikaapp.appaudit`) is unchanged (same `AppAudit` folder, same
  `com.kikaapp.appaudit.licensekeys` service); the `com.kikaapp.appaudit2` test
  build gets its own isolated store and Keychain service. This fixes the ad-hoc
  side-build re-prompting for every license key on every read. Added
  `Scripts/build_appaudit2.sh` to build/sign/install the side-build in one command.
  The owner's 8 existing license keys were first exported to an encrypted
  (`AES-256`/PBKDF2) backup on the Desktop, passphrase stored in the login Keychain
  under "AppAudit License Backup".
- **Item 12 — Sort by last used.** New `AppInfo.lastUsedDate`, read at scan time
  from Spotlight's `kMDItemLastUsedDate` via `MDItem`. New `SortOrder.lastUsed`
  ("Last Used") sorts most-recent first; apps Spotlight has never seen sort to the
  bottom, then alphabetically. The row subtitle shows a relative "Used N ago" /
  "Never used" while this sort is active. Inspired by the Mole app. *Follow-up:
  once My Apps/Favorites become filters (item 8c), keep Last Used as a sort.*

## Data Model Changes

`AppRecord` (SwiftData, additive only — safe for lightweight migration):
- **Add** `hasLicenseKey: Bool = false` (item 4).
- **Add** `hasSubscription: Bool = false` (item 9, shipped 2026-06-06).
- `suggestedAppURL` retained on the model but no longer written (item 8b).
- `licenseKey` retained as the migration bridge; nulled by item 3.

No destructive schema changes; existing stores migrate automatically.

## Affected Files (indicative)

- `Services/CacheService.swift` — staleness logic (item 1).
- `ViewModels/AppListViewModel.swift` — staleModelCount, reanalyzeAll, concurrency,
  sort/filter changes, drop AI branch.
- `Services/LicenseKeyStore.swift` — accessibility attr, bulk migration, hasKey.
- `Models/AppRecord.swift` — `hasLicenseKey`.
- `Models/AnalysisProviderKind.swift` — collapse to Ollama.
- `Services/AppleIntelligenceService.swift` — **delete**.
- `Views/AppDetailView.swift` — split + redesign + link field.
- `Views/SettingsView.swift` — remove provider picker.
- `Views/AppListView.swift` / `ContentView.swift` — banner, filters, Vault,
  toolbar (Re-analyze all, Export…).
- New: `Services/CSVExporter.swift`, detail subviews, Vault view.

## Testing Strategy

- **Unit:** `CacheService.isStale` no longer stale on model change; still stale on
  link change. `CSVExporter` quoting/columns/no-keys. `LicenseKeyStore` migration
  nulls plaintext and writes Keychain with correct accessibility (via the
  injectable `SecretStoreBackend`). Vault filtering predicate.
- **Behavior:** reanalyzeAll skips locked; banner appears only on drift.
- **Manual (end, before release):** full scan, model switch, bulk re-analyze,
  export open in Numbers, uninstall→Vault, detail panel feel. Re-test after
  packaging.

## Risks

- SwiftData migration: additive field is low-risk; verify on an existing store.
- Removing Apple Intelligence: ensure no dangling references / settings keys break
  existing user defaults.
- Keychain accessibility change applies to new writes; the migration re-writes
  legacy keys so they pick up the attribute.

## Release (deferred to the end)

After the app feels right and re-testing passes: bump `version.env`
(`MARKETING_VERSION` → 1.1.0), build + sign + notarize the DMG via existing
`Scripts/make_dmg.sh` and `docs/RELEASE.md`, and publish to **GitHub Releases**
with the signed/notarized DMG attached.

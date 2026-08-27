# Uninstall Sweep — Design

**Date:** 2026-08-01
**Status:** Approved (Kika, 2026-08-01)
**Baseline:** post-1.6.0 (`85c4b1e`)

## Problem

Sift knows everything about an installed app — what it is, what it cost,
whether it earns its place — but the final verdict ("it goes") still means
switching to Finder or another uninstaller. Kika reshelfed Mole and
Uninstally; the capability belongs in Sift.

## Goals

1. Uninstall an app from the sidebar right-click, sweeping its leftovers.
2. Trash-only — everything recoverable, nothing permanently deleted.
3. Records survive: license keys, notes, and marks stay; the License Vault
   already lists gone apps under "No longer installed".

## Sources and licensing

- **Adapted from:** `uninstally` (`~/reshelf/repos/macOS/uninstally`, MIT,
  © 2026 Codenta) — `AssociatedFileScanner` matching strategy and
  `DeletionExecutor` trash-first execution. Attribution comment in the new
  scanner's header.
- **Concepts only from:** Mole (`~/reshelf/repos/CLI/Mole`, GPL-3.0 — no
  code copied): app protection list, Homebrew uninstall path.

## Design

### 1. Entry point

`AppRow`'s context menu gains a final group: Divider + destructive
"Uninstall…". Hidden entirely when the app is protected:

```
UninstallRules.isProtected(bundleID:) == true  for
  com.apple.*            (system apps)
  com.kikaapp.appaudit   (Sift itself)
  com.kikaapp.sift2      (the side-build)
```

Selecting it opens the sweep sheet for that app.

### 2. LeftoverScanner (service)

`Sources/AppAudit/Services/LeftoverScanner.swift`, adapted from
Uninstally's `AssociatedFileScanner`:

- **Identifier-first matching.** Candidates: the app's bundle ID plus
  helper namespaces (bundleID prefix-matched children, e.g.
  `com.foo.app.helper`). A directory/file matches when its name equals or
  is prefixed by a candidate identifier.
- **Name-equality matching** only under Application Support and Logs
  (vendor convention), recorded as such in the reason.
- **User-level roots scanned** (`~/Library/...`): Application Support,
  Caches, Preferences (plist files + ByHost + `.plist.lockfile`), Logs,
  Containers, Group Containers, Saved Application State, WebKit,
  HTTPStorages, LaunchAgents, Application Scripts, Cookies.
- Every hit becomes `LeftoverItem { url, category, sizeBytes, reason }`;
  sizes computed by directory enumeration; results de-duplicated by
  standardized path and sorted by size descending.
- The app bundle itself is always item #1.

### 3. Sweep sheet (UI)

`Sources/AppAudit/Views/UninstallSheet.swift`:

- Header: app icon, name, "n items · X MB reclaimable".
- Scrolling list: checkbox per item (all pre-checked), category label,
  abbreviated path, size, caption reason.
- Running app: warning banner + "Quit & Continue" (NSRunningApplication
  terminate; rescan state after).
- Homebrew cask (`app.homebrewCaskToken != nil`): note row offering
  `brew uninstall --cask <token>` via HomebrewService (new
  `uninstallCask(_:)` mirroring `upgradeCask`), as an alternative to the
  file sweep for the bundle itself; leftover sweep still applies.
- Footer: Cancel / destructive-prominent "Move to Trash".

### 4. Execution

`FileManager.trashItem(at:)` per checked item, on a background task,
progress reported per item; failures collected and shown ("2 items could
not be moved"). No `removeItem` fallback — trash or nothing (v1). After
completion: `viewModel` removes the app from the in-memory list (record
kept), the sheet shows a short summary, and closing it returns to an
empty selection.

### 5. Data rules

- `AppRecord` is never deleted or modified by uninstall.
- License keys stay in the Keychain; the vault's existing
  "No longer installed" section covers the rest.

## Error handling

- Scanner root missing → skipped silently (normal).
- Trash failure per item → collected, listed in the summary; other items
  proceed.
- App fails to quit → stay on the banner; user can cancel.

## Testing

- `UninstallRulesTests`: protection list (com.apple.*, Sift, side-build,
  normal apps pass).
- `LeftoverMatcherTests`: identifier candidates from a bundle ID, prefix
  matching, name-equality allowed only for App Support/Logs, preference
  file matching incl. ByHost and lockfiles — pure logic, temp-dir based.
- Executor plan-building tested with a mock file remover; no real
  trashing in tests.
- Live pass in Sift2 against a sacrificial app.

## Out of scope (v1)

- System-level `/Library` sweep (admin rights).
- Batch uninstall of multiple apps.
- Uninstall history UI.
- Receipt extraction (separate deferred spec).

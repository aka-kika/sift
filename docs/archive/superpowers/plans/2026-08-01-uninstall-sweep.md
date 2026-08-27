# Uninstall Sweep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Right-click "Uninstall…" in the sidebar opens a sweep sheet listing the app bundle plus all bundle-ID-matched leftovers, and moves the checked items to the Trash.

**Architecture:** Pure matching logic (`LeftoverMatcher`, `UninstallRules`) lives in Models and is fully unit-tested. `LeftoverScanner` (Services) walks the user-level Library roots off the main actor. `UninstallSheet` (Views) presents items and drives `FileManager.trashItem`. `AppListViewModel.removeApp` drops the app from the in-memory list; the `AppRecord` is never touched.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing. Patterns adapted from `~/reshelf/repos/macOS/uninstally` (MIT © 2026 Codenta — attribute in `LeftoverScanner`'s header).

**Spec:** `docs/archive/superpowers/specs/2026-08-01-uninstall-sweep-design.md`

## Global Constraints

- Trash-only: `FileManager.trashItem(at:)`, never `removeItem`.
- User-level `~/Library` roots only; no admin paths.
- `AppRecord`, keychain keys, notes, and marks are never modified by uninstall.
- Protected (no Uninstall menu item): bundle IDs starting `com.apple.`, plus `com.kikaapp.appaudit` and `com.kikaapp.sift2`.
- Tests: `swift test` from repo root. No real trashing in tests (mock the remover).
- Commit after every task.

---

### Task 1: Models + rules (`LeftoverItem`, `UninstallRules`, `LeftoverMatcher`)

**Files:**
- Create: `Sources/AppAudit/Models/Uninstall.swift`
- Test: `Tests/AppAuditTests/AppAuditTests.swift` (append suites)

**Interfaces (produced):**
```swift
struct LeftoverItem: Identifiable, Equatable {
    let id: String            // standardized path
    let url: URL
    let category: LeftoverCategory
    let sizeBytes: Int64
    let reason: String
    var isAppBundle: Bool = false
}
enum LeftoverCategory: String { case application = "Application",
    applicationSupport = "Application Support", caches = "Caches",
    preferences = "Preferences", logs = "Logs", containers = "Containers",
    groupContainers = "Group Containers", savedState = "Saved State",
    webKit = "WebKit", httpStorages = "HTTP Storages",
    launchAgents = "Launch Agents", applicationScripts = "App Scripts",
    cookies = "Cookies" }
enum UninstallRules { static func isProtected(bundleID: String) -> Bool }
enum LeftoverMatcher {
    static func identifierCandidates(bundleID: String) -> [String]
    static func matches(name: String, bundleID: String) -> Bool
    static func nameMatchAllowed(for category: LeftoverCategory) -> Bool
    static func matchesDisplayName(_ name: String, appName: String) -> Bool
}
```

- [ ] Tests first (`UninstallRulesTests`, `LeftoverMatcherTests`): protection covers `com.apple.finder`, `com.kikaapp.appaudit`, `com.kikaapp.sift2`; `com.asiafu.Bloom` passes. Matching: `"com.asiafu.Bloom"` matches names `com.asiafu.Bloom`, `com.asiafu.Bloom.plist`, `com.asiafu.Bloom.helper`, `com.asiafu.Bloom.savedState`; does NOT match `com.asiafu.Bloomberg` is allowed (prefix semantics — document) but NOT `com.other.app`; ByHost shape `com.asiafu.Bloom.ABC123.plist` matches. Name match allowed only for `.applicationSupport`/`.logs`; display-name match is case-insensitive equality and requires >3 chars.
- [ ] Implement (matching semantics from uninstally's `containsIdentifier`): bare name (extension stripped) equals candidate, or name hasPrefix candidate, or bare hasSuffix candidate.
- [ ] `swift test --filter Uninstall` green → commit `feat: uninstall models, protection rules, leftover matcher`.

### Task 2: `LeftoverScanner` + `HomebrewService.uninstallCask`

**Files:**
- Create: `Sources/AppAudit/Services/LeftoverScanner.swift`
- Modify: `Sources/AppAudit/Services/HomebrewService.swift`

**Interfaces (produced):**
```swift
struct LeftoverScanner {          // header comment: adapted from uninstally (MIT © 2026 Codenta)
    func scan(appName: String, bundleID: String, appPath: String) async -> [LeftoverItem]
}
// HomebrewService:
func uninstallCask(_ token: String) -> String   // runBrew(["uninstall", "--cask", token], includeStandardError: true)
```

- [ ] Roots (all under `FileManager.default.homeDirectoryForCurrentUser/Library`): Application Support, Caches, Preferences (+`ByHost`, incl. `.plist.lockfile`), Logs, Containers, Group Containers, Saved Application State, WebKit, HTTPStorages, LaunchAgents, Application Scripts, Cookies. Missing root → skip. Enumerate immediate children only; match via `LeftoverMatcher`; sizes via recursive `FileManager` enumeration (`totalFileAllocatedSize` fallback `fileSize`). App bundle itself is item #1 (`isAppBundle: true`, reason "The application bundle"). De-dupe by standardized path, sort by size desc (bundle stays first).
- [ ] `swift build` green → commit `feat: LeftoverScanner + brew cask uninstall`.

### Task 3: `UninstallSheet` view

**Files:**
- Create: `Sources/AppAudit/Views/UninstallSheet.swift`

**Interfaces (produced):**
```swift
struct UninstallSheet: View {
    let app: AppInfo
    let onFinished: (_ removedBundle: Bool) -> Void   // true → app gone from disk
}
```

- [ ] States: `scanning` (spinner) → `list(items, checked: Set<String>)` → `working(progress)` → `done(failures: [String])`. Running-app banner (`NSRunningApplication.runningApplications(withBundleIdentifier:)`) with "Quit & Continue" (`terminate()`). Homebrew note row with "Run brew uninstall" when `app.homebrewCaskToken != nil` (Task.detached → `HomebrewService().uninstallCask`). Footer: Cancel / destructive `Move to Trash` (disabled while zero checked). Execution: background task, `FileManager.default.trashItem(at:resultingItemURL:)` per checked item, collect failures, then `done`. Width ~440, list ~360 max height, quiet field styling consistent with MoneyPopover.
- [ ] `swift build` green → commit `feat: UninstallSheet — sweep panel with trash-first execution`.

### Task 4: Wire-in (row menu + view model + presentation)

**Files:**
- Modify: `Sources/AppAudit/Views/AppRow.swift`
- Modify: `Sources/AppAudit/ViewModels/AppListViewModel.swift`

**Interfaces (produced):** `AppListViewModel.removeApp(bundleID: String)` — `apps.removeAll { $0.bundleID == bundleID }` (record untouched).

- [ ] AppRow: `@State private var uninstallSheetPresented = false`; context-menu final group `if !UninstallRules.isProtected(bundleID: app.bundleID) { Divider(); Button(role: .destructive) { uninstallSheetPresented = true } label: { Label("Uninstall…", systemImage: "trash") } }`; `.sheet` presenting `UninstallSheet(app: app) { removed in if removed { viewModel.removeApp(bundleID: app.bundleID) } ; uninstallSheetPresented = false }`.
- [ ] `swift build && swift test` green → commit `feat: Uninstall… in the sidebar menu, wired to the sweep sheet`.

### Task 5: Verification + changelog

- [ ] Full `swift test`; build Sift2 (`Scripts/build_sift2.sh`); live pass: uninstall a sacrificial app (e.g. a small free app), verify items listed with reasons/sizes, trash receives them, app leaves the sidebar, its record stays in the vault, protected apps show no menu item.
- [ ] CHANGELOG `[Unreleased]`: `### Added` — "Uninstall from the sidebar: right-click → Uninstall… sweeps the app and its leftovers (caches, preferences, containers, launch agents) to the Trash — recoverable, license keys and notes kept. Homebrew casks can run brew uninstall instead. Apple system apps and Sift itself are protected." Replace the "Nothing yet" placeholder, keep the receipt-extraction breadcrumb line.
- [ ] Commit `docs: changelog for uninstall sweep`.

## Self-Review Notes

- Spec coverage: entry/protection → T1+T4; scanner/roots → T2; sheet incl. running-app + brew → T3; execution trash-only → T3; data rules → T4 (removeApp only); tests → T1 + T5.
- Type consistency: `LeftoverItem.id` = standardized path used as checked-set key in T3; `UninstallRules.isProtected(bundleID:)` name used in T1 tests and T4 menu.

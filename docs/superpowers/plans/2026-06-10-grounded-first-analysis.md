# Grounded-First Analysis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Facts-first detail panel, an automatic workflow profile derived deterministically from the installed apps (categories + recently-used + currently-running), app category as visible evidence, and Apple Intelligence as the zero-setup default for first runs.

**Architecture:** Two new pure model helpers (`AppCategory`, `WorkflowDigest`) feed the existing `WorkflowProfile` via a new `current(digest:)` resolution (custom override → digest → neutral). The scanner gains category + isRunning facts; views reorder and surface them. A presence-check launch migration sets the first-run provider. No schema changes to `AppRecord`.

**Tech Stack:** SwiftUI/SwiftData, Swift Testing. Every command needs `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (standalone CLT broken on macOS 27). Ignore SourceKit/IDE diagnostics; only build/test output counts.

Spec: `docs/superpowers/specs/2026-06-10-grounded-first-analysis-design.md`

---

### Task 1: Facts layer — category, isRunning, digest, profile resolution (TDD)

**Files:**
- Create: `Sources/AppAudit/Models/AppCategory.swift`, `Sources/AppAudit/Models/WorkflowDigest.swift`
- Modify: `Sources/AppAudit/Models/AppInfo.swift`, `Sources/AppAudit/Services/AppScanner.swift`, `Sources/AppAudit/Models/WorkflowProfile.swift`, `Sources/AppAudit/Models/AnalysisProviderKind.swift`
- Test: `Tests/AppAuditTests/AppAuditTests.swift`

- [ ] **Step 1: Write the failing tests** (new suite at the end of the test file):

```swift
@Suite("Grounded Profile Tests")
struct GroundedProfileTests {

    private func app(_ name: String, category: String? = nil, lastUsed: Date? = nil, running: Bool = false) -> AppInfo {
        AppInfo(
            id: "com.test.\(name)", name: name, version: "1.0",
            bundleID: "com.test.\(name)", path: "/Applications/\(name).app",
            humanReadableDescription: nil, sparkleFeedURL: nil,
            isAppStoreInstall: false, icon: nil,
            category: category, lastUsedDate: lastUsed, isRunning: running
        )
    }

    @Test("Category raw values map to readable names")
    func categoryNames() {
        #expect(AppCategory.humanName(for: "public.app-category.developer-tools") == "Developer Tools")
        #expect(AppCategory.humanName(for: "public.app-category.productivity") == "Productivity")
        #expect(AppCategory.humanName(for: "com.example.custom") == nil)
        #expect(AppCategory.humanName(for: nil) == nil)
    }

    @Test("Digest counts categories, lists recent and running apps")
    func digestContents() {
        let now = Date()
        let apps = [
            app("Xcode", category: "public.app-category.developer-tools", lastUsed: now, running: true),
            app("Ghostty", category: "public.app-category.developer-tools", lastUsed: now.addingTimeInterval(-60)),
            app("Figma", category: "public.app-category.graphics-design", lastUsed: now.addingTimeInterval(-120)),
            app("Mystery"),
        ]
        let digest = WorkflowDigest.build(from: apps)
        #expect(digest.contains("Installed apps: 4."))
        #expect(digest.contains("Developer Tools (2)"))
        #expect(digest.contains("Graphics Design (1)"))
        #expect(digest.contains("other (1)"))
        #expect(digest.contains("Most recently used: Xcode, Ghostty, Figma."))
        #expect(digest.contains("Open right now: Xcode."))
    }

    @Test("Digest of no apps is empty")
    func digestEmpty() {
        #expect(WorkflowDigest.build(from: []) == "")
    }

    @Test("Profile resolution: custom override beats digest beats neutral")
    func profileResolution() {
        let defaults = UserDefaults(suiteName: "AppAuditTests.GroundedProfile")!
        defaults.set("my custom workflow", forKey: WorkflowProfile.storageKey)
        #expect(WorkflowProfile.current(digest: "digest text", userDefaults: defaults).promptDescription == "my custom workflow")

        defaults.removeObject(forKey: WorkflowProfile.storageKey)
        #expect(WorkflowProfile.current(digest: "digest text", userDefaults: defaults).promptDescription == "digest text")
        #expect(WorkflowProfile.current(digest: "", userDefaults: defaults).promptDescription
            == WorkflowProfile.neutralProfileText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("First-run provider default only when Apple Intelligence is available")
    func firstRunProvider() {
        #expect(AnalysisProviderKind.firstRunProviderRawValue(appleIntelligenceAvailable: true) == "appleIntelligence")
        #expect(AnalysisProviderKind.firstRunProviderRawValue(appleIntelligenceAvailable: false) == nil)
    }
}
```

- [ ] **Step 2: Run, verify compile failure** (`AppCategory`/`WorkflowDigest`/params not found):
`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -5`

- [ ] **Step 3: `AppInfo` gains the two facts.** Add stored properties and init params (defaults keep all existing call sites compiling):
- `let category: String?` after `path`; init param `category: String? = nil` placed immediately before `humanReadableDescription`'s... **simpler:** add both as DEFAULTED params at the positions shown in the test helper above: `category: String?` right after `icon`-adjacent block won't match the test — match the test exactly: init order `..., isAppStoreInstall:, homebrewCaskToken: = nil, icon:, category: String? = nil, lastUsedDate: Date? = nil, isRunning: Bool = false, aiState: ...`. Store `let category: String?` next to `let lastUsedDate: Date?`, and `var isRunning: Bool = false` next to the other `var` flags. Assign both in init.

- [ ] **Step 4: `AppCategory.swift`:**

```swift
import Foundation

/// Maps `LSApplicationCategoryType` raw values ("public.app-category.developer-tools")
/// to readable names ("Developer Tools"). Deterministic slug formatting — no lookup
/// table to maintain; unknown or missing values yield nil.
enum AppCategory {
    static func humanName(for raw: String?) -> String? {
        let prefix = "public.app-category."
        guard let raw, raw.hasPrefix(prefix) else { return nil }
        let slug = raw.dropFirst(prefix.count)
        guard !slug.isEmpty else { return nil }
        return slug.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
```

- [ ] **Step 5: `WorkflowDigest.swift`:**

```swift
import Foundation

/// Deterministic, evidence-only summary of the user's installed apps, used as the
/// automatic workflow profile. Pure code — nothing here is AI-generated, so there
/// is nothing for a small model to hallucinate from.
enum WorkflowDigest {
    static func build(from apps: [AppInfo]) -> String {
        guard !apps.isEmpty else { return "" }

        var counts: [String: Int] = [:]
        var uncategorized = 0
        for app in apps {
            if let name = AppCategory.humanName(for: app.category) {
                counts[name, default: 0] += 1
            } else {
                uncategorized += 1
            }
        }
        let top = counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(5)
            .map { "\($0.key) (\($0.value))" }
        var categories = top.joined(separator: ", ")
        if uncategorized > 0 {
            categories += categories.isEmpty ? "uncategorized (\(uncategorized))" : ", other (\(uncategorized))"
        }

        let recent = apps
            .compactMap { app in app.lastUsedDate.map { (app.name, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(8)
            .map(\.0)
        let running = apps.filter(\.isRunning).map(\.name).sorted().prefix(8)

        var parts = ["Installed apps: \(apps.count). Categories: \(categories)."]
        if !recent.isEmpty { parts.append("Most recently used: \(recent.joined(separator: ", ")).") }
        if !running.isEmpty { parts.append("Open right now: \(running.joined(separator: ", ")).") }
        return parts.joined(separator: " ")
    }
}
```

- [ ] **Step 6: Scanner reads both facts.** In `AppScanner`: `scan(...)` gains `runningBundleIDs: Set<String> = []`, threads it to `makeAppInfo`. In `makeAppInfo`: `let category = plist["LSApplicationCategoryType"] as? String`, and pass `category: category, lastUsedDate: lastUsedDate(forPath: path), isRunning: runningBundleIDs.contains(bundleID)` in the `AppInfo` init.

- [ ] **Step 7: `WorkflowProfile.current(digest:)`.** Replace `current(userDefaults:)` with:

```swift
    static func current(digest: String? = nil, userDefaults: UserDefaults = .standard) -> WorkflowProfile {
        let stored = (userDefaults.string(forKey: storageKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty { return local(text: stored) }
        if let digest, !digest.isEmpty {
            return WorkflowProfile(languages: [], tools: [], domains: [],
                                   projectKeywords: [], customDescription: digest)
        }
        return local(text: nil)
    }
```
(Existing `.current()` call sites keep compiling — digest defaults to nil → neutral fallback unchanged until Task 2 wires digests in.)

- [ ] **Step 8: `AnalysisProviderKind.firstRunProviderRawValue`:**

```swift
    /// First-run only: pick Apple Intelligence when it is actually available, else
    /// leave the preference unset so the Ollama fallback applies. Pure for testing.
    static func firstRunProviderRawValue(appleIntelligenceAvailable: Bool) -> String? {
        appleIntelligenceAvailable ? AnalysisProviderKind.appleIntelligence.rawValue : nil
    }
```

- [ ] **Step 9: Tests green** (expect 53):
`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`

- [ ] **Step 10: Commit:** `git add -A && git commit -m "Facts layer: app category, isRunning, workflow digest, profile resolution"`

---

### Task 2: Wiring + UI — digest into analysis, Settings, detail reorder, running dot

**Files:**
- Modify: `Sources/AppAudit/ViewModels/AppListViewModel.swift`, `Sources/AppAudit/Views/SettingsView.swift`, `Sources/AppAudit/Views/AppDetailView.swift`, `Sources/AppAudit/Views/AppRow.swift`, `Sources/AppAudit/Views/ContentView.swift`

- [ ] **Step 1: View model.** In `runFullScan`, replace the scan + profile lines:

```swift
        #if canImport(AppKit)
        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        #else
        let runningIDs = Set<String>()
        #endif
        let scannedApps = await scanner.scan(runningBundleIDs: runningIDs)
        let digest = WorkflowDigest.build(from: scannedApps)
        UserDefaults.standard.set(digest, forKey: "lastProfileDigest")
        workflowProfile = .current(digest: digest)
```
(add `#if canImport(AppKit) import AppKit #endif` at the top if not importable via SwiftUI). In `reanalyze` and `reanalyzeAll`, replace `workflowProfile = .current()` with `workflowProfile = .current(digest: WorkflowDigest.build(from: apps))`.

- [ ] **Step 2: First-run provider migration.** Add to the view model (near `migrateLegacyLicenseKeys`):

```swift
    /// First launch only (presence check — never overrides a stored choice): start
    /// new installs on Apple Intelligence when it actually works on this Mac.
    func applyFirstRunProviderDefault() async {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: AnalysisProviderKind.storageKey) == nil else { return }
        let available: Bool
        if case .models = await AppleIntelligenceService().fetchModels() { available = true } else { available = false }
        if let raw = AnalysisProviderKind.firstRunProviderRawValue(appleIntelligenceAvailable: available) {
            defaults.set(raw, forKey: AnalysisProviderKind.storageKey)
        }
    }
```
In `ContentView`'s `.task`, call `await viewModel.applyFirstRunProviderDefault()` after `syncLicenseFlags()` and before `runFullScan()`.

- [ ] **Step 3: Settings Profile tab.** In `ProfileSettingsTab`: add `@AppStorage("lastProfileDigest") private var lastProfileDigest = ""`. Restructure the `Form` to:

```swift
            Section("Automatic profile") {
                SettingsFooter(lastProfileDigest.isEmpty
                    ? "Derived from your installed apps after the first scan — categories, recently used, and open apps."
                    : lastProfileDigest)
            }

            Section("Custom override") {
                TextEditor(text: $profileText)
                    .font(.body)
                    .frame(minHeight: 58)
                    .scrollContentBackground(.hidden)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))

                SettingsFooter("Leave empty to use the automatic profile. Re-analyze an app to apply changes.")
            }

            Section {
                Button("Clear Override") { profileText = "" }
                    .controlSize(.small)
            }
```
**Important:** change the `profileText` default from `WorkflowProfile.defaultProfileText` to `""` (`@AppStorage(WorkflowProfile.storageKey) private var profileText = ""`) so fresh installs are automatic-by-default; the old "Restore Default Profile" button becomes "Clear Override" as shown. In `SettingsView.tabHeight`, set `case .profile: return 300`.

- [ ] **Step 4: Detail panel reorder + category.** In `AppDetailView.body`, reorder the VStack to: `headerSection`, `Divider()`, `whatIsThisSection`, `recommendationSection`, `Divider()`, `utilitySection`. In `headerSection`'s name HStack, after the version `Text`, add:

```swift
                    if let categoryName = AppCategory.humanName(for: app.category) {
                        Text("· \(categoryName)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
```

- [ ] **Step 5: Running dot.** In `AppRow`'s badge HStack (before the favorite star), add:

```swift
                    if app.isRunning {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                            .help("Open now")
                    }
```

- [ ] **Step 6: Tests (53) + side-build:**
`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`
`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash Scripts/build_sift2.sh 2>&1 | tail -2 && sleep 2 && pgrep -x Sift2`

- [ ] **Step 7: Commit:** `git add -A && git commit -m "Wire digest into analysis; facts-first detail; auto profile settings; running dot"`

---

### Task 3: Prompts, CSV, docs

**Files:**
- Modify: `Sources/AppAudit/Services/AppAnalysisPrompt.swift`, `Sources/AppAudit/ViewModels/AppListViewModel.swift` (CSV), `FEATURES.md`, `docs/README.md`, `docs/ARCHITECTURE.md`, `docs/roadmap.md`, spec status line

- [ ] **Step 1: Prompts get the category fact.** In `build(...)`: alongside `descriptionHint`, add `let categoryHint = AppCategory.humanName(for: app.category).map { "\nCategory: \($0)" } ?? ""` and include it right after `Path: \(app.path)`: `Path: \(app.path)\(categoryHint)\(descriptionHint)\(linkContext)`. In `compactFacts(...)`: after the `Path` line append:

```swift
        if let categoryName = AppCategory.humanName(for: app.category) {
            lines.append("Category: \(categoryName)")
        }
```

- [ ] **Step 2: CSV category column.** In `exportCSV()`: header gains `"Category"` after `"Version"`; each row gains `AppCategory.humanName(for: app.category) ?? ""` at the same position.

- [ ] **Step 3: Docs.**
- FEATURES.md → Analysis section: add `- **Automatic workflow profile** — derived from your installed apps (categories, recently used, open now); optional custom override in Settings.` and `- **Category** — shown per app, from the app's own metadata.` In AI providers: note new installs default to Apple Intelligence when available.
- docs/README.md → Workflow Context section: rewrite to describe automatic digest + override; Detail Panel: "What is this?" first; Models Tab: note the first-run default; CSV section: add Category to the column list.
- docs/ARCHITECTURE.md → AI Prompt/profile note: profile resolution order custom → digest → neutral.
- docs/roadmap.md → Now: replace the (shipped) glass line with `- **Grounded-first analysis** — facts before opinions: auto profile from installed apps, category evidence, zero-setup Apple Intelligence default.` Move glass to Recently shipped.
- Spec `docs/superpowers/specs/2026-06-10-grounded-first-analysis-design.md` status → `Implemented (this plan)`.

- [ ] **Step 4: Tests (53) + Sift2 rebuild + commit:** `git add -A && git commit -m "Category evidence in prompts and CSV; grounded-first docs"`

---

## Self-Review

- Spec coverage: item 1 → T2/S4; item 2 → T1/S3-6 + T3/S1-2; item 3 → T1/S5,7 + T2/S1,3; item 4 → T1/S8 + T2/S2; item 5 → tests in T1 + docs in T3. ✓
- Placeholders: none — all code shown.
- Type consistency: `AppInfo` init order in the test helper matches T1/S3's instruction; `WorkflowDigest.build` and `AppCategory.humanName` signatures match all call sites; `current(digest:)` keeps the old call sites compiling.

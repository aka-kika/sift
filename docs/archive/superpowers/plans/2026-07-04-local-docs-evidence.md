# Local Docs Evidence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user attach an app's local project folder; Sift extracts its README + a stack hint, snapshots that onto the record, feeds it into the analysis prompt as primary evidence, and re-analyzes.

**Architecture:** A small `DocsEvidence` extractor (sibling of `LinkEvidence`) reads a folder root off disk. Two defaulted `AppRecord` fields hold the snapshot text and source path. The snapshot threads through `AppAnalysisPrompt.build` and all three providers exactly like `userNotes`, loading from the cached record on every analysis path. A 7th teal "Docs" cube in the detail view drives attach / refresh / remove, each triggering a lock-respecting re-analysis.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData, Swift Testing (`@Suite`/`@Test`/`#expect`), AppKit (`NSOpenPanel`, `NSWorkspace`), macOS 14+.

**Spec:** `docs/archive/superpowers/specs/2026-07-04-local-docs-evidence-design.md`

## Global Constraints

- Product is **Sift**; sources live under `Sources/AppAudit/`; identifiers are never renamed.
- Run tests with `swift test` from the repo root. The suite is **95 tests before Task 1**; each task keeps it green.
- Tests append to the single `Tests/AppAuditTests/AppAuditTests.swift`, matching the existing `@Suite`/`@Test`/`#expect` Swift Testing style.
- New `AppRecord` fields MUST be defaulted (`docsEvidence: String? = nil`, `docsFolderPath: String? = nil`) for lightweight SwiftData migration.
- Empty/whitespace `docsEvidence` MUST produce a prompt byte-identical to today's.
- All providers keep sharing the single `AppAnalysisPrompt.build` — no per-provider prompt text.
- Locked analyses (in-memory `isAnalysisLocked` AND cached record) never auto-run.
- README cap is `4000` characters. Root-level files only; no recursion. Manifest set is exactly: `Package.swift`, `package.json`, `Cargo.toml`, `pyproject.toml`, `go.mod`, `Gemfile`, `Info.plist`.
- Docs cube tint is `.teal`, icon `doc.text`, added as the 7th cube after `favoriteCard`.

## File Structure

- Create: `Sources/AppAudit/Services/DocsEvidence.swift` — folder → snapshot text.
- Modify: `Sources/AppAudit/Models/AppRecord.swift` — two fields.
- Modify: `Sources/AppAudit/Services/AppAnalysisPrompt.swift` — docs block.
- Modify: `Sources/AppAudit/Services/AnalysisService.swift`, `OllamaService.swift`, `AnthropicService.swift`, `OpenAIService.swift` — thread `docsEvidence`.
- Modify: `Sources/AppAudit/ViewModels/AppListViewModel.swift` — load docs on every path + `reanalyzeAfterDocsChange`.
- Modify: `Sources/AppAudit/Views/AppDetailView.swift` — the Docs cube.
- Modify: `FEATURES.md`.
- Test: `Tests/AppAuditTests/AppAuditTests.swift`.

---

### Task 1: DocsEvidence extractor + AppRecord fields

**Files:**
- Create: `Sources/AppAudit/Services/DocsEvidence.swift`
- Modify: `Sources/AppAudit/Models/AppRecord.swift` (fields after `licenseType` line; init assignments after `self.licenseType = nil`)
- Test: `Tests/AppAuditTests/AppAuditTests.swift` (append)

**Interfaces:**
- Produces: `DocsEvidence.extract(fromFolder path: String) -> String?` — returns README text (truncated to 4000 chars) and/or a `Detected project files: …` line, or `nil` if neither found. `DocsEvidence.maxReadmeChars = 4000`. `AppRecord.docsEvidence: String?` (default nil), `AppRecord.docsFolderPath: String?` (default nil).

- [ ] **Step 1: Write the failing tests**

Append to `Tests/AppAuditTests/AppAuditTests.swift`:

```swift
@Suite("Docs Evidence")
struct DocsEvidenceTests {
    private func tempFolder() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docsev-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Reads README text and lists detected manifests")
    func readsReadmeAndManifests() throws {
        let dir = tempFolder()
        try "# MyTool\nA menu-bar batch renamer.".write(
            to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "{}".write(to: dir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let result = DocsEvidence.extract(fromFolder: dir.path)
        #expect(result?.contains("A menu-bar batch renamer.") == true)
        #expect(result?.contains("Detected project files:") == true)
        #expect(result?.contains("package.json") == true)
    }

    @Test("Manifest-only folder still returns the stack hint")
    func manifestOnly() throws {
        let dir = tempFolder()
        try "".write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let result = DocsEvidence.extract(fromFolder: dir.path)
        #expect(result?.contains("Package.swift") == true)
    }

    @Test("Empty or irrelevant folder returns nil")
    func emptyFolder() throws {
        let dir = tempFolder()
        try "x".write(to: dir.appendingPathComponent("notes.rtf"), atomically: true, encoding: .utf8)
        #expect(DocsEvidence.extract(fromFolder: dir.path) == nil)
        #expect(DocsEvidence.extract(fromFolder: "/no/such/folder/here") == nil)
    }

    @Test("Oversize README is truncated to the cap")
    func truncatesReadme() throws {
        let dir = tempFolder()
        let big = String(repeating: "A", count: DocsEvidence.maxReadmeChars + 500)
        try big.write(to: dir.appendingPathComponent("README"), atomically: true, encoding: .utf8)
        let result = DocsEvidence.extract(fromFolder: dir.path) ?? ""
        #expect(result.count <= DocsEvidence.maxReadmeChars + 200) // room for hint/labels
        #expect(!result.contains(big))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DocsEvidenceTests`
Expected: COMPILE ERROR — `cannot find 'DocsEvidence' in scope`.

- [ ] **Step 3: Implement the extractor and fields**

Create `Sources/AppAudit/Services/DocsEvidence.swift`:

```swift
import Foundation

/// Extracts grounding evidence from an app's LOCAL project folder — the README
/// and which manifest files are present — so the analysis prompt can describe a
/// private-repo or no-repo app from files the user already has on disk. Reads
/// the folder root only; never recurses, never touches the network.
enum DocsEvidence {
    static let maxReadmeChars = 4000

    private static let readmeNames = ["README.md", "README", "README.txt", "README.markdown"]
    private static let manifestNames = [
        "Package.swift", "package.json", "Cargo.toml",
        "pyproject.toml", "go.mod", "Gemfile", "Info.plist"
    ]

    static func extract(fromFolder path: String) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let entries = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        let lowerEntries = Set(entries.map { $0.lowercased() })

        var parts: [String] = []

        // README (first case-insensitive match, truncated).
        if let readmeName = readmeNames.first(where: { lowerEntries.contains($0.lowercased()) }),
           let actual = entries.first(where: { $0.lowercased() == readmeName.lowercased() }),
           let text = try? String(contentsOf: folder.appendingPathComponent(actual), encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let clipped = trimmed.count > maxReadmeChars
                    ? String(trimmed.prefix(maxReadmeChars)) + "…"
                    : trimmed
                parts.append(clipped)
            }
        }

        // Stack hint — which manifests are present.
        let foundManifests = manifestNames.filter { lowerEntries.contains($0.lowercased()) }
        if !foundManifests.isEmpty {
            parts.append("Detected project files: \(foundManifests.joined(separator: ", "))")
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}
```

In `Sources/AppAudit/Models/AppRecord.swift`, after `var licenseType: String? = nil` add:

```swift
    var docsEvidence: String? = nil
    var docsFolderPath: String? = nil
```

and in `init`, after `self.licenseType = nil` add:

```swift
        self.docsEvidence = nil
        self.docsFolderPath = nil
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DocsEvidenceTests` — Expected: 4 PASS.
Then: `swift test` — Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Services/DocsEvidence.swift Sources/AppAudit/Models/AppRecord.swift Tests/AppAuditTests/AppAuditTests.swift
git commit -m "feat: DocsEvidence extractor and docsEvidence/docsFolderPath record fields"
```

---

### Task 2: Docs block in the prompt builder

**Files:**
- Modify: `Sources/AppAudit/Services/AppAnalysisPrompt.swift` (the `build` function)
- Test: `Tests/AppAuditTests/AppAuditTests.swift` (append)

**Interfaces:**
- Produces: `AppAnalysisPrompt.build(..., docsEvidence: String = "")` — new trailing parameter after `userNotes`. Empty/whitespace produces today's prompt byte-for-byte.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/AppAuditTests/AppAuditTests.swift`:

```swift
@Suite("Analysis Prompt Docs Evidence")
struct AnalysisPromptDocsEvidenceTests {
    private var app: AppInfo {
        AppInfo(id: "com.x", name: "X", version: "1", bundleID: "com.x",
                path: "/Applications/X.app", humanReadableDescription: nil,
                sparkleFeedURL: nil, isAppStoreInstall: false, icon: nil)
    }

    @Test("Docs evidence appears as primary evidence when provided")
    func docsIncluded() {
        let prompt = AppAnalysisPrompt.build(app: app, profile: .generic(),
                                             includeResponseFormat: true,
                                             docsEvidence: "A menu-bar batch renamer.\nDetected project files: Package.swift")
        #expect(prompt.contains("From the app's own project files"))
        #expect(prompt.contains("A menu-bar batch renamer."))
        #expect(prompt.contains("the app's own project files outrank"))
    }

    @Test("No docs block when evidence is empty or whitespace")
    func emptyOmits() {
        let empty = AppAnalysisPrompt.build(app: app, profile: .generic(), includeResponseFormat: true)
        let whitespace = AppAnalysisPrompt.build(app: app, profile: .generic(),
                                                 includeResponseFormat: true, docsEvidence: "   \n")
        #expect(!empty.contains("From the app's own project files"))
        #expect(empty == whitespace)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AnalysisPromptDocsEvidenceTests`
Expected: COMPILE ERROR — `extra argument 'docsEvidence' in call`.

- [ ] **Step 3: Implement**

In `Sources/AppAudit/Services/AppAnalysisPrompt.swift`, change the `build` signature to add a trailing parameter:

```swift
    static func build(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil, linkEvidence: String? = nil, includeResponseFormat: Bool, styleNotes: String = "", userNotes: String = "", docsEvidence: String = "") -> String {
```

After the `notesEvidenceRule` declaration (right before `return """`), add:

```swift
        let trimmedDocs = docsEvidence.trimmingCharacters(in: .whitespacesAndNewlines)
        let docsBlock = trimmedDocs.isEmpty
            ? ""
            : "\n\nFrom the app's own project files (provided by the user — treat as the strongest evidence for what this app is):\n\(trimmedDocs)"
        let docsEvidenceRule = trimmedDocs.isEmpty
            ? ""
            : "\n- When present, the app's own project files outrank URL and metadata evidence for what the app is, but never invent facts they do not state."
```

Interpolate `\(docsBlock)` immediately after `\(notesBlock)`:

```swift
        Developer workflow context:
        \(profile.promptDescription)\(notesBlock)\(docsBlock)
```

Interpolate `\(docsEvidenceRule)` immediately after `\(notesEvidenceRule)`:

```swift
        - Score unclear apps conservatively unless the metadata clearly matches the workflow.\(notesEvidenceRule)\(docsEvidenceRule)
        \(responseFormat)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AnalysisPromptDocsEvidenceTests` — Expected: 2 PASS.
Then: `swift test` — Expected: all PASS (empty-docs prompt unchanged, so existing prompt tests stay green).

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Services/AppAnalysisPrompt.swift Tests/AppAuditTests/AppAuditTests.swift
git commit -m "feat: inject local docs evidence into the analysis prompt"
```

---

### Task 3: Thread docsEvidence through providers and every analysis path

**Files:**
- Modify: `Sources/AppAudit/Services/AnalysisService.swift:19` (protocol `analyze`)
- Modify: `Sources/AppAudit/Services/OllamaService.swift:110-121`, `AnthropicService.swift:33-34`, `OpenAIService.swift:34-35` (`analyze`)
- Modify: `Sources/AppAudit/ViewModels/AppListViewModel.swift` — `enrichSingle` (line ~370), both `enrichConcurrently` capture sites (~314 and ~358), `reanalyze` (~613)

**Interfaces:**
- Consumes: `AppAnalysisPrompt.build(..., docsEvidence:)` from Task 2.
- Produces: `analyze(app:profile:appURL:linkEvidence:userNotes:docsEvidence:)` on the protocol and all three providers (each `docsEvidence: String? = nil`, forwarded as `docsEvidence ?? ""`). `enrichSingle` gains `docsEvidence: String? = nil`. Every call site loads the cached record's `docsEvidence` next to `notes`.

Verification is a clean build + the existing suite; the prompt content is already tested in Task 2 and the loading mirrors the proven `notes` pattern.

- [ ] **Step 1: Update the protocol**

In `Sources/AppAudit/Services/AnalysisService.swift`, replace the `analyze` requirement (line 19) with:

```swift
    func analyze(app: AppInfo, profile: WorkflowProfile, appURL: String?, linkEvidence: String?, userNotes: String?, docsEvidence: String?) async -> AnalysisResult
```

- [ ] **Step 2: Update the three providers**

`OllamaService.swift` — replace the `analyze` function (lines 110–121) with:

```swift
    /// Single request returning explanation, score, reason, and best use — 3x faster than separate calls.
    func analyze(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil, linkEvidence: String? = nil, userNotes: String? = nil, docsEvidence: String? = nil) async -> OllamaResult {
        let prompt = AppAnalysisPrompt.build(
            app: app,
            profile: profile,
            appURL: appURL,
            linkEvidence: linkEvidence,
            includeResponseFormat: true,
            styleNotes: AppAnalysisPrompt.currentStyleNotes,
            userNotes: userNotes ?? "",
            docsEvidence: docsEvidence ?? ""
        )
        return await chat(messages: [.init(role: "user", content: prompt)])
    }
```

`AnthropicService.swift` — replace lines 33–34 with:

```swift
    func analyze(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil, linkEvidence: String? = nil, userNotes: String? = nil, docsEvidence: String? = nil) async -> AnalysisResult {
        let prompt = AppAnalysisPrompt.build(app: app, profile: profile, appURL: appURL, linkEvidence: linkEvidence, includeResponseFormat: true, styleNotes: AppAnalysisPrompt.currentStyleNotes, userNotes: userNotes ?? "", docsEvidence: docsEvidence ?? "")
```

`OpenAIService.swift` — replace lines 34–35 with:

```swift
    func analyze(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil, linkEvidence: String? = nil, userNotes: String? = nil, docsEvidence: String? = nil) async -> AnalysisResult {
        let prompt = AppAnalysisPrompt.build(app: app, profile: profile, appURL: appURL, linkEvidence: linkEvidence, includeResponseFormat: true, styleNotes: AppAnalysisPrompt.currentStyleNotes, userNotes: userNotes ?? "", docsEvidence: docsEvidence ?? "")
```

- [ ] **Step 3: Update `enrichSingle`**

In `AppListViewModel.swift`, replace the `enrichSingle` signature and provider switch (lines ~370–386) with:

```swift
    nonisolated private func enrichSingle(
        app: AppInfo,
        profile: WorkflowProfile,
        provider: AnalysisProviderKind,
        appURL: String? = nil,
        userNotes: String? = nil,
        docsEvidence: String? = nil
    ) async -> (String, AppInfo.AIState) {
        let linkEvidence = await linkEvidenceService.evidence(for: appURL)
        let result: AnalysisResult
        switch provider {
        case .ollama:
            result = await ollama.analyze(app: app, profile: profile, appURL: appURL, linkEvidence: linkEvidence, userNotes: userNotes, docsEvidence: docsEvidence)
        case .anthropic:
            result = await anthropic.analyze(app: app, profile: profile, appURL: appURL, linkEvidence: linkEvidence, userNotes: userNotes, docsEvidence: docsEvidence)
        case .openAI:
            result = await openAI.analyze(app: app, profile: profile, appURL: appURL, linkEvidence: linkEvidence, userNotes: userNotes, docsEvidence: docsEvidence)
        }
```

(The rest of `enrichSingle` — parsing and fallback — is unchanged.)

- [ ] **Step 4: Load docs at the two concurrent capture sites**

In `enrichConcurrently`, the seed-loop site currently reads (around lines 314–319):

```swift
                let capturedRecord = self.cacheService?.load(bundleID: app.bundleID)
                let capturedAppURL = capturedRecord?.appURL
                let capturedNotes = capturedRecord?.notes
                group.addTask {
                    let result = await self.enrichSingle(app: capturedApp, profile: capturedProfile, provider: capturedProvider, appURL: capturedAppURL, userNotes: capturedNotes)
                    return (result.0, result.1, capturedAppURL)
                }
```

Add `capturedDocs` and pass it:

```swift
                let capturedRecord = self.cacheService?.load(bundleID: app.bundleID)
                let capturedAppURL = capturedRecord?.appURL
                let capturedNotes = capturedRecord?.notes
                let capturedDocs = capturedRecord?.docsEvidence
                group.addTask {
                    let result = await self.enrichSingle(app: capturedApp, profile: capturedProfile, provider: capturedProvider, appURL: capturedAppURL, userNotes: capturedNotes, docsEvidence: capturedDocs)
                    return (result.0, result.1, capturedAppURL)
                }
```

Apply the identical change to the refill site (around lines 358–363), where the variables are `next` / `capturedNext`:

```swift
                    let capturedRecord = self.cacheService?.load(bundleID: next.bundleID)
                    let capturedAppURL = capturedRecord?.appURL
                    let capturedNotes = capturedRecord?.notes
                    let capturedDocs = capturedRecord?.docsEvidence
                    group.addTask {
                        let result = await self.enrichSingle(app: capturedNext, profile: capturedProfile, provider: capturedProvider, appURL: capturedAppURL, userNotes: capturedNotes, docsEvidence: capturedDocs)
                        return (result.0, result.1, capturedAppURL)
                    }
```

- [ ] **Step 5: Load docs in `reanalyze`**

In `reanalyze` (around lines 613–619), the current lines:

```swift
        let cachedRecord = cacheService?.load(bundleID: bundleID)
        let appURL = overrideAppURL ?? cachedRecord?.appURL
        let userNotes = cachedRecord?.notes
        workflowProfile = .current(digest: WorkflowDigest.build(from: apps))
        apps[idx].aiState = .loading
        let provider = AnalysisProviderKind.current()
        let result = await enrichSingle(app: apps[idx], profile: workflowProfile, provider: provider, appURL: appURL, userNotes: userNotes)
```

become:

```swift
        let cachedRecord = cacheService?.load(bundleID: bundleID)
        let appURL = overrideAppURL ?? cachedRecord?.appURL
        let userNotes = cachedRecord?.notes
        let docsEvidence = cachedRecord?.docsEvidence
        workflowProfile = .current(digest: WorkflowDigest.build(from: apps))
        apps[idx].aiState = .loading
        let provider = AnalysisProviderKind.current()
        let result = await enrichSingle(app: apps[idx], profile: workflowProfile, provider: provider, appURL: appURL, userNotes: userNotes, docsEvidence: docsEvidence)
```

- [ ] **Step 6: Build and run the full suite**

Run: `swift build && swift test`
Expected: builds cleanly, all tests PASS. If a provider fails to conform, its `analyze` signature does not match the protocol exactly — fix the signature.

- [ ] **Step 7: Commit**

```bash
git add Sources/AppAudit/Services/AnalysisService.swift Sources/AppAudit/Services/OllamaService.swift Sources/AppAudit/Services/AnthropicService.swift Sources/AppAudit/Services/OpenAIService.swift Sources/AppAudit/ViewModels/AppListViewModel.swift
git commit -m "feat: load local docs evidence on every analysis path"
```

---

### Task 4: `reanalyzeAfterDocsChange` trigger

**Files:**
- Modify: `Sources/AppAudit/ViewModels/AppListViewModel.swift` — add below `reanalyzeAfterLinkChange`

**Interfaces:**
- Consumes: `reanalyze(bundleID:)` (existing).
- Produces: `AppListViewModel.reanalyzeAfterDocsChange(bundleID: String)` — lock-respecting; fires `reanalyze` when neither the in-memory app nor the cached record is locked.

- [ ] **Step 1: Implement (mirrors `reanalyzeAfterLinkChange`)**

In `AppListViewModel.swift`, directly below the closing brace of `reanalyzeAfterLinkChange` (around line 700), add:

```swift
    /// Re-runs analysis after the user attaches, refreshes, or removes an app's
    /// local docs folder, so the new evidence feeds the prompt. Locked analyses
    /// are never re-run — the evidence waits for a manual run after unlocking.
    func reanalyzeAfterDocsChange(bundleID: String) {
        guard let idx = apps.firstIndex(where: { $0.bundleID == bundleID }),
              !apps[idx].isAnalysisLocked,
              cacheService?.load(bundleID: bundleID)?.isAnalysisLocked != true else {
            return
        }
        Task {
            await reanalyze(bundleID: bundleID)
        }
    }
```

- [ ] **Step 2: Build and run the full suite**

Run: `swift build && swift test`
Expected: builds cleanly, all tests PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/AppAudit/ViewModels/AppListViewModel.swift
git commit -m "feat: reanalyze after an app's docs folder changes (lock-respecting)"
```

---

### Task 5: The Docs cube + docs

**Files:**
- Modify: `Sources/AppAudit/Views/AppDetailView.swift` — add `docsCard` to `utilitySection`, plus attach/refresh/remove helpers
- Modify: `FEATURES.md`

**Interfaces:**
- Consumes: `DocsEvidence.extract(fromFolder:)`, `viewModel.reanalyzeAfterDocsChange(bundleID:)`, `ensureRecord()`, `saveRecord()`, the existing `UtilityCard` (with `tint`, `active`, `action`), `cardIcon`.
- Produces: user-visible 7th cube; attach opens `NSOpenPanel`, refresh re-reads the stored path, remove clears both fields — each triggers reanalysis.

- [ ] **Step 1: Add `docsCard` to the row**

In `utilitySection`'s `HStack`, add `docsCard` after `favoriteCard`:

```swift
        HStack(alignment: .top, spacing: 12) {
            notesCard
            licenseCard
            subscriptionCard
            linkCard
            lockCard
            favoriteCard
            docsCard
        }
```

- [ ] **Step 2: Implement the cube and its actions**

Add near the other cube definitions in `AppDetailView`:

```swift
    private var docsCard: some View {
        let hasDocs = record?.docsEvidence?.isEmpty == false
        return UtilityCard(tint: .teal, active: hasDocs, action: {
            if hasDocs { refreshDocs() } else { attachDocsFolder() }
        }) {
            cardIcon("doc.text", tint: hasDocs ? .teal : .secondary)
        }
        .help(docsHelp)
        .contextMenu {
            Button {
                attachDocsFolder()
            } label: {
                Label(hasDocs ? "Change Folder…" : "Attach Project Folder…", systemImage: "folder")
            }
            if hasDocs {
                Button {
                    refreshDocs()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                if let path = record?.docsFolderPath, !path.isEmpty {
                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                    } label: {
                        Label("Reveal Source in Finder", systemImage: "magnifyingglass")
                    }
                }
                Button(role: .destructive) {
                    removeDocs()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }

    private var docsHelp: String {
        guard let evidence = record?.docsEvidence, !evidence.isEmpty else {
            return "Attach this app's project folder — Sift reads its README to ground the analysis"
        }
        let source = record?.docsFolderPath.map { " · \($0)" } ?? ""
        let snippet = evidence.replacingOccurrences(of: "\n", with: " ").prefix(80)
        return "Docs attached\(source)\n\(snippet)…"
    }

    private func attachDocsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Attach"
        panel.message = "Choose \(app.name)'s project folder (Sift reads its README and manifest)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        storeDocs(fromFolder: url.path)
    }

    private func refreshDocs() {
        guard let path = record?.docsFolderPath, !path.isEmpty else { return }
        storeDocs(fromFolder: path)
    }

    private func storeDocs(fromFolder path: String) {
        guard let evidence = DocsEvidence.extract(fromFolder: path) else {
            docsMessage = "No README or manifest found in that folder."
            return
        }
        let ensured = ensureRecord()
        ensured.docsEvidence = evidence
        ensured.docsFolderPath = path
        saveRecord()
        viewModel.reanalyzeAfterDocsChange(bundleID: app.bundleID)
    }

    private func removeDocs() {
        let ensured = ensureRecord()
        ensured.docsEvidence = nil
        ensured.docsFolderPath = nil
        saveRecord()
        viewModel.reanalyzeAfterDocsChange(bundleID: app.bundleID)
    }
```

Add a dedicated `@State` var alongside the other detail-view state (near `homebrewUpdateMessage`):

```swift
    @State private var docsMessage: String? = nil
```

And a matching informational alert in `body`, right after the existing `homebrewUpdateMessage` alert:

```swift
        .alert(
            "Docs",
            isPresented: Binding(
                get: { docsMessage != nil },
                set: { if !$0 { docsMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(docsMessage ?? "")
        }
```

- [ ] **Step 3: Build and run the full suite**

Run: `swift build && swift test`
Expected: builds cleanly, all tests PASS.

- [ ] **Step 4: Manual smoke test (defer if headless)**

Run `bash Scripts/build_sift2.sh`, open Sift2, pick an app, click the teal Docs cube, choose a repo folder with a README → the analysis re-runs and reflects the README; the cube turns teal. Right-click → Remove → analysis re-runs without it. (If you cannot drive the GUI, note this as deferred; the build + suite must still pass.)

- [ ] **Step 5: Update FEATURES.md**

Under the utility-cube bullet in `FEATURES.md`, add:

```markdown
- **Docs cube**: attach an app's local **project folder** and Sift reads its README (and notes which manifest files are present) as primary evidence — grounding analysis for your own apps with private or no public repo, fully offline. Tap to attach, tap again to refresh after you edit the README, right-click to change/reveal/remove. Attaching, refreshing, or removing re-runs the analysis.
```

- [ ] **Step 6: Commit**

```bash
git add Sources/AppAudit/Views/AppDetailView.swift FEATURES.md
git commit -m "feat: Docs cube — attach a local project folder as analysis evidence"
```

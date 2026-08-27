# Notes Feed the Analysis — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The per-app Notes field becomes evidence in the AI analysis prompt (all providers), and closing the notes editor with changed text auto-triggers a re-analysis of that app.

**Architecture:** All providers share one prompt builder (`AppAnalysisPrompt.build`), so the notes block is injected in one place and threaded through the `AnalysisService` protocol. Notes are loaded from the cached `AppRecord` at analysis time — the same pattern already used for the reference URL — so notes apply to single re-runs, "re-analyze all," and full scans. The UI trigger mirrors the existing `reanalyzeAfterLinkChange` pattern and respects analysis locks.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData, Swift Testing (`@Suite`/`@Test`/`#expect`), macOS 14+.

**Spec:** `docs/archive/superpowers/specs/2026-07-04-notes-analysis-unranked-myapps-design.md` (sections 1–2 only; section 3 "Unranked My Apps" is a later phase — do NOT implement it).

## Global Constraints

- Product is **Sift**, but sources live under `Sources/AppAudit/` and the bundle ID stays `com.kikaapp.appaudit` — never rename these.
- All providers must keep sharing the single prompt builder `AppAnalysisPrompt.build` — no per-provider prompt text.
- Locked analyses (`isAnalysisLocked`, both on the in-memory `AppInfo` and the cached `AppRecord`) must never be re-run automatically.
- Run tests with `swift test` from the repo root. All existing tests must stay green after every task.
- Test file: everything lives in the single `Tests/AppAuditTests/AppAuditTests.swift` — append new suites there, matching the existing `@Suite`/`@Test` style.

---

### Task 1: Notes block in the prompt builder

**Files:**
- Modify: `Sources/AppAudit/Services/AppAnalysisPrompt.swift:13-58` (the `build` function)
- Test: `Tests/AppAuditTests/AppAuditTests.swift` (append new suite)

**Interfaces:**
- Produces: `AppAnalysisPrompt.build(app:profile:appURL:linkEvidence:includeResponseFormat:styleNotes:userNotes:)` — new `userNotes: String = ""` parameter. Empty/whitespace notes produce a byte-identical prompt to today's.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/AppAuditTests/AppAuditTests.swift`:

```swift
@Suite("Analysis Prompt User Notes")
struct AnalysisPromptUserNotesTests {
    private var app: AppInfo {
        AppInfo(id: "com.x", name: "X", version: "1", bundleID: "com.x",
                path: "/Applications/X.app", humanReadableDescription: nil,
                sparkleFeedURL: nil, isAppStoreInstall: false, icon: nil)
    }

    @Test("User notes appear as strongest personal-usage evidence")
    func notesIncluded() {
        let prompt = AppAnalysisPrompt.build(app: app, profile: .generic(),
                                             includeResponseFormat: true,
                                             userNotes: "I use this daily to cut release videos.")
        #expect(prompt.contains("The user's own notes about this app"))
        #expect(prompt.contains("I use this daily to cut release videos."))
        #expect(prompt.contains("The user's own notes outrank URL and metadata evidence"))
    }

    @Test("No notes block when notes are empty or whitespace")
    func emptyOmits() {
        let empty = AppAnalysisPrompt.build(app: app, profile: .generic(),
                                            includeResponseFormat: true)
        let whitespace = AppAnalysisPrompt.build(app: app, profile: .generic(),
                                                 includeResponseFormat: true,
                                                 userNotes: "  \n ")
        #expect(!empty.contains("The user's own notes"))
        #expect(!whitespace.contains("The user's own notes"))
        #expect(empty == whitespace)
    }

    @Test("Notes coexist with style notes without collision")
    func coexistsWithStyleNotes() {
        let prompt = AppAnalysisPrompt.build(app: app, profile: .generic(),
                                             includeResponseFormat: false,
                                             styleNotes: "Mention alternatives.",
                                             userNotes: "Learning this app's features.")
        #expect(prompt.contains("Learning this app's features."))
        #expect(prompt.contains("Mention alternatives."))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AnalysisPromptUserNotesTests`
Expected: COMPILE ERROR — `extra argument 'userNotes' in call` (the parameter does not exist yet).

- [ ] **Step 3: Implement the notes block**

In `Sources/AppAudit/Services/AppAnalysisPrompt.swift`, change the `build` signature (line 13):

```swift
static func build(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil, linkEvidence: String? = nil, includeResponseFormat: Bool, styleNotes: String = "", userNotes: String = "") -> String {
```

After the `styleBlock` declaration (currently lines 26–29), add:

```swift
        let trimmedUserNotes = userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesBlock = trimmedUserNotes.isEmpty
            ? ""
            : "\n\nThe user's own notes about this app (their raw words — treat as the strongest evidence for how THEY use it):\n\(trimmedUserNotes)"
        let notesEvidenceRule = trimmedUserNotes.isEmpty
            ? ""
            : "\n- The user's own notes outrank URL and metadata evidence when scoring and writing BEST_USE, but never invent product facts the notes do not state."
```

(No leading spaces inside the interpolated strings: Swift de-indents only the literal lines of a `"""` string, not interpolated content — the existing `styleBlock` on lines 26–29 follows the same convention.)

In the returned multiline string, make two insertions:

1. Interpolate `\(notesBlock)` immediately after `\(profile.promptDescription)`:

```swift
        Developer workflow context:
        \(profile.promptDescription)\(notesBlock)
```

2. Interpolate `\(notesEvidenceRule)` after the final evidence rule line:

```swift
        - Score unclear apps conservatively unless the metadata clearly matches the workflow.\(notesEvidenceRule)
        \(responseFormat)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AnalysisPromptUserNotesTests` — Expected: 3 PASS.
Then run the full suite: `swift test` — Expected: all PASS (the empty-notes prompt is unchanged, so existing prompt tests stay green).

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Services/AppAnalysisPrompt.swift Tests/AppAuditTests/AppAuditTests.swift
git commit -m "feat: inject per-app user notes into the analysis prompt"
```

---

### Task 2: Thread userNotes through the provider protocol

**Files:**
- Modify: `Sources/AppAudit/Services/AnalysisService.swift:19` (protocol)
- Modify: `Sources/AppAudit/Services/OllamaService.swift:110-120` (`analyze`)
- Modify: `Sources/AppAudit/Services/AnthropicService.swift:33-34` (`analyze`)
- Modify: `Sources/AppAudit/Services/OpenAIService.swift:34-35` (`analyze`)

**Interfaces:**
- Consumes: `AppAnalysisPrompt.build(..., userNotes:)` from Task 1.
- Produces: `AnalysisService.analyze(app:profile:appURL:linkEvidence:userNotes:)` — all three providers accept `userNotes: String? = nil` and forward it to the prompt builder as `userNotes ?? ""`.

This task is a mechanical signature change with no observable behavior of its own (the prompt content is already tested in Task 1), so the verification is: it compiles and the existing suite stays green.

- [ ] **Step 1: Update the protocol**

In `Sources/AppAudit/Services/AnalysisService.swift`, replace line 19 with:

```swift
    func analyze(app: AppInfo, profile: WorkflowProfile, appURL: String?, linkEvidence: String?, userNotes: String?) async -> AnalysisResult
```

- [ ] **Step 2: Update OllamaService**

In `Sources/AppAudit/Services/OllamaService.swift`, replace the `analyze` function (lines 110–120) with:

```swift
    /// Single request returning explanation, score, reason, and best use — 3x faster than separate calls.
    func analyze(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil, linkEvidence: String? = nil, userNotes: String? = nil) async -> OllamaResult {
        let prompt = AppAnalysisPrompt.build(
            app: app,
            profile: profile,
            appURL: appURL,
            linkEvidence: linkEvidence,
            includeResponseFormat: true,
            styleNotes: AppAnalysisPrompt.currentStyleNotes,
            userNotes: userNotes ?? ""
        )
        return await chat(messages: [.init(role: "user", content: prompt)])
    }
```

The convenience wrappers at lines 185–187 (`explain`/`score`/`bestUse`) need no change — the new parameter defaults to `nil`.

- [ ] **Step 3: Update AnthropicService and OpenAIService**

In `Sources/AppAudit/Services/AnthropicService.swift`, replace lines 33–34 with:

```swift
    func analyze(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil, linkEvidence: String? = nil, userNotes: String? = nil) async -> AnalysisResult {
        let prompt = AppAnalysisPrompt.build(app: app, profile: profile, appURL: appURL, linkEvidence: linkEvidence, includeResponseFormat: true, styleNotes: AppAnalysisPrompt.currentStyleNotes, userNotes: userNotes ?? "")
```

In `Sources/AppAudit/Services/OpenAIService.swift`, replace lines 34–35 with:

```swift
    func analyze(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil, linkEvidence: String? = nil, userNotes: String? = nil) async -> AnalysisResult {
        let prompt = AppAnalysisPrompt.build(app: app, profile: profile, appURL: appURL, linkEvidence: linkEvidence, includeResponseFormat: true, styleNotes: AppAnalysisPrompt.currentStyleNotes, userNotes: userNotes ?? "")
```

(Only the function signature line and the `AppAnalysisPrompt.build` call line change in each file; the rest of each function body stays as is.)

- [ ] **Step 4: Build and run the full suite**

Run: `swift build && swift test`
Expected: builds cleanly, all tests PASS. If the compiler reports a non-conforming type, a provider signature does not exactly match the protocol — fix the signature, not the protocol.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Services/AnalysisService.swift Sources/AppAudit/Services/OllamaService.swift Sources/AppAudit/Services/AnthropicService.swift Sources/AppAudit/Services/OpenAIService.swift
git commit -m "feat: thread per-app user notes through all analysis providers"
```

---

### Task 3: Load notes from the cached record at analysis time

**Files:**
- Modify: `Sources/AppAudit/ViewModels/AppListViewModel.swift` — `enrichSingle` (line 366), `enrichConcurrently` (both `addTask` capture sites, ~lines 310–319 and ~352–361), `reanalyze(bundleID:)` (line 602)

**Interfaces:**
- Consumes: `AnalysisService.analyze(..., userNotes:)` from Task 2; `CacheService.load(bundleID:) -> AppRecord?` (existing).
- Produces: every analysis path (single re-run, re-analyze all, initial scan enrichment) passes the cached record's `notes` into the provider.

There is no unit-test seam for `AppListViewModel`'s enrichment pipeline (it drives live providers), so this task verifies by compilation, the existing suite, and the pattern being identical to the existing `appURL` loading on the very same lines.

- [ ] **Step 1: Add the parameter to `enrichSingle`**

Replace the `enrichSingle` signature and provider switch (lines 366–380) with:

```swift
    nonisolated private func enrichSingle(
        app: AppInfo,
        profile: WorkflowProfile,
        provider: AnalysisProviderKind,
        appURL: String? = nil,
        userNotes: String? = nil
    ) async -> (String, AppInfo.AIState) {
        let linkEvidence = await linkEvidenceService.evidence(for: appURL)
        let result: AnalysisResult
        switch provider {
        case .ollama:
            result = await ollama.analyze(app: app, profile: profile, appURL: appURL, linkEvidence: linkEvidence, userNotes: userNotes)
        case .anthropic:
            result = await anthropic.analyze(app: app, profile: profile, appURL: appURL, linkEvidence: linkEvidence, userNotes: userNotes)
        case .openAI:
            result = await openAI.analyze(app: app, profile: profile, appURL: appURL, linkEvidence: linkEvidence, userNotes: userNotes)
        }
```

(The rest of `enrichSingle` — result parsing and the fallback — is unchanged.)

- [ ] **Step 2: Capture notes in `enrichConcurrently`**

In BOTH `group.addTask` capture sites inside `enrichConcurrently` (the seed loop and the refill inside `for await`), the current code reads:

```swift
                let capturedAppURL = self.cacheService?.load(bundleID: app.bundleID)?.appURL
                group.addTask {
                    let result = await self.enrichSingle(app: capturedApp, profile: capturedProfile, provider: capturedProvider, appURL: capturedAppURL)
                    return (result.0, result.1, capturedAppURL)
                }
```

Change each to load the record once and pass notes through (in the refill site the variable is `next`/`capturedNext` instead of `app`/`capturedApp`):

```swift
                let capturedRecord = self.cacheService?.load(bundleID: app.bundleID)
                let capturedAppURL = capturedRecord?.appURL
                let capturedNotes = capturedRecord?.notes
                group.addTask {
                    let result = await self.enrichSingle(app: capturedApp, profile: capturedProfile, provider: capturedProvider, appURL: capturedAppURL, userNotes: capturedNotes)
                    return (result.0, result.1, capturedAppURL)
                }
```

- [ ] **Step 3: Load notes in `reanalyze(bundleID:)`**

In `reanalyze` (line 602), the current lines:

```swift
        let appURL = overrideAppURL ?? cacheService?.load(bundleID: bundleID)?.appURL
        workflowProfile = .current(digest: WorkflowDigest.build(from: apps))
        apps[idx].aiState = .loading
        let provider = AnalysisProviderKind.current()
        let result = await enrichSingle(app: apps[idx], profile: workflowProfile, provider: provider, appURL: appURL)
```

become:

```swift
        let cachedRecord = cacheService?.load(bundleID: bundleID)
        let appURL = overrideAppURL ?? cachedRecord?.appURL
        let userNotes = cachedRecord?.notes
        workflowProfile = .current(digest: WorkflowDigest.build(from: apps))
        apps[idx].aiState = .loading
        let provider = AnalysisProviderKind.current()
        let result = await enrichSingle(app: apps[idx], profile: workflowProfile, provider: provider, appURL: appURL, userNotes: userNotes)
```

- [ ] **Step 4: Build and run the full suite**

Run: `swift build && swift test`
Expected: builds cleanly, all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/ViewModels/AppListViewModel.swift
git commit -m "feat: load per-app notes from the cached record for every analysis path"
```

---

### Task 4: Change detection + `reanalyzeAfterNotesChange`

**Files:**
- Modify: `Sources/AppAudit/ViewModels/AppListViewModel.swift` — add `NotesChange` helper and `reanalyzeAfterNotesChange(bundleID:previousNotes:)` directly below the existing `reanalyzeAfterLinkChange` (line 686)
- Test: `Tests/AppAuditTests/AppAuditTests.swift` (append new suite)

**Interfaces:**
- Consumes: `reanalyze(bundleID:)` (existing), `CacheService.load(bundleID:)` (existing).
- Produces:
  - `NotesChange.changed(previous: String?, current: String?) -> Bool` — pure, nonisolated; nil, empty, and whitespace-only are all equivalent "no note."
  - `AppListViewModel.reanalyzeAfterNotesChange(bundleID: String, previousNotes: String?)` — main-actor method the UI calls when a notes editing session ends; no-ops for locked apps and unchanged notes.

- [ ] **Step 1: Write the failing tests for the change detector**

Append to `Tests/AppAuditTests/AppAuditTests.swift`:

```swift
@Suite("Notes Change Detection")
struct NotesChangeDetectionTests {
    @Test("Different text is a change")
    func differentText() {
        #expect(NotesChange.changed(previous: "old", current: "new"))
        #expect(NotesChange.changed(previous: nil, current: "new note"))
        #expect(NotesChange.changed(previous: "had a note", current: nil))
    }

    @Test("Nil, empty, and whitespace are all 'no note' — not a change")
    func noNoteEquivalence() {
        #expect(!NotesChange.changed(previous: nil, current: ""))
        #expect(!NotesChange.changed(previous: "", current: "   \n"))
        #expect(!NotesChange.changed(previous: nil, current: nil))
    }

    @Test("Whitespace-only edits are not a change")
    func whitespaceEditsIgnored() {
        #expect(!NotesChange.changed(previous: "same note", current: "same note  \n"))
        #expect(!NotesChange.changed(previous: " same note", current: "same note"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter NotesChangeDetectionTests`
Expected: COMPILE ERROR — `cannot find 'NotesChange' in scope`.

- [ ] **Step 3: Implement the helper and the view-model method**

In `Sources/AppAudit/ViewModels/AppListViewModel.swift`, directly below `reanalyzeAfterLinkChange` (after its closing brace at ~line 696), add the method; add the `NotesChange` enum at file scope (bottom of the file, outside the class):

```swift
    /// Called when a notes editing session ends (the editor collapsed or the
    /// selection changed). Re-runs analysis when the note text meaningfully
    /// changed since the session began, so the new note feeds the prompt.
    /// Locked analyses are never re-run — the note waits for a manual run.
    func reanalyzeAfterNotesChange(bundleID: String, previousNotes: String?) {
        guard let idx = apps.firstIndex(where: { $0.bundleID == bundleID }),
              !apps[idx].isAnalysisLocked,
              let record = cacheService?.load(bundleID: bundleID),
              !record.isAnalysisLocked,
              NotesChange.changed(previous: previousNotes, current: record.notes) else {
            return
        }

        Task {
            await reanalyze(bundleID: bundleID)
        }
    }
```

```swift
/// Decides whether a note edit is worth an automatic re-analysis.
/// nil, empty, and whitespace-only text are all treated as "no note".
enum NotesChange {
    static func changed(previous: String?, current: String?) -> Bool {
        func normalized(_ text: String?) -> String {
            (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return normalized(previous) != normalized(current)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter NotesChangeDetectionTests` — Expected: 3 PASS.
Then: `swift test` — Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/ViewModels/AppListViewModel.swift Tests/AppAuditTests/AppAuditTests.swift
git commit -m "feat: add lock-respecting reanalyzeAfterNotesChange with change detection"
```

---

### Task 5: UI trigger in the notes editor + docs

**Files:**
- Modify: `Sources/AppAudit/Views/AppDetailView.swift` — state vars (~line 24) and `notesSection` (lines 472–527)
- Modify: `FEATURES.md`, `README.md` (one line each)

**Interfaces:**
- Consumes: `viewModel.reanalyzeAfterNotesChange(bundleID:previousNotes:)` from Task 4.
- Produces: user-visible behavior — closing the notes editor (or switching apps, which auto-collapses it) triggers re-analysis if the note changed.

The session snapshot captures BOTH the bundle ID and the note text when the editor expands. This matters: the existing `.onChange(of: app.bundleID)` collapses the editor *after* the selection has already moved to the new app, so the collapse handler must use the captured bundle ID, not `app.bundleID`.

- [ ] **Step 1: Add session state**

In `AppDetailView`'s state block, below `@State private var notesHovered = false` (line 24), add:

```swift
    @State private var notesSessionBundleID: String? = nil
    @State private var notesSessionInitialNotes: String? = nil
```

- [ ] **Step 2: Wire the session to editor expansion/collapse**

In `notesSection`, on the outer `VStack` chain a new `.onChange` directly BEFORE the existing `.onChange(of: app.bundleID)` modifier:

```swift
        .onChange(of: notesExpanded) { _, expanded in
            if expanded {
                notesSessionBundleID = app.bundleID
                notesSessionInitialNotes = record?.notes
            } else {
                endNotesSession()
            }
        }
```

And add the private helper next to `notesSection`:

```swift
    private func endNotesSession() {
        guard let bundleID = notesSessionBundleID else { return }
        viewModel.reanalyzeAfterNotesChange(bundleID: bundleID,
                                            previousNotes: notesSessionInitialNotes)
        notesSessionBundleID = nil
        notesSessionInitialNotes = nil
    }
```

Why this covers all the session-end paths:
- **Collapse via the pencil button or header tap** → `notesExpanded` flips to false → `endNotesSession()`.
- **Switching apps while the editor is open** → the existing `.onChange(of: app.bundleID)` sets `notesExpanded = false` → same path, and the captured `notesSessionBundleID` still points at the *previous* app, so the right app is re-analyzed. (Note edits save on every keystroke, so the previous app's record already holds the final text.)
- **Locked app** → `reanalyzeAfterNotesChange` no-ops; nothing to guard in the view.

- [ ] **Step 3: Build and verify behavior compiles clean**

Run: `swift build && swift test`
Expected: builds cleanly, all tests PASS.

- [ ] **Step 4: Manual smoke test**

Run the app (`swift run` or the project's usual run path). Verify:
1. Open an app's detail view, expand Notes, type "I use this daily for X", collapse the editor → the score badge flips to the loading spinner and a fresh analysis lands, reflecting the note.
2. Re-open the editor, change nothing, collapse → no re-analysis (badge untouched).
3. On an analysis-locked app: edit a note, collapse → note saves, no re-analysis.

- [ ] **Step 5: Update docs**

In `FEATURES.md`, in the section listing notes/analysis features, add:

```markdown
- Per-app notes feed the AI analysis as personal-usage evidence — write "I use this for x y z" and the next analysis (auto-triggered when you close the notes editor) scores and recommends around how *you* actually use the app. Locked analyses just keep the note for the next manual run.
```

In `README.md`, the opening description paragraph says "and lets you keep notes" — change that phrase to "and lets you keep notes that personalize the next analysis".

- [ ] **Step 6: Commit**

```bash
git add Sources/AppAudit/Views/AppDetailView.swift FEATURES.md README.md
git commit -m "feat: auto re-analyze when an app's notes change; document notes-as-evidence"
```

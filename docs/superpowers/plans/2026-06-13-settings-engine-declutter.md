# Settings "Models" Tab Declutter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Settings → Models tab lead with the active engine (Apple Intelligence by default), move the Engine picker into a collapsed "Advanced" disclosure, drop the redundant "Provider" header and the meaningless pinned Model row for Apple Intelligence.

**Architecture:** Pure SwiftUI reorganization of `AnalysisSettingsTab.body` in `SettingsView.swift`. No model, service, persistence, or default-logic changes — `@AppStorage(AnalysisProviderKind.storageKey)` stays the source of truth; the capability-aware first-run default already exists elsewhere. A `DisclosureGroup` holds the Engine picker; it auto-expands once on appear when the active engine isn't Apple Intelligence.

**Tech Stack:** Swift 6, SwiftUI. Builds prefixed `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (standalone CLT broken on macOS 27).

---

## Environment note

Prefix every `swift` command: `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`. SourceKit/IDE diagnostics are stale-index noise — only real `swift build`/`swift test` output counts. Baseline suite: 73 tests. This feature adds no tests (pure Settings UI, consistent with the rest of the Settings views) — verification is build + manual.

## File Structure

- **Modify** `Sources/AppAudit/Views/SettingsView.swift`:
  - `AnalysisSettingsTab.body` — reorder to hero-then-Advanced; add `advancedExpanded` + `didInitAdvanced` state + `.onAppear` one-shot.
  - `AnalysisSettingsTab.appleIntelligenceConfig` — remove the `modelRow(model: $appleIntelligenceModel)` call + one surrounding `Divider`.
  - `SettingsView.tabHeight` — trim the `.models` height.

## Testing philosophy

This is a pure SwiftUI Settings change with no extractable logic, so there are no new unit tests (matching how `AnalysisSettingsTab` / `ProfileSettingsTab` / `ScanningSettingsTab` are already untested). Verification is `swift build` clean + the existing 73 tests still green + a manual Sift2 pass.

---

### Task 1: Reorganize the Models tab — hero engine + Advanced disclosure

**Files:**
- Modify: `Sources/AppAudit/Views/SettingsView.swift`

- [ ] **Step 1: Add the disclosure state**

In `AnalysisSettingsTab`, after the existing `@State private var pccStatus: String? = nil` line, add:

```swift
    @State private var advancedExpanded = false
    @State private var didInitAdvanced = false
```

- [ ] **Step 2: Replace the body**

Replace the entire current `body` (the `var body: some View { ... }` block that starts with `SettingsSectionTitle("Provider")` and ends at the closing brace after the `.task(id: providerRaw)` modifier) with:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionTitle(provider.displayName)
            SettingsCard {
                switch provider {
                case .ollama:
                    ollamaConfig
                case .anthropic:
                    cloudConfig(apiKey: $anthropicApiKey, model: $anthropicModel,
                                hint: "Anthropic API key (console.anthropic.com). Stored in app preferences.")
                case .openAI:
                    cloudConfig(apiKey: $openAIApiKey, model: $openAIModel,
                                hint: "OpenAI API key (platform.openai.com). Stored in app preferences.")
                case .appleIntelligence:
                    appleIntelligenceConfig
                }
            }

            DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
                HStack {
                    Text("Engine")
                        .frame(width: 64, alignment: .leading)
                    Spacer()
                    Picker("", selection: $providerRaw) {
                        ForEach(AnalysisProviderKind.allCases) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 190)
                }
                SettingsFooter("Use a different engine — a local Ollama server or a cloud API.")
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .controlSize(.small)
        .task(id: providerRaw) {
            availableModels = []
            fetchState = .idle
            await fetchModels()
        }
        .onAppear {
            if !didInitAdvanced {
                advancedExpanded = (provider != .appleIntelligence)
                didInitAdvanced = true
            }
        }
    }
```

What changed vs. the original: the literal `SettingsSectionTitle("Provider")` + its Engine `SettingsCard` are gone from the top; the active-engine header (`SettingsSectionTitle(provider.displayName)`) + config card now lead; the Engine picker moved verbatim into a new `DisclosureGroup("Advanced")`; an `.onAppear` one-shot sets the initial expansion. The `.task(id: providerRaw)` block is unchanged.

- [ ] **Step 3: Remove the pinned Model row from Apple Intelligence**

In `appleIntelligenceConfig`, find this block:

```swift
        if appleIntelligenceUsePCC, let pccStatus {
            SettingsFooter(pccStatus)
        }

        Divider()
        modelRow(model: $appleIntelligenceModel)

        Divider()

        HStack(alignment: .top) {
            Text("Style")
```

Replace it with (drop the `modelRow` line and collapse the two dividers to one):

```swift
        if appleIntelligenceUsePCC, let pccStatus {
            SettingsFooter(pccStatus)
        }

        Divider()

        HStack(alignment: .top) {
            Text("Style")
```

Leave the `@AppStorage("appleIntelligenceModel") private var appleIntelligenceModel` declaration in place — it is harmless (the Apple Intelligence model identifier is pinned in the service, not read from this picker) and removing it is out of scope. `ollamaConfig` and `cloudConfig` keep their `modelRow` calls unchanged.

- [ ] **Step 4: Build + test**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build 2>&1 | tail -5`
Expected: `Build complete!` no errors. (A harmless "never used" warning on `appleIntelligenceModel` is acceptable if it appears; it must not be an error.)
Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`
Expected: 73 tests pass (unchanged).

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Views/SettingsView.swift
git commit -m "Settings: Models tab leads with active engine; engine picker under Advanced; drop AI model row"
```

---

### Task 2: Trim the Models tab height + manual verification

**Files:**
- Modify: `Sources/AppAudit/Views/SettingsView.swift`

- [ ] **Step 1: Trim the height**

In `SettingsView.tabHeight`, change the `.models` case from `430` to `400`:

```swift
    private var tabHeight: CGFloat {
        switch selectedTab {
        case .models: return 400
        case .profile: return 300
        case .general: return 290
        }
    }
```

(The tab is shorter now — the Provider card and the AI Model row are gone — so the old 430 left dead space the user disliked. 400 trims it.)

- [ ] **Step 2: Build**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build 2>&1 | tail -3`
Expected: `Build complete!`.

- [ ] **Step 3: Build Sift2 + manual verification (the important part — confirm no clipping)**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash Scripts/build_sift2.sh 2>&1 | tail -1`
Open Sift2 → ⌘, → Models tab. Verify:
- A single header showing the active engine's name (on this Mac: **"Apple Intelligence"**) — NO separate "Provider" header.
- Apple Intelligence config shows Status, the privacy footer, the PCC toggle (+ footers/status), and the **Style** field — but **NO "Model" row**.
- A collapsed **"Advanced"** disclosure below it. Expand it → the **Engine** picker appears with the "Use a different engine…" footer.
- **Critical — no clipping:** with Advanced expanded, nothing is cut off at the bottom of the window. Then switch the Engine picker to **Ollama** (its config has more rows: Base URL, API key, status, Model). Confirm the Ollama-expanded state also fits without clipping. **If anything clips, bump the `.models` height back up** (try 420, then 430) until the expanded Ollama state fits, and re-commit. 430 is the known-safe value from before this change.
- Reopen Settings while on Ollama → Advanced starts **expanded** (because the active engine isn't Apple Intelligence). Switch back to Apple Intelligence; reopen Settings → Advanced starts **collapsed**.

- [ ] **Step 4: Run the full suite once more**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`
Expected: 73 tests pass.

- [ ] **Step 5: Commit (include any height bump from Step 3)**

```bash
git add Sources/AppAudit/Views/SettingsView.swift
git commit -m "Settings: trim Models tab height to fit decluttered content"
```

This feature does not bump the version or cut a release — it folds into the next tagged release alongside the subscription, App Store ownership, Paid-marker, and badge-contrast work.

---

## Self-Review

**Spec coverage:**
- Lead with active engine under a single header → Task 1 Step 2 (`SettingsSectionTitle(provider.displayName)`, "Provider" header removed). ✓
- Engine picker into collapsed "Advanced" DisclosureGroup → Task 1 Step 2. ✓
- Drop pinned Model row for Apple Intelligence; keep it for Ollama/cloud → Task 1 Step 3 (only `appleIntelligenceConfig` loses `modelRow`). ✓
- Advanced auto-expands when active engine ≠ Apple Intelligence, once, respecting later manual toggles → Task 1 Step 2 `.onAppear` one-shot with `didInitAdvanced`. ✓
- No engine removal / no default / no model-layer changes → only `SettingsView.swift` body reordered; `providerRaw` and all `@AppStorage` keys intact. ✓
- Window height fits the expanded state without clipping, trimming dead space → Task 2 (400 with a measured bump-up fallback to 420/430). ✓

**Placeholder scan:** No TBD/TODO. The height value is a concrete 400 with an explicit, verifiable bump-up procedure and known-safe fallback (430) — not a placeholder.

**Type consistency:** `advancedExpanded`/`didInitAdvanced` (Bool `@State`) declared in Task 1 Step 1, used in Step 2. `provider` computed property and `providerRaw` `@AppStorage` are pre-existing and used consistently. `appleIntelligenceConfig`/`ollamaConfig`/`cloudConfig`/`modelRow`/`SettingsCard`/`SettingsSectionTitle`/`SettingsFooter` are all pre-existing helpers referenced with their real signatures.

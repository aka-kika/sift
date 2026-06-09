# Sift 1.2.0 — macOS 27 Polish + Apple Intelligence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-add on-device Apple Intelligence as Sift's fourth analysis provider and adopt Liquid Glass tastefully on macOS 26/27 while keeping macOS 14 working unchanged.

**Architecture:** The provider returns by restoring the deleted `AppleIntelligenceService` from git history and conforming it to the existing `AnalysisService` protocol; `AnalysisProviderKind` gains a fourth case with a pinned historical cache identifier. All Liquid Glass adoption goes through one availability-gated shim file (`GlassStyle.swift`) so views contain no raw `#available` checks and macOS 14–15 keeps today's exact appearance.

**Tech Stack:** SwiftUI, SwiftData, FoundationModels (`@Generable` structured output), SwiftPM. **Every build/test command must use the Xcode-beta toolchain** — the standalone CLT is broken on macOS 27:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```

Spec: `docs/superpowers/specs/2026-06-10-macos27-liquid-glass-apple-intelligence-design.md`

---

### Task 1: `.appleIntelligence` provider kind with pinned identifier (TDD)

**Files:**
- Modify: `Sources/AppAudit/Models/AnalysisProviderKind.swift`
- Test: `Tests/AppAuditTests/AppAuditTests.swift` (inside `AnalysisProviderKindTests` suite, after `modelIdentifiers()`)

- [ ] **Step 1: Write the failing test**

Add inside `@Suite("AnalysisProviderKind Tests") struct AnalysisProviderKindTests`:

```swift
@Test("Apple Intelligence keeps its historical cache identifier")
func appleIntelligenceIdentifier() {
    let defaults = UserDefaults(suiteName: "AppAuditTests.AnalysisProviderKind.ai")!
    // Even if a model name is stored, the identifier stays pinned so analyses
    // cached before the 1.1.0 trims revalidate as non-drifted.
    defaults.set("anything-else", forKey: "appleIntelligenceModel")
    #expect(AnalysisProviderKind.appleIntelligence.modelIdentifier(userDefaults: defaults) == "apple-intelligence:foundation-models")
    #expect(AnalysisProviderKind.allCases.count == 4)
    #expect(AnalysisProviderKind.appleIntelligence.displayName == "Apple Intelligence")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -5`
Expected: compile FAILURE — `type 'AnalysisProviderKind' has no member 'appleIntelligence'`

- [ ] **Step 3: Add the case and pinned identifier**

In `Sources/AppAudit/Models/AnalysisProviderKind.swift`, change the enum to:

```swift
enum AnalysisProviderKind: String, CaseIterable, Identifiable, Sendable {
    case ollama
    case anthropic
    case openAI
    case appleIntelligence
```

Extend each `switch` with the new case:

```swift
    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .anthropic: return "Anthropic"
        case .openAI: return "OpenAI"
        case .appleIntelligence: return "Apple Intelligence"
        }
    }

    var modelDefaultsKey: String {
        switch self {
        case .ollama: return "ollamaModel"
        case .anthropic: return "anthropicModel"
        case .openAI: return "openAIModel"
        case .appleIntelligence: return "appleIntelligenceModel"
        }
    }

    var apiKeyDefaultsKey: String {
        switch self {
        case .ollama: return "ollamaApiKey"
        case .anthropic: return "anthropicApiKey"
        case .openAI: return "openAIApiKey"
        case .appleIntelligence: return "appleIntelligenceApiKey" // unused; no key needed
        }
    }

    var defaultModel: String {
        switch self {
        case .ollama: return "llama3.2"
        case .anthropic: return "claude-3-5-haiku-latest"
        case .openAI: return "gpt-4o-mini"
        case .appleIntelligence: return "system-language-model"
        }
    }
```

And replace `modelIdentifier(userDefaults:)` with:

```swift
    func modelIdentifier(userDefaults: UserDefaults = .standard) -> String {
        // Pinned to the pre-1.1.0 identifier so old cached analyses stay valid.
        // There is exactly one on-device system model, so it never varies.
        if self == .appleIntelligence {
            return "apple-intelligence:foundation-models"
        }
        let model = userDefaults.string(forKey: modelDefaultsKey) ?? defaultModel
        return "\(rawValue):\(model)"
    }
```

- [ ] **Step 4: Run tests — new test passes, nothing else compiles yet is OK only if green**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -4`
Expected: the `SettingsView.swift` `switch provider` and `AppListViewModel.enrichSingle` switches are now **non-exhaustive → compile errors**. Add temporary minimal arms so the suite runs (they will be replaced in Tasks 3–4):

In `Sources/AppAudit/ViewModels/AppListViewModel.swift`, in `enrichSingle`'s `switch provider`:

```swift
        case .appleIntelligence:
            result = .unavailable("Apple Intelligence wiring lands in Task 3.")
```

In `Sources/AppAudit/Views/SettingsView.swift`, in the `SettingsCard { switch provider ... }`:

```swift
                case .appleIntelligence:
                    SettingsFooter("Apple Intelligence configuration lands in Task 4.")
```

and in `private func fetchModels()`'s `switch provider`:

```swift
        case .appleIntelligence: result = .failure("Not wired yet.")
```

Re-run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -4`
Expected: PASS — 47 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Models/AnalysisProviderKind.swift Sources/AppAudit/ViewModels/AppListViewModel.swift Sources/AppAudit/Views/SettingsView.swift Tests/AppAuditTests/AppAuditTests.swift
git commit -m "Add appleIntelligence provider kind with pinned cache identifier"
```

---

### Task 2: Restore `AppleIntelligenceService`, conform to `AnalysisService`

**Files:**
- Create: `Sources/AppAudit/Services/AppleIntelligenceService.swift`

- [ ] **Step 1: Restore the deleted file from history**

```bash
cd "$(git rev-parse --show-toplevel)"
git show 00ff4d7~1:Sources/AppAudit/Services/AppleIntelligenceService.swift > Sources/AppAudit/Services/AppleIntelligenceService.swift
```

- [ ] **Step 2: Conform to the protocol and add `fetchModels`**

Edit the restored file. Change the actor declaration line:

```swift
actor AppleIntelligenceService: AnalysisService {
```

Change `analyze`'s return type from `OllamaService.OllamaResult` to `AnalysisResult` (same type via typealias, but the protocol names it directly):

```swift
    func analyze(app: AppInfo, profile: WorkflowProfile, appURL: String? = nil) async -> AnalysisResult {
```

Append inside the actor, after `analyze` and before the `#if canImport` helper block:

```swift
    /// There is exactly one on-device system model. "Fetching models" doubles
    /// as the availability check for the Settings status row.
    func fetchModels() async -> ModelFetchResult {
        if let message = availabilityMessage() {
            return .failure(message)
        }
        return .models(["system-language-model"])
    }
```

- [ ] **Step 3: Build to verify the restored file compiles against the 27 SDK**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build 2>&1 | tail -3`
Expected: `Build complete!`
If `SystemLanguageModel.Availability.UnavailableReason` cases changed in the 27 SDK (beta churn), fix only `describeAvailabilityReason` — the `@unknown default` arm already absorbs new cases; a removed case will surface as a compile error naming it.

- [ ] **Step 4: Run tests**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`
Expected: PASS — 47 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppAudit/Services/AppleIntelligenceService.swift
git commit -m "Restore AppleIntelligenceService; conform to AnalysisService"
```

---

### Task 3: Route the view model to the new provider

**Files:**
- Modify: `Sources/AppAudit/ViewModels/AppListViewModel.swift` (service properties + `enrichSingle`)

- [ ] **Step 1: Add the service instance**

Next to the other services:

```swift
    private let scanner = AppScanner()
    private let ollama = OllamaService()
    private let anthropic = AnthropicService()
    private let openAI = OpenAIService()
    private let appleIntelligence = AppleIntelligenceService()
    private let updateChecker = UpdateChecker()
```

- [ ] **Step 2: Replace the Task-1 placeholder arm in `enrichSingle`**

```swift
        let result: AnalysisResult
        switch provider {
        case .ollama:
            result = await ollama.analyze(app: app, profile: profile, appURL: appURL)
        case .anthropic:
            result = await anthropic.analyze(app: app, profile: profile, appURL: appURL)
        case .openAI:
            result = await openAI.analyze(app: app, profile: profile, appURL: appURL)
        case .appleIntelligence:
            result = await appleIntelligence.analyze(app: app, profile: profile, appURL: appURL)
        }
```

- [ ] **Step 3: Build + test**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`
Expected: PASS — 47 tests.

- [ ] **Step 4: Commit**

```bash
git add Sources/AppAudit/ViewModels/AppListViewModel.swift
git commit -m "Route analysis to AppleIntelligenceService when selected"
```

---

### Task 4: Settings UI for Apple Intelligence

**Files:**
- Modify: `Sources/AppAudit/Views/SettingsView.swift` (`AnalysisSettingsTab`)

- [ ] **Step 1: Add the model storage property**

With the other `@AppStorage` properties:

```swift
    @AppStorage("appleIntelligenceModel") private var appleIntelligenceModel = "system-language-model"
```

- [ ] **Step 2: Replace the Task-1 placeholder branch in the provider `switch`**

```swift
                case .appleIntelligence:
                    appleIntelligenceConfig
```

- [ ] **Step 3: Add the config view (after `cloudConfig`)**

```swift
    @ViewBuilder
    private var appleIntelligenceConfig: some View {
        HStack {
            Text("Status")
                .frame(width: 64, alignment: .leading)
            ProviderStatusView(status: providerStatus)
            Spacer()
            fetchButton
        }

        SettingsFooter("On-device Foundation Models. No API key — analysis never leaves this Mac. Requires macOS 26+ with Apple Intelligence enabled.")

        Divider()
        modelRow(model: $appleIntelligenceModel)
    }
```

- [ ] **Step 4: Wire `fetchModels()` and friendly status text**

Replace the Task-1 placeholder arm in `private func fetchModels()`:

```swift
        case .appleIntelligence: result = await AppleIntelligenceService().fetchModels()
```

In `providerStatus`, make the loaded text read naturally for the on-device case — replace the `.loaded` arm with:

```swift
        case .loaded:
            if provider == .appleIntelligence {
                return .success("Available on this Mac")
            }
            let count = availableModels.count
            return count == 0 ? .success("Connected. No models found.") : .success("Connected. \(count) model(s).")
```

- [ ] **Step 5: Build + test, launch to eyeball**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`
Expected: PASS — 47 tests.
Then: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash Scripts/build_sift2.sh` and check Settings → Models → Engine picker shows four providers; selecting Apple Intelligence shows the status row (either "Available on this Mac" or the explanatory unavailability message).

- [ ] **Step 6: Commit**

```bash
git add Sources/AppAudit/Views/SettingsView.swift
git commit -m "Add Apple Intelligence settings: availability status, no key fields"
```

---

### Task 5: `GlassStyle.swift` shim

**Files:**
- Create: `Sources/AppAudit/Views/GlassStyle.swift`

- [ ] **Step 1: Create the shim**

```swift
import SwiftUI

// Centralized Liquid Glass adoption. All glass styling goes through these
// helpers so views carry no raw #available checks and macOS 14–15 keeps the
// exact pre-glass appearance. If a beta glass API misbehaves, change the
// fallback here rather than fighting it at call sites.
extension View {

    /// `.glassProminent` button style on macOS 26+, `.borderedProminent` earlier.
    @ViewBuilder
    func glassProminentButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// `.glass` button style on macOS 26+, `.bordered` earlier.
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Soft scroll-edge fade under translucent bars on macOS 26+, no-op earlier.
    @ViewBuilder
    func softTopScrollEdge() -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build 2>&1 | tail -3`
Expected: `Build complete!`
If `.glassProminent` / `.glass` / `scrollEdgeEffectStyle` fail to resolve (beta API drift), check the SDK's swiftinterface for the current names:
`grep -io "[a-zA-Z_]*glass[a-zA-Z_]*" "$(xcrun --show-sdk-path --sdk macosx)/System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface" | sort -u`
and adjust the shim only.

- [ ] **Step 3: Commit**

```bash
git add Sources/AppAudit/Views/GlassStyle.swift
git commit -m "Add availability-gated Liquid Glass style shim"
```

---

### Task 6: Apply glass touches

**Files:**
- Modify: `Sources/AppAudit/Views/AppDetailView.swift` (update pill button)
- Modify: `Sources/AppAudit/Views/ContentView.swift` (banner button)
- Modify: `Sources/AppAudit/Views/AppListView.swift` (list scroll edge + toolbar spacers)

- [ ] **Step 1: Update pill → glass prominent**

In `AppDetailView.updatePill`, the update-available `Button` currently reads:

```swift
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.orange)
```

Replace the `.buttonStyle(.borderedProminent)` line:

```swift
                .glassProminentButtonStyle()
                .controlSize(.small)
                .tint(.orange)
```

- [ ] **Step 2: Banner button → glass prominent**

In `ContentView.modelChangedBanner`, replace:

```swift
            Button("Re-analyze \(viewModel.staleModelCount)") {
                Task { await viewModel.reanalyzeAll(scope: .modelChangedUnlocked) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
```

with:

```swift
            Button("Re-analyze \(viewModel.staleModelCount)") {
                Task { await viewModel.reanalyzeAll(scope: .modelChangedUnlocked) }
            }
            .glassProminentButtonStyle()
            .controlSize(.small)
```

- [ ] **Step 3: Scroll-edge fades**

In `AppListView`, on the `List(...)` (after `.listStyle(.sidebar)`):

```swift
                    .listStyle(.sidebar)
                    .softTopScrollEdge()
```

In `AppDetailView.body`, on the `ScrollView` (before `.navigationTitle(app.name)`):

```swift
        .softTopScrollEdge()
```

- [ ] **Step 4: Toolbar grouping with `ToolbarSpacer`**

In `AppListView`'s `.toolbar { ... }`, insert between the Filter menu item and the refresh-button item, and between the refresh item and the More menu item:

```swift
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed)
            }
```

(`ToolbarContentBuilder` accepts `if #available`. If the beta compiler rejects it, drop the spacers entirely — grouping is a nicety, not a requirement.)

- [ ] **Step 5: Build + test + look**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`
Expected: PASS — 47 tests.
Then `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash Scripts/build_sift2.sh` — verify the update pill and banner render as glass, toolbar groups read sensibly, list edges fade under the toolbar.

- [ ] **Step 6: Commit**

```bash
git add Sources/AppAudit/Views/AppDetailView.swift Sources/AppAudit/Views/ContentView.swift Sources/AppAudit/Views/AppListView.swift
git commit -m "Adopt Liquid Glass on update pill, banner, scroll edges, toolbar"
```

---

### Task 7: Version bump + macOS 27 audit pass

**Files:**
- Modify: `version.env`
- Modify: `Sources/AppAudit/Views/SettingsView.swift` (predicted height fix)
- Possibly small layout fixes surfaced by the audit (keep each fix a separate commit)

- [ ] **Step 1: Bump version**

`version.env`:

```
MARKETING_VERSION=1.2.0
BUILD_NUMBER=3
```

- [ ] **Step 2: Predicted fix — Settings window height**

The new control metrics are taller; the Apple Intelligence/cloud branches plus the four-provider picker need room. In `SettingsView.body`:

```swift
        .frame(width: 480, height: 360)
```

(Was 340. Verify visually in Step 3; adjust once if needed — pick the smallest height where no tab clips.)

- [ ] **Step 3: The audit walk (owner-in-the-loop)**

Rebuild Sift2: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash Scripts/build_sift2.sh`
Walk every surface on macOS 27 and note anything clipped, cramped, or illegible:
1. App list: rows (badges, update pills, score circles), all four sorts, both filters, search, every empty state.
2. Detail: all `aiState` cases (pending/loading/loaded/unavailable), locked state, each update state, the ⋯ menu, Notes/License/Link rows, all three sheets.
3. Settings: all three tabs × all four providers.
4. License Vault (empty + populated), drift banner, CSV save panel.
Fix only layout (spacing/frames/line limits), not styling. One commit per logical fix:

```bash
git add <files> && git commit -m "Audit fix: <surface> under macOS 27 appearance"
```

- [ ] **Step 4: Full test run + commit the bump**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test 2>&1 | tail -3`
Expected: PASS — 47 tests.

```bash
git add version.env Sources/AppAudit/Views/SettingsView.swift
git commit -m "Bump to 1.2.0 (build 3); size Settings for new control metrics"
```

---

### Task 8: Documentation

**Files:**
- Modify: `FEATURES.md` (AI providers section)
- Modify: `docs/README.md` (Requirements table, Models Tab section)
- Modify: `docs/ARCHITECTURE.md` (provider list, prompt note)
- Modify: `docs/roadmap.md` (move Now → Recently shipped happens at release; for now mark in-progress accurately if needed — leave as-is otherwise)
- Modify: `docs/superpowers/specs/2026-06-10-macos27-liquid-glass-apple-intelligence-design.md` (status → implemented)

- [ ] **Step 1: FEATURES.md — AI providers bullet list**

Add to the **AI providers** section after the OpenAI bullet:

```markdown
- **Apple Intelligence** — on-device Foundation Models (macOS 26+). No API key;
  analysis never leaves the Mac. Availability is checked and explained in Settings.
```

And in **Privacy & data**, change the first bullet to:

```markdown
- Analysis runs locally by default (Ollama), or fully on-device with Apple
  Intelligence. Cloud providers are opt-in via API key.
```

- [ ] **Step 2: docs/README.md**

Requirements table — add after the Cloud API key row:

```markdown
| Apple Intelligence | Optional on-device provider | macOS 26+ with Apple Intelligence enabled |
```

Models Tab section — add after the Anthropic/OpenAI bullet:

```markdown
- **Apple Intelligence** — no key or URL; shows an availability status ("Available on this Mac" or the reason it isn't). On-device Foundation Models, macOS 26+.
```

- [ ] **Step 3: docs/ARCHITECTURE.md**

- Layer diagram: `Ollama/Anthropic/` `OpenAI` → `Ollama/Anthropic/` `OpenAI/Apple Intelligence`.
- Concurrency section, actor list: add `AppleIntelligenceService`.
- AI Prompt section, replace the final paragraph with:

```markdown
All providers share this one prompt via the `AnalysisService` protocol. The HTTP
providers (Ollama, Anthropic, OpenAI) return structured text for the parser;
Apple Intelligence uses FoundationModels `@Generable` structured generation and
converts the result into the same parsed format. The system prompt instructs the
model to answer directly, banning "appears to be" hedging.
```

- [ ] **Step 4: Spec status line**

In the 1.2.0 spec header: `**Status:** Implemented (this plan)`.

- [ ] **Step 5: Commit**

```bash
git add FEATURES.md docs/README.md docs/ARCHITECTURE.md docs/superpowers/specs/2026-06-10-macos27-liquid-glass-apple-intelligence-design.md
git commit -m "Document Apple Intelligence provider and Liquid Glass pass"
```

---

### Task 9: Final verification + Sift2 handoff

- [ ] **Step 1: Clean full build + tests**

```bash
cd "$(git rev-parse --show-toplevel)"
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
swift build -c release 2>&1 | tail -2
swift test 2>&1 | tail -3
```

Expected: `Build complete!`, PASS — 47 tests.

- [ ] **Step 2: Rebuild Sift2 for owner testing**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash Scripts/build_sift2.sh
```

Expected: `==> Installed /Applications/Sift2.app (<commit>)`, app launches.

- [ ] **Step 3: Owner acceptance (manual)**

Owner verifies on macOS 27, in Sift2: Apple Intelligence selectable and analyzing (or showing a clear availability reason), drift banner appears when switching providers, glass rendering on pill/banner/toolbar, no broken layouts. 1.2.0 release (notarize + GitHub) happens after acceptance via `docs/RELEASE.md` — not part of this plan.

---

## Self-Review

- **Spec coverage:** item 1 (provider) → Tasks 1–4; item 2 (glass: shim, pill, banner, scroll edges, toolbar, audit) → Tasks 5–7; item 3 (version/tests/docs/Sift2) → Tasks 1, 7, 8, 9. Release explicitly out of scope (spec agrees).
- **Placeholders:** Task 1 Step 4 introduces explicitly-labeled temporary arms, replaced in Tasks 3–4 with the exact final code shown there — intentional compile-bridging, not a gap.
- **Type consistency:** `AnalysisResult` / `ModelFetchResult` / `AnalysisService` match `AnalysisService.swift`; `fetchButton`, `modelRow(model:)`, `providerStatus`, `ProviderStatusView` match `SettingsView.swift` as shipped in 1.1.0; shim method names used in Task 6 match Task 5's definitions.

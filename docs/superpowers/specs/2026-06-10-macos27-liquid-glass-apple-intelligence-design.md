# Sift 1.2.0 — macOS 27 Polish + Apple Intelligence — Design

**Date:** 2026-06-10
**Status:** Approved design, pending spec review
**Branch:** `claude/jolly-poincare-38dcc2`
**Prerequisite:** Sift 1.1.0 notarized and published — **done** (tag `v1.1.0`,
release at github.com/aka-kika/sift).

## Context

The owner's machine runs macOS 27.0 (golden beta) with the 27.0 SDK (via the
Xcode 27 beta toolchain — the standalone CLT is broken on this OS, see
`docs/RELEASE.md`). Linking against the 26+ SDK gives the whole app the Liquid
Glass appearance automatically; custom glass APIs (`Glass`,
`.buttonStyle(.glass)` / `.glassProminent`, `ToolbarSpacer`,
`backgroundExtensionEffect`, `scrollEdgeEffectStyle`) are available behind
`#available(macOS 26.0, *)`. `FoundationModels.framework` is present in the SDK
and on the machine, making on-device Apple Intelligence analysis buildable. The
previous `AppleIntelligenceService` (removed in the 1.1.0 trims) is recoverable
intact from git history at `00ff4d7~1` and already used `@Generable` structured
output with proper availability gating.

## Decisions (from brainstorming)

| Topic | Decision |
|---|---|
| Sequencing | 1.1.0 shipped first (done); this work is 1.2.0. |
| Minimum OS | Stays **macOS 14**. Glass on 26/27, classic look on 14–15. |
| Apple Intelligence | Returns as a **4th provider**; Ollama remains the default. |
| Glass depth | **Tasteful pass** — relink + targeted touches + full audit, no deep custom treatment. |
| AI integration approach | Resurrect the deleted service and conform it to `AnalysisService` (no rewrite). |
| Glass gating approach | Centralized shim (`GlassStyle.swift`), not inline `#available` scattered through views. |

## Goals

1. Sift looks native on macOS 26/27 — inherits Liquid Glass and adopts it
   deliberately where it improves the UI — while staying correct on macOS 14.
2. Apple Intelligence analysis works on capable machines: no API key, on-device,
   private.
3. No regression for existing providers, data, or the macOS 14 build.

## Non-Goals

- No "full glass treatment" (custom glass on score badges, cards, sidebar).
- No minimum-OS bump.
- No change to which provider is default (Ollama).
- No new analysis features — this is presentation + provider plumbing.

## Work Items

### 1. Apple Intelligence provider (4th engine)

**Restore.** `git show 00ff4d7~1:Sources/AppAudit/Services/AppleIntelligenceService.swift`
→ `Sources/AppAudit/Services/AppleIntelligenceService.swift`. The file already:
- gates everything behind `#if canImport(FoundationModels)` + `@available(macOS 26.0, *)`,
- defines `@Generable AppleIntelligenceAppAnalysis` (explanation / score 1–5 /
  reason / bestUse) with `@Guide` annotations,
- exposes `availabilityMessage() -> String?` (nil = available),
- converts structured output into the shared `EXPLANATION:/SCORE:/REASON:/BEST_USE:`
  text format so the existing parser works unchanged.

**Conform to `AnalysisService`.**
- `analyze(app:profile:appURL:)` — already matches; adjust the return type to the
  shared `AnalysisResult` (the old file predates the protocol and returned
  `OllamaService.OllamaResult`, which is now a typealias — likely compiles as-is;
  fix signatures if not).
- `fetchModels()` — there is exactly one on-device system model. Return
  `.models(["system-language-model"])` when `availabilityMessage()` is nil,
  otherwise `.failure(<message>)`.

**Provider kind.** `AnalysisProviderKind` gains `.appleIntelligence`:
- `displayName` "Apple Intelligence"
- `modelDefaultsKey` `"appleIntelligenceModel"` (default `"system-language-model"`)
- `apiKeyDefaultsKey` unused — see Settings below
- `modelIdentifier` must remain **`apple-intelligence:foundation-models`** (the
  pre-trim identifier) so any analyses cached before the 1.1.0 trims revalidate
  as non-drifted rather than triggering the model-change banner. This means
  `.appleIntelligence` overrides the generic `\(rawValue):\(model)` pattern.
- On macOS < 26 (or when FoundationModels is unavailable), the provider still
  appears in the picker but Settings shows the unavailability reason and
  analysis returns `.unavailable(<message>)` — same UX as Ollama-not-running.

**Settings (Models tab).** For `.appleIntelligence`, show no Base URL / API key
fields. Show an availability status row (reusing `ProviderStatusView`) populated
by `fetchModels()` — "Available on this Mac" / the unavailability message — and
the standard model row (single entry). The refresh button re-checks availability.

**View model.** `enrichSingle` gains the `.appleIntelligence` route to a new
`appleIntelligence` service instance, matching the other three.

**Acceptance.** On this machine: selecting Apple Intelligence analyzes apps
on-device with parsed scores; Settings shows availability; switching from Ollama
shows the model-drift banner (different identifier) and analyses are preserved.
The package still builds for macOS 14 (availability-gated code compiles out).

### 2. Liquid Glass pass (tasteful)

**Shim.** New `Sources/AppAudit/Views/GlassStyle.swift` — small availability-gated
helpers so views never contain raw `#available` checks, e.g.:
- `View.glassProminentButtonIfAvailable()` → `.buttonStyle(.glassProminent)` on
  26+, `.buttonStyle(.borderedProminent)` otherwise.
- `View.glassButtonIfAvailable()` → `.glass` / `.bordered`.
- `View.edgeFadeIfAvailable()` → `scrollEdgeEffectStyle` application where used.
All fallbacks preserve today's appearance on macOS 14–15. If a glass API
misbehaves under the beta, the helper falls back to the standard style rather
than fighting it.

**Targeted adoption.**
- Update pill (`AppDetailView.updatePill`) and the model-change banner's
  Re-analyze button (`ContentView.modelChangedBanner`) → glass-prominent.
- Sidebar list and detail `ScrollView` → scroll-edge effect where it improves
  legibility under translucent toolbars.
- `AppListView` toolbar → `ToolbarSpacer` grouping: Sort + Filter | Refresh | ⋯
  (gated; plain order on 14–15).

**Audit pass.** Walk every surface under the macOS 27 appearance — app list +
rows, detail panel (all states: pending/loading/loaded/unavailable, locked,
update states), Settings (all three tabs × four providers), License Vault,
all sheets, the drift banner, empty states. Fix anything clipped, cramped, or
illegible. Expected hot spots: the fixed-size Settings window (480×340 may need
height for the new control metrics) and sheet paddings. Fixes prefer standard
layout corrections over custom styling.

**Acceptance.** App renders correctly and feels native on macOS 27; no visual
regression in code paths reachable on macOS 14 (compile-time fallbacks verified
by building with the same SDK at deployment target 14 — runtime check on an old
OS is out of scope for this machine).

### 3. Version, tests, docs

- `version.env` → `MARKETING_VERSION=1.2.0`, `BUILD_NUMBER=3`.
- Tests: existing 46 stay green. Add: `.appleIntelligence` identifier stability
  (`apple-intelligence:foundation-models` regardless of defaults), provider
  count/picker presence, and (if testable headlessly) `fetchModels` failure path
  when unavailable.
- Rebuild Sift2 (`Scripts/build_sift2.sh`) for owner testing.
- Docs: FEATURES.md + docs/README.md provider sections, ARCHITECTURE.md provider
  list and prompt note, roadmap.md (move items Now → Recently shipped at release
  time). Release of 1.2.0 itself follows the existing checklist when the owner
  is ready.

## Affected Files (indicative)

- **New:** `Services/AppleIntelligenceService.swift` (restored),
  `Views/GlassStyle.swift`.
- `Models/AnalysisProviderKind.swift` — `.appleIntelligence` + identifier override.
- `ViewModels/AppListViewModel.swift` — provider route.
- `Views/SettingsView.swift` — Apple Intelligence config branch.
- `Views/AppDetailView.swift`, `Views/ContentView.swift`,
  `Views/AppListView.swift` — glass touches + audit fixes.
- `version.env`, tests, docs.

## Risks

- **Beta SDK churn** — glass API names may change before GM; the shim contains
  the blast radius to one file.
- **Foundation Models availability** varies by hardware, language, and Apple
  Intelligence settings; the Settings status row surfaces the reason rather than
  failing silently.
- **CLT breakage** — all builds must use
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (documented in
  RELEASE.md).
- **No macOS 14 test hardware** in reach — correctness there rests on
  availability-gated compilation and unchanged fallback paths, both verified at
  build time.

## Testing Strategy

- Unit: provider identifier stability; provider routing enum exhaustiveness
  (compiler-enforced); existing suite green.
- Manual on macOS 27: full scan with Apple Intelligence; provider switching in
  all four directions (banner behavior); the audit-pass walk of every surface;
  Sift2 side-by-side with the installed 1.1.0.

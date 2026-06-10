# Sift — Grounded-First Analysis — Design

**Date:** 2026-06-10
**Status:** Approved design, pending spec review
**Branch:** `claude/jolly-poincare-38dcc2`

## Context

Owner insight from daily use: leading the detail panel with the *personalized*
verdict makes weak-model output feel hallucinated — unverifiable claims come
before checkable facts. Separately, the free-text workflow profile is the main
hallucination feed: small models parrot profile keywords back as invented app
facts (measured in the AI-quality lab — llama3.2 wove "Codex, Ollama,
local-first" into fiction about an unknown app). Strategic goal: make Sift work
for mainstream users — zero configuration, Apple Intelligence as the
out-of-the-box engine on capable Macs, Ollama as the power-user option.

## Decisions (from brainstorming)

| Topic | Decision |
|---|---|
| Detail order | "What is this?" (facts) first; ranking/best-use second. |
| Profile source | **Deterministic digest** derived from the installed apps — no AI in the loop. |
| Manual profile | Kept as optional override; Settings shows "Automatic" + digest preview. |
| Output | Keep the 4 AI fields; add **category** from `Info.plist` (factual, no AI). |
| Default provider (new installs) | **Apple Intelligence when available** (macOS 26+), else Ollama. Existing stored selections untouched. |

## Work Items

### 1. Detail panel: facts first

In `AppDetailView`, the body order becomes: header → analysis states
(pending/loading/unavailable, shown in the top content slot) → **What is
this?** → **recommendation** (score dots, best-use, reason) → utility rows.
The "Best use and ranking" block keeps its content; only position changes.

### 2. App category (factual, free)

- `AppScanner` reads `LSApplicationCategoryType` from each `Info.plist` into a
  new `AppInfo.category: String?` (raw value, e.g.
  `public.app-category.developer-tools`).
- A small mapper renders human names ("Developer Tools"); unknown/missing →
  nil. Shown in the detail header line (beside version) and as a new
  `Category` column in CSV export.
- The category line is added to the analysis prompts (`build` and
  `compactFacts`) as evidence: `Category: Developer Tools` (omitted when nil).

### 3. Auto-derived workflow digest

- New pure helper `WorkflowDigest.build(from: [AppInfo]) -> String` producing,
  deterministically:
  `Installed apps: 98. Categories: Developer Tools (22), Productivity (11),
  Design (9), Utilities (8), other (48). Most recently used: Xcode, Claude,
  Figma, Ghostty, Hazel, Keyboard Maestro, Eagle, Telegram. Open right now:
  Xcode, Ghostty, Telegram.`
  (top 5 categories by count; 8 most-recent apps by `lastUsedDate`; up to 8
  currently running apps.)
- **Running detection** (validated against the Mole clone, which shells out to
  `pgrep`; we use the native API instead): `AppInfo.isRunning`, populated at
  scan time from `NSWorkspace.shared.runningApplications` bundle IDs (read on
  the main actor, passed into the scanner). A small green dot on the app row
  shows "open now".
- Profile resolution order in `AppListViewModel.runFullScan` /
  `reanalyze*`: **custom profile text** (non-blank, from the existing storage
  key) → **digest** (computed from the current scan) → neutral text.
- The digest used for the last scan is cached to UserDefaults
  (`lastProfileDigest`) so Settings can preview it.
- Settings → Profile tab: header text becomes "Automatic — derived from your
  installed apps", a read-only digest preview, and the existing editor retitled
  as the optional override ("Leave empty to use the automatic profile").
  `WorkflowProfile.neutralProfileText` remains the last-resort fallback (first
  scan before any digest exists).

### 4. Zero-setup default provider

- First-run only: if `analysisProviderKind` has never been stored and
  FoundationModels reports the system model available, store
  `appleIntelligence`; otherwise leave unset (Ollama default applies).
  Implemented as a small launch migration (like `migrateLegacyLicenseKeys`),
  gated `#if canImport(FoundationModels)` + `#available(macOS 26.0, *)`.
- Pure decision function `defaultProviderRawValue(appleIntelligenceAvailable:
  Bool) -> String?` unit-tested; the availability probe itself is not.
- Existing installs (any stored value) are never changed.

### 5. Tests & docs

- Unit tests: digest formatting (counts, category ordering, most-used
  ordering, ties), custom-override precedence, category human-name mapping,
  default-provider decision function.
- Docs: FEATURES.md (auto profile, category, zero-setup default),
  docs/README.md (Profile tab, detail order, requirements framing — Ollama now
  "optional power-user"), ARCHITECTURE.md (profile resolution), roadmap.

## Non-Goals

- No AI-generated persona text (digest is pure code).
- No schema expansion beyond category (no alternatives/keep-or-cut fields).
- No change to the owner's existing provider/model selection.
- No removal of Ollama/Anthropic/OpenAI.

## Risks

- Category metadata is missing from many non-App-Store apps → digest counts
  skew toward "other"; acceptable, digest states only facts.
- Most-recently-used list can include the obvious (browsers); harmless — it is
  evidence, not a verdict.
- First-run default writes a provider value; must never run when ANY value is
  already stored (idempotence guarded by a presence check, not a flag).

# Sift — Settings "Models" Tab Declutter

**Date:** 2026-06-13
**Status:** Approved, ready for implementation plan
**Author:** Veronica Loren (aka-kika) + Claude

## Problem

The Settings → Models tab presents four AI engines as equal peers behind a
prominent "Engine" picker, then a second section header repeating the chosen
engine's name. For the common case — a modern Mac running Apple Intelligence —
this is visual noise: a redundant "Provider" / "Apple Intelligence" double
header (the "double menu" feeling), an always-present engine picker the user
rarely touches, and a pinned "Model: system-language-model" row that is
meaningless for Apple Intelligence (its model identifier is hard-pinned in
code — there is nothing to choose).

We decided (with the user) to keep broad reach — Ollama and the cloud engines
stay so Sift still runs on macOS 14/15, Intel, and non-Apple-Intelligence Macs —
but make Apple Intelligence the calm, zero-config hero and tuck the rest under
"Advanced." The capability-aware default already exists
(`applyFirstRunProviderDefault()` selects Apple Intelligence on first launch when
it actually works, else leaves Ollama), so this is a pure UI reorganization — no
logic, model, or default changes.

## Goals

- Lead the Models tab with the **active engine's** configuration, under a single
  header (its name) — no redundant "Provider" header.
- Move the **Engine picker** (and therefore the path to Ollama/cloud) into a
  collapsed **"Advanced"** `DisclosureGroup`.
- **Drop the pinned "Model" row for Apple Intelligence** (single fixed model).
  Keep the Model row for Ollama and the cloud engines, which have real choices.
- When the active engine is **not** Apple Intelligence, start "Advanced"
  **expanded** so it's obvious how the user got there and how to switch.
- Result: a first-timer on a modern Mac sees only "Apple Intelligence — available,
  private, on-device," the PCC toggle, and a Style field. Everything else is one
  disclosure away; nothing is removed; every Mac still works.

## Non-Goals

- **No engine removal.** Ollama, Anthropic, OpenAI all stay, fully functional.
- **No default/first-run logic changes.** The capability-aware default is already
  built and wired in `ContentView`.
- **No model-layer changes.** `AnalysisProviderKind`, services, persistence keys
  all unchanged. `@AppStorage(AnalysisProviderKind.storageKey)` remains the source
  of truth for the selected engine.
- **No behavior change for non-AI engines** beyond their config moving under the
  same "active engine" hero and the picker living in Advanced.

## Design

All changes are inside `Sources/AppAudit/Views/SettingsView.swift`, in the
`AnalysisSettingsTab` (the body of the Models tab). The current shape is:

```
SettingsSectionTitle("Provider")
  Engine [Picker over AnalysisProviderKind.allCases]
SettingsSectionTitle(provider.displayName)
  switch provider { ollamaConfig / cloudConfig / appleIntelligenceConfig }
```

### New shape

```
SettingsSectionTitle(provider.displayName)      // single header = active engine
  activeEngineConfig                             // the switch, minus AI's Model row

DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
    Engine [Picker over AnalysisProviderKind.allCases]
    SettingsFooter("Use a different engine — a local Ollama server or a cloud API.")
}
```

- **`advancedExpanded`** is `@State`, initialized so it is **collapsed when the
  active engine is Apple Intelligence, expanded otherwise.** Because `@State`
  can't read other state in its initializer cleanly, initialize it in `.task`
  / `.onAppear` (or a `.task(id: providerRaw)`) from
  `provider != .appleIntelligence`. A deliberate later collapse/expand by the
  user is respected within the session.
- **The hero header** uses `provider.displayName` (already how the second header
  is built today) — so it reads "Apple Intelligence", "Ollama", etc. The old
  literal `"Provider"` header is removed.
- **Apple Intelligence config loses its Model row.** Today `appleIntelligenceConfig`
  ends with `modelRow(model: $appleIntelligenceModel)`. Remove that one call from
  the Apple Intelligence branch only. Status, the privacy footer, the PCC toggle
  + footers + `pccStatus`, and the Style notes field all stay. (`ollamaConfig`
  and `cloudConfig` keep their `modelRow` — those models are user-selectable.)
- **The Engine picker** (the `Picker("", selection: $providerRaw)` over
  `AnalysisProviderKind.allCases`) moves verbatim into the Advanced disclosure.
  Switching it still drives `providerRaw`, so the hero above re-renders to the
  newly selected engine's config — no extra wiring.
- **Window height.** The Models tab uses a fixed height (`case .models: return
  430`). With the Model row and a header gone and Advanced collapsed, the AI
  default is shorter; the non-AI/expanded case is about the same as today. Set
  the Models height to comfortably fit the **expanded** state (so nothing clips
  when Advanced is open) — measure during implementation and pick the smallest
  value that fits Ollama-expanded without scrolling, trimming the current empty
  space. (Acceptable fallback: keep 430 if a tighter value risks clipping.)

### Resulting layout, Apple Intelligence (the common case)

```
Apple Intelligence
  Status        ✓ Available on this Mac
  (footer: on-device Foundation Models, no API key…)
  ☑ Use Private Cloud Compute when available
  (footers + PCC status)
  Style         [ e.g. Mention alternatives… ]
  (footer: appended to analysis instructions…)

▸ Advanced
```

### Resulting layout, a non-AI engine (e.g. Ollama on an older Mac)

```
Ollama
  (base URL, API key, status, Model row — unchanged)

▾ Advanced            (auto-expanded)
  Engine  [ Ollama ▾ ]
  (footer: use a different engine…)
```

## Testing

- Pure UI; no unit tests (consistent with the rest of the Settings views).
- **Build** clean (`swift build`).
- **Manual in Sift2:** On this Mac (Apple Intelligence available + selected): the
  Models tab shows a single "Apple Intelligence" section, no "Provider" header,
  no Model row, and a collapsed "Advanced" containing the Engine picker. Opening
  Advanced and switching to Ollama re-renders the hero to Ollama's config
  (including its Model row); the Advanced section is what you switch back from.
  Switch to Ollama, reopen Settings → Advanced starts expanded. No clipping in
  the expanded state.

## Affected Files

- `Sources/AppAudit/Views/SettingsView.swift` — reorder `AnalysisSettingsTab`
  body, add `advancedExpanded` state + the `DisclosureGroup`, move the Engine
  picker into it, remove the literal "Provider" header, remove the
  `modelRow` call from `appleIntelligenceConfig`, adjust the Models tab height.

## Future (post-v1)

- If macOS 26 becomes the norm, revisit dropping the non-AI engines entirely.
- A one-line "Powered by Apple Intelligence — private, on-device" reassurance in
  the main UI (not Settings) could reinforce the zero-setup story.

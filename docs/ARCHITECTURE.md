# Architecture

## Layers

```
┌─────────────────────────────────────────┐
│           SwiftUI Views                 │  Presentation
│  ContentView / AppListView / AppRow     │
│  AppDetailView / SettingsView           │
├─────────────────────────────────────────┤
│         AppListViewModel                │  Business Logic
│         @Observable @MainActor          │
├──────────────┬──────────────┬───────────┤
│ AppScanner │ AI Providers       │ Update/App Links │ Services
│ FileManager│ Ollama/Anthropic/  │ App Store/Sparkle
│            │ OpenAI/Apple Intel.│ /Homebrew
├─────────────────────────────────────────┤
│  CacheService  +  AppRecord (@Model)    │  Data
│         SwiftData store                 │
└─────────────────────────────────────────┘
```

## Data Flow

```
App Launch
  │
  └── AppScanner.scan()
          │
          ▼
  AppListViewModel
  ├── For each app: CacheService.load(bundleID)
  │     HIT + fresh  → inject cached AIState → display immediately
  │     MISS / stale → enqueue for enrichment
  │
  └── enrichConcurrently() [max 2 concurrent]
        │
        └── selected provider analyzes app + profile
              → structured text (Ollama / Anthropic / OpenAI, same prompt)
              → parseAnalysis() → AIState.loaded(...)
              → CacheService.save()
              → ViewModel updates app in place → SwiftUI re-renders row

Background side tasks:
- `UpdateChecker` checks App Store and Sparkle update state
- `AppLinkResolver` suggests missing app links from App Store lookup or Sparkle appcast metadata
```

## State Machine (AppListViewModel.ScanState)

```
idle → scanning → enriching(completed, total) → done
                                                  ↑
                                           (re-scan resets to idle)
```

## Cache Invalidation

Cache is invalidated only when the **approved app link** used for the analysis changes. A **model change no longer invalidates** analyses — the provider/model identifier (`provider:model`, stored in the legacy-named `AppRecord.ollamaModel` field) is compared read-only via `wasAnalyzedWithDifferentModel`, which drives a dismissible "model changed" banner offering an opt-in re-analyze.

Locked analyses opt out of invalidation and overwrite. `CacheService.save` refuses to update locked records, background enrichment skips locked apps, and manual re-analysis is disabled while locked.

## Concurrency

- AI enrichment uses `withTaskGroup` capped at 2 concurrent provider requests (low peak memory/CPU)
- All ViewModel mutations happen on `@MainActor`
- Services are `actor`-isolated (AppScanner, OllamaService, AnthropicService, OpenAIService)

## Persistence

SwiftData store: `~/Library/Application Support/AppAudit/AppAudit.store`. The folder
is derived from the bundle identifier; the primary app keeps the historical `AppAudit/`
folder so data carries across the Sift rename, and the `Sift2` side-build uses `Sift2/`.

`AppRecord` stores AI results + user edits. Fields added after initial release use `= default` values for zero-migration-plan schema evolution.

License keys are stored in macOS Keychain via `LicenseKeyStore` with device-bound accessibility, under a bundle-ID-derived service name. SwiftData keeps a migration bridge field; a one-time launch sweep purges any legacy plaintext into the Keychain. `AppRecord.hasLicenseKey` powers the License Vault.

Manual `appURL` values are preserved. Automatic link discovery writes `suggestedAppURL`, which only **prefills the editable link field** — it becomes analysis context when the user saves it (no separate approval step).

Saved or manually changed links trigger app re-analysis with the stored `appURL` as prompt context unless the record is locked.

## AI Prompt

Single structured provider request per app:

```
[system] You are an expert macOS app analyst...

[user]  Analyze the macOS app "X" (bundle ID: ...)
        Path: /Applications/X.app
        Category: Developer Tools   ← from Info.plist LSApplicationCategoryType (omitted when nil)
        Developer workflow: [profile text]

        EXPLANATION: [1-2 short sentences]
        SCORE: [1-5]
        REASON: [1 short sentence]
        BEST_USE: [1 short actionable sentence]
```

Parser: line-by-line prefix matching on `EXPLANATION:`, `SCORE:`, `REASON:`, `BEST_USE:`.
The parser is tolerant — it strips any `<think>…</think>` reasoning a model emits,
accepts markdown-wrapped labels (`**SCORE:**`), and reads `4/5`-style scores — so a
reasoning model's output still parses cleanly.

All providers share this one prompt via the `AnalysisService` protocol. Ollama,
Anthropic, and OpenAI return structured text for the parser. Ollama is the default
and the focus of this edition; its requests carry generation tuning (low
temperature, larger context, output cap, `keep_alive`) centralized in
`OllamaDefaults`. The system prompt instructs the model to answer directly,
banning "appears to be" hedging.

## Workflow Profile Resolution

Profile resolution order (applied at scan time and on every re-analyze):
1. **Custom override** — non-blank text stored by the user in Settings → Profile
2. **Automatic digest** — deterministic summary of installed apps: category counts, 8 most-recently-used, currently-running apps (`WorkflowDigest.build`)
3. **Neutral fallback** — `WorkflowProfile.neutralProfileText` (used only before the first scan completes)

The digest from the last scan is persisted to `UserDefaults` (`lastProfileDigest`) and
shown as a read-only preview in Settings → Profile. Leave the custom override empty to
stay automatic.

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
│ AppScanner │ Local AI Providers │ Update/App Links │ Services
│ FileManager│ Ollama/Foundation  │ App Store/Sparkle
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
  └── enrichConcurrently() [max 4 concurrent]
        │
        └── selected provider analyzes app + profile
              → Ollama structured text or Apple Foundation Models structured output
              → parseAnalysis() → AIState.loaded(...)
              → CacheService.save()
              → ViewModel updates app in place → SwiftUI re-renders row

Background side tasks:
- `UpdateChecker` checks App Store and Sparkle update state
- `AppLinkResolver` fills missing app links from App Store lookup or Sparkle appcast metadata
```

## State Machine (AppListViewModel.ScanState)

```
idle → scanning → enriching(completed, total) → done
                                                  ↑
                                           (re-scan resets to idle)
```

## Cache Invalidation

Cache is invalidated when the selected analysis provider or model changes. The identifier is stored in the legacy-named `AppRecord.ollamaModel` field.

Locked analyses opt out of invalidation and overwrite. `CacheService.save` refuses to update locked records, background enrichment skips locked apps, and manual re-analysis is disabled while locked.

## Concurrency

- AI enrichment uses `withTaskGroup` capped at 4 concurrent provider requests
- All ViewModel mutations happen on `@MainActor`
- Services are `actor`-isolated (AppScanner, OllamaService, AppleIntelligenceService)

## Persistence

SwiftData store: `~/Library/Application Support/AppAudit/AppAudit.store`

`AppRecord` stores AI results + user edits. Fields added after initial release use `= default` values for zero-migration-plan schema evolution.

License keys are stored in macOS Keychain via `LicenseKeyStore`. SwiftData keeps only a migration bridge field for older local stores.

Manual `appURL` values are preserved. Automatic link discovery only writes when the field is empty.

Manual link changes trigger app re-analysis with the stored `appURL` as prompt context unless the record is locked.

## AI Prompt

Single structured provider request per app:

```
[system] You are an expert macOS app analyst...

[user]  Analyze the macOS app "X" (bundle ID: ...)
        Developer workflow: [editable local profile text]

        EXPLANATION: [2 sentences]
        SCORE: [1-5]
        REASON: [1 sentence]
        BEST_USE: [1 sentence]
```

Parser: line-by-line prefix matching on `EXPLANATION:`, `SCORE:`, `REASON:`, `BEST_USE:`.

Apple Intelligence is optional and gated by `SystemLanguageModel.default.availability`. When available, `AppleIntelligenceService` asks Foundation Models for structured `@Generable` output, then converts it into the same parser format used by the rest of the app.

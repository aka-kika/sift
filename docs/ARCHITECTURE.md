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
│ AppScanner │ OllamaService │ UpdateChecker │ Services
│ FileManager│ HTTP/Ollama   │ App Store/Sparkle
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
        └── OllamaService.analyze(app, profile)
              → single request, structured response
              → parseAnalysis() → AIState.loaded(...)
              → CacheService.save()
              → ViewModel updates app in place → SwiftUI re-renders row
```

## State Machine (AppListViewModel.ScanState)

```
idle → scanning → enriching(completed, total) → done
                                                  ↑
                                           (re-scan resets to idle)
```

## Cache Invalidation

Only one condition invalidates cache: **the Ollama model changes** (stored in `AppRecord.ollamaModel`).

## Concurrency

- AI enrichment uses `withTaskGroup` capped at 4 concurrent Ollama requests
- All ViewModel mutations happen on `@MainActor`
- Services are `actor`-isolated (AppScanner, OllamaService)

## Persistence

SwiftData store: `~/Library/Application Support/AppAudit/AppAudit.store`

`AppRecord` stores AI results + user edits. Fields added after initial release use `= default` values for zero-migration-plan schema evolution.

License keys are stored in macOS Keychain via `LicenseKeyStore`. SwiftData keeps only a migration bridge field for older local stores.

## AI Prompt

Single structured request per app:

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

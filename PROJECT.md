---
project: Sift
slug: sift
path: /Users/kika_hub/Documents/Agents-hubs/GITHUB/sift
obsidian_log: N/A
status: shipped
tags: [macos, swiftui, app-audit]
created: 2026-06-17
updated: 2026-08-02
---

# Sift

**Bucket / Stage:** `shipped · maintained`

## One-liner
Native macOS app that audits your installed apps with a local model — grounded, evidence-only, private.

## What it is
Sift scans `/Applications` and `~/Applications`, explains what each app is, and
scores 1–5 how well it fits your workflow. The detail panel leads with a
recommendation, then a strip of minimal icon "cubes" for per-app data — notes,
license, subscription, app link, lock, favorite, docs, plus Cross-App and My App.

The standout is that analysis is **grounded and local-first**: it runs on Ollama
by default (optional Anthropic/OpenAI), and is fed only real evidence — the app's
metadata, your notes, its website's fetched words, and, for your own apps, a
local project folder's README. No bundled "known apps" catalog, no invented
facts. Cross-App only ever suggests apps you already have.

It's for a developer deciding what earns a place on their Mac: tracking updates,
storing license keys in the Keychain, watching subscriptions, and keeping the
audit exportable to CSV. Ships as a Developer ID–signed, notarized DMG.

## Stack
- Swift 5.9 / SwiftUI
- SwiftData (local store) + macOS Keychain (license keys)
- AppKit, LocalAuthentication (Touch ID)
- Local Ollama (default); optional Anthropic / OpenAI
- SwiftPM build; `create-dmg`; `notarytool`

## Components / Structure
- `Sources/AppAudit/Views/` — ContentView, AppListView, AppDetailView, AppRow, sheets
- `Sources/AppAudit/ViewModels/AppListViewModel.swift` — scan, enrich, filters, export
- `Sources/AppAudit/Services/` — Ollama/Anthropic/OpenAI, AppAnalysisPrompt, DocsEvidence, SimilarAppsPrompt, LinkEvidence, CacheService, LicenseKeyStore
- `Sources/AppAudit/Models/` — AppRecord (@Model), AppInfo, LicenseType, UtilityCardRules

## Status
`shipped` — v1.10.0 live (Gemini + OpenRouter, free tiers); first update delivered through Sparkle. Free during the beta — count downloads for 14 days, then decide on price. Next: receipt extraction (specced, deferred).

## Key paths
- **entry**: `Sources/AppAudit/AppAuditApp.swift`
- **server**: N/A (talks to a local Ollama server on 11434)
- **config**: `version.env`, `Package.swift`, `Scripts/package_app.sh`
- **docs**: `README.md`, `FEATURES.md`, `docs/` (ARCHITECTURE, RELEASE, releases/, specs/)
- **components**: `Sources/AppAudit/`
- **assets**: `AppIcon.iconset`, `Icon.icns`

## Run
```
swift build && swift test
bash Scripts/make_dmg.sh        # release DMG (adhoc by default)
```

## Notes
Bundle ID stays `com.kikaapp.appaudit` and sources stay under `Sources/AppAudit/`
across the rename to Sift, so existing SwiftData + Keychain data carries over.
A throwaway Sift2 side-build (`Scripts/build_sift2.sh`, bundle `com.kikaapp.sift2`,
isolated store) is the tester. Debt/TODO: CSV Paid column only exports for App
Store installs; unranked-My-Apps and receipt-extraction are designed but unbuilt.

## Log
- 2026-08-27 — v1.10.0: Google Gemini + OpenRouter engines (free tiers, one shared OpenAI-compatible transport); free-beta decision; download tracking on the site. First Sparkle-delivered update.
- 2026-08-27 — v1.9.0: Sift updates itself (Sparkle 2, appcast on sift.akakika.com). Landing page moved off GitHub Pages to Vercel at sift.akakika.com; Homebrew cask source; one-command release pipeline.
- 2026-08-01 — v1.7.0: uninstall sweep (trash-first, uninstally-adapted), Cross-App cube removed, one-entry License menu, vault icon fixes.
- 2026-08-02 — v1.8.0: App Store fixes found by living in the app — uninstall hands root-owned bundles to Finder, licence types save without a key and reach the vault. Vault names link out; detail page gains a facts row, named blocks, and an About tab.
- 2026-08-01 — v1.6.0: License cube merge + tabbed popover, instant label strip, Developer Mode, per-type license colors mirrored in the sidebar.
- 2026-07-05 — v1.5.1: My App cube + Docs gating, fixed 2-row grid, top-down header, first notarized DMG.
- 2026-07-04 — v1.4.0 → v1.5.0: notes-as-evidence, utility cubes, docs evidence, Cross-App, dark-mode pastels, menu-bar move.
- 2026-06-28 — v1.3.3: personal Ollama-first edition; removed Apple Intelligence + known-apps catalog.

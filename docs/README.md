# Sift

A native macOS app that audits your installed applications using local AI.

For every app on your Mac, Sift answers three questions:
- **What is this?** — plain-English explanation
- **Best use for you** — one actionable tip based on your actual workflow
- **Do you need this?** — a 1–5 relevance score

Analysis runs locally. Update and app-link checks use public vendor endpoints when those features are enabled.

---

## Requirements

| Dependency | Purpose | Install |
|---|---|---|
| macOS 14+ | Required OS | — |
| [Ollama](https://ollama.ai) | Local AI analysis provider | `brew install ollama` |
| A pulled Ollama model | LLM for analysis (default `kika-ohllama:latest`; any installed model works) | `ollama pull <model>` |
| Cloud API key | Optional — use a hosted provider instead of a local server: an ollama.com, Anthropic, or OpenAI key | — |
| `create-dmg` | Polished release DMG builder | `brew install create-dmg` |

---

## Quick Start

```bash
# 1. Start Ollama
ollama serve

# 2. Pull a model (first time only) — or use any model you already have
ollama pull llama3.2

# 3. Open Sift.dmg and drag to /Applications
# 4. Launch Sift
```

Sift scans `/Applications` and `~/Applications` on launch and begins analyzing each app with the selected provider — Ollama by default (local server or ollama.com cloud), with Anthropic and OpenAI as optional cloud alternatives. Results are cached — subsequent launches are instant.

---

## Features

### App Analysis
Each app is analyzed with the selected provider and returns:
- **Explanation** — 1–2 short sentences: what it does and who uses it
- **Relevance score** — 1 (safe to uninstall) → 5 (essential)
- **Score reason** — why this score fits your workflow
- **Best use** — one concise action tip for your stack

### Workflow Context
Sift scores apps against an automatic workflow profile derived from your installed apps — category counts, the apps you've used most recently, and what's open right now. Settings → Profile shows the current digest; an optional custom override replaces it entirely. Leave the override empty to stay automatic.

### Persistent Memory
Results are stored in SwiftData at:
```
~/Library/Application Support/AppAudit/AppAudit.store
```
Cached results are used on every launch — AI is only called for new apps or when you click **Re-analyze**.

Cache is invalidated only when the **approved app link** used for the analysis changes. Switching the Ollama model no longer wipes your analyses — instead Sift keeps them and shows a dismissible banner offering to re-analyze the affected apps (see **Re-analyze**).

Side-builds (e.g. the `Sift2` test app) use a store folder derived from the bundle identifier, so they never touch the primary app's data.

Profile edits are used the next time an app is analyzed. Click **Re-analyze** on an app to refresh its score with the current profile.

### Re-analyze (single and bulk)
- **Re-analyze** in an app's detail pane refreshes just that app.
- **Re-analyze All Apps** (toolbar ⋯ menu) refreshes every unlocked app at once.
- When you switch models, the **"model changed"** banner offers a one-click re-analyze of only the apps whose analysis came from a different model. Locked analyses are always skipped.

### Lock Mode
Lock an app's analysis from the detail pane or row context menu to prevent accidental regeneration. Locked analyses are preserved across rescans, provider changes, model changes, and manual Re-analyze clicks until you unlock them.

### My Apps
Right-click any app → **Mark as My App** to tag apps you built yourself. Tagged apps show a 🔨 badge and purple score ring. Use the toolbar **Filter** menu → **My Apps** to show just your apps.

### Subscriptions
Right-click any app → **Mark as Subscription** to flag apps you pay a recurring fee for. Flagged apps show a teal 💳 badge so you can spot ongoing costs at a glance.

### Sorting & Filtering
The toolbar **Sort** menu offers:
- **Relevance** — highest score first
- **Updates** — apps with an available update
- **Last Used** — most recently used first (from Spotlight's `kMDItemLastUsedDate`); apps macOS has no usage record for sort last as "Never used". While this sort is active each row shows a relative "Used N ago".
- **Name** — alphabetical

The toolbar **Filter** menu adds toggles for **My Apps** and **Favorites**, applied on top of the current sort.

### Updates
For App Store apps and apps with a Sparkle appcast URL, Sift checks whether a newer version is available. Right-click an app or use the detail pane to open the update target or mark the update as handled.

### App Links
Sift automatically suggests missing app links when it can resolve them:
- App Store apps use Apple's lookup API by bundle ID
- Sparkle apps use the appcast website link or feed host

A suggested link is **prefilled into the editable App Link field** — it is used only after you save it (just like a manual link). There is no separate approval step.

When you add or change an app link, Sift re-analyzes that app with the link as context unless the analysis is locked.

### License Keys
Store purchased license keys per app in macOS Keychain. Keys can be added, copied, edited, or removed from the row context menu or detail pane. Copying or revealing a key asks for Touch ID (or your password) via the macOS authentication sheet — keys are never shown or copied without it. Each key can record the email it's registered to — set a default in Settings → General, and override per key for apps bought under a different account.

### Export to CSV
Sidebar **⋯ menu → "Export to CSV…"** writes the full audit (name, bundle ID, version, category, score, recommendation, explanation, update status, My App, Favorite, Subscription, notes) to a CSV you can open in Numbers/Excel. **License keys are never included.**

### License Vault
Open from the sidebar **⋯ menu → "License Vault…"** (⇧⌘L). It collects **all** your license keys in one place, split into **Installed** and **No longer installed** — so a key never disappears: when you uninstall an app it simply moves sections, and moves back when you reinstall. Copying a key asks for Touch ID (or your password) via the macOS authentication sheet. You can delete a key with the trash button. You can also manage an installed app's key from its detail panel.

### Detail Panel
The detail panel is **facts-first**: the "What is this?" explanation comes first,
followed by the relevance score, best-use tip, and reason, then calm Notes / License /
App Link rows. The header shows the app icon, name · version · category, tag badges
(⭐ favorite, 🔨 My App, 💳 subscription, 🔒 locked), and a compact update pill.

A single **⋯ overflow menu** (top-right) holds the analysis actions: Re-analyze,
Lock/Unlock, and Customize/Remove description. Everything else about the app —
tags, license keys, Finder, Copy Bundle ID — lives in the sidebar right-click menu.

When an analysis is weak and the app has no link, Sift says so and offers Add Link right in the panel.

### Editing
In the detail panel you can:
- **Customize description** — override the AI explanation with your own text (⋯ menu)
- **Notes** — free-form notes (when you installed it, whether to keep it, etc.)

Both are preserved across re-analyses.

### Right-click Menu
| Action | Description |
|---|---|
| Re-analyze | Refresh this app's analysis (disabled while locked) |
| Add / Remove from Favorites | Tag apps for a short review list |
| Mark / Unmark as My App | Tag apps you built |
| Mark / Unmark Subscription | Flag apps with a recurring fee |
| Lock / Unlock Analysis | Prevent accidental regeneration |
| Add / Copy / Edit / Remove Key | Manage purchased license keys |
| Update App / Mark Updated | Open available update target or acknowledge it |
| Show in Finder | Reveal the .app bundle |
| Open App | Launch the app |
| Copy Bundle ID | Copy `com.example.app` to clipboard |

---

## Settings (`⌘,`)

### Models Tab
- **Provider** — Ollama is the default; **Anthropic** and **OpenAI** are under **Advanced → Engine**.
- **Ollama** — Base URL (default `http://localhost:11434`), optional API Key (for ollama.com cloud models — set the Base URL to `https://ollama.com`), and a model picker fetched from `/api/tags`. The default model is `kika-ohllama:latest`; pick any installed model.
- **Anthropic / OpenAI** — paste your API key; the model list is **fetched** from the provider (`/v1/models`) and shown in a picker. Keys are stored in app preferences.
- The refresh button next to the key/URL tests the connection and fetches models.

All providers use the same analysis prompt and structured-output parser; only the transport differs. New runs start on Ollama by default; any stored choice is never changed.

### Profile Tab
- **Automatic profile** — a read-only preview of the digest derived from your installed apps (categories, recently used, open now).
- **Custom override** — optional text that replaces the automatic profile entirely; leave empty to stay automatic.
- **Clear Override** — returns to the automatic profile.

### Scanning Tab
- **Include Apple system apps** — off by default (adds noise)
- **Include /Applications/Utilities** — on by default

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `⌘R` | Rescan apps |
| `⇧⌘L` | Open License Vault |
| `⌘,` | Open Settings |
| `↑↓` | Navigate app list |

---

## Build from Source

```bash
git clone <repo>
cd AppAudit

# Run directly
swift run

# Build .app bundle
bash Scripts/compile_and_run.sh

# Build DMG
bash Scripts/make_dmg.sh
```

### Scripts

| Script | Purpose |
|---|---|
| `Scripts/compile_and_run.sh` | Kill → build release → package → launch |
| `Scripts/package_app.sh` | Create signed `.app` bundle from binary |
| `Scripts/make_dmg.sh` | Build the app and create a polished `create-dmg` drag-to-install DMG |
| `Scripts/build_sift2.sh` | Build/sign/install the `Sift2` side-build (isolated store + Keychain) for testing alongside the primary app |

See [Release Checklist](RELEASE.md) before Developer ID signing or notarization.

---

## Architecture

```
Presentation   SwiftUI Views + @Observable ViewModel
Business       Services (AppScanner, OllamaService, UpdateChecker, AppLinkResolver)
Data           SwiftData (AppRecord) + UserDefaults (Settings)
```

### Key Files

| File | Role |
|---|---|
| `AppListViewModel.swift` | Orchestrates scan → cache → AI enrichment |
| `AnalysisProviderKind.swift` | Provider selection and cache identifier |
| `OllamaService.swift` | Ollama analysis with strict structured text output |
| `LicenseVaultView.swift` | All license keys, sectioned Installed / No longer installed |
| `CSVExporter.swift` | RFC-4180 CSV of the audit (no keys) |
| `AppLinkResolver.swift` | App Store and Sparkle app link discovery |
| `AppScanner.swift` | FileManager + Info.plist enumeration |
| `WorkflowProfile.swift` | Local workflow profile text used for relevance scoring |
| `CacheService.swift` | SwiftData read/write + cache invalidation |
| `AppRecord.swift` | Persisted model: AI results + user edits + tags |

### AI Prompt Design

All four fields (explanation, score, reason, best use) are returned in one provider call. Ollama uses a strict structured text format:

```
EXPLANATION: ...
SCORE: [1-5]
REASON: ...
BEST_USE: ...
```

A system prompt sets the analyst persona and instructs the model to answer directly (no "appears to be" hedging).

---

## Data Model

`AppRecord` (SwiftData):

| Field | Type | Purpose |
|---|---|---|
| `bundleID` | `String` (unique) | Primary key |
| `explanation` | `String` | AI-generated description |
| `relevanceScore` | `Int` | 1–5 relevance |
| `relevanceReason` | `String` | Score justification |
| `bestUse` | `String?` | Actionable workflow tip |
| `ollamaModel` | `String` | Provider/model identifier that generated this (for invalidation) |
| `userDescription` | `String?` | User's custom description |
| `notes` | `String?` | Free-form user notes |
| `isMyApp` | `Bool` | Tagged as user-built |
| `isFavorite` | `Bool` | Tagged as a favorite |
| `hasSubscription` | `Bool` | Flagged as a recurring/subscription cost |
| `hasLicenseKey` | `Bool` | A license key is stored in Keychain (powers the License Vault) |
| `isAnalysisLocked` | `Bool` | Prevents accidental regeneration |
| `appURL` | `String?` | User-approved app link used as analysis context |
| `suggestedAppURL` | `String?` | Automatically found link awaiting user approval |
| `analysisAppURL` | `String?` | App link used for the current cached analysis |
| `acknowledgedUpdateVersion` | `String?` | Latest version the user marked handled |
| `generatedAt` | `Date` | When last analyzed |

License keys are stored in macOS Keychain via `LicenseKeyStore`, not in SwiftData, with device-bound accessibility (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — not iCloud-synced). A one-time launch sweep migrates any legacy plaintext key out of the store and into the Keychain. The Keychain service name is derived from the bundle identifier, so side-builds (e.g. `Sift2`) use an isolated service and never read or prompt for the primary app's keys.

`lastUsedDate` (most-recent-use, from Spotlight) is read fresh at scan time and lives on the in-memory `AppInfo`, not in SwiftData.

---

## Troubleshooting

**Analyses look out of date after switching models**
Switching the Ollama model no longer auto-wipes analyses. Sift keeps the old results and shows a banner offering to re-analyze the affected apps — click **Re-analyze** in the banner, or use **Re-analyze All Apps** in the toolbar ⋯ menu.

**"AI Unavailable" in detail panel**
Start Ollama with `ollama serve` (local), or check the Base URL / API Key in Settings → Models if you're using ollama.com cloud models.

**Crash on launch**
Delete the SwiftData store to reset:
```bash
rm ~/Library/Application\ Support/AppAudit/AppAudit.store*
```

**App icon not showing in Dock**
```bash
killall Dock
```

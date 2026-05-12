# AppAudit

A native macOS app that audits your installed applications using local AI.

For every app on your Mac, AppAudit answers three questions:
- **What is this?** — plain-English explanation
- **Best use for you** — one actionable tip based on your actual workflow
- **Do you need this?** — a 1–5 relevance score

Everything runs locally. No cloud. No tracking.

---

## Requirements

| Dependency | Purpose | Install |
|---|---|---|
| macOS 14+ | Required OS | — |
| [Ollama](https://ollama.ai) | Local AI analysis | `brew install ollama` |
| A pulled model | LLM for analysis | `ollama pull llama3.2` |

---

## Quick Start

```bash
# 1. Start Ollama
ollama serve

# 2. Pull a model (first time only)
ollama pull llama3.2

# 3. Open AppAudit.dmg and drag to /Applications
# 4. Launch AppAudit
```

AppAudit scans `/Applications` and `~/Applications` on launch and begins analyzing each app with Ollama. Results are cached — subsequent launches are instant.

---

## Features

### App Analysis
Each app is analyzed with a single Ollama request that returns:
- **Explanation** — 2 sentences: what it does and who uses it
- **Relevance score** — 1 (safe to uninstall) → 5 (essential)
- **Score reason** — why this score given your workflow
- **Best use** — one concrete action tip for your stack

### Workflow Context
AppAudit scores apps against an editable local workflow profile. The default profile is focused on native app development, web development, terminal tooling, Codex, Ollama, packaging, and local-first software work.

### Persistent Memory
Results are stored in SwiftData at:
```
~/Library/Application Support/AppAudit/AppAudit.store
```
Cached results are used on every launch — Ollama is only called for new apps or when you click **Re-analyze**.

Cache is invalidated only when you change the Ollama model in Settings.

Profile edits are used the next time an app is analyzed. Click **Re-analyze** on an app to refresh its score with the current profile.

### My Apps
Right-click any app → **Mark as My App** to tag apps you built yourself. Tagged apps show a 🔨 badge and purple score ring. Use the **My Apps** sort option to filter to just your apps.

### Updates
For App Store apps and apps with a Sparkle appcast URL, AppAudit checks whether a newer version is available. Right-click an app or use the detail pane to open the update target or mark the update as handled.

### License Keys
Store purchased license keys per app in macOS Keychain. Keys can be added, copied, edited, or removed from the row context menu or detail pane.

### Editing
In the detail panel you can:
- **Customize description** — override the AI explanation with your own text
- **Notes** — free-form notes (when you installed it, whether to keep it, etc.)

Both are preserved across re-analyses.

### Right-click Menu
| Action | Description |
|---|---|
| Mark / Unmark as My App | Tag apps you built |
| Add / Copy / Edit / Remove Key | Manage purchased license keys |
| Update App / Mark Updated | Open available update target or acknowledge it |
| Show in Finder | Reveal the .app bundle |
| Open App | Launch the app |
| Copy Bundle ID | Copy `com.example.app` to clipboard |

---

## Settings (`⌘,`)

### Ollama Tab
- **Base URL** — default `http://localhost:11434`
- **Model picker** — fetches installed models live from `/api/tags`
- **Test connection** — verifies Ollama is reachable

### Profile Tab
- **Workflow profile** — local text used by Ollama when scoring relevance
- **Restore Default Profile** — resets the profile to AppAudit's built-in developer workflow

### Scanning Tab
- **Include Apple system apps** — off by default (adds noise)
- **Include /Applications/Utilities** — on by default

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `⌘R` | Rescan apps |
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
| `Scripts/make_dmg.sh` | Create compressed DMG with drag-to-install layout |

---

## Architecture

```
Presentation   SwiftUI Views + @Observable ViewModel
Business       Services (AppScanner, OllamaService)
Data           SwiftData (AppRecord) + UserDefaults (Settings)
```

### Key Files

| File | Role |
|---|---|
| `AppListViewModel.swift` | Orchestrates scan → cache → AI enrichment |
| `OllamaService.swift` | Single-request AI analysis with structured output |
| `AppScanner.swift` | FileManager + Info.plist enumeration |
| `WorkflowProfile.swift` | Local workflow profile text used for relevance scoring |
| `CacheService.swift` | SwiftData read/write + cache invalidation |
| `AppRecord.swift` | Persisted model: AI results + user edits + tags |

### AI Prompt Design

All four fields (explanation, score, reason, best use) are returned in a single Ollama request using a strict structured format:

```
EXPLANATION: ...
SCORE: [1-5]
REASON: ...
BEST_USE: ...
```

A `system` prompt sets the analyst persona. This approach is 3x faster than separate requests and gives the model full context when scoring.

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
| `ollamaModel` | `String` | Model that generated this (for invalidation) |
| `userDescription` | `String?` | User's custom description |
| `notes` | `String?` | Free-form user notes |
| `isMyApp` | `Bool` | Tagged as user-built |
| `acknowledgedUpdateVersion` | `String?` | Latest version the user marked handled |
| `generatedAt` | `Date` | When last analyzed |

License keys are stored in macOS Keychain via `LicenseKeyStore`, not in SwiftData.

---

## Troubleshooting

**App re-analyzes everything on every launch**
Cache is invalidated when the Ollama model changes. Check Settings → Ollama that the model hasn't changed.

**"AI Unavailable" in detail panel**
Ollama is not running. Start it: `ollama serve`

**Crash on launch**
Delete the SwiftData store to reset:
```bash
rm ~/Library/Application\ Support/AppAudit/AppAudit.store*
```

**App icon not showing in Dock**
```bash
killall Dock
```

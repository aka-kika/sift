# Sift — User and Developer Guide

**Version 1.8.0** · macOS 14+ · Apple Silicon

A native macOS app that audits your installed applications with a local model.
For every app on your Mac, Sift answers three questions:

- **What is this?** — a plain-English explanation
- **Good for** — one actionable tip based on your actual workflow
- **Do you need this?** — a 1–5 relevance score

Analysis runs on your machine by default. Nothing is collected, and no Sift
server exists — see [Privacy & Permissions](privacy.md).

---

## Requirements

| Dependency | Purpose | Install |
|---|---|---|
| macOS 14+ | Required OS | — |
| [Ollama](https://ollama.ai) | Local analysis provider (default) | `brew install ollama` |
| A pulled Ollama model | The model itself (default `kika-ohllama:latest`; any installed model works) | `ollama pull <model>` |
| Cloud API key | Optional — ollama.com, Anthropic, OpenAI, Google Gemini, or OpenRouter instead of a local server (Gemini and OpenRouter have free tiers) | — |

Building from source has its own prerequisites — see [Environment Setup](environment.md).

---

## Quick start

```bash
ollama serve
ollama pull llama3.2
```

Open `Sift-1.8.0.dmg`, drag Sift to Applications, launch it. Sift scans
`/Applications` and `~/Applications` and analyzes each app with the selected
provider. Results are cached, so later launches are instant.

---

## The window

A sidebar of your apps, a detail pane for the selected one.

**Sidebar** — search field, a **Sort** picker in the toolbar, and a Rescan
button. Each row shows the icon, name, version, a score badge, and small badges
for what's true of that app: favorite, My App, and one **license badge** that
mirrors the detail view's License cube exactly (same glyph, same colour).

**Sort** — Relevance (highest first), Updates (only apps with one; the Rescan
button becomes Refresh Updates), Last Used (most recent first; apps macOS has no
record for sort last as "Never used"), or Name.

**Filter** — under the View menu: **Favorites**, plus **My Apps** when Developer
Mode is on. Filters apply on top of the current sort.

---

## The detail pane

Reads top to bottom: header, analysis, facts.

### Header

App icon, name · version, category, bundle ID (selectable), and an update pill
when one is available. On the right sits the **cube strip** — small icon
buttons, one per kind of per-app data, in a self-balancing grid (one row up to
five cubes, otherwise two even rows). Hovering a cube writes its name and state
into the line beneath it, with no tooltip delay.

| Cube | What it does |
|---|---|
| **Re-analyze** | Refresh this app's analysis (appears once one exists, disabled while locked) |
| **Notes** | Free-form notes — they feed the next analysis as evidence |
| **License** | Everything money: licence key, type, subscription, paid/free |
| **App Link** | Open the app's site, or add/edit the link |
| **Lock** | Freeze the analysis against regeneration |
| **Favorite** | Star it |
| **My App** | Mark an app you build (Developer Mode only) |
| **Docs** | Attach a local project folder as evidence (Developer Mode, My Apps only) |

### Analysis

- **What is this?** — the explanation. Your own description, if you write one, sits above it and the AI's moves below under "AI explanation".
- **The score** — five dots and a word, coloured by score.
- **Good for** — the actionable tip.
- **Tip** — why this score fits your workflow.
- **Similar apps you have** — overlap picked only from apps you already own, with its own refresh.
- When an analysis is weak and the app has no link, Sift says so and offers **Add Link** in place.

### Facts

A quiet row closing the page: **on disk**, **last used**, **source**, and
**analyzed**. Four cells on one line. Anything Sift doesn't know is left out
rather than shown blank.

---

## The License cube

One cube owns the whole money story, and its face tells you the state at a
glance. Precedence: subscription, then App Store, then licensed/paid, then free.

| Face | Colour | Means |
|---|---|---|
| `creditcard.fill` | teal, orange near renewal | A subscription with a renewal date |
| `checkmark.seal.fill` | blue | Mac App Store install, no licence type recorded |
| `infinity` | indigo | Lifetime licence |
| `1.circle` | purple | One-time purchase |
| `calendar` | cyan | Annual licence |
| `key.horizontal` | indigo | A key with no type, or type "Other" |
| `gift` | green | Marked free |
| `dollarsign.circle` | grey | Nothing recorded yet |

Once you record a licence type it wins the face — a Mac App Store app marked
Lifetime shows `infinity`, and the store fact moves to the popover banner and
the hover line.

**Clicking** opens one popover with **Key** and **Subscription** tabs:

- **Key** — the licence key (hidden until you reveal it with Touch ID), the registered email, and a **Type** picker: Not set, Lifetime, One-time, Annual, Other.
- **Subscription** — amount, currency, monthly/yearly, renewal date, billing email.
- App Store installs get a seal banner **above** the tabs and keep every field, so a store purchase can be marked Lifetime and a mis-detected install can still take a key.
- **Save works without a key** — a licence type saves on its own, and can be corrected or cleared back to Not set at any time.
- A lifetime or one-time licence greys the Subscription tab; nothing can be a subscription and a permanent purchase at once.

**Right-click** is state-aware and offers only what makes sense: Copy Key,
Edit License…, Remove Key, or — when nothing is recorded — Mark as Paid and
Mark as Free App.

Keys live in the **macOS Keychain**, keyed to the bundle ID, device-bound and
never iCloud-synced. Revealing or copying one asks for Touch ID.

---

## License Vault

**File → License Vault…** (`⇧⌘L`) collects everything you've bought in one
place, split into **Installed** and **No longer installed** — uninstall an app
and its licence simply moves sections, then moves back if you reinstall.

A row appears if it has a key, a Paid mark, **or** a licence type. Rows show the
icon, name, bundle ID, registered email, and either a Copy Key button or a
coloured pill naming the licence type.

**The app name is a link out** to where you bought it: your saved link first,
then Sift's suggestion, and a web search when neither is on record — so a kept
licence never leaves you hunting for the vendor.

---

## Uninstall

Right-click any app → **Uninstall…** opens the sweep panel: the bundle plus
every leftover matched to its bundle ID, each with a size and the reason it
matched, all pre-checked.

- **Everything goes to the Trash** — recoverable by design, nothing is deleted.
- The **AppRecord survives** — licence keys, notes, and marks stay in the vault.
- A **running app** offers Quit & Continue.
- **Homebrew casks** can run `brew uninstall` instead.
- **Apple system apps** (`com.apple.*`) and Sift itself are refused.

Leftovers are searched across Application Support, Caches, Preferences (and
ByHost), Logs, Containers, Group Containers, Saved Application State, WebKit,
HTTP Storages, LaunchAgents, Application Scripts, and Cookies. Matching is
identifier-first; a bare app name is trusted only under Application Support and
Logs, where vendors conventionally use it.

**Mac App Store apps need one extra step.** Store bundles are owned by root, and
macOS only lets Finder move them — so Sift hands those to Finder, which raises
the standard Automation prompt the first time ("Sift wants to control Finder").
Approve it once. No password passes through Sift. Anything that still can't be
moved is listed with its real reason and a Show in Finder button. The reasoning
is recorded in [ADR 0003](decisions/0003-finder-does-privileged-trash-moves.md).

---

## Analysis

### What grounds it

Sift never guesses from a bundled catalog. Each analysis sees only real
evidence: the app's own metadata, your notes, the fetched words of an app link
you saved, and — for apps you mark as your own — a local project folder's README
and manifests.

Apps are scored against a **workflow profile** derived automatically from your
installed apps: category counts, what you've used recently, what's open now.
Settings → Profile shows the digest and lets you replace it with your own text.

All four fields come back in one call, in a strict structured format:

```
EXPLANATION: ...
SCORE: [1-5]
REASON: ...
BEST_USE: ...
```

### Caching and re-analysis

Results persist and are reused on every launch. The cache is invalidated only
when the **saved app link** changes. Switching models does **not** wipe
analyses — Sift keeps them and offers a banner to re-analyze just the apps whose
results came from a different model.

- **Re-analyze cube** — this app.
- **File → Re-analyze All Apps** (`⇧⌘R`) — every unlocked app.
- **Lock** — freezes an analysis against rescans, provider changes, model changes, and manual re-analysis until unlocked.

### Updates

For App Store apps, apps with a Sparkle appcast, and Homebrew casks, Sift checks
whether a newer version exists. The row offers the update action or **Mark
Updated** to acknowledge it. Homebrew updates can run `brew upgrade --cask` or
copy the command.

### App links

Sift suggests a link when it can resolve one — Apple's lookup API by bundle ID
for store apps, the appcast website or feed host for Sparkle apps. A suggestion
is **prefilled** into the editable field and only takes effect once you save it.
Saving a new link re-analyzes the app with it, unless the analysis is locked.

---

## Right-click menu (sidebar)

| Action | Description |
|---|---|
| Re-analyze | Refresh this app's analysis (disabled while locked) |
| Lock / Unlock Analysis | Prevent accidental regeneration |
| Add / Remove from Favorites | Tag apps for a short review list |
| Mark / Unmark as My App | Tag apps you build (Developer Mode) |
| Copy Key | Copy the licence key (Touch ID) |
| Add License… / Set License Type… / Edit License… | Opens the detail License popover directly |
| Show in Finder | Reveal the `.app` bundle |
| Open App | Launch it |
| Update App / Mark Updated | Open the update target, or acknowledge it |
| Copy Bundle ID | Copy `com.example.app` |
| Uninstall… | Open the sweep panel |

---

## Settings (`⌘,`)

**Models** — provider and model. Ollama is the default (Base URL
`http://localhost:11434`, optional API key for ollama.com cloud models);
Anthropic, OpenAI, Google Gemini and OpenRouter live under Advanced → Engine. Model lists are fetched from
the provider, and the refresh button tests the connection.

**Profile** — the automatic workflow digest (read-only preview), an optional
custom override that replaces it entirely, and **Analysis style**: a line
appended to every analysis whichever engine runs it.

**General** — appearance (System / Light / Dark), a default email for new
licence keys, directory toggles (`/Applications/Utilities` on by default, Apple
system apps off), and **Developer Mode**, which reveals the My App tools — the
hammer and docs cubes, sidebar badges, and the My Apps filter. Turning it off
hides the UI and keeps every mark.

**About** — version, build commit, and links out.

---

## Export

**File → Export to CSV…** (`⌘E`) writes the full audit: name, bundle ID,
version, category, score, recommendation, explanation, update status, My App,
Favorite, Subscription, sub price / cycle / renewal, source, paid, and notes.
**Licence keys are never included.**

---

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `⌘R` | Rescan apps (Refresh Updates in the Updates sort) |
| `⇧⌘R` | Re-analyze all apps |
| `⌘E` | Export to CSV |
| `⇧⌘L` | Open License Vault |
| `⌘,` | Settings |
| `↑` `↓` | Navigate the app list |

---

## Build from source

See [Environment Setup](environment.md) for the full path. In short:

```bash
swift build && swift test
bash Scripts/package_app.sh
open Sift.app
```

| Script | Purpose |
|---|---|
| `Scripts/compile_and_run.sh` | Kill → build release → package → launch |
| `Scripts/package_app.sh` | Build the `.app` bundle (ad-hoc by default; `SIGNING_MODE=developer` for release) |
| `Scripts/make_dmg.sh` | Build the app and a polished drag-to-install DMG |
| `Scripts/build_sift2.sh` | Build the `Sift2` side-build — its own bundle ID, so its store and Keychain never touch the primary app's |

See the [Release Checklist](RELEASE.md) before signing or notarizing.

---

## Architecture

```
Presentation   SwiftUI Views + @Observable ViewModel
Business       Services (AppScanner, analysis providers, UpdateChecker,
               AppLinkResolver, LeftoverScanner, TrashService)
Data           SwiftData (AppRecord) + Keychain (keys) + UserDefaults (settings)
```

Pure rules live in `Models/` as plain enums and structs so they can be unit
tested without a view: `MoneyCubeState`, `UtilityCardRules`, `LicenseDraftRules`,
`AppFacts`, `VaultLink`, `UninstallRules`, `LeftoverMatcher`. 133 tests across
35 suites cover them.

### Key files

| File | Role |
|---|---|
| `AppListViewModel.swift` | Orchestrates scan → cache → AI enrichment |
| `AppScanner.swift` | FileManager + Info.plist enumeration |
| `CacheService.swift` | SwiftData read/write and cache invalidation |
| `AnalysisProviderKind.swift` | Provider selection and cache identifier |
| `OllamaService.swift` | Local analysis with strict structured output |
| `OpenAICompatibleService.swift` | One transport for OpenAI, Gemini (OpenAI-compatible endpoint) and OpenRouter |
| `AppAnalysisPrompt.swift` | The one prompt all providers share |
| `AppDetailView.swift` | Header, cube strip, analysis, facts |
| `MoneyPopover.swift` | The Key / Subscription panel |
| `MoneyCubeState.swift` | One licence state → one face and colour, everywhere |
| `LicenseKeyStore.swift` | Keychain storage, bundle-ID-derived service |
| `LicenseVaultView.swift` | Everything bought, installed or not |
| `LeftoverScanner.swift` | Bundle-ID-first leftover discovery |
| `TrashService.swift` | Trash move, with the Finder fallback |
| `AppLinkResolver.swift` | App Store and Sparkle link discovery |
| `CSVExporter.swift` | RFC-4180 CSV (no keys) |

### Where data lives

```
~/Library/Application Support/AppAudit/AppAudit.store    SwiftData
macOS Keychain, service derived from the bundle ID       licence keys
UserDefaults                                             settings
```

Side-builds derive both the store folder and the Keychain service from their own
bundle identifier, so `Sift2` never reads — or prompts for — the primary app's
keys.

`lastUsedDate` comes fresh from Spotlight at scan time and lives on the
in-memory `AppInfo`, not in SwiftData.

---

## Troubleshooting

**"AI Unavailable" in the detail pane**
Start Ollama (`ollama serve`), or check the Base URL / API key in Settings →
Models if you're using cloud models.

**Analyses look out of date after switching models**
They're kept on purpose. Use the "model changed" banner to re-analyze only the
affected apps, or `⇧⌘R` for all unlocked ones.

**Uninstall says "could not be moved"**
Read the reason on the row. If it's an App Store app and you denied the Finder
prompt, re-enable it in System Settings → Privacy & Security → Automation → Sift.

**"Sift wants to control Finder"**
Expected, and only on the first uninstall of an app Sift can't move itself. See
[Privacy & Permissions](privacy.md).

**Crash on launch**
Reset the store — this drops your audit and notes, but not your keys:

```bash
rm ~/Library/Application\ Support/AppAudit/AppAudit.store*
```

**App icon not showing in the Dock**

```bash
killall Dock
```

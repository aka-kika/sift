<!--
Changelog — PER PROJECT. From TAMPLATES/3-workflow/changelog.
Format: Keep a Changelog. Versioning: SemVer. Newest version at the top.
Append to [Unreleased] as you work; on release, rename it to the version + date.
Style: no emojis. Monochrome. SF Symbol names noted in comments, not rendered.
-->

# Changelog

All notable changes to Sift are recorded here.
Format: [Keep a Changelog](https://keepachangelog.com). Versioning: [SemVer](https://semver.org).

## [Unreleased]

Next up (1.13): real in-place updates for Sparkle apps, and an analysis that works out of the box — Apple Intelligence or a small bundled model — so Sift does not need Ollama or a key to be useful. See `docs/roadmap.md`.

## [1.12.4] — 2026-10-20

<!-- SF Symbol: checkmark.shield -->
### Fixed
- Mac App Store apps could not be uninstalled in the shipped build: the hardened runtime blocked the Finder handoff. The app now carries the Apple Events entitlement; macOS asks once to let Sift control Finder.
- When the app bundle could not be moved to the Trash, the sweep still trashed its data. The app now goes first, and if it stays, nothing else is touched.
- `brew uninstall` could run for a different copy with the same name. It is offered only when Homebrew's install record for the cask points at this exact bundle.
- Uninstall could pre-check shared data that a second copy outside the scanned folders still uses. Spotlight now finds every copy with the same bundle ID; another copy, or no answer from Spotlight, leaves the data unchecked.
- A licence key showed "Key saved" even when the Keychain write failed. The panel now flips only on success and says so when the Keychain refuses.
- At launch Sift read every licence key from the Keychain to see whether one existed. That check is now attribute-only; a key is read only after Touch ID. A Touch ID lock on the Keychain item itself is not possible for a Developer ID app without a provisioning profile (errSecMissingEntitlement), so privacy.md now says Touch ID is Sift's own gate.
- Cloud API keys sat in plain text in the preferences plist. They live in the login keychain now (service `com.kikaapp.appaudit.apikeys`); a launch migration moves them and removes the plist copy only once the Keychain holds the key.
- With a cloud provider every analysis sent the names of recent and open apps. The cloud workflow profile now carries counts and categories only; Find Similar, which has to send the app list, asks first every time on a cloud model.
- The default model was a private one, so a new Mac failed every analysis. The default is `llama3.2`, and a scan switches to the first installed chat model when the chosen one is missing.
- Any failed database open renamed the store and showed an empty vault. The open is retried, only a file that fails SQLite's quick_check is set aside, an intact but unreadable store stays in place for an in-memory session, and an alert names the file. The crash loop when a fresh store could not be created is gone too.

- CSV export: fields starting with = + - @ get a leading apostrophe so spreadsheets do not run them as formulas; a failed save shows an alert.
- The legacy licence-key sweep marked itself done even when the Keychain refused a key. It now retries until no plaintext key is left.
- README excerpts of attached project folders are kept in the local store; privacy.md said they were not.
- Link evidence fetched local and private addresses and sent the page to a cloud model. Local, private and link-local hosts (and redirects to them) are refused, and the query and fragment are dropped before fetching and in the prompt.
- Update feeds and Download links accepted http: and file:. They are https only now.
- The App Store lookup fell back to the first result, attaching another app's version and link. A result must match the bundle ID.
- Sparkle updates that need a newer macOS were offered. `sparkle:minimumSystemVersion` is read and the newest runnable release is chosen.
- `brew outdated` could run `brew update`. Checks run with `HOMEBREW_NO_AUTO_UPDATE=1`; a clicked upgrade keeps auto-update.
- App Group folders (`group.<id>`, team-prefixed) under Group Containers and Application Scripts stayed behind after uninstall. They are matched now, for the app's own team only.
- A copied licence key stayed on the clipboard. It is marked concealed and transient and cleared after 60 seconds if still there.
- Cmd-Q or closing the window quit Sift in the middle of an uninstall sweep or a brew command. Quit now waits and says why.
- Rescan emptied the sidebar first; an interrupted scan left it empty. The old list stays until the new one is ready.
- Apps in subfolders of /Applications (Adobe, Setapp) were never listed. The scanner walks two levels.
- Month-end renewals drifted to the 28th after February. Renewals count whole cycles from the stored date.
- The Finder handoff ran on the main thread and froze the window while macOS asked for permission. The Apple Event is sent off the main thread with a 30-second timeout (ADR 0004).
- A folder named only like the app was pre-checked even when another installed app shares the name (1Password and 1Password 7). It now starts unchecked and names the other app.

<!-- SF Symbol: doc.text -->
### Added
- What's new sheet once after each update, and Help > What's New in Sift.
- Settings > General > Updates: turn off the update checks a scan makes.

## [1.12.3] — 2026-10-14

<!-- SF Symbol: lock -->
### Changed
- The License panel no longer reads a saved key just because you opened an app. It shows "Key saved" with Reveal, Copy and Replace; Reveal and Copy ask for Touch ID first, and only then is the key read from the Keychain. Replace starts from an empty field. Saving the email or license type leaves the key alone, and an empty key field never deletes a key (the trash button does, behind Touch ID). After Reveal the panel reopens by itself, since the Touch ID prompt closes it, and closing the panel forgets the revealed key.

## [1.12.2] — 2026-10-14

<!-- SF Symbol: hammer -->
### Fixed
- Two installed copies of one app (same bundle ID) no longer draw a ghost third row in the sidebar, and each copy can be selected on its own. Row identity is now the app's path; records stay keyed by bundle ID, so both copies still share one analysis and one set of notes.
- Right-clicking another app in the sidebar and choosing Edit License or Set License Type opened the License panel with the previous app's details. Saving there could overwrite or delete the new app's key. The panel now loads the right app first, and each app gets a fresh detail view.
- Homebrew scans, update checks and upgrades could hang forever when brew printed a lot (over 64 KB, say during its own auto-update). Sift now reads brew's output while it runs.
- Removing a license key now asks for Touch ID, like revealing or copying one, in the License panel and in the License Vault. It removes only the key: the license type and email stay. The detail view no longer shows a key the vault already deleted.
- Two copies of one app: uninstalling one no longer drops both from the sidebar, update checks answer each copy on its own (no copy stuck on "Checking"), and the Uninstall panel leaves the shared settings unchecked and only quits this copy.
- "Find similar apps you have" is back under the recommendation; its button had disappeared with the Cross-App cube in 1.7.0.
- Mac App Store apps can be marked Paid again (right-click the License cube). The License Vault says "Mac App Store · Paid" only for apps that really came from the Store, and the CSV export's Paid column now says yes for any saved key, license type or Paid mark.
- Switching the AI provider or model in Settings now shows the "model changed" banner right away, not only after a rescan.
- Links typed without https (raycast.com, github.com/org/repo) are saved as https links, so the Link cube opens them, the analysis reads them and GitHub update checks find them. Links saved that way before are read correctly too.
- A model answer Sift could not read (wrong format, or the whole answer spent on thinking) is now shown as an error you can retry, not saved as the app's description. Such answers saved by older versions are analyzed again on the next scan.
- Clearing or removing an app's link now re-analyzes the app, so the description no longer rests on a link you took away.
- The pointing-hand cursor no longer stays stuck after closing the License Vault.
- The loading text says "Using local AI" only when Ollama runs on this Mac; with a cloud provider it names the provider the app's details go to.
- Sidebar rows no longer read the database or the Keychain each time they draw; the license badge uses a flag kept in memory, and the row's Copy Key reads the key only after Touch ID.

<!-- SF Symbol: globe -->
### Site
- Removed the expired launch countdown (it showed 00d 00h 00m 00s) and corrected the FAQ: Sift does uninstall apps, but only when you ask, and everything goes to the Trash.

## [1.12.1] — 2026-09-19

<!-- SF Symbol: bandage -->
### Fixed
- 1.12.0 crashed a few seconds after launch when two installed apps shared a bundle ID (a test copy beside the real app, say) and one of them had a saved GitHub link. The update refresh keyed a lookup by bundle ID and trapped on the duplicate. Widening the update check to GitHub-linked apps in 1.12.0 is what let such a pair into one batch. A regression test now holds it.

## [1.12.0] — 2026-09-19

<!-- SF Symbol: arrow.triangle.2.circlepath -->
### Added
- GitHub releases as a fourth update source. When the link you saved for an app is a GitHub repo, Sift asks that repo's latest release — so direct-download apps with no Sparkle feed, no cask and no store listing stop reading as "unavailable". Drafts and prereleases are never offered, a tag with no dotted version (`nightly`, `build-4521`) is not compared, and a Mac App Store copy is never answered by GitHub. Saving, changing or removing the link rechecks that one app straight away. The check reads the redirect of the repo's `/releases/latest` page instead of calling `api.github.com`, so it does not run into the API's 60-requests-an-hour limit however many GitHub links you save.
- GitHub links wear GitHub's own mark — on the link cube and on the update button — instead of a generic code glyph.
- Sparkle updates that keep the same version and only raise the build (`1.0` build 374 → 390) are now found, and shown as `1.0 (390)`. The build only breaks a tie; it never overrules the version.
- **Open app to update.** For an app with its own Sparkle updater, the update button now opens the app so it installs the new version in place — no more downloading a copy and swapping it in by hand. The download is still there as a second, quieter button.
- "Built with" in the facts row: Electron, Tauri, Flutter, Qt, Java, Chromium, Mac Catalyst, or native (SwiftUI / AppKit). Read from the bundle alone — nothing is run — and left out when Sift cannot tell. The analysis prompt gets the same fact.
- A quiet note under the update button when a paid or licensed app is about to jump a major version: the current license may not cover it. Store copies, free apps and calendar versions (2025 → 2026) stay quiet.

### Fixed
- The site now says what the README always did: the AI analysis needs a model (Ollama, or a free Gemini / OpenRouter key). A reader pointed out it was mentioned nowhere but GitHub.
- Version comparison reads versions the way a person does. `2.0.0` no longer counts as newer than `2.0` (a phantom update), and `1.2.3-beta` no longer counts as newer than `1.2.3`. A leading `v` is ignored.

Bundle-marker rules and the version tokenizer are adapted from [DuoUpdater](https://github.com/jizhi0v0/duo-updater) (MIT). The GitHub mark's path data is from [Simple Icons](https://simpleicons.org) (CC0).

## [1.11.0] — 2026-08-27

<!-- SF Symbol: stethoscope -->
### Fixed
- Uninstall no longer lists a sibling app's files as leftovers: removing Chrome used to pre-check Chrome Canary's and Chrome Beta's preferences and caches (any bundle ID that extends the uninstalled one — Edge Canary, JetBrains CE editions). A file that belongs to another installed app is never claimed.
- `brew uninstall` failures are failures. A wrong cask name, a cask that needs sudo, or no brew at all used to read as "Homebrew finished" and hide the app from the list while it was still installed; the sheet now shows brew's message and keeps the app bundle in the sweep.
- Re-analyze could crash, or paint its result on the wrong row, if a rescan (⌘R) or an uninstall shrank the list while the model was thinking. The result is matched back by bundle ID.
- Clicking a cube on an app whose analysis had just arrived could replace the fresh analysis with a blank record (the detail page held a stale "no record yet"). It now re-checks before creating anything.
- Opening Settings → Models no longer silently switches you to the first listed model when you were on the provider default — which then flagged every analysis as "generated with a different model".
- A packaged build without a Sparkle feed no longer writes an empty `SUFeedURL`; Check for Updates is offered only when a real feed is configured.
- Site and docs: version badge, "Launching September" copy, and download links that pointed into the private GitHub repo now point at sift.akakika.com.
- Sidebar rows no longer read the Keychain on every render; the license badge uses the flag synced at launch. On a build signed differently from the one that stored the keys, that was one macOS prompt per row.
- Two installed casks that differ only in punctuation (`x-beta` vs `x@beta`) no longer crash the scan.
- Sparkle feeds are read per item: the human version wins over the build number (no more "Update to 2045"), and beta/nightly channels are not offered to a release install.
- A license key is only removed from the old plaintext field once the Keychain verifiably holds it — a denied prompt used to be the moment the key was lost.
- Ollama HTTP errors say what Ollama said ("model 'x' not found") instead of "the data couldn't be read"; Anthropic, OpenAI, Gemini and OpenRouter share one wording, and a 429 reads as quota, not key.
- Update checks run four at a time with a 15 s cap per feed; a handful of dead vendor feeds no longer turns a refresh into minutes of "Checking…".
- Switching apps while "Find similar" or the size lookup is still running no longer writes the old app's result into the new one.
- A data store the app cannot open (downgrade, corruption) is set aside as `AppAudit.store.broken-<date>` and a fresh one created, instead of crashing before the window appears. Nothing is deleted.
- `Scripts/build_sift2.sh` is a five-line wrapper around the real packaging script instead of a drifting copy.

### Removed / tidied (no behaviour change)
- Dead code: the Ollama "legacy compatibility" block, `WorkflowProfile`'s never-filled arrays, wrapper parsers, and every `#if canImport(AppKit)` guard in a macOS-only package — about 250 lines.
- One source each for things that were written twice: update-action symbols and copy (`UpdateSource`), the 1–5 score palette (`ScoreScale`), the Sift/Sift2 build distinction (`BuildVariant`), the stub `AppRecord`, the provider-to-service mapping (`AnalysisServices.make`), the `/models` response shape, and HTTP error wording. Anthropic's analyze/complete are one request path. Providers read their preference keys from `AnalysisProviderKind` instead of repeating the strings.
- Stale files: `PROJECTS_MAP.md`, the unsigned 1.8.0 DMG and its appcast entry, two merged worktrees; executed plans/specs archived under `docs/archive/`; roadmap rewritten; version strings, provider lists and dependency claims refreshed across the docs.

## [1.10.0] — 2026-08-27

<!-- SF Symbol: bolt.horizontal -->
### Added
- Two more engines, both with free tiers: **Google Gemini** (its OpenAI-compatible endpoint; default `gemini-2.5-flash-lite`, the free tier's most generous daily quota) and **OpenRouter** (default `openrouter/free`, the alias for whatever is free that day; `:free` models listed first). A Mac with no local model can now run a full audit at no cost. Settings → Models → Advanced → Engine.

### Changed
- OpenAI, Gemini and OpenRouter share one transport (`OpenAICompatibleService`); a 429 now says "daily free quota reached" instead of blaming the key.
- Sift is free during the beta; the site says so.

## [1.9.0] — 2026-08-27

<!-- SF Symbol: arrow.triangle.2.circlepath -->
### Added
- Sift updates itself. Sparkle 2 is embedded and checks `sift.akakika.com/appcast.xml` once a day; a new version shows up as the familiar "Install and Relaunch" sheet, verified against Sift's own EdDSA key. **Check for Updates…** lives in the Sift menu and on the About tab. Until now every update meant downloading the DMG and replacing the app by hand.
- A landing page at [sift.akakika.com](https://sift.akakika.com) with a stable download link (`/Sift.dmg`), and a Homebrew cask source (`Scripts/homebrew/sift.rb`) marked `auto_updates` so `brew upgrade` leaves Sparkle in charge.

### Changed
- The About tab's GitHub row no longer says "private for now".
- `Scripts/release.sh` runs the whole pipe — Developer ID build, notarize, staple, appcast, site redirect, cask bump — so a release is one command plus a deploy.

## [1.8.0] — 2026-08-02

<!-- SF Symbol: infinity -->
### Fixed
- Uninstall works on Mac App Store apps. Store bundles are owned by root, and macOS requires write permission on a directory to move it — so every store app landed in "could not be moved". A permission refusal is now handed to Finder, which owns that path (and puts up its own prompt if one is needed); Sift never touches a password.
- The sweep says why an item was refused instead of listing a bare path, and each refusal gets a Show in Finder button.
- Mac App Store apps are no longer stuck on the seal: the License popover keeps its Key | Subscription tabs (banner above them), so a store purchase can be recorded as Lifetime, One-time, Annual or Other — and a mis-detected install can still take a key.
- The license type saves on its own. Save no longer requires a key, so a type can be set, corrected, or cleared back to Not set at any time.
- A keyless licensed app now reaches the License Vault. Records carrying only a license type were invisible there; they now list with their type, and the vault's trash clears the type along with the Paid mark.
- Sidebar right-click offers License… for App Store apps too (Set License Type… when nothing is recorded yet).

### Added
- A quiet facts row closes the detail page — on disk, last used, source, analyzed — filling the empty space under the analysis with things the prose never says. Four cells at most, so it always sits on one line; anything Sift doesn't know is left out rather than shown blank.
- An About tab in Settings: app icon, version, the line, and links out to akakika.com, undrdr.com, X, and the Sift repo — each a full-width row that lights up on hover, wearing the real brand mark (bundled vector PDFs, tinted as templates so they follow light and dark).
- App names in the License Vault are links out to the maker's site — the saved link first, then Sift's suggestion, and a web search when neither is on record, so a vault entry never leaves you googling for where you bought it.

### Changed
- "What is this?" is a proper section heading now, with a quiet text glyph in place of the info circle. No sparkles anywhere in the app — the Sparkle update action wears a download arrow instead.
- The two prose blocks under the score are labelled — Good for, Tip — so the grey line at the end reads as a finding rather than a trailing remark.
- One micro-label style across the detail page: small, uppercase, tertiary, above every fact cell and prose block.
- Long-form analysis text got a little line spacing, so the page reads less cramped.
- The License cube wears the license type once one is recorded — an App Store app marked Lifetime shows the infinity face, and its hover reads "Mac App Store — Lifetime, tied to your Apple ID".

## [1.7.0] — 2026-08-01

<!-- SF Symbol: trash -->
### Added
- Uninstall from the sidebar: right-click → Uninstall… sweeps the app and its leftovers (caches, preferences, containers, launch agents) to the Trash — recoverable, license keys and notes kept. Homebrew casks can run brew uninstall instead. Apple system apps and Sift itself are protected.
- Add/Edit License… in the sidebar right-click selects the app and opens its License popover directly.

### Changed
- Removed the Cross-App cube — the Similar-apps section keeps its own refresh; the cube grid is now symmetric (3+3 or 4+4) in everyday states.
- Sidebar right-click decluttered: the subscription toggle and the key-sheet trio collapse into the one License entry; Copy Key stays.
- License popover: the Paid pill is gone (Mark as Paid lives in the cube's right-click for keyless purchases); the Free pill shows only while nothing stronger is recorded.
- The uninstall sweep panel is larger, fitting a typical sweep without scrolling.

### Fixed
- License Vault shows icons for App Store purchases — rows fall back to the installed app's live icon, and marking Paid now captures the icon.

## [1.6.0] — 2026-08-01

<!-- SF Symbol: key.horizontal -->
### Added
- Instant label strip under the utility cubes — hover shows name + state with no tooltip delay.
- Developer Mode (Settings → Scanning): the My App tools (hammer, docs, badges, filter) hide unless enabled; all marks are preserved.
- The License cube wears its license type on its face — infinity for Lifetime, 1 for One-time, calendar for Annual, key otherwise.
- One sidebar license badge next to the app name, mirroring the cube exactly (same icon, same color).

### Changed
- License cube: license, subscription, and paid/free merged into one cube with a single tabbed popover (Key | Subscription); Save closes the panel; the right-click menu is state-aware.
- Every license state has its own color — free green, subscription teal (orange near renewal), App Store blue, lifetime indigo, one-time purple, annual cyan.
- Detail header shows 7 cubes (9 in Developer Mode), down from 10, in a self-balancing grid — one line up to 5 cubes, otherwise two even rows.

## [1.5.1] — 2026-07-05

<!-- SF Symbol: shippingbox -->
### Added
- My App cube (hammer) in the utility strip; it gates the Docs cube — only a My App can attach a local project folder.

### Changed
- The utility strip is a fixed 5-column grid — always two rows at any width.
- Header reads top-down: name + version, category, bundle ID, update indicator.
- Detail prose unified to one size/font; equal, slightly more open spacing (16pt) around the ranking dots.
- First Developer ID–signed and Apple-notarized DMG (stapled).

### Removed
- Unused `FlowLayout` (the strip is now a fixed grid).

## [1.5.0] — 2026-07-04

### Added
- Local docs evidence: attach a project folder; its README + manifests ground the analysis, fully offline.
- Cross-App: find which of your other installed apps overlap, picked only from apps you own; gated on a fully-analyzed library and frozen with a locked analysis.

### Changed
- Detail panel redesigned: minimal icon-only utility cubes in the header, wrapping gracefully; reading-width content column; default window 900x620.
- Dark mode: cubes and sidebar score badges pastelized; calmer orange banner.
- Filter, Re-analyze All Apps, Export to CSV, and License Vault moved to the native Mac menu bar.

## [1.4.0] — 2026-07-04

### Added
- Per-app notes feed the AI analysis as personal-usage evidence, with auto re-analysis on save.
- Utility cards with pricing semantics: explicit Free marker (opposite of Paid), license types (Lifetime / One-time / Annual / Other), one-click subscription marking, host-aware App Link icon.

## [1.3.3] — 2026-06-28

- Personal Ollama-first edition: Ollama is the default and tuned; Apple Intelligence and the bundled known-apps catalog removed; analysis is local and evidence-only.

## [1.1.0 – 1.3.2] — earlier

- Foundations: app scan and 1–5 workflow scoring, update detection (App Store / Sparkle / Homebrew), Keychain license keys + vault, subscription tracking, CSV export, last-used sort, instant appearance switching. See `docs/releases/` for per-version records.

<!-- Link references — point each version at its compare/diff range. -->
[Unreleased]: https://github.com/aka-kika/sift/compare/v1.11.0...HEAD
[1.11.0]: https://github.com/aka-kika/sift/compare/v1.10.0...v1.11.0
[1.10.0]: https://github.com/aka-kika/sift/compare/v1.9.0...v1.10.0
[1.9.0]: https://github.com/aka-kika/sift/compare/v1.8.0...v1.9.0
[1.8.0]: https://github.com/aka-kika/sift/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/aka-kika/sift/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/aka-kika/sift/compare/v1.5.1...v1.6.0
[1.5.1]: https://github.com/aka-kika/sift/compare/v1.5.0...v1.5.1
[1.5.0]: https://github.com/aka-kika/sift/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/aka-kika/sift/compare/v1.3.3...v1.4.0
[1.3.3]: https://github.com/aka-kika/sift/releases/tag/v1.3.3

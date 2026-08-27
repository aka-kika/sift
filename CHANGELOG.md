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

Next up: receipt extraction (spec at `docs/specs/receipt-extraction.md`).

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
[Unreleased]: https://github.com/aka-kika/sift/compare/v1.10.0...HEAD
[1.10.0]: https://github.com/aka-kika/sift/compare/v1.9.0...v1.10.0
[1.9.0]: https://github.com/aka-kika/sift/compare/v1.8.0...v1.9.0
[1.8.0]: https://github.com/aka-kika/sift/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/aka-kika/sift/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/aka-kika/sift/compare/v1.5.1...v1.6.0
[1.5.1]: https://github.com/aka-kika/sift/compare/v1.5.0...v1.5.1
[1.5.0]: https://github.com/aka-kika/sift/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/aka-kika/sift/compare/v1.3.3...v1.4.0
[1.3.3]: https://github.com/aka-kika/sift/releases/tag/v1.3.3

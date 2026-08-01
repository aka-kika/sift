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

<!-- SF Symbol: trash -->
### Added
- Uninstall from the sidebar: right-click → Uninstall… sweeps the app and its leftovers (caches, preferences, containers, launch agents) to the Trash — recoverable, license keys and notes kept. Homebrew casks can run brew uninstall instead. Apple system apps and Sift itself are protected.

### Changed
- Removed the Cross-App cube — the Similar-apps section keeps its own refresh; the cube grid is now symmetric (3+3 or 4+4) in everyday states.

Next up: receipt extraction (spec at `docs/specs/receipt-extraction.md`).

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
[Unreleased]: https://github.com/aka-kika/sift/compare/v1.5.1...HEAD
[1.5.1]: https://github.com/aka-kika/sift/compare/v1.5.0...v1.5.1
[1.5.0]: https://github.com/aka-kika/sift/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/aka-kika/sift/compare/v1.3.3...v1.4.0
[1.3.3]: https://github.com/aka-kika/sift/releases/tag/v1.3.3

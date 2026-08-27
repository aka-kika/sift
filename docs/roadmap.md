<!--
Roadmap — PER PROJECT. Now = building it · Next = committed, not started ·
Later = directional, may change. Shipped is a summary; CHANGELOG.md is the record.
Style: no emojis. Monochrome. SF Symbol names noted in comments, not rendered.
-->

# Sift — Roadmap

**Updated:** 2026-08-27 · **Current version:** 1.10.0

## Now

<!-- SF Symbol: circle.fill -->
- **Free beta** — Sift is free while downloads are counted for 14 days from the
  1.10.0 launch. Bug fixes found by living in the app land in `[Unreleased]`.

## Next

<!-- SF Symbol: circle.lefthalf.filled -->
- **Receipt extraction** — drop an invoice PDF onto an app and backfill the
  subscription and licence fields from it. Spec ready to build:
  [docs/specs/receipt-extraction.md](specs/receipt-extraction.md).
- **Pricing decision** — after the 14-day free beta: stay free, one-time, or
  something else. Decided on the download count, not before.

## Later

<!-- SF Symbol: circle -->
- **Homebrew tap** — the cask source exists (`Scripts/homebrew/sift.rb`) and
  `release.sh` bumps it; the public `aka-kika/homebrew-tap` repo is not created yet.
- **Universal binary** — add x86_64 to the release DMG for Intel Macs.
- **JSON export** — a machine-readable sibling of the CSV export.

## Shipped

<!-- SF Symbol: checkmark.circle -->
- **1.10.0** — Google Gemini and OpenRouter engines, both with free tiers, on one
  OpenAI-compatible transport; free during the beta.
- **1.9.0** — self-update through Sparkle 2 (daily appcast check, Check for
  Updates…), landing page at sift.akakika.com with a stable `/Sift.dmg`, Homebrew
  cask source, one-command release pipeline (`Scripts/release.sh`).
- **1.8.0** — App Store fixes: root-owned bundles handed to Finder for the Trash
  move, licence types save without a key, vault names link out, facts row and
  About tab.
- **1.7.0** — uninstall sweep (trash-first, bundle-ID-matched leftovers),
  Cross-App cube removed, one-entry License menu.
- **1.6.0** — one License cube with a tabbed Key / Subscription popover,
  Developer Mode, per-type licence colours mirrored in the sidebar.
- **1.5.x** — notes as analysis evidence, utility cubes, local project docs as
  evidence, My App cube, first notarized DMG.
- **1.4.0 – 1.3.3** — Ollama-first edition: Apple Intelligence engine and the
  known-apps catalog removed, analyses kept across model changes.
- **1.1.0 – 1.3.2** — foundations: scan and 1–5 workflow scoring, update
  detection (App Store / Sparkle / Homebrew), Keychain licence keys and the
  License Vault, subscriptions, CSV export, last-used sort, the AppAudit → Sift
  rename with full data continuity.

## Considering / not doing

<!-- SF Symbol: tray -->
- No-AI mode — decided against; the analysis is the product.
- Manual vault entries — decided against; the Vault auto-retains keys from
  uninstalled apps rather than becoming a general password manager.
- License keys in CSV export — decided against; keys never leave the Keychain
  except by explicit per-key copy.
- Unranked My Apps — designed, not scheduled.

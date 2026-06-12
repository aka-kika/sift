# Sift — Roadmap

**Updated:** 2026-06-12 · **Current version:** 1.2.0

> Now = building it · Next = committed, not started · Later = directional, may change

## Now

<!-- SF Symbol: circle.fill -->
- **Subscriptions filter** — the 💳-tag exists; add a filter toggle for it next
  to My Apps and Favorites so recurring costs are reviewable as a list.

## Next

<!-- SF Symbol: circle.lefthalf.filled -->
- **App Store sandbox milestone** — security-scoped ~/Applications access,
  MAS-mode Homebrew degrade, pkg + Transporter pipeline (core scan already
  proven sandbox-compatible).
- **Detail-view file split** — extract the utility rows and header from
  `AppDetailView` into focused subviews; behavior-neutral cleanup deferred from
  the redesign.

## Later

<!-- SF Symbol: circle -->
- **Self-update** — Sift should check for its own new releases the way it checks
  everyone else's.
- **Universal binary** — add x86_64 to the release DMG for Intel Macs.
- **JSON export** — a machine-readable sibling of the CSV export.

## Recently shipped

<!-- SF Symbol: checkmark.circle -->
- **1.2.0** — the grounding release: facts-first analysis with an automatic
  workflow profile, fetched link evidence, Liquid Glass on macOS 26/27, Apple
  Intelligence engine, Touch ID-protected license keys with a complete sectioned
  Vault (icons + registered emails), and the gold magnifier icon.
- **1.1.0** — first notarized release: three AI providers, License Vault,
  Last Used sort, CSV export, recommendation-first detail panel, and the
  AppAudit → Sift rename with full data continuity.

## Considering / not doing

<!-- SF Symbol: tray -->
- OpenRouter provider — parked; two cloud providers cover the need for now.
- No-AI mode — decided against; the analysis is the product.
- Manual vault entries — decided against; the Vault auto-retains keys from
  uninstalled apps rather than becoming a general password manager.
- License keys in CSV export — decided against; keys never leave the Keychain
  except by explicit per-key copy.

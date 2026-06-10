# Sift — Roadmap

**Updated:** 2026-06-10 · **Current version:** 1.1.0

> Now = building it · Next = committed, not started · Later = directional, may change

## Now

<!-- SF Symbol: circle.fill -->
- **macOS 27 / Liquid Glass polish (1.2.0)** — link against the new SDK for the
  system-wide glass appearance, add tasteful glass touches (update pill, banner
  actions, scroll-edge effects, toolbar grouping), and audit every surface under
  the new look. First because the OS just changed under the app.
- **Apple Intelligence provider (1.2.0)** — restore on-device Foundation Models
  analysis as a fourth engine alongside Ollama, Anthropic, and OpenAI.
  Availability-gated; Ollama stays the default. No API key, fully private.

## Next

<!-- SF Symbol: circle.lefthalf.filled -->
- **Subscriptions filter** — the 💳-tag exists; add a filter toggle for it next
  to My Apps and Favorites so recurring costs are reviewable as a list.
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

# Sift — Private Keys & Honest Gaps — Design

**Date:** 2026-06-10
**Status:** Approved (owner Q&A), implementing
**Branch:** `claude/jolly-poincare-38dcc2`

## Decisions

| Topic | Decision |
|---|---|
| Key protection | System authentication sheet (LocalAuthentication, `.deviceOwnerAuthentication` — Touch ID / Watch / password) on **every** license-key copy or reveal, in the detail row, the row context menu, and the Vault. Never a custom password dialog. |
| Reveal | New eye button in the detail license row: after auth, the full key shows for ~10 seconds, then re-masks. Copy never shows the key. |
| Fail mode | If no system auth is available, fail **closed** (no copy/reveal) — failing open would defeat the visible promise. |
| Honest gap callout | When a loaded analysis has **score ≤ 2 AND no saved app link AND not locked**, the detail panel shows a quiet callout: "Sift couldn't confidently identify this app… [Add Link]" opening the existing link sheet (which already re-analyzes on save). Deterministic trigger, no text parsing. |

## Work Items

1. **`Services/LicenseKeyGuard.swift`** — tiny async wrapper over `LAContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason:)`; returns Bool; fail-closed when `canEvaluatePolicy` is false.
2. **Detail license row** (`AppDetailView`): eye (reveal, gated, auto re-mask ~10s, reset on app switch) + copy (gated, "Copied" tick). Delete/edit stay ungated (they never expose the secret; the edit sheet uses a SecureField).
3. **Row context menu** (`AppRow`): "Copy Key" gated the same way.
4. **Vault** (`LicenseVaultView`): "Copy Key" gated; delete stays ungated.
5. **Callout** (`AppDetailView`): pure predicate `AppInfo.needsLinkHelp(score:hasAppURL:isLocked:)` (unit-tested) drives the callout view placed after the recommendation section.
6. Docs touch: FEATURES.md license bullet (+ Touch ID), docs/README.md License Keys section + callout mention.

## Non-Goals

- No custom password UI, no app-level passcode.
- No gating of analysis data, notes, or CSV (which never contains keys).
- No change to Keychain storage (already device-bound).

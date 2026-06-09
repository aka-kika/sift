# 0001. Keep the AppAudit bundle identifier across the Sift rename

**Date:** 2026-06-06 · **Status:** Accepted

## Context

<!-- SF Symbol: doc.text -->
The product was renamed AppAudit → Sift after a month of daily use. By then the
app owned real user data tied to its identity: a SwiftData store under
`~/Library/Application Support/AppAudit/` and eight purchased license keys in the
macOS Keychain under the service `com.kikaapp.appaudit.licensekeys`. Keychain
access and data continuity both key off the bundle identifier. A rename that
changed the identifier would orphan the store and trigger Keychain access
prompts — or silent data loss — for the app's most valuable feature.

## Options considered

<!-- SF Symbol: arrow.triangle.branch -->
- **Rename everything, migrate data** — new `com.kikaapp.sift` identifier plus a
  one-time migration that moves the store and re-writes Keychain items. Clean
  naming; but Keychain migration from an ad-hoc-to-Developer-ID transition is
  prompt-heavy and risky, and a failed migration loses license keys.
- **Keep the bundle identifier, rename the surface** — product name, window
  title, artifacts, and docs say Sift; `com.kikaapp.appaudit` and the
  `Sources/AppAudit/` path stay. Zero migration; internal names are stale.
- **Fork identities** — ship Sift as a new app and keep AppAudit installed for
  data. Two apps, permanent confusion.

## Decision

<!-- SF Symbol: checkmark.circle -->
Keep `com.kikaapp.appaudit` and the `Sources/AppAudit/` source path; rename only
what users see. Data continuity for the license keys decided it — the Keychain
items must keep working without a single prompt or migration step.

## Consequences

<!-- SF Symbol: arrow.right.circle -->
- **Good:** installing Sift over AppAudit carries every analysis, note, tag, and
  license key with no migration code and no Keychain prompts.
- **Cost:** internal identifiers (`com.kikaapp.appaudit`, `Sources/AppAudit/`,
  `AppAuditApp.swift`) no longer match the product name; every new contributor
  needs the README note explaining why.
- **Follow-ups:** the side-build derives its isolated identity
  (`com.kikaapp.sift2`) from the same switch points, so the mapping lives in
  exactly two places (`AppAuditApp.dataFolderName`,
  `KeychainSecretStoreBackend.defaultService`).

## References

<!-- SF Symbol: link -->
- `docs/superpowers/specs/2026-06-06-appaudit-practical-improvements-design.md`, item 17
- Commit `0711efa` — Rebrand AppAudit → Sift (v1.1.0)

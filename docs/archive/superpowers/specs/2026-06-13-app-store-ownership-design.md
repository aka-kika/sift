# Sift — App Store Ownership

**Date:** 2026-06-13
**Status:** Approved, ready for implementation plan
**Author:** Veronica Loren (aka-kika) + Claude

## Problem

Sift tracks "what I've paid for" via license keys. But Mac App Store apps have
no license key — Apple ties the entitlement to your Apple ID — so the License
Key row is the wrong tool for them, and there's no way to represent an App Store
purchase in the audit. The user asked: "how do we mark the bought ones from the
App Store?"

Sift already *detects* App Store apps: every scanned app carries
`AppInfo.isAppStoreInstall`, set true when the bundle contains
`Contents/_MASReceipt/receipt` (see `AppScanner.swift`). Today that flag only
routes update checks; it is never shown as provenance.

Key constraint: the receipt proves an app **came from the App Store**, but macOS
does **not** expose whether the user **paid** for it — a free and a paid App
Store app are indistinguishable to Sift. So "from the App Store" is
auto-detectable; "paid" is not, and must be an optional manual mark.

## Goals

- Surface App Store provenance automatically where the License Key row sits, so
  the user understands why there's no key ("Tied to your Apple ID").
- Let the user optionally mark an App Store app as **Paid**, giving a coherent
  "what I've bought" view spanning license-key apps and App Store purchases.
- Reflect both in CSV export (a `Source` column, auto-derived, and a `Paid`
  column).

## Non-Goals (explicit v1 cut lines)

- **No price for one-time App Store purchases.** The receipt doesn't expose it.
  (Recurring App Store subscriptions can already use the Subscription row.)
- **No License Vault entry for App Store apps** — they have no key to collect;
  the Vault stays key-only.
- **The Paid mark is App-Store-only.** Direct apps already imply "bought" via
  their license key, so no general "Paid" toggle on non-App-Store apps.
- **Detail-panel only.** No new badge in the main app-list row in v1.
- **No Touch ID** on the App Store variant — provenance and a paid flag are not
  secrets.

## Data Model

One new field on `AppRecord` (SwiftData, non-secret):

| field | type | notes |
|---|---|---|
| `isPaidApp` | `Bool` (default `false`) | the optional "I paid for this" mark. Only meaningful for App Store apps; defaults off so Sift never assumes a free app was bought. |

`AppInfo.isAppStoreInstall` already exists — no scanner change. The Paid mark is
read directly off the `AppRecord` by both the detail row and CSV export, so no
`AppInfo` projection field and no `viewModel` setter are required (mutate the
record + `saveRecord()`, the same pattern `notes` uses).

## UI — the adaptive License Key row

`licenseKeySection` in `AppDetailView` branches on `app.isAppStoreInstall`:

### Not an App Store app (unchanged)
Exactly as today: the masked key, reveal/copy behind Touch ID, edit/clear, the
registered email. No behavioral change.

### App Store app (new ownership variant)
The same row slot renders an ownership view instead of a key field:

- **Chip:** `bag.fill` SF Symbol, blue tint (distinct from the indigo key chip),
  via the existing `utilityChip` helper.
- **Label:** the row's left label reads **`Mac App Store`** for this variant
  (replacing `License Key`), so the row self-describes. Same font/weight as the
  sibling-row labels.
- **Value:** a tertiary caption `Tied to your Apple ID` sits after the label
  (occupying the spot the masked key holds in the key variant). When
  `isPaidApp == true`, a small green **`Paid`** badge shows next to it and
  remains visible regardless of hover.
- **Hover control:** a single borderless button toggling `isPaidApp` —
  `checkmark.seal.fill` when paid (help "Marked as paid — click to unmark"),
  `checkmark.seal` when not (help "Mark as paid"). Revealed on hover with the
  same `.opacity(hovered ? 1 : 0)` pattern as the other rows. No edit, no trash,
  no Touch ID.
- Any stored license key on an App Store app (rare, user error) is ignored by
  this variant — the ownership view takes precedence when `isAppStoreInstall`.

The existing `licenseHovered` state drives the hover reveal for both variants.

## CSV Export

Two additions to `exportCSV()` in `AppListViewModel`:

- **`Source`** — auto-derived per app: `App Store` if `isAppStoreInstall`, else
  `Sparkle` if `sparkleFeedURL != nil`, else `Homebrew` if
  `homebrewCaskToken != nil`, else `Other`. Implemented as a computed
  `installSourceLabel` on `AppInfo` so the logic is testable in isolation.
- **`Paid`** — `yes` when `record?.isPaidApp == true`, else blank.

Column placement: `Source` near the other provenance/status columns; `Paid`
adjacent to it. Header and row arrays must stay equal length (the existing CSV
tests / build guard this).

## Testing

- **`installSourceLabel` unit tests** (the one piece of new logic): App Store
  wins over Sparkle/Homebrew; Sparkle when only a feed URL; Homebrew when only a
  cask token; Other when none. Deterministic — construct `AppInfo` values
  directly.
- **`AppRecord.isPaidApp` default test:** a fresh record has `isPaidApp == false`.
- **CSV tests:** `Source` and `Paid` columns present with correct values for
  App-Store-paid, App-Store-unpaid, and non-App-Store cases; header/row counts
  equal.
- The App Store row variant itself is verified by build + manual check in Sift2
  (SwiftUI view, consistent with how the rest of the UI is verified).
- Existing suite stays green.

## Affected Files

- `Sources/AppAudit/Models/AppRecord.swift` — add `isPaidApp` + init default.
- `Sources/AppAudit/Models/AppInfo.swift` — add computed `installSourceLabel`.
- `Sources/AppAudit/Views/AppDetailView.swift` — branch `licenseKeySection` on
  `app.isAppStoreInstall`; add the ownership variant + a `togglePaidApp()`
  helper.
- `Sources/AppAudit/ViewModels/AppListViewModel.swift` — `Source` + `Paid` CSV
  columns.
- `Tests/AppAuditTests/AppAuditTests.swift` — `installSourceLabel`, `isPaidApp`
  default, and CSV tests.

## Future (post-v1)

- A "Paid" / source filter or a "what I've bought" summary view.
- Optional one-time purchase price note on App Store apps (parallel to the
  subscription price), if the user wants spend totals to include them.
- A provenance badge in the main app-list row.

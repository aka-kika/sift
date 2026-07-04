# Utility Cards + Pricing Semantics

**Date:** 2026-07-04
**Status:** Approved

## Summary

The four stacked utility sections in the app detail view — Notes, License Key,
Subscription, App Link — become a 2×2 grid of glass cards. Two new pricing
facts drive smart gray-out rules: an explicit **Free app** marker (the opposite
of the existing Paid marker) and a **license type** (Lifetime / One-time /
Annual / Other). Cards that cannot apply to an app are grayed with a one-word
reason, never hidden, and graying never deletes stored data.

## Background

- The detail view (`Sources/AppAudit/Views/AppDetailView.swift`) stacks
  `notesSection`, license key, subscription, and link sections with dividers;
  each expands inline, which makes the layout jump.
- `AppRecord` already has `isPaidApp`, `hasLicenseKey`, `licenseEmail`,
  subscription fields, `notes`, `appURL`/`suggestedAppURL`. License keys live
  in the Keychain via `LicenseKeyStore`.
- The notes editor (from the notes-feed-analysis feature) has Save (⌘↩) /
  Clear buttons; closing it triggers `reanalyzeAfterNotesChange`.

## Design

### 1. Card grid

- Replace the stacked utility sections with a 2-column grid of cards:
  **Notes, License, Subscription, App Link** (reading order).
- Card face: the section's icon chip, title, and a one-line status:
  - Notes: first line of the note, or "None yet".
  - License: "Saved · Lifetime" (key state + type badge), or "Add key".
  - Subscription: e.g. "€4.99/mo · renews Aug 12", or "Add subscription".
  - App Link: the host (e.g. "raycast.com"), or "Add link".
- Styling follows the existing glass card conventions (`GlassStyle.swift`).
- No inline expanders remain; the grid height is stable.

### 2. Card interactions

- **Notes** → opens a **sheet** containing the existing notes editor (Save ⌘↩,
  Clear, Esc closes). Closing the sheet ends the notes session exactly like
  the current collapse path — changed text still auto-triggers re-analysis.
  The analysis pipeline is untouched.
- **License** → sheet with the existing key + email fields plus a new **type
  picker**: Lifetime / One-time / Annual / Other.
- **Subscription** → sheet with the existing price / cycle / renewal / email
  fields.
- **App Link** → click **opens the URL** in the browser. A small
  always-visible pencil on the card opens the link editor (cards use small
  always-visible action icons rather than the old rows' hover-reveal). If no
  link is set, click opens the editor instead. Auto-suggested links (`suggestedAppURL`) keep working; editing and
  saving a link keeps triggering `reanalyzeAfterLinkChange` as today.

### 3. Pricing semantics

- New `AppRecord` field: `isFreeApp: Bool = false`.
  - The **Free** toggle sits next to the existing **Paid** marker in the
    detail view; they are mutually exclusive — setting one clears the other
    (enforced in the view model setters).
- New `AppRecord` field: `licenseType: String?` with the code-level enum
  `LicenseType: String` = `lifetime | oneTime | annual | other`; set from the
  license sheet's picker. `nil` = unset.

### 4. Gray-out rules

Evaluated live from record state (pure function, unit-tested):

- **License card disabled** when `isMyApp || isFreeApp`.
- **Subscription card disabled** when
  `isMyApp || isFreeApp || licenseType ∈ {lifetime, oneTime}`.
- Disabled card: grayed content, clicks do nothing, and a small hint states
  the reason — priority order: "Your app" (isMyApp) → "Free app" (isFreeApp)
  → "Lifetime license" / "One-time license".
- **Graying never deletes data.** Stored keys, subscription details, and the
  license type survive; un-graying reveals them unchanged.

## Out of scope

- CSV export unchanged (Paid column already exists; a License Type column can
  come later).
- Unranked My Apps (phase 2 of the notes spec) — this design only grays
  cards for My Apps, it does not touch scoring.
- No changes to the license vault, Keychain storage, or update checking.

## Testing

- Pure disable-rule function: all combinations of isMyApp × isFreeApp ×
  licenseType.
- Free/Paid mutual exclusion in the view model setters.
- LicenseType raw-value round-trip (persistence).
- Card visuals and sheet flows verified manually in the Sift2 side-build.

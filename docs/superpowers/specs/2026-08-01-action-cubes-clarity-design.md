# Action Cubes Clarity — Design

**Date:** 2026-08-01
**Status:** Approved (Kika, 2026-08-01)
**Baseline:** Sift 1.5.1 (`6832e22`)

## Problem

The detail-view header carries 10 icon-only utility cubes (re-analyze, cross-app,
notes, license, subscription, link, lock, favorite, docs, my-app). Even the owner
confuses them: the icons alone don't say what they do, ten is a wall, and
active/disabled states are hard to read. macOS tooltips carry the answers but
take ~1.5s to appear.

## Goals

1. Fewer cubes — merge the money-related ones, gate the developer-only ones.
2. Instant explanation — no tooltip delay.
3. Keep the minimal icon-cube look; no data migration, nothing lost.

Personal-first: Kika is the only user today. "Other users" framing is
far-future context, not a requirement.

## Design

### 1. Grid composition

`headerUtilities` in `AppDetailView` keeps the 34pt cube grid (5 fixed columns,
8pt spacing) but drops from 10 items to 7:

> re-analyze · cross-app · notes · **money** · link · lock · favorite

Developer Mode ON adds **docs** and **my-app (hammer)** back → 9 cubes.
Tints, active fills, and disabled looks stay as they are.

### 2. Money cube (replaces license + subscription cubes)

One cube owns all pricing state. Its face reflects the dominant state:

| State | Icon | Tint |
|---|---|---|
| App Store install | `checkmark.seal.fill` | blue |
| License key / marked paid | `key.horizontal` | indigo |
| Subscription | `creditcard.fill` | green (orange when renewal near) |
| Free app | quiet outline | secondary |
| My App | disabled | — (existing `UtilityCardRules` reason) |

Precedence when several apply: subscription > license/paid > App Store > free.

**Click → popover** (not a sheet) containing, in one panel:

- Paid / Free marks (the current context-menu toggles, visible as controls).
- App Store note when `isAppStoreInstall` ("tied to your Apple ID").
- License section: key (add, Touch-ID copy, remove), license type, email.
  Hidden for App Store installs, same as today's rules.
- Subscription section: has-subscription mark, price, currency, cycle,
  renewal date, email. Disable rules from `UtilityCardRules` apply inside
  the popover (e.g. lifetime license ⇒ subscription controls disabled with
  the existing reason text).

The popover replaces the two existing edit sheets (`editingLicenseKey`,
`editingSubscription`). Right-click on the cube keeps quick shortcuts:
Mark Paid/Free, Copy Key (Touch ID), Remove Key, Remove Subscription.

**Data:** reads/writes the exact same `AppRecord` fields
(`isPaidApp`, `isFreeApp`, `licenseKey`/keychain, `licenseType`,
`licenseEmail`, `hasSubscription`, `subscriptionPrice/Currency/Cycle/
RenewalDate/Email`). No migration.

### 3. Instant label strip

A single caption line sits directly under the cube grid, right-aligned with
it, with **reserved fixed height** so nothing jumps. Hovering a cube shows its
name + live state instantly:

- "Subscription — $9/mo · renews in 12d"
- "Docs — needs My App first"
- "Lock — analysis locked"

Content reuses the existing `.help` strings (shortened to one line). When no
cube is hovered the line is empty. `.help` tooltips remain as backup.

### 4. Developer Mode

`@AppStorage`-backed toggle, **default OFF**, in a small "Developer" section
in Settings. When OFF, everything My-App-related hides:

- hammer cube and docs cube in the detail header
- hammer badges on sidebar rows (`AppRow`)
- the My Apps library filter (`AppListViewModel` filter option)
- My-App treatment in `ScoreBadgeView`

All `isMyApp` / docs data is kept untouched; flipping the toggle back ON
restores the exact previous state. `UtilityCardRules` continues to treat
`isMyApp == true` apps as "your app" (money cube disabled) regardless of the
toggle — the toggle hides UI, it never rewrites records.

## Error handling

- Money popover validation matches the current sheets (price parsing,
  URL-free fields); nothing new to fail.
- Touch-ID copy keeps its existing `LicenseKeyGuard` flow.
- Dev-mode toggle has no failure modes (pure UI gate).

## Testing

- Unit tests for money-cube state derivation (state precedence table above).
- Unit tests for dev-mode gating (filter list excludes My Apps option when
  off; row badge logic).
- Existing `UtilityCardRules` tests keep passing unchanged.
- Visual pass via the Sift2 side-build before release.

## Out of scope

- Receipt extraction (separate deferred spec, 2026-07-04).
- Any change to analysis, ranking, or the license vault.

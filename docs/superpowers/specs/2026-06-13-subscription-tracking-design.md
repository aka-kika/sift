# Sift — Subscription Tracking

**Date:** 2026-06-13
**Status:** Approved, ready for implementation plan
**Author:** Veronica Loren (aka-kika) + Claude

## Problem

Today an app can be flagged as a subscription via a context-menu toggle
(`AppRecord.hasSubscription`), but Sift captures nothing about the subscription
itself — no price, no renewal date, no billing cycle, no account. The flag is
exported to CSV and that's it. Users forget what they pay for and when the
charge lands.

Sift should turn that flag into useful, structured data: what you pay, in which
currency, on what cycle, when it renews next, and which account it's billed to —
surfaced where you already look (the app detail panel), and warning you softly
when a renewal is near.

## Goals

- Capture subscription price, currency, cycle (monthly/yearly), next renewal
  date, and billing email per app.
- Surface it as a first-class utility row in the detail panel, matching the
  existing Notes / License Key / App Link pattern (chip, label, value,
  hover-reveal controls).
- Show a live "renews in X days" countdown that turns amber when a charge is
  near, with no system permissions or background scheduling.
- Keep the next renewal date correct over time without re-entry (auto
  roll-forward by cycle).
- Extend CSV export with the structured subscription fields.

## Non-Goals (explicit v1 cut lines)

- **No system notifications.** No `UNUserNotificationCenter`, no permission
  prompt, no background scheduling. The countdown is in-app only.
- **No spend summary / subscriptions filter view.** A "total monthly/yearly
  spend" rollup and a dedicated subscriptions list are natural follow-ons but
  out of scope for v1. The structured data this feature adds makes both cheap
  to build later.
- **No Touch ID gate.** Subscription details are not secrets (unlike license
  keys), so the row and sheet are frictionless — no authentication.

## Data Model

All fields are non-secret and live in the SwiftData `AppRecord` model (not the
Keychain). Additive and optional/defaulted, so existing stores migrate cleanly.

| field | type | notes |
|---|---|---|
| `hasSubscription` | `Bool` | **already exists** — remains the on/off flag |
| `subscriptionPrice` | `Double?` | the amount, nil if unset |
| `subscriptionCurrency` | `String?` | ISO 4217 code (e.g. `"EUR"`), defaults to the Mac's locale currency at entry time |
| `subscriptionCycle` | `String?` | `"monthly"` or `"yearly"` |
| `subscriptionRenewalDate` | `Date?` | the next charge date (date-only semantics) |
| `subscriptionEmail` | `String?` | billing account; pre-fills from `licenseEmail` or the default license email |

New `@Attribute` lines on `AppRecord` plus matching initializer defaults
(all nil / false), consistent with the existing optional fields.

### Billing cycle representation

Stored as a plain string (`"monthly"` / `"yearly"`) to match the model's
existing string-typed style and keep SwiftData migration trivial. A small
`BillingCycle` enum (`RawRepresentable`, `String`) provides type safety in code
and the roll-forward logic; the model stores its `rawValue`.

## Renewal Roll-Forward

The one piece of real logic, isolated as a pure, fully unit-tested function so
it can be reasoned about and tested without UI.

```
func nextRenewal(from stored: Date, cycle: BillingCycle, now: Date, calendar: Calendar) -> Date
```

Behavior: if `stored` is in the past relative to `now`, advance it by the cycle
(`Calendar` `.month` for monthly, `.year` for yearly) repeatedly until it is
strictly in the future; otherwise return it unchanged. This keeps
"renews in X days" always correct and positive without the user re-entering the
date after a charge passes.

- Pure: takes `now` and `calendar` as parameters (no hidden `Date()` /
  `Calendar.current`) so tests are deterministic.
- The computed forward date is used for **display only**. Whether we also
  persist the rolled-forward date back to the record is an implementation
  detail to decide in the plan; display correctness does not depend on it.

### Countdown display

- `< 0 days` (shouldn't occur post-roll-forward): treat as "due".
- Within **7 days**: amber tint on the countdown text.
- Otherwise: secondary tint.
- Copy: `renews in N days`, `renews tomorrow`, `renews today`.

## UI

### Subscription row (`AppDetailView`)

A new utility row placed **directly below the License Key row**, following the
exact hover-reveal pattern just shipped in 1.2.1:

- **Chip:** 💳 `creditcard` SF Symbol, green tint (distinct from License Key's
  indigo and App Link's blue).
- **Label:** `Subscription`.
- **Empty state:** `None yet` placeholder (tertiary), hover reveals a `+`
  (`plus.circle`) button that opens the sheet.
- **Filled state:** primary line shows `€9.99 / mo · renews in 12 days`
  (formatted price + cycle abbreviation + countdown, countdown amber within 7
  days); optional second line shows the billing email (secondary, truncated
  middle) — mirroring how License Key shows its email.
- **Hover controls:** pencil (edit → opens sheet) and trash (clear → resets all
  subscription fields and `hasSubscription = false`). Borderless, secondary,
  `.opacity(hovered ? 1 : 0)` like the sibling rows.
- **No Touch ID.**

Price formatting uses `Decimal`/`NumberFormatter` currency style with the stored
currency code. Cycle renders as `/ mo` or `/ yr`.

### Subscription sheet (`SubscriptionSheet`)

Mirrors `DetailLicenseKeySheet`: a 400-wide `VStack`, headline
`Subscription for <appName>`, a short caption, then:

- **Amount + currency:** a number field (`TextField`, decimal) and a compact
  currency `Picker` on one line; currency defaults to the locale currency.
- **Cycle:** a segmented `Picker` — Monthly / Yearly.
- **Renewal:** a `DatePicker` (`.datePickerStyle(.graphical)` or `.field`,
  date components only).
- **Email:** optional `TextField`, pre-filled from `licenseEmail` / default
  license email when empty.
- **Buttons:** Cancel (esc) · Clear · Save (⌘↩, prominent), matching the
  existing sheets.

Saving sets `hasSubscription = true` and persists the fields; Clear resets them
and sets `hasSubscription = false`.

## Context Menu

The existing "Mark as Subscription" / "Unmark Subscription" context-menu action
is preserved as the zero-detail quick toggle. Marking sets `hasSubscription =
true` with no details; the detail row is where details are added. Unmarking /
clearing resets the detail fields too.

## CSV Export

The existing single `Subscription` boolean column expands to a small group:

- `Subscription` (Yes/No — unchanged position/meaning)
- `Sub Price` (amount, blank if unset)
- `Sub Cycle` (`monthly` / `yearly`, blank if unset)
- `Sub Renewal` (ISO date, blank if unset)

The billing **email is intentionally excluded** from CSV, consistent with how
license emails are kept out of exports.

## Testing

- **Roll-forward unit tests** (the core logic): past monthly date rolls to the
  next future month; past yearly date rolls to the next future year; a future
  date is returned unchanged; a date exactly today/now boundary behaves as
  specified; multi-period gaps (e.g. a renewal 5 months stale) roll forward the
  correct number of steps. Deterministic via injected `now` + `calendar`.
- **Countdown formatting tests:** N days / tomorrow / today / amber threshold
  at the 7-day boundary.
- **CSV tests:** new columns present, correct values for set/unset cases, email
  absent.
- **Model migration sanity:** existing records load with nil subscription
  fields and `hasSubscription` preserved.
- Existing suite (57 tests) stays green.

## Affected Files

- `Sources/AppAudit/Models/AppRecord.swift` — new fields + initializer defaults.
- `Sources/AppAudit/Views/AppDetailView.swift` — new `subscriptionSection` row +
  `SubscriptionSheet` + state/bindings; `BillingCycle` enum + roll-forward +
  countdown helpers (location TBD in plan — possibly a small dedicated file to
  avoid growing the view further).
- `Sources/AppAudit/ViewModels/AppListViewModel.swift` — CSV header/row
  expansion; any subscription persistence helpers.
- Tests — new test file(s) for roll-forward, countdown, CSV.

`AppDetailView.swift` is already large; the plan should consider extracting the
billing-cycle/roll-forward/countdown helpers into their own file rather than
piling more into the view.

## Future (post-v1)

- System notifications a few days before renewal.
- "Total monthly/yearly spend" summary and a dedicated subscriptions
  filter/list (the roadmap's "💳 → its own list").

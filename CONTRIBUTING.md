<!--
Contributing — PER PROJECT. From TAMPLATES/4-github/contributing.
Style: no emojis. Monochrome.
-->

# Contributing to Sift

Sift is a personal tool that happens to be open source, maintained by one
person. Bug reports and ideas are genuinely welcome; large unsolicited pull
requests are likely to sit, so open an issue first and we can agree on the shape
before you write anything.

## Getting set up

**[docs/environment.md](docs/environment.md)** takes a fresh machine to a running
build. The short version:

```bash
swift build && swift test
bash Scripts/package_app.sh && open Sift.app
```

Use `bash Scripts/build_sift2.sh` to test against a side-build. It carries its
own bundle ID, so its database and Keychain are isolated — it can never read or
prompt for your real licence keys. Do your poking there.

## Reporting a bug

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md). The two
details that matter most, and that reports usually omit:

- **Where the app came from** — Mac App Store, direct download, or Homebrew. Store apps are owned by root and behave differently; that has been the root cause of more than one bug.
- **The reason text on the row**, if it's an uninstall failure. The sweep prints why an item was refused, and that line is the diagnosis.

Never paste a real licence key. A redacted example is always enough.

## Security

Not through issues — see [SECURITY.md](SECURITY.md) for private reporting.

## The house style

Read a few files before writing; the codebase is consistent and it's easier to
match than to describe. The load-bearing conventions:

- **Pure rules live in `Models/`** as plain enums and structs, free of SwiftUI, so they can be unit tested without a view. `MoneyCubeState`, `AppFacts`, `VaultLink`, `LicenseDraftRules`, `UninstallRules` are the pattern. If your change has a decision in it, that decision belongs there and not inside a `body`.
- **Views are dumb.** State arrives as values and bindings; changes leave as callbacks.
- **Comments explain why, never what.** A comment that restates the code will be removed. A comment that records the constraint that forced the code is the one worth writing.
- No emojis in code, comments, docs, or commit messages.

## Tests

`swift test` must pass. New behaviour with a decision in it needs a test — the
pure models exist precisely so this is cheap. As of 1.8.0 there are 133 tests
across 35 suites; that number should go up.

## Commits and pull requests

- Subject line in the imperative, prefixed with its kind: `fix:`, `feat:`, `polish:`, `docs:`, `release:`.
- The body explains the problem, not the diff. The diff is already in the diff.
- Fill in the [pull request template](.github/pull_request_template.md), including how you verified it in the app and not only in tests.
- Anything that changes a permission, a data path, or where licence data lives also needs a line in [CHANGELOG.md](CHANGELOG.md) under `[Unreleased]` — and, if it's a real architectural fork, a record in [docs/decisions/](docs/decisions/).

## What Sift will not do

Worth knowing before proposing a feature:

- **Nothing leaves the machine by default.** Any feature that requires a network call has to work, or degrade honestly, with the local provider.
- **Nothing is deleted.** The uninstall sweep moves to the Trash and always will.
- **No telemetry, no accounts, no Sift-operated server.**
- **No guessing.** Analysis is grounded in real evidence; a bundled catalogue of "known apps" was deliberately removed in 1.3.3 and is not coming back.

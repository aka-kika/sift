<!--
Decision Record (ADR) — PER PROJECT
Keep in the repo, e.g. docs/decisions/NNNN-slug.md. One file per decision.
Number them in order (0001, 0002, ...). Once Accepted, treat as immutable — to
change a decision, write a new record that supersedes this one.
Style: no emojis. Monochrome. SF Symbol names noted in comments, not rendered.
-->

# 0004. The Finder handoff runs off the main thread, with a timeout

**Date:** 2026-10-20 · **Status:** Accepted · **Amends:** [0003](0003-finder-does-privileged-trash-moves.md) (its "main-thread only" cost; the decision to hand privileged moves to Finder stands)

## Context

<!-- SF Symbol: doc.text -->
0003 sent Finder its delete request through `NSAppleScript`, which must run on
the main thread. While macOS showed the "Sift wants to control Finder" prompt or
Finder's own password prompt, the whole window froze (review finding 6dc1,
2026-10-20). And the shipped 1.12.3 build lacked the Apple Events entitlement,
so the hardened runtime refused the event outright (finding 45c4).

## Decision

<!-- SF Symbol: checkmark.circle -->
Build the same Apple Event (Finder `delete`, the file URL as direct object) with
`NSAppleEventDescriptor` and send it from a background thread with a 30-second
reply timeout, plus a 35-second backstop in case sending itself waits on the
consent prompt. The release build carries `com.apple.security.automation.apple-events`.
The result is still checked against the disk. A timeout is reported in plain words,
and a bundle that times out stops the sweep like any bundle failure.

## Consequences

<!-- SF Symbol: arrow.right.circle -->
- **Good:** the uninstall sheet keeps its progress and stays responsive while macOS asks.
- **Cost:** if the user approves a Finder prompt after the 30 seconds, the item may still reach the Trash after Sift reported it as not moved. The message says so.

## References

<!-- SF Symbol: link -->
- `Sources/AppAudit/Services/TrashService.swift`
- `Sources/AppAudit/AppAudit.entitlements`
- `Tests/AppAuditTests` — "Trash Service" and "Finder handoff does not block the window" suites
- Release: `docs/releases/1.12.4.md`

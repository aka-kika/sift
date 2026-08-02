<!--
Decision Record (ADR) — PER PROJECT
Keep in the repo, e.g. docs/decisions/NNNN-slug.md. One file per decision.
Number them in order (0001, 0002, ...). Once Accepted, treat as immutable — to
change a decision, write a new record that supersedes this one.
Style: no emojis. Monochrome. SF Symbol names noted in comments, not rendered.
-->

# 0003. Finder performs privileged trash moves

**Date:** 2026-08-02 · **Status:** Accepted

## Context

<!-- SF Symbol: doc.text -->
The uninstall sweep moves an app bundle and its leftovers to the Trash with
`FileManager.trashItem`, which renames the item into `~/.Trash`. POSIX requires
write permission on the **directory being renamed**, not merely on its parent,
because the rename rewrites that directory's `..` entry.

A Mac App Store bundle is installed `drwxr-xr-x root:wheel`. The user is in
`admin` and `/Applications` is `drwxrwxr-x root:admin`, so the parent is
writable — but the bundle itself is not. Every store-bought app therefore failed
with `NSCocoaErrorDomain 513` (underlying OSStatus −5000), while apps the user
dragged in themselves (`kika_hub:staff`) succeeded. The failure was total and
silent: the catch block recorded the path and discarded the error, so the sweep
reported "could not be moved" with no reason for anyone to act on.

Sift is not sandboxed and does scan and modify user-level files, so the question
is not whether it may touch these paths but which mechanism should carry out a
move the calling user is entitled to make but the API refuses.

## Options considered

<!-- SF Symbol: arrow.triangle.branch -->
- **Report and stop** — detect the permission refusal, explain it, offer Reveal in Finder and let the user drag the app out themselves. Honest and zero new permissions, but it leaves the headline feature broken for an entire class of apps, which is most of what gets bought.
- **Escalate privileges in-process** — a privileged helper tool or `AuthorizationExecuteWithPrivileges` to perform the move as root. Works for every case, but it means Sift handles an authorization session and ships a setuid-shaped component, for a feature whose whole promise is "recoverable, nothing scary".
- **`NSWorkspace.recycle`** — the sanctioned AppKit recycling call, in the hope it escalates where `FileManager` will not. Probed and it neither moved the item nor reported an error on a non-writable directory; no better than option one.
- **Hand the item to Finder** — send an Apple Event asking Finder to delete it. Finder owns the privileged path and raises its own authorization prompt when one is genuinely required.

## Decision

<!-- SF Symbol: checkmark.circle -->
Try `FileManager.trashItem` first, and on a **permission** refusal specifically
(`NSFileWriteNoPermissionError`, `NSFileReadNoPermissionError`,
`NSFileWriteVolumeReadOnlyError`) hand the item to Finder via Apple Event.
Anything else fails with its real reason attached.

Two reasons decided it. Finder already is the trusted path for exactly this move
— dragging a store app to the Trash is the thing every Mac user does — so the
authorization UI is the system's own and no password ever passes through Sift.
And the fast, silent path stays the default: the Apple Event only fires for the
minority of items that genuinely need it.

The result is verified against the disk rather than the script's reply, since
AppleScript can report success and leave the item in place.

## Consequences

<!-- SF Symbol: arrow.right.circle -->
- **Good:** uninstall works on every app the user can remove in Finder, with no privileged helper, no setuid component, and no credential handling in Sift. Failures that remain carry a real reason and a Show in Finder button.
- **Cost:** a new `NSAppleEventsUsageDescription` entitlement, and a one-time macOS Automation consent prompt ("Sift wants to control Finder") on the first store-app uninstall. Consent is keyed to the code signature, so ad-hoc local builds re-prompt after every rebuild. The fallback is also main-thread only — `NSAppleScript` is not thread-safe — so it cannot be batched off the main actor the way the `FileManager` attempt is.
- **Follow-ups:** if Apple ever restricts Automation further, revisit against option one (report and stop) rather than option two (privilege escalation) — the trade that made this acceptable is that Sift gains no new power of its own.

## References

<!-- SF Symbol: link -->
- `Sources/AppAudit/Services/TrashService.swift` — the two-step implementation
- `Sources/AppAudit/Views/UninstallSheet.swift` — failure reporting
- `Tests/AppAuditTests` — "Trash Service" suite (error classification, script escaping)
- Release: [v1.8.0](https://github.com/aka-kika/sift/releases/tag/v1.8.0) · record in `docs/releases/1.8.0.md`
- Related: [0001 — keep bundle ID across the Sift rename](0001-keep-bundle-id-across-sift-rename.md)

# Sift review fixes, 24 Oct 2026

Branch `review-fixes-2026-10-24`, from `main` at `02f76be`. Backup branch `backup/main-2026-10-24` points at that same commit. Nothing was pushed, merged, tagged, released, or installed. Sift was not opened on this Mac.

`swift test` at the end: 374 tests in 121 suites, all passed.

## Commits

`git log --oneline main..HEAD`

```
4fac072 fix: send a cloud API key only over https, or to this Mac
58ee10d fix: forget a revealed licence key when the panel closes
6afce62 fix: show What's New when an existing library has never seen the sheet
bb70379 fix: send a project excerpt only while the app is marked My App
e161d3e fix: compare app copies without resolving symlinks
074866b fix: do not offer a Sparkle beta when every feed item is on a channel
7e77023 fix: never claim CloudDocs, MobileSync or AppAudit by name
9a7eac9 fix: name an app from its display name, executable or file name
f7c9ec2 fix: require a colon on analysis labels and keep the following lines
b2f677f docs: match the signing identity and the supported version to 1.12.4
a2f81f4 docs: stop calling licence keys device-bound
541563c fix: make Cmd-R refresh updates when the list is sorted by Updates
8a8d239 fix: treat a Homebrew comma as a version separator
197e004 fix: unload a Launch Agent before moving its plist to the Trash
f6f15da fix: a bundle-id folder is not an app bundle for Finder
2d779aa fix: ask Finder only when the app bundle itself cannot be moved
3c64ebd fix: ignore bundle IDs with fewer than three parts
994d010 fix: let Lifetime, Free and My App outrank a leftover subscription
04c06e7 docs: move a damaged store to the Desktop instead of deleting it
a3b5146 fix: skip an App Store release this Mac cannot run
d5a3f4e fix: compare a Sparkle build-only item with the app's build
18b6d8b fix: stop hiding Microsoft Edge Canary as an Apple system app
d9c0ea5 fix: offer Done after brew uninstall when nothing else is checked
485d272 fix: disable Rescan and Re-analyze while an analysis is running
fe8ed70 fix: keep the sidebar list on screen during a rescan
fda7336 docs: a subscription renewal date is stored only when you pick one
c7c8b55 fix: send app paths with a tilde so cloud prompts hide the account name
9364a4f fix: leave a subscription renewal empty until the user picks a date
420b1e0 fix: list subscriptions in the License Vault
d05d2fb fix: clear a licence flag only when the Keychain says the item is missing
a523543 fix: skip the saved-link fetch when update checks are off
4e1d2f5 fix: ask for Touch ID before Replace on a saved licence key
f94df1e fix: say brew uninstall removes the app, it is not in the Trash
```

Two of those are follow-ups on an item already closed: `f6f15da` corrects the Finder check so a folder named `com.example.app` is not treated as an app bundle, and `fda7336` is the renewal-date sentence that belonged with `9364a4f`.

## Closed

31 of the original 41. Runway "done today" matches that.

## Left on purpose

- **602c** Data-only sweep. Unchecking the app and sweeping its data is what the existing tests call intended. The card offers two product choices (warn on the sheet, or ask first), and either one changes what gets deleted. Left open for Kika.

## Still open from the original card

These were not finished. They are still real fixes, not product calls.

- **c4b8** Run Update can brew-upgrade a cask matched only by name, and a failed brew can still read as finished. Needs `caskOwnsBundle` and brew's exit status.
- **b503** Quit & Continue looks once after 1 second, and the sweep does not check again before moving.
- **b0a1** A locked app with no analysis stays on "Waiting to analyze", and the lock blocks Re-analyze.
- **e623** Update and link clients follow redirects without checking https or a public host again.
- **568a** The local-link guard checks the name only, not the address it points at.
- **16cc** A failed save is hidden by `try?`, so it looks saved.
- **89a7** Switching engine while models load can save the old model under the new one. `llama3.2` and `llama3.2:latest` can leave the picker blank.
- **3353** Notes save on every key. Escape keeps the edit and starts a re-analysis.
- **b7b6** Brew commands have no time limit.

## New items that appeared during the session

These were not in the 41. They are still open. Not done here.

- **adbd** The cloud API key field writes to the Keychain on every key press.
- **4b7e** A failed or missing brew check can read as Up to date.
- **36eb** A saved analysis is kept after the app's version changes, with no hint.
- **84ce** A Sparkle item with no https enclosure falls back to the feed URL.
- **b3ae** Every app with a version shows Checking, including apps with no update source.
- **49f5** README says Touch ID only. The check also takes the account password.
- **9a6f** Quitting within a minute of copying a key can leave it on the clipboard.
- **1000** A denied Finder Automation prompt does not name the Automation setting.

## What needs a VM check

Nothing here was clicked in the app. A test VM should walk:

- Homebrew uninstall: the finished line says removed by Homebrew, not in the Trash. With nothing else checked, Done removes the app from the sidebar. The brew button stays disabled while brew runs.
- Replace on a saved licence key asks for Touch ID. A cancelled prompt does not open the field.
- Closing the licence panel forgets a revealed key. Reveal still works after the Touch ID prompt.
- A rescan keeps the sidebar list. The first scan, with no apps yet, still shows the spinner.
- Rescan and Re-analyze are disabled while an analysis runs, and the help text says why.
- Mark Subscribed does not store today. Set renewal date is a separate button.
- A subscription with no key shows in the License Vault.
- Microsoft Edge Canary shows in the list.
- Cmd-R in the Updates sort refreshes updates. In any other sort it rescans.
- What's New appears for a library that already has records and has never stored a last-seen version.

## Not done

No push, no merge, no tag, no release, no install.

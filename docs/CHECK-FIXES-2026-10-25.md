# Sift check fixes, 25 Oct 2026

Branch `check-fixes-2026-10-25`, from `review-fixes-2026-10-24` at `c4e0c36`. One commit and test per item. Nothing was pushed, merged, tagged, released or installed. Sift was not opened on Kika's Mac; app checks ran in the test VM (vm1).

## Second check: should fix

| Item | Commit | What changed |
| --- | --- | --- |
| 1 · 485d272 reanalyze dropped during a scan | 5ba4c3c | A link, note or docs change saved during a scan is queued (newest link wins) and analyzed when the scan ends. |
| 2 · f6f15da / 2d779aa dotted app names | 4ccabbb | The sweep passes the scanner's `isAppBundle` to `TrashService`; `isAppBundlePath` is gone. Checked in the VM with a root-owned `dot.test.app`. |
| 3 · 6658902 brew warnings break the JSON | fbb0a19 | `brew outdated` reads stdout alone; JSON that does not decode is `.failed`. |
| 4 · 8a8d239 `1.3.0,999` fake update | 95c3604 | The part after the comma only breaks a tie with `CFBundleVersion`; no build means equal. |
| 5 · 4fac072 any `.local` is this Mac | 3555b82 | Only localhost, loopback and this Mac's own Bonjour name may get http. |
| 6 · 7ff5264 API key lost on close | 9770939 | The tab commits on disappear; Remove Key added. |

## Second check: small

| Item | Commit |
| --- | --- |
| 58ee10d Copy's prompt wipes a revealed key; a typed first key is lost on close | dd3f2b6 |
| f7c9ec2 closing chatter in Best use | 8f66016 |
| a523543 manual Re-analyze skips the link page with checks off | b767145 |
| 197e004 `try? process.run()` then wait | 339f291 |
| d5a3f4e "Update to 1.5.1 (1.5.2)" | faad03a |

## Runway leftovers (all closed)

| Id | Commit | What changed |
| --- | --- | --- |
| 602c | b558209, 64f0aae | Kika's option B: "The app stays installed. Delete only its data?" with Cancel as the default. Return and Escape both cancel (found and fixed in the VM). |
| c4b8 | c6e3fd6 | Run Update checks `caskOwnsBundle` and brew's exit status. |
| b503 | b07a3e6 | Quit & Continue polls up to 10 s; the sweep re-checks running state first. |
| b0a1 | 8457a18 | A lock with no analysis says so and offers Unlock and Analyze. |
| e623 | 34f66a1 | Feed and lookup redirects must stay on https and a public host. |
| 568a | 91cab81 | A saved link's address is resolved first; every address must be public. |
| 16cc | 0165145, b8d2b99 | `saveReportingFailure` replaces `try? save()`; a banner shows a failed save. |
| 89a7 | d9dad5e | A model list fetched for another engine is dropped; the picker maps `x` to `x:latest`. |
| 3353 | b4e5ed6 | The Notes sheet edits a draft; Save stores it, Cancel and Escape change nothing. |
| b7b6 | 39e547a | brew runs through `TimedProcess` with a deadline (2 min checks, 10 min uninstall, 30 min upgrade). |

## Tests

- b988b27: the vault test fetches from an in-memory store with the vault's own predicate (`VaultMembership.predicate`, now used by the `@Query`). Source-text tests and README-wording tests are removed; SECURITY.md is checked against `version.env`.
- `swift test`: 431 tests in 144 suites pass.

## Test VM (vm1, macOS 26.6.2)

- Homebrew: Itsycal made to look outdated; the sidebar showed Brew 0.15.15, Run Update upgraded it for real and said "Homebrew finished".
- Uninstall: data-only question shown with Kika's wording; Return and Escape cancel and the data stays; Delete Data Only moves only the data. A root-owned `dot.test.app` went to the Trash through Finder.
- Slow Finder prompt (Kika's option B): a move Finder finishes after the 30 s wait now reads as moved. The result screen re-checks every 2 s while open and again on Done. Checked in the VM: password entered after 45 s, the screen switched to "reached the Trash after Sift stopped waiting" and Done removed the row.

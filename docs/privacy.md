<!--
Privacy & Permissions — PER PROJECT. From TAMPLATES/2-repo-docs/privacy-permissions.
Mirror the user-facing parts into the public privacy policy URL.
Only claim what is actually true of the shipping build.
Style: no emojis. Monochrome. SF Symbol names noted in comments, not rendered.
-->

# Sift — Privacy & Permissions

**Updated:** 2026-08-27 · **Version:** 1.10.0

## In one line

<!-- SF Symbol: hand.raised -->
Everything stays on your Mac. Sift collects nothing, has no analytics, no
accounts, and no servers of its own — the only bytes that ever leave are the ones
you opt into by choosing a cloud model or by Sift fetching the public page of an
app you linked.

## Data the app handles

<!-- SF Symbol: externaldrive -->
| Data | Why | Where it lives | Leaves device? |
|---|---|---|---|
| Installed-app inventory (name, bundle ID, version, path, category, last-used date) | The audit itself | SwiftData store in `~/Library/Application Support/` | No |
| AI analysis (explanation, score, reason, best use) | The recommendation | Same local store | No |
| Your notes and custom descriptions | Feed the analysis as evidence | Same local store | Only if you pick a cloud provider (see Network) |
| Licence keys | The License Vault | **macOS Keychain**, service keyed to the bundle ID — never the SwiftData store | No |
| Licence type, registered email, subscription price / cycle / renewal / billing email | Cost tracking | Local store | No |
| App icons (PNG) | Vault rows survive uninstalling the app | Local store | No |
| Attached project folder contents (README, manifests) for apps you mark as yours | Grounds the analysis in real evidence | Read at analysis time, not copied | Only if you pick a cloud provider |
| CSV export | Your own reporting | Wherever you save it | Only if you move it |

Records outlive the app they describe: uninstalling an app keeps its licence and
notes, which is the point of the vault. Nothing is uploaded as a consequence.

## Permissions requested

<!-- SF Symbol: lock.shield -->
| Permission | When | What it's for |
|---|---|---|
| **Automation → Finder** (`NSAppleEventsUsageDescription`) | First uninstall of an app Sift cannot move itself | Mac App Store bundles are owned by root, and macOS refuses the move to any process but Finder. Sift asks Finder to do it. No password passes through Sift; any authorization prompt is macOS's own. See `docs/decisions/0003-finder-does-privileged-trash-moves.md`. |
| **Touch ID / local authentication** | Revealing or copying a licence key | Keeps a shoulder-surfer from reading a key out of an unlocked Mac. Failing it simply cancels. |
| **Keychain access** | Saving or reading a licence key | Standard per-app Keychain items; other apps cannot read them. |
| **Network client** | Analysis with a cloud provider, update checks, fetching a linked app's page | See Network. |

Sift is **not sandboxed**, because auditing installed apps means reading
`/Applications`, `~/Applications`, and the user-level Library folders directly.
It reads app metadata and, during an uninstall sweep, moves the items you tick to
the Trash. It never writes into another app's data, and it never deletes: every
sweep is a Trash move you can undo. Apple system apps (`com.apple.*`) and Sift
itself are refused outright.

## Network

<!-- SF Symbol: network -->
Apart from its own daily update check, Sift makes no network connections in its
default configuration.

- **Analysis** runs on **local Ollama** by default — prompts never leave the Mac. If you switch the provider to Anthropic, OpenAI, Google Gemini or OpenRouter in Settings, the prompt (app metadata, your notes, fetched link evidence, attached docs evidence) goes to that provider under your own API key and their terms. That switch is yours to make and yours to undo.
- **Update checks** contact the Mac App Store lookup endpoint and, for apps that publish one, their Sparkle feed. Homebrew checks run the local `brew` binary.
- **Sift's own updates** (since 1.9.0) — Sparkle fetches `sift.akakika.com/appcast.xml` once a day and downloads the DMG only when you accept an update. The feed is a static file; nothing about you or your Mac is sent with the request.
- **Link evidence** fetches the public page of an app link you saved, to ground the analysis in what the maker actually says.
- **About tab links** open in your browser when you click them; nothing is requested in the background.

## Third-party services

<!-- SF Symbol: shippingbox -->
None. No analytics, no telemetry, no crash reporting, no accounts, no
Sift-operated server exists beyond the static site that hosts the update feed.
Anthropic, OpenAI, Google Gemini and OpenRouter are optional providers you
configure yourself; Apple and Homebrew are contacted only for update metadata.

## Your controls

<!-- SF Symbol: slider.horizontal.3 -->
- **Revoke Automation:** System Settings → Privacy & Security → Automation → Sift. Uninstall then reports what it cannot move rather than handing it to Finder.
- **Stay fully offline:** keep the provider on Ollama; that is the default.
- **Remove a licence key:** the trash button in the License popover or the vault row deletes the Keychain item.
- **Remove a purchase record:** the vault row's trash clears the Paid mark and the licence type.
- **Delete everything:** quit Sift, then remove its Application Support folder and its Keychain items. Uninstalling Sift alone leaves both behind on purpose, so a reinstall keeps your vault.
- **Export:** File → Export to CSV writes the audit wherever you choose.

## Contact

<!-- SF Symbol: envelope -->
Questions about privacy: [akakika.com](https://akakika.com) · [@akakikaaa](https://x.com/akakikaaa)

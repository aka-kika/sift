<!--
Privacy & Permissions — PER PROJECT. From TAMPLATES/2-repo-docs/privacy-permissions.
Mirror the user-facing parts into the public privacy policy URL.
Only claim what is actually true of the shipping build.
Style: no emojis. Monochrome. SF Symbol names noted in comments, not rendered.
-->

# Sift — Privacy & Permissions

**Updated:** 2026-10-20 · **Version:** 1.12.4

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
| Licence keys | The License Vault | **macOS login keychain**, service `com.kikaapp.appaudit.licensekeys`, this device only, never iCloud-synced — never the SwiftData store | No |
| Cloud API keys (Anthropic, OpenAI, Gemini, OpenRouter, ollama.com) | Optional cloud analysis | **macOS login keychain**, service `com.kikaapp.appaudit.apikeys`, one item per provider. Builds up to 1.12.3 kept them in the preferences file; Sift moves them on first launch and removes the old copy only once the Keychain holds the key | Only to the provider it belongs to, with each request |
| Licence type, registered email, subscription price / cycle / renewal / billing email | Cost tracking | Local store | No |
| App icons (PNG) | Vault rows survive uninstalling the app | Local store | No |
| Attached project folder contents (README, manifests) for apps you mark as yours | Grounds the analysis in real evidence | Read when you attach or refresh the folder; a short excerpt is kept in the local store and reused by each analysis. Detaching the folder removes it | Only if you pick a cloud provider |
| CSV export | Your own reporting | Wherever you save it | Only if you move it |

Records outlive the app they describe: uninstalling an app keeps its licence and
notes, which is the point of the vault. Nothing is uploaded as a consequence.

## Permissions requested

<!-- SF Symbol: lock.shield -->
| Permission | When | What it's for |
|---|---|---|
| **Automation → Finder** (`NSAppleEventsUsageDescription`) | First uninstall of an app Sift cannot move itself | Mac App Store bundles are owned by root, and macOS refuses the move to any process but Finder. Sift asks Finder to do it. No password passes through Sift; any authorization prompt is macOS's own. See `docs/decisions/0003-finder-does-privileged-trash-moves.md`. |
| **Touch ID / local authentication** | Revealing, copying, or removing a licence key | Keeps a shoulder-surfer from reading a key out of an unlocked Mac. Failing it simply cancels. A copied key is marked concealed and transient, so clipboard managers skip it, and Sift clears it after a minute if it is still on the clipboard. |
| **Keychain access** | Saving a licence key, reading one after Touch ID, and reading a cloud API key when it calls that provider | Standard login-keychain items. The item trusts Sift; another app asking for it gets a macOS prompt asking for your approval first. Touch ID is Sift's own check before it reads, copies, reveals or removes a licence key — it is not a lock on the Keychain item itself (a Developer ID app without a provisioning profile cannot put one there). At launch, in the sidebar and in the vault, Sift only checks whether a key exists, without reading it; it reads a licence key only after Touch ID, or once when it moves an old key out of its database. If the Keychain refuses a save, Sift says so and keeps the key in the field. |
| **Network client** | Analysis with a cloud provider, update checks, fetching a linked app's page | See Network. |

Sift is **not sandboxed**, because auditing installed apps means reading
`/Applications`, `~/Applications`, and the user-level Library folders directly.
It reads app metadata and, during an uninstall sweep, moves the items you tick to
the Trash. Before a sweep it asks Spotlight, on this Mac, for other copies of the
same app, so data another copy still uses is not pre-checked. If the app itself
cannot be moved, the sweep stops and nothing else is touched. It never writes into another app's data. A sweep moves files to the Trash, which you can undo. `brew uninstall` removes the app for good; that copy is not in the Trash. Apple system apps (`com.apple.*`) and Sift
itself are refused outright.

## Network

<!-- SF Symbol: network -->
In its default configuration Sift connects to: its own update feed (daily), and,
on each scan, the Mac App Store lookup, the update feeds of apps that publish one,
and GitHub releases for apps linked to GitHub. Settings → General → Updates turns
the scan checks off; then a scan makes no network requests, and the sidebar's
refresh button checks only when you click it.

- **Analysis** runs on **local Ollama** by default — prompts never leave the Mac. If you switch the provider to Anthropic, OpenAI, Google Gemini or OpenRouter in Settings, the prompt (that app's metadata, your notes, fetched link evidence, attached docs evidence, and your workflow profile) goes to that provider under your own API key and their terms. The automatic workflow profile sent to a cloud provider has only the number of apps and their top categories — no app names. With local Ollama it also names your recently used and open apps. That switch is yours to make and yours to undo.
- **Find similar apps** has to show the model your other installed apps (name, category, short description) to pick from. With a cloud provider, Sift asks before every such request; with local Ollama nothing leaves the Mac.
- **Update checks** contact the Mac App Store lookup endpoint and, for apps that publish one, their Sparkle feed or GitHub releases, over https only. Each request names only the app being checked. Homebrew checks run the local `brew` binary with Homebrew's auto-update turned off, so a check never runs `brew update`; Homebrew reaches the network only when you click an upgrade. You can turn the checks off in Settings → General → Updates.
- **Sift's own updates** (since 1.9.0) — Sparkle fetches `sift.akakika.com/appcast.xml` once a day and downloads the DMG only when you accept an update. The feed is a static file; nothing about you or your Mac is sent with the request.
- **Link evidence** fetches the public page of an app link you saved, to ground the analysis in what the maker actually says. Links to this Mac or your local network are never fetched, redirects to them are refused, and the query and fragment are removed before fetching and before the link goes into a prompt.
- **About tab links** open in your browser when you click them; nothing is requested in the background.

## Third-party services

<!-- SF Symbol: shippingbox -->
None. No analytics, no telemetry, no crash reporting, no accounts, no
Sift-operated server exists beyond the static site that hosts the update feed.
Anthropic, OpenAI, Google Gemini and OpenRouter are optional providers you
configure yourself; Apple and GitHub are contacted only for update metadata, and Homebrew only when you run an upgrade.

## Your controls

<!-- SF Symbol: slider.horizontal.3 -->
- **Revoke Automation:** System Settings → Privacy & Security → Automation → Sift. Uninstall then reports what it cannot move rather than handing it to Finder.
- **Stay fully offline:** keep the provider on Ollama (the default) and turn off Settings → General → Updates → "Check apps for updates on every scan".
- **Remove a licence key:** the trash button in the License popover or the vault row deletes the Keychain item, after Touch ID.
- **Remove a purchase record:** the vault row's trash clears the Paid mark and the licence type.
- **Delete everything:** quit Sift, then remove its Application Support folder and its Keychain items (services `com.kikaapp.appaudit.licensekeys` and `com.kikaapp.appaudit.apikeys`, in Keychain Access). Uninstalling Sift alone leaves both behind on purpose, so a reinstall keeps your vault.
- **A damaged library:** if Sift's database file is damaged, Sift moves it aside (never deletes it), starts fresh, and tells you the file's name. If the file is intact but cannot be opened (for example, a newer Sift wrote it), Sift leaves it alone and says so.
- **Export:** File → Export to CSV writes the audit wherever you choose.

## Contact

<!-- SF Symbol: envelope -->
Questions about privacy: [akakika.com](https://akakika.com) · [@akakikaaa](https://x.com/akakikaaa)

<!--
Environment Setup — PER PROJECT. From TAMPLATES/2-repo-docs/environment-setup.
Written so a fresh machine can go from zero to running without asking anyone.
Update it when dependencies change.
Style: no emojis. Monochrome. SF Symbol names noted in comments, not rendered.
-->

<!-- SF Symbol: macbook.and.iphone -->
# Environment Setup

Project: Sift
Last tested on: macOS 27.0 (26A5388g), Apple Silicon — 2026-08-02

---

<!-- SF Symbol: gearshape -->
## Prerequisites

- **Xcode 27 beta** (or its toolchain) — the standalone Command Line Tools' SwiftPM is broken on macOS 27 (missing `BuildServerProtocol.framework`)
- **Swift 5.9+**, via that toolchain
- **macOS 14.0+** to run the app (`LSMinimumSystemVersion`)
- **Ollama** running locally with a pulled model — the default analysis provider. Without it the app runs and scans; the analysis panel reports the provider is unavailable
- **create-dmg** (Homebrew) — only for `Scripts/make_dmg.sh`
- **Developer ID Application certificate** + a `notarytool` keychain profile — only for release builds
- **rsvg-convert** (Homebrew `librsvg`) — only if regenerating the About tab's brand marks

If the toolchain is not already selected:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```

---

<!-- SF Symbol: arrow.down.to.line.compact -->
## Installation

No package dependencies — the target is pure SwiftPM with system frameworks
only. Cloning is the install.

```bash
git clone https://github.com/aka-kika/sift.git && cd sift
```

---

<!-- SF Symbol: hammer -->
## Build

```bash
swift build && swift test
```

Bundle a runnable, ad-hoc-signed `Sift.app` in the repo root:

```bash
bash Scripts/package_app.sh
```

---

<!-- SF Symbol: play -->
## Run

```bash
open Sift.app
```

To iterate without touching your real data, build the **Sift2 side-build**. It
carries its own bundle ID (`com.kikaapp.sift2`), so its SwiftData store and
Keychain service are separate — it can never read or prompt for the primary
app's licence keys:

```bash
bash Scripts/build_sift2.sh   # installs /Applications/Sift2.app
```

---

<!-- SF Symbol: checkmark.circle -->
## Verify it works

- The sidebar fills with your installed apps and analysis begins ("Analyzing n/N" in the toolbar).
- Selecting an app shows What is this?, a 1–5 score, and a facts row (on disk, last used, source, analyzed).
- `swift test` reports **133 tests in 35 suites passed** as of 1.8.0.

---

<!-- SF Symbol: key -->
## Secrets / Config

Nothing lives in the repo, and no `.env` is used.

| Secret | Where it lives | Needed for |
|---|---|---|
| Anthropic / OpenAI API key | Entered in Settings → Models, stored in the app's own store | Optional cloud analysis; Ollama is the default and needs no key |
| Licence keys | macOS Keychain, keyed to the bundle ID | The License Vault at runtime |
| Notarization credentials | Login Keychain profile `AC_PASSWORD` (`xcrun notarytool store-credentials`) | Release only |
| Developer ID certificate | Login Keychain | Release only |

---

<!-- SF Symbol: ladybug -->
## Troubleshooting

| Symptom | Fix |
|---|---|
| `swift build` fails on missing `BuildServerProtocol.framework` | The standalone CLT SwiftPM is broken on macOS 27. `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`, or `sudo xcode-select -s` it once. |
| `codesign: ... ambiguous (matches ... and ...)` | Two valid Developer ID certs share one name in the login Keychain. Pass the SHA-1 hash instead of the name: `security find-identity -v -p codesigning`, then `APP_IDENTITY=<hash>`. |
| Analysis panel says the provider is unavailable | Ollama is not running or has no model pulled. Start it, or switch provider in Settings → Models. |
| "Sift wants to control Finder" on first uninstall | Expected. It is the handoff that lets store-bought apps reach the Trash; approve once. Ad-hoc builds re-prompt after each rebuild because consent is keyed to the signature. |
| Uninstall reports "could not be moved" | Read the reason on the row. If Automation was denied, re-enable it in System Settings → Privacy & Security → Automation → Sift. |
| Brand marks missing from the About tab | The PDFs in `Resources/socials/` were not copied into the bundle; rebuild with `Scripts/package_app.sh`. Rows fall back to SF Symbols meanwhile. |

---

<!-- SF Symbol: arrow.triangle.2.circlepath -->
## Teardown / Reset

Build artifacts only:

```bash
rm -rf .build Sift.app .dmg-source Sift-*.dmg
```

Full reset of app data — this drops your audit, notes, and vault:

```bash
osascript -e 'quit app "Sift"'
rm -rf ~/Library/Application\ Support/AppAudit
# Licence keys live in the Keychain; remove the "Sift" items in Keychain Access.
```

The Sift2 side-build stores under `~/Library/Application Support/Sift2` and can
be reset independently.

# Release Checklist

This checklist prepares **Sift** for Developer ID signing and notarization.

> The product is **Sift**; the bundle identifier stays `com.kikaapp.appaudit` for
> data continuity, and Swift sources live under `Sources/AppAudit/`. The build
> artifacts are `Sift.app` and `Sift-<version>.dmg`.

## 1. Clean and Verify

```bash
rm -rf .build Sift.app .dmg-source
swift build
swift test
```

## 2. Build a Local DMG

Use this for internal testing. It is ad-hoc signed and not notarization-ready.

```bash
bash Scripts/make_dmg.sh
hdiutil verify Sift-1.10.0.dmg
```

The DMG includes a polished Finder layout, the app icon, an Applications drop link, and a custom icon on the `.dmg` file itself.

## 3. Build a Developer ID DMG

Use this before notarization.

```bash
APP_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
SIGNING_MODE=developer \
bash Scripts/make_dmg.sh
```

Confirm the app is signed with hardened runtime:

```bash
codesign --verify --deep --strict --verbose=2 Sift.app
codesign -dv --verbose=4 Sift.app
codesign --verify --verbose=2 Sift-1.10.0.dmg
spctl --assess --type execute --verbose=4 Sift.app
spctl --assess --type open --context context:primary-signature --verbose=4 Sift-1.10.0.dmg
hdiutil verify Sift-1.10.0.dmg
```

## 4. Notarize

Submit the DMG after Developer ID signing passes.

```bash
xcrun notarytool submit Sift-1.10.0.dmg \
  --keychain-profile "AC_PASSWORD" \
  --wait
```

Staple and verify:

```bash
xcrun stapler staple Sift-1.10.0.dmg
xcrun stapler validate Sift-1.10.0.dmg
spctl --assess --type open --verbose=4 Sift-1.10.0.dmg
```

## 5. Sparkle self-update (since 1.9.0)

Sift ships Sparkle 2 embedded at `Contents/Frameworks/Sparkle.framework`
(`Scripts/package_app.sh` copies it from the SwiftPM artifact and signs its nested
helpers before the app). `Info.plist` gets `SUFeedURL` and `SUPublicEDKey` from
`version.env`.

- **Feed:** https://sift.akakika.com/appcast.xml — generated into `site/appcast.xml`
  by `generate_appcast` from every DMG in `site/downloads/`.
- **Key:** EdDSA key pair in the login Keychain, service `https://sparkle-project.org`,
  account `Sift` (a separate account from the default one other apps use). Losing the
  private key means every installed copy stops accepting updates — back it up with
  `generate_keys --account Sift -x sift-sparkle-key.private` to a safe place, never
  into the repo.
- **Sift2** (`Scripts/build_sift2.sh`) embeds the framework but sets no feed, so the
  side-build never offers to update itself.

### One-command pipeline

```bash
bash Scripts/release.sh            # build, sign, notarize, staple, appcast, site, cask
NOTARIZE=0 bash Scripts/release.sh # local dry run
```

Then, by hand: commit + tag + push, `gh release create`, and `cd site && vercel deploy --prod --yes`.
The deploy is what makes the update visible — Sparkle reads the appcast from the site.

## 6. Publish

- Tag the release (e.g. `v1.9.0`) and attach the notarized `Sift-1.9.0.dmg` to a GitHub Release.
- Deploy `site/` so the appcast and DMG go live: `cd site && vercel deploy --prod --yes`.
- Homebrew: `release.sh` bumps `Scripts/homebrew/sift.rb`; the public tap `aka-kika/homebrew-tap` is not created yet (see `Scripts/homebrew/README.md`).
- Installing the new `Sift.app` replaces the old `AppAudit.app` (same bundle ID); existing data and license keys carry over.

## Notes

- On macOS 27, the standalone Command Line Tools' SwiftPM is broken (missing
  `BuildServerProtocol.framework`). Build via the Xcode beta toolchain instead:
  `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`
  (or `sudo xcode-select -s /Applications/Xcode-beta.app/Contents/Developer` once).
- Notarization credentials are stored in the login Keychain under the
  `AC_PASSWORD` profile (`xcrun notarytool store-credentials`).
- The login Keychain holds two valid `Developer ID Application: Veronica Loren
  (P5RB3W3D58)` certificates, so passing `APP_IDENTITY` by name fails with
  "ambiguous". Pass the SHA-1 hash instead — list them with
  `security find-identity -v -p codesigning`. Both are valid; `Scripts/release.sh`
  defaults to `APP_IDENTITY=D833417579CBB62121FD344B1513AE5D44A36762`, so use that
  one for manual builds too and the signature stays consistent across releases.

- `Scripts/package_app.sh` defaults to ad-hoc signing for local builds.
- Set `SIGNING_MODE=developer` and `APP_IDENTITY` for release signing.
- The app uses the network client entitlement for Ollama/cloud providers and App Store/Sparkle checks.
- Sandbox is disabled because Sift scans installed apps directly.
- `Scripts/build_sift2.sh` builds an isolated `Sift2` side-build for testing without touching primary data.

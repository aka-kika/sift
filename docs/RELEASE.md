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
hdiutil verify Sift-1.1.0.dmg
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
codesign --verify --verbose=2 Sift-1.1.0.dmg
spctl --assess --type execute --verbose=4 Sift.app
spctl --assess --type open --context context:primary-signature --verbose=4 Sift-1.1.0.dmg
hdiutil verify Sift-1.1.0.dmg
```

## 4. Notarize

Submit the DMG after Developer ID signing passes.

```bash
xcrun notarytool submit Sift-1.1.0.dmg \
  --keychain-profile "AC_PASSWORD" \
  --wait
```

Staple and verify:

```bash
xcrun stapler staple Sift-1.1.0.dmg
xcrun stapler validate Sift-1.1.0.dmg
spctl --assess --type open --verbose=4 Sift-1.1.0.dmg
```

## 5. Publish

- Tag the release (e.g. `v1.1.0`) and attach the notarized `Sift-1.1.0.dmg` to a GitHub Release.
- Installing the new `Sift.app` replaces the old `AppAudit.app` (same bundle ID); existing data and license keys carry over.

## Notes

- `Scripts/package_app.sh` defaults to ad-hoc signing for local builds.
- Set `SIGNING_MODE=developer` and `APP_IDENTITY` for release signing.
- The app uses the network client entitlement for Ollama/cloud providers and App Store/Sparkle checks.
- Sandbox is disabled because Sift scans installed apps directly.
- `Scripts/build_sift2.sh` builds an isolated `Sift2` side-build for testing without touching primary data.

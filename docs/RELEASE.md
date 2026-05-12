# Release Checklist

This checklist prepares AppAudit for Developer ID signing and notarization.

## 1. Clean and Verify

```bash
rm -rf .build AppAudit.app .dmg-source
swift build
swift test
```

## 2. Build a Local DMG

Use this for internal testing. It is ad-hoc signed and not notarization-ready.

```bash
bash Scripts/make_dmg.sh
hdiutil verify AppAudit-1.0.0.dmg
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
codesign --verify --deep --strict --verbose=2 AppAudit.app
codesign -dv --verbose=4 AppAudit.app
spctl --assess --type execute --verbose=4 AppAudit.app
hdiutil verify AppAudit-1.0.0.dmg
```

## 4. Notarize

Submit the DMG after Developer ID signing passes.

```bash
xcrun notarytool submit AppAudit-1.0.0.dmg \
  --keychain-profile "AC_PASSWORD" \
  --wait
```

Staple and verify:

```bash
xcrun stapler staple AppAudit-1.0.0.dmg
xcrun stapler validate AppAudit-1.0.0.dmg
spctl --assess --type open --verbose=4 AppAudit-1.0.0.dmg
```

## Notes

- `Scripts/package_app.sh` defaults to ad-hoc signing for local builds.
- Set `SIGNING_MODE=developer` and `APP_IDENTITY` for release signing.
- The app uses network client entitlement for Ollama, App Store, and Sparkle checks.
- Sandbox is disabled because AppAudit scans installed apps directly.

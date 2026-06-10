#!/usr/bin/env bash
# Builds and installs the Sift2 side-build: a parallel copy with its own bundle ID
# (com.kikaapp.sift2). Because the store folder and Keychain service derive from the
# bundle ID, Sift2 uses an isolated SwiftData store (~/Library/Application Support/Sift2)
# and an isolated Keychain service, so it never touches — or prompts for — the primary
# Sift app's data and license keys.
#
# Usage: bash Scripts/build_sift2.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ARCH="$(uname -m)"
APP_NAME="Sift2"
BUNDLE_ID="com.kikaapp.sift2"
PRODUCT="Sift"   # Swift package product/binary name

if [[ -f version.env ]]; then source version.env; fi
MARKETING_VERSION="${MARKETING_VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

echo "==> Building (release, $ARCH)"
swift build -c release --arch "$ARCH"

# Older SwiftPM writes per-arch dirs; the Xcode 27 toolchain writes .build/release
# even when --arch is passed. Prefer whichever actually exists.
SRCBIN="$ROOT/.build/${ARCH}-apple-macosx/release/${PRODUCT}"
if [[ ! -f "$SRCBIN" ]]; then
  SRCBIN="$ROOT/.build/release/${PRODUCT}"
fi
[[ -f "$SRCBIN" ]] || { echo "ERROR: missing build product at $SRCBIN" >&2; exit 1; }

APP="$ROOT/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$SRCBIN" "$APP/Contents/MacOS/${APP_NAME}"
chmod +x "$APP/Contents/MacOS/${APP_NAME}"
[[ -f "$ROOT/Icon.icns" ]] && cp "$ROOT/Icon.icns" "$APP/Contents/Resources/AppIcon.icns"

GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key><string>© $(date +%Y) Veronica Loren</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>GitCommit</key><string>${GIT_COMMIT}</string>
</dict>
</plist>
PLIST

xattr -cr "$APP"
codesign --force --sign "-" --entitlements "$ROOT/Sources/AppAudit/AppAudit.entitlements" "$APP"

pkill -x "${APP_NAME}" 2>/dev/null || true
sleep 0.5
rm -rf "/Applications/${APP_NAME}.app"
cp -R "$APP" "/Applications/${APP_NAME}.app"
rm -rf "$APP"

echo "==> Installed /Applications/${APP_NAME}.app (${GIT_COMMIT})"
open "/Applications/${APP_NAME}.app" || true

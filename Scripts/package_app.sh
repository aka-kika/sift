#!/usr/bin/env bash
set -euo pipefail

CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP_NAME=${APP_NAME:-Sift}
# Bundle ID intentionally unchanged across the AppAudit -> Sift rename so existing
# user data (SwiftData store + Keychain license keys) carries over.
BUNDLE_ID=${BUNDLE_ID:-com.kikaapp.appaudit}
MACOS_MIN_VERSION=${MACOS_MIN_VERSION:-14.0}
SIGNING_MODE=${SIGNING_MODE:-adhoc}
APP_IDENTITY=${APP_IDENTITY:-}

if [[ -f "$ROOT/version.env" ]]; then
  source "$ROOT/version.env"
else
  MARKETING_VERSION=${MARKETING_VERSION:-1.0.0}
  BUILD_NUMBER=${BUILD_NUMBER:-1}
fi

ARCH_LIST=( ${ARCHES:-} )
if [[ ${#ARCH_LIST[@]} -eq 0 ]]; then
  HOST_ARCH=$(uname -m)
  ARCH_LIST=("$HOST_ARCH")
fi

for ARCH in "${ARCH_LIST[@]}"; do
  swift build -c "$CONF" --arch "$ARCH"
done

APP="$ROOT/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")

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
    <key>LSMinimumSystemVersion</key><string>${MACOS_MIN_VERSION}</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key><string>© $(date +%Y) Veronica Loren</string>
    <!-- Uninstall hands root-owned bundles (App Store installs) to Finder,
         which macOS gates behind an Automation consent prompt. -->
    <key>NSAppleEventsUsageDescription</key><string>Sift asks Finder to move App Store apps to the Trash, because macOS only lets Finder move apps it owns.</string>
    <key>LSUIElement</key><false/>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>BuildTimestamp</key><string>${BUILD_TIMESTAMP}</string>
    <key>GitCommit</key><string>${GIT_COMMIT}</string>
$(if [[ -n "${SPARKLE_FEED_URL:-}" ]]; then cat <<SPARKLE
    <!-- Sparkle self-update: feed + EdDSA public key come from version.env. -->
    <key>SUFeedURL</key><string>${SPARKLE_FEED_URL}</string>
    <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_KEY:-}</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUScheduledCheckInterval</key><integer>86400</integer>
SPARKLE
fi)
</dict>
</plist>
PLIST

build_product_path() {
  local name="$1"
  local arch="$2"
  # Older SwiftPM writes per-arch dirs; the Xcode 27 toolchain writes .build/<conf>
  # even when --arch is passed. Prefer whichever actually exists.
  local arch_path=".build/${arch}-apple-macosx/$CONF/$name"
  local flat_path=".build/$CONF/$name"
  if [[ -f "$arch_path" ]]; then
    echo "$arch_path"
  else
    echo "$flat_path"
  fi
}

install_binary() {
  local name="$1"
  local dest="$2"
  local binaries=()
  for arch in "${ARCH_LIST[@]}"; do
    local src
    src=$(build_product_path "$name" "$arch")
    if [[ ! -f "$src" ]]; then
      echo "ERROR: Missing ${name} build for ${arch} at ${src}" >&2
      exit 1
    fi
    binaries+=("$src")
  done
  if [[ ${#ARCH_LIST[@]} -gt 1 ]]; then
    lipo -create "${binaries[@]}" -output "$dest"
  else
    cp "${binaries[0]}" "$dest"
  fi
  chmod +x "$dest"
}

install_binary "$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# Embed Sparkle.framework (SwiftPM binary artifact). The executable is linked with
# an @executable_path/../Frameworks rpath (see Package.swift) so it finds it here.
SPARKLE_FW=$(find "$ROOT/.build/artifacts" -path '*Sparkle.xcframework/macos-*/Sparkle.framework' -maxdepth 5 -type d | head -1)
if [[ -z "$SPARKLE_FW" ]]; then
  echo "ERROR: Sparkle.framework not found under .build/artifacts — run 'swift package resolve'." >&2
  exit 1
fi
# -R keeps the Versions/ symlink structure; --deep signing below relies on it being intact.
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"

# Bundle app icon
ICON_ICNS="$ROOT/Icon.icns"
if [[ -f "$ICON_ICNS" ]]; then
  cp "$ICON_ICNS" "$APP/Contents/Resources/AppIcon.icns"
fi

# Bundle the About tab's brand glyphs (vector PDFs, tinted as templates)
if [[ -d "$ROOT/Resources/socials" ]]; then
  cp "$ROOT"/Resources/socials/*.pdf "$APP/Contents/Resources/"
fi

# Copy entitlements
ENTITLEMENTS="$ROOT/Sources/AppAudit/AppAudit.entitlements"
if [[ ! -f "$ENTITLEMENTS" ]]; then
  ENTITLEMENTS="$ROOT/AppAudit.entitlements"
fi

chmod -R u+w "$APP"
xattr -cr "$APP"
find "$APP" -name '._*' -delete

if [[ "$SIGNING_MODE" == "adhoc" || -z "$APP_IDENTITY" ]]; then
  CODESIGN_ARGS=(--force --sign "-")
else
  CODESIGN_ARGS=(--force --timestamp --options runtime --sign "$APP_IDENTITY")
fi

# Sparkle: sign the helpers inside the framework first, then the framework, then
# the app — nested code must already be signed when the outer signature is made.
SPARKLE_IN_APP="$APP/Contents/Frameworks/Sparkle.framework"
codesign "${CODESIGN_ARGS[@]}" "$SPARKLE_IN_APP/Versions/B/XPCServices/Installer.xpc"
codesign "${CODESIGN_ARGS[@]}" "$SPARKLE_IN_APP/Versions/B/XPCServices/Downloader.xpc"
codesign "${CODESIGN_ARGS[@]}" "$SPARKLE_IN_APP/Versions/B/Autoupdate"
codesign "${CODESIGN_ARGS[@]}" "$SPARKLE_IN_APP/Versions/B/Updater.app"
codesign "${CODESIGN_ARGS[@]}" "$SPARKLE_IN_APP"

if [[ -f "$ENTITLEMENTS" ]]; then
  codesign "${CODESIGN_ARGS[@]}" --entitlements "$ENTITLEMENTS" "$APP"
else
  codesign "${CODESIGN_ARGS[@]}" "$APP"
fi

echo "✅ Created $APP"

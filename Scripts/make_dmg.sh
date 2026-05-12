#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="AppAudit"
VERSION=$(source version.env && echo "$MARKETING_VERSION")
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_SOURCE=".dmg-source"

set_dmg_file_icon() {
  local target="$1"
  local icon="$2"
  local temp_dir
  local temp_icon
  local temp_rsrc

  if ! command -v sips >/dev/null 2>&1 ||
     ! xcrun -find Rez >/dev/null 2>&1 ||
     ! xcrun -find DeRez >/dev/null 2>&1 ||
     ! xcrun -find SetFile >/dev/null 2>&1; then
    echo "WARN: Skipping DMG file icon; Xcode icon tools are not available." >&2
    return 0
  fi

  temp_dir=$(mktemp -d -t "${APP_NAME}-dmg-icon")
  temp_icon="$temp_dir/Icon.icns"
  temp_rsrc="$temp_dir/Icon.rsrc"
  trap 'rm -rf "$temp_dir"' RETURN

  cp "$icon" "$temp_icon"
  sips -i "$temp_icon" >/dev/null
  xcrun DeRez -only icns "$temp_icon" > "$temp_rsrc"
  xcrun Rez -append "$temp_rsrc" -o "$target"
  xcrun SetFile -a C "$target"
}

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "ERROR: create-dmg is required. Install with: brew install create-dmg" >&2
  exit 1
fi

echo "==> Building ${APP_NAME}.app"
bash "$ROOT/Scripts/package_app.sh" release

echo "==> Creating polished DMG for ${APP_NAME} ${VERSION}"

rm -rf "$DMG_SOURCE"
rm -f "$DMG_NAME"
mkdir -p "$DMG_SOURCE"
cp -R "${APP_NAME}.app" "$DMG_SOURCE/"

hdiutil detach "/Volumes/${APP_NAME}" 2>/dev/null || true

create-dmg \
  --volname "$APP_NAME" \
  --volicon "$ROOT/Icon.icns" \
  --window-pos 200 120 \
  --window-size 620 360 \
  --text-size 12 \
  --icon-size 112 \
  --icon "${APP_NAME}.app" 155 170 \
  --hide-extension "${APP_NAME}.app" \
  --app-drop-link 465 170 \
  --no-internet-enable \
  "$DMG_NAME" \
  "$DMG_SOURCE"

rm -rf "$DMG_SOURCE"

echo "==> Applying DMG file icon"
set_dmg_file_icon "$DMG_NAME" "$ROOT/Icon.icns"

if [[ "${SIGNING_MODE:-adhoc}" != "adhoc" && -n "${APP_IDENTITY:-}" ]]; then
  echo "==> Signing DMG"
  codesign --force --timestamp --sign "$APP_IDENTITY" "$DMG_NAME"
fi

echo ""
echo "✅ Created: $(ls -lh "$DMG_NAME" | awk '{print $9, "("$5")"}')"

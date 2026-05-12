#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="AppAudit"
VERSION=$(source version.env && echo "$MARKETING_VERSION")
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
TEMP_DMG="${APP_NAME}-temp.dmg"

APP_SIZE=$(du -sm "${APP_NAME}.app" | awk '{print $1}')
DMG_SIZE=$((APP_SIZE + 30))

echo "==> Creating DMG (${DMG_SIZE}MB) for ${APP_NAME} ${VERSION}"

rm -f "$TEMP_DMG" "$DMG_NAME"

# Create writable HFS+ image
hdiutil create -size "${DMG_SIZE}m" -fs HFS+ -volname "$APP_NAME" -o "$TEMP_DMG"

# Eject any existing AppAudit volume first
hdiutil detach "/Volumes/${APP_NAME}" 2>/dev/null || true

# Mount and capture mount point reliably via plist output
MOUNT_PLIST=$(hdiutil attach "$TEMP_DMG" -readwrite -noverify -noautoopen -plist)
MOUNT_POINT=$(echo "$MOUNT_PLIST" | \
  python3 -c "import sys,plistlib; d=plistlib.loads(sys.stdin.buffer.read()); \
  [print(e['mount-point']) for e in d.get('system-entities',[]) if 'mount-point' in e]" | tail -1)
echo "Mounted at: $MOUNT_POINT"

# Copy app bundle
cp -R "${APP_NAME}.app" "$MOUNT_POINT/"

# Create Applications symlink inside the DMG volume
ln -s /Applications "$MOUNT_POINT/Applications"

# Set Finder window layout
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$APP_NAME"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {400, 100, 900, 400}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 100
    delay 1
    try
      set position of item "${APP_NAME}.app" of container window to {130, 150}
      set position of item "Applications" of container window to {370, 150}
    end try
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

# Bless the volume and detach
hdiutil detach "$MOUNT_POINT"

# Convert to compressed read-only
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_NAME"
rm "$TEMP_DMG"

echo ""
echo "✅ Created: $(ls -lh "$DMG_NAME" | awk '{print $9, "("$5")"}')"

#!/usr/bin/env bash
# Sift release pipeline — one command from source to a published update.
#
#   bash Scripts/release.sh            # build, sign, notarize, staple, appcast, site files
#   NOTARIZE=0 bash Scripts/release.sh # skip notarization (local dry run)
#
# What it does, in order:
#   1. Developer ID build + DMG (Scripts/make_dmg.sh)
#   2. Notarize + staple the DMG (NOTARIZE=1, default)
#   3. Copy the DMG into site/downloads/ and regenerate site/appcast.xml with
#      Sparkle's generate_appcast (EdDSA-signed with the "Sift" keychain key)
#   4. Point site/vercel.json's /Sift.dmg redirect at the new DMG
#   5. Bump the Homebrew cask (version + sha256)
#
# Publishing the site (`cd site && vercel deploy --prod --yes`) and the GitHub
# release (`gh release create`) stay separate, deliberate steps — see docs/RELEASE.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source version.env

VERSION="$MARKETING_VERSION"
DMG="Sift-${VERSION}.dmg"
NOTARIZE="${NOTARIZE:-1}"
SIGNING_MODE="${SIGNING_MODE:-developer}"
# Two identical Developer ID certs live in the login keychain; by-name is ambiguous.
APP_IDENTITY="${APP_IDENTITY:-D833417579CBB62121FD344B1513AE5D44A36762}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-Sift}"
SITE_DOWNLOADS="$ROOT/site/downloads"
DOWNLOAD_PREFIX="https://sift.akakika.com/downloads/"

step() { printf '\n==> %s\n' "$*"; }

step "1/5 Build + sign Sift ${VERSION} (identity ${APP_IDENTITY:0:8}…)"
SIGNING_MODE="$SIGNING_MODE" APP_IDENTITY="$APP_IDENTITY" bash Scripts/make_dmg.sh
codesign --verify --deep --strict --verbose=2 Sift.app
spctl --assess --type execute --verbose=4 Sift.app || true

if [[ "$NOTARIZE" == "1" ]]; then
  step "2/5 Notarize + staple ${DMG}"
  xcrun notarytool submit "$DMG" --keychain-profile AC_PASSWORD --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
else
  step "2/5 Notarization skipped (NOTARIZE=0)"
fi

step "3/5 Appcast"
GENERATE_APPCAST=$(find "$ROOT/.build/artifacts" -path '*/Sparkle/bin/generate_appcast' -maxdepth 6 | head -1)
[[ -x "$GENERATE_APPCAST" ]] || { echo "ERROR: generate_appcast not found — run 'swift package resolve'." >&2; exit 1; }
mkdir -p "$SITE_DOWNLOADS"
cp -f "$DMG" "$SITE_DOWNLOADS/$DMG"
# generate_appcast signs every DMG in the folder and writes deltas for older ones;
# we keep only full DMGs so the site stays small.
"$GENERATE_APPCAST" --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --maximum-deltas 0 \
  -o "$ROOT/site/appcast.xml" \
  "$SITE_DOWNLOADS"
echo "appcast entries:"; grep -o 'sparkle:shortVersionString="[^"]*"' "$ROOT/site/appcast.xml" || grep -o '<sparkle:shortVersionString>[^<]*' "$ROOT/site/appcast.xml" || true

step "4/5 Site redirect -> ${DMG}"
sed -i '' -E "s#/downloads/Sift-[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?\.dmg#/downloads/${DMG}#g" site/vercel.json
sed -i '' -E "s#Sift · v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)? · macOS#Sift · v${VERSION} · macOS#" site/index.html
grep -n "downloads/" site/vercel.json

step "5/5 Homebrew cask"
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
sed -i '' -E "s#^  version \".*\"#  version \"${VERSION}\"#; s#^  sha256 \".*\"#  sha256 \"${SHA}\"#" Scripts/homebrew/sift.rb
grep -n "version\|sha256" Scripts/homebrew/sift.rb

printf '\nSHA-256 %s  %s\n' "$SHA" "$DMG"
cat <<EOF

Next (by hand, in this order):
  git add -A && git commit -m "release: Sift ${VERSION}" && git tag v${VERSION} && git push origin main v${VERSION}
  gh release create v${VERSION} ${DMG} --title "Sift ${VERSION}" --notes-file docs/releases/${VERSION}.md
  cd site && vercel deploy --prod --yes      # ships appcast.xml + the DMG; Sparkle users see the update
EOF

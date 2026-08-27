#!/usr/bin/env bash
# Sift2 — an isolated side-build for testing without touching the daily Sift.app:
# its own bundle ID (own SwiftData folder + Keychain service), no Sparkle feed.
# Everything else is the real packaging script, so the two can't drift.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME=Sift2 BUNDLE_ID=com.kikaapp.sift2 SPARKLE_FEED_URL= SPARKLE_PUBLIC_KEY= \
  bash "$ROOT/Scripts/package_app.sh" release

pkill -x Sift2 2>/dev/null || true
sleep 0.5
rm -rf /Applications/Sift2.app
cp -R "$ROOT/Sift2.app" /Applications/Sift2.app
rm -rf "$ROOT/Sift2.app"

echo "==> Installed /Applications/Sift2.app ($(git rev-parse --short HEAD 2>/dev/null || echo dev))"
open /Applications/Sift2.app || true

# typed: strict
# frozen_string_literal: true

cask "sift" do
  version "1.11.0"
  sha256 "19e26a55ebfc3d2a20b0366d1a14f856f370114d44322131322618f547c6b89a"

  url "https://sift.akakika.com/downloads/Sift-#{version}.dmg"
  name "Sift"
  desc "Audit of every installed app: what it is, what it costs you, whether it stays"
  homepage "https://sift.akakika.com/"

  livecheck do
    url :homepage
    regex(/v?(\d+(?:\.\d+)+)\s*·\s*macOS/i)
  end

  # Sift updates itself with Sparkle; brew upgrade leaves it alone.
  auto_updates true
  depends_on macos: :sonoma

  app "Sift.app"

  # Keychain items (stored license keys) are deliberately left alone.
  zap trash: [
    "~/Library/Application Support/AppAudit",
    "~/Library/Caches/com.kikaapp.appaudit",
    "~/Library/Preferences/com.kikaapp.appaudit.plist",
  ]
end

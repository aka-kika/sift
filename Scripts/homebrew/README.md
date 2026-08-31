# Homebrew cask

**Published 2026-09-01.** The tap lives at https://github.com/aka-kika/homebrew-tap
(public, cask at `Casks/sift.rb`); users install with
`brew install --cask aka-kika/tap/sift`. `Scripts/release.sh` bumps the local
`sift.rb` on every release — copy it into the tap repo and push (step 2 below).

`sift.rb` is the source of truth for the Sift cask. It installs the notarized DMG
from https://sift.akakika.com/downloads/Sift-<version>.dmg.

## Own tap (works today, no review queue)

The cask must live in a **public** repo named `homebrew-tap`:

```bash
gh repo create aka-kika/homebrew-tap --public --description "Homebrew tap for Kika's apps" --clone
cp Scripts/homebrew/sift.rb ../homebrew-tap/Casks/sift.rb   # create Casks/ first
git -C ../homebrew-tap add -A && git -C ../homebrew-tap commit -m "sift 1.10.0" && git -C ../homebrew-tap push
```

Users then run:

```bash
brew install --cask aka-kika/tap/sift
```

## On each release

1. Bump `version` and `sha256` (`shasum -a 256 site/downloads/Sift-X.Y.Z.dmg`) — `Scripts/release.sh` does this.
2. Copy the file into the tap repo and push. `brew livecheck --cask sift` should report the
   new version from the site footer.

## homebrew/cask (the central index)

Possible later; the app has to be publicly downloadable (it is) and Homebrew's reviewers
apply a notability bar. Start with the tap, submit once the app has some public traction.

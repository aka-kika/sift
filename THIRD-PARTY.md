# Third-party notices

Sift itself is MIT licensed (see [LICENSE](LICENSE)). This file lists the outside work it uses or learned from.

## Sparkle (bundled)

https://github.com/sparkle-project/Sparkle
MIT License, Copyright (c) 2006-2013 Andy Matuschak and the other Sparkle contributors named in its LICENSE.
Sift's self-update runs on Sparkle 2, which ships inside the app as Sparkle.framework. It is Sift's only package dependency. Its full licence text comes with the framework and is in the Sparkle repository.

## uninstally (adapted)

https://github.com/gostonx/uninstally
MIT License, Copyright (c) 2026 Codenta.
The leftover-discovery strategy in `Sources/AppAudit/Services/LeftoverScanner.swift` is adapted from uninstally. Attribution is preserved in that source file. Its MIT terms are compatible with Sift's licence.

## Mole (idea only, no code)

https://github.com/tw93/Mole
GNU General Public License v3.0, Copyright (c) tw93.
Mole is the reason Sift shows a running-app indicator and offers a sort by last-used date, and it was studied for its protection-list and Homebrew-path concepts. No Mole source is present in Sift: Mole is written in Go, Sift in Swift, and these behaviours are independent implementations against Apple's own APIs (NSRunningApplication and Spotlight's kMDItemLastUsedDate). What was taken is the idea, which carries no licence obligation; Mole remains separately licensed under the GPL-3.0 and no part of it is redistributed here.

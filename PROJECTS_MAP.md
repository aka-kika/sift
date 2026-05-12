# AppAudit Project Map

AppAudit is a native SwiftUI macOS app built with Swift Package Manager.

## Top Level

| Path | Purpose |
|---|---|
| `Package.swift` | Swift package definition |
| `Sources/AppAudit` | App source code |
| `Tests/AppAuditTests` | Unit and behavior tests |
| `Scripts` | Build, run, package, and DMG scripts |
| `docs` | Product, architecture, and release documentation |
| `Icon.icns` | App and DMG icon source |
| `AppIcon.iconset` | Icon source slices |
| `version.env` | Marketing version and build number |

Generated files such as `.build/`, `AppAudit.app/`, and `AppAudit-*.dmg` are ignored.

## Source Layout

| Area | Key Files |
|---|---|
| App entry | `AppAuditApp.swift` |
| Models | `AppInfo.swift`, `AppRecord.swift`, `WorkflowProfile.swift`, `AnalysisProviderKind.swift` |
| Services | `AppScanner.swift`, `OllamaService.swift`, `AppleIntelligenceService.swift`, `CacheService.swift`, `UpdateChecker.swift`, `AppLinkResolver.swift`, `LicenseKeyStore.swift`, `HomebrewService.swift` |
| View model | `AppListViewModel.swift` |
| Views | `ContentView.swift`, `AppListView.swift`, `AppRow.swift`, `AppDetailView.swift`, `SettingsView.swift` |

## Build Commands

```bash
swift build
swift test
bash Scripts/compile_and_run.sh
bash Scripts/make_dmg.sh
```

## Release Docs

Read `docs/RELEASE.md` before Developer ID signing or notarization.

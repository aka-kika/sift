# AppAudit

This repository contains the source code and supporting materials for AppAudit, a native macOS application designed to audit installed applications using local AI analysis.

## Purpose

- Provide the executable code for the AppAudit macOS application.
- Implement local AI analysis capabilities using Ollama to assess installed applications.
- Manage the application's architecture, including views, view models, and service layers for structured data flow.
- Utilize SwiftData for persistent local storage of app analysis results.

## Key Observations

- The application requires macOS 14+ and integrates local AI analysis via Ollama (e.g., `ollama pull llama3.2`).
- AppAudit analyzes installed applications, providing an explanation, a 1-5 relevance score, and an actionable tip for the user.
- The architecture is structured using SwiftUI Views, an `AppListViewModel`, and services (`AppScanner`, `OllamaService`).
- Data persistence is managed by SwiftData, storing cached results in `~/Library/Application Support/AppAudit/AppAudit.store`.
- Analysis scans installed apps, loads cached records, and limits Ollama enrichment to 4 concurrent tasks.

## Top-Level Contents

- `AppAudit-1.0.0.dmg`: Top-level file.
- `AppAudit.app`: Folder containing project files or grouped materials.
- `AppIcon.iconset`: Folder containing project files or grouped materials.
- `docs`: Project or reference folder with documentation at the top level.
- `Icon.icns`: Top-level file.
- `Package.swift`: Top-level file.
- `Scripts`: Folder containing project files or grouped materials.
- `Sources`: Folder containing project files or grouped materials.
- `Tests`: Folder containing project files or grouped materials.
- `version.env`: Top-level file.

## Grouped Contents

Below is a high-level grouping of the contents, based on naming and file types:

- **Apple / Swift projects**: `AppAudit.app`, `AppIcon.iconset`
- **Project folders**: `docs`, `Scripts`, `Sources`, `Tests`
- **Files**: `AppAudit-1.0.0.dmg`, `Icon.icns`, `Package.swift`, `version.env`

## Quick Start Suggestions

- Review `docs/README.md` for prerequisites, noting the need for macOS 14+ and Ollama setup.
- Consult `Package.swift` to understand the Swift package structure and target definition.
- Execute the quick start steps provided in the README: start Ollama, pull the model, and run the `.dmg` file.
- Examine the architecture diagrams in `docs/ARCHITECTURE.md` to understand the flow between services and the `AppListViewModel`.

## Summary Statistics

- **Total Files**: 35
- **Total Folders**: 12
- **Total Size**: 4.9 MB

## Common File Types

Here are the most common file extensions in this directory:

| Extension | Count |
|-----------|-------|
| `swift` | 16 |
| `png` | 10 |
| `sh` | 3 |
| `md` | 2 |
| `dmg` | 1 |
| `entitlements` | 1 |
| `env` | 1 |
| `icns` | 1 |

## Directory Structure Preview

Below is a preview of the directory structure (up to 41 levels deep):

```text
AppAudit
├─ AppAudit.app
│  └─ Contents
│     ├─ _CodeSignature
│     ├─ Frameworks
│     ├─ MacOS
│     ├─ Resources
│     └─ Info.plist
├─ AppIcon.iconset
│  ├─ icon_128x128.png
│  ├─ icon_128x128@2x.png
│  ├─ icon_16x16.png
│  ├─ icon_16x16@2x.png
│  ├─ icon_256x256.png
│  ├─ icon_256x256@2x.png
│  ├─ icon_32x32.png
│  ├─ icon_32x32@2x.png
│  ├─ icon_512x512.png
│  └─ icon_512x512@2x.png
├─ docs
│  ├─ ARCHITECTURE.md
│  └─ README.md
├─ Scripts
│  ├─ compile_and_run.sh
│  ├─ make_dmg.sh
│  └─ package_app.sh
├─ Sources
│  └─ AppAudit
│     ├─ Models
│     ├─ Services
│     ├─ ViewModels
│     ├─ Views
│     ├─ AppAudit.entitlements
│     └─ AppAuditApp.swift
├─ Tests
│  └─ AppAuditTests
│     └─ AppAuditTests.swift
├─ AppAudit-1.0.0.dmg
├─ Icon.icns
├─ Package.swift
└─ version.env
```

> _Note: This preview is truncated for readability. For a full view, browse the directory directly._

# Local Docs Evidence for Apps

**Date:** 2026-07-04
**Status:** Approved

## Summary

Let any app — especially a **My App** with a private repo or no public presence
— get grounded analysis from a **local folder** read off disk. The user attaches
the app's project folder once; Sift extracts the README and a stack hint,
snapshots that text onto the record, and feeds it into the existing analysis
evidence channel alongside `linkEvidence` and `userNotes`. Fully local: no
network, no auth.

## Background

- The analysis prompt already grounds on *evidence*: `AppAnalysisPrompt.build`
  takes `linkEvidence` (the app website's fetched words) and `userNotes`, both
  treated as primary evidence for "what this app is."
- My Apps analyze poorly only because they have no *public* evidence to fetch.
  A local project folder is the grounding they're missing.
- `LinkEvidence` is the model for a small, focused evidence extractor.
- New `AppRecord` fields are additive/defaulted, so the SwiftData store migrates
  in place (same pattern as `isFreeApp` / `licenseType`).
- Sift is not sandboxed (ad-hoc signed Swift package app), so plain path reading
  works — no security-scoped bookmarks needed in v1.

## Design

### 1. Extraction — `DocsEvidence`

A new enum `DocsEvidence` (sibling of `LinkEvidence`), given a folder path,
reads at the folder **root only** (no recursion in v1):

- **README** — first match, case-insensitive, of `README.md`, `README`,
  `README.txt`, `README.markdown`. Its text is trimmed and truncated to a cap
  (`maxReadmeChars = 4000`) so a large README cannot dominate the prompt.
- **Stack hint** — the filenames of any present manifest files from a fixed set
  (`Package.swift`, `package.json`, `Cargo.toml`, `pyproject.toml`, `go.mod`,
  `Gemfile`, `Info.plist`, `*.xcodeproj`/`*.xcworkspace` by name), joined into
  one line: `Detected project files: <names>`.
- Returns the combined snapshot string, or `nil` if neither a README nor any
  manifest is found.

Signature: `DocsEvidence.extract(fromFolder path: String) -> String?`

### 2. Storage

Two new `AppRecord` fields, both defaulted:

- `docsEvidence: String?` — the extracted snapshot text (nil = none attached).
- `docsFolderPath: String?` — the remembered source folder, for one-click
  refresh and "reveal in Finder".

Snapshot semantics: the evidence is captured at attach/refresh time and does not
re-read disk during analysis, so a full scan never touches the filesystem or
re-prompts for access. The user refreshes when they change the README.

### 3. UI — the Docs cube (7th cube)

A teal, icon-only cube added to the utility row after the existing six, matching
the established `UtilityCard` pattern:

- Icon `doc.text`; **gray when `docsEvidence` is nil**, **teal (active) when
  set**.
- **Tap, empty** → open an `NSOpenPanel` folder picker; on pick, extract and
  store, then trigger reanalysis. If extraction returns nil, show a brief
  "No README or manifest found there" message and attach nothing.
- **Tap, attached** → refresh: re-read `docsFolderPath`, re-store, trigger
  reanalysis.
- **Right-click** → "Change Folder…", "Reveal Source in Finder", "Remove".
  Remove clears both fields and triggers reanalysis.
- Tooltip shows the source folder and a short snippet of the evidence.

The row remains icon-only; the cube stretches with the others to fill the width.

### 4. Prompt integration + reanalysis

- `AppAnalysisPrompt.build` gains `docsEvidence: String = ""`. When non-empty it
  injects a block above the evidence rules:

  > From the app's own project files (provided by the user — treat as the
  > strongest evidence for what this app is):
  > `<snapshot>`

  plus one evidence rule: the app's own project files outrank URL and metadata
  evidence for what the app is, but do not invent facts they do not state.
- All three providers already share `build(...)`; `docsEvidence` threads through
  the `analyze(...)` chain the same way `userNotes` does.
- Loaded from the cached record on **every** analysis path (`reanalyze`,
  `enrichConcurrently` seed + refill, full scan) next to where `appURL` /
  `notes` are already loaded.
- New `reanalyzeAfterDocsChange(bundleID:)` mirrors `reanalyzeAfterLinkChange`:
  lock-respecting (in-memory flag AND cached record), fires `reanalyze`.

### 5. Out of scope (v1)

- No recursion into subfolders; root-level files only.
- No deep parsing of manifest contents (only their presence as a stack hint).
- No GitHub/network fetch (a separate, opt-in future option).
- No security-scoped bookmarks (Sift is not sandboxed).
- CSV export unchanged; scoring unchanged.

## Testing

- `DocsEvidence.extract`: temp folder with README + manifest → returns README
  text and the stack-hint line; folder with only a manifest → returns the hint;
  empty/irrelevant folder → nil; oversize README → truncated to the cap.
- Prompt: docs block present and framed as primary evidence when set; omitted
  and byte-identical to today when empty/whitespace.
- Change detection for the reanalysis trigger follows the existing lock-respect
  pattern (covered by the trigger method's guards).
- Existing suite stays green.

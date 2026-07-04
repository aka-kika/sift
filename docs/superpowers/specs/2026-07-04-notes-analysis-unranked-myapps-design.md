# Personal Notes → Analysis + Unranked My Apps

**Date:** 2026-07-04
**Status:** Approved

## Summary

Two features that make Sift's analysis personal:

1. **Notes feed the analysis.** The existing per-app Notes field becomes evidence
   for the AI. Raw user text like "I use this app for x y z" or "I'm learning this
   app's features" directly informs the explanation, score, and best-use line.
   Saving a changed note auto-triggers a re-analysis.
2. **Unranked My Apps.** A global Settings toggle stops ranking apps marked
   **My App** (they are the user's own builds — scoring their "fit" is meaningless),
   with a per-app override to rank a specific one anyway.

## Background

- `AppRecord.notes` already exists (free text, edited in `AppDetailView`'s
  `NotesEditor`, exported to CSV) but is not used in analysis today. Only the
  global style notes from Settings reach the prompt.
- `AppRecord.isMyApp` exists; My Apps get a purple hammer badge when pending and
  a purple ring around their score badge, but they are still scored 1–5.
- All providers (Ollama, ollama.com, Anthropic, OpenAI) build their prompt through
  the single shared `AppAnalysisPrompt.build(...)`, so per-app context is a
  single-point injection.
- The notes editor saves on every keystroke, so "on save" must mean "when the
  editor closes and the text changed," not per keystroke.

## Design

### 1. Notes as analysis evidence

- `AppAnalysisPrompt.build(...)` gains a `userNotes: String = ""` parameter.
- When non-empty, the prompt includes a block above the evidence rules:

  > The user's own notes about this app (their raw words — treat as the
  > strongest evidence for how THEY use it):

  followed by the trimmed note text.
- One new evidence rule: user notes outrank URL/metadata evidence for **scoring
  and best-use**, but must not be used to invent product facts the note does not
  state.
- The `AnalysisService` protocol's `analyze(...)` (and each provider) passes
  `userNotes` through to the prompt builder.
- Notes are loaded from the cached `AppRecord` at analysis time, in the same
  place the reference URL (`appURL`) is loaded — so notes apply during full
  scans and "re-analyze all," not just single re-runs.

### 2. Auto re-analysis on note change

- New `reanalyzeAfterNotesChange(bundleID:)` on `AppListViewModel`, mirroring
  `reanalyzeAfterLinkChange`: skips locked analyses (both the in-memory flag and
  the cached record's `isAnalysisLocked`), then runs `reanalyze(bundleID:)`.
- Trigger point in `AppDetailView`: when the notes editor collapses (or focus
  leaves the detail view / the selected app changes), compare the current note
  text to a snapshot captured when the editor was expanded. Different → trigger;
  same → nothing. Typing alone never triggers a run.
- Locked apps: the note still saves; the analysis does not run. It simply feeds
  the next manual re-analysis after unlocking.

### 3. Unranked My Apps

**Controls**

- Global Settings toggle: **"Don't rank My Apps"** (`UserDefaults` key
  `skipRankingMyApps`, default **off**).
- Per-app override on `AppRecord`: `rankingOverride: Bool?` (nil = follow the
  global setting; `true` = rank this app anyway). Shown in the detail view only
  for apps marked My App, only when the global toggle is on.
- Effective rule: an app is **unranked** when
  `skipRankingMyApps && isMyApp && rankingOverride != true`.

**Display (immediate, no re-analysis required)**

- Unranked apps show the purple hammer badge instead of the score number, even
  if a cached score exists.
- Relevance sort groups unranked apps with unscored apps.
- CSV export writes an empty score/reason column for unranked apps.

**Analysis (takes effect on next run)**

- For unranked apps, the response format drops `SCORE:` and `REASON:` entirely —
  the model produces only `EXPLANATION:` and `BEST_USE:` (still informed by
  notes). The scoring guide block is also omitted.
- The parser accepts the score-less format; the stored `relevanceScore` is `0`,
  meaning "not ranked."

### 4. Out of scope

- No auto re-analysis when toggling the global setting or a per-app override
  (display updates immediately; the cheaper prompt applies on the next run).
- The Custom Description field stays presentation-only.
- No exclusion toggle for non-My-App apps.

## Testing

- Prompt builder: includes the notes block when notes are set; omits it when
  empty/whitespace; unranked format omits SCORE/REASON and the scoring guide.
- Parser: parses a response with only EXPLANATION and BEST_USE (score → 0).
- Trigger logic: note changed on editor close → re-analysis requested; note
  unchanged → not requested; locked app → not requested.
- Effective-unranked rule: all combinations of global toggle × isMyApp ×
  rankingOverride.
- Existing tests stay green.

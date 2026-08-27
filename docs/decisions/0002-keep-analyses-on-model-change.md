# 0002. Keep cached analyses when the AI model changes

**Date:** 2026-06-06 · **Status:** Accepted

## Context

<!-- SF Symbol: doc.text -->
Originally, `CacheService.isStale` treated any difference between a record's
stored model identifier and the currently selected model as staleness. Switching
the Ollama model therefore silently wiped and regenerated every unlocked
analysis on the next scan — minutes of local LLM work and any wording the owner
had come to rely on, gone without consent. As the app gained more providers
(Anthropic, OpenAI), provider/model switching became routine rather than rare,
making the silent wipe a recurring cost.

## Options considered

<!-- SF Symbol: arrow.triangle.branch -->
- **Keep auto-invalidation** — always re-analyze on model change. Results always
  reflect the current model; but regeneration is slow, unprompted, and destroys
  output the user may prefer.
- **Never invalidate, no signal** — keep analyses forever until manual
  re-analyze. Safe but silently mixes models with no way to notice drift.
- **Keep analyses, surface drift, offer bulk refresh** — model mismatch no
  longer marks records stale; a read-only check (`wasAnalyzedWithDifferentModel`)
  counts drifted records and drives a dismissible banner with a one-click
  scoped re-analyze. App-link changes still invalidate, since the link is
  analysis *input* rather than analysis *engine*.

## Decision

<!-- SF Symbol: checkmark.circle -->
Keep analyses and surface drift (option three). Regeneration becomes something
the user chooses, never something that happens to them — consistent with the
app's existing lock feature, which exists for exactly this fear.

## Consequences

<!-- SF Symbol: arrow.right.circle -->
- **Good:** model experimentation is free; nothing is lost by trying a different
  LLM. The banner plus "Re-analyze All Apps" gives a clean refresh path.
- **Cost:** the list can transiently mix analyses from different models, and the
  drift banner is one more piece of UI state to maintain.
- **Follow-ups:** none open; bulk re-analyze shipped alongside
  (`reanalyzeAll(scope:)`).

## References

<!-- SF Symbol: link -->
- `docs/archive/superpowers/specs/2026-06-06-appaudit-practical-improvements-design.md`, items 1–2
- Commit `932af92` — Add bulk re-analyze, stop auto-wipe on model change

<!--
Feature Spec (one-pager) — PER PROJECT. From TAMPLATES/1-ship/feature-spec.
Style: no emojis. Monochrome. SF Symbol names noted in comments, not rendered.
-->

# Receipt extraction — backfill missing subscription & license fields

**Date:** 2026-07-04 · **Status:** Ready to build (deferred) · **Owner:** Kika

## Problem

<!-- SF Symbol: questionmark.circle -->
Recording a subscription's price and renewal, or a license's key and email, is
manual retyping from an invoice you already have. The details sit in a receipt
PDF in your inbox; Sift makes you re-enter them by hand.

## Who it's for

<!-- SF Symbol: person -->
Someone adding a subscription or license to an app in Sift who has the vendor's
receipt on disk and doesn't want to transcribe it field by field.

## Proposed behavior

<!-- SF Symbol: wand.and.stars -->
The subscription sheet and the license sheet each show a small drop zone and an
"Attach receipt…" button. Drag a receipt PDF (or plain text) onto it, or click to
pick one. Sift reads the text, asks the local model to pull out the relevant
fields, and fills **only the empty draft fields** — price, currency, cycle,
renewal date, email for a subscription; key, email, type for a license. Anything
you already typed is left untouched. You see the sheet populate, edit anything,
then Save as normal. Nothing commits until you Save.

## Edge cases

<!-- SF Symbol: arrow.triangle.branch -->
- Empty state: nothing attached yet — the sheet works exactly as today.
- Unreadable / image-only / empty PDF: a brief "Couldn't read that receipt"; nothing is filled.
- Model finds nothing: "No new details found"; the sheet is unchanged.
- A field you already filled: never overwritten, even if the receipt disagrees.

## Out of scope

<!-- SF Symbol: nosign -->
- OCR / image receipts (screenshots, scanned PDFs) — text PDFs and .txt/.eml only in v1.
- Storing the receipt file itself, or auto-detecting the vendor.
- Any network fetch — extraction runs through the active analysis provider (local Ollama by default).

## Success looks like

<!-- SF Symbol: target -->
Drop a Paddle or App Store receipt on the subscription sheet and its price,
cycle, and renewal date appear filled and correct, ready to Save — no typing.

## Open questions

<!-- SF Symbol: exclamationmark.bubble -->
- Cloud-provider caveat: if the user has switched to Anthropic/OpenAI, receipt text goes to that provider (same as analysis). Surface it in the tooltip — settled, noted here for the record.

<!-- Full design (architecture, parser, mapping, tests): docs/superpowers/specs/2026-07-04-receipt-extraction-design.md -->

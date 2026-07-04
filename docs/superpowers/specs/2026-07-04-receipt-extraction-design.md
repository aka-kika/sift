# Receipt Extraction to Backfill Missing Fields

**Date:** 2026-07-04
**Status:** DEFERRED — designed, not yet built. Approved approach; parked for a
later release ("later we complicate it").

## Summary

On the subscription sheet and the license sheet, let the user drag-and-drop
(or pick) an invoice/receipt file. Sift reads it, extracts the relevant fields
with the local model, and fills **only the fields that are currently empty** —
never overwriting anything the user already entered. Fully local (PDFKit + the
active analysis provider), grounded (extract only what's in the receipt).

## Decisions (locked during brainstorming)

- **File types:** PDF (text-based, via PDFKit) and plain text (`.txt`/`.eml`).
  No OCR, no image support in v1.
- **Extraction method:** the active provider's `complete()` with a structured
  extraction prompt (mirrors `AppAnalysisPrompt`/`parseAnalysis`). Not regex.
- **UI:** a compact drop zone **plus** an "Attach receipt…" button in each
  sheet (drag or open — both paths). Spinner while the model works.
- **Fill semantics:** extracted values populate only the **empty draft fields**
  of the open sheet; the user reviews and Saves. Nothing commits until Save.

## Design

### 1. `ReceiptText` (file → text)
PDF via `PDFDocument(url:)?.string`; `.txt`/`.eml` via `String(contentsOf:)`.
Trim and cap to ~8 KB. Returns nil for unreadable/empty/image-only files.

### 2. `ReceiptExtractionPrompt` + `ReceiptFields`
A structured prompt asking the model to return a fixed block from the receipt
text (ISO date, currency code, cycle word, price, email, license key, license
type), leaving any absent field blank. A tolerant parser (like `parseAnalysis`)
produces `ReceiptFields` with all-optional properties:
`price: Double?`, `currencyCode: String?`, `cycle: BillingCycle?`,
`renewalDate: Date?`, `email: String?`, `licenseKey: String?`,
`licenseType: LicenseType?`. View-model method
`extractReceipt(text:) async -> ReceiptFields?` runs it through `complete()`.

### 3. Sheet integration
`SubscriptionSheet` and `DetailLicenseKeySheet` each take an
`extractReceipt: (URL) async -> ReceiptFields?` closure (provided by
`AppDetailView`, which wires `ReceiptText` → `viewModel.extractReceipt`). On
drop/open, the sheet runs it and fills only its empty draft bindings:
- Subscription: price, currency, cycle, renewal date, email.
- License: key, email, type.

### 4. Mapping
Currency → code; cycle word → `BillingCycle`; ISO string → `Date`; type word →
`LicenseType`. Unparseable values stay nil (field left as-is).

### 5. Edge cases / local-first
- Unreadable/empty → "Couldn't read that receipt", nothing filled.
- Nothing found → "No new details found", sheet unchanged.
- Caveat: if the active provider is cloud (Anthropic/OpenAI), the receipt text
  goes to that provider, same as analysis. On the default Ollama it's fully
  local. Surface this in the tooltip.

## Testing
- Receipt parser: structured block → `ReceiptFields`; blanks stay nil.
- Mapping: currency/cycle/date/type conversions.
- "Only if missing" merge: pure function — given draft + extracted, only empty
  fields change.

## Not in v1 (future)
- OCR / image receipts.
- Storing the receipt file itself.
- Auto-detecting the vendor.

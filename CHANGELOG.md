# Changelog

Versions follow `versionName+versionCode` from `pubspec.yaml`. The Android
application id `com.abnalhag.gimi.buy_price_assistant_gimi` and the signing
key have not changed, so every version installs as an update.

## 1.5.0+8 — not released yet (branch `claude-development`)

Engineering remediation after the October 2026 audit. Database schema 4 → 5
(additive), backup format 2 → 3 (older backups still restore).

### Data safety
- **Import never merges reordered names.** "كابل 2 خط 4 ملم" and "كابل 4 خط 2 ملم"
  were merged into one product's history by 1.4.0; they are now separate.
  Automatic matching only uses the same code or the same name in the same word
  order and unit; everything else needs an explicit link / create / skip
  decision. See `docs/IMPORT_MATCHING_POLICY.md`.
- Full-page import preview: new, matched and ambiguous products, duplicate
  records (skipped by default, so re-importing a file adds nothing twice) and
  rejected rows (blocking unless accepted). The import is re-checked inside its
  transaction and can be undone later.
- Role-specific columns (Supplier/Customer, Purchase/Sale price and date) are
  no longer silently dropped; duplicate columns, month/day/year dates,
  Windows-1256 and UTF-16 CSV files get clear messages.
- Safety snapshot before every restore and import (newest 5 kept).
- Backups carry a SHA-256 checksum, counts and explicit columns; restore
  validates every row first and shows a summary before replacing data.
- Migrations are idempotent (a downgrade with an older app and upgrade again
  works) and a database from a newer app is refused instead of damaged.
- Unsupported currencies are rejected on upgraded databases that lack the
  CHECK constraint.

### Speed and stability
- Search index (schema v5): 4–11 ms instead of 230–383 ms per search on
  5,000 products / 35,000 records; results are paged with a total count.
- Archived products can be viewed and restored.
- Debounced search, refreshed filter lists, double-tap protection, exact
  values when editing, history loaded page by page.
- Local error log (never sent) with a copyable report; friendly messages in
  the app language instead of raw exceptions.

### Design and language
- New design system (navy and gold from the icon, semantic purchase and sale
  colours, light and dark themes with checked contrast, 48 dp targets).
- Every screen redesigned: home, product card, details and history, product
  and entry forms, settings, import/export and preview, backup, support/about.
- Arabic right-to-left and English left-to-right throughout, including data
  and import messages; numbers use Latin digits with thousands separators.
- New records start in the currency of the product's last record of the same
  kind.
- Adaptive launcher icon with themed-icon layer; the dollar sign is centred.

### Build and release
- `file_picker` 10.3.10 → 13.1.0; `pubspec.lock` committed; `crypto` added.
- SDK levels pinned (min 24, target 36, compile 36); build stops if the
  application id changes.
- CI builds a signed APK and AAB, checks manifest values, 16 KB alignment and
  signatures; actions pinned by commit SHA.
- Tests: 39 → 198 automated tests (plus on-demand benchmark and screenshots).

## 1.4.0+7 — 2026-10-27
- XLSX import compatibility: spreadsheet parsing moved to `excel_community`.

## 1.4.0+6 — 2026-10-26
- HJI branding, launcher icon generated at build time, navigation drawer.
- Search across product fields, notes, suppliers and customers with Arabic,
  Persian and Latin digits; brand and supplier filters; notes-match badge.
- Import matched names independent of word order (reverted in 1.5.0: it
  merged different products).

## 1.3.0+5
- Excel (XLSX) and CSV import and export.

## 1.1.0+3
- Arabic/English, light/dark/system theme, default currency (USD, SAR, YER)
  with a currency per record, name suggestions, settings in backups.
  Details: `docs/archive/v1.1.0/`.

## 1.0.1+2
- First released version: products, purchase and sale history, JSON backup.

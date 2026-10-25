#!/usr/bin/env python3
"""Fail-fast structural, spreadsheet, and SQLite checks for GIMI 1.3.0."""
from __future__ import annotations

import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)
    print(f"PASS: {message}")


def source(relative: str) -> str:
    path = ROOT / relative
    require(path.is_file(), f"required file exists: {relative}")
    return path.read_text(encoding="utf-8")


def main() -> int:
    pubspec = source("pubspec.yaml")
    database = source("lib/data/app_database.dart")
    home = source("lib/screens/home_screen.dart")
    details = source("lib/screens/product_details_screen.dart")
    entries = source("lib/screens/price_entry_form_screen.dart")
    backup = source("lib/screens/backup_restore_screen.dart")
    settings = source("lib/state/app_settings.dart")
    form = source("lib/screens/product_form_screen.dart")
    workflow = source(".github/workflows/android-ci.yml")
    sqlite_verifier = source("tooling/verify_update_sqlite.py")
    db_tests = source("test/app_database_test.dart")
    settings_tests = source("test/app_settings_test.dart")
    migration_tests = source("test/database_migration_test.dart")
    spreadsheet = source("lib/data/spreadsheet_exchange.dart")
    exchange_tests = source("test/spreadsheet_exchange_test.dart")
    exchange_screen = source("lib/screens/data_exchange_screen.dart")
    support_screen = source("lib/screens/support_screen.dart")

    require(bool(re.search(r"(?m)^version:\s*1\.2\.0\+4\s*$", pubspec)), "version is 1.3.0+5")
    require("excel: ^4.0.6" in pubspec and "csv: ^6.0.0" in pubspec, "Excel and CSV dependencies are declared")
    require("url_launcher: ^6.3.2" in pubspec, "support link dependency is declared")
    require("transaction((txn) async" in spreadsheet and "confirmDuplicates" in spreadsheet, "spreadsheet imports use preview and one atomic transaction")
    require("restoreBackupJson" not in spreadsheet, "spreadsheet imports do not invoke destructive JSON restore")
    require("duplicateCount" in spreadsheet, "spreadsheet duplicate detection exists")
    require("normalizes header names and dates" in exchange_tests, "spreadsheet validation tests are included")
    require("DataExchangeScreen" in exchange_screen and "SupportScreen" in support_screen, "data exchange and support screens are included")
    require("https://wa.me/967773436537" in support_screen and "abnalhag2022@gmail.com" in support_screen, "support contacts match approved details")
    require("shared_preferences: ^2.5.6" in pubspec, "persistent settings dependency is declared")
    require("static const _databaseVersion = 2;" in database and "onUpgrade: _upgradeSchema" in database, "database v1-to-v2 migration is wired")
    require("currency_code TEXT NOT NULL DEFAULT 'YER'" in database, "new currency column defaults legacy records to YER")
    require("currency_code = 'YER'" in database or "_validatedCurrency(currencyCode)" in database, "currency writes are validated")
    require("suggestProductNames" in database and "findExactProductName" in database, "local name suggestions and duplicate lookup exist")
    require("decoded['schemaVersion'] == 1 || decoded['schemaVersion'] == 2" in database, "backup restore accepts v1 and v2 archives")
    require("putIfAbsent('currency_code', () => 'YER')" in database, "legacy backup rows receive YER before validation")
    require("currencyCode: _currency" in entries and "_currency = AppSettings.instance.currency" in entries, "new transactions store the selected/default currency")
    require("if ((product.latestPurchaseCurrency ?? 'YER') != (product.latestSaleCurrency ?? 'YER'))" in details, "price differences are blocked across currencies")
    require("exportSettings()" in backup and "restoreSettings(restoredSettings)" in backup, "backup export/restore includes settings")
    require("_suggestionPanel" in form and "findExactProductName" in form, "product form presents historical names and duplicate warning")
    require("Application language" in source("lib/screens/settings_screen.dart"), "settings screen contains bilingual language option")
    require("themeMode: settings.themeMode" in source("lib/main.dart"), "main app applies persisted theme")
    require("python3 tooling/validate_update_package.py" in workflow and "python3 tooling/verify_update_sqlite.py" in workflow, "GitHub Actions runs both update checks")
    require("latest-price query returns separately stored purchase and sale currencies" in sqlite_verifier or "latest_price" in sqlite_verifier, "deep SQLite source verifier is included")
    require("legacy backup records to YER" in db_tests or "maps old backup records to YER" in db_tests, "database tests cover old backup currency fallback")
    require("persists language, theme, and preferred currency" in settings_tests, "settings persistence test is present")
    require("upgrades schema v1 without losing saved records" in migration_tests, "database migration preservation test is present")

    # Ensure there is exactly one currency column in each SELECT projection used for price histories.
    for method, table in (("getPurchaseHistory", "purchase_entries"), ("getSaleHistory", "sale_entries")):
        fragment = database.split(f"Future<List<Map<String, Object?>>> {method}", 1)[1]
        projection = re.search(r"SELECT(.*?)FROM\s+" + table, fragment, re.S)
        require(projection is not None and projection.group(1).count("currency_code") == 1,
                f"{method} returns currency_code exactly once")

    # Reject known runtime-constant mistakes caught during local static review.
    dart_sources = list((ROOT / "lib").rglob("*.dart")) + list((ROOT / "test").rglob("*.dart"))
    for path in dart_sources:
        content = path.read_text(encoding="utf-8")
        require("const TextStyle(color: Theme.of(context)" not in content, f"no const theme-dependent TextStyle in {path.relative_to(ROOT)}")
        require("const InputDecoration(labelText: appTextValue" not in content, f"no const runtime-localized InputDecoration in {path.relative_to(ROOT)}")

    # Exercise the exact ALTER statements against v1-shaped SQLite tables. No Flutter/Dart is needed for this check.
    migration = re.search(r"Future<void> _upgradeSchema\(.*?\) async \{(.*?)\n  \}", database, re.S)
    require(migration is not None, "migration function can be found for SQLite simulation")
    alters = re.findall(r'db\.execute\("(ALTER TABLE [^"]+)"\)', migration.group(1))
    require(len(alters) == 2, "migration contains exactly the two intended ALTER statements")
    connection = sqlite3.connect(":memory:")
    connection.executescript("""
      CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
      CREATE TABLE purchase_entries (id INTEGER PRIMARY KEY, product_id INTEGER, unit_price REAL, quantity REAL);
      CREATE TABLE sale_entries (id INTEGER PRIMARY KEY, product_id INTEGER, unit_price REAL, quantity REAL);
      INSERT INTO products VALUES (1, 'legacy item');
      INSERT INTO purchase_entries VALUES (1, 1, 12.5, 2);
      INSERT INTO sale_entries VALUES (1, 1, 19.5, 1);
    """)
    for statement in alters:
        connection.execute(statement)
    result = connection.execute("""
      SELECT p.name, pe.unit_price, pe.currency_code, se.unit_price, se.currency_code
      FROM products p JOIN purchase_entries pe ON pe.product_id=p.id
      JOIN sale_entries se ON se.product_id=p.id WHERE p.id=1
    """).fetchone()
    require(result == ("legacy item", 12.5, "YER", 19.5, "YER"), "SQLite migration preserves existing purchase/sale values and defaults currency to YER")

    print("Structural/SQLite update checks passed. This does not replace dart format, flutter analyze, flutter test, or an Android build.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(2)

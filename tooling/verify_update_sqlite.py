#!/usr/bin/env python3
"""Execute the actual schema/migration/search SQL from GIMI 1.1.0 with Python SQLite."""
from __future__ import annotations

import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "lib/data/app_database.dart"


def check(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)
    print(f"PASS: {message}")


def main() -> int:
    source = DB_PATH.read_text(encoding="utf-8")
    migration = re.search(
        r"Future<void> _upgradeSchema\(Database db, int oldVersion, int newVersion\) async \{(.*?)\n  \}",
        source,
        re.S,
    )
    check(migration is not None, "schema migration function exists")
    alter_statements = re.findall(r'db\.execute\("(ALTER TABLE [^"]+)"\)', migration.group(1))
    check(len(alter_statements) == 2, "migration adds currency columns to both history tables")

    # Create a representative v1 schema, populate both price-history tables, then run
    # the exact ALTER TABLE statements extracted from the current Dart source.
    old = sqlite3.connect(":memory:")
    old.executescript("""
      CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
      CREATE TABLE purchase_entries (id INTEGER PRIMARY KEY, product_id INTEGER, unit_price REAL, quantity REAL);
      CREATE TABLE sale_entries (id INTEGER PRIMARY KEY, product_id INTEGER, unit_price REAL, quantity REAL);
      INSERT INTO products VALUES (1, 'legacy item');
      INSERT INTO purchase_entries VALUES (1, 1, 12.5, 2);
      INSERT INTO sale_entries VALUES (1, 1, 19.5, 1);
    """)
    for statement in alter_statements:
        old.execute(statement)
    result = old.execute("""
      SELECT p.name, pe.unit_price, pe.currency_code, se.unit_price, se.currency_code
      FROM products p JOIN purchase_entries pe ON pe.product_id=p.id
      JOIN sale_entries se ON se.product_id=p.id WHERE p.id=1
    """).fetchone()
    check(result == ("legacy item", 12.5, "YER", 19.5, "YER"), "v1-to-v2 SQLite migration preserves rows and defaults historical currencies to YER")
    old.close()

    create_block = re.search(
        r"Future<void> _createSchema\(Database db, int version\) async \{(.*?)\n  \}\n\n  String _now",
        source,
        re.S,
    )
    check(create_block is not None, "schema creation function exists")
    create_statements = re.findall(r"await db\.execute\('''(.*?)'''\);", create_block.group(1), re.S)
    check(len(create_statements) == 3, "source defines products, purchases, and sales tables")
    connection = sqlite3.connect(":memory:")
    connection.execute("PRAGMA foreign_keys = ON")
    for statement in create_statements:
        connection.execute(statement)
    for statement in re.findall(r"await db\.execute\('(CREATE INDEX [^']+)'\);", create_block.group(1)):
        connection.execute(statement)

    connection.execute("""INSERT INTO products
      (id, name, search_name, search_code, search_category, unit, is_favorite,
       is_archived, created_at, updated_at)
      VALUES (1, 'Agency Bedford converter 75kW', 'agency bedford converter 75kw', '', '', 'piece', 0, 0, '2026-10-01', '2026-10-01')""")
    connection.execute("""INSERT INTO purchase_entries
      (product_id, purchase_date, unit_price, currency_code, quantity, created_at)
      VALUES (1, '2026-10-02', 125, 'USD', 2, '2026-10-02')""")
    connection.execute("""INSERT INTO sale_entries
      (product_id, sale_date, unit_price, currency_code, quantity, created_at)
      VALUES (1, '2026-10-03', 180, 'SAR', 1, '2026-10-03')""")

    select_match = re.search(r"String _productSelect\(\) => '''(.*?)'''", source, re.S)
    check(select_match is not None, "latest product query is extractable")
    cursor = connection.execute(select_match.group(1) + " WHERE p.id = ? LIMIT 1", (1,))
    latest = dict(zip([column[0] for column in cursor.description], cursor.fetchone()))
    check(latest.get("latest_purchase_currency") == "USD" and latest.get("latest_sale_currency") == "SAR",
          "latest-price query returns separately stored purchase and sale currencies")

    try:
        connection.execute("""INSERT INTO purchase_entries
          (product_id, purchase_date, unit_price, currency_code, quantity, created_at)
          VALUES (1, '2026-10-04', 10, 'EUR', 1, '2026-10-04')""")
        raise RuntimeError("Currency CHECK constraint unexpectedly accepted EUR.")
    except sqlite3.IntegrityError:
        print("PASS: SQLite CHECK constraint rejects unsupported currency EUR")

    suggestion_fragment = source.split("Future<List<Map<String, Object?>>> suggestProductNames", 1)[1]
    suggestion_match = re.search(r"return db\.rawQuery\(\s*'''(.*?)'''", suggestion_fragment, re.S)
    check(suggestion_match is not None, "substring suggestion query is extractable")
    suggested = connection.execute(suggestion_match.group(1), ("%bedford%", None, None, "bedford", 10)).fetchall()
    check(len(suggested) == 1 and suggested[0][1] == "Agency Bedford converter 75kW",
          "actual substring SQL returns the established item name")
    exact = connection.execute(
        "SELECT id FROM products WHERE search_name = ? AND (? IS NULL OR id != ?)",
        ("agency bedford converter 75kw", None, None),
    ).fetchone()
    check(exact == (1,), "exact-name duplicate lookup identifies an existing product")
    connection.close()

    print("SQLite source checks passed. These checks do not replace Dart analysis, Flutter tests, or Android APK build/signature verification.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(2)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:buy_price_assistant_gimi/data/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('upgrades schema v1 without losing saved records', () async {
    final directory = await Directory.systemTemp.createTemp('gimi_schema_v1_');
    AppDatabase? upgraded;
    try {
      final oldPath = p.join(directory.path, 'buy_price_assistant_gimi.db');
      final legacy = await databaseFactoryFfi.openDatabase(
        oldPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE products (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                search_name TEXT NOT NULL,
                code TEXT,
                search_code TEXT NOT NULL DEFAULT '',
                category TEXT,
                search_category TEXT NOT NULL DEFAULT '',
                unit TEXT NOT NULL DEFAULT 'قطعة',
                brand TEXT,
                notes TEXT,
                is_favorite INTEGER NOT NULL DEFAULT 0 CHECK (is_favorite IN (0, 1)),
                is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE purchase_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                product_id INTEGER NOT NULL,
                purchase_date TEXT NOT NULL,
                unit_price REAL NOT NULL CHECK (unit_price >= 0),
                quantity REAL NOT NULL CHECK (quantity > 0),
                supplier TEXT,
                invoice_number TEXT,
                notes TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT
              )
            ''');
            await db.execute('''
              CREATE TABLE sale_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                product_id INTEGER NOT NULL,
                sale_date TEXT NOT NULL,
                unit_price REAL NOT NULL CHECK (unit_price >= 0),
                quantity REAL NOT NULL CHECK (quantity > 0),
                customer TEXT,
                notes TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT
              )
            ''');
            await db.insert('products', <String, Object?>{
              'id': 1,
              'name': 'صنف قديم',
              'search_name': 'صنف قديم',
              'search_code': '',
              'search_category': '',
              'unit': 'قطعة',
              'is_favorite': 0,
              'is_archived': 0,
              'created_at': '2026-01-01T00:00:00',
              'updated_at': '2026-01-01T00:00:00',
            });
            await db.insert('purchase_entries', <String, Object?>{
              'id': 1,
              'product_id': 1,
              'purchase_date': '2026-01-02',
              'unit_price': 275.0,
              'quantity': 2.0,
              'supplier': 'مورد سابق',
              'created_at': '2026-01-02T00:00:00',
            });
            await db.insert('sale_entries', <String, Object?>{
              'id': 1,
              'product_id': 1,
              'sale_date': '2026-01-03',
              'unit_price': 350.0,
              'quantity': 1.0,
              'customer': 'عميل سابق',
              'created_at': '2026-01-03T00:00:00',
            });
          },
        ),
      );
      await legacy.close();

      upgraded = AppDatabase(
        factory: databaseFactoryFfi,
        databasePathProvider: () async => directory.path,
      );
      final product = await upgraded.getProduct(1);
      expect(product, isNotNull);
      expect(product!['name'], 'صنف قديم');
      expect(product['latest_purchase_price'], 275.0);
      expect(product['latest_sale_price'], 350.0);

      final purchases = await upgraded.getPurchaseHistory(1);
      final sales = await upgraded.getSaleHistory(1);
      expect(purchases, hasLength(1));
      expect(sales, hasLength(1));
      expect(purchases.single['currency_code'], 'YER');
      expect(sales.single['currency_code'], 'YER');
    } finally {
      await upgraded?.close();
      await directory.delete(recursive: true);
    }
  });
}

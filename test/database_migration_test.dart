import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:buy_price_assistant_gimi/data/app_database.dart';

/// Schemas exactly as earlier releases created them (from git history), so the
/// migration is tested against what is really on users' phones.
const _v1Products = '''
  CREATE TABLE products (
    id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, search_name TEXT NOT NULL,
    code TEXT, search_code TEXT NOT NULL DEFAULT '', category TEXT,
    search_category TEXT NOT NULL DEFAULT '', unit TEXT NOT NULL DEFAULT 'قطعة', brand TEXT, notes TEXT,
    is_favorite INTEGER NOT NULL DEFAULT 0 CHECK (is_favorite IN (0, 1)),
    is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''';
const _v1Purchases = '''
  CREATE TABLE purchase_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, purchase_date TEXT NOT NULL,
    unit_price REAL NOT NULL CHECK (unit_price >= 0), quantity REAL NOT NULL CHECK (quantity > 0),
    supplier TEXT, invoice_number TEXT, notes TEXT, created_at TEXT NOT NULL,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT)''';
const _v1Sales = '''
  CREATE TABLE sale_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, sale_date TEXT NOT NULL,
    unit_price REAL NOT NULL CHECK (unit_price >= 0), quantity REAL NOT NULL CHECK (quantity > 0),
    customer TEXT, notes TEXT, created_at TEXT NOT NULL,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT)''';
const _v3Purchases = '''
  CREATE TABLE purchase_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, purchase_date TEXT NOT NULL,
    unit_price REAL NOT NULL CHECK (unit_price >= 0),
    currency_code TEXT NOT NULL DEFAULT 'YER' CHECK (currency_code IN ('YER', 'SAR', 'USD')),
    quantity REAL NOT NULL CHECK (quantity > 0), supplier TEXT, invoice_number TEXT, notes TEXT,
    created_at TEXT NOT NULL, FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT)''';
const _v3Sales = '''
  CREATE TABLE sale_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, sale_date TEXT NOT NULL,
    unit_price REAL NOT NULL CHECK (unit_price >= 0),
    currency_code TEXT NOT NULL DEFAULT 'YER' CHECK (currency_code IN ('YER', 'SAR', 'USD')),
    quantity REAL NOT NULL CHECK (quantity > 0), customer TEXT, notes TEXT, created_at TEXT NOT NULL,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT)''';
const _indexes = [
  'CREATE INDEX idx_products_search_name ON products(search_name)',
  'CREATE INDEX idx_products_search_code ON products(search_code)',
  'CREATE INDEX idx_purchase_product_date ON purchase_entries(product_id, purchase_date DESC, id DESC)',
  'CREATE INDEX idx_sale_product_date ON sale_entries(product_id, sale_date DESC, id DESC)',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory directory;
  late String path;
  final opened = <AppDatabase>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gimi_migration_');
    path = p.join(directory.path, 'buy_price_assistant_gimi.db');
  });

  tearDown(() async {
    for (final db in opened) {
      await db.close();
    }
    opened.clear();
    await directory.delete(recursive: true);
  });

  AppDatabase app() {
    final db = AppDatabase(factory: databaseFactoryFfi, databasePathProvider: () async => directory.path);
    opened.add(db);
    return db;
  }

  /// Creates a database as an old release left it, with one product whose
  /// stored search name still has Arabic-Indic digits (as before v3).
  Future<void> createLegacy(int version) async {
    final legacy = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(
      version: version,
      onCreate: (db, _) async {
        await db.execute(_v1Products);
        await db.execute(version == 1 ? _v1Purchases : _v3Purchases);
        await db.execute(version == 1 ? _v1Sales : _v3Sales);
        for (final index in _indexes) {
          await db.execute(index);
        }
        await db.insert('products', {
          'id': 1, 'name': 'غطاس ٥٥ كيلوواط', 'search_name': 'غطاس ٥٥ كيلوواط', 'search_code': '',
          'search_category': '', 'unit': 'قطعة', 'is_favorite': 0, 'is_archived': 0,
          'created_at': '2026-01-01T00:00:00', 'updated_at': '2026-01-01T00:00:00',
        });
        await db.insert('purchase_entries', {
          'id': 1, 'product_id': 1, 'purchase_date': '2026-01-02', 'unit_price': 275.0, 'quantity': 2.0,
          'supplier': 'مورد سابق', 'created_at': '2026-01-02T00:00:00',
          if (version > 1) 'currency_code': 'SAR',
        });
        await db.insert('sale_entries', {
          'id': 1, 'product_id': 1, 'sale_date': '2026-01-03', 'unit_price': 350.0, 'quantity': 1.0,
          'customer': 'عميل سابق', 'created_at': '2026-01-03T00:00:00',
          if (version > 1) 'currency_code': 'SAR',
        });
      },
    ));
    await legacy.close();
  }

  Future<Map<String, Set<String>>> columnsOf(Database db) async {
    final result = <String, Set<String>>{};
    for (final table in ['products', 'purchase_entries', 'sale_entries', 'import_batches']) {
      final info = await db.rawQuery('PRAGMA table_info($table)');
      result[table] = info.map((row) => row['name']! as String).toSet();
    }
    return result;
  }

  Future<Set<String>> indexesOf(Database db) async =>
      (await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%'"))
          .map((row) => row['name']! as String)
          .toSet();

  for (final version in [1, 2, 3]) {
    test('upgrades schema v$version to v${AppDatabase.schemaVersion} without losing records', () async {
      await createLegacy(version);
      final upgraded = app();
      final product = await upgraded.getProduct(1);
      expect(product!['name'], 'غطاس ٥٥ كيلوواط');
      expect(product['latest_purchase_price'], 275.0);
      expect(product['latest_sale_price'], 350.0);
      final currency = version == 1 ? 'YER' : 'SAR';
      expect((await upgraded.getPurchaseHistory(1)).single['currency_code'], currency);
      expect((await upgraded.getSaleHistory(1)).single['currency_code'], currency);

      // Search columns are recomputed, so Latin and Arabic-Indic digits both find it.
      expect(await upgraded.searchProducts('غطاس 55'), hasLength(1));
      expect(await upgraded.searchProducts('٥٥'), hasLength(1));
      // The v5 search index is built from the existing purchase and sale records.
      expect(await upgraded.searchProducts('مورد سابق'), hasLength(1));
      expect(await upgraded.searchProducts('عميل سابق 2026-01-03'), hasLength(1));

      // The upgraded database has every column and index a fresh install has.
      final freshDir = await Directory.systemTemp.createTemp('gimi_fresh_');
      addTearDown(() => freshDir.delete(recursive: true));
      final fresh = AppDatabase(factory: databaseFactoryFfi, databasePathProvider: () async => freshDir.path);
      addTearDown(fresh.close);
      expect(await columnsOf(await upgraded.database), await columnsOf(await fresh.database));
      expect(await indexesOf(await upgraded.database), await indexesOf(await fresh.database));
    });
  }

  test('upgrading again after an older app lowered the version does not fail', () async {
    await createLegacy(3);
    final first = app();
    await first.recordPurchase(productId: 1, date: '2026-02-01', unitPrice: 300, quantity: 1);
    await first.close();
    // Older releases have no onDowngrade: sqflite silently writes their version.
    final raw = await databaseFactoryFfi.openDatabase(path);
    await raw.setVersion(3);
    // The older app writes a record without knowing about the search index.
    await raw.insert('purchase_entries', {
      'product_id': 1, 'purchase_date': '2026-02-02', 'unit_price': 310.0, 'currency_code': 'SAR',
      'quantity': 1.0, 'supplier': 'مورد الإصدار القديم', 'created_at': '2026-02-02T00:00:00',
    });
    await raw.close();

    final again = app();
    expect(await again.getPurchaseHistory(1), hasLength(3));
    expect(await again.searchProducts('القديم'), hasLength(1), reason: 'the index is rebuilt on upgrade');
    final columns = await columnsOf(await again.database);
    expect(columns['purchase_entries']!.where((c) => c == 'import_batch_id'), hasLength(1));
  });

  test('refuses to open a database from a newer app and leaves it untouched', () async {
    await createLegacy(3);
    final raw = await databaseFactoryFfi.openDatabase(path);
    await raw.setVersion(99);
    await raw.close();

    await expectLater(app().database, throwsA(isA<DatabaseVersionTooNewException>()));
    final check = await databaseFactoryFfi.openDatabase(path);
    expect(await check.getVersion(), 99);
    expect(await check.query('purchase_entries'), hasLength(1));
    await check.close();
  });

  test('every write path rejects unsupported currencies on upgraded databases', () async {
    // Upgraded v1 tables have no currency CHECK constraint (SQLite cannot add
    // one to an existing column); the application validates instead.
    await createLegacy(1);
    final upgraded = app();
    await expectLater(
      upgraded.recordPurchase(productId: 1, date: '2026-02-01', unitPrice: 1, quantity: 1, currencyCode: 'EUR'),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      upgraded.updateSaleEntry(id: 1, productId: 1, date: '2026-02-01', unitPrice: 1, quantity: 1, currencyCode: 'EUR'),
      throwsA(isA<ArgumentError>()),
    );
    expect((await upgraded.getPurchaseHistory(1)).single['currency_code'], 'YER');
  });
}

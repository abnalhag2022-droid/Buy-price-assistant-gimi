import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common/sqlite_api.dart';

import '../utils/app_helpers.dart';
import '../utils/currencies.dart';
import 'backup_validator.dart';

export 'backup_validator.dart' show BackupContents, ImportUndoResult;

/// Thrown when the database file was written by a newer app version.
/// Opening it with an older schema could silently corrupt data, so the app stops.
class DatabaseVersionTooNewException implements Exception {
  const DatabaseVersionTooNewException(this.fileVersion, this.appVersion);
  final int fileVersion;
  final int appVersion;

  @override
  String toString() =>
      'قاعدة البيانات أنشأها إصدار أحدث من التطبيق (مخطط $fileVersion، والمدعوم $appVersion). ثبّت الإصدار الأحدث؛ لم تُعدَّل البيانات.';
}

class AppDatabase {
  AppDatabase({
    DatabaseFactory? factory,
    Future<String> Function()? databasePathProvider,
  })  : _factory = factory ?? sqflite.databaseFactory,
        _databasePathProvider = databasePathProvider ?? sqflite.getDatabasesPath;

  static AppDatabase _instance = AppDatabase();

  /// The database used by the app. Tests may replace it with an in-memory one.
  static AppDatabase get instance => _instance;

  @visibleForTesting
  static set instance(AppDatabase value) => _instance = value;

  static const _databaseName = 'buy_price_assistant_gimi.db';

  /// Schema history:
  /// 1 = initial; 2 = currency per entry; 3 = digit-normalized search columns;
  /// 4 = import batches (import_batch_id + import_batches table).
  /// Never redefine a released version: add a new one instead.
  static const int schemaVersion = 4;

  final DatabaseFactory _factory;
  final Future<String> Function() _databasePathProvider;
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final directory = await _databasePathProvider();
    final path = directory == ':memory:' ? directory : p.join(directory, _databaseName);
    _database = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
        onDowngrade: (db, oldVersion, newVersion) async {
          throw DatabaseVersionTooNewException(oldVersion, newVersion);
        },
      ),
    );
    return _database!;
  }

  /// Every step is idempotent: a user who downgraded with an older app (which
  /// silently lowers user_version) and upgrades again must not hit
  /// "duplicate column" errors.
  Future<void> _upgradeSchema(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _addColumnIfMissing(db, 'purchase_entries', 'currency_code', "TEXT NOT NULL DEFAULT 'YER'");
      await _addColumnIfMissing(db, 'sale_entries', 'currency_code', "TEXT NOT NULL DEFAULT 'YER'");
    }
    if (oldVersion < 4) {
      await _addColumnIfMissing(db, 'products', 'import_batch_id', 'TEXT');
      await _addColumnIfMissing(db, 'purchase_entries', 'import_batch_id', 'TEXT');
      await _addColumnIfMissing(db, 'sale_entries', 'import_batch_id', 'TEXT');
      await _createImportBatchObjects(db);
    }
    // Search columns depend on normalizeForSearch, which changed in v3.
    // Recomputing them is cheap and keeps every upgraded install consistent.
    await _recomputeProductSearchColumns(db);
  }

  Future<void> _addColumnIfMissing(DatabaseExecutor db, String table, String column, String definition) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    if (info.any((row) => row['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  Future<void> _createImportBatchObjects(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS import_batches (
        id TEXT PRIMARY KEY,
        file_name TEXT,
        created_at TEXT NOT NULL,
        products_added INTEGER NOT NULL DEFAULT 0,
        entries_added INTEGER NOT NULL DEFAULT 0,
        unarchived_product_ids TEXT,
        undone_at TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_purchase_import_batch ON purchase_entries(import_batch_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_import_batch ON sale_entries(import_batch_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_import_batch ON products(import_batch_id)');
  }

  Future<void> _recomputeProductSearchColumns(DatabaseExecutor db) async {
    final products = await db.query('products', columns: ['id', 'name', 'code', 'category']);
    for (final product in products) {
      await db.update('products', {
        'search_name': normalizeForSearch(product['name'] as String? ?? ''),
        'search_code': normalizeForSearch(product['code'] as String? ?? ''),
        'search_category': normalizeForSearch(product['category'] as String? ?? ''),
      }, where: 'id = ?', whereArgs: [product['id']]);
    }
  }

  Future<void> _createSchema(Database db, int version) async {
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
        updated_at TEXT NOT NULL,
        import_batch_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE purchase_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        purchase_date TEXT NOT NULL,
        unit_price REAL NOT NULL CHECK (unit_price >= 0),
        currency_code TEXT NOT NULL DEFAULT 'YER' CHECK (currency_code IN ('YER', 'SAR', 'USD')),
        quantity REAL NOT NULL CHECK (quantity > 0),
        supplier TEXT,
        invoice_number TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        import_batch_id TEXT,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT
      )
    ''');
    await db.execute('''
      CREATE TABLE sale_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        sale_date TEXT NOT NULL,
        unit_price REAL NOT NULL CHECK (unit_price >= 0),
        currency_code TEXT NOT NULL DEFAULT 'YER' CHECK (currency_code IN ('YER', 'SAR', 'USD')),
        quantity REAL NOT NULL CHECK (quantity > 0),
        customer TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        import_batch_id TEXT,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT
      )
    ''');
    await db.execute('CREATE INDEX idx_products_search_name ON products(search_name)');
    await db.execute('CREATE INDEX idx_products_search_code ON products(search_code)');
    await db.execute('CREATE INDEX idx_purchase_product_date ON purchase_entries(product_id, purchase_date DESC, id DESC)');
    await db.execute('CREATE INDEX idx_sale_product_date ON sale_entries(product_id, sale_date DESC, id DESC)');
    await _createImportBatchObjects(db);
  }

  String _now() => DateTime.now().toIso8601String();

  String _requiredText(String value, String fieldName) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) throw ArgumentError('$fieldName مطلوب.');
    return trimmed;
  }

  void _validateEntry({required String date, required double price, required double quantity}) {
    final parsedDate = DateTime.tryParse(date);
    if (parsedDate == null || toIsoDate(parsedDate) != date) {
      throw ArgumentError('التاريخ غير صحيح؛ استخدم صيغة YYYY-MM-DD.');
    }
    if (!price.isFinite || price < 0) throw ArgumentError('السعر يجب ألا يكون سالبًا.');
    if (!quantity.isFinite || quantity <= 0) throw ArgumentError('الكمية يجب أن تكون أكبر من صفر.');
  }

  Future<int> saveProduct({
    int? id,
    required String name,
    String? code,
    String? category,
    String unit = 'قطعة',
    String? brand,
    String? notes,
    bool isFavorite = false,
  }) async {
    final safeName = _requiredText(name, 'اسم الصنف');
    final safeUnit = unit.trim().isEmpty ? 'قطعة' : unit.trim();
    final timestamp = _now();
    final values = <String, Object?>{
      'name': safeName,
      'search_name': normalizeForSearch(safeName),
      'code': _nullableTrim(code),
      'search_code': normalizeForSearch(code ?? ''),
      'category': _nullableTrim(category),
      'search_category': normalizeForSearch(category ?? ''),
      'unit': safeUnit,
      'brand': _nullableTrim(brand),
      'notes': _nullableTrim(notes),
      'is_favorite': isFavorite ? 1 : 0,
      'updated_at': timestamp,
    };
    final db = await database;
    if (id == null) {
      values['created_at'] = timestamp;
      return db.insert('products', values);
    }
    final count = await db.update('products', values, where: 'id = ? AND is_archived = 0', whereArgs: [id]);
    if (count == 0) throw StateError('لم يتم العثور على الصنف المطلوب لتعديله.');
    return id;
  }

  String? _nullableTrim(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  String _productSelect() => '''
    SELECT p.*,
      (SELECT pe.unit_price FROM purchase_entries pe WHERE pe.product_id = p.id
       ORDER BY pe.purchase_date DESC, pe.id DESC LIMIT 1) AS latest_purchase_price,
      (SELECT pe.purchase_date FROM purchase_entries pe WHERE pe.product_id = p.id
       ORDER BY pe.purchase_date DESC, pe.id DESC LIMIT 1) AS latest_purchase_date,
      (SELECT pe.currency_code FROM purchase_entries pe WHERE pe.product_id = p.id
       ORDER BY pe.purchase_date DESC, pe.id DESC LIMIT 1) AS latest_purchase_currency,
      (SELECT COUNT(*) FROM purchase_entries pe WHERE pe.product_id = p.id) AS purchase_count,
      (SELECT se.unit_price FROM sale_entries se WHERE se.product_id = p.id
       ORDER BY se.sale_date DESC, se.id DESC LIMIT 1) AS latest_sale_price,
      (SELECT se.sale_date FROM sale_entries se WHERE se.product_id = p.id
       ORDER BY se.sale_date DESC, se.id DESC LIMIT 1) AS latest_sale_date,
      (SELECT se.currency_code FROM sale_entries se WHERE se.product_id = p.id
       ORDER BY se.sale_date DESC, se.id DESC LIMIT 1) AS latest_sale_currency,
      (SELECT COUNT(*) FROM sale_entries se WHERE se.product_id = p.id) AS sale_count
    FROM products p
  ''';

  String _sqlNormalizeDigits(String expression) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var sql = expression;
    for (var i = 0; i < 10; i++) {
      sql = "replace($sql, '${arabic[i]}', '$i')";
      sql = "replace($sql, '${persian[i]}', '$i')";
    }
    return sql;
  }

  Future<List<Map<String, Object?>>> searchProducts(
    String query, {
    String? category,
    String? brand,
    String? supplier,
  }) async {
    final db = await database;
    final normalized = normalizeForSearch(query);
    final terms = normalized.split(RegExp(r'\s+')).where((v) => v.isNotEmpty).toList();
    final args = <Object?>[];
    final conditions = <String>['p.is_archived = 0'];
    for (final term in terms) {
      final termPattern = '%${escapeLikePattern(term)}%';
      conditions.add('''(
        p.search_name LIKE ? ESCAPE '!' OR p.search_code LIKE ? ESCAPE '!' OR
        p.search_category LIKE ? ESCAPE '!' OR ${_sqlNormalizeDigits("lower(coalesce(p.brand, ''))")} LIKE ? ESCAPE '!' OR
        ${_sqlNormalizeDigits("lower(coalesce(p.notes, ''))")} LIKE ? ESCAPE '!' OR
        EXISTS (SELECT 1 FROM purchase_entries pe WHERE pe.product_id = p.id AND (
          ${_sqlNormalizeDigits("lower(coalesce(pe.supplier, ''))")} LIKE ? ESCAPE '!' OR
          ${_sqlNormalizeDigits("lower(coalesce(pe.notes, ''))")} LIKE ? ESCAPE '!' OR
          coalesce(pe.purchase_date, '') LIKE ? ESCAPE '!' OR cast(pe.unit_price as text) LIKE ? ESCAPE '!')) OR
        EXISTS (SELECT 1 FROM sale_entries se WHERE se.product_id = p.id AND (
          ${_sqlNormalizeDigits("lower(coalesce(se.customer, ''))")} LIKE ? ESCAPE '!' OR
          ${_sqlNormalizeDigits("lower(coalesce(se.notes, ''))")} LIKE ? ESCAPE '!' OR
          coalesce(se.sale_date, '') LIKE ? ESCAPE '!' OR cast(se.unit_price as text) LIKE ? ESCAPE '!'))
      )''');
      args.addAll(List<Object?>.filled(5, termPattern));
      args.addAll(List<Object?>.filled(4, termPattern));
      args.addAll(List<Object?>.filled(4, termPattern));
    }
    if (category != null && category.isNotEmpty) {
      conditions.add('p.search_category = ?');
      args.add(normalizeForSearch(category));
    }
    if (brand != null && brand.isNotEmpty) {
      conditions.add('lower(coalesce(p.brand, "")) = lower(?)');
      args.add(brand);
    }
    if (supplier != null && supplier.isNotEmpty) {
      conditions.add("EXISTS (SELECT 1 FROM purchase_entries pe WHERE pe.product_id = p.id AND lower(coalesce(pe.supplier, '')) = lower(?))");
      args.add(supplier);
    }
    final noteChecks = <String>[];
    final noteArgs = <Object?>[];
    for (final term in terms) {
      final notePattern = '%${escapeLikePattern(term)}%';
      noteChecks.add('''(
        ${_sqlNormalizeDigits("lower(coalesce(p.notes, ''))")} LIKE ? ESCAPE '!' OR
        EXISTS (SELECT 1 FROM purchase_entries pn WHERE pn.product_id = p.id AND
          ${_sqlNormalizeDigits("lower(coalesce(pn.notes, ''))")} LIKE ? ESCAPE '!') OR
        EXISTS (SELECT 1 FROM sale_entries sn WHERE sn.product_id = p.id AND
          ${_sqlNormalizeDigits("lower(coalesce(sn.notes, ''))")} LIKE ? ESCAPE '!')
      )''');
      noteArgs.addAll(List<Object?>.filled(3, notePattern));
    }
    final noteSelect = noteChecks.isEmpty
        ? '0 AS search_match_notes'
        : 'CASE WHEN ${noteChecks.join(' OR ')} THEN 1 ELSE 0 END AS search_match_notes';
    final select = _productSelect().replaceFirst(
      'FROM products p',
      ', $noteSelect FROM products p',
    );
    return db.rawQuery(
      '$select WHERE ${conditions.join(' AND ')} ORDER BY p.is_favorite DESC, p.updated_at DESC, p.name COLLATE NOCASE ASC LIMIT 250',
      [...noteArgs, ...args],
    );
  }

  Future<List<String>> getDistinctBrands() async {
    final db = await database;
    final rows = await db.rawQuery("SELECT DISTINCT brand FROM products WHERE is_archived = 0 AND brand IS NOT NULL AND trim(brand) <> '' ORDER BY brand COLLATE NOCASE");
    return rows.map((r) => r['brand']! as String).toList();
  }

  Future<List<String>> getDistinctSuppliers() async {
    final db = await database;
    final rows = await db.rawQuery("SELECT DISTINCT supplier FROM purchase_entries WHERE supplier IS NOT NULL AND trim(supplier) <> '' ORDER BY supplier COLLATE NOCASE");
    return rows.map((r) => r['supplier']! as String).toList();
  }

  Future<List<String>> getDistinctCategories() async {
    final db = await database;
    final rows = await db.rawQuery("SELECT DISTINCT category FROM products WHERE is_archived = 0 AND category IS NOT NULL AND trim(category) <> '' ORDER BY category COLLATE NOCASE");
    return rows.map((r) => r['category']! as String).toList();
  }

  /// Suggestions include archived products so staff can reuse established naming patterns.
  Future<List<Map<String, Object?>>> suggestProductNames(
    String query, {int? excludeId, int limit = 12}
  ) async {
    final normalized = normalizeForSearch(query);
    if (normalized.length < 2) return <Map<String, Object?>>[];
    final db = await database;
    final pattern = '%${escapeLikePattern(normalized)}%';
    return db.rawQuery(
      '''SELECT id, name, category, unit, brand, is_archived, search_name, updated_at
         FROM products WHERE search_name LIKE ? ESCAPE '!'
           AND (? IS NULL OR id != ?)
         ORDER BY CASE WHEN search_name = ? THEN 0 ELSE 1 END, is_archived ASC,
                  updated_at DESC, name COLLATE NOCASE ASC LIMIT ?''',
      [pattern, excludeId, excludeId, normalized, limit.clamp(1, 50)],
    );
  }

  Future<Map<String, Object?>?> findExactProductName(String name, {int? excludeId}) async {
    final normalized = normalizeForSearch(name);
    if (normalized.isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'products', columns: ['id', 'name', 'category', 'unit', 'is_archived'],
      where: 'search_name = ? AND (? IS NULL OR id != ?)',
      whereArgs: [normalized, excludeId, excludeId],
      orderBy: 'is_archived ASC, updated_at DESC', limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  String _validatedCurrency(String currencyCode) {
    final code = AppCurrencies.tryParse(currencyCode);
    if (code == null) throw ArgumentError('العملة غير مدعومة: $currencyCode');
    return code;
  }

  Future<Map<String, Object?>?> getProduct(int id) async {
    final db = await database;
    final result = await db.rawQuery('${_productSelect()} WHERE p.id = ? LIMIT 1', [id]);
    return result.isEmpty ? null : result.first;
  }

  Future<void> setFavorite(int id, bool favorite) async {
    final db = await database;
    await db.update(
      'products',
      {'is_favorite': favorite ? 1 : 0, 'updated_at': _now()},
      where: 'id = ? AND is_archived = 0',
      whereArgs: [id],
    );
  }

  Future<void> archiveProduct(int id) async {
    final db = await database;
    await db.update(
      'products',
      {'is_archived': 1, 'updated_at': _now()},
      where: 'id = ? AND is_archived = 0',
      whereArgs: [id],
    );
  }

  Future<int> recordPurchase({
    required int productId,
    required String date,
    required double unitPrice,
    required double quantity,
    String? supplier,
    String? invoiceNumber,
    String? notes,
    String currencyCode = 'YER',
  }) async {
    _validateEntry(date: date, price: unitPrice, quantity: quantity);
    return _recordEntry('purchase_entries', {
      'product_id': productId,
      'purchase_date': date,
      'unit_price': unitPrice,
      'currency_code': _validatedCurrency(currencyCode),
      'quantity': quantity,
      'supplier': _nullableTrim(supplier),
      'invoice_number': _nullableTrim(invoiceNumber),
      'notes': _nullableTrim(notes),
      'created_at': _now(),
    });
  }

  Future<int> recordSale({
    required int productId,
    required String date,
    required double unitPrice,
    required double quantity,
    String? customer,
    String? notes,
    String currencyCode = 'YER',
  }) async {
    _validateEntry(date: date, price: unitPrice, quantity: quantity);
    return _recordEntry('sale_entries', {
      'product_id': productId,
      'sale_date': date,
      'unit_price': unitPrice,
      'currency_code': _validatedCurrency(currencyCode),
      'quantity': quantity,
      'customer': _nullableTrim(customer),
      'notes': _nullableTrim(notes),
      'created_at': _now(),
    });
  }


  /// Updates one purchase record while preserving its ID and created_at.
  Future<void> updatePurchaseEntry({
    required int id,
    required int productId,
    required String date,
    required double unitPrice,
    required double quantity,
    String? supplier,
    String? invoiceNumber,
    String? notes,
    String currencyCode = 'YER',
  }) async {
    _validateEntry(date: date, price: unitPrice, quantity: quantity);
    await _updateHistoryEntry('purchase_entries', id: id, productId: productId, values: {
      'purchase_date': date,
      'unit_price': unitPrice,
      'currency_code': _validatedCurrency(currencyCode),
      'quantity': quantity,
      'supplier': _nullableTrim(supplier),
      'invoice_number': _nullableTrim(invoiceNumber),
      'notes': _nullableTrim(notes),
    });
  }

  /// Updates one sale record while preserving its ID and created_at.
  Future<void> updateSaleEntry({
    required int id,
    required int productId,
    required String date,
    required double unitPrice,
    required double quantity,
    String? customer,
    String? notes,
    String currencyCode = 'YER',
  }) async {
    _validateEntry(date: date, price: unitPrice, quantity: quantity);
    await _updateHistoryEntry('sale_entries', id: id, productId: productId, values: {
      'sale_date': date,
      'unit_price': unitPrice,
      'currency_code': _validatedCurrency(currencyCode),
      'quantity': quantity,
      'customer': _nullableTrim(customer),
      'notes': _nullableTrim(notes),
    });
  }

  Future<void> deletePurchaseEntry({required int id, required int productId}) =>
      _deleteHistoryEntry('purchase_entries', id: id, productId: productId);

  Future<void> deleteSaleEntry({required int id, required int productId}) =>
      _deleteHistoryEntry('sale_entries', id: id, productId: productId);

  Future<void> _updateHistoryEntry(
    String table, {
    required int id,
    required int productId,
    required Map<String, Object?> values,
  }) async {
    if (table != 'purchase_entries' && table != 'sale_entries') {
      throw ArgumentError.value(table, 'table', 'جدول غير مسموح.');
    }
    final db = await database;
    final count = await db.update(
      table,
      values,
      where: 'id = ? AND product_id = ?',
      whereArgs: [id, productId],
    );
    if (count == 0) {
      throw StateError('لم يتم العثور على العملية المطلوبة لتعديلها.');
    }
  }

  Future<void> _deleteHistoryEntry(
    String table, {
    required int id,
    required int productId,
  }) async {
    if (table != 'purchase_entries' && table != 'sale_entries') {
      throw ArgumentError.value(table, 'table', 'جدول غير مسموح.');
    }
    final db = await database;
    final count = await db.delete(
      table,
      where: 'id = ? AND product_id = ?',
      whereArgs: [id, productId],
    );
    if (count == 0) {
      throw StateError('لم يتم العثور على العملية المطلوبة لحذفها.');
    }
  }

  Future<int> _recordEntry(String table, Map<String, Object?> values) async {
    if (table != 'purchase_entries' && table != 'sale_entries') {
      throw ArgumentError.value(table, 'table', 'جدول غير مسموح.');
    }
    final db = await database;
    final product = await db.query(
      'products',
      columns: ['id'],
      where: 'id = ? AND is_archived = 0',
      whereArgs: [values['product_id']],
      limit: 1,
    );
    if (product.isEmpty) throw StateError('الصنف غير موجود أو مؤرشف.');
    return db.insert(table, values);
  }

  Future<List<Map<String, Object?>>> getPurchaseHistory(int productId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT id, product_id, purchase_date AS entry_date, unit_price, quantity,
             supplier AS party_name, invoice_number, notes, created_at, currency_code
      FROM purchase_entries WHERE product_id = ?
      ORDER BY purchase_date DESC, id DESC
    ''', [productId]);
  }

  Future<List<Map<String, Object?>>> getSaleHistory(int productId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT id, product_id, sale_date AS entry_date, unit_price, quantity,
             customer AS party_name, NULL AS invoice_number, notes, created_at, currency_code
      FROM sale_entries WHERE product_id = ?
      ORDER BY sale_date DESC, id DESC
    ''', [productId]);
  }

  static const String backupFormatName = 'buy_price_assistant_gimi_backup';

  /// Backup file versions: 1 = no currency; 2 = currency per entry;
  /// 3 = import batches, SHA-256 checksum, derived search columns omitted.
  static const int backupSchemaVersion = 3;

  static const Map<String, List<String>> _backupColumns = <String, List<String>>{
    'products': <String>[
      'id', 'name', 'code', 'category', 'unit', 'brand', 'notes', 'is_favorite',
      'is_archived', 'created_at', 'updated_at', 'import_batch_id',
    ],
    'purchase_entries': <String>[
      'id', 'product_id', 'purchase_date', 'unit_price', 'currency_code', 'quantity',
      'supplier', 'invoice_number', 'notes', 'created_at', 'import_batch_id',
    ],
    'sale_entries': <String>[
      'id', 'product_id', 'sale_date', 'unit_price', 'currency_code', 'quantity',
      'customer', 'notes', 'created_at', 'import_batch_id',
    ],
    'import_batches': <String>[
      'id', 'file_name', 'created_at', 'products_added', 'entries_added',
      'unarchived_product_ids', 'undone_at',
    ],
  };

  /// Exports all user data, including archived products, every price record
  /// and import-batch history, with counts and a SHA-256 checksum of `tables`.
  Future<String> exportBackupJson() async {
    final db = await database;
    final tables = <String, Object?>{};
    final counts = <String, int>{};
    for (final entry in _backupColumns.entries) {
      final rows = await db.query(
        entry.key,
        columns: entry.value,
        orderBy: entry.key == 'import_batches' ? 'created_at ASC, id ASC' : 'id ASC',
      );
      tables[entry.key] = rows;
      counts[entry.key] = rows.length;
    }
    final payload = <String, Object?>{
      'format': backupFormatName,
      'schemaVersion': backupSchemaVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'tables': tables,
      'counts': counts,
      'checksum': <String, String>{
        'algorithm': 'sha256',
        'value': BackupValidator.checksumOf(tables),
      },
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Replaces all local records atomically after validating the whole file.
  /// Any validation or database error leaves the existing data untouched.
  /// Derived search columns are always recomputed from the restored values.
  Future<BackupContents> restoreBackupJson(String source) async {
    final contents = BackupValidator.parse(source);
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('purchase_entries');
      await txn.delete('sale_entries');
      await txn.delete('products');
      await txn.delete('import_batches');
      for (final row in contents.products) {
        final name = row['name']! as String;
        final code = row['code'] as String?;
        final category = row['category'] as String?;
        await txn.insert('products', <String, Object?>{
          ...row,
          'search_name': normalizeForSearch(name),
          'search_code': normalizeForSearch(code ?? ''),
          'search_category': normalizeForSearch(category ?? ''),
        });
      }
      for (final row in contents.purchases) {
        await txn.insert('purchase_entries', row);
      }
      for (final row in contents.sales) {
        await txn.insert('sale_entries', row);
      }
      for (final row in contents.importBatches) {
        await txn.insert('import_batches', row);
      }
    });
    return contents;
  }

  /// Most recent import batches first.
  Future<List<Map<String, Object?>>> listImportBatches({int limit = 20}) async {
    final db = await database;
    return db.query('import_batches', orderBy: 'created_at DESC, id DESC', limit: limit);
  }

  /// Removes everything a spreadsheet import added: its price entries, the
  /// products it created (only when no other entry references them) and it
  /// re-archives products the import un-archived. Other data is never touched.
  Future<ImportUndoResult> undoImportBatch(String batchId) async {
    final db = await database;
    return db.transaction((txn) async {
      final batches = await txn.query('import_batches', where: 'id = ?', whereArgs: [batchId], limit: 1);
      if (batches.isEmpty) throw StateError('دفعة الاستيراد غير موجودة.');
      final batch = batches.single;
      if (batch['undone_at'] != null) throw StateError('تم التراجع عن هذه الدفعة سابقًا.');

      final purchases = await txn.delete('purchase_entries', where: 'import_batch_id = ?', whereArgs: [batchId]);
      final sales = await txn.delete('sale_entries', where: 'import_batch_id = ?', whereArgs: [batchId]);
      final created = await txn.query('products', columns: ['id'], where: 'import_batch_id = ?', whereArgs: [batchId]);
      var removed = 0;
      var kept = 0;
      for (final product in created) {
        final id = product['id']! as int;
        final used = await txn.rawQuery(
          'SELECT 1 FROM purchase_entries WHERE product_id = ? UNION ALL SELECT 1 FROM sale_entries WHERE product_id = ? LIMIT 1',
          [id, id],
        );
        if (used.isEmpty) {
          removed += await txn.delete('products', where: 'id = ?', whereArgs: [id]);
        } else {
          kept++;
        }
      }
      var rearchived = 0;
      final unarchived = batch['unarchived_product_ids'] as String?;
      if (unarchived != null && unarchived.isNotEmpty) {
        final ids = (jsonDecode(unarchived) as List).whereType<int>();
        for (final id in ids) {
          rearchived += await txn.update(
            'products',
            {'is_archived': 1, 'updated_at': _now()},
            where: 'id = ? AND is_archived = 0',
            whereArgs: [id],
          );
        }
      }
      await txn.update('import_batches', {'undone_at': _now()}, where: 'id = ?', whereArgs: [batchId]);
      return ImportUndoResult(
        entriesRemoved: purchases + sales,
        productsRemoved: removed,
        productsKept: kept,
        productsRearchived: rearchived,
      );
    });
  }

  static String newImportBatchId() {
    final random = Random.secure().nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return 'imp_${DateTime.now().toUtc().microsecondsSinceEpoch}_$random';
  }

  Future<void> close() async {
    final current = _database;
    _database = null;
    if (current != null && current.isOpen) await current.close();
  }
}

import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common/sqlite_api.dart';

import '../utils/app_helpers.dart';

class AppDatabase {
  AppDatabase({
    DatabaseFactory? factory,
    Future<String> Function()? databasePathProvider,
  })  : _factory = factory ?? sqflite.databaseFactory,
        _databasePathProvider = databasePathProvider ?? sqflite.getDatabasesPath;

  static final AppDatabase instance = AppDatabase();

  static const _databaseName = 'buy_price_assistant_gimi.db';
  static const _databaseVersion = 2;

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
        version: _databaseVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
    return _database!;
  }

  Future<void> _upgradeSchema(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE purchase_entries ADD COLUMN currency_code TEXT NOT NULL DEFAULT 'YER'");
      await db.execute("ALTER TABLE sale_entries ADD COLUMN currency_code TEXT NOT NULL DEFAULT 'YER'");
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
        updated_at TEXT NOT NULL
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
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT
      )
    ''');
    await db.execute('CREATE INDEX idx_products_search_name ON products(search_name)');
    await db.execute('CREATE INDEX idx_products_search_code ON products(search_code)');
    await db.execute('CREATE INDEX idx_purchase_product_date ON purchase_entries(product_id, purchase_date DESC, id DESC)');
    await db.execute('CREATE INDEX idx_sale_product_date ON sale_entries(product_id, sale_date DESC, id DESC)');
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

  Future<List<Map<String, Object?>>> searchProducts(
    String query, {
    String? category,
    String? brand,
    String? supplier,
  }) async {
    final db = await database;
    final normalized = normalizeForSearch(query);
    final terms = normalized.split(RegExp(r'\\s+')).where((v) => v.isNotEmpty).toList();
    final args = <Object?>[];
    final conditions = <String>['p.is_archived = 0'];
    for (final term in terms) {
      final termPattern = '%${escapeLikePattern(term)}%';
      conditions.add('''(
        p.search_name LIKE ? ESCAPE '!' OR p.search_code LIKE ? ESCAPE '!' OR
        p.search_category LIKE ? ESCAPE '!' OR lower(coalesce(p.brand, '')) LIKE ? ESCAPE '!' OR
        lower(coalesce(p.notes, '')) LIKE ? ESCAPE '!' OR
        EXISTS (SELECT 1 FROM purchase_entries pe WHERE pe.product_id = p.id AND (
          lower(coalesce(pe.supplier, '')) LIKE ? ESCAPE '!' OR
          lower(coalesce(pe.notes, '')) LIKE ? ESCAPE '!' OR
          coalesce(pe.purchase_date, '') LIKE ? ESCAPE '!' OR cast(pe.unit_price as text) LIKE ? ESCAPE '!')) OR
        EXISTS (SELECT 1 FROM sale_entries se WHERE se.product_id = p.id AND (
          lower(coalesce(se.customer, '')) LIKE ? ESCAPE '!' OR
          lower(coalesce(se.notes, '')) LIKE ? ESCAPE '!' OR
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
    return db.rawQuery(
      '${_productSelect()} WHERE ${conditions.join(' AND ')} ORDER BY p.is_favorite DESC, p.updated_at DESC, p.name COLLATE NOCASE ASC LIMIT 250',
      args,
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
    final code = currencyCode.trim().toUpperCase();
    if (!const <String>{'YER', 'SAR', 'USD'}.contains(code)) {
      throw ArgumentError('العملة غير مدعومة: $currencyCode');
    }
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

  /// Exports all user data, including archived products and every price record.
  Future<String> exportBackupJson() async {
    final db = await database;
    final products = await db.query('products', orderBy: 'id ASC');
    final purchases = await db.query('purchase_entries', orderBy: 'id ASC');
    final sales = await db.query('sale_entries', orderBy: 'id ASC');
    final payload = <String, Object?>{
      'format': 'buy_price_assistant_gimi_backup',
      'schemaVersion': 2,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'tables': <String, Object?>{
        'products': products,
        'purchase_entries': purchases,
        'sale_entries': sales,
      },
      'counts': <String, int>{
        'products': products.length,
        'purchase_entries': purchases.length,
        'sale_entries': sales.length,
      },
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Replaces all local records atomically. Invalid backups leave existing data untouched.
  Future<void> restoreBackupJson(String source) async {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'buy_price_assistant_gimi_backup' ||
        !(decoded['schemaVersion'] == 1 || decoded['schemaVersion'] == 2) ||
        decoded['tables'] is! Map<String, dynamic>) {
      throw const FormatException('ملف النسخة الاحتياطية غير معروف أو غير مدعوم.');
    }

    final tables = decoded['tables'] as Map<String, dynamic>;
    const columns = <String, Set<String>>{
      'products': {
        'id', 'name', 'search_name', 'code', 'search_code', 'category',
        'search_category', 'unit', 'brand', 'notes', 'is_favorite',
        'is_archived', 'created_at', 'updated_at',
      },
      'purchase_entries': {
        'id', 'product_id', 'purchase_date', 'unit_price', 'currency_code', 'quantity',
        'supplier', 'invoice_number', 'notes', 'created_at',
      },
      'sale_entries': {
        'id', 'product_id', 'sale_date', 'unit_price', 'currency_code', 'quantity',
        'customer', 'notes', 'created_at',
      },
    };
    const required = <String, Set<String>>{
      'products': {
        'id', 'name', 'search_name', 'search_code', 'search_category',
        'unit', 'is_favorite', 'is_archived', 'created_at', 'updated_at',
      },
      'purchase_entries': {
        'id', 'product_id', 'purchase_date', 'unit_price', 'quantity', 'created_at',
      },
      'sale_entries': {
        'id', 'product_id', 'sale_date', 'unit_price', 'quantity', 'created_at',
      },
    };

    final normalized = <String, List<Map<String, Object?>>>{};
    for (final table in columns.keys) {
      final rows = tables[table];
      if (rows is! List) {
        throw FormatException('بيانات الجدول $table غير موجودة في النسخة الاحتياطية.');
      }
      final cleanRows = <Map<String, Object?>>[];
      for (final row in rows) {
        if (row is! Map) {
          throw FormatException('توجد بيانات غير صحيحة داخل الجدول $table.');
        }
        final item = Map<String, Object?>.from(row);
        if (table == 'purchase_entries' || table == 'sale_entries') {
          // Schema v1 backups did not store currency. Their original display currency was YER.
          item.putIfAbsent('currency_code', () => 'YER');
          final currency = item['currency_code'];
          if (currency is! String || !const <String>{'YER', 'SAR', 'USD'}.contains(currency)) {
            throw FormatException('العملة غير صالحة في الجدول $table.');
          }
        }
        if (!columns[table]!.containsAll(item.keys) ||
            !item.keys.toSet().containsAll(required[table]!)) {
          throw FormatException('أعمدة الجدول $table لا تتوافق مع إصدار قاعدة البيانات.');
        }
        if (item['id'] is! int) {
          throw FormatException('يوجد معرّف غير صحيح في الجدول $table.');
        }
        cleanRows.add(item);
      }
      normalized[table] = cleanRows;
    }

    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('purchase_entries');
      await txn.delete('sale_entries');
      await txn.delete('products');
      for (final row in normalized['products']!) {
        await txn.insert('products', row);
      }
      for (final row in normalized['purchase_entries']!) {
        await txn.insert('purchase_entries', row);
      }
      for (final row in normalized['sale_entries']!) {
        await txn.insert('sale_entries', row);
      }
    });
  }

  Future<void> close() async {
    final current = _database;
    _database = null;
    if (current != null && current.isOpen) await current.close();
  }
}

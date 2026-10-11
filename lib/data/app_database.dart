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
  static const _databaseVersion = 1;

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
      ),
    );
    return _database!;
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
      (SELECT COUNT(*) FROM purchase_entries pe WHERE pe.product_id = p.id) AS purchase_count,
      (SELECT se.unit_price FROM sale_entries se WHERE se.product_id = p.id
       ORDER BY se.sale_date DESC, se.id DESC LIMIT 1) AS latest_sale_price,
      (SELECT se.sale_date FROM sale_entries se WHERE se.product_id = p.id
       ORDER BY se.sale_date DESC, se.id DESC LIMIT 1) AS latest_sale_date,
      (SELECT COUNT(*) FROM sale_entries se WHERE se.product_id = p.id) AS sale_count
    FROM products p
  ''';

  Future<List<Map<String, Object?>>> searchProducts(String query) async {
    final db = await database;
    final normalized = normalizeForSearch(query);
    final pattern = '%${escapeLikePattern(normalized)}%';
    return db.rawQuery(
      '''${_productSelect()}
         WHERE p.is_archived = 0
           AND (? = '' OR p.search_name LIKE ? ESCAPE '!'
             OR p.search_code LIKE ? ESCAPE '!'
             OR p.search_category LIKE ? ESCAPE '!')
         ORDER BY p.is_favorite DESC, p.updated_at DESC, p.name COLLATE NOCASE ASC
         LIMIT 250''',
      [normalized, pattern, pattern, pattern],
    );
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
  }) async {
    _validateEntry(date: date, price: unitPrice, quantity: quantity);
    return _recordEntry('purchase_entries', {
      'product_id': productId,
      'purchase_date': date,
      'unit_price': unitPrice,
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
  }) async {
    _validateEntry(date: date, price: unitPrice, quantity: quantity);
    return _recordEntry('sale_entries', {
      'product_id': productId,
      'sale_date': date,
      'unit_price': unitPrice,
      'quantity': quantity,
      'customer': _nullableTrim(customer),
      'notes': _nullableTrim(notes),
      'created_at': _now(),
    });
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
             supplier AS party_name, invoice_number, notes, created_at
      FROM purchase_entries WHERE product_id = ?
      ORDER BY purchase_date DESC, id DESC
    ''', [productId]);
  }

  Future<List<Map<String, Object?>>> getSaleHistory(int productId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT id, product_id, sale_date AS entry_date, unit_price, quantity,
             customer AS party_name, NULL AS invoice_number, notes, created_at
      FROM sale_entries WHERE product_id = ?
      ORDER BY sale_date DESC, id DESC
    ''', [productId]);
  }

  Future<void> close() async {
    final current = _database;
    _database = null;
    if (current != null && current.isOpen) await current.close();
  }
}

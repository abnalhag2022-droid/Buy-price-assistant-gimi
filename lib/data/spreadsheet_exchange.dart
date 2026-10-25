import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../state/app_settings.dart';
import '../utils/app_helpers.dart';
import 'app_database.dart';

/// Additive spreadsheet exchange. JSON backup/restore intentionally remains separate.
class SpreadsheetExchange {
  SpreadsheetExchange._(this._db);
  static final SpreadsheetExchange instance = SpreadsheetExchange._(AppDatabase.instance);
  factory SpreadsheetExchange.forDatabase(AppDatabase db) => SpreadsheetExchange._(db);
  final AppDatabase _db;

  static const headers = <String>[
    'Type', 'Product Name', 'Unit', 'Code', 'Category', 'Brand', 'Product Notes',
    'Date', 'Unit Price', 'Currency', 'Quantity', 'Supplier/Customer',
    'Invoice Number', 'Entry Notes', 'Product Archived', 'Product Favorite',
    'Record Created At',
  ];

  static const Map<String, List<String>> _aliases = {
    'type': ['type', 'transactiontype', 'operationtype', 'entrytype', 'نوعالعملية', 'نوع', 'النوع', 'حركة'],
    'name': ['productname', 'itemname', 'name', 'product', 'item', 'اسمالصنف', 'الصنف', 'اسمالمنتج', 'المنتج', 'اسم'],
    'unit': ['unit', 'unitofmeasure', 'uom', 'الوحدة', 'وحدة', 'وحدةالقياس', 'وحدةالصنف'],
    'code': ['code', 'productcode', 'itemcode', 'sku', 'الكود', 'كود', 'كودالصنف'],
    'category': ['category', 'productcategory', 'التصنيف', 'تصنيف', 'فئة'],
    'brand': ['brand', 'manufacturer', 'الماركة', 'العلامةالتجارية', 'الشركة'],
    'productNotes': ['productnotes', 'itemnotes', 'ملاحظاتالصنف', 'ملاحظاتالمنتج'],
    'date': ['date', 'entrydate', 'transactiondate', 'purchasedate', 'saledate', 'التاريخ', 'تاريخ', 'تاريخالعملية', 'تاريخالشراء', 'تاريخالبيع'],
    'price': ['unitprice', 'price', 'priceperunit', 'purchaseprice', 'saleprice', 'السعر', 'سعرالوحدة', 'سعر', 'سعرالشراء', 'سعرالبيع'],
    'currency': ['currency', 'currencycode', 'العملة', 'رمزالعملة'],
    'quantity': ['quantity', 'qty', 'الكمية', 'كمية'],
    'party': ['suppliercustomer', 'supplier', 'customer', 'party', 'partyname', 'المورد', 'المورّد', 'العميل', 'اسمالمورد', 'اسمالعميل', 'الجهة'],
    'invoice': ['invoicenumber', 'invoice', 'billnumber', 'رقمالفاتورة', 'فاتورة'],
    'notes': ['entrynotes', 'transactionnotes', 'notes', 'ملاحظاتالعملية', 'ملاحظاتالسجل', 'ملاحظات'],
    'archived': ['productarchived', 'isarchived', 'مؤرشف', 'الصنفمؤرشف'],
    'favorite': ['productfavorite', 'isfavorite', 'مفضل', 'المفضلة'],
    'createdAt': ['recordcreatedat', 'createdat', 'تاريخالانشاء', 'تاريخالإنشاء'],
  };

  static String normalizeColumnHeader(String value) =>
      normalizeForSearch(value).replaceAll(RegExp(r'[\s_\-./\\()\[\]{}:]+'), '');

  static String? normalizeDateValue(String input) {
    var value = input.trim().replaceAll('٫', '.').replaceAll('٬', '').replaceAll(',', '');
    const ar = '٠١٢٣٤٥٦٧٨٩';
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < 10; i++) {
      value = value.replaceAll(ar[i], '$i').replaceAll(fa[i], '$i');
    }
    if (value.isEmpty) return null;
    DateTime? checked(int y, int m, int d) {
      final date = DateTime.tryParse(
        '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}',
      );
      if (date == null || date.year != y || date.month != m || date.day != d) return null;
      return date;
    }
    final iso = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[ T].*)?$').firstMatch(value);
    if (iso != null) {
      final d = checked(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
      return d == null ? null : toIsoDate(d);
    }
    final dmy = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$').firstMatch(value);
    if (dmy != null) {
      final d = checked(int.parse(dmy[3]!), int.parse(dmy[2]!), int.parse(dmy[1]!));
      return d == null ? null : toIsoDate(d);
    }
    final serial = double.tryParse(value);
    if (serial != null && serial >= 20000 && serial <= 100000) {
      return toIsoDate(DateTime(1899, 12, 30).add(Duration(days: serial.floor())));
    }
    return null;
  }

  static String _cellText(Object? cell) {
    Object? raw = cell;
    if (raw is Data) raw = raw.value;
    if (raw == null) return '';
    if (raw is TextCellValue) return raw.value.text ?? '';
    if (raw is DateCellValue) return toIsoDate(raw.asDateTimeLocal());
    if (raw is DateTimeCellValue) return toIsoDate(raw.asDateTimeLocal());
    if (raw is IntCellValue) return raw.value.toString();
    if (raw is DoubleCellValue) return raw.value.toString();
    if (raw is BoolCellValue) return raw.value ? 'true' : 'false';
    if (raw is FormulaCellValue) return raw.formula;
    return raw.toString().trim();
  }

  static String _clean(String value) {
    final v = value.trim();
    return v.length > 1 && v.startsWith("'") && '=+-@'.contains(v[1]) ? v.substring(1) : v;
  }

  static String _key(String name, String unit) =>
      '${normalizeForSearch(name)}\u001f${normalizeForSearch(unit)}';
  static String? _nullable(String s) => s.trim().isEmpty ? null : s.trim();
  static bool _flag(String s) => const {'1', 'true', 'yes', 'y', 'نعم'}.contains(normalizeForSearch(s));

  static String _sig({
    required String type, required String key, required String date, required double price,
    required String currency, required double quantity, String? party, String? invoice, String? notes,
  }) => [
    type, key, date, price.toStringAsFixed(8), currency, quantity.toStringAsFixed(8),
    normalizeForSearch(party ?? ''), normalizeForSearch(invoice ?? ''), normalizeForSearch(notes ?? ''),
  ].join('\u001e');

  Future<SpreadsheetPreview> previewBytes(Uint8List bytes, String filename) async {
    if (bytes.isEmpty) throw const FormatException('الملف فارغ.');
    final lower = filename.toLowerCase();
    if (lower.endsWith('.xls') && !lower.endsWith('.xlsx')) {
      throw const FormatException('صيغة XLS القديمة غير مدعومة مباشرة. احفظ الملف بصيغة XLSX أو CSV UTF-8.');
    }
    List<List<String>> matrix;
    if (lower.endsWith('.csv')) {
      final source = utf8.decode(bytes, allowMalformed: false)
          .replaceFirst('\uFEFF', '')
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n');
      matrix = const CsvToListConverter(shouldParseNumbers: false, eol: '\n').convert(source)
          .map((row) => row.map((v) => v?.toString() ?? '').toList()).toList();
      if (matrix.isNotEmpty && !_hasHeaders(matrix.first)) {
        final other = const CsvToListConverter(fieldDelimiter: ';', shouldParseNumbers: false, eol: '\n')
            .convert(source).map((row) => row.map((v) => v?.toString() ?? '').toList()).toList();
        if (other.isNotEmpty && _hasHeaders(other.first)) matrix = other;
      }
    } else if (lower.endsWith('.xlsx')) {
      try {
        final workbook = Excel.decodeBytes(bytes);
        final sheets = workbook.tables.values.where((s) => s.rows.isNotEmpty).toList();
        if (sheets.isEmpty) throw const FormatException('لا توجد بيانات في ورقة Excel.');
        matrix = sheets.first.rows.map((row) => row.map(_cellText).toList()).toList();
      } catch (e) {
        if (e is FormatException) rethrow;
        throw FormatException('تعذر قراءة XLSX. تأكد أن الملف سليم وغير محمي. $e');
      }
    } else {
      throw const FormatException('الصيغ المدعومة هي XLSX وCSV UTF-8.');
    }
    if (matrix.isEmpty) throw const FormatException('لا يحتوي الملف على بيانات.');
    final indexes = <String, int>{};
    for (var i = 0; i < matrix.first.length; i++) {
      final h = normalizeColumnHeader(matrix.first[i]);
      for (final entry in _aliases.entries) {
        if (entry.value.contains(h)) {
          indexes.putIfAbsent(entry.key, () => i);
          break;
        }
      }
    }
    if (!indexes.containsKey('name') || !indexes.containsKey('unit')) {
      throw const FormatException('يجب أن يحتوي صف العناوين على اسم الصنف ووحدة القياس.');
    }
    final rows = <SpreadsheetRecord>[];
    for (var i = 1; i < matrix.length; i++) {
      final values = matrix[i];
      if (values.every((v) => v.trim().isEmpty)) continue;
      String get(String field) {
        final index = indexes[field];
        return index == null || index >= values.length ? '' : _clean(values[index]);
      }
      final name = get('name');
      final unit = get('unit');
      final typeRaw = normalizeColumnHeader(get('type'));
      final type = const {'purchase', 'buy', 'p', 'شراء', 'مشتريات', 'وارد'}.contains(typeRaw)
          ? 'PURCHASE'
          : const {'sale', 'sell', 's', 'بيع', 'مبيعات', 'صادر'}.contains(typeRaw) ? 'SALE' : '';
      final dateRaw = get('date');
      final priceRaw = get('price');
      final quantityRaw = get('quantity');
      final party = get('party');
      final invoice = get('invoice');
      final notes = get('notes');
      final hasTransaction = [get('type'), dateRaw, priceRaw, quantityRaw, party, invoice, notes].any((v) => v.isNotEmpty);
      final errors = <String>[];
      final warnings = <String>[];
      if (name.isEmpty) errors.add('اسم الصنف مطلوب.');
      if (unit.isEmpty) errors.add('وحدة القياس مطلوبة للمطابقة الآمنة.');
      final date = hasTransaction ? normalizeDateValue(dateRaw) : null;
      final price = hasTransaction ? parseLocalizedNumber(priceRaw) : null;
      final quantity = hasTransaction ? parseLocalizedNumber(quantityRaw) : null;
      var currency = get('currency').toUpperCase();
      if (hasTransaction) {
        if (type.isEmpty) errors.add('نوع العملية مطلوب: PURCHASE أو SALE.');
        if (date == null) errors.add('التاريخ غير صحيح؛ استخدم YYYY-MM-DD أو DD/MM/YYYY.');
        if (price == null || price < 0) errors.add('سعر الوحدة مطلوب ويجب ألا يكون سالبًا.');
        if (quantity == null || quantity <= 0) errors.add('الكمية مطلوبة ويجب أن تكون أكبر من صفر.');
        if (currency.isEmpty) {
          currency = AppSettings.instance.currency;
          warnings.add('العملة غير محددة؛ ستستخدم العملة الافتراضية الحالية: $currency.');
        }
        if (!const {'YER', 'SAR', 'USD'}.contains(currency)) errors.add('العملة يجب أن تكون YER أو SAR أو USD.');
        if (type == 'SALE' && invoice.isNotEmpty) errors.add('رقم الفاتورة غير مدعوم في سجلات البيع؛ لا يمكن حفظه.');
      }
      DateTime? created;
      final createdRaw = get('createdAt');
      if (createdRaw.isNotEmpty) {
        created = DateTime.tryParse(createdRaw);
        if (created == null) warnings.add('وقت إنشاء السجل غير صالح؛ سيستخدم الوقت الحالي.');
      }
      rows.add(SpreadsheetRecord(
        line: i + 1, name: name, unit: unit, code: _nullable(get('code')),
        category: _nullable(get('category')), brand: _nullable(get('brand')),
        productNotes: _nullable(get('productNotes')), productArchived: _flag(get('archived')),
        productFavorite: _flag(get('favorite')), type: type, hasTransaction: hasTransaction,
        date: date, price: price, quantity: quantity, currency: currency,
        party: _nullable(party), invoice: _nullable(invoice), notes: _nullable(notes),
        createdAt: created?.toIso8601String(), errors: errors, warnings: warnings,
      ));
    }
    return _buildPreview(rows, await _db.database);
  }

  bool _hasHeaders(List<String> values) {
    final found = <String>{};
    for (final value in values) {
      final h = normalizeColumnHeader(value);
      for (final entry in _aliases.entries) {
        if (entry.value.contains(h)) found.add(entry.key);
      }
    }
    return found.contains('name') && found.contains('unit');
  }

  Future<SpreadsheetPreview> _buildPreview(List<SpreadsheetRecord> rows, DatabaseExecutor ex) async {
    final issues = <SpreadsheetIssue>[];
    for (final r in rows) {
      for (final message in r.errors) {
        issues.add(SpreadsheetIssue(row: r.line, message: message, isError: true));
      }
      for (final message in r.warnings) {
        issues.add(SpreadsheetIssue(row: r.line, message: message, isError: false));
      }
    }
    final products = await ex.query('products');
    final productsByKey = <String, List<Map<String, Object?>>>{};
    for (final p in products) {
      productsByKey.putIfAbsent(_key(p['name']! as String, p['unit']! as String), () => []).add(p);
    }
    final groups = <String, List<SpreadsheetRecord>>{};
    for (final r in rows) {
      if (r.name.isNotEmpty && r.unit.isNotEmpty && r.hasTransaction) {
        groups.putIfAbsent(_key(r.name, r.unit), () => []).add(r);
      }
    }
    var matched = 0;
    var newItems = 0;
    for (final group in groups.entries) {
      final hits = productsByKey[group.key] ?? [];
      final active = hits.where((p) => (p['is_archived'] as num? ?? 0) == 0).toList();
      final archived = hits.where((p) => (p['is_archived'] as num? ?? 0) == 1).toList();
      if (active.length > 1 || (active.isNotEmpty && archived.isNotEmpty)) {
        for (final r in group.value) {
          issues.add(SpreadsheetIssue(row: r.line, message: 'توجد أصناف نشطة/مؤرشفة متطابقة بالاسم والوحدة؛ عالج التطابق أولًا.', isError: true));
        }
      } else if (active.isEmpty && archived.isNotEmpty) {
        for (final r in group.value) {
          issues.add(SpreadsheetIssue(row: r.line, message: 'الصنف المطابق مؤرشف؛ لن يعاد استخدامه أو إلغاء أرشفته تلقائيًا.', isError: true));
        }
      } else if (active.length == 1) {
        if (group.value.any((r) => r.productArchived)) {
          for (final r in group.value) {
            issues.add(SpreadsheetIssue(row: r.line, message: 'الملف يحدد الصنف كمؤرشف بينما الصنف المطابق نشط؛ راجع البيانات.', isError: true));
          }
        } else {
          matched++;
        }
      } else {
        final purchase = group.value.any((r) => r.type == 'PURCHASE' && r.errors.isEmpty && r.date != null && r.price != null && r.quantity != null);
        if (!purchase) {
          for (final r in group.value) {
            issues.add(SpreadsheetIssue(row: r.line, message: 'الصنف الجديد يحتاج إلى عملية شراء صحيحة واحدة على الأقل.', isError: true));
          }
        } else {
          newItems++;
        }
      }
    }

    final known = <String>{};
    final purchases = await ex.rawQuery('''
      SELECT p.name,p.unit,e.purchase_date AS date,e.unit_price AS price,e.currency_code AS currency,
             e.quantity,e.supplier AS party,e.invoice_number AS invoice,e.notes
      FROM purchase_entries e JOIN products p ON p.id=e.product_id
    ''');
    for (final r in purchases) {
      known.add(_sig(type: 'PURCHASE', key: _key(r['name']! as String, r['unit']! as String),
        date: r['date']! as String, price: (r['price']! as num).toDouble(),
        currency: r['currency']! as String, quantity: (r['quantity']! as num).toDouble(),
        party: r['party'] as String?, invoice: r['invoice'] as String?, notes: r['notes'] as String?));
    }
    final sales = await ex.rawQuery('''
      SELECT p.name,p.unit,e.sale_date AS date,e.unit_price AS price,e.currency_code AS currency,
             e.quantity,e.customer AS party,e.notes
      FROM sale_entries e JOIN products p ON p.id=e.product_id
    ''');
    for (final r in sales) {
      known.add(_sig(type: 'SALE', key: _key(r['name']! as String, r['unit']! as String),
        date: r['date']! as String, price: (r['price']! as num).toDouble(),
        currency: r['currency']! as String, quantity: (r['quantity']! as num).toDouble(),
        party: r['party'] as String?, notes: r['notes'] as String?));
    }
    final seen = <String>{};
    var duplicates = 0;
    var valid = 0;
    for (final r in rows) {
      if (!r.hasTransaction || r.errors.isNotEmpty || r.type.isEmpty || r.date == null ||
          r.price == null || r.quantity == null || r.name.isEmpty || r.unit.isEmpty) {
        continue;
      }
      valid++;
      final sig = _sig(type: r.type, key: _key(r.name, r.unit), date: r.date!, price: r.price!,
        currency: r.currency, quantity: r.quantity!, party: r.party, invoice: r.invoice, notes: r.notes);
      if (known.contains(sig)) {
        duplicates++;
        issues.add(SpreadsheetIssue(row: r.line, message: 'توجد عملية مطابقة في قاعدة البيانات؛ تتطلب تأكيدًا صريحًا لإضافتها.', isError: false));
      } else if (seen.contains(sig)) {
        duplicates++;
        issues.add(SpreadsheetIssue(row: r.line, message: 'هذه العملية مكررة داخل الملف؛ تتطلب تأكيدًا صريحًا لإضافتها.', isError: false));
      }
      seen.add(sig);
    }
    return SpreadsheetPreview(
      rows: rows, issues: issues, matchedProducts: matched, newProducts: newItems,
      duplicateCount: duplicates, validTransactionCount: valid,
      errorCount: issues.where((i) => i.isError).length,
    );
  }

  Future<SpreadsheetImportResult> importPreview(SpreadsheetPreview preview, {required bool confirmDuplicates}) async {
    final db = await _db.database;
    var productsAdded = 0;
    var entriesAdded = 0;
    await db.transaction((txn) async {
      final fresh = await _buildPreview(preview.rows, txn);
      if (fresh.errorCount > 0) throw SpreadsheetImportException(fresh, 'ظهرت أخطاء عند إعادة التحقق؛ لم تتم الكتابة.');
      if (fresh.validTransactionCount == 0) throw SpreadsheetImportException(fresh, 'لا توجد عمليات صحيحة للاستيراد.');
      if (fresh.duplicateCount > 0 && !confirmDuplicates) {
        throw SpreadsheetImportException(fresh, 'يلزم تأكيد صريح قبل إضافة العمليات المكررة.');
      }
      final products = await txn.query('products', columns: ['id', 'name', 'unit', 'is_archived']);
      final byKey = <String, List<Map<String, Object?>>>{};
      for (final p in products) {
        byKey.putIfAbsent(_key(p['name']! as String, p['unit']! as String), () => []).add(p);
      }
      final groups = <String, List<SpreadsheetRecord>>{};
      for (final r in fresh.rows) {
        if (r.hasTransaction) groups.putIfAbsent(_key(r.name, r.unit), () => []).add(r);
      }
      final ids = <String, int>{};
      final now = DateTime.now().toIso8601String();
      for (final group in groups.entries) {
        final hits = byKey[group.key] ?? [];
        final active = hits.where((p) => (p['is_archived'] as num? ?? 0) == 0).toList();
        if (active.length == 1) {
          ids[group.key] = (active.single['id']! as num).toInt();
          continue; // Existing product metadata is never overwritten.
        }
        final source = group.value.firstWhere((r) => r.type == 'PURCHASE' && r.errors.isEmpty);
        final id = await txn.insert('products', {
          'name': source.name,
          'search_name': normalizeForSearch(source.name),
          'code': source.code,
          'search_code': normalizeForSearch(source.code ?? ''),
          'category': source.category,
          'search_category': normalizeForSearch(source.category ?? ''),
          'unit': source.unit,
          'brand': source.brand,
          'notes': source.productNotes,
          'is_favorite': source.productFavorite ? 1 : 0,
          'is_archived': source.productArchived ? 1 : 0,
          'created_at': now,
          'updated_at': now,
        });
        ids[group.key] = id;
        productsAdded++;
      }
      for (final r in fresh.rows) {
        if (!r.hasTransaction) continue;
        final id = ids[_key(r.name, r.unit)];
        if (id == null) throw StateError('تعذر ربط سجل الأسعار بالصنف.');
        final createdAt = r.createdAt ?? DateTime.now().toIso8601String();
        if (r.type == 'PURCHASE') {
          await txn.insert('purchase_entries', {
            'product_id': id, 'purchase_date': r.date, 'unit_price': r.price,
            'currency_code': r.currency, 'quantity': r.quantity, 'supplier': r.party,
            'invoice_number': r.invoice, 'notes': r.notes, 'created_at': createdAt,
          });
        } else {
          await txn.insert('sale_entries', {
            'product_id': id, 'sale_date': r.date, 'unit_price': r.price,
            'currency_code': r.currency, 'quantity': r.quantity, 'customer': r.party,
            'notes': r.notes, 'created_at': createdAt,
          });
        }
        entriesAdded++;
      }
    });
    return SpreadsheetImportResult(productsAdded: productsAdded, transactionsAdded: entriesAdded);
  }

  Future<Uint8List> exportCsv() async {
    final rows = await _exportRows();
    final safe = rows.map((row) => row.map((value) {
      final s = value?.toString() ?? '';
      return s.isNotEmpty && '=+-@'.contains(s[0]) ? "'$s" : s;
    }).toList()).toList();
    final csv = const ListToCsvConverter().convert(safe);
    return Uint8List.fromList(utf8.encode('\uFEFF$csv'));
  }

  Future<Uint8List> exportXlsx() async {
    final rows = await _exportRows();
    final workbook = Excel.createExcel();
    workbook.rename('Sheet1', 'Data');
    final sheet = workbook['Data']..isRTL = true;
    sheet.appendRow(headers.map<CellValue>((v) => TextCellValue(v)).toList());
    for (final row in rows.skip(1)) {
      sheet.appendRow(row.map<CellValue?>((v) {
        if (v == null || v.toString().isEmpty) return TextCellValue('');
        if (v is num) return DoubleCellValue(v.toDouble());
        return TextCellValue(v.toString());
      }).toList());
    }
    final bytes = workbook.encode();
    if (bytes == null || bytes.isEmpty) throw StateError('تعذر إنشاء ملف Excel.');
    return Uint8List.fromList(bytes);
  }

  Future<List<List<Object?>>> _exportRows() async {
    final db = await _db.database;
    final products = await db.query('products', orderBy: 'id ASC');
    final purchases = await db.query('purchase_entries', orderBy: 'purchase_date ASC, id ASC');
    final sales = await db.query('sale_entries', orderBy: 'sale_date ASC, id ASC');
    final productsById = <int, Map<String, Object?>>{
      for (final p in products) (p['id']! as num).toInt(): p,
    };
    final history = <int, List<List<Object?>>>{};
    for (final p in purchases) {
      final product = productsById[(p['product_id']! as num).toInt()];
      if (product == null) continue;
      history.putIfAbsent((product['id']! as num).toInt(), () => []).add(_entry(
        'PURCHASE', product, p['purchase_date']! as String, (p['unit_price']! as num).toDouble(),
        p['currency_code']! as String, (p['quantity']! as num).toDouble(), p['supplier'] as String?,
        p['invoice_number'] as String?, p['notes'] as String?, p['created_at'] as String?));
    }
    for (final s in sales) {
      final product = productsById[(s['product_id']! as num).toInt()];
      if (product == null) continue;
      history.putIfAbsent((product['id']! as num).toInt(), () => []).add(_entry(
        'SALE', product, s['sale_date']! as String, (s['unit_price']! as num).toDouble(),
        s['currency_code']! as String, (s['quantity']! as num).toDouble(), s['customer'] as String?,
        null, s['notes'] as String?, s['created_at'] as String?));
    }
    final rows = <List<Object?>>[headers];
    for (final p in products) {
      final entries = history[(p['id']! as num).toInt()];
      if (entries == null || entries.isEmpty) {
        rows.add(['', p['name'], p['unit'], p['code'], p['category'], p['brand'], p['notes'],
          '', '', '', '', '', '', '', p['is_archived'], p['is_favorite'], '']);
      } else {
        entries.sort((a, b) {
          final date = (a[7]?.toString() ?? '').compareTo(b[7]?.toString() ?? '');
          return date != 0 ? date : (a[0]?.toString() ?? '').compareTo(b[0]?.toString() ?? '');
        });
        rows.addAll(entries);
      }
    }
    return rows;
  }

  List<Object?> _entry(String type, Map<String, Object?> p, String date, double price,
      String currency, double quantity, String? party, String? invoice, String? notes, String? created) => [
    type, p['name'], p['unit'], p['code'], p['category'], p['brand'], p['notes'], date, price,
    currency, quantity, party, invoice, notes, p['is_archived'], p['is_favorite'], created,
  ];
}

class SpreadsheetRecord {
  SpreadsheetRecord({
    required this.line, required this.name, required this.unit, required this.code,
    required this.category, required this.brand, required this.productNotes,
    required this.productArchived, required this.productFavorite, required this.type,
    required this.hasTransaction, required this.date, required this.price, required this.quantity,
    required this.currency, required this.party, required this.invoice, required this.notes,
    required this.createdAt, required this.errors, required this.warnings,
  });
  final int line;
  final String name, unit;
  final String? code, category, brand, productNotes;
  final bool productArchived, productFavorite, hasTransaction;
  final String type;
  final String? date;
  final double? price, quantity;
  final String currency;
  final String? party, invoice, notes, createdAt;
  final List<String> errors, warnings;
}

class SpreadsheetIssue {
  const SpreadsheetIssue({required this.row, required this.message, required this.isError});
  final int row;
  final String message;
  final bool isError;
}

class SpreadsheetPreview {
  const SpreadsheetPreview({
    required this.rows, required this.issues, required this.matchedProducts,
    required this.newProducts, required this.duplicateCount, required this.validTransactionCount,
    required this.errorCount,
  });
  final List<SpreadsheetRecord> rows;
  final List<SpreadsheetIssue> issues;
  final int matchedProducts, newProducts, duplicateCount, validTransactionCount, errorCount;
  bool get canImport => errorCount == 0 && validTransactionCount > 0;
}

class SpreadsheetImportResult {
  const SpreadsheetImportResult({required this.productsAdded, required this.transactionsAdded});
  final int productsAdded, transactionsAdded;
}

class SpreadsheetImportException implements Exception {
  const SpreadsheetImportException(this.preview, this.message);
  final SpreadsheetPreview preview;
  final String message;
  @override
  String toString() => message;
}

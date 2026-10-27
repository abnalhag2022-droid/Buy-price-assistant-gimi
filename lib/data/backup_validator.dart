import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../utils/app_helpers.dart';
import '../utils/currencies.dart';

/// Validated, normalized rows of a JSON backup, ready for insertion.
class BackupContents {
  const BackupContents({
    required this.schemaVersion,
    required this.products,
    required this.purchases,
    required this.sales,
    required this.importBatches,
    required this.settings,
    required this.checksumVerified,
  });

  final int schemaVersion;
  final List<Map<String, Object?>> products;
  final List<Map<String, Object?>> purchases;
  final List<Map<String, Object?>> sales;
  final List<Map<String, Object?>> importBatches;

  /// Raw `settings` object when present; validated separately by AppSettings.
  final Object? settings;
  final bool checksumVerified;
}

/// Result of undoing one spreadsheet import batch.
class ImportUndoResult {
  const ImportUndoResult({
    required this.entriesRemoved,
    required this.productsRemoved,
    required this.productsKept,
    required this.productsRearchived,
  });

  final int entriesRemoved;
  final int productsRemoved;
  final int productsKept;
  final int productsRearchived;
}

/// Validates backup files without touching the database. Every failure is a
/// [FormatException] with an Arabic message that names the table and row.
class BackupValidator {
  BackupValidator._();

  static const String formatName = 'buy_price_assistant_gimi_backup';
  static const Set<int> supportedVersions = <int>{1, 2, 3};

  static const Map<String, String> _tableNames = <String, String>{
    'products': 'الأصناف',
    'purchase_entries': 'المشتريات',
    'sale_entries': 'المبيعات',
    'import_batches': 'دفعات الاستيراد',
  };

  /// SHA-256 of the compact JSON encoding of the `tables` object.
  static String checksumOf(Object? tables) =>
      sha256.convert(utf8.encode(jsonEncode(tables))).toString();

  static BackupContents parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('الملف ليس JSON صالحًا أو أنه غير مكتمل.');
    }
    if (decoded is! Map || decoded['format'] != formatName) {
      throw const FormatException('الملف ليس نسخة احتياطية من هذا التطبيق.');
    }
    final version = decoded['schemaVersion'];
    if (version is! int || !supportedVersions.contains(version)) {
      throw FormatException('إصدار النسخة الاحتياطية غير مدعوم ($version). قد تكون من إصدار أحدث من التطبيق.');
    }
    final tables = decoded['tables'];
    if (tables is! Map) {
      throw const FormatException('النسخة الاحتياطية لا تحتوي على الجداول.');
    }

    var checksumVerified = false;
    final checksum = decoded['checksum'];
    if (checksum != null) {
      if (checksum is! Map || checksum['algorithm'] != 'sha256' || checksum['value'] is! String) {
        throw const FormatException('بصمة التحقق في النسخة الاحتياطية غير صالحة.');
      }
      if (checksumOf(tables) != checksum['value']) {
        throw const FormatException('بصمة التحقق لا تطابق محتوى الملف؛ الملف تالف أو عُدّل يدويًا.');
      }
      checksumVerified = true;
    } else if (version >= 3) {
      throw const FormatException('النسخة الاحتياطية من الإصدار 3 يجب أن تتضمن بصمة تحقق.');
    }

    final products = _table(tables, 'products', required: true, validate: (row, at) => _product(row, at));
    final purchases = _table(tables, 'purchase_entries', required: true,
        validate: (row, at) => _entry(row, at, isPurchase: true, version: version));
    final sales = _table(tables, 'sale_entries', required: true,
        validate: (row, at) => _entry(row, at, isPurchase: false, version: version));
    final batches = _table(tables, 'import_batches', required: false, validate: (row, at) => _batch(row, at));

    final productIds = products.map((row) => row['id']! as int).toSet();
    for (final entry in <List<Map<String, Object?>>>[purchases, sales]) {
      for (final row in entry) {
        if (!productIds.contains(row['product_id'])) {
          throw FormatException('يوجد سجل سعر مرتبط بصنف غير موجود في النسخة (معرّف ${row['product_id']}).');
        }
      }
    }

    final counts = decoded['counts'];
    if (counts != null) {
      if (counts is! Map) throw const FormatException('عدادات النسخة الاحتياطية غير صالحة.');
      final actual = <String, int>{
        'products': products.length,
        'purchase_entries': purchases.length,
        'sale_entries': sales.length,
        if (tables.containsKey('import_batches')) 'import_batches': batches.length,
      };
      for (final entry in actual.entries) {
        final expected = counts[entry.key];
        if (expected != null && expected != entry.value) {
          throw FormatException('عدد السجلات في ${_tableNames[entry.key]} (${entry.value}) لا يطابق العدد المسجل في الملف ($expected).');
        }
      }
    }

    return BackupContents(
      schemaVersion: version,
      products: products,
      purchases: purchases,
      sales: sales,
      importBatches: batches,
      settings: decoded['settings'],
      checksumVerified: checksumVerified,
    );
  }

  static List<Map<String, Object?>> _table(
    Map tables,
    String name, {
    required bool required,
    required Map<String, Object?> Function(Map row, String at) validate,
  }) {
    final raw = tables[name];
    if (raw == null && !required) return <Map<String, Object?>>[];
    if (raw is! List) {
      throw FormatException('جدول ${_tableNames[name]} مفقود أو غير صالح في النسخة الاحتياطية.');
    }
    final result = <Map<String, Object?>>[];
    final seenIds = <Object?>{};
    for (var i = 0; i < raw.length; i++) {
      final row = raw[i];
      final at = 'السجل رقم ${i + 1} في جدول ${_tableNames[name]}';
      if (row is! Map) throw FormatException('$at غير صالح.');
      final clean = validate(row, at);
      if (!seenIds.add(clean['id'])) throw FormatException('$at: المعرّف ${clean['id']} مكرر.');
      result.add(clean);
    }
    return result;
  }

  static Map<String, Object?> _product(Map row, String at) {
    const allowed = <String>{
      'id', 'name', 'code', 'category', 'unit', 'brand', 'notes', 'is_favorite', 'is_archived',
      'created_at', 'updated_at', 'import_batch_id',
      // Derived columns written by older versions; recomputed on restore.
      'search_name', 'search_code', 'search_category',
    };
    _rejectUnknown(row, allowed, at);
    final name = _requiredText(row, 'name', at);
    final unit = row['unit'];
    return <String, Object?>{
      'id': _positiveId(row, 'id', at),
      'name': name,
      'code': _optionalText(row, 'code', at),
      'category': _optionalText(row, 'category', at),
      'unit': unit is String && unit.trim().isNotEmpty ? unit.trim() : 'قطعة',
      'brand': _optionalText(row, 'brand', at),
      'notes': _optionalText(row, 'notes', at),
      'is_favorite': _flag(row, 'is_favorite', at),
      'is_archived': _flag(row, 'is_archived', at),
      'created_at': _timestamp(row, 'created_at', at),
      'updated_at': _timestamp(row, 'updated_at', at),
      'import_batch_id': _optionalText(row, 'import_batch_id', at),
    };
  }

  static Map<String, Object?> _entry(Map row, String at, {required bool isPurchase, required int version}) {
    final dateColumn = isPurchase ? 'purchase_date' : 'sale_date';
    final partyColumn = isPurchase ? 'supplier' : 'customer';
    final allowed = <String>{
      'id', 'product_id', dateColumn, 'unit_price', 'currency_code', 'quantity', partyColumn,
      'notes', 'created_at', 'import_batch_id', if (isPurchase) 'invoice_number',
    };
    _rejectUnknown(row, allowed, at);
    final date = row[dateColumn];
    if (date is! String || !_isIsoDate(date)) {
      throw FormatException('$at: التاريخ غير صالح؛ الصيغة المطلوبة YYYY-MM-DD.');
    }
    final price = row['unit_price'];
    if (price is! num || !price.isFinite || price < 0) {
      throw FormatException('$at: السعر غير صالح.');
    }
    final quantity = row['quantity'];
    if (quantity is! num || !quantity.isFinite || quantity <= 0) {
      throw FormatException('$at: الكمية غير صالحة.');
    }
    var currency = row['currency_code'];
    if (currency == null && version == 1) {
      // Schema v1 did not store currency; those records were displayed as YER.
      currency = AppCurrencies.legacyDefault;
    }
    if (!AppCurrencies.isSupported(currency)) {
      throw FormatException('$at: العملة غير مدعومة ($currency).');
    }
    final productId = row['product_id'];
    if (productId is! int) throw FormatException('$at: معرّف الصنف غير صالح.');
    return <String, Object?>{
      'id': _positiveId(row, 'id', at),
      'product_id': productId,
      dateColumn: date,
      'unit_price': price.toDouble(),
      'currency_code': currency,
      'quantity': quantity.toDouble(),
      partyColumn: _optionalText(row, partyColumn, at),
      if (isPurchase) 'invoice_number': _optionalText(row, 'invoice_number', at),
      'notes': _optionalText(row, 'notes', at),
      'created_at': _timestamp(row, 'created_at', at),
      'import_batch_id': _optionalText(row, 'import_batch_id', at),
    };
  }

  static Map<String, Object?> _batch(Map row, String at) {
    const allowed = <String>{
      'id', 'file_name', 'created_at', 'products_added', 'entries_added', 'unarchived_product_ids', 'undone_at',
    };
    _rejectUnknown(row, allowed, at);
    final id = row['id'];
    if (id is! String || id.isEmpty) throw FormatException('$at: معرّف الدفعة غير صالح.');
    int count(String key) {
      final value = row[key] ?? 0;
      if (value is! int || value < 0) throw FormatException('$at: القيمة $key غير صالحة.');
      return value;
    }

    final undone = row['undone_at'];
    return <String, Object?>{
      'id': id,
      'file_name': _optionalText(row, 'file_name', at),
      'created_at': _timestamp(row, 'created_at', at),
      'products_added': count('products_added'),
      'entries_added': count('entries_added'),
      'unarchived_product_ids': _optionalText(row, 'unarchived_product_ids', at),
      'undone_at': undone == null ? null : _timestamp(row, 'undone_at', at),
    };
  }

  static void _rejectUnknown(Map row, Set<String> allowed, String at) {
    for (final key in row.keys) {
      if (key is! String || !allowed.contains(key)) {
        throw FormatException('$at: الحقل "$key" غير معروف؛ قد تكون النسخة من إصدار أحدث.');
      }
    }
  }

  static int _positiveId(Map row, String key, String at) {
    final value = row[key];
    if (value is! int || value <= 0) throw FormatException('$at: المعرّف غير صالح.');
    return value;
  }

  static String _requiredText(Map row, String key, String at) {
    final value = row[key];
    if (value is! String || value.trim().isEmpty) throw FormatException('$at: الحقل $key مطلوب.');
    return value.trim();
  }

  static String? _optionalText(Map row, String key, String at) {
    final value = row[key];
    if (value == null) return null;
    if (value is! String) throw FormatException('$at: الحقل $key يجب أن يكون نصًا.');
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int _flag(Map row, String key, String at) {
    final value = row[key];
    if (value == 0 || value == false) return 0;
    if (value == 1 || value == true) return 1;
    throw FormatException('$at: القيمة $key يجب أن تكون 0 أو 1.');
  }

  static String _timestamp(Map row, String key, String at) {
    final value = row[key];
    if (value is! String || DateTime.tryParse(value) == null) {
      throw FormatException('$at: الوقت $key غير صالح.');
    }
    return value;
  }

  static bool _isIsoDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
    final parsed = DateTime.tryParse(value);
    return parsed != null && toIsoDate(parsed) == value;
  }
}

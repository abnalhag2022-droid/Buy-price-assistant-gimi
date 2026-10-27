import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel_community/excel_community.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../state/app_settings.dart';
import '../utils/app_helpers.dart';
import '../utils/currencies.dart';
import '../utils/localized_message.dart';
import 'app_database.dart';

/// One data row of an imported sheet after parsing and row-level validation.
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

  /// 'PURCHASE', 'SALE', or '' for product-only rows.
  final String type;
  final String? date;
  final double? price, quantity;
  final String currency;
  final String? party, invoice, notes, createdAt;
  final List<Bilingual> errors, warnings;

  bool get isValid => errors.isEmpty;
  bool get isPurchase => type == 'PURCHASE';
}

class SpreadsheetIssue {
  const SpreadsheetIssue({required this.row, required this.text, required this.isError});

  /// Spreadsheet line number, or 0 for file-level notices.
  final int row;
  final Bilingual text;
  final bool isError;

  String get message => text.ar;
}

/// Result of parsing a file; safe to send between isolates.
class ParsedSpreadsheet {
  const ParsedSpreadsheet({required this.records, required this.fileIssues, required this.ignoredColumns});
  final List<SpreadsheetRecord> records;
  final List<SpreadsheetIssue> fileIssues;
  final List<String> ignoredColumns;
}

enum ImportGroupStatus { newProduct, matched, needsDecision }

enum CandidateReason { sameName, sameCode, reorderedName }

/// An existing product that an imported group might belong to.
class ImportCandidate {
  const ImportCandidate({
    required this.productId, required this.name, required this.unit, required this.code,
    required this.category, required this.brand, required this.archived,
    required this.reasons, required this.differences,
  });

  final int productId;
  final String name, unit;
  final String? code, category, brand;
  final bool archived;
  final Set<CandidateReason> reasons;

  /// Fields that differ from the imported product.
  final List<Bilingual> differences;
}

/// All valid rows of the file that describe the same product.
class ImportGroup {
  ImportGroup({
    required this.id, required this.name, required this.unit, required this.code,
    required this.category, required this.brand, required this.productNotes,
    required this.fileArchived, required this.fileFavorite, required this.rows,
  });

  final int id;
  final String name, unit;
  final String? code, category, brand, productNotes;
  final bool fileArchived, fileFavorite;
  final List<SpreadsheetRecord> rows;
  ImportGroupStatus status = ImportGroupStatus.newProduct;
  int? matchedProductId;
  List<ImportCandidate> candidates = const <ImportCandidate>[];
  final List<Bilingual> notices = <Bilingual>[];

  String get exactKey => SpreadsheetExchange.exactKey(name, unit);
  String get looseKey => SpreadsheetExchange.looseKey(name, unit);
  String get codeKey => normalizeForSearch(code ?? '');
  List<SpreadsheetRecord> get transactions => rows.where((r) => r.hasTransaction).toList();
  int get purchaseCount => rows.where((r) => r.hasTransaction && r.isPurchase).length;
  int get saleCount => rows.where((r) => r.hasTransaction && !r.isPurchase).length;
}

enum ImportDecisionKind { link, createNew, skip }

class ImportDecision {
  const ImportDecision.link(int this.productId) : kind = ImportDecisionKind.link;
  const ImportDecision.createNew() : kind = ImportDecisionKind.createNew, productId = null;
  const ImportDecision.skip() : kind = ImportDecisionKind.skip, productId = null;

  final ImportDecisionKind kind;
  final int? productId;

  @override
  bool operator ==(Object other) => other is ImportDecision && other.kind == kind && other.productId == productId;

  @override
  int get hashCode => Object.hash(kind, productId);
}

class SpreadsheetPreview {
  SpreadsheetPreview({required this.fileName, required this.parsed, required this.groups});

  final String fileName;
  final ParsedSpreadsheet parsed;
  final List<ImportGroup> groups;

  List<SpreadsheetRecord> get rows => parsed.records;
  List<SpreadsheetRecord> get rejectedRows => parsed.records.where((r) => !r.isValid).toList();
  List<SpreadsheetIssue> get fileErrors => parsed.fileIssues.where((i) => i.isError).toList();

  /// Every notice in line order: file-level, then row errors and warnings.
  List<SpreadsheetIssue> get issues => <SpreadsheetIssue>[
        ...parsed.fileIssues,
        for (final r in parsed.records) ...[
          for (final m in r.errors) SpreadsheetIssue(row: r.line, text: m, isError: true),
          for (final m in r.warnings) SpreadsheetIssue(row: r.line, text: m, isError: false),
        ],
      ];

  int get validTransactionCount => groups.fold(0, (sum, g) => sum + g.transactions.length);
  int get matchedProducts => groups.where((g) => g.status == ImportGroupStatus.matched).length;
  int get newProducts => groups.where((g) => g.status == ImportGroupStatus.newProduct).length;
  int get decisionsNeeded => groups.where((g) => g.status == ImportGroupStatus.needsDecision).length;

  /// Decisions the app can take without asking: matched → link, new → create.
  Map<int, ImportDecision> get automaticDecisions => <int, ImportDecision>{
        for (final g in groups)
          if (g.status == ImportGroupStatus.matched)
            g.id: ImportDecision.link(g.matchedProductId!)
          else if (g.status == ImportGroupStatus.newProduct)
            g.id: const ImportDecision.createNew(),
      };
}

/// One price record the import would write.
class PlannedEntry {
  const PlannedEntry({required this.group, required this.record, required this.duplicateInDatabase, required this.duplicateInFile});
  final ImportGroup group;
  final SpreadsheetRecord record;
  final bool duplicateInDatabase, duplicateInFile;
  bool get isDuplicate => duplicateInDatabase || duplicateInFile;
}

/// What the import will do with the current decisions.
class ImportPlan {
  const ImportPlan({required this.preview, required this.decisions, required this.entries});

  final SpreadsheetPreview preview;
  final Map<int, ImportDecision> decisions;
  final List<PlannedEntry> entries;

  List<ImportGroup> get undecidedGroups =>
      preview.groups.where((g) => !decisions.containsKey(g.id)).toList();
  List<ImportGroup> groupsWith(ImportDecisionKind kind) =>
      preview.groups.where((g) => decisions[g.id]?.kind == kind).toList();
  int get productsToCreate => groupsWith(ImportDecisionKind.createNew).length;
  int get duplicateCount => entries.where((e) => e.isDuplicate).length;
  int entriesToWrite({required bool includeDuplicates}) =>
      entries.where((e) => includeDuplicates || !e.isDuplicate).length;

  List<int> get productsToUnarchive {
    final ids = <int>{};
    for (final g in groupsWith(ImportDecisionKind.link)) {
      final id = decisions[g.id]!.productId;
      final candidate = g.candidates.where((c) => c.productId == id);
      if (candidate.isNotEmpty && candidate.first.archived) ids.add(id!);
    }
    return ids.toList();
  }

  bool canImport({required bool acceptRejectedRows, required bool includeDuplicates}) =>
      preview.fileErrors.isEmpty &&
      undecidedGroups.isEmpty &&
      (preview.rejectedRows.isEmpty || acceptRejectedRows) &&
      (entriesToWrite(includeDuplicates: includeDuplicates) > 0 ||
          productsToCreate > 0 ||
          productsToUnarchive.isNotEmpty);
}

class SpreadsheetImportResult {
  const SpreadsheetImportResult({
    required this.batchId, required this.productsAdded, required this.transactionsAdded,
    required this.duplicatesSkipped, required this.productsUnarchived,
  });
  final String batchId;
  final int productsAdded, transactionsAdded, duplicatesSkipped, productsUnarchived;
}

class SpreadsheetImportException implements Exception, LocalizedMessage {
  const SpreadsheetImportException(this.ar, this.en);
  @override
  final String ar;
  @override
  final String en;
  String get message => ar;
  @override
  String toString() => ar;
}

/// Spreadsheet import/export. Import never overwrites product metadata or
/// existing price records, and never merges non-identical product names
/// without an explicit user decision. JSON backup/restore stays separate.
class SpreadsheetExchange {
  SpreadsheetExchange._(this._dbOverride);

  /// Uses the current [AppDatabase.instance] each time (replaceable in tests).
  static final SpreadsheetExchange instance = SpreadsheetExchange._(null);
  factory SpreadsheetExchange.forDatabase(AppDatabase db) => SpreadsheetExchange._(db);
  final AppDatabase? _dbOverride;
  AppDatabase get _db => _dbOverride ?? AppDatabase.instance;

  static const int maxFileBytes = 20 * 1024 * 1024;
  static const int maxDataRows = 100000;

  static const headers = <String>[
    'Type', 'Product Name', 'Unit', 'Code', 'Category', 'Brand', 'Product Notes',
    'Date', 'Unit Price', 'Currency', 'Quantity', 'Supplier/Customer',
    'Invoice Number', 'Entry Notes', 'Product Archived', 'Product Favorite',
    'Record Created At',
  ];

  static const Map<String, Bilingual> _fieldLabels = {
    'type': Bilingual('نوع العملية', 'Type'), 'name': Bilingual('اسم الصنف', 'Product Name'),
    'unit': Bilingual('الوحدة', 'Unit'), 'code': Bilingual('الكود', 'Code'),
    'category': Bilingual('التصنيف', 'Category'), 'brand': Bilingual('العلامة التجارية', 'Brand'),
    'productNotes': Bilingual('ملاحظات الصنف', 'Product Notes'), 'date': Bilingual('التاريخ', 'Date'),
    'purchaseDate': Bilingual('تاريخ الشراء', 'Purchase Date'), 'saleDate': Bilingual('تاريخ البيع', 'Sale Date'),
    'price': Bilingual('السعر', 'Price'), 'purchasePrice': Bilingual('سعر الشراء', 'Purchase Price'),
    'salePrice': Bilingual('سعر البيع', 'Sale Price'), 'currency': Bilingual('العملة', 'Currency'),
    'quantity': Bilingual('الكمية', 'Quantity'), 'party': Bilingual('المورد/العميل', 'Supplier/Customer'),
    'supplier': Bilingual('المورد', 'Supplier'), 'customer': Bilingual('العميل', 'Customer'),
    'invoice': Bilingual('رقم الفاتورة', 'Invoice Number'), 'notes': Bilingual('ملاحظات العملية', 'Entry Notes'),
    'archived': Bilingual('مؤرشف', 'Archived'), 'favorite': Bilingual('مفضل', 'Favorite'),
    'createdAt': Bilingual('وقت الإنشاء', 'Created At'),
  };

  /// Header aliases after [normalizeColumnHeader]. Role-specific columns
  /// (supplier/customer, purchase/sale price and date) are resolved per row
  /// type, so a sheet may carry both without one silently hiding the other.
  static const Map<String, List<String>> _aliases = {
    'type': ['type', 'transactiontype', 'operationtype', 'entrytype', 'نوعالعملية', 'نوع', 'النوع', 'حركة'],
    'name': ['productname', 'itemname', 'name', 'product', 'item', 'اسمالصنف', 'الصنف', 'اسمالمنتج', 'المنتج', 'اسم'],
    'unit': ['unit', 'unitofmeasure', 'uom', 'الوحدة', 'وحدة', 'وحدةالقياس', 'وحدةالصنف'],
    'code': ['code', 'productcode', 'itemcode', 'sku', 'barcode', 'الكود', 'كود', 'كودالصنف', 'الباركود'],
    'category': ['category', 'productcategory', 'التصنيف', 'تصنيف', 'فئة'],
    'brand': ['brand', 'manufacturer', 'الماركة', 'العلامةالتجارية', 'الشركة'],
    'productNotes': ['productnotes', 'itemnotes', 'ملاحظاتالصنف', 'ملاحظاتالمنتج'],
    'date': ['date', 'entrydate', 'transactiondate', 'التاريخ', 'تاريخ', 'تاريخالعملية'],
    'purchaseDate': ['purchasedate', 'تاريخالشراء'],
    'saleDate': ['saledate', 'تاريخالبيع'],
    'price': ['unitprice', 'price', 'priceperunit', 'السعر', 'سعرالوحدة', 'سعر'],
    'purchasePrice': ['purchaseprice', 'buyprice', 'سعرالشراء'],
    'salePrice': ['saleprice', 'sellprice', 'سعرالبيع'],
    'currency': ['currency', 'currencycode', 'العملة', 'رمزالعملة'],
    'quantity': ['quantity', 'qty', 'الكمية', 'كمية'],
    'party': ['suppliercustomer', 'party', 'partyname', 'الجهة', 'الموردالعميل'],
    'supplier': ['supplier', 'المورد', 'اسمالمورد'],
    'customer': ['customer', 'العميل', 'اسمالعميل'],
    'invoice': ['invoicenumber', 'invoice', 'billnumber', 'رقمالفاتورة', 'فاتورة'],
    'notes': ['entrynotes', 'transactionnotes', 'notes', 'ملاحظاتالعملية', 'ملاحظاتالسجل', 'ملاحظات'],
    'archived': ['productarchived', 'isarchived', 'مؤرشف', 'الصنفمؤرشف'],
    'favorite': ['productfavorite', 'isfavorite', 'مفضل', 'المفضلة'],
    'createdAt': ['recordcreatedat', 'createdat', 'تاريخالانشاء'],
  };

  static String normalizeColumnHeader(String value) =>
      normalizeForSearch(value).replaceAll(RegExp(r'[\s_\-./\\()\[\]{}:]+'), '');

  /// Order-sensitive identity of a product name: words, digits and their order
  /// all count. "كابل 2 خط 4 ملم" and "كابل 4 خط 2 ملم" are different keys.
  static String exactKey(String name, String unit) =>
      '${normalizeForSearch(name)}\u001f${normalizeForSearch(unit)}';

  /// Order-insensitive key used only to *detect* possible duplicates that the
  /// user must confirm; it is never used to merge automatically.
  static String looseKey(String name, String unit) {
    final tokens = normalizeForSearch(name).split(' ').where((t) => t.isNotEmpty).toList()..sort();
    return '${tokens.join(' ')}\u001f${normalizeForSearch(unit)}';
  }

  /// Parses YYYY-MM-DD (also with / or .), DD/MM/YYYY and Excel serial dates.
  static String? normalizeDateValue(String input) => _parseDate(input)?.iso;

  static _ParsedDate? _parseDate(String input) {
    final value = normalizeDigits(input.trim()).replaceAll('٫', '.').replaceAll('٬', '').replaceAll(',', '');
    if (value.isEmpty) return null;
    DateTime? checked(int y, int m, int d) {
      if (m < 1 || m > 12 || d < 1 || d > 31) return null;
      final date = DateTime.utc(y, m, d);
      return date.year == y && date.month == m && date.day == d ? date : null;
    }

    final iso = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[ T].*)?$').firstMatch(value);
    if (iso != null) {
      final d = checked(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
      return d == null ? null : _ParsedDate(toIsoDate(d), _DateKind.iso, 0, 0);
    }
    final dmy = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$').firstMatch(value);
    if (dmy != null) {
      final first = int.parse(dmy[1]!);
      final second = int.parse(dmy[2]!);
      final d = checked(int.parse(dmy[3]!), second, first);
      return d == null
          ? _ParsedDate(null, _DateKind.dayMonth, first, second)
          : _ParsedDate(toIsoDate(d), _DateKind.dayMonth, first, second);
    }
    final serial = double.tryParse(value);
    if (serial != null && serial >= 20000 && serial <= 100000) {
      // Excel's day zero; UTC avoids daylight-saving shifts changing the day.
      final date = DateTime.utc(1899, 12, 30).add(Duration(days: serial.floor()));
      return _ParsedDate(toIsoDate(date), _DateKind.serial, 0, 0);
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
    if (raw is DoubleCellValue) return editableNumber(raw.value);
    if (raw is BoolCellValue) return raw.value ? 'true' : 'false';
    if (raw is FormulaCellValue) return raw.formula;
    return raw.toString().trim();
  }

  /// Characters that make spreadsheet programs treat a cell as a formula.
  static const String _formulaTriggers = '=+-@\t\r\n\uFF1D\uFF0B\uFF0D\uFF20';

  static bool needsFormulaGuard(String value) => value.isNotEmpty && _formulaTriggers.contains(value[0]);

  /// Removes the apostrophe this app adds on export before formula characters.
  static String _clean(String value) {
    final v = value.trim();
    return v.length > 1 && v.startsWith("'") && _formulaTriggers.contains(v[1]) ? v.substring(1) : v;
  }

  static String? _nullable(String s) => s.trim().isEmpty ? null : s.trim();
  static bool _flag(String s) => const {'1', 'true', 'yes', 'y', 'نعم'}.contains(normalizeForSearch(s));

  // ---------------------------------------------------------------- parsing

  /// Decodes and validates the file in a background isolate, then compares it
  /// with the database. Nothing is written.
  Future<SpreadsheetPreview> previewBytes(Uint8List bytes, String filename) async {
    final currency = AppSettings.instance.currency;
    final parsed = await Isolate.run(() => parseSpreadsheet(bytes, filename, defaultCurrency: currency));
    return analyze(parsed, filename, await _db.database);
  }

  /// Pure parsing step (no database). Throws [FormatException] for unreadable files.
  static ParsedSpreadsheet parseSpreadsheet(Uint8List bytes, String filename, {required String defaultCurrency}) {
    if (bytes.isEmpty) throw const LocalizedFormatException('الملف فارغ.', 'The file is empty.');
    if (bytes.length > maxFileBytes) {
      throw const LocalizedFormatException(
        'حجم الملف أكبر من 20 ميغابايت. قسّمه إلى ملفات أصغر.',
        'The file is larger than 20 MB. Split it into smaller files.',
      );
    }
    final lower = filename.toLowerCase();
    final fileIssues = <SpreadsheetIssue>[];
    List<List<String>> matrix;
    if (lower.endsWith('.xls')) {
      throw const LocalizedFormatException(
        'صيغة XLS القديمة غير مدعومة. احفظ الملف من Excel بصيغة XLSX أو CSV UTF-8.',
        'The old XLS format is not supported. Save the file from Excel as XLSX or CSV UTF-8.',
      );
    } else if (lower.endsWith('.csv')) {
      matrix = _readCsv(bytes);
    } else if (lower.endsWith('.xlsx')) {
      try {
        final workbook = Excel.decodeBytes(bytes);
        final sheets = workbook.tables.entries.where((s) => s.value.rows.isNotEmpty).toList();
        if (sheets.isEmpty) {
          throw const LocalizedFormatException('لا توجد بيانات في ملف Excel.', 'The Excel file contains no data.');
        }
        if (sheets.length > 1) {
          fileIssues.add(SpreadsheetIssue(row: 0, isError: false, text: Bilingual(
            'يحتوي الملف على ${sheets.length} أوراق؛ قُرئت الورقة الأولى فقط: «${sheets.first.key}».',
            'The file has ${sheets.length} sheets; only the first one was read: "${sheets.first.key}".',
          )));
        }
        matrix = sheets.first.value.rows.map((row) => row.map(_cellText).toList()).toList();
      } on FormatException {
        rethrow;
      } catch (_) {
        throw const LocalizedFormatException(
          'تعذر قراءة ملف XLSX. تأكد أنه سليم وغير محمي بكلمة مرور.',
          'The XLSX file could not be read. Check that it is not damaged or password-protected.',
        );
      }
    } else {
      throw const LocalizedFormatException('الصيغ المدعومة هي XLSX وCSV بترميز UTF-8.', 'Supported formats are XLSX and UTF-8 CSV.');
    }
    if (matrix.isEmpty) throw const LocalizedFormatException('لا يحتوي الملف على بيانات.', 'The file contains no data.');
    if (matrix.length - 1 > maxDataRows) {
      throw const LocalizedFormatException(
        'عدد الصفوف أكبر من 100,000. قسّم الملف إلى ملفات أصغر.',
        'The file has more than 100,000 rows. Split it into smaller files.',
      );
    }

    // ---- header mapping
    final header = matrix.first;
    final columns = <String, List<int>>{};
    final ignored = <String>[];
    for (var i = 0; i < header.length; i++) {
      final title = header[i].trim();
      if (title.isEmpty) continue;
      final h = normalizeColumnHeader(title);
      final field = _aliases.entries.where((e) => e.value.contains(h)).map((e) => e.key).firstOrNull;
      if (field == null) {
        ignored.add(title);
      } else {
        columns.putIfAbsent(field, () => <int>[]).add(i);
      }
    }
    if (!columns.containsKey('name') || !columns.containsKey('unit')) {
      throw const LocalizedFormatException(
        'يجب أن يحتوي صف العناوين على عمودي اسم الصنف ووحدة القياس.',
        'The header row must contain the Product Name and Unit columns.',
      );
    }
    for (final entry in columns.entries) {
      if (entry.value.length > 1) {
        final titles = entry.value.map((i) => header[i].trim());
        final label = _fieldLabels[entry.key]!;
        fileIssues.add(SpreadsheetIssue(row: 0, isError: true, text: Bilingual(
          'الأعمدة ${titles.map((t) => '«$t»').join(' و')} تمثل الحقل نفسه (${label.ar}). احذف المكرر حتى لا تُستخدم قيمة خاطئة.',
          'The columns ${titles.map((t) => '"$t"').join(' and ')} are the same field (${label.en}). Remove the duplicate so a wrong value is not used.',
        )));
      }
    }
    if (ignored.isNotEmpty) {
      fileIssues.add(SpreadsheetIssue(row: 0, isError: false, text: Bilingual(
        'أعمدة غير معروفة لن تُستورد: ${ignored.map((t) => '«$t»').join('، ')}.',
        'Unknown columns will not be imported: ${ignored.map((t) => '"$t"').join(', ')}.',
      )));
    }

    // ---- rows
    final records = <SpreadsheetRecord>[];
    final ambiguousDates = <int>[];
    var dayFirstProven = false;
    for (var i = 1; i < matrix.length; i++) {
      final values = matrix[i];
      if (values.every((v) => v.trim().isEmpty)) continue;
      String get(String field) {
        final index = columns[field]?.first;
        return index == null || index >= values.length ? '' : _clean(values[index]);
      }

      final name = get('name');
      final unit = get('unit');
      final typeRaw = normalizeColumnHeader(get('type'));
      final type = const {'purchase', 'buy', 'p', 'شراء', 'مشتريات', 'وارد'}.contains(typeRaw)
          ? 'PURCHASE'
          : const {'sale', 'sell', 's', 'بيع', 'مبيعات', 'صادر'}.contains(typeRaw) ? 'SALE' : '';
      final isSale = type == 'SALE';
      String pick(String specific, String generic) {
        final value = get(specific);
        return value.isNotEmpty ? value : get(generic);
      }

      final dateRaw = type.isEmpty ? (get('date').isNotEmpty ? get('date') : pick('purchaseDate', 'saleDate'))
          : pick(isSale ? 'saleDate' : 'purchaseDate', 'date');
      final priceRaw = type.isEmpty ? (get('price').isNotEmpty ? get('price') : pick('purchasePrice', 'salePrice'))
          : pick(isSale ? 'salePrice' : 'purchasePrice', 'price');
      final party = type.isEmpty ? (get('party').isNotEmpty ? get('party') : pick('supplier', 'customer'))
          : pick(isSale ? 'customer' : 'supplier', 'party');
      final quantityRaw = get('quantity');
      final invoiceRaw = get('invoice');
      final invoice = isSale ? '' : invoiceRaw;
      final notes = get('notes');
      final hasTransaction = [get('type'), dateRaw, priceRaw, quantityRaw, party, invoiceRaw, notes].any((v) => v.isNotEmpty);
      final errors = <Bilingual>[];
      final warnings = <Bilingual>[];
      if (name.isEmpty) errors.add(const Bilingual('اسم الصنف مطلوب.', 'The product name is required.'));
      if (unit.isEmpty) errors.add(const Bilingual('وحدة القياس مطلوبة.', 'The unit is required.'));
      String? date;
      double? price;
      double? quantity;
      var currency = get('currency').toUpperCase();
      if (hasTransaction) {
        final parsedDate = _parseDate(dateRaw);
        date = parsedDate?.iso;
        if (type.isEmpty) {
          errors.add(const Bilingual('نوع العملية مطلوب: PURCHASE أو SALE (شراء أو بيع).', 'The type is required: PURCHASE or SALE.'));
        }
        if (date == null) {
          if (parsedDate != null && parsedDate.kind == _DateKind.dayMonth && parsedDate.second > 12 && parsedDate.first <= 12) {
            errors.add(Bilingual(
              'التاريخ «$dateRaw» يبدو بصيغة شهر/يوم/سنة. استخدم YYYY-MM-DD أو يوم/شهر/سنة.',
              'The date "$dateRaw" looks like month/day/year. Use YYYY-MM-DD or day/month/year.',
            ));
          } else {
            errors.add(const Bilingual('التاريخ غير صحيح؛ استخدم YYYY-MM-DD أو DD/MM/YYYY.', 'Invalid date; use YYYY-MM-DD or DD/MM/YYYY.'));
          }
        } else if (parsedDate!.kind == _DateKind.dayMonth) {
          if (parsedDate.first > 12) dayFirstProven = true;
          if (parsedDate.first <= 12 && parsedDate.second <= 12 && parsedDate.first != parsedDate.second) {
            ambiguousDates.add(i + 1);
          }
        }
        price = parseLocalizedNumber(priceRaw);
        quantity = parseLocalizedNumber(quantityRaw);
        if (price == null || price < 0) {
          errors.add(const Bilingual('سعر الوحدة مطلوب ويجب ألا يكون سالبًا.', 'The unit price is required and cannot be negative.'));
        }
        if (quantity == null || quantity <= 0) {
          errors.add(const Bilingual('الكمية مطلوبة ويجب أن تكون أكبر من صفر.', 'The quantity is required and must be greater than zero.'));
        }
        if (currency.isEmpty) {
          currency = defaultCurrency;
          warnings.add(Bilingual(
            'العملة غير محددة؛ ستُستخدم العملة الافتراضية $currency.',
            'No currency given; the default currency $currency will be used.',
          ));
        }
        if (!AppCurrencies.isSupported(currency)) {
          errors.add(Bilingual(
            'العملة يجب أن تكون ${AppCurrencies.supported.join(' أو ')}.',
            'The currency must be ${AppCurrencies.supported.join(', ')}.',
          ));
        }
        if (isSale && invoiceRaw.isNotEmpty) {
          warnings.add(const Bilingual('رقم الفاتورة غير مدعوم في سجلات البيع؛ سيُتجاهل.', 'Sale records have no invoice number; it will be ignored.'));
        }
      }
      String? created;
      final createdRaw = get('createdAt');
      if (createdRaw.isNotEmpty) {
        final parsed = DateTime.tryParse(createdRaw);
        if (parsed == null) {
          warnings.add(const Bilingual('وقت إنشاء السجل غير صالح؛ سيُستخدم الوقت الحالي.', 'Invalid record creation time; the current time will be used.'));
        } else {
          created = parsed.toIso8601String();
        }
      }
      records.add(SpreadsheetRecord(
        line: i + 1, name: name, unit: unit, code: _nullable(get('code')),
        category: _nullable(get('category')), brand: _nullable(get('brand')),
        productNotes: _nullable(get('productNotes')), productArchived: _flag(get('archived')),
        productFavorite: _flag(get('favorite')), type: type, hasTransaction: hasTransaction,
        date: date, price: price, quantity: quantity, currency: currency,
        party: _nullable(party), invoice: _nullable(invoice), notes: _nullable(notes),
        createdAt: created, errors: errors, warnings: warnings,
      ));
    }
    if (records.isEmpty) {
      throw const LocalizedFormatException('لا يحتوي الملف على صفوف بيانات بعد صف العناوين.', 'The file has no data rows after the header row.');
    }
    if (ambiguousDates.isNotEmpty && !dayFirstProven) {
      fileIssues.add(SpreadsheetIssue(row: 0, isError: false, text: Bilingual(
        'قُرئت ${ambiguousDates.length} تواريخ بصيغة يوم/شهر/سنة (مثل 03/04/2026 = 3 أبريل). '
            'تأكد أن الملف لا يستخدم صيغة شهر/يوم/سنة.',
        '${ambiguousDates.length} dates were read as day/month/year (03/04/2026 = 3 April). '
            'Make sure the file does not use month/day/year.',
      )));
    }
    return ParsedSpreadsheet(records: records, fileIssues: fileIssues, ignoredColumns: ignored);
  }

  static List<List<String>> _readCsv(Uint8List bytes) {
    if (bytes.length >= 2 && ((bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
      throw const LocalizedFormatException(
        'الملف بترميز UTF-16. احفظه من Excel بصيغة «CSV UTF-8» أو XLSX.',
        'The file is UTF-16 encoded. Save it from Excel as "CSV UTF-8" or XLSX.',
      );
    }
    final String source;
    try {
      source = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const LocalizedFormatException(
        'ترميز الملف ليس UTF-8 (غالبًا Windows-1256 من Excel). احفظه بصيغة «CSV UTF-8 (Comma delimited)» أو XLSX ثم أعد المحاولة.',
        'The file is not UTF-8 (often Windows-1256 from Excel). Save it as "CSV UTF-8 (Comma delimited)" or XLSX and try again.',
      );
    }
    final text = source.replaceFirst('\uFEFF', '').replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    List<List<String>> parse(String delimiter) => CsvToListConverter(
          fieldDelimiter: delimiter, shouldParseNumbers: false, eol: '\n',
        ).convert(text).map((row) => row.map((v) => v?.toString() ?? '').toList()).toList();
    var matrix = parse(',');
    if (matrix.isNotEmpty && !_hasHeaders(matrix.first)) {
      final other = parse(';');
      if (other.isNotEmpty && _hasHeaders(other.first)) matrix = other;
    }
    return matrix;
  }

  static bool _hasHeaders(List<String> values) {
    final found = <String>{};
    for (final value in values) {
      final h = normalizeColumnHeader(value);
      for (final entry in _aliases.entries) {
        if (entry.value.contains(h)) found.add(entry.key);
      }
    }
    return found.contains('name') && found.contains('unit');
  }

  // ---------------------------------------------------------------- analysis

  /// Groups valid rows by product and compares each group with existing products.
  static Future<SpreadsheetPreview> analyze(ParsedSpreadsheet parsed, String fileName, DatabaseExecutor ex) async {
    final groups = _group(parsed.records.where((r) => r.isValid).toList());
    final products = await ex.query('products',
        columns: ['id', 'name', 'unit', 'code', 'category', 'brand', 'is_archived'], orderBy: 'id ASC');
    final byExact = <String, List<Map<String, Object?>>>{};
    final byLoose = <String, List<Map<String, Object?>>>{};
    final byCode = <String, List<Map<String, Object?>>>{};
    for (final p in products) {
      final name = p['name']! as String;
      final unit = p['unit']! as String;
      byExact.putIfAbsent(exactKey(name, unit), () => []).add(p);
      byLoose.putIfAbsent(looseKey(name, unit), () => []).add(p);
      final code = normalizeForSearch(p['code'] as String? ?? '');
      if (code.isNotEmpty) byCode.putIfAbsent(code, () => []).add(p);
    }
    bool archived(Map<String, Object?> p) => (p['is_archived'] as num? ?? 0) == 1;

    for (final g in groups) {
      final exact = byExact[g.exactKey] ?? const <Map<String, Object?>>[];
      final exactActive = exact.where((p) => !archived(p)).toList();
      final codeHits = g.codeKey.isEmpty ? const <Map<String, Object?>>[] : (byCode[g.codeKey] ?? const []);
      final loose = (byLoose[g.looseKey] ?? const <Map<String, Object?>>[])
          .where((p) => exactKey(p['name']! as String, p['unit']! as String) != g.exactKey)
          .toList();

      if (codeHits.isNotEmpty) {
        final hit = codeHits.length == 1 ? codeHits.single : null;
        if (hit != null && !archived(hit) && exactKey(hit['name']! as String, hit['unit']! as String) == g.exactKey) {
          g.status = ImportGroupStatus.matched;
          g.matchedProductId = hit['id']! as int;
        } else {
          g.status = ImportGroupStatus.needsDecision;
          g.candidates = _candidates(g, [...codeHits, ...exact, ...loose]);
        }
      } else if (exactActive.length == 1) {
        final hit = exactActive.single;
        final hitCode = normalizeForSearch(hit['code'] as String? ?? '');
        if (g.codeKey.isNotEmpty && hitCode.isNotEmpty && hitCode != g.codeKey) {
          g.status = ImportGroupStatus.needsDecision;
          g.candidates = _candidates(g, exact);
        } else {
          g.status = ImportGroupStatus.matched;
          g.matchedProductId = hit['id']! as int;
        }
      } else if (exact.isNotEmpty || loose.isNotEmpty) {
        g.status = ImportGroupStatus.needsDecision;
        g.candidates = _candidates(g, [...exact, ...loose]);
      } else {
        g.status = ImportGroupStatus.newProduct;
      }
    }

    // Similar names inside the file stay separate products; say so explicitly.
    final byFileLoose = <String, List<ImportGroup>>{};
    for (final g in groups) {
      byFileLoose.putIfAbsent(g.looseKey, () => []).add(g);
    }
    for (final similar in byFileLoose.values.where((list) => list.length > 1)) {
      for (final g in similar) {
        final others = similar.where((o) => o != g).map((o) => o.name);
        g.notices.add(Bilingual(
          'في الملف أسماء متشابهة بترتيب كلمات أو كود مختلف: ${others.map((n) => '«$n»').join('، ')}. ستُعامل كأصناف منفصلة.',
          'The file has similar names with another word order or code: ${others.map((n) => '"$n"').join(', ')}. They stay separate products.',
        ));
      }
    }
    for (final g in groups) {
      if (g.status == ImportGroupStatus.newProduct && g.purchaseCount == 0) {
        g.notices.add(g.saleCount == 0
            ? const Bilingual('صنف جديد بلا سجلات أسعار؛ ستُضاف بياناته فقط.', 'New product without price records; only its details are added.')
            : const Bilingual('صنف جديد بلا سعر شراء؛ سيحتوي على سجلات بيع فقط.', 'New product without a purchase price; it will only have sale records.'));
      }
      if (g.status == ImportGroupStatus.matched && g.fileArchived) {
        g.notices.add(const Bilingual(
          'الملف يحدد الصنف كمؤرشف بينما الصنف الموجود نشط؛ لن تتغير حالته.',
          'The file marks the product as archived but the existing one is active; its status stays as it is.',
        ));
      }
    }
    return SpreadsheetPreview(fileName: fileName, parsed: parsed, groups: groups);
  }

  static List<ImportGroup> _group(List<SpreadsheetRecord> rows) {
    final coded = <String, List<SpreadsheetRecord>>{};
    final uncoded = <String, List<SpreadsheetRecord>>{};
    for (final r in rows) {
      final key = exactKey(r.name, r.unit);
      final code = normalizeForSearch(r.code ?? '');
      if (code.isEmpty) {
        uncoded.putIfAbsent(key, () => []).add(r);
      } else {
        coded.putIfAbsent('$key\u001e$code', () => []).add(r);
      }
    }
    // Rows without a code join the single coded group of the same name, if any.
    final groupsByKey = <String, List<SpreadsheetRecord>>{...coded};
    for (final entry in uncoded.entries) {
      final sameName = coded.keys.where((k) => k.startsWith('${entry.key}\u001e')).toList();
      if (sameName.length == 1) {
        groupsByKey[sameName.single]!.addAll(entry.value);
      } else {
        groupsByKey['${entry.key}\u001e'] = entry.value;
      }
    }
    final ordered = groupsByKey.values.toList()
      ..sort((a, b) => a.map((r) => r.line).reduce((x, y) => x < y ? x : y)
          .compareTo(b.map((r) => r.line).reduce((x, y) => x < y ? x : y)));
    final result = <ImportGroup>[];
    for (var i = 0; i < ordered.length; i++) {
      final rows = ordered[i]..sort((a, b) => a.line.compareTo(b.line));
      String? firstOf(String? Function(SpreadsheetRecord r) read) =>
          rows.map(read).firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
      final group = ImportGroup(
        id: i, name: rows.first.name, unit: rows.first.unit, code: firstOf((r) => r.code),
        category: firstOf((r) => r.category), brand: firstOf((r) => r.brand),
        productNotes: firstOf((r) => r.productNotes),
        fileArchived: rows.first.productArchived, fileFavorite: rows.first.productFavorite, rows: rows,
      );
      bool differs(String? Function(SpreadsheetRecord r) read) =>
          rows.map(read).whereType<String>().where((v) => v.isNotEmpty).map(normalizeForSearch).toSet().length > 1;
      final mixed = <Bilingual>[
        if (differs((r) => r.category)) _fieldLabels['category']!,
        if (differs((r) => r.brand)) _fieldLabels['brand']!,
        if (differs((r) => r.productNotes)) _fieldLabels['productNotes']!,
      ];
      if (mixed.isNotEmpty) {
        group.notices.add(Bilingual(
          'قيم ${mixed.map((m) => m.ar).join(' و')} مختلفة بين صفوف الصنف؛ ستُستخدم أول قيمة غير فارغة.',
          '${mixed.map((m) => m.en).join(' and ')} differ between the rows of this product; the first non-empty value is used.',
        ));
      }
      result.add(group);
    }
    return result;
  }

  static List<ImportCandidate> _candidates(ImportGroup g, List<Map<String, Object?>> products) {
    final seen = <int>{};
    final result = <ImportCandidate>[];
    for (final p in products) {
      final id = p['id']! as int;
      if (!seen.add(id)) continue;
      final name = p['name']! as String;
      final unit = p['unit']! as String;
      final code = p['code'] as String?;
      final reasons = <CandidateReason>{
        if (exactKey(name, unit) == g.exactKey) CandidateReason.sameName,
        if (g.codeKey.isNotEmpty && normalizeForSearch(code ?? '') == g.codeKey) CandidateReason.sameCode,
        if (exactKey(name, unit) != g.exactKey && looseKey(name, unit) == g.looseKey) CandidateReason.reorderedName,
      };
      bool same(String? a, String? b) => normalizeForSearch(a ?? '') == normalizeForSearch(b ?? '');
      Bilingual diff(String field, Object? existing, Object? file) {
        final label = _fieldLabels[field]!;
        return Bilingual(
          '${label.ar}: «${existing ?? '—'}» مقابل «${file ?? '—'}» في الملف',
          '${label.en}: "${existing ?? '—'}" vs "${file ?? '—'}" in the file',
        );
      }

      final differences = <Bilingual>[
        if (!same(name, g.name)) diff('name', name, g.name),
        if (!same(unit, g.unit)) diff('unit', unit, g.unit),
        if (!same(code, g.code)) diff('code', code, g.code),
        if (g.category != null && !same(p['category'] as String?, g.category)) diff('category', p['category'], g.category),
        if (g.brand != null && !same(p['brand'] as String?, g.brand)) diff('brand', p['brand'], g.brand),
      ];
      result.add(ImportCandidate(
        productId: id, name: name, unit: unit, code: code, category: p['category'] as String?,
        brand: p['brand'] as String?, archived: (p['is_archived'] as num? ?? 0) == 1,
        reasons: reasons, differences: differences,
      ));
    }
    return result;
  }

  // ---------------------------------------------------------------- planning

  static String _signature(Object target, SpreadsheetRecord r) => [
        target, r.type, r.date, r.price!.toStringAsFixed(6), r.currency, r.quantity!.toStringAsFixed(6),
        normalizeForSearch(r.party ?? ''), normalizeForSearch(r.invoice ?? ''), normalizeForSearch(r.notes ?? ''),
      ].join('\u001e');

  static String _dbSignature(Object target, String type, Map<String, Object?> e) => [
        target, type, e['date'], (e['price']! as num).toDouble().toStringAsFixed(6), e['currency'],
        (e['quantity']! as num).toDouble().toStringAsFixed(6), normalizeForSearch(e['party'] as String? ?? ''),
        normalizeForSearch(e['invoice'] as String? ?? ''), normalizeForSearch(e['notes'] as String? ?? ''),
      ].join('\u001e');

  /// Applies [decisions] (missing groups stay undecided) and flags duplicates
  /// against existing records of the target products and within the file.
  Future<ImportPlan> buildPlan(SpreadsheetPreview preview, Map<int, ImportDecision> decisions) async =>
      _plan(preview, decisions, await _db.database);

  static Future<ImportPlan> _plan(
      SpreadsheetPreview preview, Map<int, ImportDecision> decisions, DatabaseExecutor ex) async {
    final effective = <int, ImportDecision>{};
    for (final g in preview.groups) {
      final decision = decisions[g.id] ?? preview.automaticDecisions[g.id];
      if (decision == null) continue;
      if (decision.kind == ImportDecisionKind.link) {
        final allowed = g.status == ImportGroupStatus.matched
            ? decision.productId == g.matchedProductId
            : g.candidates.any((c) => c.productId == decision.productId);
        if (!allowed) continue;
      }
      effective[g.id] = decision;
    }
    final targets = effective.values
        .where((d) => d.kind == ImportDecisionKind.link)
        .map((d) => d.productId!)
        .toSet();
    final known = <String>{};
    if (targets.isNotEmpty) {
      final placeholders = List.filled(targets.length, '?').join(',');
      final purchases = await ex.rawQuery(
        'SELECT product_id, purchase_date AS date, unit_price AS price, currency_code AS currency, quantity, '
        'supplier AS party, invoice_number AS invoice, notes FROM purchase_entries WHERE product_id IN ($placeholders)',
        targets.toList(),
      );
      for (final e in purchases) {
        known.add(_dbSignature(e['product_id']!, 'PURCHASE', e));
      }
      final sales = await ex.rawQuery(
        'SELECT product_id, sale_date AS date, unit_price AS price, currency_code AS currency, quantity, '
        'customer AS party, NULL AS invoice, notes FROM sale_entries WHERE product_id IN ($placeholders)',
        targets.toList(),
      );
      for (final e in sales) {
        known.add(_dbSignature(e['product_id']!, 'SALE', e));
      }
    }
    final seen = <String>{};
    final entries = <PlannedEntry>[];
    for (final g in preview.groups) {
      final decision = effective[g.id];
      if (decision == null || decision.kind == ImportDecisionKind.skip) continue;
      final Object target = decision.kind == ImportDecisionKind.link ? decision.productId! : 'new:${g.id}';
      for (final r in g.transactions) {
        final sig = _signature(target, r);
        entries.add(PlannedEntry(
          group: g, record: r,
          duplicateInDatabase: known.contains(sig),
          duplicateInFile: !seen.add(sig),
        ));
      }
    }
    return ImportPlan(preview: preview, decisions: effective, entries: entries);
  }

  // ---------------------------------------------------------------- import

  /// Writes the plan in one transaction tagged with a new import batch. The
  /// file is re-analysed inside the transaction; if the database changed since
  /// the preview, nothing is written.
  Future<SpreadsheetImportResult> importPreview(
    SpreadsheetPreview preview,
    Map<int, ImportDecision> decisions, {
    required bool includeDuplicates,
    required bool acceptRejectedRows,
  }) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final fresh = await analyze(preview.parsed, preview.fileName, txn);
      if (!_sameAnalysis(preview, fresh)) {
        throw const SpreadsheetImportException(
          'تغيرت بيانات الأصناف منذ المعاينة؛ أعد المعاينة ثم حاول مجددًا. لم يُكتب أي شيء.',
          'Products changed since the preview; preview the file again and retry. Nothing was written.',
        );
      }
      final plan = await _plan(fresh, decisions, txn);
      if (!plan.canImport(acceptRejectedRows: acceptRejectedRows, includeDuplicates: includeDuplicates)) {
        throw const SpreadsheetImportException(
          'الاستيراد غير مكتمل الشروط: راجع القرارات والأخطاء. لم يُكتب أي شيء.',
          'The import is not ready: review the decisions and errors. Nothing was written.',
        );
      }
      final batchId = AppDatabase.newImportBatchId();
      final now = DateTime.now().toIso8601String();
      await txn.insert('import_batches', {'id': batchId, 'file_name': preview.fileName, 'created_at': now});

      final productIds = <int, int>{};
      var productsAdded = 0;
      for (final g in plan.groupsWith(ImportDecisionKind.createNew)) {
        productIds[g.id] = await txn.insert('products', {
          'name': g.name,
          'search_name': normalizeForSearch(g.name),
          'code': g.code,
          'search_code': normalizeForSearch(g.code ?? ''),
          'category': g.category,
          'search_category': normalizeForSearch(g.category ?? ''),
          'unit': g.unit,
          'brand': g.brand,
          'notes': g.productNotes,
          'is_favorite': g.fileFavorite ? 1 : 0,
          'is_archived': g.fileArchived ? 1 : 0,
          'created_at': now,
          'updated_at': now,
          'import_batch_id': batchId,
        });
        productsAdded++;
      }
      for (final g in plan.groupsWith(ImportDecisionKind.link)) {
        productIds[g.id] = plan.decisions[g.id]!.productId!;
      }
      final unarchived = plan.productsToUnarchive;
      for (final id in unarchived) {
        await txn.update('products', {'is_archived': 0, 'updated_at': now}, where: 'id = ?', whereArgs: [id]);
      }

      var written = 0;
      var skipped = 0;
      for (final planned in plan.entries) {
        if (planned.isDuplicate && !includeDuplicates) {
          skipped++;
          continue;
        }
        final r = planned.record;
        final productId = productIds[planned.group.id]!;
        final createdAt = r.createdAt ?? now;
        if (r.isPurchase) {
          await txn.insert('purchase_entries', {
            'product_id': productId, 'purchase_date': r.date, 'unit_price': r.price,
            'currency_code': r.currency, 'quantity': r.quantity, 'supplier': r.party,
            'invoice_number': r.invoice, 'notes': r.notes, 'created_at': createdAt,
            'import_batch_id': batchId,
          });
        } else {
          await txn.insert('sale_entries', {
            'product_id': productId, 'sale_date': r.date, 'unit_price': r.price,
            'currency_code': r.currency, 'quantity': r.quantity, 'customer': r.party,
            'notes': r.notes, 'created_at': createdAt, 'import_batch_id': batchId,
          });
        }
        written++;
      }
      await AppDatabase.refreshSearchIndex(txn, productIds: productIds.values);
      await txn.update('import_batches', {
        'products_added': productsAdded,
        'entries_added': written,
        'unarchived_product_ids': unarchived.isEmpty ? null : jsonEncode(unarchived),
      }, where: 'id = ?', whereArgs: [batchId]);
      return SpreadsheetImportResult(
        batchId: batchId, productsAdded: productsAdded, transactionsAdded: written,
        duplicatesSkipped: skipped, productsUnarchived: unarchived.length,
      );
    });
  }

  static bool _sameAnalysis(SpreadsheetPreview a, SpreadsheetPreview b) {
    if (a.groups.length != b.groups.length) return false;
    for (var i = 0; i < a.groups.length; i++) {
      final x = a.groups[i];
      final y = b.groups[i];
      if (x.status != y.status || x.matchedProductId != y.matchedProductId) return false;
      final xs = x.candidates.map((c) => '${c.productId}:${c.archived}').toSet();
      final ys = y.candidates.map((c) => '${c.productId}:${c.archived}').toSet();
      if (xs.length != ys.length || !xs.containsAll(ys)) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------- export

  /// CSV with a UTF-8 BOM (so Excel shows Arabic correctly). Text that starts
  /// with a formula character gets a leading apostrophe; import removes it.
  Future<Uint8List> exportCsv() async {
    final rows = await _exportRows();
    final safe = rows.map((row) => row.map((value) {
          final s = value is num ? editableNumber(value) : (value?.toString() ?? '');
          return needsFormulaGuard(s) ? "'$s" : s;
        }).toList()).toList();
    final csv = const ListToCsvConverter().convert(safe);
    return Uint8List.fromList(utf8.encode('\uFEFF$csv'));
  }

  /// XLSX export: text is stored as text cells (never formulas), numbers as numbers.
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
    if (bytes == null || bytes.isEmpty) throw LocalizedStateError('تعذر إنشاء ملف Excel.', 'The Excel file could not be created.');
    return Uint8List.fromList(bytes);
  }

  Future<List<List<Object?>>> _exportRows() async {
    final db = await _db.database;
    final products = await db.query('products', orderBy: 'id ASC');
    final purchases = await db.query('purchase_entries', orderBy: 'purchase_date ASC, id ASC');
    final sales = await db.query('sale_entries', orderBy: 'sale_date ASC, id ASC');
    final history = <int, List<List<Object?>>>{};
    final productsById = <int, Map<String, Object?>>{for (final p in products) p['id']! as int: p};
    for (final p in purchases) {
      final product = productsById[p['product_id']! as int];
      if (product == null) continue;
      history.putIfAbsent(product['id']! as int, () => []).add(_entry(
        'PURCHASE', product, p['purchase_date']! as String, (p['unit_price']! as num).toDouble(),
        p['currency_code']! as String, (p['quantity']! as num).toDouble(), p['supplier'] as String?,
        p['invoice_number'] as String?, p['notes'] as String?, p['created_at'] as String?));
    }
    for (final s in sales) {
      final product = productsById[s['product_id']! as int];
      if (product == null) continue;
      history.putIfAbsent(product['id']! as int, () => []).add(_entry(
        'SALE', product, s['sale_date']! as String, (s['unit_price']! as num).toDouble(),
        s['currency_code']! as String, (s['quantity']! as num).toDouble(), s['customer'] as String?,
        null, s['notes'] as String?, s['created_at'] as String?));
    }
    final rows = <List<Object?>>[headers];
    for (final p in products) {
      final entries = history[p['id']! as int];
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

enum _DateKind { iso, dayMonth, serial }

class _ParsedDate {
  const _ParsedDate(this.iso, this.kind, this.first, this.second);
  final String? iso;
  final _DateKind kind;
  final int first, second;
}

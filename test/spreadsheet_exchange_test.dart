import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:buy_price_assistant_gimi/data/app_database.dart';
import 'package:buy_price_assistant_gimi/data/spreadsheet_exchange.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase db;
  late SpreadsheetExchange exchange;

  AppDatabase memoryDb() => AppDatabase(factory: databaseFactoryFfi, databasePathProvider: () async => ':memory:');

  setUp(() {
    db = memoryDb();
    exchange = SpreadsheetExchange.forDatabase(db);
  });
  tearDown(() async => db.close());

  Uint8List bytes(String csv) => Uint8List.fromList(utf8.encode(csv));
  const header = 'Type,Product Name,Unit,Code,Category,Brand,Product Notes,Date,Unit Price,Currency,Quantity,Supplier/Customer,Invoice Number,Entry Notes,Product Archived,Product Favorite,Record Created At\n';
  String purchase(String name, {String unit = 'قطعة', String code = '', String date = '2026-10-01', String price = '100', String currency = 'YER', String qty = '1', String party = 'مورد', String notes = ''}) =>
      'PURCHASE,$name,$unit,$code,,,,$date,$price,$currency,$qty,$party,,$notes,0,0,\n';

  Future<SpreadsheetPreview> preview(String csv) => exchange.previewBytes(bytes(csv), 'file.csv');

  Future<SpreadsheetImportResult> importAll(SpreadsheetPreview p, [Map<int, ImportDecision> choices = const {}, bool duplicates = false]) =>
      exchange.importPreview(p, {...p.automaticDecisions, ...choices}, includeDuplicates: duplicates, acceptRejectedRows: false);

  Future<int> countRows(String table) async =>
      (await (await db.database).rawQuery('SELECT COUNT(*) AS c FROM $table')).single['c']! as int;

  group('parsing', () {
    test('normalizes header names and dates', () {
      expect(SpreadsheetExchange.normalizeColumnHeader('Product Name'), 'productname');
      expect(SpreadsheetExchange.normalizeColumnHeader('اسم الصنف'), 'اسمالصنف');
      expect(SpreadsheetExchange.normalizeDateValue('21/10/2026'), '2026-10-21');
      expect(SpreadsheetExchange.normalizeDateValue('٢١/١٠/٢٠٢٦'), '2026-10-21');
      expect(SpreadsheetExchange.normalizeDateValue('2026-02-31'), isNull);
      expect(SpreadsheetExchange.normalizeDateValue('46000'), '2025-12-09');
    });

    test('reports month/day/year dates instead of guessing', () async {
      final p = await preview('$header${purchase('صنف', date: '04/25/2026')}');
      expect(p.rejectedRows.single.errors.single.ar, contains('شهر/يوم/سنة'));
    });

    test('warns when every slash date is ambiguous', () async {
      final p = await preview('$header${purchase('صنف', date: '03/04/2026')}');
      expect(p.rows.single.date, '2026-04-03');
      expect(p.parsed.fileIssues.any((i) => !i.isError && i.message.contains('يوم/شهر/سنة')), isTrue);
    });

    test('explains non UTF-8 and UTF-16 CSV files', () async {
      final cp1256 = Uint8List.fromList([...utf8.encode('Product Name,Unit\n'), 0xC7, 0xE1, 0x2C, 0x41, 0x0A]);
      await expectLater(exchange.previewBytes(cp1256, 'a.csv'),
          throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('UTF-8'))));
      final utf16 = Uint8List.fromList([0xFF, 0xFE, 0x41, 0x00]);
      await expectLater(exchange.previewBytes(utf16, 'a.csv'),
          throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('UTF-16'))));
    });

    test('rejects files above the size limit', () async {
      final big = Uint8List(SpreadsheetExchange.maxFileBytes + 1);
      await expectLater(exchange.previewBytes(big, 'big.csv'), throwsA(isA<FormatException>()));
    });

    test('blocks two columns that map to the same field', () async {
      const csv = 'Type,Product Name,Unit,Date,Price,Unit Price,Currency,Quantity\nPURCHASE,صنف,قطعة,2026-10-01,100,90,YER,1\n';
      final p = await preview(csv);
      expect(p.fileErrors, hasLength(1));
      final plan = await exchange.buildPlan(p, const {});
      expect(plan.canImport(acceptRejectedRows: true, includeDuplicates: false), isFalse);
    });

    test('uses supplier and purchase price for purchases, customer and sale price for sales', () async {
      const csv = 'Type,Product Name,Unit,Date,Purchase Price,Sale Price,Supplier,Customer,Currency,Quantity\n'
          'PURCHASE,لوح,قطعة,2026-10-01,100,150,المورد أ,العميل أ,USD,2\n'
          'SALE,لوح,قطعة,2026-10-02,100,150,المورد أ,العميل أ,USD,1\n';
      final p = await preview(csv);
      expect(p.fileErrors, isEmpty);
      final buy = p.rows.firstWhere((r) => r.type == 'PURCHASE');
      final sell = p.rows.firstWhere((r) => r.type == 'SALE');
      expect([buy.price, buy.party], [100, 'المورد أ']);
      expect([sell.price, sell.party], [150, 'العميل أ']);
    });

    test('lists unknown columns instead of silently dropping them', () async {
      final p = await preview('Product Name,Unit,Colour\nصنف,قطعة,أحمر\n');
      expect(p.parsed.ignoredColumns, ['Colour']);
    });
  });

  group('product matching (regression for P0-01)', () {
    test('never merges names whose numbers are in a different order', () async {
      final existing = await db.saveProduct(name: 'كابل 2 خط 4 ملم', unit: 'متر');
      final p = await preview('$header${purchase('كابل 4 خط 2 ملم', unit: 'متر')}');
      final g = p.groups.single;
      expect(g.status, ImportGroupStatus.needsDecision);
      expect(g.candidates.single.productId, existing);
      expect(g.candidates.single.reasons, contains(CandidateReason.reorderedName));
      final plan = await exchange.buildPlan(p, const {});
      expect(plan.undecidedGroups, hasLength(1));
      expect(plan.canImport(acceptRejectedRows: false, includeDuplicates: false), isFalse);
      await expectLater(importAll(p), throwsA(isA<SpreadsheetImportException>()));
      expect(await db.getPurchaseHistory(existing), isEmpty);

      await importAll(p, {g.id: const ImportDecision.createNew()});
      expect(await db.getPurchaseHistory(existing), isEmpty, reason: 'the existing cable must not receive the other cable prices');
      final created = await db.findExactProductName('كابل 4 خط 2 ملم');
      expect(created, isNotNull);
      expect(await db.getPurchaseHistory(created!['id']! as int), hasLength(1));
    });

    test('keeps similar names inside one file as separate products', () async {
      final p = await preview('$header${purchase('كابل 2 خط 4 ملم', unit: 'متر')}${purchase('كابل 4 خط 2 ملم', unit: 'متر')}');
      expect(p.groups, hasLength(2));
      expect(p.groups.every((g) => g.status == ImportGroupStatus.newProduct), isTrue);
      expect(p.groups.every((g) => g.notices.any((n) => n.ar.contains('متشابهة'))), isTrue);
      final result = await importAll(p);
      expect(result.productsAdded, 2);
    });

    test('reordered words require a decision; linking keeps existing details', () async {
      final id = await db.saveProduct(name: 'محول شمسي', unit: 'قطعة', code: 'OLD', category: 'قديم');
      final p = await preview('$header${purchase('شمسي محول', code: '')}');
      final g = p.groups.single;
      expect(g.status, ImportGroupStatus.needsDecision);
      final result = await importAll(p, {g.id: ImportDecision.link(id)});
      expect(result.productsAdded, 0);
      expect(result.transactionsAdded, 1);
      final product = await db.getProduct(id);
      expect(product!['code'], 'OLD');
      expect(product['category'], 'قديم');
      expect(await db.getPurchaseHistory(id), hasLength(1));
    });

    test('matches automatically on the same name in the same order and unit', () async {
      final id = await db.saveProduct(name: 'غطاس ٥٥ كيلوواط', unit: 'حبة', category: 'مضخات');
      final p = await preview('$header${purchase('غطاس 55 كيلوواط', unit: 'حبة')}');
      expect(p.groups.single.status, ImportGroupStatus.matched);
      expect(p.groups.single.matchedProductId, id);
      await importAll(p);
      expect(await db.getPurchaseHistory(id), hasLength(1));
      expect((await db.getProduct(id))!['category'], 'مضخات');
    });

    test('code identifies the product; a same-code different-name row needs a decision', () async {
      final id = await db.saveProduct(name: 'بطارية ليثيوم 100 أمبير', unit: 'قطعة', code: 'B-100');
      final same = await preview('$header${purchase('بطارية ليثيوم 100 أمبير', code: 'B-100')}');
      expect(same.groups.single.status, ImportGroupStatus.matched);
      final renamed = await preview('$header${purchase('بطارية 100', code: 'B-100')}');
      expect(renamed.groups.single.status, ImportGroupStatus.needsDecision);
      expect(renamed.groups.single.candidates.single.reasons, contains(CandidateReason.sameCode));
      expect(renamed.groups.single.candidates.single.productId, id);
    });

    test('same name with a different code needs a decision', () async {
      await db.saveProduct(name: 'قاطع 32 أمبير', unit: 'قطعة', code: 'C-32');
      final p = await preview('$header${purchase('قاطع 32 أمبير', code: 'C-99')}');
      expect(p.groups.single.status, ImportGroupStatus.needsDecision);
    });

    test('rows without a code join the coded rows of the same product', () async {
      final p = await preview('$header${purchase('منظم شحن', code: 'R-1')}${purchase('منظم شحن', date: '2026-10-05')}');
      expect(p.groups, hasLength(1));
      expect(p.groups.single.transactions, hasLength(2));
    });

    test('archived match needs a decision; linking un-archives and undo re-archives', () async {
      final id = await db.saveProduct(name: 'صنف مؤرشف', unit: 'قطعة');
      await db.archiveProduct(id);
      final p = await preview('$header${purchase('صنف مؤرشف')}');
      final g = p.groups.single;
      expect(g.status, ImportGroupStatus.needsDecision);
      expect(g.candidates.single.archived, isTrue);
      final result = await importAll(p, {g.id: ImportDecision.link(id)});
      expect(result.productsUnarchived, 1);
      expect((await db.getProduct(id))!['is_archived'], 0);
      await db.undoImportBatch(result.batchId);
      expect((await db.getProduct(id))!['is_archived'], 1);
      expect(await db.getPurchaseHistory(id), isEmpty);
    });
  });

  group('duplicates, rejected rows and atomicity', () {
    test('re-importing the same file adds nothing by default', () async {
      final csv = '$header${purchase('صنف جديد', price: '25')}';
      final first = await importAll(await preview(csv));
      expect([first.productsAdded, first.transactionsAdded], [1, 1]);
      final again = await preview(csv);
      expect(again.groups.single.status, ImportGroupStatus.matched);
      final plan = await exchange.buildPlan(again, const {});
      expect(plan.duplicateCount, 1);
      expect(plan.canImport(acceptRejectedRows: false, includeDuplicates: false), isFalse);
      final forced = await importAll(again, const {}, true);
      expect(forced.transactionsAdded, 1);
      expect(await countRows('purchase_entries'), 2);
    });

    test('flags a row repeated inside the file and skips it unless asked', () async {
      final row = purchase('صنف مكرر', price: '25');
      final p = await preview('$header$row$row');
      final plan = await exchange.buildPlan(p, const {});
      expect(plan.entries.where((e) => e.duplicateInFile), hasLength(1));
      final result = await importAll(p);
      expect([result.transactionsAdded, result.duplicatesSkipped], [1, 1]);
    });

    test('rejected rows block the import until the user accepts ignoring them', () async {
      final p = await preview('$header${purchase('صنف صالح')}PURCHASE,صنف خاطئ,قطعة,,,,,2026-10-01,-5,YER,1,,,,0,0,\n');
      expect(p.rejectedRows, hasLength(1));
      final plan = await exchange.buildPlan(p, const {});
      expect(plan.canImport(acceptRejectedRows: false, includeDuplicates: false), isFalse);
      expect(plan.canImport(acceptRejectedRows: true, includeDuplicates: false), isTrue);
      final result = await exchange.importPreview(p, p.automaticDecisions, includeDuplicates: false, acceptRejectedRows: true);
      expect(result.productsAdded, 1);
      expect(await db.findExactProductName('صنف خاطئ'), isNull);
    });

    test('a failure in the middle of the import writes nothing', () async {
      final raw = await db.database;
      await raw.execute("CREATE TRIGGER fail_import BEFORE INSERT ON purchase_entries WHEN NEW.supplier = 'FAIL' "
          "BEGIN SELECT RAISE(ABORT, 'simulated failure'); END");
      final p = await preview('$header${purchase('أول صنف')}${purchase('ثاني صنف', party: 'FAIL')}');
      await expectLater(importAll(p), throwsA(anything));
      expect(await countRows('products'), 0);
      expect(await countRows('purchase_entries'), 0);
      expect(await countRows('import_batches'), 0);
    });

    test('refuses to import when products changed after the preview', () async {
      final p = await preview('$header${purchase('صنف متغير')}');
      expect(p.groups.single.status, ImportGroupStatus.newProduct);
      await db.saveProduct(name: 'صنف متغير', unit: 'قطعة');
      await expectLater(importAll(p), throwsA(isA<SpreadsheetImportException>()));
      expect(await countRows('purchase_entries'), 0);
    });

    test('undo removes only what the batch added', () async {
      final p = await preview('$header${purchase('صنف أ')}${purchase('صنف ب')}');
      final result = await importAll(p);
      final a = (await db.findExactProductName('صنف أ'))!['id']! as int;
      await db.recordSale(productId: a, date: '2026-10-09', unitPrice: 130, quantity: 1);
      final undo = await db.undoImportBatch(result.batchId);
      expect(undo.entriesRemoved, 2);
      expect(undo.productsRemoved, 1);
      expect(undo.productsKept, 1);
      expect(await db.getSaleHistory(a), hasLength(1));
      expect(await db.findExactProductName('صنف ب'), isNull);
      await expectLater(db.undoImportBatch(result.batchId), throwsA(isA<StateError>()));
    });
  });

  group('row rules', () {
    test('ignores unsupported invoice number on sales rows without blocking import', () async {
      final id = await db.saveProduct(name: 'صنف بيع', unit: 'قطعة');
      final p = await preview('${header}SALE,صنف بيع,قطعة,,,,,2026-10-13,2100,YER,1,عميل,20,ملاحظة,0,0,\n');
      expect(p.rows.single.invoice, isNull);
      expect(p.rows.single.warnings.any((w) => w.ar.contains('سيُتجاهل')), isTrue);
      final result = await importAll(p);
      expect(result.transactionsAdded, 1);
      expect(await db.getSaleHistory(id), hasLength(1));
    });

    test('new sale-only and product-only rows create products with a notice', () async {
      final p = await preview('${header}SALE,بيع فقط,قطعة,C-2,,,,2026-10-03,30,YER,1,عميل,,,0,0,\n'
          ',صنف بلا سجل,كرتون,,,,,,,,,,,,0,1,\n');
      expect(p.groups.every((g) => g.status == ImportGroupStatus.newProduct), isTrue);
      expect(p.groups.every((g) => g.notices.isNotEmpty), isTrue);
      final result = await importAll(p);
      expect(result.productsAdded, 2);
      final noHistory = await db.findExactProductName('صنف بلا سجل');
      expect(noHistory, isNotNull);
    });
  });

  group('export and round trip', () {
    Future<void> seed(AppDatabase source) async {
      final a = await source.saveProduct(name: 'لوح 550 واط', unit: 'لوح', code: 'PV-550', category: 'ألواح', brand: 'Jinko', notes: '=1+1 ملاحظة', isFavorite: true);
      await source.recordPurchase(productId: a, date: '2026-10-01', unitPrice: 1500000, quantity: 3, currencyCode: 'YER', supplier: '+مورد', invoiceNumber: 'INV-9', notes: '-خصم');
      await source.recordSale(productId: a, date: '2026-10-02', unitPrice: 12.5, quantity: 1, currencyCode: 'USD', customer: '@عميل', notes: '\tنص');
      final b = await source.saveProduct(name: 'بطارية 200 أمبير', unit: 'قطعة');
      await source.recordSale(productId: b, date: '2026-10-03', unitPrice: 300, quantity: 2, currencyCode: 'SAR');
      final c = await source.saveProduct(name: 'صنف مؤرشف بسجل', unit: 'قطعة');
      await source.recordPurchase(productId: c, date: '2026-09-01', unitPrice: 5, quantity: 1);
      await source.archiveProduct(c);
      await source.saveProduct(name: 'صنف بلا سجل', unit: 'كرتون');
    }

    Future<List<String>> snapshot(AppDatabase target) async {
      final raw = await target.database;
      final products = await raw.rawQuery('SELECT name, unit, code, category, brand, notes, is_favorite, is_archived FROM products ORDER BY name');
      final purchases = await raw.rawQuery('SELECT p.name, e.purchase_date, e.unit_price, e.currency_code, e.quantity, e.supplier, e.invoice_number, e.notes, e.created_at FROM purchase_entries e JOIN products p ON p.id = e.product_id ORDER BY p.name, e.purchase_date');
      final sales = await raw.rawQuery('SELECT p.name, e.sale_date, e.unit_price, e.currency_code, e.quantity, e.customer, e.notes, e.created_at FROM sale_entries e JOIN products p ON p.id = e.product_id ORDER BY p.name, e.sale_date');
      return [...products, ...purchases, ...sales].map((r) => jsonEncode(r)).toList();
    }

    for (final format in ['csv', 'xlsx']) {
      test('$format export imports into an empty database unchanged', () async {
        await seed(db);
        final file = format == 'csv' ? await exchange.exportCsv() : await exchange.exportXlsx();
        // A separate file: every ':memory:' open shares one sqflite instance.
        final dir = await Directory.systemTemp.createTemp('gimi_roundtrip_');
        final target = AppDatabase(factory: databaseFactoryFfi, databasePathProvider: () async => dir.path);
        addTearDown(() async {
          await target.close();
          await dir.delete(recursive: true);
        });
        final targetExchange = SpreadsheetExchange.forDatabase(target);
        final p = await targetExchange.previewBytes(file, 'export.$format');
        expect(p.rejectedRows, isEmpty, reason: p.rejectedRows.map((r) => r.errors).join());
        expect(p.decisionsNeeded, 0);
        await targetExchange.importPreview(p, p.automaticDecisions, includeDuplicates: false, acceptRejectedRows: false);
        expect(await snapshot(target), await snapshot(db));
      });
    }

    test('CSV export guards every formula trigger and import removes the guard', () async {
      await seed(db);
      final raw = await exchange.exportCsv();
      expect(raw.take(3).toList(), [0xEF, 0xBB, 0xBF], reason: 'UTF-8 BOM so Excel shows Arabic correctly');
      final csv = utf8.decode(raw);
      for (final guarded in ["'=1+1", "'+مورد", "'-خصم", "'@عميل"]) {
        expect(csv, contains(guarded));
      }
      // Stored text is trimmed, but the guard also covers characters that
      // only appear when values come from other sources.
      for (final trigger in ['\t1', '\r1', '\n1', '\uFF1DSUM(A1)', '\uFF0B1', '\uFF0D1', '\uFF20A']) {
        expect(SpreadsheetExchange.needsFormulaGuard(trigger), isTrue, reason: trigger);
      }
      expect(SpreadsheetExchange.needsFormulaGuard('عادي'), isFalse);
    });

    test('XLSX export stores text as text cells, never formulas', () async {
      await seed(db);
      final workbook = Excel.decodeBytes(await exchange.exportXlsx());
      final cells = workbook.tables['Data']!.rows.expand((r) => r).whereType<Data>();
      expect(cells.any((c) => c.value is FormulaCellValue), isFalse);
    });
  });
}

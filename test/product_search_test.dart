import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:buy_price_assistant_gimi/data/app_database.dart';
import 'package:buy_price_assistant_gimi/data/spreadsheet_exchange.dart';

/// Every field the search covers, one test per field, plus the index being
/// kept current by every write path (schema v5 search index).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late AppDatabase db;
  late int pump;

  setUp(() async {
    db = AppDatabase(factory: databaseFactoryFfi, databasePathProvider: () async => ':memory:');
    pump = await db.saveProduct(
      name: 'غطاس فانسان ٥٥ كيلوواط', code: 'VS-55', category: 'مضخات', brand: 'Vansan',
      notes: 'يحتاج كابل خاص', unit: 'حبة',
    );
    await db.recordPurchase(
      productId: pump, date: '2026-03-14', unitPrice: 1250.5, quantity: 2,
      supplier: 'مؤسسة النور', invoiceNumber: 'F-77', notes: 'دفعة مقدمة', currencyCode: 'USD',
    );
    await db.recordSale(
      productId: pump, date: '2026-04-02', unitPrice: 1490, quantity: 1,
      customer: 'مزرعة الوادي', notes: 'تركيب مجاني', currencyCode: 'USD',
    );
    await db.saveProduct(name: 'لوح شمسي 550 واط', code: 'PV-550', category: 'ألواح', brand: 'Jinko');
  });

  tearDown(() async => db.close());

  Future<List<String>> names(String query, {bool archived = false}) async =>
      (await db.searchProducts(query, archived: archived)).map((row) => row['name']! as String).toList();

  group('finds a product through each field', () {
    final cases = <String, String>{
      'name': 'فانسان',
      'name with diacritics and hamza variants': 'غَطّاس',
      'code': 'vs-55',
      'category': 'مضخات',
      'brand (any case)': 'VANSAN',
      'product notes': 'كابل',
      'supplier': 'النور',
      'supplier with a different hamza': 'موسسة',
      'purchase notes': 'مقدمة',
      'customer': 'الوادي',
      'sale notes': 'مجاني',
      'purchase date': '2026-03',
      'sale date': '2026-04-02',
      'purchase price': '1250.5',
      'sale price': '1490',
      'Arabic-Indic digits in the query': '١٢٥٠',
      'Latin digits for Arabic-Indic digits stored': 'غطاس 55',
      'several words from different fields': 'غطاس النور 2026-04',
    };
    for (final entry in cases.entries) {
      test(entry.key, () async {
        expect(await names(entry.value), ['غطاس فانسان ٥٥ كيلوواط']);
      });
    }
  });

  test('every word must match; a word never spans two fields', () async {
    expect(await names('غطاس Jinko'), isEmpty);
    // Name ends with "كيلوواط" and the code starts with "VS": no cross-field match.
    expect(await names('كيلوواطvs'), isEmpty);
    expect(await names('مجهول'), isEmpty);
  });

  test('wildcards are literal characters', () async {
    await db.saveProduct(name: 'سلك 50% نحاس');
    await db.saveProduct(name: 'سلك_مرن');
    expect(await names('%'), ['سلك 50% نحاس']);
    expect(await names('_'), ['سلك_مرن']);
  });

  test('marks results that matched through a note', () async {
    final byNote = await db.searchProducts('مقدمة');
    expect(byNote.single['search_match_notes'], 1);
    final byName = await db.searchProducts('فانسان');
    expect(byName.single['search_match_notes'], 0);
    final empty = await db.searchProducts('');
    expect(empty.every((row) => row['search_match_notes'] == 0), isTrue);
  });

  test('returns the latest purchase and sale with party, quantity and currency', () async {
    final row = (await db.searchProducts('فانسان')).single;
    expect(row['latest_purchase_price'], 1250.5);
    expect(row['latest_purchase_supplier'], 'مؤسسة النور');
    expect(row['latest_purchase_quantity'], 2.0);
    expect(row['latest_purchase_currency'], 'USD');
    expect(row['latest_sale_price'], 1490.0);
    expect(row['latest_sale_customer'], 'مزرعة الوادي');
    expect(row['latest_sale_quantity'], 1.0);
    expect(row['purchase_count'], 1);
    expect(row['sale_count'], 1);
    expect(row.containsKey('search_text'), isFalse, reason: 'the index stays internal');

    final empty = (await db.searchProducts('لوح')).single;
    expect(empty['latest_purchase_price'], isNull, reason: 'no invented price when there is no record');
    expect(empty['purchase_count'], 0);
  });

  test('filters by category, brand (any case) and supplier', () async {
    expect((await db.searchProducts('', category: 'مضخات')).single['id'], pump);
    expect((await db.searchProducts('', brand: 'jinko')).single['name'], 'لوح شمسي 550 واط');
    expect((await db.searchProducts('', supplier: 'مؤسسة النور')).single['id'], pump);
    expect(await db.searchProducts('', supplier: 'مورد آخر'), isEmpty);
  });

  test('archived products are listed separately and can be restored', () async {
    await db.archiveProduct(pump);
    expect(await names('فانسان'), isEmpty);
    expect(await names('فانسان', archived: true), ['غطاس فانسان ٥٥ كيلوواط']);
    expect(await db.countProducts('', archived: true), 1);

    await db.unarchiveProduct(pump);
    expect(await names('فانسان'), ['غطاس فانسان ٥٥ كيلوواط']);
    expect((await db.getPurchaseHistory(pump)), hasLength(1), reason: 'history is kept');
    await expectLater(db.unarchiveProduct(pump), throwsA(isA<StateError>()));
  });

  test('pages through every result with a matching total count', () async {
    for (var i = 0; i < 23; i++) {
      await db.saveProduct(name: 'بطارية رقم $i');
    }
    expect(await db.countProducts('بطارية'), 23);
    final seen = <Object?>{};
    for (var offset = 0; offset < 23; offset += 10) {
      final page = await db.searchProducts('بطارية', limit: 10, offset: offset);
      expect(page.length, offset == 20 ? 3 : 10);
      seen.addAll(page.map((row) => row['id']));
    }
    expect(seen, hasLength(23), reason: 'no product is skipped or repeated between pages');
    expect(await db.countProducts(''), 25);
  });

  test('a favorite comes first without changing when it was last edited', () async {
    final before = (await db.getProduct(pump))!['updated_at'];
    await db.setFavorite(pump, true);
    expect((await db.getProduct(pump))!['updated_at'], before);
    expect((await db.searchProducts('')).first['id'], pump);
  });

  group('the index follows every change', () {
    test('editing a product', () async {
      await db.saveProduct(id: pump, name: 'غطاس بيدروللو', brand: 'Pedrollo');
      expect(await names('فانسان'), isEmpty);
      expect(await names('pedrollo'), ['غطاس بيدروللو']);
    });

    test('editing and deleting entries', () async {
      final entry = (await db.getPurchaseHistory(pump)).single['id']! as int;
      await db.updatePurchaseEntry(
        id: entry, productId: pump, date: '2026-03-14', unitPrice: 1250.5, quantity: 2, supplier: 'مورد جديد',
      );
      expect(await names('النور'), isEmpty);
      expect(await names('جديد'), hasLength(1));

      await db.deletePurchaseEntry(id: entry, productId: pump);
      expect(await names('جديد'), isEmpty);
      final sale = (await db.getSaleHistory(pump)).single['id']! as int;
      await db.deleteSaleEntry(id: sale, productId: pump);
      expect(await names('الوادي'), isEmpty);
      expect(await names('فانسان'), hasLength(1), reason: 'product fields stay searchable');
    });

    test('import, undo and restore', () async {
      const csv = 'Type,Product Name,Unit,Date,Unit Price,Currency,Quantity,Supplier\n'
          'PURCHASE,مضخة جديدة,حبة,2026-05-01,1300,USD,1,شركة الأفق\n';
      final exchange = SpreadsheetExchange.forDatabase(db);
      final preview = await exchange.previewBytes(Uint8List.fromList(utf8.encode(csv)), 'p.csv');
      final result = await exchange.importPreview(
        preview, preview.automaticDecisions, includeDuplicates: false, acceptRejectedRows: false,
      );
      expect(await names('الافق'), ['مضخة جديدة']);

      final backup = await db.exportBackupJson();
      await db.undoImportBatch(result.batchId);
      expect(await names('الافق'), isEmpty);

      await db.restoreBackupJson(backup);
      expect(await names('الافق'), ['مضخة جديدة']);
    });
  });

  test('history pages are newest first and cover every record once', () async {
    for (var day = 10; day < 20; day++) {
      await db.recordPurchase(productId: pump, date: '2026-05-$day', unitPrice: day.toDouble(), quantity: 1);
    }
    final all = await db.getPurchaseHistory(pump);
    expect(all, hasLength(11));
    final first = await db.getPurchaseHistory(pump, limit: 4);
    final rest = await db.getPurchaseHistory(pump, limit: 20, offset: 4);
    expect([...first, ...rest].map((row) => row['id']), all.map((row) => row['id']));
    expect(first.first['entry_date'], '2026-05-19');
  });

  test('name suggestions and exact-name checks work with and without an excluded id', () async {
    expect(await db.suggestProductNames('فانسان'), hasLength(1));
    expect(await db.suggestProductNames('فانسان', excludeId: pump), isEmpty);
    expect(await db.findExactProductName('غطاس فانسان 55 كيلوواط'), isNotNull);
    expect(await db.findExactProductName('غطاس فانسان 55 كيلوواط', excludeId: pump), isNull);
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:buy_price_assistant_gimi/data/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(
      factory: databaseFactoryFfi,
      databasePathProvider: () async => ':memory:',
    );
  });

  tearDown(() async => db.close());

  test('keeps every purchase and sale while returning the latest prices', () async {
    final productId = await db.saveProduct(
      name: 'محول شمسية',
      code: 'INV-01',
      unit: 'قطعة',
    );

    await db.recordPurchase(productId: productId, date: '2026-10-01', unitPrice: 100, quantity: 2, supplier: 'مورد أ');
    await db.recordPurchase(productId: productId, date: '2026-10-10', unitPrice: 125.5, quantity: 3, supplier: 'مورد ب');
    await db.recordSale(productId: productId, date: '2026-10-11', unitPrice: 160, quantity: 1, customer: 'عميل أ');

    final results = await db.searchProducts('مُحَوِّل');
    expect(results, hasLength(1));
    expect(results.single['latest_purchase_price'], 125.5);
    expect(results.single['latest_sale_price'], 160.0);
    expect(results.single['purchase_count'], 2);
    expect(results.single['sale_count'], 1);

    final purchases = await db.getPurchaseHistory(productId);
    expect(purchases, hasLength(2));
    expect(purchases.first['unit_price'], 125.5);
    expect(purchases.last['unit_price'], 100.0);
  });

  test('escapes wildcard query characters rather than matching every product', () async {
    await db.saveProduct(name: 'سلك 50% نحاس', unit: 'متر');
    await db.saveProduct(name: 'سلك 500 نحاس', unit: 'متر');

    final results = await db.searchProducts('%');
    expect(results, hasLength(1));
    expect(results.single['name'], 'سلك 50% نحاس');
  });

  test('archives a product without deleting historical records', () async {
    final id = await db.saveProduct(name: 'مضخة اختبار');
    await db.recordPurchase(productId: id, date: '2026-10-01', unitPrice: 50, quantity: 1);
    await db.archiveProduct(id);

    expect(await db.searchProducts('مضخة'), isEmpty);
    expect(await db.getPurchaseHistory(id), hasLength(1));
  });

  test('rejects invalid quantity and negative price at the data layer', () async {
    final id = await db.saveProduct(name: 'صنف فحص');
    await expectLater(
      db.recordPurchase(productId: id, date: '2026-10-01', unitPrice: 10, quantity: 0),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      db.recordSale(productId: id, date: '2026-10-01', unitPrice: -1, quantity: 1),
      throwsA(isA<ArgumentError>()),
    );
  });
  test('backup round-trip preserves products and all price history', () async {
    final id = await db.saveProduct(
      name: 'لوح شمسي', code: 'PV-01', category: 'طاقة', unit: 'لوح',
      brand: 'GIMI', notes: 'اختبار', isFavorite: true,
    );
    await db.recordPurchase(
      productId: id, date: '2026-10-01', unitPrice: 100, quantity: 3,
      supplier: 'المورد', invoiceNumber: 'INV-1', notes: 'شراء',
    );
    await db.recordSale(
      productId: id, date: '2026-10-02', unitPrice: 150, quantity: 1,
      customer: 'العميل', notes: 'بيع',
    );
    await db.archiveProduct(id);
    final backup = await db.exportBackupJson();
    await db.restoreBackupJson(backup);
    expect(await db.getProduct(id), isNotNull);
    expect(await db.getPurchaseHistory(id), hasLength(1));
    expect(await db.getSaleHistory(id), hasLength(1));
    expect((await db.getProduct(id))!['is_archived'], 1);
  });

  test('invalid backup does not delete existing data', () async {
    final id = await db.saveProduct(name: 'بيانات محفوظة');
    await expectLater(
      db.restoreBackupJson('{"format":"wrong","schemaVersion":1,"tables":{}}'),
      throwsA(isA<FormatException>()),
    );
    expect(await db.getProduct(id), isNotNull);
  });

  test('finds historical item-name suggestions by substring', () async {
    final first = await db.saveProduct(name: 'محول 110 كيلوواط بيدفورد الوكالة');
    final second = await db.saveProduct(name: 'محول 75 كيلوواط بيدفورد الوكالة');
    await db.archiveProduct(second);
    final rows = await db.suggestProductNames('بيدفورد');
    expect(rows.map((row) => row['id']), containsAll(<int>[first, second]));
    expect(await db.findExactProductName('محول 110 كيلوواط بيدفورد الوكالة'), isNotNull);
  });

  test('stores a transaction currency and maps old backup records to YER', () async {
    final id = await db.saveProduct(name: 'بطارية اختبار');
    await db.recordPurchase(
      productId: id,
      date: '2026-10-01',
      unitPrice: 100,
      quantity: 1,
      currencyCode: 'USD',
    );
    expect((await db.getPurchaseHistory(id)).single['currency_code'], 'USD');

    final decoded = jsonDecode(await db.exportBackupJson()) as Map<String, dynamic>;
    decoded['schemaVersion'] = 1;
    final tables = Map<String, dynamic>.from(decoded['tables'] as Map);
    final entries = (tables['purchase_entries'] as List).map((raw) {
      final item = Map<String, dynamic>.from(raw as Map);
      item.remove('currency_code');
      return item;
    }).toList();
    tables['purchase_entries'] = entries;
    decoded['tables'] = tables;
    await db.restoreBackupJson(jsonEncode(decoded));
    expect((await db.getPurchaseHistory(id)).single['currency_code'], 'YER');
  });

}

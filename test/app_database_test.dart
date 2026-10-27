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

    // A schema v1 backup as version 1.0 wrote it: no currency, no checksum.
    final legacy = <String, Object?>{
      'format': 'buy_price_assistant_gimi_backup',
      'schemaVersion': 1,
      'createdAt': '2026-01-05T10:00:00.000Z',
      'tables': {
        'products': [
          {
            'id': 7, 'name': 'صنف قديم', 'search_name': 'صنف قديم', 'code': null, 'search_code': '',
            'category': null, 'search_category': '', 'unit': 'قطعة', 'brand': null, 'notes': null,
            'is_favorite': 0, 'is_archived': 0, 'created_at': '2026-01-01T00:00:00', 'updated_at': '2026-01-01T00:00:00',
          },
        ],
        'purchase_entries': [
          {
            'id': 1, 'product_id': 7, 'purchase_date': '2026-01-02', 'unit_price': 275.0, 'quantity': 2.0,
            'supplier': 'مورد سابق', 'invoice_number': null, 'notes': null, 'created_at': '2026-01-02T00:00:00',
          },
        ],
        'sale_entries': <Object?>[],
      },
      'counts': {'products': 1, 'purchase_entries': 1, 'sale_entries': 0},
    };
    await db.restoreBackupJson(jsonEncode(legacy));
    expect(await db.getProduct(id), isNull, reason: 'restore replaces all current data');
    expect((await db.getPurchaseHistory(7)).single['currency_code'], 'YER');
  });


  test('edits purchase and sale history entries without replacing their IDs', () async {
    final productId = await db.saveProduct(name: 'صنف اختبار تعديل السجل');
    final purchaseId = await db.recordPurchase(
      productId: productId, date: '2026-10-01', unitPrice: 100,
      quantity: 2, supplier: 'مورد قديم', invoiceNumber: 'INV-1',
      notes: 'قديم', currencyCode: 'YER',
    );
    final oldPurchaseCreatedAt = (await db.getPurchaseHistory(productId)).single['created_at'];

    await db.updatePurchaseEntry(
      id: purchaseId, productId: productId, date: '2026-10-03',
      unitPrice: 125.5, quantity: 4, supplier: 'مورد جديد',
      invoiceNumber: 'INV-2', notes: 'معدل', currencyCode: 'USD',
    );
    final purchase = (await db.getPurchaseHistory(productId)).single;
    expect(purchase['id'], purchaseId);
    expect(purchase['entry_date'], '2026-10-03');
    expect(purchase['unit_price'], 125.5);
    expect(purchase['quantity'], 4.0);
    expect(purchase['party_name'], 'مورد جديد');
    expect(purchase['invoice_number'], 'INV-2');
    expect(purchase['notes'], 'معدل');
    expect(purchase['currency_code'], 'USD');
    expect(purchase['created_at'], oldPurchaseCreatedAt);

    final saleId = await db.recordSale(
      productId: productId, date: '2026-10-02', unitPrice: 160,
      quantity: 1, customer: 'عميل قديم', notes: 'قديم',
      currencyCode: 'YER',
    );
    final oldSaleCreatedAt = (await db.getSaleHistory(productId)).single['created_at'];
    await db.updateSaleEntry(
      id: saleId, productId: productId, date: '2026-10-04',
      unitPrice: 175, quantity: 3, customer: 'عميل جديد',
      notes: 'معدل', currencyCode: 'SAR',
    );
    final sale = (await db.getSaleHistory(productId)).single;
    expect(sale['id'], saleId);
    expect(sale['entry_date'], '2026-10-04');
    expect(sale['unit_price'], 175.0);
    expect(sale['quantity'], 3.0);
    expect(sale['party_name'], 'عميل جديد');
    expect(sale['notes'], 'معدل');
    expect(sale['currency_code'], 'SAR');
    expect(sale['created_at'], oldSaleCreatedAt);
  });

  test('deletes only the selected purchase or sale history entry', () async {
    final productId = await db.saveProduct(name: 'صنف اختبار حذف السجل');
    final otherProductId = await db.saveProduct(name: 'صنف مختلف');
    final oldPurchaseId = await db.recordPurchase(
      productId: productId, date: '2026-10-01', unitPrice: 50, quantity: 1,
    );
    final latestPurchaseId = await db.recordPurchase(
      productId: productId, date: '2026-10-02', unitPrice: 60, quantity: 2,
    );
    final oldSaleId = await db.recordSale(
      productId: productId, date: '2026-10-01', unitPrice: 70, quantity: 1,
    );
    final latestSaleId = await db.recordSale(
      productId: productId, date: '2026-10-02', unitPrice: 80, quantity: 2,
    );

    await expectLater(
      db.deletePurchaseEntry(id: latestPurchaseId, productId: otherProductId),
      throwsA(isA<StateError>()),
    );
    expect(await db.getPurchaseHistory(productId), hasLength(2));

    await db.deletePurchaseEntry(id: latestPurchaseId, productId: productId);
    await db.deleteSaleEntry(id: latestSaleId, productId: productId);
    expect((await db.getPurchaseHistory(productId)).map((e) => e['id']).toList(), [oldPurchaseId]);
    expect((await db.getSaleHistory(productId)).map((e) => e['id']).toList(), [oldSaleId]);

    await db.deletePurchaseEntry(id: oldPurchaseId, productId: productId);
    await db.deleteSaleEntry(id: oldSaleId, productId: productId);
    expect(await db.getPurchaseHistory(productId), isEmpty);
    expect(await db.getSaleHistory(productId), isEmpty);
  });

  test('search treats Arabic-Indic and English digits as equivalent', () async {
    await db.saveProduct(name: 'غطاس ٥٥ كيلوواط فانسان', unit: 'حبة');
    expect(await db.searchProducts('غطاس 55 كيلوواط فانسان'), hasLength(1));
    expect(await db.searchProducts('غطاس ٥٥ كيلوواط فانسان'), hasLength(1));
  });

  test('search finds purchase notes and supplier names', () async {
    final id = await db.saveProduct(name: 'غطاس اختبار', unit: 'حبة');
    await db.recordPurchase(
      productId: id, date: '2026-10-01', unitPrice: 100, quantity: 1,
      supplier: 'المورد المكيس', notes: 'قطر ٧ هنش',
    );
    expect(await db.searchProducts('المكيس'), hasLength(1));
    expect(await db.searchProducts('قطر'), hasLength(1));
  });

}

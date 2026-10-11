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
}

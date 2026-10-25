import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:buy_price_assistant_gimi/data/app_database.dart';
import 'package:buy_price_assistant_gimi/data/spreadsheet_exchange.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase db;
  late SpreadsheetExchange exchange;

  setUp(() {
    db = AppDatabase(factory: databaseFactoryFfi, databasePathProvider: () async => ':memory:');
    exchange = SpreadsheetExchange.forDatabase(db);
  });
  tearDown(() async => db.close());

  Uint8List bytes(String csv) => Uint8List.fromList(utf8.encode(csv));
  const header = 'Type,Product Name,Unit,Code,Category,Brand,Product Notes,Date,Unit Price,Currency,Quantity,Supplier/Customer,Invoice Number,Entry Notes,Product Archived,Product Favorite,Record Created At\n';

  test('normalizes header names and dates', () {
    expect(SpreadsheetExchange.normalizeColumnHeader('Product Name'), 'productname');
    expect(SpreadsheetExchange.normalizeColumnHeader('اسم الصنف'), 'اسمالصنف');
    expect(SpreadsheetExchange.normalizeDateValue('21/10/2026'), '2026-10-21');
    expect(SpreadsheetExchange.normalizeDateValue('٢١/١٠/٢٠٢٦'), '2026-10-21');
    expect(SpreadsheetExchange.normalizeDateValue('2026-02-31'), isNull);
  });

  test('matches existing product by normalized name and unit without overwriting metadata', () async {
    final id = await db.saveProduct(name: 'محول شمسي', unit: 'قطعة', code: 'OLD', category: 'قديم');
    final source = '${header}PURCHASE,مُحَوِّل شمسي,قطعة,NEW,جديد,,ملاحظة,2026-10-01,100,USD,2,مورد,INV-1,ملاحظة عملية,0,0,\n';
    final preview = await exchange.previewBytes(bytes(source), 'history.csv');
    expect(preview.canImport, isTrue, reason: 'valid=${preview.validTransactionCount}; errors=${preview.errorCount}; issues=${preview.issues.map((i) => i.message).join(' | ')}');
    expect(preview.matchedProducts, 1);
    final result = await exchange.importPreview(preview, confirmDuplicates: false);
    expect(result.productsAdded, 0);
    expect(result.transactionsAdded, 1);
    final product = await db.getProduct(id);
    expect(product!['code'], 'OLD');
    expect(product['category'], 'قديم');
    expect(await db.getPurchaseHistory(id), hasLength(1));
  });

  test('requires explicit confirmation for duplicate entries', () async {
    final row = 'PURCHASE,صنف جديد,قطعة,C-1,معدات,, ,2026-10-02,25,YER,3,مورد,INV-2,اختبار,0,0,\n';
    final preview = await exchange.previewBytes(bytes(header + row + row), 'duplicates.csv');
    expect(preview.canImport, isTrue);
    expect(preview.duplicateCount, 1);
    await expectLater(exchange.importPreview(preview, confirmDuplicates: false), throwsA(isA<SpreadsheetImportException>()));
    expect(await db.searchProducts('صنف جديد'), isEmpty);
    final again = await exchange.previewBytes(bytes(header + row + row), 'duplicates.csv');
    final result = await exchange.importPreview(again, confirmDuplicates: true);
    expect(result.productsAdded, 1);
    expect(result.transactionsAdded, 2);
    final item = await db.suggestProductNames('صنف جديد');
    expect(item, hasLength(1));
    final details = await db.getProduct((item.single['id']! as num).toInt());
    expect(details!['purchase_count'], 2);
  });

  test('rejects new sale-only products and refuses archived matches', () async {
    final saleOnly = await exchange.previewBytes(bytes('${header}SALE,بيع فقط,قطعة,C-2,,,,2026-10-03,30,YER,1,عميل,,ملاحظة,0,0,\n'), 'sale.csv');
    expect(saleOnly.canImport, isFalse);
    final archivedId = await db.saveProduct(name: 'صنف مؤرشف', unit: 'قطعة');
    await db.archiveProduct(archivedId);
    final archived = await exchange.previewBytes(bytes('${header}PURCHASE,صنف مؤرشف,قطعة,C-3,,,,2026-10-03,30,YER,1,مورد,INV,شراء,0,0,\n'), 'archived.csv');
    expect(archived.canImport, isFalse);
    expect(archived.issues.any((x) => x.isError && x.message.contains('مؤرشف')), isTrue, reason: 'canImport=${archived.canImport}; valid=${archived.validTransactionCount}; errors=${archived.errorCount}; issues=${archived.issues.map((i) => i.message).join(' | ')}');
    expect(await db.getPurchaseHistory(archivedId), isEmpty);
  });

  test('exports every history record and products without history', () async {
    final id = await db.saveProduct(name: 'صنف له تاريخ', unit: 'قطعة');
    await db.recordPurchase(productId: id, date: '2026-10-01', unitPrice: 12.5, quantity: 2, currencyCode: 'USD');
    await db.recordSale(productId: id, date: '2026-10-02', unitPrice: 20, quantity: 1, currencyCode: 'SAR');
    await db.saveProduct(name: 'صنف بلا تاريخ', unit: 'كرتون');
    final csv = utf8.decode(await exchange.exportCsv()).replaceFirst('\uFEFF', '');
    expect(csv, contains('صنف له تاريخ'));
    expect(csv, contains('صنف بلا تاريخ'));
    expect(csv, contains('PURCHASE'));
    expect(csv, contains('SALE'));
    expect(csv, contains('USD'));
    expect(csv, contains('SAR'));
    final xlsx = await exchange.exportXlsx();
    final xlsxPreview = await exchange.previewBytes(xlsx, 'data.xlsx');
    expect(xlsxPreview.canImport, isTrue);
    expect(xlsxPreview.validTransactionCount, 2);
  });
}

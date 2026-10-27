import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:buy_price_assistant_gimi/data/app_database.dart';
import 'package:buy_price_assistant_gimi/data/backup_service.dart';
import 'package:buy_price_assistant_gimi/data/backup_validator.dart';
import 'package:buy_price_assistant_gimi/state/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory dir;
  late AppDatabase db;
  late BackupService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppSettings.instance.load();
    dir = await Directory.systemTemp.createTemp('gimi_backup_');
    db = AppDatabase(factory: databaseFactoryFfi, databasePathProvider: () async => dir.path);
    service = BackupService(database: db, directoryProvider: () async => dir.path);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<int> seed() async {
    final id = await db.saveProduct(name: 'لوح شمسي ٥٥٠', code: 'PV-550', unit: 'لوح', brand: 'Jinko', isFavorite: true);
    await db.recordPurchase(productId: id, date: '2026-10-01', unitPrice: 100, quantity: 3, supplier: 'المورد', invoiceNumber: 'INV-1');
    await db.recordSale(productId: id, date: '2026-10-02', unitPrice: 150, quantity: 1, customer: 'العميل', currencyCode: 'USD');
    return id;
  }

  Map<String, dynamic> decode(String json) => jsonDecode(json) as Map<String, dynamic>;

  /// Re-computes the checksum after a test edits the tables on purpose.
  String reseal(Map<String, dynamic> backup) {
    (backup['checksum'] as Map)['value'] = BackupValidator.checksumOf(backup['tables']);
    return jsonEncode(backup);
  }

  group('validation (nothing changes when a file is rejected)', () {
    Future<void> expectRejected(String content, String messagePart) async {
      final id = await db.saveProduct(name: 'بيانات حالية');
      await expectLater(db.restoreBackupJson(content),
          throwsA(isA<FormatException>().having((e) => e.message, 'message', contains(messagePart))));
      expect(await db.getProduct(id), isNotNull);
    }

    test('detects a damaged or edited file through the checksum', () async {
      await seed();
      final backup = decode(await db.exportBackupJson());
      ((backup['tables'] as Map)['purchase_entries'] as List).first['unit_price'] = 1;
      await expectRejected(jsonEncode(backup), 'بصمة التحقق');
    });

    test('rejects truncated JSON', () async {
      await seed();
      final json = await db.exportBackupJson();
      await expectRejected(json.substring(0, json.length ~/ 2), 'JSON');
    });

    test('rejects an invalid date, price, currency and unknown column', () async {
      await seed();
      final cases = <String, void Function(Map tables)>{
        'التاريخ': (t) => (t['purchase_entries'] as List).first['purchase_date'] = '2026-02-31',
        'السعر': (t) => (t['purchase_entries'] as List).first['unit_price'] = -1,
        'العملة': (t) => (t['sale_entries'] as List).first['currency_code'] = 'EUR',
        'غير معروف': (t) => (t['products'] as List).first['colour'] = 'red',
      };
      for (final entry in cases.entries) {
        final backup = decode(await db.exportBackupJson());
        entry.value(backup['tables'] as Map);
        await expectRejected(reseal(backup), entry.key);
      }
    });

    test('rejects counts that do not match and entries without a product', () async {
      await seed();
      final counts = decode(await db.exportBackupJson());
      (counts['counts'] as Map)['products'] = 5;
      await expectRejected(jsonEncode(counts), 'لا يطابق');
      final orphan = decode(await db.exportBackupJson());
      ((orphan['tables'] as Map)['sale_entries'] as List).first['product_id'] = 999;
      await expectRejected(reseal(orphan), 'غير موجود');
    });

    test('rejects a backup from a newer version', () async {
      await seed();
      final backup = decode(await db.exportBackupJson());
      backup['schemaVersion'] = 4;
      await expectRejected(jsonEncode(backup), 'غير مدعوم');
    });
  });

  test('round trip keeps every product, entry and import batch', () async {
    await seed();
    final before = await db.exportBackupJson();
    await db.restoreBackupJson(before);
    final after = decode(await db.exportBackupJson());
    expect(after['tables'], decode(before)['tables']);
  });

  test('restoring a pre-v3 backup recomputes search columns (Arabic digits)', () async {
    // Version 1.3 stored search_name without converting Arabic-Indic digits.
    final legacy = {
      'format': 'buy_price_assistant_gimi_backup',
      'schemaVersion': 2,
      'createdAt': '2026-09-01T10:00:00.000Z',
      'tables': {
        'products': [
          {
            'id': 3, 'name': 'غطاس ٥٥ كيلوواط', 'search_name': 'غطاس ٥٥ كيلوواط', 'code': 'غ-٥٥',
            'search_code': 'غ-٥٥', 'category': null, 'search_category': '', 'unit': 'حبة', 'brand': null,
            'notes': null, 'is_favorite': 0, 'is_archived': 0,
            'created_at': '2026-09-01T00:00:00', 'updated_at': '2026-09-01T00:00:00',
          },
        ],
        'purchase_entries': [],
        'sale_entries': [],
      },
      'counts': {'products': 1, 'purchase_entries': 0, 'sale_entries': 0},
    };
    await db.restoreBackupJson(jsonEncode(legacy));
    expect(await db.searchProducts('غطاس 55'), hasLength(1));
    expect(await db.searchProducts('غ-55'), hasLength(1));
  });

  group('BackupService', () {
    test('saves a safety snapshot before restoring and it brings the old data back', () async {
      final id = await seed();
      final backup = await service.buildFullBackup();
      await db.recordPurchase(productId: id, date: '2026-10-05', unitPrice: 120, quantity: 1);
      expect(await db.getPurchaseHistory(id), hasLength(2));

      final outcome = await service.restoreFullBackup(backup);
      expect(await db.getPurchaseHistory(id), hasLength(1));
      expect(outcome.summary.products, 1);
      expect(outcome.safetySnapshot.reason, 'before_restore');

      await service.restoreFullBackup(await service.readSnapshot(outcome.safetySnapshot));
      expect(await db.getPurchaseHistory(id), hasLength(2), reason: 'the safety copy holds the replaced data');
    });

    test('an invalid file creates no snapshot and changes nothing', () async {
      final id = await seed();
      await expectLater(service.restoreFullBackup('{"format":"other"}'), throwsA(isA<FormatException>()));
      expect(await service.listSnapshots(), isEmpty);
      expect(await db.getProduct(id), isNotNull);
    });

    test('restores settings with the data and rolls them back if the database step fails', () async {
      await seed();
      await AppSettings.instance.setCurrency('SAR');
      final backup = decode(await service.buildFullBackup());
      (backup['settings'] as Map)['currency'] = 'YER';
      await service.restoreFullBackup(jsonEncode(backup));
      expect(AppSettings.instance.currency, 'YER');

      await AppSettings.instance.setCurrency('USD');
      final raw = await db.database;
      await raw.execute("CREATE TRIGGER fail_restore BEFORE INSERT ON sale_entries BEGIN SELECT RAISE(ABORT, 'disk full'); END");
      await expectLater(service.restoreFullBackup(jsonEncode(backup)), throwsA(anything));
      expect(AppSettings.instance.currency, 'USD', reason: 'settings are rolled back');
      expect((await db.searchProducts('')).length, 1, reason: 'the database transaction is rolled back');
    });

    test('keeps only the newest snapshots', () async {
      await seed();
      for (var i = 0; i < BackupService.keepSnapshots + 2; i++) {
        await service.createSafetySnapshot('manual');
        await Future<void>.delayed(const Duration(milliseconds: 3));
      }
      final snapshots = await service.listSnapshots();
      expect(snapshots, hasLength(BackupService.keepSnapshots));
      expect(snapshots.first.createdAt.isAfter(snapshots.last.createdAt), isTrue);
      expect(dir.listSync(recursive: true).where((e) => e.path.endsWith('.tmp')), isEmpty);
    });
  });
}

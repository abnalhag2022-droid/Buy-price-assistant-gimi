import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:buy_price_assistant_gimi/data/app_database.dart';

/// Search timing with synthetic data. Skipped unless GIMI_BENCHMARK=1:
///   GIMI_BENCHMARK=1 flutter test test/benchmark/search_benchmark_test.dart
/// Numbers depend on the machine; compare runs made on the same machine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final enabled = Platform.environment['GIMI_BENCHMARK'] == '1';

  test('search timing with 5,000 products and 35,000 price records', () async {
    final dir = await Directory.systemTemp.createTemp('gimi_bench_');
    final db = AppDatabase(factory: databaseFactoryFfi, databasePathProvider: () async => dir.path);
    const kinds = ['كابل', 'لوح شمسي', 'محول', 'بطارية', 'غطاس'];
    final seed = Stopwatch()..start();
    for (var i = 0; i < 5000; i++) {
      final id = await db.saveProduct(
        name: '${kinds[i % 5]} ${i % 97} خط ${i % 13} ملم رقم $i',
        code: 'C-$i', category: 'فئة ${i % 20}', brand: 'Brand${i % 30}',
      );
      for (var j = 0; j < 5; j++) {
        await db.recordPurchase(
          productId: id, date: '2026-${(j % 12 + 1).toString().padLeft(2, '0')}-1${j % 9}',
          unitPrice: 100.0 + i + j, quantity: 1, supplier: 'مورد ${(i + j) % 40}', notes: j == 0 ? 'ملاحظة $i' : null,
        );
      }
      for (var j = 0; j < 2; j++) {
        await db.recordSale(productId: id, date: '2026-0${j + 4}-20', unitPrice: 150.0 + i, quantity: 1, customer: 'عميل ${i % 50}');
      }
    }
    seed.stop();
    final queries = <String>['', 'كابل', 'كابل 4 ملم', 'مورد 17', '2026-03', '١٢٣', 'غير موجود'];
    final lines = <String>['seed: ${seed.elapsedMilliseconds} ms'];
    for (final q in queries) {
      final times = <int>[];
      var rows = 0;
      for (var run = 0; run < 5; run++) {
        final watch = Stopwatch()..start();
        rows = (await db.searchProducts(q, limit: 250)).length;
        watch.stop();
        times.add(watch.elapsedMicroseconds);
      }
      times.sort();
      lines.add('query "${q.isEmpty ? '(empty)' : q}": median ${(times[2] / 1000).toStringAsFixed(1)} ms, rows $rows');
    }
    // ignore: avoid_print
    print(lines.join('\n'));
    await db.close();
    await dir.delete(recursive: true);
  }, skip: enabled ? false : 'set GIMI_BENCHMARK=1 to run', timeout: const Timeout(Duration(minutes: 20)));
}

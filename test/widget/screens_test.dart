import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buy_price_assistant_gimi/data/app_database.dart';
import 'package:buy_price_assistant_gimi/data/backup_service.dart';
import 'package:buy_price_assistant_gimi/data/spreadsheet_exchange.dart';
import 'package:buy_price_assistant_gimi/models/product.dart';
import 'package:buy_price_assistant_gimi/screens/backup_restore_screen.dart';
import 'package:buy_price_assistant_gimi/screens/data_exchange_screen.dart';
import 'package:buy_price_assistant_gimi/screens/home_screen.dart';
import 'package:buy_price_assistant_gimi/screens/import_preview_screen.dart';
import 'package:buy_price_assistant_gimi/screens/price_entry_form_screen.dart';
import 'package:buy_price_assistant_gimi/screens/product_details_screen.dart';
import 'package:buy_price_assistant_gimi/screens/product_form_screen.dart';
import 'package:buy_price_assistant_gimi/screens/settings_screen.dart';
import 'package:buy_price_assistant_gimi/screens/support_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'harness.dart';

/// Every screen renders without layout overflow or exceptions on a small and
/// a large phone, in Arabic (RTL) and English (LTR), light and dark.
void main() {
  sqfliteFfiInit();

  final screens = <String, Future<Widget> Function(AppDatabase db, int productId)>{
    'home': (db, id) async => const HomeScreen(),
    'product details': (db, id) async => ProductDetailsScreen(productId: id),
    'new product': (db, id) async => const ProductFormScreen(),
    'edit product': (db, id) async => ProductFormScreen(product: Product.fromMap((await db.getProduct(id))!)),
    'record purchase': (db, id) async => PriceEntryFormScreen(product: Product.fromMap((await db.getProduct(id))!), isPurchase: true),
    'settings': (db, id) async => const SettingsScreen(),
    'import and export': (db, id) async => const DataExchangeScreen(),
    'import preview': (db, id) async {
      const csv = 'Type,Product Name,Unit,Date,Unit Price,Currency,Quantity,Supplier\n'
          'PURCHASE,كابل نحاس 4 خط 2 ملم,متر,2026-10-21,1400,YER,50,مورد جديد\n'
          'PURCHASE,مضخة غاطسة 2 حصان,قطعة,2026-10-22,95,USD,1,\n'
          'PURCHASE,,قطعة,2026-10-22,95,USD,1,\n';
      final exchange = SpreadsheetExchange.forDatabase(db);
      final parsed = SpreadsheetExchange.parseSpreadsheet(Uint8List.fromList(utf8.encode(csv)), 'prices.csv', defaultCurrency: 'YER');
      final preview = await SpreadsheetExchange.analyze(parsed, 'prices.csv', await db.database);
      return ImportPreviewScreen(preview: preview, exchange: exchange);
    },
    'backup': (db, id) async => BackupRestoreScreen(
          service: BackupService(database: db, directoryProvider: () async => Directory.systemTemp.createTempSync('gimi_snap_').path),
        ),
    'support': (db, id) async => const SupportScreen(),
  };

  for (final entry in screens.entries) {
    for (final size in [smallPhone, largePhone]) {
      for (final language in ['ar', 'en']) {
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          final name = '${entry.key} · ${size.width.toInt()}dp · $language · ${mode.name}';
          testWidgets(name, (tester) async {
            await setSurface(tester, size);
            late Widget screen;
            await tester.runAsync(() async {
              await setLanguage(language);
              final db = await installTestDatabase();
              final id = await seedProducts(db);
              screen = await entry.value(db, id);
            });
            await tester.pumpWidget(testApp(screen, language: language, themeMode: mode));
            await settle(tester);
            expect(tester.takeException(), isNull);
            final direction = Directionality.of(tester.element(find.byType(Scaffold).first));
            expect(direction, language == 'ar' ? TextDirection.rtl : TextDirection.ltr);
          });
        }
      }
    }
  }

  testWidgets('home on a small phone with 130% text renders without overflow', (tester) async {
    await setSurface(tester, smallPhone, textScale: 1.3);
    await tester.runAsync(() async {
      await setLanguage('ar');
      await seedProducts(await installTestDatabase());
    });
    await tester.pumpWidget(testApp(const HomeScreen(), language: 'ar', themeMode: ThemeMode.light));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}

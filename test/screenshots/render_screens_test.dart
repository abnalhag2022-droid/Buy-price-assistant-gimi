import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:buy_price_assistant_gimi/data/app_database.dart';
import 'package:buy_price_assistant_gimi/data/backup_service.dart';
import 'package:buy_price_assistant_gimi/data/spreadsheet_exchange.dart';
import 'package:buy_price_assistant_gimi/screens/backup_restore_screen.dart';
import 'package:buy_price_assistant_gimi/screens/data_exchange_screen.dart';
import 'package:buy_price_assistant_gimi/screens/home_screen.dart';
import 'package:buy_price_assistant_gimi/screens/import_preview_screen.dart';
import 'package:buy_price_assistant_gimi/models/product.dart';
import 'package:buy_price_assistant_gimi/screens/price_entry_form_screen.dart';
import 'package:buy_price_assistant_gimi/screens/product_details_screen.dart';
import 'package:buy_price_assistant_gimi/screens/settings_screen.dart';
import 'package:buy_price_assistant_gimi/screens/support_screen.dart';
import 'package:buy_price_assistant_gimi/ui/app_theme.dart';

import '../widget/harness.dart';

/// Renders real screenshots for design review into .screenshots/ (ignored by
/// git). Skipped unless GIMI_SCREENSHOTS=1. Text uses Roboto with Noto Naskh
/// Arabic as fallback, like Android; fonts come from the local Flutter SDK.
void main() {
  sqfliteFfiInit();
  final enabled = Platform.environment['GIMI_SCREENSHOTS'] == '1';
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter-sdk/flutter';

  Future<void> loadFonts() async {
    Future<ByteData> read(String path) async => ByteData.sublistView(await File(path).readAsBytes());
    final material = '$flutterRoot/bin/cache/artifacts/material_fonts';
    final roboto = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      roboto.addFont(read('$material/Roboto-$weight.ttf'));
    }
    await roboto.load();
    await (FontLoader('MaterialIcons')..addFont(read('$material/MaterialIcons-Regular.otf'))).load();
    await (FontLoader('NotoNaskhArabic')
          ..addFont(read('$flutterRoot/engine/src/flutter/txt/third_party/fonts/NotoNaskhArabic-Regular.ttf')))
        .load();
  }

  ThemeData withFonts(ThemeData theme) => theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'Roboto', fontFamilyFallback: const ['NotoNaskhArabic']),
      );

  final shots = <String, Future<Widget> Function(AppDatabase db, int id)>{
    'home': (db, id) async => const HomeScreen(),
    'details': (db, id) async => ProductDetailsScreen(productId: id),
    'entry': (db, id) async => PriceEntryFormScreen(product: Product.fromMap((await db.getProduct(id))!), isPurchase: true),
    'settings': (db, id) async => const SettingsScreen(),
    'exchange': (db, id) async => const DataExchangeScreen(),
    'preview': (db, id) async {
      const csv = 'Type,Product Name,Unit,Date,Unit Price,Currency,Quantity,Supplier\n'
          'PURCHASE,كابل نحاس 4 خط 2 ملم,متر,2026-10-21,1400,YER,50,مورد جديد\n'
          'PURCHASE,مضخة غاطسة 2 حصان,قطعة,2026-10-22,95,USD,1,\n'
          'PURCHASE,,قطعة,2026-10-22,95,USD,1,\n';
      final parsed = SpreadsheetExchange.parseSpreadsheet(Uint8List.fromList(utf8.encode(csv)), 'prices.csv', defaultCurrency: 'YER');
      final preview = await SpreadsheetExchange.analyze(parsed, 'prices.csv', await db.database);
      return ImportPreviewScreen(preview: preview, exchange: SpreadsheetExchange.forDatabase(db));
    },
    'backup': (db, id) async => BackupRestoreScreen(
          service: BackupService(database: db, directoryProvider: () async => Directory.systemTemp.createTempSync('gimi_snap_').path),
        ),
    'support': (db, id) async => const SupportScreen(),
  };

  final variants = <(String, ThemeMode, Size)>[
    ('ar', ThemeMode.light, largePhone),
    ('ar', ThemeMode.dark, largePhone),
    ('en', ThemeMode.light, largePhone),
    ('ar', ThemeMode.light, smallPhone),
  ];

  for (final shot in shots.entries) {
    for (final (language, mode, size) in variants) {
      final name = '${shot.key}_${language}_${mode.name}_${size.width.toInt()}';
      testWidgets(name, (tester) async {
        await setSurface(tester, size);
        late Widget screen;
        await tester.runAsync(() async {
          await loadFonts();
          await setLanguage(language);
          final db = await installTestDatabase();
          final id = await seedProducts(db);
          screen = await shot.value(db, id);
        });
        final key = GlobalKey();
        // flutter_test draws shadows as solid outlines; draw them as on a device.
        debugDisableShadows = false;
        await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: testApp(screen, language: language, themeMode: mode,
              light: withFonts(AppTheme.light()), dark: withFonts(AppTheme.dark())),
        ));
        await settle(tester);
        await tester.runAsync(() async {
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('.screenshots/$name.png')..createSync(recursive: true);
          file.writeAsBytesSync(png!.buffer.asUint8List());
        });
        debugDisableShadows = true;
      }, skip: !enabled);
    }
  }

  testWidgets('home_empty_ar_light_412', (tester) async {
    await setSurface(tester, largePhone);
    await tester.runAsync(() async {
      await loadFonts();
      await setLanguage('ar');
      await (await installTestDatabase()).database;
    });
    final key = GlobalKey();
    debugDisableShadows = false;
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: testApp(const HomeScreen(), language: 'ar', themeMode: ThemeMode.light, light: withFonts(AppTheme.light())),
    ));
    await settle(tester);
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('.screenshots/home_empty_ar_light_412.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(png!.buffer.asUint8List());
    });
    debugDisableShadows = true;
  }, skip: !enabled);
}

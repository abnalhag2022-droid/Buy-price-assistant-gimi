import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:buy_price_assistant_gimi/data/app_database.dart';
import 'package:buy_price_assistant_gimi/state/app_settings.dart';
import 'package:buy_price_assistant_gimi/ui/app_theme.dart';

/// Phone sizes used by the screen tests (logical pixels).
const Size smallPhone = Size(320, 640);
const Size largePhone = Size(412, 915);

/// A fresh database in a temporary directory, installed as
/// [AppDatabase.instance]. The non-isolate FFI factory lets database futures
/// complete inside widget tests.
Future<AppDatabase> installTestDatabase() async {
  final dir = Directory.systemTemp.createTempSync('gimi_widget_');
  final db = AppDatabase(factory: databaseFactoryFfiNoIsolate, databasePathProvider: () async => dir.path);
  AppDatabase.instance = db;
  addTearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });
  return db;
}

Future<void> setLanguage(String language) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await AppSettings.instance.load();
  await AppSettings.instance.setLanguage(language);
}

/// Seeds a product with purchase and sale history and one without prices.
Future<int> seedProducts(AppDatabase db) async {
  final id = await db.saveProduct(
    name: 'كابل نحاس 2 خط 4 ملم', code: 'CU-2x4', category: 'كابلات', brand: 'Riyadh Cables', unit: 'متر',
    notes: 'لفة 100 متر',
  );
  await db.recordPurchase(productId: id, date: '2026-09-14', unitPrice: 1250.5, quantity: 100,
      supplier: 'مؤسسة النور للتجارة', invoiceNumber: 'F-1029', currencyCode: 'YER');
  await db.recordPurchase(productId: id, date: '2026-10-02', unitPrice: 1310, quantity: 200,
      supplier: 'مؤسسة النور للتجارة', currencyCode: 'YER');
  await db.recordSale(productId: id, date: '2026-10-20', unitPrice: 1600, quantity: 35,
      customer: 'ورشة الأمل', notes: 'تسليم فوري', currencyCode: 'YER');
  await db.saveProduct(name: 'لوح شمسي 550 واط أحادي البلورة', code: 'PV-550', category: 'ألواح شمسية', unit: 'قطعة');
  final usd = await db.saveProduct(name: 'إنفرتر هجين 5 كيلوواط', category: 'إنفرترات', brand: 'Growatt', unit: 'قطعة');
  await db.recordPurchase(productId: usd, date: '2026-08-01', unitPrice: 412.75, quantity: 3, supplier: 'Sun Trade', currencyCode: 'USD');
  await db.recordSale(productId: usd, date: '2026-08-09', unitPrice: 2650, quantity: 1, customer: 'عميل نقدي', currencyCode: 'SAR');
  return id;
}

Widget testApp(Widget home, {required String language, required ThemeMode themeMode, ThemeData? light, ThemeData? dark}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(language),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: light ?? AppTheme.light(),
      darkTheme: dark ?? AppTheme.dark(),
      themeMode: themeMode,
      home: home,
    );

Future<void> setSurface(WidgetTester tester, Size size, {double textScale = 1}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Pumps until database work and animations finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

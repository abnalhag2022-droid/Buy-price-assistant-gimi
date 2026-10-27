import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:buy_price_assistant_gimi/data/app_database.dart';
import 'package:buy_price_assistant_gimi/models/price_entry.dart';
import 'package:buy_price_assistant_gimi/models/product.dart';
import 'package:buy_price_assistant_gimi/screens/home_screen.dart';
import 'package:buy_price_assistant_gimi/screens/price_entry_form_screen.dart';
import 'package:buy_price_assistant_gimi/screens/product_details_screen.dart';
import 'package:buy_price_assistant_gimi/screens/product_form_screen.dart';
import 'package:buy_price_assistant_gimi/screens/settings_screen.dart';
import 'package:buy_price_assistant_gimi/state/app_settings.dart';

import 'harness.dart';

void main() {
  sqfliteFfiInit();

  Future<(AppDatabase, int)> prepare(WidgetTester tester, {String language = 'ar'}) async {
    await setSurface(tester, largePhone);
    late AppDatabase db;
    late int id;
    await tester.runAsync(() async {
      await setLanguage(language);
      db = await installTestDatabase();
      id = await seedProducts(db);
    });
    return (db, id);
  }

  Future<void> show(WidgetTester tester, Widget screen, {String language = 'ar'}) async {
    await tester.pumpWidget(testApp(screen, language: language, themeMode: ThemeMode.light));
    await settle(tester);
  }

  Future<Product> productOf(WidgetTester tester, AppDatabase db, int id) async =>
      Product.fromMap((await tester.runAsync<Map<String, Object?>?>(() => db.getProduct(id)))!);

  testWidgets('search waits for a pause in typing, then shows the matching items and their count', (tester) async {
    await prepare(tester);
    await show(tester, const HomeScreen());
    expect(find.text('عدد الأصناف: \u20663\u2069'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'نحاس');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('إنفرتر هجين 5 كيلوواط'), findsOneWidget, reason: 'no query before the debounce delay');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.text('كابل نحاس 2 خط 4 ملم'), findsOneWidget);
    expect(find.text('إنفرتر هجين 5 كيلوواط'), findsNothing);
    expect(find.text('عدد الأصناف: \u20661\u2069'), findsOneWidget);
  });

  testWidgets('an item without prices says so and shows no invented price', (tester) async {
    await prepare(tester);
    await show(tester, const HomeScreen());
    final card = find.ancestor(of: find.text('لوح شمسي 550 واط أحادي البلورة'), matching: find.byType(Card));
    expect(find.descendant(of: card, matching: find.text('لا يوجد سعر مسجل')), findsNWidgets(2));
  });

  testWidgets('archived items are listed separately and can be restored', (tester) async {
    final (db, id) = await prepare(tester);
    await tester.runAsync(() => db.archiveProduct(id));
    await show(tester, const HomeScreen());
    expect(find.text('كابل نحاس 2 خط 4 ملم'), findsNothing);

    await tester.tap(find.text('المؤرشفة'));
    await settle(tester);
    expect(find.text('كابل نحاس 2 خط 4 ملم'), findsOneWidget);
    await tester.tap(find.text('إلغاء الأرشفة'));
    await settle(tester);
    final product = await productOf(tester, db, id);
    expect(product.isArchived, isFalse);
  });

  testWidgets('a double tap on save creates the product once', (tester) async {
    final (db, _) = await prepare(tester);
    await show(tester, const ProductFormScreen());
    await tester.enterText(find.byType(TextFormField).first, 'منظم جهد 10 كيلو');
    final save = find.text('حفظ الصنف');
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await settle(tester);
    final count = await tester.runAsync(() => db.countProducts('منظم'));
    expect(count, 1);
  });

  testWidgets('leaving a form with unsaved changes asks first', (tester) async {
    await prepare(tester);
    await tester.pumpWidget(testApp(
      Builder(builder: (context) => Scaffold(body: Center(child: TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProductFormScreen())),
        child: const Text('open'),
      )))),
      language: 'ar',
      themeMode: ThemeMode.light,
    ));
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.enterText(find.byType(TextFormField).first, 'صنف لم يُحفظ');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('تجاهل التغييرات؟'), findsOneWidget);
    await tester.tap(find.text('متابعة التعديل'));
    await settle(tester);
    expect(find.text('صنف لم يُحفظ'), findsOneWidget, reason: 'the form stays open with the text');
  });

  testWidgets('editing a record shows its exact values and currency', (tester) async {
    final (db, id) = await prepare(tester);
    final product = await productOf(tester, db, id);
    final history = await tester.runAsync(() => db.getPurchaseHistory(id));
    final oldest = PriceEntry.fromMap(history!.last);
    await show(tester, PriceEntryFormScreen(product: product, isPurchase: true, entry: oldest));
    expect(find.widgetWithText(TextFormField, '1250.5'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '100'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'F-1029'), findsOneWidget);
  });

  testWidgets('a new record starts in the currency of the last record, not the app default', (tester) async {
    final (db, id) = await prepare(tester);
    await tester.runAsync(() => AppSettings.instance.setCurrency('USD'));
    final product = await productOf(tester, db, id);
    await show(tester, PriceEntryFormScreen(product: product, isPurchase: true));
    final segmented = tester.widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
    expect(segmented.selected, {'YER'});
  });

  testWidgets('prices in different currencies are never subtracted', (tester) async {
    final (db, _) = await prepare(tester);
    final id = (await tester.runAsync(() => db.findExactProductName('إنفرتر هجين 5 كيلوواط')))!['id']! as int;
    await show(tester, ProductDetailsScreen(productId: id));
    expect(find.textContaining('بعملتين مختلفتين'), findsOneWidget);
    expect(find.textContaining('الفرق بين آخر بيع'), findsNothing);
  });

  testWidgets('removing a category asks first and cancelling keeps it', (tester) async {
    await prepare(tester);
    await show(tester, const SettingsScreen());
    final chip = find.widgetWithText(InputChip, 'بطاريات');
    await tester.ensureVisible(chip);
    await tester.tap(find.descendant(of: chip, matching: find.byIcon(Icons.clear)));
    await settle(tester);
    expect(find.text('إزالة التصنيف؟'), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await settle(tester);
    expect(AppSettings.instance.categories, contains('بطاريات'));
  });

  testWidgets('English mode shows English text for data errors', (tester) async {
    await prepare(tester, language: 'en');
    await show(tester, const ProductDetailsScreen(productId: 999), language: 'en');
    expect(find.textContaining('The item was not found'), findsOneWidget);
    expect(find.textContaining('لم يُعثر'), findsNothing);
  });
}

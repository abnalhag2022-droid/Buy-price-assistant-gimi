import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buy_price_assistant_gimi/state/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('loads defaults with USD as the preferred new-entry currency', () async {
    await AppSettings.instance.load();
    expect(AppSettings.instance.language, 'ar');
    expect(AppSettings.instance.theme, 'light');
    expect(AppSettings.instance.currency, 'USD');
    expect(AppSettings.instance.categories, isNotEmpty);
    expect(AppSettings.instance.units, contains('قطعة'));
  });

  test('persists language, theme, and preferred currency', () async {
    await AppSettings.instance.load();
    await AppSettings.instance.setLanguage('en');
    await AppSettings.instance.setTheme('dark');
    await AppSettings.instance.setCurrency('SAR');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('gimi.language'), 'en');
    expect(prefs.getString('gimi.theme'), 'dark');
    expect(prefs.getString('gimi.currency'), 'SAR');
  });

  test('validates exported settings and rejects invalid currency', () async {
    await AppSettings.instance.load();
    final snapshot = AppSettings.instance.exportSettings();
    expect(AppSettings.validateBackupSettings(snapshot)['currency'], 'USD');
    final bad = <String, Object?>{...snapshot, 'currency': 'EUR'};
    expect(() => AppSettings.validateBackupSettings(bad), throwsFormatException);
  });

  test('restores language, theme, currency, categories, and units from a valid snapshot', () async {
    await AppSettings.instance.load();
    final snapshot = <String, Object?>{
      'language': 'en',
      'theme': 'dark',
      'currency': 'SAR',
      'categories': <String>['محولات', 'محولات', '  بطاريات  ', ''],
      'units': <String>['قطعة', 'متر'],
    };

    await AppSettings.instance.restoreSettings(snapshot);

    expect(AppSettings.instance.language, 'en');
    expect(AppSettings.instance.theme, 'dark');
    expect(AppSettings.instance.currency, 'SAR');
    expect(AppSettings.instance.categories, <String>['محولات', 'بطاريات']);
    expect(AppSettings.instance.units, <String>['قطعة', 'متر']);

    await AppSettings.instance.load();
    expect(AppSettings.instance.language, 'en');
    expect(AppSettings.instance.theme, 'dark');
    expect(AppSettings.instance.currency, 'SAR');
    expect(AppSettings.instance.categories, <String>['محولات', 'بطاريات']);
    expect(AppSettings.instance.units, <String>['قطعة', 'متر']);
  });

  test('rejects invalid backup settings before changing current settings', () async {
    await AppSettings.instance.load();
    await AppSettings.instance.setLanguage('en');
    final before = AppSettings.instance.exportSettings();
    final invalid = <String, Object?>{...before, 'theme': 'invalid'};

    expect(
      () => AppSettings.instance.restoreSettings(invalid),
      throwsFormatException,
    );
    expect(AppSettings.instance.exportSettings(), before);
  });

  test('rejects duplicate categories and supports removing catalog values', () async {
    await AppSettings.instance.load();
    await AppSettings.instance.addCategory('تجربة مؤقتة');
    await expectLater(
      AppSettings.instance.addCategory('تجربة مؤقتة'),
      throwsA(isA<StateError>()),
    );
    expect(AppSettings.instance.categories.where((v) => v == 'تجربة مؤقتة').length, 1);
    await AppSettings.instance.removeCategory('تجربة مؤقتة');
    expect(AppSettings.instance.categories, isNot(contains('تجربة مؤقتة')));
  });
}

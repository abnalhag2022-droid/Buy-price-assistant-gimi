import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/currencies.dart';
import '../utils/localized_message.dart';

/// Persistent local preferences for the offline-first app.
/// Changes are stored before they are announced to the UI.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  String _language = 'ar';
  String _theme = 'light';
  String _currency = 'USD';
  List<String> _categories = <String>[
    'محولات', 'بطاريات', 'ألواح شمسية', 'إنفرترات', 'كابلات',
    'ملحقات', 'أدوات', 'قطع غيار', 'أجهزة كهربائية', 'أخرى',
  ];
  List<String> _units = <String>[
    'قطعة', 'كرتون', 'متر', 'كيلوغرام', 'غرام', 'لتر',
    'أمبير', 'كيلوواط', 'كيلوواط ساعة', 'مجموعة',
  ];

  String get language => _language;
  bool get isArabic => _language == 'ar';
  Locale get locale => Locale(_language);
  String get theme => _theme;
  String get currency => _currency;
  List<String> get categories => List<String>.unmodifiable(_categories);
  List<String> get units => List<String>.unmodifiable(_units);

  ThemeMode get themeMode => switch (_theme) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      };

  Future<void> load() async {
    // Reset in-memory defaults before loading persisted values. This also makes reloads deterministic.
    _language = 'ar';
    _theme = 'light';
    _currency = 'USD';
    _categories = <String>['محولات','بطاريات','ألواح شمسية','إنفرترات','كابلات','ملحقات','أدوات','قطع غيار','أجهزة كهربائية','أخرى'];
    _units = <String>['قطعة','كرتون','متر','كيلوغرام','غرام','لتر','أمبير','كيلوواط','كيلوواط ساعة','مجموعة'];
    final prefs = await SharedPreferences.getInstance();
    final language = prefs.getString('gimi.language');
    final theme = prefs.getString('gimi.theme');
    final currency = prefs.getString('gimi.currency');
    if (language == 'ar' || language == 'en') _language = language!;
    if (theme == 'light' || theme == 'dark' || theme == 'system') _theme = theme!;
    if (currency != null && AppCurrencies.isSupported(currency)) _currency = currency;
    final categories = prefs.getStringList('gimi.categories');
    final units = prefs.getStringList('gimi.units');
    if (categories != null && categories.isNotEmpty) {
      final cleanCategories = _cleanList(categories);
      if (cleanCategories.isNotEmpty) _categories = cleanCategories;
    }
    if (units != null && units.isNotEmpty) {
      final cleanUnits = _cleanList(units);
      if (cleanUnits.isNotEmpty) _units = cleanUnits;
    }
  }

  Future<void> setLanguage(String value) async {
    if (value != 'ar' && value != 'en') {
      throw ArgumentError.value(value, 'value', 'Unsupported language.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gimi.language', value);
    _language = value;
    notifyListeners();
  }

  Future<void> setTheme(String value) async {
    if (!const <String>{'light', 'dark', 'system'}.contains(value)) {
      throw ArgumentError.value(value, 'value', 'Unsupported theme.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gimi.theme', value);
    _theme = value;
    notifyListeners();
  }

  Future<void> setCurrency(String value) async {
    if (!AppCurrencies.isSupported(value)) {
      throw ArgumentError.value(value, 'value', 'Unsupported currency.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gimi.currency', value);
    _currency = value;
    notifyListeners();
  }

  Future<void> addCategory(String value) => _addCatalogValue(value, isCategory: true);
  Future<void> addUnit(String value) => _addCatalogValue(value, isCategory: false);

  Future<void> removeCategory(String value) async {
    _categories.removeWhere((item) => item == value);
    if (_categories.isEmpty) _categories = <String>['أخرى'];
    await _saveList('gimi.categories', _categories);
    notifyListeners();
  }

  Future<void> removeUnit(String value) async {
    _units.removeWhere((item) => item == value);
    if (_units.isEmpty) _units = <String>['قطعة'];
    await _saveList('gimi.units', _units);
    notifyListeners();
  }

  Future<void> _addCatalogValue(String value, {required bool isCategory}) async {
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) throw LocalizedArgumentError('القيمة لا يمكن أن تكون فارغة.', 'The value cannot be empty.');
    final target = isCategory ? _categories : _units;
    if (target.any((item) => item.toLowerCase() == clean.toLowerCase())) {
      throw LocalizedStateError('هذه القيمة مسجلة مسبقًا.', 'This value already exists.');
    }
    if (target.length >= 100) {
      throw LocalizedStateError('وصلت القائمة إلى الحد الأقصى (100 عنصر).', 'The list reached its limit (100 entries).');
    }
    target.add(clean);
    await _saveList(isCategory ? 'gimi.categories' : 'gimi.units', target);
    notifyListeners();
  }

  List<String> _cleanList(List<String> values) {
    final result = <String>[];
    for (final raw in values) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      if (!result.any((item) => item.toLowerCase() == value.toLowerCase())) {
        result.add(value);
      }
      if (result.length >= 100) break;
    }
    return result;
  }

  Future<void> _saveList(String key, List<String> values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, List<String>.from(values));
  }

  Map<String, Object?> exportSettings() => <String, Object?>{
        'language': _language,
        'theme': _theme,
        'currency': _currency,
        'categories': List<String>.from(_categories),
        'units': List<String>.from(_units),
      };

  static Map<String, Object?> validateBackupSettings(Object? source) {
    if (source is! Map) {
      throw const LocalizedFormatException('إعدادات النسخة الاحتياطية غير صالحة.', 'The backup settings are invalid.');
    }
    final map = Map<String, Object?>.from(source);
    final language = map['language'];
    final theme = map['theme'];
    final currency = map['currency'];
    final categories = map['categories'];
    final units = map['units'];

    if (language is! String || !const <String>{'ar', 'en'}.contains(language)) {
      throw const LocalizedFormatException('لغة النسخة الاحتياطية غير صالحة.', 'The backup language setting is invalid.');
    }
    if (theme is! String || !const <String>{'light', 'dark', 'system'}.contains(theme)) {
      throw const LocalizedFormatException('المظهر في النسخة الاحتياطية غير صالح.', 'The backup appearance setting is invalid.');
    }
    if (currency is! String || !AppCurrencies.isSupported(currency)) {
      throw const LocalizedFormatException('العملة الافتراضية في النسخة الاحتياطية غير صالحة.', 'The backup default currency is invalid.');
    }
    if (categories is! List || units is! List ||
        categories.any((item) => item is! String) ||
        units.any((item) => item is! String)) {
      throw const LocalizedFormatException('قوائم التصنيفات أو الوحدات غير صالحة.', 'The category or unit lists are invalid.');
    }
    if (categories.length > 100 || units.length > 100) {
      throw const LocalizedFormatException('قوائم الإعدادات أكبر من الحد المسموح.', 'The settings lists are larger than allowed.');
    }
    return <String, Object?>{
      'language': language,
      'theme': theme,
      'currency': currency,
      'categories': categories.cast<String>(),
      'units': units.cast<String>(),
    };
  }

  Future<void> restoreSettings(Map<String, Object?> values) async {
    final valid = validateBackupSettings(values);
    final categories = _cleanList((valid['categories']! as List).cast<String>());
    final units = _cleanList((valid['units']! as List).cast<String>());
    if (categories.isEmpty) categories.add('أخرى');
    if (units.isEmpty) units.add('قطعة');

    final prefs = await SharedPreferences.getInstance();
    const keys = <String>[
      'gimi.language',
      'gimi.theme',
      'gimi.currency',
      'gimi.categories',
      'gimi.units',
    ];
    final previous = <String, Object?>{
      'gimi.language': prefs.getString('gimi.language'),
      'gimi.theme': prefs.getString('gimi.theme'),
      'gimi.currency': prefs.getString('gimi.currency'),
      'gimi.categories': prefs.getStringList('gimi.categories'),
      'gimi.units': prefs.getStringList('gimi.units'),
    };

    // SharedPreferences does not provide a multi-key transaction. If any write
    // fails, restore the previous values before propagating the failure.
    try {
      final results = <bool>[
        await prefs.setString('gimi.language', valid['language']! as String),
        await prefs.setString('gimi.theme', valid['theme']! as String),
        await prefs.setString('gimi.currency', valid['currency']! as String),
        await prefs.setStringList('gimi.categories', categories),
        await prefs.setStringList('gimi.units', units),
      ];
      if (results.any((success) => !success)) {
        throw LocalizedStateError('تعذر حفظ بعض إعدادات النسخة الاحتياطية.', 'Some backup settings could not be saved.');
      }
    } catch (error) {
      Object? rollbackError;
      for (final key in keys.reversed) {
        try {
          final oldValue = previous[key];
          if (oldValue == null) {
            await prefs.remove(key);
          } else if (key == 'gimi.categories' || key == 'gimi.units') {
            await prefs.setStringList(key, List<String>.from(oldValue as List<String>));
          } else {
            await prefs.setString(key, oldValue as String);
          }
        } catch (restoreError) {
          rollbackError ??= restoreError;
        }
      }
      if (rollbackError != null) {
        throw LocalizedStateError(
          'فشل حفظ الإعدادات وفشل التراجع عن بعضها: $rollbackError',
          'Saving the settings failed and some could not be rolled back: $rollbackError',
        );
      }
      rethrow;
    }

    _language = valid['language']! as String;
    _theme = valid['theme']! as String;
    _currency = valid['currency']! as String;
    _categories = categories;
    _units = units;
    notifyListeners();
  }
}

/// Supported transaction currencies. The database CHECK constraint on fresh
/// installs, imports, restores and every write path rely on this single list.
class AppCurrencies {
  AppCurrencies._();

  static const String usd = 'USD';
  static const String sar = 'SAR';
  static const String yer = 'YER';

  /// Display order used by pickers.
  static const List<String> supported = <String>[usd, sar, yer];

  /// Records created before currencies were stored (schema v1) were YER.
  static const String legacyDefault = yer;

  static bool isSupported(Object? code) => code is String && supported.contains(code);

  /// Returns the upper-cased code when supported, otherwise null.
  static String? tryParse(String? code) {
    final value = code?.trim().toUpperCase();
    return isSupported(value) ? value : null;
  }

  static String englishName(String code) => switch (code) {
        usd => 'US Dollar',
        sar => 'Saudi Riyal',
        _ => 'Yemeni Rial',
      };

  static String arabicName(String code) => switch (code) {
        usd => 'دولار أمريكي',
        sar => 'ريال سعودي',
        _ => 'ريال يمني',
      };

  static String arabicSymbol(String code) => switch (code) {
        usd => 'دولار',
        sar => 'ر.س',
        _ => 'ر.ي',
      };
}

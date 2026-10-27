/// Single source for the app identity shown inside the app. `version` and
/// `buildNumber` must equal `version:` in pubspec.yaml, which sets the
/// Android versionName/versionCode; test/app_info_test.dart enforces it.
abstract final class AppInfo {
  static const String nameEn = 'Buy Price Assistant HJI';
  static const String nameAr = 'مرجع أسعار الأصناف';
  static const String version = '1.5.0';
  static const int buildNumber = 8;

  static String get versionLabel => '$version ($buildNumber)';
}

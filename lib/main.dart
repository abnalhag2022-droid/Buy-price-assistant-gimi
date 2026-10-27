import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/home_screen.dart';
import 'state/app_settings.dart';
import 'utils/app_info.dart';
import 'utils/error_log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ErrorLog.instance.load();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    ErrorLog.instance.record(details.exception, details.stack, source: 'flutter');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorLog.instance.record(error, stack, source: 'async');
    return true;
  };
  await initializeDateFormatting('ar');
  await initializeDateFormatting('en');
  await AppSettings.instance.load();
  runApp(const BuyPriceAssistantApp());
}

class BuyPriceAssistantApp extends StatelessWidget {
  const BuyPriceAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    const seed = Color(0xFF315A93);

    final lightTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: seed),
      scaffoldBackgroundColor: const Color(0xFFF7F8FA),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Color(0xFFF7F8FA),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE1E5EA)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: seed, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE8EBEF)),
        ),
      ),
    );

    final darkTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
      ).copyWith(
        surface: Colors.black,
        surfaceContainerHighest: const Color(0xFF1C1C1C),
      ),
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.black,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF171717),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF353535)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF789BD1), width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xFF111111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF292929)),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => MaterialApp(
        onGenerateTitle: (_) => settings.isArabic ? AppInfo.nameAr : AppInfo.nameEn,
        debugShowCheckedModeBanner: false,
        locale: settings.locale,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: settings.themeMode,
        home: const HomeScreen(),
      ),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/home_screen.dart';
import 'state/app_settings.dart';
import 'ui/app_theme.dart';
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
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        onGenerateTitle: (_) => settings.isArabic ? AppInfo.nameAr : AppInfo.nameEn,
        debugShowCheckedModeBanner: false,
        locale: settings.locale,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: settings.themeMode,
        home: const HomeScreen(),
      ),
    );
  }
}

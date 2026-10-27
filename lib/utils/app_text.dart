import 'package:flutter/material.dart';

import '../state/app_settings.dart';
import 'app_helpers.dart';
import 'currencies.dart';

/// Use for short interface strings where introducing generated ARB files is not
/// part of this version's scope. Longer-term localization can migrate to gen-l10n.
String appTextValue(String arabic, String english) =>
    AppSettings.instance.isArabic ? arabic : english;

/// Currency shown next to an amount: the Arabic symbol in Arabic, the ISO
/// code in English.
String currencyLabel(BuildContext context, String? code) {
  final currency = code ?? AppCurrencies.legacyDefault;
  if (Localizations.localeOf(context).languageCode != 'ar') return currency;
  return AppCurrencies.arabicSymbol(currency);
}

/// "1,250.5 دولار" / "1,250.5 USD". The number is isolated left-to-right so
/// it is never reordered inside Arabic text. Never invents a value: a missing
/// price is the caller's responsibility to show as "not recorded".
String formatAmount(BuildContext context, num price, String? currency) =>
    '${ltrIsolate(formatMoney(price))} ${currencyLabel(context, currency)}';

String localizeCatalogValue(BuildContext context, String value) {
  if (Localizations.localeOf(context).languageCode != 'en') return value;
  const labels = <String, String>{
    'محولات': 'Converters',
    'بطاريات': 'Batteries',
    'ألواح شمسية': 'Solar panels',
    'إنفرترات': 'Inverters',
    'كابلات': 'Cables',
    'ملحقات': 'Accessories',
    'أدوات': 'Tools',
    'قطع غيار': 'Spare parts',
    'أجهزة كهربائية': 'Electrical devices',
    'أخرى': 'Other',
    'قطعة': 'Piece',
    'كرتون': 'Carton',
    'متر': 'Meter',
    'كيلوغرام': 'Kilogram',
    'غرام': 'Gram',
    'لتر': 'Liter',
    'أمبير': 'Ampere',
    'كيلوواط': 'Kilowatt',
    'كيلوواط ساعة': 'Kilowatt-hour',
    'مجموعة': 'Set',
  };
  return labels[value] ?? value;
}

class AppText extends StatelessWidget {
  const AppText({
    super.key,
    required this.ar,
    required this.en,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.softWrap,
    this.textDirection,
  });

  final String ar;
  final String en;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool? softWrap;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) => Text(
        Localizations.localeOf(context).languageCode == 'ar' ? ar : en,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
        softWrap: softWrap,
        textDirection: textDirection,
      );
}

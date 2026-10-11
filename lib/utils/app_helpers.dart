import 'package:intl/intl.dart';

/// Normalizes common Arabic spelling variants to make item search more forgiving.
/// It deliberately does not merge semantically different letters such as ة and ه.
String normalizeForSearch(String value) {
  return value
      .toLowerCase()
      .replaceAll('\u0640', '')
      .replaceAll(RegExp('[\u064B-\u065F\u0670]'), '')
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي')
      .replaceAll('ى', 'ي')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// Escapes LIKE wildcard characters. The caller uses `ESCAPE '!'` in SQL.
String escapeLikePattern(String value) => value
    .replaceAll('!', '!!')
    .replaceAll('%', '!%')
    .replaceAll('_', '!_');

/// Parses Latin or Arabic-Indic digits, including an Arabic decimal separator.
double? parseLocalizedNumber(String input) {
  var value = input.trim();
  if (value.isEmpty) return null;

  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
  for (var i = 0; i < 10; i++) {
    value = value.replaceAll(arabicDigits[i], '$i');
    value = value.replaceAll(persianDigits[i], '$i');
  }
  value = value.replaceAll('٫', '.').replaceAll('٬', '').replaceAll(' ', '');

  if (!value.contains('.') && value.contains(',')) {
    final pieces = value.split(',');
    if (pieces.length == 2 && pieces.last.length <= 2) {
      value = '${pieces.first}.${pieces.last}';
    } else if (pieces.length >= 2 &&
        pieces.first.isNotEmpty &&
        pieces.first.length <= 3 &&
        pieces.skip(1).every((part) => part.length == 3) &&
        pieces.every((part) => RegExp(r'^\d+$').hasMatch(part))) {
      value = pieces.join();
    } else {
      return null;
    }
  } else if (value.contains('.') && value.contains(',')) {
    final decimalParts = value.split('.');
    if (decimalParts.length != 2) return null;
    final whole = decimalParts.first;
    final groups = whole.split(',');
    final validGrouping = groups.length > 1 &&
        groups.first.isNotEmpty &&
        groups.first.length <= 3 &&
        groups.skip(1).every((part) => part.length == 3) &&
        groups.every((part) => RegExp(r'^\d+$').hasMatch(part));
    if (!validGrouping) return null;
    value = '${groups.join()}.${decimalParts.last}';
  } else {
    value = value.replaceAll(',', '');
  }

  final parsed = double.tryParse(value);
  if (parsed == null || !parsed.isFinite) return null;
  return parsed;
}

String formatMoney(num? value) {
  if (value == null) return '—';
  var result = value.toStringAsFixed(2);
  if (result.endsWith('.00')) {
    result = result.substring(0, result.length - 3);
  } else if (result.endsWith('0')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

String toIsoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String formatDate(String? isoDate) {
  if (isoDate == null || isoDate.isEmpty) return 'غير مسجل';
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  return DateFormat('dd/MM/yyyy', 'ar').format(parsed);
}

String formatDateTime(String? isoDateTime) {
  if (isoDateTime == null || isoDateTime.isEmpty) return 'غير مسجل';
  final parsed = DateTime.tryParse(isoDateTime);
  if (parsed == null) return isoDateTime;
  return DateFormat('dd/MM/yyyy - HH:mm', 'ar').format(parsed);
}

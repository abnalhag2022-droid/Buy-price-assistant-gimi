import 'package:intl/intl.dart';

const String _arabicIndicDigits = '٠١٢٣٤٥٦٧٨٩';
const String _persianDigits = '۰۱۲۳۴۵۶۷۸۹';

/// Converts Arabic-Indic and Persian digits to Latin digits.
/// This is the single digit-normalization routine used by search, number
/// parsing, date parsing, and spreadsheet import.
String normalizeDigits(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    final arabic = _arabicIndicDigits.indexOf(char);
    if (arabic >= 0) {
      buffer.write(arabic);
      continue;
    }
    final persian = _persianDigits.indexOf(char);
    buffer.write(persian >= 0 ? persian : char);
  }
  return buffer.toString();
}

/// Normalizes common Arabic spelling variants to make item search more forgiving.
/// It deliberately does not merge semantically different letters such as ة and ه.
String normalizeForSearch(String value) {
  final text = value
      .toLowerCase()
      .replaceAll('ـ', '')
      .replaceAll(RegExp('[ً-ٰٟ]'), '')
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي')
      .replaceAll('ى', 'ي');
  return normalizeDigits(text).trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Escapes LIKE wildcard characters. The caller uses `ESCAPE '!'` in SQL.
String escapeLikePattern(String value) => value
    .replaceAll('!', '!!')
    .replaceAll('%', '!%')
    .replaceAll('_', '!_');

/// Parses Latin or Arabic-Indic digits, including an Arabic decimal separator.
double? parseLocalizedNumber(String input) {
  var value = normalizeDigits(input.trim());
  if (value.isEmpty) return null;
  value = value.replaceAll('٫', '.').replaceAll('٬', '').replaceAll(' ', '');

  // Only plain decimal notation is accepted; exponents such as 1e5 are rejected.
  if (!RegExp(r'^[+-]?[0-9.,]+$').hasMatch(value)) return null;

  if (!value.contains('.') && value.contains(',')) {
    final pieces = value.split(',');
    if (pieces.length == 2 && pieces.last.length <= 2) {
      value = '${pieces.first}.${pieces.last}';
    } else if (pieces.length >= 2 &&
        pieces.first.isNotEmpty &&
        pieces.first.length <= 3 &&
        pieces.skip(1).every((part) => part.length == 3) &&
        pieces.every((part) => RegExp(r'^[+-]?\d+$').hasMatch(part))) {
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
        groups.every((part) => RegExp(r'^[+-]?\d+$').hasMatch(part));
    if (!validGrouping) return null;
    value = '${groups.join()}.${decimalParts.last}';
  }

  final parsed = double.tryParse(value);
  if (parsed == null || !parsed.isFinite) return null;
  return parsed;
}

final NumberFormat _moneyFormat = NumberFormat('#,##0.##', 'en');
final NumberFormat _quantityFormat = NumberFormat('#,##0.###', 'en');

/// Formats an amount with thousands separators and at most two decimals.
/// Latin digits are used everywhere so screens, exports and imports agree.
String formatMoney(num? value) {
  if (value == null) return '—';
  return _moneyFormat.format(value);
}

/// Formats a quantity with thousands separators and up to three decimals.
String formatQuantity(num? value) {
  if (value == null) return '—';
  return _quantityFormat.format(value);
}

/// Plain machine-readable number text (no grouping) used when editing values.
String editableNumber(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  var text = value.toStringAsFixed(6);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  return text.endsWith('.') ? text.substring(0, text.length - 1) : text;
}

String toIsoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String formatDate(String? isoDate, [String locale = 'ar']) {
  if (isoDate == null || isoDate.isEmpty) return locale == 'ar' ? 'غير مسجل' : 'Not recorded';
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  return DateFormat('dd/MM/yyyy', 'en').format(parsed);
}

String formatDateTime(String? isoDateTime, [String locale = 'ar']) {
  if (isoDateTime == null || isoDateTime.isEmpty) return locale == 'ar' ? 'غير مسجل' : 'Not recorded';
  final parsed = DateTime.tryParse(isoDateTime);
  if (parsed == null) return isoDateTime;
  return DateFormat('dd/MM/yyyy - HH:mm', 'en').format(parsed.toLocal());
}

/// Wraps left-to-right content (codes, invoice numbers, file names) in Unicode
/// directional isolates so it is not reordered inside Arabic sentences.
String ltrIsolate(String value) => '\u2066$value\u2069';

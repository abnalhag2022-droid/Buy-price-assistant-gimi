import 'package:flutter_test/flutter_test.dart';
import 'package:buy_price_assistant_gimi/utils/app_helpers.dart';

void main() {
  group('normalizeForSearch', () {
    test('normalizes Arabic, Persian, and English digits identically', () {
      expect(normalizeForSearch('غطاس ٥٥'), 'غطاس 55');
      expect(normalizeForSearch('غطاس ۵۵'), 'غطاس 55');
      expect(normalizeForSearch('غطاس 55'), 'غطاس 55');
    });

    test('removes Arabic diacritics and normalizes common alef forms', () {
      expect(normalizeForSearch('إِضَاءَة'), 'اضاءة');
      expect(normalizeForSearch('مُحَوِّل'), 'محول');
    });

    test('does not silently merge taa marbuta and haa', () {
      expect(normalizeForSearch('مروحة'), isNot(normalizeForSearch('مروحه')));
    });
  });

  group('parseLocalizedNumber', () {
    test('parses Latin and Arabic-Indic digits', () {
      expect(parseLocalizedNumber('123.50'), 123.5);
      expect(parseLocalizedNumber('١٢٣٫٥٠'), 123.5);
      expect(parseLocalizedNumber('۱۲۳٫۵۰'), 123.5);
    });

    test('rejects empty, invalid, and non-finite input', () {
      expect(parseLocalizedNumber(''), isNull);
      expect(parseLocalizedNumber('abc'), isNull);
      expect(parseLocalizedNumber('NaN'), isNull);
      expect(parseLocalizedNumber('Infinity'), isNull);
    });

    test('handles comma decimal and thousand separators', () {
      expect(parseLocalizedNumber('12,50'), 12.5);
      expect(parseLocalizedNumber('1,250'), 1250);
      expect(parseLocalizedNumber('1,250.50'), 1250.5);
      expect(parseLocalizedNumber('1,2,50'), isNull);
    });
  });

  test('formats money without unnecessary trailing zeros', () {
    expect(formatMoney(120), '120');
    expect(formatMoney(12.5), '12.5');
    expect(formatMoney(12.25), '12.25');
    expect(formatMoney(null), '—');
  });

  test('escapes SQL LIKE wildcard characters', () {
    expect(escapeLikePattern('50%_!'), '50!%!_!!');
  });
}

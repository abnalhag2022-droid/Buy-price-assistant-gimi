import 'package:flutter_test/flutter_test.dart';
import 'package:buy_price_assistant_gimi/data/backup_format.dart';

void main() {
  final snapshot = <String, Object?>{
    'products': <Map<String, Object?>>[
      <String, Object?>{'id': 1, 'name': 'صنف تجريبي'},
    ],
    'purchase_entries': <Map<String, Object?>>[
      <String, Object?>{'id': 1, 'product_id': 1, 'unit_price': 10.5},
    ],
    'sale_entries': <Map<String, Object?>>[],
  };

  test('encodes and decodes a versioned archive', () {
    final createdAt = DateTime.utc(2026, 10, 13, 1, 30);
    final encoded = BackupFormat.encode(
      database: snapshot,
      createdAt: createdAt,
    );
    final decoded = BackupFormat.decode(encoded);

    expect(decoded['format'], BackupFormat.formatName);
    expect(decoded['format_version'], BackupFormat.currentVersion);
    expect(decoded['created_at'], createdAt.toIso8601String());
    expect(decoded['database'], snapshot);
  });

  test('rejects malformed JSON', () {
    expect(() => BackupFormat.decode('{not-json'), throwsFormatException);
  });

  test('rejects an unrelated JSON document', () {
    expect(
      () => BackupFormat.decode('{"hello":"world"}'),
      throwsFormatException,
    );
  });

  test('rejects an unsupported archive version', () {
    final encoded = BackupFormat.encode(database: snapshot);
    final changed = encoded.replaceFirst(
      '"format_version": 1',
      '"format_version": 999',
    );
    expect(() => BackupFormat.decode(changed), throwsFormatException);
  });

  test('rejects archives with missing database tables', () {
    expect(
      () => BackupFormat.encode(database: <String, Object?>{
        'products': <Object?>[],
        'purchase_entries': <Object?>[],
      }),
      throwsFormatException,
    );
  });

  test('rejects invalid rows', () {
    expect(
      () => BackupFormat.encode(database: <String, Object?>{
        'products': <Object?>['not a row'],
        'purchase_entries': <Object?>[],
        'sale_entries': <Object?>[],
      }),
      throwsFormatException,
    );
  });
}

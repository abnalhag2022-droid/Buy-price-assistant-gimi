import 'dart:convert';

/// Versioned JSON envelope for application backups.
/// File I/O and database restoration are handled separately.
class BackupFormat {
  BackupFormat._();

  static const String formatName =
      'buy_price_assistant_gimi_backup';
  static const int currentVersion = 1;

  static const List<String> requiredTables = <String>[
    'products',
    'purchase_entries',
    'sale_entries',
  ];

  static String encode({
    required Map<String, Object?> database,
    DateTime? createdAt,
  }) {
    _validateDatabase(database);
    final archive = <String, Object?>{
      'format': formatName,
      'format_version': currentVersion,
      'created_at': (createdAt ?? DateTime.now())
          .toUtc()
          .toIso8601String(),
      'database': database,
    };
    return const JsonEncoder.withIndent('  ').convert(archive);
  }

  /// Validates an archive without modifying the database or files.
  static Map<String, Object?> decode(String contents) {
    final Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('ملف النسخة الاحتياطية غير صالح: $error');
    }

    if (decoded is! Map) {
      throw const FormatException(
        'محتوى النسخة الاحتياطية يجب أن يكون كائن JSON.',
      );
    }

    final archive = _stringKeyedMap(decoded, 'archive');
    if (archive['format'] != formatName) {
      throw const FormatException(
        'الملف ليس نسخة احتياطية معروفة من التطبيق.',
      );
    }

    final version = archive['format_version'];
    if (version != currentVersion) {
      throw FormatException('إصدار النسخة غير مدعوم: $version');
    }

    final createdAt = archive['created_at'];
    if (createdAt is! String || DateTime.tryParse(createdAt) == null) {
      throw const FormatException(
        'تاريخ إنشاء النسخة مفقود أو غير صالح.',
      );
    }

    final rawDatabase = archive['database'];
    if (rawDatabase is! Map) {
      throw const FormatException(
        'بيانات قاعدة البيانات مفقودة من النسخة.',
      );
    }

    final database = _stringKeyedMap(rawDatabase, 'database');
    _validateDatabase(database);
    return archive;
  }

  static void _validateDatabase(Map<String, Object?> database) {
    for (final table in requiredTables) {
      final rows = database[table];
      if (rows is! List) {
        throw FormatException(
          'بيانات الجدول "$table" مفقودة أو غير صالحة.',
        );
      }
      for (var index = 0; index < rows.length; index++) {
        if (rows[index] is! Map) {
          throw FormatException(
            'السجل رقم ${index + 1} في الجدول "$table" غير صالح.',
          );
        }
        _stringKeyedMap(rows[index] as Map, '$table row');
      }
    }
  }

  static Map<String, Object?> _stringKeyedMap(
    Map value,
    String label,
  ) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw FormatException('يوجد مفتاح غير نصي في $label.');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import '../state/app_settings.dart';
import 'app_database.dart';
import 'backup_validator.dart';

/// A JSON backup the app saved automatically before a risky operation.
class SafetySnapshot {
  const SafetySnapshot({required this.file, required this.createdAt, required this.reason, required this.sizeBytes});
  final File file;
  final DateTime createdAt;

  /// 'before_restore', 'before_import' or 'manual'.
  final String reason;
  final int sizeBytes;
  String get fileName => p.basename(file.path);
}

/// Summary shown to the user before a restore replaces their data.
class BackupSummary {
  const BackupSummary({
    required this.schemaVersion, required this.createdAt, required this.products,
    required this.purchases, required this.sales, required this.hasSettings, required this.checksumVerified,
  });
  final int schemaVersion;
  final String? createdAt;
  final int products, purchases, sales;
  final bool hasSettings, checksumVerified;
}

class RestoreOutcome {
  const RestoreOutcome({required this.safetySnapshot, required this.summary});

  /// The automatic copy of the data that was replaced.
  final SafetySnapshot safetySnapshot;
  final BackupSummary summary;
}

/// Full backups (database + settings), restore with automatic safety copies,
/// and the list of safety snapshots kept in the app's private storage.
class BackupService {
  BackupService({AppDatabase? database, AppSettings? settings, Future<String> Function()? directoryProvider})
      : _databaseOverride = database,
        _settingsOverride = settings,
        _directoryProvider = directoryProvider ?? sqflite.getDatabasesPath;

  static final BackupService instance = BackupService();

  /// Number of automatic safety snapshots kept; older ones are deleted.
  static const int keepSnapshots = 5;

  final AppDatabase? _databaseOverride;
  final AppSettings? _settingsOverride;
  final Future<String> Function() _directoryProvider;

  AppDatabase get _db => _databaseOverride ?? AppDatabase.instance;
  AppSettings get _settings => _settingsOverride ?? AppSettings.instance;

  /// Database backup (with checksum) plus the current settings.
  Future<String> buildFullBackup() async {
    final archive = Map<String, Object?>.from(jsonDecode(await _db.exportBackupJson()) as Map);
    archive['settings'] = _settings.exportSettings();
    return const JsonEncoder.withIndent('  ').convert(archive);
  }

  /// Validates a backup without changing anything and describes its content.
  BackupSummary inspect(String content) {
    final contents = BackupValidator.parse(content);
    if (contents.settings != null) AppSettings.validateBackupSettings(contents.settings);
    final decoded = jsonDecode(content) as Map;
    return BackupSummary(
      schemaVersion: contents.schemaVersion,
      createdAt: decoded['createdAt'] as String?,
      products: contents.products.length,
      purchases: contents.purchases.length,
      sales: contents.sales.length,
      hasSettings: contents.settings != null,
      checksumVerified: contents.checksumVerified,
    );
  }

  /// Replaces all data with [content]. Order of operations:
  /// 1. validate the whole file (nothing changes if it is invalid);
  /// 2. save a safety snapshot of the current data and settings;
  /// 3. apply settings, then the database in one transaction;
  /// 4. if the database step fails, put the previous settings back.
  Future<RestoreOutcome> restoreFullBackup(String content) async {
    final summary = inspect(content);
    final contents = BackupValidator.parse(content);
    final snapshot = await createSafetySnapshot('before_restore');
    final newSettings = contents.settings == null ? null : AppSettings.validateBackupSettings(contents.settings);
    final previousSettings = _settings.exportSettings();
    if (newSettings != null) await _settings.restoreSettings(newSettings);
    try {
      await _db.restoreBackupJson(content);
    } catch (error) {
      if (newSettings != null) {
        try {
          await _settings.restoreSettings(previousSettings);
        } catch (rollbackError) {
          throw StateError('فشلت استعادة قاعدة البيانات، وتعذر التراجع عن الإعدادات. نسخة الأمان محفوظة باسم ${snapshot.fileName}.');
        }
      }
      rethrow;
    }
    return RestoreOutcome(safetySnapshot: snapshot, summary: summary);
  }

  Future<Directory> _snapshotDirectory() async {
    final dir = Directory(p.join(await _directoryProvider(), 'safety_backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Writes the current data and settings to a new snapshot and keeps only
  /// the newest [keepSnapshots] files.
  Future<SafetySnapshot> createSafetySnapshot(String reason) async {
    final dir = await _snapshotDirectory();
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}'
        '_${now.millisecond.toString().padLeft(3, '0')}';
    final safeReason = reason.replaceAll(RegExp(r'[^a-z_]'), '');
    final file = File(p.join(dir.path, 'safety_${stamp}_$safeReason.json'));
    final content = await buildFullBackup();
    // Write to a temporary name first so a crash never leaves a partial snapshot.
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(content, flush: true);
    await temp.rename(file.path);
    final snapshots = await listSnapshots();
    for (final old in snapshots.skip(keepSnapshots)) {
      await old.file.delete();
    }
    return snapshots.firstWhere((s) => s.file.path == file.path);
  }

  /// Newest first.
  Future<List<SafetySnapshot>> listSnapshots() async {
    final dir = await _snapshotDirectory();
    final result = <SafetySnapshot>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final match = RegExp(r'^safety_(\d{8})_(\d{6})_(\d{3})_([a-z_]+)\.json$').firstMatch(p.basename(entity.path));
      if (match == null) continue;
      final d = match[1]!;
      final t = match[2]!;
      final created = DateTime(
        int.parse(d.substring(0, 4)), int.parse(d.substring(4, 6)), int.parse(d.substring(6, 8)),
        int.parse(t.substring(0, 2)), int.parse(t.substring(2, 4)), int.parse(t.substring(4, 6)), int.parse(match[3]!),
      );
      result.add(SafetySnapshot(file: entity, createdAt: created, reason: match[4]!, sizeBytes: await entity.length()));
    }
    result.sort((a, b) => b.fileName.compareTo(a.fileName));
    return result;
  }

  Future<String> readSnapshot(SafetySnapshot snapshot) => snapshot.file.readAsString();
}

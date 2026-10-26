import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../state/app_settings.dart';
import '../utils/app_text.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _busy = false;

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _exportBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final databaseJson = await AppDatabase.instance.exportBackupJson();
      final archive = Map<String, Object?>.from(jsonDecode(databaseJson) as Map);
      archive['settings'] = AppSettings.instance.exportSettings();
      final json = const JsonEncoder.withIndent('  ').convert(archive);
      final now = DateTime.now();
      final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final output = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ النسخة الاحتياطية',
        fileName: 'gimi_backup_$stamp.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Uint8List.fromList(utf8.encode(json)),
      );
      if (output != null) _message(appTextValue('تم إنشاء ملف النسخة الاحتياطية بنجاح.', 'Backup file created successfully.'));
    } catch (error) {
      _message('${appTextValue('تعذر إنشاء النسخة الاحتياطية', 'Could not create backup')}: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmRestore() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const AppText(ar: 'تأكيد استعادة البيانات', en: 'Confirm data restore'),
            content: const AppText(
              ar: 'ستُستبدل بيانات الأصناف وسجلات الشراء والبيع الحالية بمحتويات الملف. أنشئ نسخة احتياطية من بياناتك الحالية أولاً.',
              en: 'Current items and purchase/sale history will be replaced by the selected file. Create a backup of your current data first.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const AppText(ar: 'إلغاء', en: 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const AppText(ar: 'متابعة', en: 'Continue'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _restoreBackup() async {
    if (_busy) return;
    if (!await _confirmRestore() || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final Uint8List bytes;
      if (file.bytes != null) {
        bytes = file.bytes!;
      } else if (file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      } else {
        throw const FormatException('تعذر قراءة الملف المختار.');
      }
      final content = utf8.decode(bytes, allowMalformed: false);
      final decoded = jsonDecode(content);
      Map<String, Object?>? restoredSettings;
      if (decoded is Map && decoded['settings'] != null) {
        restoredSettings = AppSettings.validateBackupSettings(decoded['settings']);
      }
      // Stage settings first. If the database restore fails, roll the settings
      // back so the two parts of a backup do not intentionally diverge.
      final previousSettings = restoredSettings == null
          ? null
          : AppSettings.instance.exportSettings();
      if (restoredSettings != null) {
        await AppSettings.instance.restoreSettings(restoredSettings);
      }
      try {
        await AppDatabase.instance.restoreBackupJson(content);
      } catch (restoreError) {
        if (previousSettings != null) {
          try {
            await AppSettings.instance.restoreSettings(previousSettings);
          } catch (rollbackError) {
            throw StateError(
              'فشلت استعادة قاعدة البيانات ($restoreError)، كما تعذر التراجع عن الإعدادات ($rollbackError).',
            );
          }
        }
        rethrow;
      }
      _message(appTextValue('تمت استعادة البيانات بنجاح.', 'Data restored successfully.'));
    } catch (error) {
      _message('${appTextValue('لم تتم الاستعادة؛ لم تُعتمد بيانات الملف.', 'Restore failed; file data was not applied.')}: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppText(ar: 'النسخ الاحتياطي والاستعادة', en: 'Backup and restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined, size: 34),
                  const SizedBox(height: 12),
                  const AppText(ar: 'حافظ على بياناتك', en: 'Protect your data', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  const AppText(
                    ar: 'تتضمن النسخة الاحتياطية الأصناف النشطة والمؤرشفة وسجلات الشراء والبيع والأسعار والكميات والتواريخ والموردين والعملاء والملاحظات، إضافة إلى إعدادات اللغة والمظهر والعملة والتصنيفات والوحدات.',
                    en: 'The backup contains active and archived items, purchase/sale history, prices, quantities, dates, suppliers, customers, notes, and your language, theme, currency, category, and unit settings.',
                    style: TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _exportBackup,
                    icon: const Icon(Icons.save_alt),
                    label: const AppText(ar: 'إنشاء نسخة احتياطية', en: 'Create backup'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.restore, size: 34),
                  const SizedBox(height: 12),
                  const AppText(ar: 'استعادة من ملف', en: 'Restore from file', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  const AppText(
                    ar: 'اختر ملفًا أنشأه التطبيق. تُفحص بنيته أولًا ثم تُستعاد البيانات داخل معاملة واحدة. تقبل الاستعادة النسخ القديمة، وتُلغى العملية إذا فشل فحص البيانات.',
                    en: 'Choose a backup file created by this app. Its structure is checked first, then restored in one database transaction. Older backups remain supported, and invalid data is rejected.',
                    style: TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _restoreBackup,
                    icon: const Icon(Icons.folder_open),
                    label: const AppText(ar: 'اختيار ملف للاستعادة', en: 'Choose backup file'),
                  ),
                ],
              ),
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 8),
            const Center(child: AppText(ar: 'يرجى الانتظار...', en: 'Please wait...')),
          ],
          const SizedBox(height: 12),
          const Text(
            'تنبيه: الاستعادة تستبدل بيانات الأصناف والأسعار الحالية. احتفظ بنسخة احتياطية قبل الاستعادة.',
            style: TextStyle(color: Colors.redAccent, height: 1.5),
          ),
        ],
      ),
    );
  }
}

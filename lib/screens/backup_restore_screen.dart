import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/backup_service.dart';
import '../utils/app_helpers.dart';
import '../utils/app_text.dart';
import '../utils/error_messages.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key, this.service});
  final BackupService? service;

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _busy = false;
  late Future<List<SafetySnapshot>> _snapshots;

  BackupService get _service => widget.service ?? BackupService.instance;

  @override
  void initState() {
    super.initState();
    _snapshots = _service.listSnapshots();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _stamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
  }

  Future<void> _exportBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final json = await _service.buildFullBackup();
      final output = await FilePicker.platform.saveFile(
        dialogTitle: appTextValue('حفظ النسخة الاحتياطية', 'Save backup'),
        fileName: 'hji_backup_${_stamp()}.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Uint8List.fromList(utf8.encode(json)),
      );
      if (output != null) {
        _message(appTextValue(
          'تم إنشاء النسخة الاحتياطية. تحتوي كل أسعارك وأسماء الموردين والعملاء؛ احفظها خارج الهاتف في مكان آمن.',
          'Backup created. It contains all prices and supplier/customer names; keep it off the phone somewhere safe.',
        ));
      }
    } catch (error) {
      _message('${appTextValue('تعذر إنشاء النسخة الاحتياطية', 'Could not create backup')}: ${friendlyError(error)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreFromFile() async {
    if (_busy) return;
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
      final String content;
      try {
        content = utf8.decode(bytes);
      } on FormatException {
        throw const FormatException('الملف ليس نسخة احتياطية نصية بترميز UTF-8.');
      }
      await _confirmAndRestore(content, ltrIsolate(file.name));
    } catch (error) {
      _message('${appTextValue('لم تتم الاستعادة؛ بياناتك الحالية لم تتغير', 'Restore failed; your current data is unchanged')}: ${friendlyError(error)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreSnapshot(SafetySnapshot snapshot) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _confirmAndRestore(await _service.readSnapshot(snapshot), _snapshotTitle(snapshot));
    } catch (error) {
      _message('${appTextValue('لم تتم الاستعادة؛ بياناتك الحالية لم تتغير', 'Restore failed; your current data is unchanged')}: ${friendlyError(error)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmAndRestore(String content, String sourceLabel) async {
    // Validation happens before any confirmation; an invalid file never gets this far.
    final summary = _service.inspect(content);
    if (!mounted) return;
    final created = summary.createdAt == null
        ? appTextValue('غير معروف', 'unknown')
        : formatDateTime(summary.createdAt, Localizations.localeOf(context).languageCode);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: AppText(ar: 'استبدال جميع البيانات؟', en: 'Replace all data?'),
        content: SingleChildScrollView(
          child: Text(appTextValue(
            'الملف: $sourceLabel\nأُنشئ: $created\nيحتوي: ${summary.products} صنف، ${summary.purchases} عملية شراء، ${summary.sales} عملية بيع${summary.hasSettings ? '، والإعدادات' : ''}.\n\n'
                'ستُستبدل كل بياناتك الحالية بمحتوى الملف. ستُحفظ نسخة أمان تلقائية من بياناتك الحالية أولًا ويمكنك استعادتها من هذه الشاشة.',
            'File: $sourceLabel\nCreated: $created\nContains: ${summary.products} products, ${summary.purchases} purchases, ${summary.sales} sales${summary.hasSettings ? ', and settings' : ''}.\n\n'
                'All current data will be replaced. An automatic safety copy of your current data is saved first and can be restored from this screen.',
          )),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: AppText(ar: 'إلغاء', en: 'Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialog).colorScheme.error),
            onPressed: () => Navigator.pop(dialog, true),
            child: AppText(ar: 'استبدال البيانات', en: 'Replace data'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final outcome = await _service.restoreFullBackup(content);
    if (!mounted) return;
    setState(() => _snapshots = _service.listSnapshots());
    _message(appTextValue(
      'تمت الاستعادة. حُفظت بياناتك السابقة في نسخة أمان (${_snapshotTitle(outcome.safetySnapshot)}).',
      'Restored. Your previous data was saved as a safety copy (${_snapshotTitle(outcome.safetySnapshot)}).',
    ));
  }

  Future<void> _saveSnapshotCopy(SafetySnapshot snapshot) async {
    try {
      final output = await FilePicker.platform.saveFile(
        dialogTitle: appTextValue('حفظ نسخة الأمان', 'Save safety copy'),
        fileName: snapshot.fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: await snapshot.file.readAsBytes(),
      );
      if (output != null) _message(appTextValue('تم حفظ نسخة الأمان.', 'Safety copy saved.'));
    } catch (error) {
      _message(friendlyError(error));
    }
  }

  String _snapshotTitle(SafetySnapshot s) {
    final reason = switch (s.reason) {
      'before_restore' => appTextValue('قبل الاستعادة', 'before restore'),
      'before_import' => appTextValue('قبل الاستيراد', 'before import'),
      _ => appTextValue('يدوية', 'manual'),
    };
    return '${formatDateTime(s.createdAt.toIso8601String(), Localizations.localeOf(context).languageCode)} · $reason';
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
                  const AppText(ar: 'إنشاء نسخة احتياطية', en: 'Create a backup', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  const AppText(
                    ar: 'ملف JSON يحتوي كل الأصناف النشطة والمؤرشفة وسجلات الشراء والبيع وسجل الاستيراد والإعدادات، مع بصمة تحقق تكشف أي تلف. الملف غير مشفّر؛ احفظه في مكان آمن خارج الهاتف.',
                    en: 'A JSON file with all active and archived products, purchase and sale records, import history and settings, with a checksum that detects damage. The file is not encrypted; keep it somewhere safe off the phone.',
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
                  const AppText(ar: 'استعادة من ملف', en: 'Restore from a file', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  const AppText(
                    ar: 'يُفحص الملف كاملًا ويُعرض ملخصه قبل التأكيد. الاستعادة تستبدل كل البيانات الحالية، وتُحفظ نسخة أمان تلقائية قبلها. تُقبل النسخ من الإصدارات السابقة.',
                    en: 'The whole file is checked and summarised before you confirm. Restoring replaces all current data, and an automatic safety copy is saved first. Backups from earlier versions are accepted.',
                    style: TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _restoreFromFile,
                    icon: const Icon(Icons.folder_open),
                    label: const AppText(ar: 'اختيار ملف للاستعادة', en: 'Choose backup file'),
                  ),
                ],
              ),
            ),
          ),
          if (_busy) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
          const SizedBox(height: 12),
          FutureBuilder<List<SafetySnapshot>>(
            future: _snapshots,
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <SafetySnapshot>[];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const AppText(ar: 'نسخ الأمان التلقائية', en: 'Automatic safety copies', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    AppText(
                      ar: 'تُحفظ تلقائيًا قبل كل استعادة أو استيراد، ويُحتفظ بآخر ${BackupService.keepSnapshots} نسخ داخل التطبيق فقط. تُحذف إذا حُذف التطبيق، لذا لا تغني عن نسختك الاحتياطية.',
                      en: 'Saved automatically before every restore or import; the last ${BackupService.keepSnapshots} are kept inside the app only. They are removed if the app is uninstalled, so keep your own backup too.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: AppText(ar: 'لا توجد نسخ أمان بعد.', en: 'No safety copies yet.', style: Theme.of(context).textTheme.bodyMedium),
                      ),
                    for (final s in items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history_toggle_off),
                        title: Text(_snapshotTitle(s)),
                        subtitle: Text('${(s.sizeBytes / 1024).toStringAsFixed(1)} KB'),
                        trailing: PopupMenuButton<String>(
                          tooltip: appTextValue('إجراءات', 'Actions'),
                          onSelected: (value) {
                            if (value == 'restore') _restoreSnapshot(s);
                            if (value == 'save') _saveSnapshotCopy(s);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'restore', child: AppText(ar: 'استعادة هذه النسخة', en: 'Restore this copy')),
                            PopupMenuItem(value: 'save', child: AppText(ar: 'حفظ نسخة منها في ملف', en: 'Save a copy to a file')),
                          ],
                        ),
                      ),
                  ]),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          AppText(
            ar: 'نسخ Android التلقائي: قد يحفظ Android بيانات التطبيق ضمن نسخ حسابك في Google إذا كان مفعّلًا على الهاتف، ويستعيدها عند نقلها إلى هاتف جديد.',
            en: 'Android auto backup: if enabled on the phone, Android may include this app\'s data in your Google account backup and restore it on a new phone.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

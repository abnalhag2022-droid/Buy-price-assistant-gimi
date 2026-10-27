import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/backup_service.dart';
import '../data/file_access.dart';
import '../ui/ui.dart';
import '../utils/app_helpers.dart';
import '../utils/app_text.dart';
import '../utils/error_messages.dart';
import '../utils/localized_message.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key, this.service});
  final BackupService? service;

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _busy = false;
  List<SafetySnapshot> _snapshots = const <SafetySnapshot>[];
  Object? _snapshotsError;

  BackupService get _service => widget.service ?? BackupService.instance;

  @override
  void initState() {
    super.initState();
    _loadSnapshots();
  }

  Future<void> _loadSnapshots() async {
    try {
      final snapshots = await _service.listSnapshots();
      if (!mounted) return;
      setState(() {
        _snapshots = snapshots;
        _snapshotsError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _snapshotsError = error);
    }
  }

  /// Backups larger than this are refused before being read into memory.
  static const int _maxBackupBytes = 200 * 1024 * 1024;

  void _message(String text) {
    if (mounted) showMessage(context, text);
  }

  Future<void> _exportBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final json = await _service.buildFullBackup();
      final saved = await FileAccess.instance.saveFile(
        dialogTitle: appTextValue('حفظ النسخة الاحتياطية', 'Save backup'),
        fileName: 'hji_backup_${fileStamp()}.json',
        extension: 'json',
        bytes: Uint8List.fromList(utf8.encode(json)),
      );
      if (saved) {
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
      final file = await FileAccess.instance.pickFile(
        dialogTitle: appTextValue('اختر ملف النسخة الاحتياطية', 'Choose a backup file'),
        extensions: const ['json'],
        maxBytes: _maxBackupBytes,
      );
      if (file == null) return;
      final bytes = file.bytes;
      final String content;
      try {
        content = utf8.decode(bytes);
      } on FormatException {
        throw const LocalizedFormatException('الملف ليس نسخة احتياطية نصية بترميز UTF-8.', 'The file is not a UTF-8 text backup.');
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
    final confirmed = await showConfirmDialog(
      context,
      title: appTextValue('استبدال جميع البيانات؟', 'Replace all data?'),
      message: appTextValue(
        'الملف: $sourceLabel\nأُنشئ: $created\nالأصناف: ${summary.products}\nعمليات الشراء: ${summary.purchases}\nعمليات البيع: ${summary.sales}${summary.hasSettings ? '\nيشمل الإعدادات' : ''}\n\n'
            'ستُستبدل كل بياناتك الحالية بمحتوى الملف. تُحفظ نسخة أمان تلقائية من بياناتك الحالية أولًا ويمكنك استعادتها من هذه الشاشة.',
        'File: $sourceLabel\nCreated: $created\nItems: ${summary.products}\nPurchases: ${summary.purchases}\nSales: ${summary.sales}${summary.hasSettings ? '\nIncludes settings' : ''}\n\n'
            'All current data will be replaced. An automatic safety copy of your current data is saved first and can be restored from this screen.',
      ),
      confirmLabel: appTextValue('استبدال البيانات', 'Replace data'),
      destructive: true,
    );
    if (!confirmed) return;
    final outcome = await _service.restoreFullBackup(content);
    if (!mounted) return;
    await _loadSnapshots();
    _message(appTextValue(
      'تمت الاستعادة. حُفظت بياناتك السابقة في نسخة أمان (${_snapshotTitle(outcome.safetySnapshot)}).',
      'Restored. Your previous data was saved as a safety copy (${_snapshotTitle(outcome.safetySnapshot)}).',
    ));
  }

  Future<void> _saveSnapshotCopy(SafetySnapshot snapshot) async {
    try {
      final saved = await FileAccess.instance.saveFile(
        dialogTitle: appTextValue('حفظ نسخة الأمان', 'Save safety copy'),
        fileName: snapshot.fileName,
        extension: 'json',
        bytes: await snapshot.file.readAsBytes(),
      );
      if (saved) _message(appTextValue('تم حفظ نسخة الأمان.', 'Safety copy saved.'));
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
      appBar: AppBar(title: Text(appTextValue('النسخ الاحتياطي والاستعادة', 'Backup and restore'))),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.all(Space.lg),
          children: [
            if (_busy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: Space.md),
            ],
            SectionCard(
              title: appTextValue('إنشاء نسخة احتياطية', 'Create a backup'),
              icon: Icons.save_alt,
              children: [
                Text(appTextValue(
                  'ملف JSON بكل الأصناف النشطة والمؤرشفة وسجلات الشراء والبيع وسجل الاستيراد والإعدادات، مع بصمة تحقق تكشف أي تلف.',
                  'A JSON file with all active and archived items, purchase and sale records, import history and settings, with a checksum that detects damage.',
                )),
                NoticeBanner(
                  kind: NoticeKind.warning,
                  text: appTextValue(
                    'الملف غير مشفّر ويحتوي أسعارك وأسماء الموردين والعملاء. احفظه خارج الهاتف في مكان آمن.',
                    'The file is not encrypted and contains your prices and supplier/customer names. Keep it somewhere safe off the phone.',
                  ),
                ),
                const SizedBox(height: Space.lg),
                FilledButton.icon(
                  onPressed: _busy ? null : _exportBackup,
                  icon: const Icon(Icons.save_alt),
                  label: Text(appTextValue('إنشاء نسخة احتياطية', 'Create backup')),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            SectionCard(
              title: appTextValue('الاستعادة من ملف', 'Restore from a file'),
              icon: Icons.settings_backup_restore,
              children: [
                Text(appTextValue(
                  'يُفحص الملف كاملًا ويُعرض ملخصه قبل التأكيد. الاستعادة تستبدل كل البيانات الحالية بعد حفظ نسخة أمان تلقائية. تُقبل نسخ الإصدارات السابقة.',
                  'The whole file is checked and summarised before you confirm. Restoring replaces all current data after an automatic safety copy is saved. Backups from earlier versions are accepted.',
                )),
                const SizedBox(height: Space.lg),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _restoreFromFile,
                  icon: const Icon(Icons.folder_open),
                  label: Text(appTextValue('اختيار ملف للاستعادة', 'Choose a backup file')),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            Builder(
              builder: (context) {
                final items = _snapshots;
                return SectionCard(
                  title: appTextValue('نسخ الأمان التلقائية', 'Automatic safety copies'),
                  icon: Icons.shield_outlined,
                  padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.sm),
                  subtitle: appTextValue(
                    'تُحفظ قبل كل استعادة أو استيراد، ويُحتفظ بآخر ${BackupService.keepSnapshots} نسخ داخل التطبيق. تُحذف بحذف التطبيق، فلا تغني عن نسختك الاحتياطية.',
                    'Saved before every restore or import; the last ${BackupService.keepSnapshots} are kept inside the app. They are deleted with the app, so keep your own backup too.',
                  ),
                  children: [
                    if (_snapshotsError != null)
                      NoticeBanner(kind: NoticeKind.error, text: friendlyError(_snapshotsError!))
                    else if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.sm),
                        child: Text(appTextValue('لا توجد نسخ أمان بعد.', 'No safety copies yet.'), style: context.text.bodySmall),
                      ),
                    for (final s in items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history_toggle_off),
                        title: Text(_snapshotTitle(s)),
                        subtitle: Text(ltrIsolate('${(s.sizeBytes / 1024).toStringAsFixed(1)} KB')),
                        trailing: PopupMenuButton<String>(
                          tooltip: appTextValue('إجراءات', 'Actions'),
                          onSelected: (value) {
                            if (value == 'restore') _restoreSnapshot(s);
                            if (value == 'save') _saveSnapshotCopy(s);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'restore', child: Text(appTextValue('استعادة هذه النسخة', 'Restore this copy'))),
                            PopupMenuItem(value: 'save', child: Text(appTextValue('حفظ نسخة منها في ملف', 'Save a copy to a file'))),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: Space.md),
            Text(
              appTextValue(
                'نسخ Android التلقائي: إذا كان مفعّلًا على الهاتف، قد يحفظ Android بيانات التطبيق ضمن نسخ حسابك في Google ويستعيدها على هاتف جديد.',
                "Android auto backup: if it is on for the phone, Android may include this app's data in your Google account backup and restore it on a new phone.",
              ),
              style: context.text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

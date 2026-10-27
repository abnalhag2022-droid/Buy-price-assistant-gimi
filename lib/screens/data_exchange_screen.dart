import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/file_access.dart';
import '../data/spreadsheet_exchange.dart';
import '../ui/ui.dart';
import '../utils/app_helpers.dart';
import '../utils/app_text.dart';
import '../utils/error_messages.dart';
import 'import_preview_screen.dart';

/// Spreadsheet export, import with preview, and undo of recent imports.
class DataExchangeScreen extends StatefulWidget {
  const DataExchangeScreen({super.key});

  @override
  State<DataExchangeScreen> createState() => _DataExchangeScreenState();
}

class _DataExchangeScreenState extends State<DataExchangeScreen> {
  bool _busy = false;
  String? _busyText;
  late Future<List<Map<String, Object?>>> _batches = AppDatabase.instance.listImportBatches(limit: 5);

  void _reloadBatches() => setState(() => _batches = AppDatabase.instance.listImportBatches(limit: 5));

  Future<void> _work(String text, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyText = text;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) showMessage(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export({required bool excel}) => _work(appTextValue('جارٍ تجهيز الملف…', 'Preparing the file…'), () async {
        final bytes = excel ? await SpreadsheetExchange.instance.exportXlsx() : await SpreadsheetExchange.instance.exportCsv();
        final extension = excel ? 'xlsx' : 'csv';
        final saved = await FileAccess.instance.saveFile(
          dialogTitle: appTextValue('حفظ ملف التصدير', 'Save the export'),
          fileName: 'hji_data_${fileStamp()}.$extension',
          bytes: bytes,
          extension: extension,
        );
        if (saved && mounted) {
          showMessage(context, appTextValue(
            'تم التصدير. الملف يحتوي أسعارًا وأسماء موردين وعملاء؛ احفظه في مكان آمن.',
            'Exported. The file contains prices and supplier/customer names; keep it somewhere safe.',
          ));
        }
      });

  Future<void> _import() async {
    SpreadsheetPreview? preview;
    await _work(appTextValue('جارٍ قراءة الملف وفحصه…', 'Reading and checking the file…'), () async {
      final file = await FileAccess.instance.pickFile(
        dialogTitle: appTextValue('اختر ملف XLSX أو CSV', 'Choose an XLSX or CSV file'),
        extensions: const ['xlsx', 'csv', 'xls'],
        maxBytes: SpreadsheetExchange.maxFileBytes,
      );
      if (file == null) return;
      preview = await SpreadsheetExchange.instance.previewBytes(file.bytes, file.name);
    });
    final ready = preview;
    if (ready == null || !mounted) return;
    final result = await Navigator.of(context).push<SpreadsheetImportResult>(
      MaterialPageRoute(builder: (_) => ImportPreviewScreen(preview: ready)),
    );
    if (result == null || !mounted) return;
    _reloadBatches();
    showMessage(context, appTextValue(
      'اكتمل الاستيراد: أصناف جديدة ${result.productsAdded}، وعمليات ${result.transactionsAdded}'
          '${result.duplicatesSkipped > 0 ? '، وتُخطّيت ${result.duplicatesSkipped} مكررة' : ''}.',
      'Import complete: ${result.productsAdded} new items, ${result.transactionsAdded} records'
          '${result.duplicatesSkipped > 0 ? ', ${result.duplicatesSkipped} duplicates skipped' : ''}.',
    ));
  }

  Future<void> _undo(Map<String, Object?> batch) async {
    final confirmed = await showConfirmDialog(
      context,
      title: appTextValue('التراجع عن هذا الاستيراد؟', 'Undo this import?'),
      message: appTextValue(
        'يُحذف ما أضافه هذا الاستيراد فقط: سجلات الأسعار التي أنشأها (حتى لو عدّلتها لاحقًا)، والأصناف التي أنشأها إن لم تُسجَّل لها عمليات أخرى، وتُعاد أرشفة ما ألغى أرشفته. لا تتأثر بقية البيانات.',
        'Only what this import added is removed: the price records it created (even if edited later), the items it created unless other records use them, and items it un-archived are archived again. Nothing else changes.',
      ),
      confirmLabel: appTextValue('تراجع', 'Undo'),
      destructive: true,
    );
    if (!confirmed) return;
    await _work(appTextValue('جارٍ التراجع…', 'Undoing…'), () async {
      final result = await AppDatabase.instance.undoImportBatch(batch['id']! as String);
      if (!mounted) return;
      _reloadBatches();
      showMessage(context, appTextValue(
        'تم التراجع: حُذفت ${result.entriesRemoved} عملية و${result.productsRemoved} صنف'
            '${result.productsKept > 0 ? '، وبقي ${result.productsKept} صنف لوجود سجلات أخرى عليه' : ''}.',
        'Undone: ${result.entriesRemoved} records and ${result.productsRemoved} items removed'
            '${result.productsKept > 0 ? '; ${result.productsKept} kept because other records use them' : ''}.',
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(appTextValue('استيراد وتصدير', 'Import and export'))),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.all(Space.lg),
          children: [
            if (_busy) ...[
              LinearProgressIndicator(semanticsLabel: _busyText),
              const SizedBox(height: Space.sm),
              Text(_busyText ?? '', style: context.text.bodySmall),
              const SizedBox(height: Space.md),
            ],
            SectionCard(
              title: appTextValue('استيراد من Excel أو CSV', 'Import from Excel or CSV'),
              icon: Icons.upload_file,
              children: [
                Text(appTextValue(
                  'يقبل XLSX وCSV بترميز UTF-8 بعناوين عربية أو إنجليزية. تُعرض معاينة كاملة قبل أي كتابة، وتُحفظ نسخة أمان قبل الاستيراد، ويمكن التراجع عنه لاحقًا.',
                  'Accepts XLSX and UTF-8 CSV with Arabic or English headers. A full preview comes before anything is written, a safety copy is saved first, and the import can be undone later.',
                )),
                NoticeBanner(
                  text: appTextValue(
                    'لا يُربط سطر بصنف موجود تلقائيًا إلا إذا تطابق الكود، أو الاسم بنفس ترتيب الكلمات والوحدة. «كابل 2 خط 4 ملم» و«كابل 4 خط 2 ملم» صنفان مختلفان، وأي تشابه آخر يُعرض عليك لتقرر.',
                    'A row is linked to an existing item automatically only by the same code, or the same name in the same word order and unit. "Cable 2 core 4 mm" and "Cable 4 core 2 mm" are different items; any other similarity is shown to you to decide.',
                  ),
                ),
                const SizedBox(height: Space.lg),
                FilledButton.icon(
                  onPressed: _busy ? null : _import,
                  icon: const Icon(Icons.file_open_outlined),
                  label: Text(appTextValue('اختيار ملف ومعاينته', 'Choose a file and preview')),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            SectionCard(
              title: appTextValue('تصدير كل البيانات', 'Export all data'),
              icon: Icons.download_outlined,
              children: [
                Text(appTextValue(
                  'يشمل الأصناف النشطة والمؤرشفة وكل سجلات الشراء والبيع. لحفظ نسخة كاملة تشمل الإعدادات وسجل الاستيراد، استخدم النسخ الاحتياطي.',
                  'Includes active and archived items and every purchase and sale record. For a complete copy with settings and import history, use Backup.',
                )),
                const SizedBox(height: Space.lg),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _export(excel: true),
                  icon: const Icon(Icons.table_view_outlined),
                  label: Text(appTextValue('تصدير Excel (XLSX)', 'Export Excel (XLSX)')),
                ),
                const SizedBox(height: Space.sm),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _export(excel: false),
                  icon: const Icon(Icons.description_outlined),
                  label: Text(appTextValue('تصدير CSV (UTF-8)', 'Export CSV (UTF-8)')),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            FutureBuilder<List<Map<String, Object?>>>(
              future: _batches,
              builder: (context, snapshot) {
                final batches = snapshot.data ?? const <Map<String, Object?>>[];
                return SectionCard(
                  title: appTextValue('آخر عمليات الاستيراد', 'Recent imports'),
                  icon: Icons.history,
                  padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.sm),
                  children: [
                    if (batches.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.sm),
                        child: Text(appTextValue('لا توجد عمليات استيراد بعد.', 'No imports yet.'), style: context.text.bodySmall),
                      ),
                    for (final b in batches)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(b['undone_at'] == null ? Icons.task_alt : Icons.undo),
                        title: Text(ltrIsolate(b['file_name'] as String? ?? '—'), maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${ltrIsolate(formatDateTime(b['created_at'] as String?, language))} · '
                          '${appTextValue('أصناف ${b['products_added']} · عمليات ${b['entries_added']}', '${b['products_added']} items · ${b['entries_added']} records')}'
                          '${b['undone_at'] != null ? ' · ${appTextValue('تم التراجع عنه', 'undone')}' : ''}',
                        ),
                        trailing: b['undone_at'] != null
                            ? null
                            : TextButton(onPressed: _busy ? null : () => _undo(b), child: Text(appTextValue('تراجع', 'Undo'))),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: Space.md),
            Text(
              appTextValue('ملفات XLS القديمة غير مدعومة؛ احفظها من Excel بصيغة XLSX أو CSV UTF-8. الحد الأقصى 20 ميغابايت و100,000 صف.',
                  'Old XLS files are not supported; save them from Excel as XLSX or CSV UTF-8. Limit: 20 MB and 100,000 rows.'),
              style: context.text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

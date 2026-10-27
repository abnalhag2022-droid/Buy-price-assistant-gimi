import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/spreadsheet_exchange.dart';
import '../utils/app_helpers.dart';
import '../utils/app_text.dart';
import '../utils/error_messages.dart';
import 'import_preview_screen.dart';

class DataExchangeScreen extends StatefulWidget {
  const DataExchangeScreen({super.key});
  @override
  State<DataExchangeScreen> createState() => _DataExchangeScreenState();
}

class _DataExchangeScreenState extends State<DataExchangeScreen> {
  bool _busy = false;
  late Future<List<Map<String, Object?>>> _batches;

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  void _loadBatches() {
    _batches = AppDatabase.instance.listImportBatches(limit: 5);
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _export({required bool excel}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = excel
          ? await SpreadsheetExchange.instance.exportXlsx()
          : await SpreadsheetExchange.instance.exportCsv();
      final now = DateTime.now();
      final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final extension = excel ? 'xlsx' : 'csv';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: appTextValue('حفظ ملف التصدير', 'Save export file'),
        fileName: 'hji_data_$stamp.$extension',
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: bytes,
      );
      if (path != null) {
        _message(appTextValue(
          'تم التصدير. الملف يحتوي أسعارًا وأسماء موردين وعملاء؛ احفظه في مكان آمن.',
          'Exported. The file contains prices and supplier/customer names; keep it somewhere safe.',
        ));
      }
    } catch (e) {
      _message('${appTextValue('تعذر التصدير', 'Export failed')}: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickImport() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: appTextValue('اختر ملف XLSX أو CSV', 'Choose XLSX or CSV'),
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv', 'xls'],
        withData: true,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final Uint8List? bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        _message(appTextValue('تعذر قراءة محتوى الملف.', 'Could not read the selected file.'));
        return;
      }
      final preview = await SpreadsheetExchange.instance.previewBytes(bytes, file.name);
      if (!mounted) return;
      setState(() => _busy = false);
      final imported = await Navigator.of(context).push<SpreadsheetImportResult>(
        MaterialPageRoute(builder: (_) => ImportPreviewScreen(preview: preview)),
      );
      if (imported == null || !mounted) return;
      setState(_loadBatches);
      _message(appTextValue(
        'اكتمل الاستيراد: ${imported.productsAdded} صنف جديد و${imported.transactionsAdded} عملية'
            '${imported.duplicatesSkipped > 0 ? '، وتُخطّي ${imported.duplicatesSkipped} مكرر' : ''}.',
        'Import complete: ${imported.productsAdded} new products and ${imported.transactionsAdded} entries'
            '${imported.duplicatesSkipped > 0 ? ', ${imported.duplicatesSkipped} duplicates skipped' : ''}.',
      ));
    } catch (e) {
      _message('${appTextValue('تعذر قراءة الملف', 'Could not read the file')}: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo(Map<String, Object?> batch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: AppText(ar: 'التراجع عن الاستيراد', en: 'Undo import'),
        content: AppText(
          ar: 'سيُحذف كل ما أضافه هذا الاستيراد: سجلات الأسعار التي أنشأها (حتى لو عدّلتها لاحقًا)، والأصناف التي أنشأها إن لم تُسجَّل لها عمليات أخرى. لا تتأثر بقية البيانات.',
          en: 'Everything this import added is removed: the price records it created (even if you edited them later) and the products it created unless other records use them. Other data is not affected.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: AppText(ar: 'إلغاء', en: 'Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialog).colorScheme.error),
            onPressed: () => Navigator.pop(dialog, true),
            child: AppText(ar: 'تراجع', en: 'Undo'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final result = await AppDatabase.instance.undoImportBatch(batch['id']! as String);
      if (!mounted) return;
      setState(_loadBatches);
      _message(appTextValue(
        'تم التراجع: حُذف ${result.entriesRemoved} سجل و${result.productsRemoved} صنف${result.productsKept > 0 ? '، وبقي ${result.productsKept} صنف لوجود سجلات أخرى عليه' : ''}.',
        'Undone: ${result.entriesRemoved} records and ${result.productsRemoved} products removed${result.productsKept > 0 ? '; ${result.productsKept} kept because other records use them' : ''}.',
      ));
    } catch (e) {
      _message(friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText(ar: 'استيراد وتصدير البيانات', en: 'Import and export data')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const AppText(ar: 'تصدير كامل البيانات', en: 'Export all data', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const AppText(
            ar: 'يشمل الأصناف النشطة والمؤرشفة وجميع سجلات الشراء والبيع. ملف الجدول لا يحفظ الإعدادات ولا سجل الاستيراد؛ استخدم النسخ الاحتياطي لحفظ نسخة كاملة.',
            en: 'Includes active and archived products and every purchase/sale record. A spreadsheet does not keep settings or import history; use Backup for a complete copy.',
          ),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _busy ? null : () => _export(excel: true),
            icon: const Icon(Icons.table_view),
            label: const AppText(ar: 'تصدير Excel (.xlsx)', en: 'Export Excel (.xlsx)'),
          )),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: _busy ? null : () => _export(excel: false),
            icon: const Icon(Icons.description_outlined),
            label: const AppText(ar: 'تصدير CSV بترميز UTF-8', en: 'Export CSV UTF-8'),
          )),
        ]),
      )),
      const SizedBox(height: 12),
      Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const AppText(ar: 'استيراد سجل الأسعار', en: 'Import price history', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const AppText(
            ar: 'يدعم XLSX وCSV UTF-8 بعناوين عربية أو إنجليزية. تُعرض معاينة كاملة قبل أي كتابة: الأصناف الجديدة، والمطابقة بدقة، والملتبسة التي تحتاج إلى قرارك، والصفوف المرفوضة.',
            en: 'Supports XLSX and UTF-8 CSV with Arabic or English headers. A full preview comes first: new products, exact matches, ambiguous ones that need your decision, and rejected rows.',
          ),
          const SizedBox(height: 8),
          const AppText(
            ar: 'المطابقة التلقائية تتم فقط عند تطابق الاسم بالترتيب نفسه والوحدة، أو الكود. لا تتغير بيانات الصنف الموجود ولا يُحذف أي سجل.',
            en: 'Automatic matching only happens for the same name in the same word order and unit, or the same code. Existing product details are never changed and nothing is deleted.',
          ),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _busy ? null : _pickImport,
            icon: const Icon(Icons.upload_file),
            label: const AppText(ar: 'اختيار ملف ومعاينة البيانات', en: 'Choose file and preview'),
          )),
        ]),
      )),
      if (_busy) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      const SizedBox(height: 12),
      FutureBuilder<List<Map<String, Object?>>>(
        future: _batches,
        builder: (context, snapshot) {
          final batches = snapshot.data ?? const <Map<String, Object?>>[];
          if (batches.isEmpty) return const SizedBox.shrink();
          return Card(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const AppText(ar: 'آخر عمليات الاستيراد', en: 'Recent imports', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              for (final b in batches)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(ltrIsolate(b['file_name'] as String? ?? '—'), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${formatDateTime(b['created_at'] as String?, Localizations.localeOf(context).languageCode)} · '
                    '${appTextValue('أصناف', 'products')} ${b['products_added']} · ${appTextValue('عمليات', 'entries')} ${b['entries_added']}'
                    '${b['undone_at'] != null ? ' · ${appTextValue('تم التراجع', 'undone')}' : ''}',
                  ),
                  trailing: b['undone_at'] != null
                      ? null
                      : TextButton(onPressed: () => _undo(b), child: const AppText(ar: 'تراجع', en: 'Undo')),
                ),
            ]),
          ));
        },
      ),
      const SizedBox(height: 10),
      const AppText(
        ar: 'ملفات XLS القديمة غير مدعومة؛ احفظها بصيغة XLSX أو CSV UTF-8.',
        en: 'Legacy XLS files are not supported; save them as XLSX or UTF-8 CSV.',
      ),
    ]),
  );
}

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/spreadsheet_exchange.dart';
import '../utils/app_text.dart';

class DataExchangeScreen extends StatefulWidget {
  const DataExchangeScreen({super.key});
  @override
  State<DataExchangeScreen> createState() => _DataExchangeScreenState();
}

class _DataExchangeScreenState extends State<DataExchangeScreen> {
  bool _busy = false;

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
        fileName: 'gimi_data_$stamp.$extension',
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: bytes,
      );
      if (path != null) {
        _message(appTextValue('تم تصدير جميع الأصناف وسجلات الشراء والبيع التاريخية.', 'All products and purchase/sale history exported.'));
      }
    } catch (e) {
      _message(appTextValue('تعذر التصدير: ', 'Export failed: ') + e.toString());
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
      final approved = await _previewDialog(preview, file.name);
      if (approved != true || !mounted) return;
      var confirmedDuplicates = false;
      if (preview.duplicateCount > 0) {
        confirmedDuplicates = await _duplicateDialog(preview.duplicateCount) ?? false;
        if (!confirmedDuplicates || !mounted) return;
      }
      final imported = await SpreadsheetExchange.instance.importPreview(
        preview,
        confirmDuplicates: confirmedDuplicates,
      );
      _message(appTextValue(
        'اكتمل الاستيراد: ${imported.productsAdded} صنف جديد و${imported.transactionsAdded} عملية تاريخية.',
        'Import complete: ${imported.productsAdded} new products and ${imported.transactionsAdded} history entries.',
      ));
    } on SpreadsheetImportException catch (e) {
      _message(appTextValue('أُوقف الاستيراد لحماية البيانات: ', 'Import stopped to protect data: ') + e.message);
    } catch (e) {
      _message(appTextValue('تعذر الاستيراد: ', 'Import failed: ') + e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _previewDialog(SpreadsheetPreview preview, String filename) => showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialog) => AlertDialog(
      title: Text(appTextValue('معاينة الاستيراد', 'Import preview')),
      content: SizedBox(
        width: 560,
        height: 440,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(filename, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          _CountLine(ar: 'عمليات صحيحة', en: 'Valid transactions', value: preview.validTransactionCount),
          _CountLine(ar: 'أصناف مطابقة موجودة', en: 'Matched items', value: preview.matchedProducts),
          _CountLine(ar: 'أصناف جديدة', en: 'New items', value: preview.newProducts),
          _CountLine(ar: 'عمليات مكررة', en: 'Duplicate transactions', value: preview.duplicateCount),
          _CountLine(ar: 'أخطاء تمنع الاستيراد', en: 'Blocking errors', value: preview.errorCount),
          const Divider(),
          Text(appTextValue('الأخطاء والتنبيهات', 'Errors and warnings'), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Expanded(
            child: preview.issues.isEmpty
                ? Center(child: Text(appTextValue('لا توجد تنبيهات.', 'No warnings.')))
                : ListView.builder(
                    itemCount: preview.issues.length > 100 ? 100 : preview.issues.length,
                    itemBuilder: (context, index) {
                      final issue = preview.issues[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          '${issue.isError ? '✖ ' : '• '}${appTextValue('صف ', 'Row ')}${issue.row}: ${issue.message}',
                          style: TextStyle(color: issue.isError ? Theme.of(context).colorScheme.error : null, fontSize: 12),
                        ),
                      );
                    },
                  ),
          ),
          if (preview.issues.length > 100)
            Text(appTextValue('تُعرض أول 100 ملاحظة.', 'Showing the first 100 notices.'), style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: Text(appTextValue('إلغاء', 'Cancel'))),
        FilledButton(
          onPressed: preview.canImport ? () => Navigator.of(dialog).pop(true) : null,
          child: Text(appTextValue('متابعة', 'Continue')),
        ),
      ],
    ),
  );

  Future<bool?> _duplicateDialog(int count) => showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialog) => AlertDialog(
      title: Text(appTextValue('تأكيد العمليات المكررة', 'Confirm duplicate entries')),
      content: Text(appTextValue(
        'عُثر على $count عملية مكررة. الموافقة ستضيفها مرة أخرى دون حذف أي سجل. هل تريد المتابعة؟',
        '$count duplicate transaction(s) found. Continuing will add them again without deleting existing records. Continue?',
      )),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: Text(appTextValue('إلغاء', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: Text(appTextValue('تأكيد الإضافة', 'Confirm additions'))),
      ],
    ),
  );

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
            ar: 'يشمل الأصناف النشطة والمؤرشفة وجميع سجلات الشراء والبيع التاريخية، حتى الأصناف التي لا تملك سجل أسعار.',
            en: 'Includes active and archived products and every purchase/sale history record, including products without price history.',
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
            ar: 'يدعم XLSX وCSV UTF-8 بعناوين عربية أو إنجليزية. تُعرض المعاينة والأخطاء قبل أي كتابة في قاعدة البيانات.',
            en: 'Supports XLSX and UTF-8 CSV with Arabic or English headers. Preview and validation happen before data is written.',
          ),
          const SizedBox(height: 8),
          const AppText(
            ar: 'تتم المطابقة بالاسم ووحدة القياس فقط. لا تتغير بيانات الصنف الموجود، ولا يُحذف أي سجل. الصنف الجديد يحتاج إلى عملية شراء صحيحة واحدة على الأقل.',
            en: 'Matching uses normalized product name and unit only. Existing product metadata stays unchanged and no records are deleted. A new product needs at least one valid purchase.',
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
      const SizedBox(height: 10),
      const AppText(
        ar: 'ملفات XLS القديمة غير مدعومة مباشرة؛ احفظها من Excel أو LibreOffice بصيغة XLSX أو CSV UTF-8. استعادة النسخة الاحتياطية JSON مستقلة ولا تتأثر بهذا الاستيراد.',
        en: 'Legacy XLS files are not imported directly; save them from Excel or LibreOffice as XLSX or UTF-8 CSV. JSON backup restore is unchanged and separate.',
      ),
    ]),
  );
}

class _CountLine extends StatelessWidget {
  const _CountLine({required this.ar, required this.en, required this.value});
  final String ar;
  final String en;
  final int value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Expanded(child: AppText(ar: ar, en: en)),
      Text(value.toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
    ]),
  );
}

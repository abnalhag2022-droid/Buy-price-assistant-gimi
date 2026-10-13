import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/app_database.dart';

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
      final json = await AppDatabase.instance.exportBackupJson();
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
      if (output != null) _message('تم إنشاء ملف النسخة الاحتياطية بنجاح.');
    } catch (error) {
      _message('تعذر إنشاء النسخة الاحتياطية: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmRestore() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('تأكيد استعادة البيانات'),
            content: const Text(
              'ستُستبدل جميع الأصناف وسجلات الشراء والبيع الموجودة حالياً بالبيانات الموجودة في الملف المختار. '
              'صدّر نسخة احتياطية من بياناتك الحالية أولاً. لن تُحذف بيانات التطبيق أو إعداداته الأخرى.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('متابعة'),
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
      await AppDatabase.instance.restoreBackupJson(content);
      _message('تمت استعادة البيانات بنجاح.');
    } catch (error) {
      _message('لم تتم الاستعادة، ولم تُعتمد بيانات الملف: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('النسخ الاحتياطي والاستعادة')),
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
                  const Text('حافظ على بياناتك', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  const Text(
                    'تتضمن النسخة الاحتياطية الأصناف النشطة والمؤرشفة، وجميع سجلات الشراء والبيع، '
                    'والأسعار والكميات والتواريخ والموردين والعملاء والملاحظات. يُحفظ الملف بصيغة JSON '
                    'يمكنك نقله إلى مكان آمن.',
                    style: TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _exportBackup,
                    icon: const Icon(Icons.save_alt),
                    label: const Text('إنشاء نسخة احتياطية'),
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
                  const Text('استعادة من ملف', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  const Text(
                    'اختر ملفاً أنشأه هذا التطبيق. تُفحص بنيته أولاً، ثم تُستعاد البيانات داخل معاملة قاعدة بيانات '
                    'واحدة؛ إذا فشل الاستيراد، تُلغى العملية ولا تُعتمد بيانات جزئية.',
                    style: TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _restoreBackup,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('اختيار ملف للاستعادة'),
                  ),
                ],
              ),
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 8),
            const Center(child: Text('يرجى الانتظار...')),
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

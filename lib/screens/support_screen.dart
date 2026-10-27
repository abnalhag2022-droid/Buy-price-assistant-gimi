import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_settings.dart';
import '../ui/ui.dart';
import '../utils/app_helpers.dart';
import '../utils/app_info.dart';
import '../utils/app_text.dart';
import '../utils/error_log.dart';

/// Contact details, privacy summary, version, licences and the local error
/// log the user can copy into a support message.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, this.errorLog});

  final ErrorLog? errorLog;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  static const String _whatsApp = '+967773436537';
  static const String _email = 'abnalhag2022@gmail.com';

  ErrorLog get _log => widget.errorLog ?? ErrorLog.instance;

  Future<void> _open(Uri uri) async {
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      showMessage(context, appTextValue('لا يوجد تطبيق لفتح هذا الرابط على الجهاز.', 'No app on this device can open this link.'));
    }
  }

  Future<void> _copyReport() async {
    await Clipboard.setData(ClipboardData(text: _log.report(language: AppSettings.instance.language)));
    if (mounted) {
      showMessage(context, appTextValue('نُسخ التقرير. الصقه في رسالة الدعم.', 'Report copied. Paste it into your support message.'));
    }
  }

  Future<void> _clearLog() async {
    final confirmed = await showConfirmDialog(
      context,
      title: appTextValue('مسح سجل الأخطاء؟', 'Clear the error log?'),
      message: appTextValue('يُحذف سجل الأخطاء من الجهاز. لا تتأثر بياناتك.', 'The error log is deleted from the device. Your data is not affected.'),
      confirmLabel: appTextValue('مسح', 'Clear'),
    );
    if (!confirmed) return;
    await _log.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final errors = _log.entries;
    return Scaffold(
      appBar: AppBar(title: Text(appTextValue('الدعم وحول التطبيق', 'Support and about'))),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.all(Space.lg),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Row(children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(color: BrandColors.navy, borderRadius: BorderRadius.circular(Radii.lg)),
                    child: const Icon(Icons.receipt_long_rounded, color: BrandColors.gold, size: 32),
                  ),
                  const SizedBox(width: Space.lg),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(appTextValue(AppInfo.nameAr, AppInfo.nameEn), style: context.text.titleMedium),
                      Text(ltrIsolate(AppInfo.nameEn), style: context.text.bodySmall),
                      Text('${appTextValue('الإصدار', 'Version')} ${ltrIsolate(AppInfo.versionLabel)}', style: context.text.bodySmall),
                    ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: Space.md),
            SectionCard(
              title: appTextValue('التواصل', 'Contact'),
              icon: Icons.support_agent_outlined,
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.sm),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.chat_outlined),
                  title: Text(appTextValue('واتساب', 'WhatsApp')),
                  subtitle: Text(ltrIsolate(_whatsApp)),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _open(Uri.parse('https://wa.me/${_whatsApp.substring(1)}')),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.email_outlined),
                  title: Text(appTextValue('البريد الإلكتروني', 'Email')),
                  subtitle: Text(ltrIsolate(_email)),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _open(Uri(scheme: 'mailto', path: _email)),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            SectionCard(
              title: appTextValue('الخصوصية', 'Privacy'),
              icon: Icons.lock_outline,
              children: [
                Text(appTextValue(
                  'يعمل التطبيق دون إنترنت. الأصناف والأسعار وأسماء الموردين والعملاء محفوظة على هذا الجهاز فقط، ولا يرسل التطبيق أي بيانات أو إحصاءات. '
                      'الملفات التي تصدّرها أو نسخك الاحتياطية تُحفظ حيث تختار، وهي غير مشفّرة.',
                  'The app works offline. Items, prices and supplier/customer names are stored on this device only, and the app sends no data or analytics. '
                      'Files you export and your backups are saved where you choose and are not encrypted.',
                )),
              ],
            ),
            const SizedBox(height: Space.md),
            SectionCard(
              title: appTextValue('سجل الأخطاء', 'Error log'),
              icon: Icons.bug_report_outlined,
              subtitle: appTextValue(
                'يُحفظ على الجهاز فقط ولا يُرسل تلقائيًا. انسخه وأرسله إلى الدعم عند الإبلاغ عن مشكلة.',
                'Kept on the device only and never sent automatically. Copy it into a support message when reporting a problem.',
              ),
              children: [
                Text(
                  errors.isEmpty
                      ? appTextValue('لا توجد أخطاء مسجلة.', 'No errors recorded.')
                      : appTextValue('أخطاء مسجلة: ${ltrIsolate('${errors.length}')} · آخرها ${ltrIsolate(formatDateTime(errors.first.time.toIso8601String()))}',
                          'Recorded errors: ${errors.length} · latest ${ltrIsolate(formatDateTime(errors.first.time.toIso8601String()))}'),
                ),
                const SizedBox(height: Space.md),
                Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                  OutlinedButton.icon(
                    onPressed: _copyReport,
                    icon: const Icon(Icons.copy),
                    label: Text(appTextValue('نسخ التقرير', 'Copy report')),
                  ),
                  if (errors.isNotEmpty)
                    TextButton.icon(
                      onPressed: _clearLog,
                      icon: const Icon(Icons.delete_outline),
                      label: Text(appTextValue('مسح السجل', 'Clear log')),
                    ),
                ]),
              ],
            ),
            const SizedBox(height: Space.md),
            Card(
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(appTextValue('تراخيص البرمجيات مفتوحة المصدر', 'Open-source licences')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: appTextValue(AppInfo.nameAr, AppInfo.nameEn),
                  applicationVersion: AppInfo.versionLabel,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

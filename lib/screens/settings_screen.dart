import 'package:flutter/material.dart';

import '../state/app_settings.dart';
import '../utils/app_text.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _addValue(BuildContext context, {required bool category}) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AppText(
          ar: category ? 'إضافة تصنيف' : 'إضافة وحدة',
          en: category ? 'Add category' : 'Add unit',
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: appTextValue('الاسم', 'Name')),
          onSubmitted: (text) => Navigator.of(dialogContext).pop(text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const AppText(ar: 'إلغاء', en: 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const AppText(ar: 'إضافة', en: 'Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty || !context.mounted) return;
    try {
      if (category) {
        await AppSettings.instance.addCategory(value);
      } else {
        await AppSettings.instance.addUnit(value);
      }
    } on StateError {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(appTextValue(
          'لم تتم الإضافة: القيمة مسجلة مسبقًا أو وصلت القائمة إلى الحد الأقصى.',
          'Not added: the value already exists or the list reached its limit.',
        )),
      ));
    } on ArgumentError {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(appTextValue('أدخل قيمة صحيحة.', 'Enter a valid value.')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const AppText(ar: 'الإعدادات', en: 'Settings')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SettingsSection(
              titleAr: 'التفضيلات العامة',
              titleEn: 'General preferences',
              icon: Icons.tune,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: settings.language,
                  decoration: InputDecoration(
                    labelText: appTextValue('لغة البرنامج', 'Application language'),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'ar', child: Text('العربية')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    try {
                      await settings.setLanguage(value);
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(error.toString())),
                        );
                      }
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: settings.theme,
                  decoration: InputDecoration(
                    labelText: appTextValue('المظهر', 'Appearance'),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'light', child: AppText(ar: 'فاتح', en: 'Light')),
                    DropdownMenuItem(value: 'dark', child: AppText(ar: 'ليلي أسود', en: 'Black / dark')),
                    DropdownMenuItem(value: 'system', child: AppText(ar: 'حسب الجهاز', en: 'System default')),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    try {
                      await settings.setTheme(value);
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(error.toString())),
                        );
                      }
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: settings.currency,
                  decoration: InputDecoration(
                    labelText: appTextValue(
                      'العملة الافتراضية للعمليات الجديدة',
                      'Default currency for new entries',
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'USD', child: Text('USD — US Dollar')),
                    DropdownMenuItem(value: 'SAR', child: Text('SAR — Saudi Riyal')),
                    DropdownMenuItem(value: 'YER', child: Text('YER — Yemeni Rial')),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    try {
                      await settings.setCurrency(value);
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(error.toString())),
                        );
                      }
                    }
                  },
                ),
                const SizedBox(height: 8),
                const AppText(
                  ar: 'تغيير العملة الافتراضية لا يحوّل الأسعار القديمة. لكل عملية عملتها المسجلة بصورة مستقلة.',
                  en: 'Changing the default currency does not convert historical prices. Each transaction retains its recorded currency.',
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SettingsSection(
              titleAr: 'تصنيفات الأصناف',
              titleEn: 'Product categories',
              icon: Icons.category_outlined,
              trailing: IconButton(
                tooltip: appTextValue('إضافة تصنيف', 'Add category'),
                onPressed: () => _addValue(context, category: true),
                icon: const Icon(Icons.add_circle_outline),
              ),
              children: [
                const AppText(
                  ar: 'توحّد هذه القائمة كتابة التصنيفات عند إضافة الأصناف. إزالة تصنيف من القائمة لا تغيّر بيانات الأصناف السابقة.',
                  en: 'This list keeps category names consistent. Removing one here does not modify previously saved products.',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: settings.categories
                      .map((value) => InputChip(
                            label: Text(localizeCatalogValue(context, value)),
                            onDeleted: () => settings.removeCategory(value),
                          ))
                      .toList(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SettingsSection(
              titleAr: 'وحدات القياس',
              titleEn: 'Units of measure',
              icon: Icons.straighten,
              trailing: IconButton(
                tooltip: appTextValue('إضافة وحدة', 'Add unit'),
                onPressed: () => _addValue(context, category: false),
                icon: const Icon(Icons.add_circle_outline),
              ),
              children: [
                const AppText(
                  ar: 'استخدم قائمة موحّدة للوحدات لتقليل اختلاف كتابتها بين الأصناف.',
                  en: 'Use a consistent unit list to reduce naming variations across products.',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: settings.units
                      .map((value) => InputChip(
                            label: Text(localizeCatalogValue(context, value)),
                            onDeleted: () => settings.removeUnit(value),
                          ))
                      .toList(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: const AppText(ar: 'حول التطبيق', en: 'About the app'),
                subtitle: const Text('Buy Price Assistant GIMI · 1.1.0'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.titleAr,
    required this.titleEn,
    required this.icon,
    required this.children,
    this.trailing,
  });

  final String titleAr;
  final String titleEn;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppText(
                      ar: titleAr,
                      en: titleEn,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );
}

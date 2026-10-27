import 'package:flutter/material.dart';

import '../state/app_settings.dart';
import '../ui/ui.dart';
import '../utils/app_helpers.dart';
import '../utils/app_info.dart';
import '../utils/app_text.dart';
import '../utils/currencies.dart';
import '../utils/error_messages.dart';
import 'backup_restore_screen.dart';
import 'data_exchange_screen.dart';
import 'support_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _apply(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) showMessage(context, friendlyError(error));
    }
  }

  Future<void> _addValue(BuildContext context, {required bool category}) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(category ? appTextValue('إضافة تصنيف', 'Add category') : appTextValue('إضافة وحدة', 'Add unit')),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: appTextValue('الاسم', 'Name')),
          onSubmitted: (text) => Navigator.of(dialog).pop(text.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(), child: Text(appTextValue('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.of(dialog).pop(controller.text.trim()), child: Text(appTextValue('إضافة', 'Add'))),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty || !context.mounted) return;
    final settings = AppSettings.instance;
    await _apply(context, () => category ? settings.addCategory(value) : settings.addUnit(value));
  }

  Future<void> _removeValue(BuildContext context, String value, {required bool category}) async {
    final confirmed = await showConfirmDialog(
      context,
      title: category ? appTextValue('إزالة التصنيف؟', 'Remove category?') : appTextValue('إزالة الوحدة؟', 'Remove unit?'),
      message: appTextValue(
        'ستُزال «${localizeCatalogValue(context, value)}» من القائمة فقط. الأصناف المسجلة بها لا تتغير.',
        '"${localizeCatalogValue(context, value)}" is removed from this list only. Items that use it are not changed.',
      ),
      confirmLabel: appTextValue('إزالة', 'Remove'),
    );
    if (!confirmed || !context.mounted) return;
    final settings = AppSettings.instance;
    await _apply(context, () => category ? settings.removeCategory(value) : settings.removeUnit(value));
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final language = Localizations.localeOf(context).languageCode;
        Widget values({required List<String> items, required bool category}) => Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final value in items)
                  InputChip(
                    label: Text(localizeCatalogValue(context, value)),
                    onDeleted: () => _removeValue(context, value, category: category),
                    deleteButtonTooltipMessage: appTextValue('إزالة', 'Remove'),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: Sizes.iconSm),
                  label: Text(appTextValue('إضافة', 'Add')),
                  onPressed: () => _addValue(context, category: category),
                ),
              ],
            );
        return Scaffold(
          appBar: AppBar(title: Text(appTextValue('الإعدادات', 'Settings'))),
          body: PageBody(
            child: ListView(
              padding: const EdgeInsets.all(Space.lg),
              children: [
                SectionCard(
                  title: appTextValue('اللغة والمظهر', 'Language and appearance'),
                  icon: Icons.tune,
                  children: [
                    Text(appTextValue('اللغة', 'Language'), style: context.text.labelLarge),
                    const SizedBox(height: Space.xs),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'ar', label: Text('العربية')),
                        ButtonSegment(value: 'en', label: Text('English')),
                      ],
                      selected: {settings.language},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) => _apply(context, () => settings.setLanguage(v.single)),
                    ),
                    const SizedBox(height: Space.lg),
                    Text(appTextValue('المظهر', 'Appearance'), style: context.text.labelLarge),
                    const SizedBox(height: Space.xs),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: 'light', icon: const Icon(Icons.light_mode_outlined), label: Text(appTextValue('فاتح', 'Light'))),
                        ButtonSegment(value: 'dark', icon: const Icon(Icons.dark_mode_outlined), label: Text(appTextValue('داكن', 'Dark'))),
                        ButtonSegment(value: 'system', icon: const Icon(Icons.brightness_auto_outlined), label: Text(appTextValue('الجهاز', 'System'))),
                      ],
                      selected: {settings.theme},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) => _apply(context, () => settings.setTheme(v.single)),
                    ),
                  ],
                ),
                const SizedBox(height: Space.md),
                SectionCard(
                  title: appTextValue('العملة الافتراضية', 'Default currency'),
                  subtitle: appTextValue(
                    'تُقترح للعمليات الجديدة فقط. لا تُحوَّل الأسعار المسجلة؛ لكل عملية عملتها.',
                    'Suggested for new records only. Recorded prices are never converted; each keeps its own currency.',
                  ),
                  icon: Icons.payments_outlined,
                  children: [
                    ChoiceList<String>(
                      options: [
                        for (final code in AppCurrencies.supported)
                          ChoiceOption(
                            value: code,
                            label: language == 'ar'
                                ? '${AppCurrencies.arabicName(code)} (${ltrIsolate(code)})'
                                : '${AppCurrencies.englishName(code)} ($code)',
                          ),
                      ],
                      selected: settings.currency,
                      onChanged: (code) => _apply(context, () => settings.setCurrency(code)),
                    ),
                  ],
                ),
                const SizedBox(height: Space.md),
                SectionCard(
                  title: appTextValue('التصنيفات', 'Categories'),
                  subtitle: appTextValue('قائمة تُختار منها التصنيفات عند إضافة صنف.', 'The list you pick categories from when adding an item.'),
                  icon: Icons.category_outlined,
                  children: [values(items: settings.categories, category: true)],
                ),
                const SizedBox(height: Space.md),
                SectionCard(
                  title: appTextValue('وحدات القياس', 'Units'),
                  subtitle: appTextValue('وحدات موحّدة تقلل اختلاف الكتابة بين الأصناف.', 'Consistent units reduce spelling differences between items.'),
                  icon: Icons.straighten,
                  children: [values(items: settings.units, category: false)],
                ),
                const SizedBox(height: Space.md),
                Card(
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.import_export_rounded),
                      title: Text(appTextValue('استيراد وتصدير Excel وCSV', 'Excel and CSV import/export')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const DataExchangeScreen())),
                    ),
                    const Divider(indent: Space.lg, endIndent: Space.lg),
                    ListTile(
                      leading: const Icon(Icons.backup_outlined),
                      title: Text(appTextValue('النسخ الاحتياطي والاستعادة', 'Backup and restore')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const BackupRestoreScreen())),
                    ),
                    const Divider(indent: Space.lg, endIndent: Space.lg),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(appTextValue('الدعم وحول التطبيق', 'Support and about')),
                      subtitle: Text(ltrIsolate('${AppInfo.nameEn} ${AppInfo.versionLabel}')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const SupportScreen())),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/product.dart';
import '../state/app_settings.dart';
import '../ui/ui.dart';
import '../utils/app_text.dart';
import '../utils/error_messages.dart';

/// Adds a product or edits its details. Prices are recorded separately.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.product});
  final Product? product;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _brand;
  late final TextEditingController _notes;
  final FocusNode _nameFocus = FocusNode();
  Timer? _suggestionTimer;
  List<Map<String, Object?>> _suggestions = <Map<String, Object?>>[];
  String? _category;
  late String _unit;
  bool _saving = false;
  bool _dirty = false;

  bool get _editing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _code = TextEditingController(text: product?.code ?? '');
    _brand = TextEditingController(text: product?.brand ?? '');
    _notes = TextEditingController(text: product?.notes ?? '');
    _category = product?.category;
    _unit = product?.unit ?? AppSettings.instance.units.first;
  }

  @override
  void dispose() {
    _suggestionTimer?.cancel();
    for (final c in [_name, _code, _brand, _notes]) {
      c.dispose();
    }
    _nameFocus.dispose();
    super.dispose();
  }

  void _changed([Object? _]) {
    if (!_dirty) setState(() => _dirty = true);
  }

  List<String> get _categoryOptions => <String>{...AppSettings.instance.categories, ?_category}.toList();

  List<String> get _unitOptions => <String>{_unit, ...AppSettings.instance.units}.toList();

  void _onNameChanged(String value) {
    _changed();
    _suggestionTimer?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    _suggestionTimer = Timer(const Duration(milliseconds: 250), () async {
      try {
        final rows = await AppDatabase.instance.suggestProductNames(query, excludeId: widget.product?.id, limit: 6);
        if (mounted && _name.text.trim() == query) setState(() => _suggestions = rows);
      } catch (_) {
        // Suggestions only help; a failure must never block entering a product.
        if (mounted) setState(() => _suggestions = const []);
      }
    });
  }

  void _useSuggestion(Map<String, Object?> row) {
    final name = row['name'] as String? ?? '';
    _name.value = TextEditingValue(text: name, selection: TextSelection.collapsed(offset: name.length));
    setState(() {
      final category = row['category'] as String?;
      final unit = row['unit'] as String?;
      final brand = row['brand'] as String?;
      if (category != null && category.trim().isNotEmpty) _category = category;
      if (unit != null && unit.trim().isNotEmpty) _unit = unit;
      if (brand != null && brand.trim().isNotEmpty && _brand.text.trim().isEmpty) _brand.text = brand;
      _suggestions = const [];
      _dirty = true;
    });
  }

  Future<void> _save() async {
    // The flag is set before any await so a double tap cannot save twice.
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (!_editing) {
        final duplicate = await AppDatabase.instance.findExactProductName(_name.text);
        if (!mounted) return;
        if (duplicate != null) {
          final archived = (duplicate['is_archived'] as num?)?.toInt() == 1;
          final proceed = await showConfirmDialog(
            context,
            title: appTextValue('الاسم مسجل مسبقًا', 'This name already exists'),
            message: appTextValue(
              'يوجد صنف باسم «${duplicate['name']}»${archived ? ' في الأرشيف' : ''}. الأفضل إضافة الأسعار إلى الصنف الموجود. هل تريد إنشاء صنف آخر بالاسم نفسه؟',
              'An item named "${duplicate['name']}"${archived ? ' is in the archive' : ' exists'}. Adding prices to the existing item is usually better. Create another item with the same name?',
            ),
            confirmLabel: appTextValue('إنشاء صنف آخر', 'Create another'),
            cancelLabel: appTextValue('رجوع', 'Go back'),
          );
          if (!proceed) {
            if (mounted) setState(() => _saving = false);
            return;
          }
        }
      }
      await AppDatabase.instance.saveProduct(
        id: widget.product?.id,
        name: _name.text,
        code: _code.text,
        category: _category,
        unit: _unit,
        brand: _brand.text,
        notes: _notes.text,
        isFavorite: widget.product?.isFavorite ?? false,
      );
      if (!mounted) return;
      _dirty = false;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, friendlyError(error));
    }
  }

  Widget _suggestionList(BuildContext context) => Card(
        margin: const EdgeInsets.only(top: Space.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.xs),
            child: Text(appTextValue('أصناف بأسماء قريبة', 'Items with similar names'), style: context.text.labelLarge),
          ),
          for (final row in _suggestions)
            ListTile(
              dense: true,
              leading: Icon((row['is_archived'] as num?) == 1 ? Icons.inventory_2_outlined : Icons.history),
              title: Text(row['name'] as String? ?? ''),
              subtitle: Text([
                if ((row['category'] as String?)?.isNotEmpty ?? false) localizeCatalogValue(context, row['category']! as String),
                localizeCatalogValue(context, row['unit'] as String? ?? ''),
                if ((row['is_archived'] as num?) == 1) appTextValue('مؤرشف', 'archived'),
              ].join(' · ')),
              onTap: () => _useSuggestion(row),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
            child: Text(
              appTextValue('اختيار اسم ينسخ تصنيفه ووحدته لتوحيد التسمية؛ لا يُدمج الصنفان.',
                  'Choosing a name copies its category and unit for consistent naming; the items are not merged.'),
              style: context.text.bodySmall,
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_dirty || _saving,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await confirmDiscardChanges(context) && context.mounted) {
            _dirty = false;
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          appBar: AppBar(title: Text(_editing ? appTextValue('تعديل الصنف', 'Edit item') : appTextValue('صنف جديد', 'New item'))),
          body: PageBody(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(Space.lg),
                children: [
                  TextFormField(
                    controller: _name,
                    focusNode: _nameFocus,
                    autofocus: !_editing,
                    textInputAction: TextInputAction.next,
                    onChanged: _onNameChanged,
                    decoration: InputDecoration(
                      labelText: appTextValue('اسم الصنف', 'Item name'),
                      hintText: appTextValue('مثال: كابل نحاس 2 خط 4 ملم', 'e.g. Copper cable 2 core 4 mm'),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? appTextValue('اسم الصنف مطلوب.', 'The item name is required.')
                        : null,
                  ),
                  if (_suggestions.isNotEmpty) _suggestionList(context),
                  const SizedBox(height: Space.md),
                  TextFormField(
                    controller: _code,
                    textInputAction: TextInputAction.next,
                    onChanged: _changed,
                    decoration: InputDecoration(
                      labelText: appTextValue('الكود أو الباركود', 'Code or barcode'),
                      hintText: appTextValue('اختياري', 'Optional'),
                      prefixIcon: const Icon(Icons.qr_code_2),
                    ),
                  ),
                  const SizedBox(height: Space.md),
                  DropdownButtonFormField<String?>(
                    initialValue: _category,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: appTextValue('التصنيف', 'Category'), prefixIcon: const Icon(Icons.category_outlined)),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text(appTextValue('بدون تصنيف', 'No category'))),
                      for (final value in _categoryOptions)
                        DropdownMenuItem<String?>(value: value, child: Text(localizeCatalogValue(context, value))),
                    ],
                    onChanged: (value) {
                      setState(() => _category = value);
                      _changed();
                    },
                  ),
                  const SizedBox(height: Space.md),
                  DropdownButtonFormField<String>(
                    initialValue: _unit,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: appTextValue('الوحدة', 'Unit'), prefixIcon: const Icon(Icons.straighten)),
                    items: [
                      for (final value in _unitOptions)
                        DropdownMenuItem<String>(value: value, child: Text(localizeCatalogValue(context, value))),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _unit = value);
                      _changed();
                    },
                  ),
                  const SizedBox(height: Space.md),
                  TextFormField(
                    controller: _brand,
                    textInputAction: TextInputAction.next,
                    onChanged: _changed,
                    decoration: InputDecoration(
                      labelText: appTextValue('العلامة التجارية أو الموديل', 'Brand or model'),
                      hintText: appTextValue('اختياري', 'Optional'),
                      prefixIcon: const Icon(Icons.business_outlined),
                    ),
                  ),
                  const SizedBox(height: Space.md),
                  TextFormField(
                    controller: _notes,
                    minLines: 2,
                    maxLines: 4,
                    onChanged: _changed,
                    decoration: InputDecoration(
                      labelText: appTextValue('ملاحظات', 'Notes'),
                      hintText: appTextValue('اختياري', 'Optional'),
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (_editing)
                    NoticeBanner(
                      margin: const EdgeInsets.only(top: Space.lg),
                      text: appTextValue(
                        'تعديل بيانات الصنف لا يغيّر سجلات أسعاره.',
                        'Editing the item details does not change its price records.',
                      ),
                    ),
                  const SizedBox(height: Space.xxl),
                ],
              ),
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.md),
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(_saving ? appTextValue('جارٍ الحفظ…', 'Saving…') : appTextValue('حفظ الصنف', 'Save item')),
              ),
            ),
          ),
        ),
      );
}

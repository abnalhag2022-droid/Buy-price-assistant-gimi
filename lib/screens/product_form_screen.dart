import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/product.dart';
import '../state/app_settings.dart';
import '../utils/app_text.dart';

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
  String? _selectedCategory;
  late String _selectedUnit;
  String _suggestionQuery = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _code = TextEditingController(text: product?.code ?? '');
    _brand = TextEditingController(text: product?.brand ?? '');
    _notes = TextEditingController(text: product?.notes ?? '');
    _selectedCategory = product?.category;
    _selectedUnit = product?.unit ?? AppSettings.instance.units.first;
  }

  @override
  void dispose() {
    _suggestionTimer?.cancel();
    _name.dispose();
    _code.dispose();
    _brand.dispose();
    _notes.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  List<String> get _categoryOptions {
    final values = <String>['', ...AppSettings.instance.categories];
    final current = _selectedCategory;
    if (current != null && current.isNotEmpty && !values.contains(current)) {
      values.add(current);
    }
    return values;
  }

  List<String> get _unitOptions {
    final values = <String>[...AppSettings.instance.units];
    if (!values.contains(_selectedUnit)) values.insert(0, _selectedUnit);
    return values.isEmpty ? <String>['قطعة'] : values;
  }

  void _onNameChanged(String value) {
    _suggestionTimer?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _suggestions = <Map<String, Object?>>[];
        _suggestionQuery = query;
      });
      return;
    }

    _suggestionTimer = Timer(const Duration(milliseconds: 180), () async {
      try {
        final rows = await AppDatabase.instance.suggestProductNames(
          query,
          excludeId: widget.product?.id,
          limit: 10,
        );
        if (!mounted || _name.text.trim() != query) return;
        setState(() {
          _suggestions = rows;
          _suggestionQuery = query;
        });
      } catch (_) {
        // Suggestions are helpful but never block normal item entry if search fails.
        if (mounted && _name.text.trim() == query) {
          setState(() => _suggestions = <Map<String, Object?>>[]);
        }
      }
    });
  }

  void _useSuggestion(Map<String, Object?> row) {
    final value = row['name'] as String? ?? '';
    _name.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    final category = row['category'] as String?;
    final unit = row['unit'] as String?;
    final brand = row['brand'] as String?;
    setState(() {
      if (category != null && category.trim().isNotEmpty) {
        _selectedCategory = category;
      }
      if (unit != null && unit.trim().isNotEmpty) _selectedUnit = unit;
      if (brand != null && brand.trim().isNotEmpty) _brand.text = brand;
      _suggestions = <Map<String, Object?>>[];
    });
    _nameFocus.requestFocus();
  }

  Future<bool> _confirmDuplicate(Map<String, Object?> duplicate) async {
    final name = duplicate['name'] as String? ?? _name.text.trim();
    final archived = (duplicate['is_archived'] as num?)?.toInt() == 1;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const AppText(
              ar: 'اسم صنف مسجل مسبقًا',
              en: 'An item with this name already exists',
            ),
            content: Text(appTextValue(
              'يوجد صنف بالاسم «$name»${archived ? ' (مؤرشف)' : ''}. يمكنك العودة لاختيار الصنف الموجود، أو حفظ نسخة أخرى إذا كان ذلك مقصودًا.',
              'An item named “$name”${archived ? ' (archived)' : ''} already exists. Go back to use it, or save a duplicate if intentional.',
            )),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const AppText(ar: 'العودة', en: 'Go back'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const AppText(ar: 'حفظ رغم ذلك', en: 'Save anyway'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    if (widget.product == null) {
      final duplicate = await AppDatabase.instance.findExactProductName(_name.text);
      if (!mounted) return;
      if (duplicate != null && !await _confirmDuplicate(duplicate)) return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await AppDatabase.instance.saveProduct(
        id: widget.product?.id,
        name: _name.text,
        code: _code.text,
        category: _selectedCategory,
        unit: _selectedUnit,
        brand: _brand.text,
        notes: _notes.text,
        isFavorite: widget.product?.isFavorite ?? false,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${appTextValue('تعذر حفظ الصنف', 'Unable to save item')}: $error'),
        ),
      );
      setState(() => _saving = false);
    }
  }

  Widget _suggestionPanel(BuildContext context) => Card(
        margin: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: AppText(
                ar: 'أسماء سابقة تحتوي على «$_suggestionQuery»',
                en: 'Existing names containing “$_suggestionQuery”',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            ..._suggestions.map((row) {
              final archived = (row['is_archived'] as num?)?.toInt() == 1;
              final category = row['category'] as String?;
              final unit = row['unit'] as String? ?? '';
              final description = <String>[
                if (category != null && category.isNotEmpty)
                  localizeCatalogValue(context, category),
                if (unit.isNotEmpty) localizeCatalogValue(context, unit),
                appTextValue(
                  archived ? 'مؤرشف' : 'مسجل سابقًا',
                  archived ? 'Archived' : 'Already registered',
                ),
              ].join(' • ');
              return ListTile(
                dense: true,
                leading: Icon(
                  archived ? Icons.inventory_2_outlined : Icons.history,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(row['name'] as String? ?? ''),
                subtitle: Text(description),
                onTap: () => _useSuggestion(row),
              );
            }),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: AppText(
            ar: widget.product == null ? 'إضافة صنف جديد' : 'تعديل بيانات الصنف',
            en: widget.product == null ? 'Add new item' : 'Edit item',
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const AppText(
                ar: 'البيانات الأساسية',
                en: 'Basic information',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                focusNode: _nameFocus,
                autofocus: widget.product == null,
                textInputAction: TextInputAction.next,
                onChanged: _onNameChanged,
                decoration: InputDecoration(
                  labelText: appTextValue('اسم الصنف *', 'Item name *'),
                  hintText: appTextValue(
                    'مثال: محول ٧٥ كيلوواط بيدفورد الوكالة',
                    'Example: Bedford Agency 75 kW converter',
                  ),
                  suffixIcon: const Icon(Icons.search),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? appTextValue('أدخل اسم الصنف.', 'Enter an item name.')
                    : null,
              ),
              if (_suggestions.isNotEmpty) _suggestionPanel(context),
              const SizedBox(height: 12),
              TextFormField(
                controller: _code,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: appTextValue('كود الصنف / الباركود', 'Item code / barcode'),
                  hintText: appTextValue('اختياري', 'Optional'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedCategory ?? '',
                      decoration: InputDecoration(
                        labelText: appTextValue('التصنيف', 'Category'),
                      ),
                      items: _categoryOptions
                          .map((value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(value.isEmpty
                                    ? appTextValue('بدون تصنيف', 'Uncategorized')
                                    : localizeCatalogValue(context, value)),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() {
                        _selectedCategory = value == null || value.isEmpty ? null : value;
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedUnit,
                      decoration: InputDecoration(
                        labelText: appTextValue('الوحدة *', 'Unit *'),
                      ),
                      items: _unitOptions
                          .map((value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(localizeCatalogValue(context, value)),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _selectedUnit = value);
                      },
                      validator: (value) => value == null || value.trim().isEmpty
                          ? appTextValue('اختر الوحدة.', 'Select a unit.')
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _brand,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: appTextValue('العلامة التجارية / الموديل', 'Brand / model'),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: appTextValue('ملاحظات', 'Notes'),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),
              AppText(
                ar: 'تظهر هنا أسماء الأصناف المسجلة التي تحتوي على أي جزء من الاسم المكتوب. اختيار اسم سابق يساعد على توحيد تسمية المجموعة والتصنيف والوحدة. لا يتم استبدال الاسم إلا عند اختيار أحد الاقتراحات.',
                en: 'Previously saved item names containing any part of the current text appear here. Selecting a suggestion reuses its name, category, unit, and brand. The current name is only replaced when you select a suggestion.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: AppText(
                  ar: _saving ? 'جارٍ الحفظ...' : 'حفظ الصنف',
                  en: _saving ? 'Saving...' : 'Save item',
                ),
              ),
            ],
          ),
        ),
      );
}

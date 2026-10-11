import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/product.dart';

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
  late final TextEditingController _category;
  late final TextEditingController _unit;
  late final TextEditingController _brand;
  late final TextEditingController _notes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _code = TextEditingController(text: product?.code ?? '');
    _category = TextEditingController(text: product?.category ?? '');
    _unit = TextEditingController(text: product?.unit ?? 'قطعة');
    _brand = TextEditingController(text: product?.brand ?? '');
    _notes = TextEditingController(text: product?.notes ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _category.dispose();
    _unit.dispose();
    _brand.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await AppDatabase.instance.saveProduct(
        id: widget.product?.id,
        name: _name.text,
        code: _code.text,
        category: _category.text,
        unit: _unit.text,
        brand: _brand.text,
        notes: _notes.text,
        isFavorite: widget.product?.isFavorite ?? false,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حفظ الصنف: $error')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.product == null ? 'إضافة صنف جديد' : 'تعديل بيانات الصنف')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _FormSectionTitle(title: 'البيانات الأساسية', icon: Icons.inventory_2_outlined),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                autofocus: widget.product == null,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'اسم الصنف *', hintText: 'مثال: كابل نحاس 16 ملم'),
                validator: (value) => (value == null || value.trim().isEmpty) ? 'أدخل اسم الصنف.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _code, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'كود الصنف / الباركود', hintText: 'اختياري')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextFormField(controller: _category, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'التصنيف'))),
                const SizedBox(width: 10),
                Expanded(child: TextFormField(controller: _unit, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'الوحدة'), validator: (v) => (v == null || v.trim().isEmpty) ? 'أدخل الوحدة.' : null)),
              ]),
              const SizedBox(height: 12),
              TextFormField(controller: _brand, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'العلامة التجارية / الموديل')),
              const SizedBox(height: 12),
              TextFormField(controller: _notes, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'ملاحظات', alignLabelWithHint: true)),
              const SizedBox(height: 24),
              const _FormSectionTitle(title: 'معلومة مهمة', icon: Icons.info_outline),
              const SizedBox(height: 8),
              const Text('بيانات الصنف وصفية فقط. يتم تسجيل كل عملية شراء أو بيع في سجل مستقل حتى لا تتغير الأسعار السابقة عند تحديث بيانات الصنف.', style: TextStyle(color: Colors.black54, height: 1.5)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ الصنف'),
              ),
            ],
          ),
        ),
      );
}

class _FormSectionTitle extends StatelessWidget {
  const _FormSectionTitle({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ]);
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_database.dart';
import '../utils/app_helpers.dart';

class PriceEntryFormScreen extends StatefulWidget {
  const PriceEntryFormScreen({super.key, required this.productId, required this.productName, required this.isPurchase});

  final int productId;
  final String productName;
  final bool isPurchase;

  @override
  State<PriceEntryFormScreen> createState() => _PriceEntryFormScreenState();
}

class _PriceEntryFormScreenState extends State<PriceEntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _price = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _party = TextEditingController();
  final _invoice = TextEditingController();
  final _notes = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _price.dispose();
    _quantity.dispose();
    _party.dispose();
    _invoice.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('ar'),
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'اختر تاريخ العملية',
      cancelText: 'إلغاء',
      confirmText: 'اختيار',
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  String? _validateNumber(String? value, {required bool quantity}) {
    final parsed = parseLocalizedNumber(value ?? '');
    if (parsed == null) return 'أدخل رقمًا صحيحًا.';
    if (quantity ? parsed <= 0 : parsed < 0) {
      return quantity ? 'الكمية يجب أن تكون أكبر من صفر.' : 'السعر يجب ألا يكون سالبًا.';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final price = parseLocalizedNumber(_price.text)!;
    final quantity = parseLocalizedNumber(_quantity.text)!;
    try {
      final date = toIsoDate(_date);
      if (widget.isPurchase) {
        await AppDatabase.instance.recordPurchase(
          productId: widget.productId,
          date: date,
          unitPrice: price,
          quantity: quantity,
          supplier: _party.text,
          invoiceNumber: _invoice.text,
          notes: _notes.text,
        );
      } else {
        await AppDatabase.instance.recordSale(
          productId: widget.productId,
          date: date,
          unitPrice: price,
          quantity: quantity,
          customer: _party.text,
          notes: _notes.text,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تسجيل العملية: $error')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPurchase = widget.isPurchase;
    final title = isPurchase ? 'تسجيل عملية شراء' : 'تسجيل عملية بيع';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Icon(isPurchase ? Icons.shopping_cart_outlined : Icons.sell_outlined)),
                title: Text(widget.productName, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(isPurchase ? 'سيُحفظ السعر في سجل المشتريات' : 'سيُحفظ السعر في سجل المبيعات'),
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'تاريخ العملية *', prefixIcon: Icon(Icons.calendar_month_outlined)),
                child: Row(children: [Expanded(child: Text(formatDate(toIsoDate(_date)))), const Icon(Icons.edit_calendar_outlined)]),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹.,٫٬\-]'))],
              decoration: InputDecoration(labelText: isPurchase ? 'سعر شراء الوحدة *' : 'سعر بيع الوحدة *', suffixText: 'ر.ي', helperText: 'اكتب السعر للوحدة الواحدة، ويمكن إدخال الأرقام العربية أو الإنجليزية.'),
              validator: (value) => _validateNumber(value, quantity: false),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _quantity,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹.,٫٬]'))],
              decoration: const InputDecoration(labelText: 'الكمية *'),
              validator: (value) => _validateNumber(value, quantity: true),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _party, textInputAction: TextInputAction.next, decoration: InputDecoration(labelText: isPurchase ? 'اسم المورد' : 'اسم العميل')),
            if (isPurchase) ...[
              const SizedBox(height: 12),
              TextFormField(controller: _invoice, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'رقم الفاتورة')),
            ],
            const SizedBox(height: 12),
            TextFormField(controller: _notes, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'ملاحظات العملية', alignLabelWithHint: true)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ العملية'),
            ),
          ],
        ),
      ),
    );
  }
}

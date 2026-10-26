import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_database.dart';
import '../models/price_entry.dart';
import '../utils/app_helpers.dart';
import '../state/app_settings.dart';
import '../utils/app_text.dart';

class PriceEntryFormScreen extends StatefulWidget {
  const PriceEntryFormScreen({super.key, required this.productId, required this.productName, required this.isPurchase, this.entry});

  final int productId;
  final String productName;
  final bool isPurchase;
  final PriceEntry? entry;

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
  String _currency = AppSettings.instance.currency;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    if (entry != null) {
      _price.text = entry.unitPrice.toString();
      _quantity.text = entry.quantity.toString();
      _party.text = entry.partyName ?? '';
      _invoice.text = entry.invoiceNumber ?? '';
      _notes.text = entry.notes ?? '';
      _date = DateTime.parse(entry.date);
      _currency = entry.currencyCode;
    }
  }

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
      locale: Localizations.localeOf(context),
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
    if (parsed == null) return appTextValue('أدخل رقمًا صحيحًا.', 'Enter a valid number.');
    if (quantity ? parsed <= 0 : parsed < 0) {
      return quantity ? appTextValue('الكمية يجب أن تكون أكبر من صفر.', 'Quantity must be greater than zero.') : appTextValue('السعر يجب ألا يكون سالبًا.', 'Price cannot be negative.');
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
      final entry = widget.entry;
      if (entry != null) {
        if (widget.isPurchase) {
          await AppDatabase.instance.updatePurchaseEntry(
            id: entry.id,
            productId: widget.productId,
            date: date,
            unitPrice: price,
            quantity: quantity,
            supplier: _party.text,
            invoiceNumber: _invoice.text,
            notes: _notes.text,
            currencyCode: _currency,
          );
        } else {
          await AppDatabase.instance.updateSaleEntry(
            id: entry.id,
            productId: widget.productId,
            date: date,
            unitPrice: price,
            quantity: quantity,
            customer: _party.text,
            notes: _notes.text,
            currencyCode: _currency,
          );
        }
      } else if (widget.isPurchase) {
        await AppDatabase.instance.recordPurchase(
          productId: widget.productId,
          date: date,
          unitPrice: price,
          quantity: quantity,
          supplier: _party.text,
          invoiceNumber: _invoice.text,
          notes: _notes.text,
          currencyCode: _currency,
        );
      } else {
        await AppDatabase.instance.recordSale(
          productId: widget.productId,
          date: date,
          unitPrice: price,
          quantity: quantity,
          customer: _party.text,
          notes: _notes.text,
          currencyCode: _currency,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(appTextValue(widget.entry == null ? 'تعذر تسجيل العملية: ' : 'تعذر تعديل العملية: ', widget.entry == null ? 'Could not save transaction: ' : 'Could not update transaction: ') + error.toString())));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPurchase = widget.isPurchase;
    final title = widget.entry == null
        ? appTextValue(isPurchase ? 'تسجيل عملية شراء' : 'تسجيل عملية بيع', isPurchase ? 'Record purchase' : 'Record sale')
        : appTextValue(isPurchase ? 'تعديل عملية شراء' : 'تعديل عملية بيع', isPurchase ? 'Edit purchase transaction' : 'Edit sale transaction');
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
                subtitle: Text(appTextValue(
                  widget.entry == null
                      ? (isPurchase ? 'سيُحفظ السعر في سجل المشتريات' : 'سيُحفظ السعر في سجل المبيعات')
                      : 'سيتم تحديث هذه العملية في سجل ${isPurchase ? 'المشتريات' : 'المبيعات'}',
                  widget.entry == null
                      ? (isPurchase ? 'This price will be saved in purchase history' : 'This price will be saved in sales history')
                      : 'This transaction will be updated in ${isPurchase ? 'purchase' : 'sales'} history',
                )),
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: InputDecoration(labelText: appTextValue('تاريخ العملية *', 'Transaction date *'), prefixIcon: Icon(Icons.calendar_month_outlined)),
                child: Row(children: [Expanded(child: Text(formatDate(toIsoDate(_date), Localizations.localeOf(context).languageCode))), const Icon(Icons.edit_calendar_outlined)]),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹.,٫٬\-]'))],
              decoration: InputDecoration(labelText: appTextValue(isPurchase ? 'سعر شراء الوحدة *' : 'سعر بيع الوحدة *', isPurchase ? 'Purchase price per unit *' : 'Sale price per unit *'), suffixText: currencyLabel(context, _currency), helperText: appTextValue('اكتب السعر للوحدة الواحدة، ويمكن إدخال الأرقام العربية أو الإنجليزية.', 'Enter price per unit. Arabic and English digits are supported.')),
              validator: (value) => _validateNumber(value, quantity: false),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              decoration: InputDecoration(labelText: appTextValue('عملة العملية', 'Transaction currency')),
              items: const [
                DropdownMenuItem(value: 'USD', child: Text('USD — US Dollar')),
                DropdownMenuItem(value: 'SAR', child: Text('SAR — Saudi Riyal')),
                DropdownMenuItem(value: 'YER', child: Text('YER — Yemeni Rial')),
              ],
              onChanged: (value) { if (value != null) setState(() => _currency = value); },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _quantity,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹.,٫٬]'))],
              decoration: InputDecoration(labelText: appTextValue('الكمية *', 'Quantity *')),
              validator: (value) => _validateNumber(value, quantity: true),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _party, textInputAction: TextInputAction.next, decoration: InputDecoration(labelText: appTextValue(isPurchase ? 'اسم المورد' : 'اسم العميل', isPurchase ? 'Supplier name' : 'Customer name'))),
            if (isPurchase) ...[
              const SizedBox(height: 12),
              TextFormField(controller: _invoice, textInputAction: TextInputAction.next, decoration: InputDecoration(labelText: appTextValue('رقم الفاتورة', 'Invoice number'))),
            ],
            const SizedBox(height: 12),
            TextFormField(controller: _notes, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: appTextValue('ملاحظات العملية', 'Transaction notes'), alignLabelWithHint: true)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
              label: AppText(
                ar: _saving ? 'جارٍ الحفظ...' : (widget.entry == null ? 'حفظ العملية' : 'حفظ التعديلات'),
                en: _saving ? 'Saving...' : (widget.entry == null ? 'Save transaction' : 'Save changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/price_entry.dart';
import '../models/product.dart';
import '../state/app_settings.dart';
import '../ui/ui.dart';
import '../utils/app_helpers.dart';
import '../utils/app_text.dart';
import '../utils/currencies.dart';
import '../utils/error_messages.dart';

/// Records a new purchase or sale price, or edits an existing record.
class PriceEntryFormScreen extends StatefulWidget {
  const PriceEntryFormScreen({super.key, required this.product, required this.isPurchase, this.entry});

  final Product product;
  final bool isPurchase;

  /// When set, this record is edited instead of a new one being added.
  final PriceEntry? entry;

  @override
  State<PriceEntryFormScreen> createState() => _PriceEntryFormScreenState();
}

class _PriceEntryFormScreenState extends State<PriceEntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _price;
  late final TextEditingController _quantity;
  late final TextEditingController _party;
  late final TextEditingController _invoice;
  late final TextEditingController _notes;
  late DateTime _date;
  late String _currency;
  bool _saving = false;
  bool _dirty = false;

  bool get _editing => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    // Edited values are shown without grouping or exponent so they can be
    // edited and parsed back exactly.
    _price = TextEditingController(text: entry == null ? '' : editableNumber(entry.unitPrice));
    _quantity = TextEditingController(text: entry == null ? '1' : editableNumber(entry.quantity));
    _party = TextEditingController(text: entry?.partyName ?? '');
    _invoice = TextEditingController(text: entry?.invoiceNumber ?? '');
    _notes = TextEditingController(text: entry?.notes ?? '');
    _date = entry == null ? DateTime.now() : DateTime.parse(entry.date);
    // A new record starts in the currency of the product's last record of the
    // same kind, so a rial price is not saved as dollars by mistake.
    final last = widget.isPurchase ? widget.product.latestPurchaseCurrency : widget.product.latestSaleCurrency;
    _currency = entry?.currencyCode ?? last ?? AppSettings.instance.currency;
  }

  @override
  void dispose() {
    for (final c in [_price, _quantity, _party, _invoice, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed([Object? _]) {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _pickDate() async {
    // Imported records may be older or later than the usual range; keep them pickable.
    final first = DateTime(2000);
    final last = DateTime.now().add(const Duration(days: 366));
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _date.isBefore(first) ? _date : first,
      lastDate: _date.isAfter(last) ? _date : last,
      helpText: appTextValue('تاريخ العملية', 'Transaction date'),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
      _changed();
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final db = AppDatabase.instance;
    final price = parseLocalizedNumber(_price.text)!;
    final quantity = parseLocalizedNumber(_quantity.text)!;
    final date = toIsoDate(_date);
    final productId = widget.product.id;
    try {
      final entry = widget.entry;
      if (widget.isPurchase) {
        if (entry == null) {
          await db.recordPurchase(productId: productId, date: date, unitPrice: price, quantity: quantity,
              supplier: _party.text, invoiceNumber: _invoice.text, notes: _notes.text, currencyCode: _currency);
        } else {
          await db.updatePurchaseEntry(id: entry.id, productId: productId, date: date, unitPrice: price, quantity: quantity,
              supplier: _party.text, invoiceNumber: _invoice.text, notes: _notes.text, currencyCode: _currency);
        }
      } else {
        if (entry == null) {
          await db.recordSale(productId: productId, date: date, unitPrice: price, quantity: quantity,
              customer: _party.text, notes: _notes.text, currencyCode: _currency);
        } else {
          await db.updateSaleEntry(id: entry.id, productId: productId, date: date, unitPrice: price, quantity: quantity,
              customer: _party.text, notes: _notes.text, currencyCode: _currency);
        }
      }
      if (!mounted) return;
      _dirty = false;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, friendlyError(error));
    }
  }

  Widget _reference(BuildContext context) {
    final p = widget.product;
    final price = widget.isPurchase ? p.latestPurchasePrice : p.latestSalePrice;
    if (_editing) return const SizedBox.shrink();
    return PriceTile(
      kind: widget.isPurchase ? PriceKind.purchase : PriceKind.sale,
      price: price,
      currency: widget.isPurchase ? p.latestPurchaseCurrency : p.latestSaleCurrency,
      date: widget.isPurchase ? p.latestPurchaseDate : p.latestSaleDate,
      party: widget.isPurchase ? p.latestPurchaseSupplier : p.latestSaleCustomer,
    );
  }

  @override
  Widget build(BuildContext context) {
    final purchase = widget.isPurchase;
    final title = _editing
        ? appTextValue(purchase ? 'تعديل عملية شراء' : 'تعديل عملية بيع', purchase ? 'Edit purchase' : 'Edit sale')
        : appTextValue(purchase ? 'تسجيل شراء' : 'تسجيل بيع', purchase ? 'Record purchase' : 'Record sale');
    final language = Localizations.localeOf(context).languageCode;
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirmDiscardChanges(context) && context.mounted) {
          _dirty = false;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: PageBody(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(Space.lg),
              children: [
                Text(widget.product.name, style: context.text.titleMedium),
                const SizedBox(height: Space.xs),
                Text(
                  appTextValue('الوحدة: ${localizeCatalogValue(context, widget.product.unit)}',
                      'Unit: ${localizeCatalogValue(context, widget.product.unit)}'),
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: Space.md),
                _reference(context),
                const SizedBox(height: Space.lg),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: Radii.tile,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: appTextValue('تاريخ العملية', 'Transaction date'),
                      prefixIcon: const Icon(Icons.calendar_month_outlined),
                    ),
                    child: Text(ltrIsolate(formatDate(toIsoDate(_date), language))),
                  ),
                ),
                const SizedBox(height: Space.md),
                AmountField(
                  controller: _price,
                  label: appTextValue(purchase ? 'سعر شراء الوحدة' : 'سعر بيع الوحدة', purchase ? 'Purchase price per unit' : 'Sale price per unit'),
                  suffixText: currencyLabel(context, _currency),
                  helperText: appTextValue('سعر الوحدة الواحدة. تُقبل الأرقام العربية والإنجليزية.', 'Price of one unit. Arabic and Latin digits are accepted.'),
                  onChanged: _changed,
                ),
                const SizedBox(height: Space.md),
                Text(appTextValue('العملة', 'Currency'), style: context.text.labelLarge),
                const SizedBox(height: Space.xs),
                SegmentedButton<String>(
                  segments: [
                    for (final code in AppCurrencies.supported)
                      ButtonSegment<String>(
                        value: code,
                        label: Text(language == 'ar' ? AppCurrencies.arabicSymbol(code) : code),
                        tooltip: language == 'ar' ? AppCurrencies.arabicName(code) : AppCurrencies.englishName(code),
                      ),
                  ],
                  selected: {_currency},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) {
                    setState(() => _currency = value.single);
                    _changed();
                  },
                ),
                const SizedBox(height: Space.md),
                AmountField(
                  controller: _quantity,
                  label: appTextValue('الكمية', 'Quantity'),
                  suffixText: localizeCatalogValue(context, widget.product.unit),
                  mustBePositive: true,
                  onChanged: _changed,
                ),
                const SizedBox(height: Space.md),
                TextFormField(
                  controller: _party,
                  textInputAction: TextInputAction.next,
                  onChanged: _changed,
                  decoration: InputDecoration(
                    labelText: appTextValue(purchase ? 'المورد' : 'العميل', purchase ? 'Supplier' : 'Customer'),
                    hintText: appTextValue('اختياري', 'Optional'),
                    prefixIcon: Icon(purchase ? Icons.storefront_outlined : Icons.person_outline),
                  ),
                ),
                if (purchase) ...[
                  const SizedBox(height: Space.md),
                  TextFormField(
                    controller: _invoice,
                    textInputAction: TextInputAction.next,
                    onChanged: _changed,
                    decoration: InputDecoration(
                      labelText: appTextValue('رقم الفاتورة', 'Invoice number'),
                      hintText: appTextValue('اختياري', 'Optional'),
                      prefixIcon: const Icon(Icons.receipt_outlined),
                    ),
                  ),
                ],
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
              label: Text(_saving
                  ? appTextValue('جارٍ الحفظ…', 'Saving…')
                  : _editing
                      ? appTextValue('حفظ التعديلات', 'Save changes')
                      : appTextValue('حفظ العملية', 'Save')),
            ),
          ),
        ),
      ),
    );
  }
}

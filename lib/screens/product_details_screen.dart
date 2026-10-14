import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/price_entry.dart';
import '../models/product.dart';
import '../utils/app_helpers.dart';
import '../utils/app_text.dart';
import 'price_entry_form_screen.dart';
import 'product_form_screen.dart';

class ProductDetailsScreen extends StatefulWidget {
  const ProductDetailsScreen({super.key, required this.productId});
  final int productId;

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  bool _loading = true;
  String? _error;
  Product? _product;
  List<PriceEntry> _purchases = [];
  List<PriceEntry> _sales = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = AppDatabase.instance;
      final rawProduct = await db.getProduct(widget.productId);
      if (rawProduct == null) throw StateError('لم يتم العثور على الصنف.');
      final purchases = await db.getPurchaseHistory(widget.productId);
      final sales = await db.getSaleHistory(widget.productId);
      if (!mounted) return;
      setState(() {
        _product = Product.fromMap(rawProduct);
        _purchases = purchases.map(PriceEntry.fromMap).toList();
        _sales = sales.map(PriceEntry.fromMap).toList();
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _addEntry({required bool purchase}) async {
    final product = _product;
    if (product == null) return;
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => PriceEntryFormScreen(productId: product.id, productName: product.name, isPurchase: purchase),
    ));
    if (saved == true && mounted) await _load();
  }

  Future<void> _editProduct() async {
    final product = _product;
    if (product == null) return;
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ProductFormScreen(product: product)));
    if (saved == true && mounted) await _load();
  }

  Future<void> _archiveProduct() async {
    final product = _product;
    if (product == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText(ar: 'أرشفة الصنف', en: 'Archive item'),
        content: Text(appTextValue('سيختفي «${product.name}» من قائمة البحث، مع الاحتفاظ بسجل الشراء والبيع. هل تريد المتابعة؟', '“${product.name}” will be hidden from search while purchase and sale history are kept. Continue?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const AppText(ar: 'إلغاء', en: 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const AppText(ar: 'أرشفة', en: 'Archive')),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppDatabase.instance.archiveProduct(product.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null || _product == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(appTextValue('تعذر فتح الصنف', 'Could not open item') + ': $_error')));
    }
    final product = _product!;
    return Scaffold(
      appBar: AppBar(
        title: const AppText(ar: 'تفاصيل الصنف', en: 'Item details'),
        actions: [
          IconButton(tooltip: appTextValue('تعديل', 'Edit'), onPressed: _editProduct, icon: const Icon(Icons.edit_outlined)),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'archive') _archiveProduct();
              if (value == 'favorite') AppDatabase.instance.setFavorite(product.id, !product.isFavorite).then((_) => _load());
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'favorite', child: Text(appTextValue(product.isFavorite ? 'إزالة من المفضلة' : 'إضافة إلى المفضلة', product.isFavorite ? 'Remove from favorites' : 'Add to favorites'))),
              PopupMenuItem(value: 'archive', child: Text(appTextValue('أرشفة الصنف', 'Archive item'))),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(radius: 25, child: const Icon(Icons.inventory_2_outlined, size: 27)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(product.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                  ]),
                  const SizedBox(height: 14),
                  _detailLine(appTextValue('الكود', 'Code'), product.code),
                  _detailLine(appTextValue('التصنيف', 'Category'), product.category == null ? null : localizeCatalogValue(context, product.category!)),
                  _detailLine(appTextValue('الوحدة', 'Unit'), localizeCatalogValue(context, product.unit)),
                  _detailLine(appTextValue('العلامة التجارية / الموديل', 'Brand / model'), product.brand),
                  _detailLine(appTextValue('ملاحظات', 'Notes'), product.notes),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _CurrentPrice(label: appTextValue('آخر شراء', 'Latest purchase'), price: product.latestPurchasePrice, date: product.latestPurchaseDate, currency: product.latestPurchaseCurrency ?? 'YER', icon: Icons.shopping_cart_outlined)),
                    const SizedBox(width: 10),
                    Expanded(child: _CurrentPrice(label: appTextValue('آخر بيع', 'Latest sale'), price: product.latestSalePrice, date: product.latestSaleDate, currency: product.latestSaleCurrency ?? 'YER', icon: Icons.sell_outlined)),
                  ]),
                  const SizedBox(height: 10),
                  Text('${appTextValue('الفرق بين آخر سعر بيع وشراء', 'Difference between latest sale and purchase')}: ${_priceDifference(context, product)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const AppText(ar: 'هذا فرق سعري فقط، ولا يمثل صافي الربح بعد المصاريف والضرائب والخصومات.', en: 'This is only a price difference, not net profit after expenses, taxes, or discounts.', style: TextStyle(fontSize: 12)),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: FilledButton.icon(onPressed: () => _addEntry(purchase: true), icon: const Icon(Icons.add_shopping_cart), label: const AppText(ar: 'إضافة شراء', en: 'Add purchase'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton.tonalIcon(onPressed: () => _addEntry(purchase: false), icon: const Icon(Icons.point_of_sale_outlined), label: const AppText(ar: 'إضافة بيع', en: 'Add sale'))),
            ]),
            const SizedBox(height: 20),
            _HistorySection(title: appTextValue('سجل المشتريات', 'Purchase history'), icon: Icons.shopping_cart_outlined, entries: _purchases, isPurchase: true, unit: product.unit),
            const SizedBox(height: 14),
            _HistorySection(title: appTextValue('سجل المبيعات', 'Sales history'), icon: Icons.sell_outlined, entries: _sales, isPurchase: false, unit: product.unit),
          ],
        ),
      ),
    );
  }

  Widget _detailLine(String label, String? value) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 125, child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
        Expanded(child: Text(value)),
      ]),
    );
  }

  String _priceDifference(BuildContext context, Product product) {
    if (product.latestPurchasePrice == null || product.latestSalePrice == null) return appTextValue('غير متاح لعدم اكتمال السعرين', 'Unavailable because a price is missing');
    if ((product.latestPurchaseCurrency ?? 'YER') != (product.latestSaleCurrency ?? 'YER')) return appTextValue('لا يمكن مقارنة سعرين بعملتين مختلفتين', 'Cannot compare prices in different currencies');
    final difference = product.latestSalePrice! - product.latestPurchasePrice!;
    return '${difference >= 0 ? '+' : ''}${formatMoney(difference)} ${currencyLabel(context, product.latestPurchaseCurrency)}';
  }
}

class _CurrentPrice extends StatelessWidget {
  const _CurrentPrice({required this.label, required this.price, required this.date, required this.currency, required this.icon});
  final String label;
  final double? price;
  final String? date;
  final String currency;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, size: 16), const SizedBox(width: 5), Text(label, style: const TextStyle(fontSize: 12))]),
          const SizedBox(height: 5),
          Text(price == null ? appTextValue('غير مسجل', 'Not recorded') : '${formatMoney(price)} ${currencyLabel(context, currency)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          if (date != null) Text(formatDate(date, Localizations.localeOf(context).languageCode), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      );
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.title, required this.icon, required this.entries, required this.isPurchase, required this.unit});
  final String title;
  final IconData icon;
  final List<PriceEntry> entries;
  final bool isPurchase;
  final String unit;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(icon, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8), Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const Spacer(), Text(appTextValue('${entries.length} عملية', '${entries.length} transactions'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))]),
            const SizedBox(height: 10),
            if (entries.isEmpty)
              Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: Text('لا توجد عمليات مسجلة بعد.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))))
            else
              ...entries.map((entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(width: 4, height: 54, decoration: BoxDecoration(color: isPurchase ? Colors.blue : Colors.green, borderRadius: BorderRadius.circular(4))),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(formatDate(entry.date, Localizations.localeOf(context).languageCode), style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(appTextValue('الكمية: ${formatMoney(entry.quantity)} $unit', 'Quantity: ${formatMoney(entry.quantity)} $unit'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        if ((entry.partyName ?? '').isNotEmpty) Text(appTextValue(isPurchase ? 'المورد: ${entry.partyName}' : 'العميل: ${entry.partyName}', isPurchase ? 'Supplier: ${entry.partyName}' : 'Customer: ${entry.partyName}'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        if ((entry.invoiceNumber ?? '').isNotEmpty) Text(appTextValue('الفاتورة: ${entry.invoiceNumber}', 'Invoice: ${entry.invoiceNumber}'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        if ((entry.notes ?? '').isNotEmpty) Text(appTextValue('ملاحظة: ${entry.notes}', 'Note: ${entry.notes}'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ])),
                      const SizedBox(width: 8),
                      Text('${formatMoney(entry.unitPrice)} ${currencyLabel(context, entry.currencyCode)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    ]),
                  )),
          ]),
        ),
      );
}

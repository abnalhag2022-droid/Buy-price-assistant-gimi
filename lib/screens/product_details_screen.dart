import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/price_entry.dart';
import '../models/product.dart';
import '../ui/ui.dart';
import '../utils/app_helpers.dart';
import '../utils/app_text.dart';
import '../utils/error_messages.dart';
import '../utils/localized_message.dart';
import 'price_entry_form_screen.dart';
import 'product_form_screen.dart';

/// One product: its details, latest prices and full purchase/sale history.
class ProductDetailsScreen extends StatefulWidget {
  const ProductDetailsScreen({super.key, required this.productId});
  final int productId;

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  static const int _pageSize = 30;

  Product? _product;
  Object? _error;
  bool _loading = true;
  bool _showPurchases = true;
  final List<PriceEntry> _purchases = <PriceEntry>[];
  final List<PriceEntry> _sales = <PriceEntry>[];
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = AppDatabase.instance;
      final raw = await db.getProduct(widget.productId);
      if (raw == null) {
        throw LocalizedStateError('لم يُعثر على الصنف؛ ربما حُذف بالتراجع عن استيراد.', 'The item was not found; an import undo may have removed it.');
      }
      final product = Product.fromMap(raw);
      // Keep at least as many rows as already shown, so editing an old entry
      // does not collapse the list the user scrolled through.
      final purchases = await db.getPurchaseHistory(widget.productId, limit: _pageSize.clamp(_purchases.length, 100000));
      final sales = await db.getSaleHistory(widget.productId, limit: _pageSize.clamp(_sales.length, 100000));
      if (!mounted) return;
      setState(() {
        _product = product;
        _purchases
          ..clear()
          ..addAll(purchases.map(PriceEntry.fromMap));
        _sales
          ..clear()
          ..addAll(sales.map(PriceEntry.fromMap));
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final db = AppDatabase.instance;
      final purchases = _showPurchases;
      final rows = purchases
          ? await db.getPurchaseHistory(widget.productId, limit: _pageSize, offset: _purchases.length)
          : await db.getSaleHistory(widget.productId, limit: _pageSize, offset: _sales.length);
      if (!mounted) return;
      setState(() => (purchases ? _purchases : _sales).addAll(rows.map(PriceEntry.fromMap)));
    } catch (error) {
      if (mounted) showMessage(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _push(Widget screen) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => screen));
    if (changed == true && mounted) await _load();
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    try {
      await action();
      if (!mounted) return;
      if (done != null) showMessage(context, done);
      await _load();
    } catch (error) {
      if (mounted) showMessage(context, friendlyError(error));
    }
  }

  Future<void> _deleteEntry(PriceEntry entry, {required bool purchase}) async {
    final product = _product!;
    final confirmed = await showConfirmDialog(
      context,
      title: appTextValue('حذف العملية؟', 'Delete this record?'),
      message: appTextValue(
        'سيُحذف سجل ${purchase ? 'الشراء' : 'البيع'} بتاريخ ${formatDate(entry.date)} بسعر ${formatAmount(context, entry.unitPrice, entry.currencyCode)} نهائيًا. '
            'لا يمكن التراجع إلا باستعادة نسخة احتياطية.',
        'The ${purchase ? 'purchase' : 'sale'} of ${formatDate(entry.date, 'en')} at ${formatAmount(context, entry.unitPrice, entry.currencyCode)} will be deleted. '
            'It can only be recovered from a backup.',
      ),
      confirmLabel: appTextValue('حذف', 'Delete'),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final db = AppDatabase.instance;
    await _run(
      () => purchase
          ? db.deletePurchaseEntry(id: entry.id, productId: product.id)
          : db.deleteSaleEntry(id: entry.id, productId: product.id),
      done: appTextValue('حُذفت العملية.', 'Record deleted.'),
    );
  }

  Future<void> _archive() async {
    final product = _product!;
    final confirmed = await showConfirmDialog(
      context,
      title: appTextValue('أرشفة الصنف؟', 'Archive this item?'),
      message: appTextValue(
        'سيختفي «${product.name}» من قائمة الأصناف مع الاحتفاظ بكامل سجله. يمكنك إعادته من «المؤرشفة» في أي وقت.',
        '"${product.name}" will be hidden from the item list and its full history kept. You can restore it from "Archived" at any time.',
      ),
      confirmLabel: appTextValue('أرشفة', 'Archive'),
    );
    if (!confirmed || !mounted) return;
    await _run(() => AppDatabase.instance.archiveProduct(product.id), done: appTextValue('أُرشف الصنف.', 'Item archived.'));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(), body: const LoadingState());
    final product = _product;
    if (_error != null || product == null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorState(
          error: _error ?? StateError('missing product'),
          onRetry: () {
            setState(() => _loading = true);
            _load();
          },
          title: appTextValue('تعذر فتح الصنف', 'Could not open the item'),
        ),
      );
    }
    final entries = _showPurchases ? _purchases : _sales;
    final total = _showPurchases ? product.purchaseCount : product.saleCount;
    return Scaffold(
      appBar: AppBar(
        title: Text(appTextValue('تفاصيل الصنف', 'Item details')),
        actions: [
          if (!product.isArchived) ...[
            IconButton(
              tooltip: product.isFavorite
                  ? appTextValue('إزالة من المفضلة', 'Remove from favorites')
                  : appTextValue('إضافة إلى المفضلة', 'Add to favorites'),
              isSelected: product.isFavorite,
              icon: const Icon(Icons.star_border_rounded),
              selectedIcon: Icon(Icons.star_rounded, color: context.palette.favorite),
              onPressed: () => _run(() => AppDatabase.instance.setFavorite(product.id, !product.isFavorite)),
            ),
            IconButton(
              tooltip: appTextValue('تعديل بيانات الصنف', 'Edit item'),
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _push(ProductFormScreen(product: product)),
            ),
          ],
          PopupMenuButton<String>(
            tooltip: appTextValue('خيارات أخرى', 'More options'),
            onSelected: (value) {
              if (value == 'archive') _archive();
              if (value == 'unarchive') {
                _run(() => AppDatabase.instance.unarchiveProduct(product.id), done: appTextValue('أُعيد الصنف.', 'Item restored.'));
              }
            },
            itemBuilder: (_) => [
              if (product.isArchived)
                PopupMenuItem(value: 'unarchive', child: Text(appTextValue('إلغاء الأرشفة', 'Restore from archive')))
              else
                PopupMenuItem(value: 'archive', child: Text(appTextValue('أرشفة الصنف', 'Archive item'))),
            ],
          ),
        ],
      ),
      body: PageBody(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xxl),
            children: [
              _Header(product: product),
              if (product.isArchived)
                NoticeBanner(
                  kind: NoticeKind.warning,
                  margin: const EdgeInsets.only(top: Space.md),
                  text: appTextValue(
                    'هذا الصنف مؤرشف: لا يظهر في البحث ولا تُضاف له عمليات حتى تُلغى أرشفته. سجله محفوظ كاملًا.',
                    'This item is archived: it is hidden from search and takes no new records until restored. Its history is kept.',
                  ),
                  action: TextButton(
                    onPressed: () => _run(() => AppDatabase.instance.unarchiveProduct(product.id),
                        done: appTextValue('أُعيد الصنف.', 'Item restored.')),
                    child: Text(appTextValue('إلغاء الأرشفة', 'Restore')),
                  ),
                ),
              const SizedBox(height: Space.lg),
              PriceTile(
                kind: PriceKind.purchase,
                large: true,
                price: product.latestPurchasePrice,
                currency: product.latestPurchaseCurrency,
                date: product.latestPurchaseDate,
                party: product.latestPurchaseSupplier,
                quantity: product.latestPurchaseQuantity,
                unit: product.unit,
              ),
              const SizedBox(height: Space.sm),
              PriceTile(
                kind: PriceKind.sale,
                large: true,
                price: product.latestSalePrice,
                currency: product.latestSaleCurrency,
                date: product.latestSaleDate,
                party: product.latestSaleCustomer,
                quantity: product.latestSaleQuantity,
                unit: product.unit,
              ),
              _Difference(product: product),
              if (!product.isArchived) ...[
                const SizedBox(height: Space.lg),
                RecordButtons(
                  filled: true,
                  onPurchase: () => _push(PriceEntryFormScreen(product: product, isPurchase: true)),
                  onSale: () => _push(PriceEntryFormScreen(product: product, isPurchase: false)),
                ),
              ],
              SectionHeader(appTextValue('السجل', 'History')),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: Text(appTextValue('المشتريات (${product.purchaseCount})', 'Purchases (${product.purchaseCount})')),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.sell_outlined),
                    label: Text(appTextValue('المبيعات (${product.saleCount})', 'Sales (${product.saleCount})')),
                  ),
                ],
                selected: {_showPurchases},
                showSelectedIcon: false,
                onSelectionChanged: (value) => setState(() => _showPurchases = value.single),
              ),
              const SizedBox(height: Space.md),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.xl),
                  child: Text(
                    _showPurchases
                        ? appTextValue('لا توجد عمليات شراء مسجلة.', 'No purchases recorded.')
                        : appTextValue('لا توجد عمليات بيع مسجلة.', 'No sales recorded.'),
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                )
              else
                Card(
                  child: Column(children: [
                    for (var i = 0; i < entries.length; i++) ...[
                      if (i > 0) const Divider(indent: Space.lg, endIndent: Space.lg),
                      _EntryTile(
                        entry: entries[i],
                        purchase: _showPurchases,
                        unit: product.unit,
                        onEdit: () => _push(PriceEntryFormScreen(product: product, isPurchase: _showPurchases, entry: entries[i])),
                        onDelete: () => _deleteEntry(entries[i], purchase: _showPurchases),
                      ),
                    ],
                  ]),
                ),
              if (entries.length < total)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Center(
                    child: _loadingMore
                        ? const LoadingState()
                        : TextButton(
                            onPressed: _loadMore,
                            child: Text(appTextValue(
                              'عرض المزيد (${entries.length} من $total)',
                              'Show more (${entries.length} of $total)',
                            )),
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    Widget line(IconData icon, String label, String value, {bool ltr = false}) => Padding(
          padding: const EdgeInsets.only(top: Space.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: Sizes.iconMd, color: context.colors.onSurfaceVariant),
            const SizedBox(width: Space.sm),
            SizedBox(width: 96, child: Text(label, style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant))),
            Expanded(child: SelectableText(ltr ? ltrIsolate(value) : value, style: context.text.bodyMedium)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(product.name, style: context.text.headlineSmall),
          if ((product.code ?? '').isNotEmpty) line(Icons.qr_code_2, appTextValue('الكود', 'Code'), product.code!, ltr: true),
          if ((product.category ?? '').isNotEmpty)
            line(Icons.category_outlined, appTextValue('التصنيف', 'Category'), localizeCatalogValue(context, product.category!)),
          if ((product.brand ?? '').isNotEmpty) line(Icons.business_outlined, appTextValue('العلامة', 'Brand'), product.brand!),
          line(Icons.straighten, appTextValue('الوحدة', 'Unit'), localizeCatalogValue(context, product.unit)),
          if ((product.notes ?? '').isNotEmpty) line(Icons.sticky_note_2_outlined, appTextValue('ملاحظات', 'Notes'), product.notes!),
        ]),
      ),
    );
  }
}

/// Difference between the latest sale and purchase price, only when both
/// exist in the same currency (amounts in different currencies are never
/// compared or converted).
class _Difference extends StatelessWidget {
  const _Difference({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final buy = product.latestPurchasePrice;
    final sell = product.latestSalePrice;
    if (buy == null || sell == null) return const SizedBox.shrink();
    if (product.latestPurchaseCurrency != product.latestSaleCurrency) {
      return NoticeBanner(
        text: appTextValue(
          'آخر شراء وآخر بيع بعملتين مختلفتين؛ لا يُحسب الفرق بينهما.',
          'The latest purchase and sale are in different currencies, so no difference is calculated.',
        ),
      );
    }
    final difference = sell - buy;
    final sign = difference > 0 ? '+' : '';
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Text(
        appTextValue(
          'الفرق بين آخر بيع وآخر شراء: ${ltrIsolate(sign + formatMoney(difference))} ${currencyLabel(context, product.latestSaleCurrency)} (فرق سعري، وليس ربحًا صافيًا).',
          'Latest sale minus latest purchase: $sign${formatMoney(difference)} ${currencyLabel(context, product.latestSaleCurrency)} (a price difference, not net profit).',
        ),
        style: context.text.bodySmall,
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.purchase, required this.unit, required this.onEdit, required this.onDelete});

  final PriceEntry entry;
  final bool purchase;
  final String unit;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    final details = <String>[
      appTextValue(
        'الكمية ${ltrIsolate(formatQuantity(entry.quantity))} ${localizeCatalogValue(context, unit)}',
        'Qty ${formatQuantity(entry.quantity)} ${localizeCatalogValue(context, unit)}',
      ),
      if ((entry.partyName ?? '').isNotEmpty) entry.partyName!,
      if ((entry.invoiceNumber ?? '').isNotEmpty) appTextValue('فاتورة ${ltrIsolate(entry.invoiceNumber!)}', 'Invoice ${entry.invoiceNumber}'),
    ];
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(Space.lg, Space.md, Space.xs, Space.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(formatDate(entry.date, language), style: context.text.titleSmall)),
              Text(
                formatAmount(context, entry.unitPrice, entry.currencyCode),
                style: context.text.titleMedium?.copyWith(
                  color: purchase ? context.palette.purchase : context.palette.sale,
                  fontFeatures: tabularFigures,
                ),
              ),
            ]),
            const SizedBox(height: 2),
            Text(details.join(' · '), style: context.text.bodySmall),
            if ((entry.notes ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(entry.notes!, style: context.text.bodySmall),
            ],
          ]),
        ),
        PopupMenuButton<String>(
          tooltip: appTextValue('إجراءات العملية', 'Record actions'),
          onSelected: (value) {
            if (value == 'edit') onEdit?.call();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (_) => [
            if (onEdit != null)
              PopupMenuItem(
                value: 'edit',
                child: ListTile(leading: const Icon(Icons.edit_outlined), title: Text(appTextValue('تعديل', 'Edit'))),
              ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline, color: context.colors.error),
                title: Text(appTextValue('حذف', 'Delete')),
              ),
            ),
          ],
        ),
      ]),
    );
  }
}

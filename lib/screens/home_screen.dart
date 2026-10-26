import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/product.dart';
import '../utils/app_helpers.dart';
import '../utils/app_text.dart';
import 'price_entry_form_screen.dart';
import 'product_details_screen.dart';
import 'product_form_screen.dart';
import 'backup_restore_screen.dart';
import 'settings_screen.dart';
import 'data_exchange_screen.dart';
import 'support_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  late Future<List<Map<String, Object?>>> _productsFuture;
  String _query = '';
  String? _categoryFilter;
  String? _brandFilter;
  String? _supplierFilter;
  late Future<List<String>> _categoriesFuture;
  late Future<List<String>> _brandsFuture;
  late Future<List<String>> _suppliersFuture;

  @override
  void initState() {
    super.initState();
    _productsFuture = AppDatabase.instance.searchProducts('');
    _categoriesFuture = AppDatabase.instance.getDistinctCategories();
    _brandsFuture = AppDatabase.instance.getDistinctBrands();
    _suppliersFuture = AppDatabase.instance.getDistinctSuppliers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload([String? query]) {
    if (query != null) _query = query;
    setState(() => _productsFuture = AppDatabase.instance.searchProducts(_query, category: _categoryFilter, brand: _brandFilter, supplier: _supplierFilter));
  }

  Future<void> _addProduct() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ProductFormScreen()),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _openProduct(Product product) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ProductDetailsScreen(productId: product.id)),
    );
    if (mounted) _reload();
  }

  Future<void> _quickEntry(Product product, {required bool purchase}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PriceEntryFormScreen(
          productId: product.id,
          productName: product.name,
          isPurchase: purchase,
        ),
      ),
    );
    if (saved == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: Builder(builder: (context) => IconButton(
          tooltip: appTextValue('القائمة', 'Menu'),
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => Scaffold.of(context).openEndDrawer(),
        )),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppText(ar: 'مرجع أسعار الأصناف', en: 'Item price reference', style: TextStyle(fontWeight: FontWeight.w800)),
            Text('Buy Price Assistant HJI', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: appTextValue('إضافة صنف', 'Add item'),
            onPressed: _addProduct,
            icon: const Icon(Icons.add_box_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      endDrawer: Drawer(
        width: MediaQuery.sizeOf(context).width * 0.80,
        child: SafeArea(child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.tertiary],
                begin: Alignment.topRight, end: Alignment.bottomLeft,
              ),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.receipt_long_rounded, size: 42, color: Colors.white),
              SizedBox(height: 14),
              Text('Buy Price Assistant HJI', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              SizedBox(height: 4),
              Text('Purchase • Sales • Price history', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          Expanded(child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
            _drawerItem(context, Icons.inventory_2_outlined, 'الأصناف', 'Items', () => Navigator.pop(context)),
            _drawerItem(context, Icons.tune_rounded, 'الإعدادات والتصنيفات', 'Settings and categories', () async {
              Navigator.pop(context);
              await Navigator.of(this.context).push<void>(MaterialPageRoute(builder: (_) => const SettingsScreen()));
              if (mounted) _reload();
            }),
            _drawerItem(context, Icons.backup_outlined, 'النسخ الاحتياطي والاستعادة', 'Backup and restore', () async {
              Navigator.pop(context);
              await Navigator.of(this.context).push<void>(MaterialPageRoute(builder: (_) => const BackupRestoreScreen()));
              if (mounted) _reload();
            }),
            _drawerItem(context, Icons.import_export_rounded, 'استيراد وتصدير Excel وCSV', 'Excel / CSV import and export', () async {
              Navigator.pop(context);
              await Navigator.of(this.context).push<void>(MaterialPageRoute(builder: (_) => const DataExchangeScreen()));
              if (mounted) _reload();
            }),
            _drawerItem(context, Icons.support_agent_rounded, 'الدعم والتواصل', 'Support and contact', () {
              Navigator.pop(context);
              Navigator.of(this.context).push<void>(MaterialPageRoute(builder: (_) => const SupportScreen()));
            }),
            const Divider(indent: 18, endIndent: 18),
            Padding(padding: const EdgeInsets.all(18), child: Text(
              appTextValue('بحث أسرع • سجل أسعار محفوظ • يعمل دون إنترنت', 'Faster search • Saved price history • Works offline'),
              style: Theme.of(context).textTheme.bodySmall,
            )),
          ])),
        ])),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addProduct,
        icon: const Icon(Icons.add),
        label: const AppText(ar: 'إضافة صنف', en: 'Add item'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onChanged: _reload,
                    decoration: InputDecoration(
                      hintText: appTextValue('ابحث باسم الصنف أو الكود أو التصنيف', 'Search by item name, code, or category'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? const Icon(Icons.search, color: Colors.black38)
                          : IconButton(
                              tooltip: appTextValue('مسح البحث', 'Clear search'),
                              onPressed: () {
                                _searchController.clear();
                                _reload('');
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<List<String>>(
                    future: _categoriesFuture,
                    builder: (context, snapshot) {
                      final categories = snapshot.data ?? const <String>[];
                      return DropdownButtonFormField<String>(
                        value: _categoryFilter,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: appTextValue('تصفية حسب التصنيف', 'Filter by category'),
                          prefixIcon: const Icon(Icons.filter_list_rounded),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: [
                          DropdownMenuItem<String>(value: null, child: AppText(ar: 'كل التصنيفات', en: 'All categories')),
                          ...categories.map((value) => DropdownMenuItem<String>(
                            value: value, child: Text(localizeCatalogValue(context, value), overflow: TextOverflow.ellipsis),
                          )),
                        ],
                        onChanged: (value) {
                          setState(() => _categoryFilter = value);
                          _reload();
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: FutureBuilder<List<String>>(
                      future: _brandsFuture,
                      builder: (context, snapshot) {
                        final values = snapshot.data ?? const <String>[];
                        return DropdownButtonFormField<String>(
                          value: _brandFilter,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: appTextValue('العلامة التجارية', 'Brand'),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          items: [
                            DropdownMenuItem<String>(value: null, child: AppText(ar: 'كل العلامات', en: 'All brands')),
                            ...values.map((v) => DropdownMenuItem<String>(value: v, child: Text(v, overflow: TextOverflow.ellipsis))),
                          ],
                          onChanged: (v) { setState(() => _brandFilter = v); _reload(); },
                        );
                      },
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: FutureBuilder<List<String>>(
                      future: _suppliersFuture,
                      builder: (context, snapshot) {
                        final values = snapshot.data ?? const <String>[];
                        return DropdownButtonFormField<String>(
                          value: _supplierFilter,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: appTextValue('المورد', 'Supplier'),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          items: [
                            DropdownMenuItem<String>(value: null, child: AppText(ar: 'كل الموردين', en: 'All suppliers')),
                            ...values.map((v) => DropdownMenuItem<String>(value: v, child: Text(v, overflow: TextOverflow.ellipsis))),
                          ],
                          onChanged: (v) { setState(() => _supplierFilter = v); _reload(); },
                        );
                      },
                    )),
                  ]),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.history, size: 18, color: colors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _query.trim().isEmpty
                              ? appTextValue('الأصناف المحفوظة', 'Saved items')
                              : appTextValue('نتائج البحث عن: ${_query.trim()}', 'Search results for: ${_query.trim()}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _reload(),
                        icon: const Icon(Icons.refresh, size: 17),
                        label: const AppText(ar: 'تحديث', en: 'Refresh'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, Object?>>>(
                future: _productsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _MessageState(
                      icon: Icons.error_outline,
                      title: appTextValue('تعذر تحميل الأصناف', 'Could not load items'),
                      message: '${appTextValue('تحقق من سلامة البيانات ثم أعد المحاولة.', 'Check your data and try again.')}\n${snapshot.error}',
                      actionLabel: appTextValue('إعادة المحاولة', 'Retry'),
                      onAction: () => _reload(),
                    );
                  }
                  final rows = snapshot.data ?? const <Map<String, Object?>>[];
                  if (rows.isEmpty) {
                    return _MessageState(
                      icon: _query.isEmpty ? Icons.inventory_2_outlined : Icons.search_off,
                      title: _query.isEmpty ? appTextValue('ابدأ بإضافة أول صنف', 'Add your first item') : appTextValue('لا توجد نتائج مطابقة', 'No matching results'),
                      message: _query.isEmpty
                          ? appTextValue('بعد تسجيل الصنف، أضف أسعار الشراء والبيع لتظهر هنا في أي وقت.', 'After adding an item, record purchase and sale prices to view them here anytime.')
                          : appTextValue('جرّب جزءًا آخر من الاسم أو الكود، أو أضف الصنف إن لم يكن مسجلًا.', 'Try another part of the name or code, or add the item if it is not listed.'),
                      actionLabel: _query.isEmpty ? appTextValue('إضافة صنف', 'Add item') : appTextValue('مسح البحث', 'Clear search'),
                      onAction: _query.isEmpty
                          ? _addProduct
                          : () {
                              _searchController.clear();
                              _reload('');
                            },
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => _reload(),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => _ProductCard(
                        product: Product.fromMap(rows[index]),
                        onOpen: () => _openProduct(Product.fromMap(rows[index])),
                        onFavorite: (favorite) async {
                          await AppDatabase.instance.setFavorite(rows[index]['id']! as int, favorite);
                          if (mounted) _reload();
                        },
                        onPurchase: () => _quickEntry(Product.fromMap(rows[index]), purchase: true),
                        onSale: () => _quickEntry(Product.fromMap(rows[index]), purchase: false),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _drawerItem(BuildContext context, IconData icon, String ar, String en, VoidCallback onTap) =>
    ListTile(
      leading: Icon(icon),
      title: AppText(ar: ar, en: en),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.onOpen,
    required this.onFavorite,
    required this.onPurchase,
    required this.onSale,
  });

  final Product product;
  final VoidCallback onOpen;
  final ValueChanged<bool> onFavorite;
  final VoidCallback onPurchase;
  final VoidCallback onSale;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(13)),
                    child: Icon(Icons.inventory_2_outlined, color: colors.onPrimaryContainer),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(
                          [if ((product.code ?? '').isNotEmpty) appTextValue('الكود: ${product.code}', 'Code: ${product.code}'), if ((product.category ?? '').isNotEmpty) localizeCatalogValue(context, product.category!)]
                              .join(' • ')
                              .ifEmpty(appTextValue('الوحدة: ${localizeCatalogValue(context, product.unit)}', 'Unit: ${localizeCatalogValue(context, product.unit)}')),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: appTextValue(product.isFavorite ? 'إزالة من المفضلة' : 'إضافة إلى المفضلة', product.isFavorite ? 'Remove from favorites' : 'Add to favorites'),
                    onPressed: () => onFavorite(!product.isFavorite),
                    icon: Icon(product.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                        color: product.isFavorite ? Colors.amber.shade800 : Colors.black38),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _PricePill(
                      label: appTextValue('آخر شراء', 'Latest purchase'),
                      price: product.latestPurchasePrice,
                      currency: product.latestPurchaseCurrency,
                      date: product.latestPurchaseDate,
                      color: const Color(0xFFEAF3FF),
                      icon: Icons.shopping_cart_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PricePill(
                      label: appTextValue('آخر بيع', 'Latest sale'),
                      price: product.latestSalePrice,
                      currency: product.latestSaleCurrency,
                      date: product.latestSaleDate,
                      color: const Color(0xFFEAF7EF),
                      icon: Icons.sell_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPurchase,
                      icon: const Icon(Icons.add_shopping_cart, size: 18),
                      label: const AppText(ar: 'تسجيل شراء', en: 'Record purchase'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: onSale,
                      icon: const Icon(Icons.point_of_sale_outlined, size: 18),
                      label: const AppText(ar: 'تسجيل بيع', en: 'Record sale'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PricePill extends StatelessWidget {
  const _PricePill({required this.label, required this.price, required this.currency, required this.date, required this.color, required this.icon});
  final String label;
  final double? price;
  final String? currency;
  final String? date;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).colorScheme.surfaceContainerHighest : color, borderRadius: BorderRadius.circular(13)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, size: 15), const SizedBox(width: 5), Flexible(child: Text(label, style: const TextStyle(fontSize: 12)))]),
            const SizedBox(height: 5),
            Text(price == null ? appTextValue('غير مسجل', 'Not recorded') : '${formatMoney(price)} ${currencyLabel(context, currency)}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (date != null) ...[
              const SizedBox(height: 3),
              Text(formatDate(date, Localizations.localeOf(context).languageCode), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      );
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.icon, required this.title, required this.message, required this.actionLabel, required this.onAction});
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 58, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(message, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5), textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton.icon(onPressed: onAction, icon: const Icon(Icons.arrow_forward), label: Text(actionLabel)),
            ],
          ),
        ),
      );
}

extension _NonEmptyString on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

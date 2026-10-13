import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/product.dart';
import '../utils/app_helpers.dart';
import 'price_entry_form_screen.dart';
import 'product_details_screen.dart';
import 'product_form_screen.dart';
import 'backup_restore_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  late Future<List<Map<String, Object?>>> _productsFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _productsFuture = AppDatabase.instance.searchProducts('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload([String? query]) {
    if (query != null) _query = query;
    setState(() => _productsFuture = AppDatabase.instance.searchProducts(_query));
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
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('مرجع أسعار الأصناف', style: TextStyle(fontWeight: FontWeight.w800)),
            Text('Buy Price Assistant GIMI', style: TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'النسخ الاحتياطي والاستعادة',
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const BackupRestoreScreen()),
              );
              if (mounted) _reload();
            },
            icon: const Icon(Icons.backup_outlined),
          ),
          IconButton(
            tooltip: 'إضافة صنف',
            onPressed: _addProduct,
            icon: const Icon(Icons.add_box_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addProduct,
        icon: const Icon(Icons.add),
        label: const Text('إضافة صنف'),
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
                      hintText: 'ابحث باسم الصنف أو الكود أو التصنيف',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? const Icon(Icons.search, color: Colors.black38)
                          : IconButton(
                              tooltip: 'مسح البحث',
                              onPressed: () {
                                _searchController.clear();
                                _reload('');
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.history, size: 18, color: colors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _query.trim().isEmpty
                              ? 'الأصناف المحفوظة'
                              : 'نتائج البحث عن: ${_query.trim()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _reload(),
                        icon: const Icon(Icons.refresh, size: 17),
                        label: const Text('تحديث'),
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
                      title: 'تعذر تحميل الأصناف',
                      message: 'تحقق من سلامة البيانات ثم أعد المحاولة.\n${snapshot.error}',
                      actionLabel: 'إعادة المحاولة',
                      onAction: () => _reload(),
                    );
                  }
                  final rows = snapshot.data ?? const <Map<String, Object?>>[];
                  if (rows.isEmpty) {
                    return _MessageState(
                      icon: _query.isEmpty ? Icons.inventory_2_outlined : Icons.search_off,
                      title: _query.isEmpty ? 'ابدأ بإضافة أول صنف' : 'لا توجد نتائج مطابقة',
                      message: _query.isEmpty
                          ? 'بعد تسجيل الصنف، أضف أسعار الشراء والبيع لتظهر هنا في أي وقت.'
                          : 'جرّب جزءًا آخر من الاسم أو الكود، أو أضف الصنف إن لم يكن مسجلًا.',
                      actionLabel: _query.isEmpty ? 'إضافة صنف' : 'مسح البحث',
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
                          [if ((product.code ?? '').isNotEmpty) 'الكود: ${product.code}', if ((product.category ?? '').isNotEmpty) product.category!]
                              .join(' • ')
                              .ifEmpty('الوحدة: ${product.unit}'),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: product.isFavorite ? 'إزالة من المفضلة' : 'إضافة إلى المفضلة',
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
                      label: 'آخر شراء',
                      price: product.latestPurchasePrice,
                      date: product.latestPurchaseDate,
                      color: const Color(0xFFEAF3FF),
                      icon: Icons.shopping_cart_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PricePill(
                      label: 'آخر بيع',
                      price: product.latestSalePrice,
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
                      label: const Text('تسجيل شراء'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: onSale,
                      icon: const Icon(Icons.point_of_sale_outlined, size: 18),
                      label: const Text('تسجيل بيع'),
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
  const _PricePill({required this.label, required this.price, required this.date, required this.color, required this.icon});
  final String label;
  final double? price;
  final String? date;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(13)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, size: 15), const SizedBox(width: 5), Flexible(child: Text(label, style: const TextStyle(fontSize: 12)))]),
            const SizedBox(height: 5),
            Text(price == null ? 'غير مسجل' : '${formatMoney(price)} ر.ي',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (date != null) ...[
              const SizedBox(height: 3),
              Text(formatDate(date), style: const TextStyle(fontSize: 11, color: Colors.black54)),
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
              Text(message, style: const TextStyle(color: Colors.black54, height: 1.5), textAlign: TextAlign.center),
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

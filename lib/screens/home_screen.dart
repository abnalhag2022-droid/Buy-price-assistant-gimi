import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/product.dart';
import '../ui/ui.dart';
import '../utils/app_info.dart';
import '../utils/app_text.dart';
import '../utils/error_messages.dart';
import 'backup_restore_screen.dart';
import 'data_exchange_screen.dart';
import 'price_entry_form_screen.dart';
import 'product_details_screen.dart';
import 'product_form_screen.dart';
import 'settings_screen.dart';
import 'support_screen.dart';

/// Search and browse products with their latest purchase and sale prices.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _Filters {
  const _Filters({this.category, this.brand, this.supplier});
  final String? category, brand, supplier;
  int get count => [category, brand, supplier].where((v) => v != null).length;
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _pageSize = 30;

  final _searchController = TextEditingController();
  final _scroll = ScrollController();

  String _query = '';
  _Filters _filters = const _Filters();
  bool _archived = false;

  final List<Product> _items = <Product>[];
  final Set<int> _notesMatches = <int>{};
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  int _request = 0;

  List<String> _categories = const <String>[];
  List<String> _brands = const <String>[];
  List<String> _suppliers = const <String>[];

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
  }

  /// Reloads the first page and the filter lists (they change after edits,
  /// imports and restores).
  Future<void> _reload() async {
    final request = ++_request;
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final db = AppDatabase.instance;
      final results = await Future.wait<Object>([
        db.searchProducts(_query, category: _filters.category, brand: _filters.brand, supplier: _filters.supplier,
            archived: _archived, limit: _pageSize),
        db.countProducts(_query, category: _filters.category, brand: _filters.brand, supplier: _filters.supplier,
            archived: _archived),
        db.getDistinctCategories(),
        db.getDistinctBrands(),
        db.getDistinctSuppliers(),
      ]);
      if (!mounted || request != _request) return;
      final rows = results[0] as List<Map<String, Object?>>;
      setState(() {
        _items
          ..clear()
          ..addAll(rows.map(Product.fromMap));
        _notesMatches
          ..clear()
          ..addAll(rows.where((r) => r['search_match_notes'] == 1).map((r) => r['id']! as int));
        _total = results[1] as int;
        _categories = results[2] as List<String>;
        _brands = results[3] as List<String>;
        _suppliers = results[4] as List<String>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _error != null) return;
    final request = _request;
    setState(() => _loadingMore = true);
    try {
      final rows = await AppDatabase.instance.searchProducts(_query,
          category: _filters.category, brand: _filters.brand, supplier: _filters.supplier,
          archived: _archived, limit: _pageSize, offset: _items.length);
      if (!mounted || request != _request) return;
      setState(() {
        _items.addAll(rows.map(Product.fromMap));
        _notesMatches.addAll(rows.where((r) => r['search_match_notes'] == 1).map((r) => r['id']! as int));
        if (rows.isEmpty) _total = _items.length;
      });
    } catch (error) {
      if (mounted) showMessage(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _search(String value) {
    if (value == _query) return;
    _query = value;
    _items.clear();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _reload();
  }

  void _applyFilters(_Filters filters, {bool? archived}) {
    setState(() {
      _filters = filters;
      if (archived != null) _archived = archived;
      _items.clear();
    });
    _reload();
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _reload();
  }

  Future<void> _addProduct() => _open(const ProductFormScreen());

  Future<void> _record(Product product, {required bool purchase}) =>
      _open(PriceEntryFormScreen(product: product, isPurchase: purchase));

  Future<void> _toggleFavorite(Product product, bool favorite) async {
    try {
      await AppDatabase.instance.setFavorite(product.id, favorite);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) showMessage(context, friendlyError(error));
    }
  }

  Future<void> _unarchive(Product product) async {
    try {
      await AppDatabase.instance.unarchiveProduct(product.id);
      if (!mounted) return;
      showMessage(context, appTextValue('أُعيد «${product.name}» إلى قائمة الأصناف.', '"${product.name}" is back in the item list.'));
      _reload();
    } catch (error) {
      if (mounted) showMessage(context, friendlyError(error));
    }
  }

  Future<void> _showFilters() async {
    final result = await showModalBottomSheet<_Filters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(
        initial: _filters,
        categories: _categories,
        brands: _brands,
        suppliers: _suppliers,
      ),
    );
    if (result != null) _applyFilters(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(appTextValue(AppInfo.nameAr, AppInfo.nameEn), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: appTextValue('إضافة صنف', 'Add item'),
            onPressed: _addProduct,
            icon: const Icon(Icons.add_box_outlined),
          ),
        ],
      ),
      drawer: _AppDrawer(onOpen: (screen) {
        Navigator.of(context).pop();
        _open(screen);
      }),
      floatingActionButton: _archived
          ? null
          : FloatingActionButton.extended(
              onPressed: _addProduct,
              icon: const Icon(Icons.add),
              label: Text(appTextValue('صنف جديد', 'New item')),
            ),
      body: PageBody(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
              child: DebouncedSearchField(
                controller: _searchController,
                onChanged: _search,
                hintText: appTextValue('ابحث بالاسم أو الكود أو المورد', 'Search name, code, supplier, price'),
              ),
            ),
            _FilterBar(
              filters: _filters,
              archived: _archived,
              onOpenFilters: _showFilters,
              onArchived: (value) => _applyFilters(_filters, archived: value),
              onClear: (filters) => _applyFilters(filters),
            ),
            Expanded(child: _results()),
          ],
        ),
      ),
    );
  }

  Widget _results() {
    if (_loading) return const LoadingState();
    if (_error != null) {
      return ErrorState(
        error: _error!,
        onRetry: _reload,
        title: appTextValue('تعذر تحميل الأصناف', 'Could not load the items'),
      );
    }
    final searching = _query.trim().isNotEmpty || _filters.count > 0;
    if (_items.isEmpty) {
      if (_archived) {
        return EmptyState(
          icon: Icons.inventory_2_outlined,
          title: appTextValue('لا توجد أصناف مؤرشفة', 'No archived items'),
          message: searching
              ? appTextValue('لا يطابق البحث أي صنف مؤرشف.', 'No archived item matches the search.')
              : appTextValue('الأصناف التي تؤرشفها تظهر هنا مع كامل سجلها، ويمكن إعادتها في أي وقت.',
                  'Items you archive appear here with their full history and can be restored at any time.'),
          actionLabel: appTextValue('عرض الأصناف النشطة', 'Show active items'),
          onAction: () => _applyFilters(_filters, archived: false),
        );
      }
      if (searching) {
        return EmptyState(
          icon: Icons.search_off,
          title: appTextValue('لا توجد نتائج', 'No results'),
          message: appTextValue(
            'جرّب جزءًا آخر من الاسم أو الكود، أو أزل عوامل التصفية. الأصناف المؤرشفة لا تظهر هنا.',
            'Try another part of the name or code, or remove filters. Archived items are not shown here.',
          ),
          actionLabel: appTextValue('مسح البحث والتصفية', 'Clear search and filters'),
          onAction: () {
            _searchController.clear();
            _query = '';
            _applyFilters(const _Filters());
          },
          secondaryLabel: appTextValue('إضافة صنف جديد', 'Add a new item'),
          onSecondary: _addProduct,
        );
      }
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: appTextValue('ابدأ بإضافة أول صنف', 'Add your first item'),
        message: appTextValue(
          'سجّل الصنف ثم أسعار شرائه وبيعه، لتجد آخر سعر في ثوانٍ. بياناتك تبقى على هذا الجهاز.',
          'Add an item, then its purchase and sale prices, to find the latest price in seconds. Your data stays on this device.',
        ),
        actionLabel: appTextValue('إضافة صنف', 'Add item'),
        onAction: _addProduct,
        secondaryLabel: appTextValue('استيراد من Excel أو CSV', 'Import from Excel or CSV'),
        onSecondary: () => _open(const DataExchangeScreen()),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, 96),
        itemCount: _items.length + 2,
        separatorBuilder: (_, index) => SizedBox(height: index == 0 ? Space.xs : Space.md),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Semantics(
              liveRegion: true,
              child: Text(productCountLabel(_total), style: context.text.labelLarge?.copyWith(color: context.colors.onSurfaceVariant)),
            );
          }
          if (index == _items.length + 1) {
            if (_loadingMore) {
              return const Padding(padding: EdgeInsets.all(Space.lg), child: LoadingState());
            }
            if (_hasMore) {
              return Center(
                child: TextButton(onPressed: _loadMore, child: Text(appTextValue('عرض المزيد', 'Show more'))),
              );
            }
            return const SizedBox.shrink();
          }
          final product = _items[index - 1];
          return ProductCard(
            product: product,
            matchFromNotes: _query.trim().isNotEmpty && _notesMatches.contains(product.id),
            onOpen: () => _open(ProductDetailsScreen(productId: product.id)),
            onFavorite: (favorite) => _toggleFavorite(product, favorite),
            onPurchase: () => _record(product, purchase: true),
            onSale: () => _record(product, purchase: false),
            onUnarchive: () => _unarchive(product),
          );
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filters,
    required this.archived,
    required this.onOpenFilters,
    required this.onArchived,
    required this.onClear,
  });

  final _Filters filters;
  final bool archived;
  final VoidCallback onOpenFilters;
  final ValueChanged<bool> onArchived;
  final ValueChanged<_Filters> onClear;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      FilterChip(
        avatar: const Icon(Icons.tune, size: Sizes.iconSm),
        label: Text(filters.count == 0
            ? appTextValue('تصفية', 'Filter')
            : appTextValue('تصفية (${filters.count})', 'Filter (${filters.count})')),
        selected: filters.count > 0,
        showCheckmark: false,
        onSelected: (_) => onOpenFilters(),
      ),
      FilterChip(
        avatar: const Icon(Icons.inventory_2_outlined, size: Sizes.iconSm),
        label: Text(appTextValue('المؤرشفة', 'Archived')),
        selected: archived,
        onSelected: onArchived,
      ),
      if (filters.category != null)
        InputChip(
          label: Text(localizeCatalogValue(context, filters.category!)),
          onDeleted: () => onClear(_Filters(brand: filters.brand, supplier: filters.supplier)),
          deleteButtonTooltipMessage: appTextValue('إزالة', 'Remove'),
        ),
      if (filters.brand != null)
        InputChip(
          label: Text(filters.brand!),
          onDeleted: () => onClear(_Filters(category: filters.category, supplier: filters.supplier)),
          deleteButtonTooltipMessage: appTextValue('إزالة', 'Remove'),
        ),
      if (filters.supplier != null)
        InputChip(
          label: Text(filters.supplier!),
          onDeleted: () => onClear(_Filters(category: filters.category, brand: filters.brand)),
          deleteButtonTooltipMessage: appTextValue('إزالة', 'Remove'),
        ),
    ];
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
        itemBuilder: (_, index) => chips[index],
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.categories, required this.brands, required this.suppliers});
  final _Filters initial;
  final List<String> categories, brands, suppliers;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _category = widget.initial.category;
  late String? _brand = widget.initial.brand;
  late String? _supplier = widget.initial.supplier;

  Widget _dropdown({
    required String label,
    required String allLabel,
    required List<String> values,
    required String? value,
    required ValueChanged<String?> onChanged,
    String Function(String value)? display,
  }) {
    final options = <String>{...values, ?value}.toList();
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(allLabel)),
        for (final option in options)
          DropdownMenuItem<String?>(value: option, child: Text(display?.call(option) ?? option, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg + MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(appTextValue('تصفية الأصناف', 'Filter items'), style: context.text.titleLarge),
                const SizedBox(height: Space.lg),
                _dropdown(
                  label: appTextValue('التصنيف', 'Category'),
                  allLabel: appTextValue('كل التصنيفات', 'All categories'),
                  values: widget.categories,
                  value: _category,
                  display: (v) => localizeCatalogValue(context, v),
                  onChanged: (v) => setState(() => _category = v),
                ),
                const SizedBox(height: Space.md),
                _dropdown(
                  label: appTextValue('العلامة التجارية', 'Brand'),
                  allLabel: appTextValue('كل العلامات', 'All brands'),
                  values: widget.brands,
                  value: _brand,
                  onChanged: (v) => setState(() => _brand = v),
                ),
                const SizedBox(height: Space.md),
                _dropdown(
                  label: appTextValue('اشتُري من المورد', 'Bought from supplier'),
                  allLabel: appTextValue('كل الموردين', 'All suppliers'),
                  values: widget.suppliers,
                  value: _supplier,
                  onChanged: (v) => setState(() => _supplier = v),
                ),
                const SizedBox(height: Space.xl),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(const _Filters()),
                      child: Text(appTextValue('مسح الكل', 'Clear all')),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_Filters(category: _category, brand: _brand, supplier: _supplier)),
                      child: Text(appTextValue('تطبيق', 'Apply')),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      );
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({required this.onOpen});
  final ValueChanged<Widget> onOpen;

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String ar, String en, Widget screen) => ListTile(
          leading: Icon(icon),
          title: Text(appTextValue(ar, en)),
          onTap: () => onOpen(screen),
        );
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.lg),
              color: BrandColors.navy,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(color: BrandColors.gold, shape: BoxShape.circle),
                  child: const Icon(Icons.receipt_long_rounded, color: BrandColors.navy),
                ),
                const SizedBox(height: Space.md),
                Text(appTextValue(AppInfo.nameAr, AppInfo.nameEn),
                    style: context.text.titleLarge?.copyWith(color: Colors.white)),
                const SizedBox(height: Space.xs),
                Text(
                  appTextValue('أسعار الشراء والبيع · يعمل دون إنترنت', 'Purchase and sale prices · Works offline'),
                  style: context.text.bodySmall?.copyWith(color: Colors.white70),
                ),
              ]),
            ),
            const SizedBox(height: Space.sm),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(appTextValue('الأصناف', 'Items')),
              selected: true,
              onTap: () => Navigator.of(context).pop(),
            ),
            item(Icons.import_export_rounded, 'استيراد وتصدير Excel وCSV', 'Excel and CSV import/export', const DataExchangeScreen()),
            item(Icons.backup_outlined, 'النسخ الاحتياطي والاستعادة', 'Backup and restore', const BackupRestoreScreen()),
            item(Icons.settings_outlined, 'الإعدادات', 'Settings', const SettingsScreen()),
            item(Icons.support_agent_rounded, 'الدعم وحول التطبيق', 'Support and about', const SupportScreen()),
          ],
        ),
      ),
    );
  }
}

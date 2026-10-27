import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../utils/app_helpers.dart';
import '../../utils/app_text.dart';
import '../app_theme.dart';
import '../tokens.dart';
import 'meta_chip.dart';
import 'price_tile.dart';
import 'record_buttons.dart';

/// One product in the search results: identity, latest purchase and sale
/// prices, and the quick actions for recording a new price.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onOpen,
    required this.onFavorite,
    this.onPurchase,
    this.onSale,
    this.onUnarchive,
    this.matchFromNotes = false,
  });

  final Product product;
  final bool matchFromNotes;
  final VoidCallback onOpen;
  final ValueChanged<bool> onFavorite;
  final VoidCallback? onPurchase;
  final VoidCallback? onSale;
  final VoidCallback? onUnarchive;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final meta = <Widget>[
      if ((p.code ?? '').isNotEmpty) MetaChip(label: p.code!, icon: Icons.qr_code_2, ltr: true, tooltip: appTextValue('الكود', 'Code')),
      if ((p.category ?? '').isNotEmpty) MetaChip(label: localizeCatalogValue(context, p.category!), icon: Icons.category_outlined),
      if ((p.brand ?? '').isNotEmpty) MetaChip(label: p.brand!, icon: Icons.business_outlined),
      MetaChip(label: localizeCatalogValue(context, p.unit), icon: Icons.straighten),
    ];
    final purchase = PriceTile(
      kind: PriceKind.purchase,
      price: p.latestPurchasePrice,
      currency: p.latestPurchaseCurrency,
      date: p.latestPurchaseDate,
      party: p.latestPurchaseSupplier,
    );
    final sale = PriceTile(
      kind: PriceKind.sale,
      price: p.latestSalePrice,
      currency: p.latestSaleCurrency,
      date: p.latestSaleDate,
      party: p.latestSaleCustomer,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(Space.lg, Space.md, Space.xs, Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: Space.xs),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
                        const SizedBox(height: Space.xs + 2),
                        Wrap(spacing: Space.xs + 2, runSpacing: Space.xs + 2, children: meta),
                      ]),
                    ),
                  ),
                  if (!p.isArchived)
                    IconButton(
                      tooltip: p.isFavorite
                          ? appTextValue('إزالة من المفضلة', 'Remove from favorites')
                          : appTextValue('إضافة إلى المفضلة', 'Add to favorites'),
                      isSelected: p.isFavorite,
                      onPressed: () => onFavorite(!p.isFavorite),
                      icon: Icon(Icons.star_border_rounded, color: context.colors.onSurfaceVariant),
                      selectedIcon: Icon(Icons.star_rounded, color: context.palette.favorite),
                    ),
                ],
              ),
              if (matchFromNotes) ...[
                const SizedBox(height: Space.sm),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: MetaChip(label: appTextValue('وُجدت الكلمة في الملاحظات', 'Found in notes'), icon: Icons.sticky_note_2_outlined),
                ),
              ],
              const SizedBox(height: Space.md),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: Space.md),
                child: LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth >= 250
                      ? IntrinsicHeight(
                          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Expanded(child: purchase),
                            const SizedBox(width: Space.sm),
                            Expanded(child: sale),
                          ]),
                        )
                      : Column(children: [purchase, const SizedBox(height: Space.sm), sale]),
                ),
              ),
              const SizedBox(height: Space.sm),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: Space.md),
                child: p.isArchived
                    ? Row(children: [
                        Icon(Icons.inventory_2_outlined, size: Sizes.iconMd, color: context.colors.onSurfaceVariant),
                        const SizedBox(width: Space.xs),
                        Expanded(child: Text(appTextValue('مؤرشف', 'Archived'), style: context.text.labelLarge)),
                        if (onUnarchive != null)
                          TextButton.icon(
                            onPressed: onUnarchive,
                            icon: const Icon(Icons.unarchive_outlined),
                            label: Text(appTextValue('إلغاء الأرشفة', 'Restore')),
                          ),
                      ])
                    : RecordButtons(onPurchase: onPurchase, onSale: onSale, short: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Formats the count line under the search box.
String productCountLabel(int count) =>
    appTextValue('عدد الأصناف: ${ltrIsolate('$count')}', count == 1 ? '1 item' : '$count items');

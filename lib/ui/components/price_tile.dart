import 'package:flutter/material.dart';

import '../../utils/app_helpers.dart';
import '../../utils/app_text.dart';
import '../app_theme.dart';
import '../tokens.dart';

enum PriceKind { purchase, sale }

/// The latest purchase or sale price of a product with its date, party and
/// quantity. Shows "no price recorded" when there is no record: a price is
/// never estimated or carried over from the other kind.
class PriceTile extends StatelessWidget {
  const PriceTile({
    super.key,
    required this.kind,
    required this.price,
    required this.currency,
    this.date,
    this.party,
    this.quantity,
    this.unit,
    this.large = false,
  });

  final PriceKind kind;
  final double? price;
  final String? currency;
  final String? date;
  final String? party;
  final double? quantity;
  final String? unit;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final purchase = kind == PriceKind.purchase;
    final background = purchase ? palette.purchaseContainer : palette.saleContainer;
    final foreground = purchase ? palette.onPurchaseContainer : palette.onSaleContainer;
    final label = purchase ? appTextValue('آخر شراء', 'Latest purchase') : appTextValue('آخر بيع', 'Latest sale');
    final language = Localizations.localeOf(context).languageCode;
    final details = <String>[
      if (date != null) formatDate(date, language),
      if (party != null && party!.isNotEmpty) party!,
    ];
    final quantityText = quantity == null
        ? null
        : appTextValue(
            'الكمية ${ltrIsolate(formatQuantity(quantity))}${unit == null ? '' : ' ${localizeCatalogValue(context, unit!)}'}',
            'Qty ${formatQuantity(quantity)}${unit == null ? '' : ' ${localizeCatalogValue(context, unit!)}'}',
          );
    final semantic = price == null
        ? '$label: ${appTextValue('لا يوجد سعر مسجل', 'no price recorded')}'
        : '$label: ${formatAmount(context, price!, currency)}${details.isEmpty ? '' : ', ${details.join(', ')}'}';

    return Semantics(
      container: true,
      label: semantic,
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.all(large ? Space.lg : Space.md),
        decoration: BoxDecoration(color: background, borderRadius: Radii.tile),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(purchase ? Icons.shopping_cart_outlined : Icons.sell_outlined, size: Sizes.iconSm, color: foreground),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: context.text.labelMedium?.copyWith(color: foreground)),
              ),
            ]),
            const SizedBox(height: Space.xs),
            if (price == null)
              Text(
                appTextValue('لا يوجد سعر مسجل', 'No price recorded'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodyMedium?.copyWith(color: foreground, fontStyle: FontStyle.italic),
              )
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: ltrIsolate(formatMoney(price)),
                      style: (large ? context.text.headlineSmall : context.text.titleLarge)
                          ?.copyWith(color: foreground, fontWeight: FontWeight.w800, fontFeatures: tabularFigures),
                    ),
                    TextSpan(
                      text: ' ${currencyLabel(context, currency)}',
                      style: context.text.labelLarge?.copyWith(color: foreground),
                    ),
                  ]),
                  maxLines: 1,
                ),
              ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(details.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(color: foreground)),
            ],
            if (large && quantityText != null)
              Text(quantityText, style: context.text.bodySmall?.copyWith(color: foreground)),
          ],
        ),
      ),
    );
  }
}

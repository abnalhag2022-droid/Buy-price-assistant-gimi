import 'package:flutter/material.dart';

import '../../utils/app_text.dart';
import '../app_theme.dart';
import '../tokens.dart';

/// "Record purchase" and "Record sale" buttons in the purchase and sale
/// colours used by the price tiles, so the action matches what it records.
class RecordButtons extends StatelessWidget {
  const RecordButtons({super.key, required this.onPurchase, required this.onSale, this.filled = false, this.short = false});

  final VoidCallback? onPurchase;
  final VoidCallback? onSale;

  /// Filled on the details screen, outlined in lists.
  final bool filled;

  /// "Purchase"/"Sale" instead of "Record purchase"/"Record sale".
  final bool short;

  Widget _button(BuildContext context, {required bool purchase}) {
    final palette = context.palette;
    final color = purchase ? palette.purchase : palette.sale;
    final onColor = purchase ? palette.onPurchase : palette.onSale;
    final label = purchase
        ? (short ? appTextValue('شراء', 'Purchase') : appTextValue('تسجيل شراء', 'Record purchase'))
        : (short ? appTextValue('بيع', 'Sale') : appTextValue('تسجيل بيع', 'Record sale'));
    final icon = Icon(purchase ? Icons.add_shopping_cart : Icons.point_of_sale_outlined, size: Sizes.iconMd);
    final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
    final onPressed = purchase ? onPurchase : onSale;
    return filled
        ? FilledButton.icon(
            onPressed: onPressed,
            style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: onColor),
            icon: icon,
            label: text,
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color.withValues(alpha: 0.6))),
            icon: icon,
            label: text,
          );
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: _button(context, purchase: true)),
        const SizedBox(width: Space.sm),
        Expanded(child: _button(context, purchase: false)),
      ]);
}

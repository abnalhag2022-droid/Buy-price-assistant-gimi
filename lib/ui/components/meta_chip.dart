import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../tokens.dart';

/// Small label for a product attribute (code, category, brand, unit).
class MetaChip extends StatelessWidget {
  const MetaChip({super.key, required this.label, this.icon, this.ltr = false, this.tooltip});

  final String label;
  final IconData? icon;

  /// Codes and model numbers keep left-to-right order inside Arabic text.
  final bool ltr;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 3),
      decoration: BoxDecoration(color: context.colors.surfaceContainerHigh, borderRadius: Radii.chip),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: context.colors.onSurfaceVariant),
          const SizedBox(width: Space.xs),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: ltr ? TextDirection.ltr : null,
            style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ),
      ]),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

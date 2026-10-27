import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../tokens.dart';

enum NoticeKind { info, warning, error, success }

/// An inline message with an icon; never relies on colour alone.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key, required this.text, this.kind = NoticeKind.info, this.action, this.margin});

  final String text;
  final NoticeKind kind;
  final Widget? action;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final colors = context.colors;
    final (Color background, Color foreground, IconData icon) = switch (kind) {
      NoticeKind.info => (palette.infoContainer, palette.onInfoContainer, Icons.info_outline),
      NoticeKind.warning => (palette.warningContainer, palette.onWarningContainer, Icons.warning_amber_rounded),
      NoticeKind.error => (colors.errorContainer, colors.onErrorContainer, Icons.error_outline),
      NoticeKind.success => (palette.successContainer, palette.onSuccessContainer, Icons.check_circle_outline),
    };
    return Container(
      margin: margin ?? const EdgeInsets.only(top: Space.sm),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(color: background, borderRadius: Radii.tile),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: Sizes.iconMd, color: foreground),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: context.text.bodyMedium?.copyWith(color: foreground)),
                if (action != null) Align(alignment: AlignmentDirectional.centerEnd, child: action),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

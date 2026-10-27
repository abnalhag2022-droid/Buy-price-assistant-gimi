import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../tokens.dart';

/// A titled card that groups related content on a screen.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(Space.lg),
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: context.colors.primary, size: Sizes.iconLg),
                    const SizedBox(width: Space.sm),
                  ],
                  Expanded(
                    child: Semantics(header: true, child: Text(title, style: context.text.titleMedium)),
                  ),
                  ?trailing,
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: Space.xs),
                Text(subtitle!, style: context.text.bodySmall),
              ],
              const SizedBox(height: Space.md),
              ...children,
            ],
          ),
        ),
      );
}

/// Heading between groups of content inside a scrolling screen.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.xl, bottom: Space.sm),
        child: Row(children: [
          Expanded(child: Semantics(header: true, child: Text(title, style: context.text.titleMedium))),
          ?trailing,
        ]),
      );
}

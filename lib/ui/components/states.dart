import 'package:flutter/material.dart';

import '../../utils/app_text.dart';
import '../../utils/error_messages.dart';
import '../app_theme.dart';
import '../tokens.dart';

/// Centered message for an empty list or a finished task.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: context.palette.infoContainer, shape: BoxShape.circle),
                  child: Icon(icon, size: 36, color: context.palette.onInfoContainer),
                ),
                const SizedBox(height: Space.lg),
                Text(title, style: context.text.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: Space.sm),
                Text(message, style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant), textAlign: TextAlign.center),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: Space.xl),
                  FilledButton(onPressed: onAction, child: Text(actionLabel!)),
                ],
                if (secondaryLabel != null && onSecondary != null) ...[
                  const SizedBox(height: Space.sm),
                  TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
                ],
              ],
            ),
          ),
        ),
      );
}

/// Shows a failed load with a friendly message (never raw exception text).
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, required this.onRetry, this.title});

  final Object error;
  final VoidCallback onRetry;
  final String? title;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: context.colors.error),
                const SizedBox(height: Space.md),
                Text(
                  title ?? appTextValue('تعذر تحميل البيانات', 'Could not load the data'),
                  style: context.text.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Space.sm),
                Text(friendlyError(error), textAlign: TextAlign.center, style: context.text.bodyMedium),
                const SizedBox(height: Space.lg),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const AppText(ar: 'إعادة المحاولة', en: 'Try again'),
                ),
              ],
            ),
          ),
        ),
      );
}

class LoadingState extends StatelessWidget {
  const LoadingState({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
          label: appTextValue('جارٍ التحميل', 'Loading'),
          child: const CircularProgressIndicator(),
        ),
      );
}

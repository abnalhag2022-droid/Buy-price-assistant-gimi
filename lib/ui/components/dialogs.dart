import 'package:flutter/material.dart';

import '../../utils/app_text.dart';
import '../app_theme.dart';

/// Asks before an action; destructive actions use the error colour.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
  String? cancelLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          child: Text(cancelLabel ?? appTextValue('إلغاء', 'Cancel')),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: dialog.colors.error, foregroundColor: dialog.colors.onError)
              : null,
          onPressed: () => Navigator.of(dialog).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Used by forms before leaving with unsaved changes.
Future<bool> confirmDiscardChanges(BuildContext context) => showConfirmDialog(
      context,
      title: appTextValue('تجاهل التغييرات؟', 'Discard changes?'),
      message: appTextValue('لم تُحفظ التغييرات التي أدخلتها. هل تريد الخروج دون حفظ؟', 'Your changes are not saved. Leave without saving?'),
      confirmLabel: appTextValue('خروج دون حفظ', 'Discard'),
      cancelLabel: appTextValue('متابعة التعديل', 'Keep editing'),
      destructive: true,
    );

void showMessage(BuildContext context, String text) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

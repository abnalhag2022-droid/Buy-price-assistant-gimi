import 'dart:io';

import 'package:sqflite_common/sqlite_api.dart';

import 'app_text.dart';

/// An error whose message is already written for the user, in both languages.
class UserFacingException implements Exception {
  const UserFacingException(this.ar, this.en);
  final String ar;
  final String en;

  @override
  String toString() => ar;
}

/// Converts any error into a short message for the user. Raw exception class
/// names and stack details are never shown; app errors keep their wording.
String friendlyError(Object error) {
  if (error is UserFacingException) return appTextValue(error.ar, error.en);
  if (error is FormatException) return error.message;
  if (error is StateError) return error.message;
  if (error is ArgumentError) {
    final message = error.message;
    if (message is String && message.isNotEmpty) return message;
  }
  if (error is DatabaseException) {
    if (error.isUniqueConstraintError() || error.toString().contains('CHECK constraint')) {
      return appTextValue('رُفضت البيانات لأنها لا تطابق قواعد الحفظ.', 'The data was rejected because it breaks a storage rule.');
    }
    return appTextValue('تعذر الوصول إلى قاعدة البيانات. لم تُحفظ التغييرات.', 'The database could not be accessed. Changes were not saved.');
  }
  if (error is FileSystemException) {
    return appTextValue('تعذر قراءة الملف أو كتابته.', 'The file could not be read or written.');
  }
  final text = error.toString();
  // Messages written by this app (Arabic) are safe to show as they are.
  if (RegExp('[؀-ۿ]').hasMatch(text) && !text.contains('Exception:')) return text;
  return appTextValue('حدث خطأ غير متوقع. حاول مرة أخرى.', 'Something went wrong. Please try again.');
}

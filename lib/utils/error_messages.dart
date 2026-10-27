import 'dart:io';

import 'package:sqflite_common/sqlite_api.dart';

import 'app_text.dart';
import 'error_log.dart';
import 'localized_message.dart';

/// An error whose message is already written for the user, in both languages.
class UserFacingException implements Exception, LocalizedMessage {
  const UserFacingException(this.ar, this.en);
  @override
  final String ar;
  @override
  final String en;

  @override
  String toString() => ar;
}

/// Converts any error into a short message for the user. App errors carry
/// their own Arabic and English wording ([LocalizedMessage]); raw exception
/// text and stack details are never shown. Database, file and unexpected
/// errors are added to the [ErrorLog] so the details can be copied from the
/// support screen.
String friendlyError(Object error) {
  if (error is LocalizedMessage) return appTextValue(error.ar, error.en);
  ErrorLog.instance.record(error, null);
  if (error is DatabaseException) {
    if (error.isUniqueConstraintError() || error.toString().contains('CHECK constraint')) {
      return appTextValue('رُفضت البيانات لأنها لا تطابق قواعد الحفظ.', 'The data was rejected because it breaks a storage rule.');
    }
    return appTextValue('تعذر الوصول إلى قاعدة البيانات. لم تُحفظ التغييرات.', 'The database could not be accessed. Changes were not saved.');
  }
  if (error is FileSystemException) {
    return appTextValue('تعذر قراءة الملف أو كتابته.', 'The file could not be read or written.');
  }
  return appTextValue('حدث خطأ غير متوقع. حاول مرة أخرى.', 'Something went wrong. Please try again.');
}

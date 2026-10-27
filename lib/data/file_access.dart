import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../utils/localized_message.dart';

class PickedFile {
  const PickedFile({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

/// The only place that talks to the system file picker, so screens stay
/// independent of the plugin's API. Files are chosen by the user through the
/// Android document picker; the app needs no storage permission.
class FileAccess {
  const FileAccess();

  static FileAccess instance = const FileAccess();

  static const Map<String, String> _mimeTypes = <String, String>{
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'csv': 'text/csv',
    'json': 'application/json',
  };

  /// Returns null when the user cancels. Files larger than [maxBytes] are
  /// refused before they are read into memory when the size is known.
  Future<PickedFile?> pickFile({required List<String> extensions, required int maxBytes, String? dialogTitle}) async {
    final file = await FilePicker.pickFile(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (file == null) return null;
    final size = file.lengthSync() ?? await file.length();
    if (size != null && size > maxBytes) throw _tooLarge(maxBytes);
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on Exception {
      throw const LocalizedFormatException('تعذر قراءة الملف المختار.', 'The selected file could not be read.');
    }
    if (bytes.length > maxBytes) throw _tooLarge(maxBytes);
    return PickedFile(name: file.name, bytes: bytes);
  }

  LocalizedFormatException _tooLarge(int maxBytes) {
    final megabytes = (maxBytes / (1024 * 1024)).round();
    return LocalizedFormatException('حجم الملف أكبر من $megabytes ميغابايت.', 'The file is larger than $megabytes MB.');
  }

  /// Asks the user where to save [bytes]. Returns false when cancelled.
  Future<bool> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String extension,
    String? dialogTitle,
  }) async {
    final uri = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      bytes: bytes,
      mimeType: _mimeTypes[extension] ?? 'application/octet-stream',
    );
    return uri != null;
  }
}

/// "20261027_1530" for file names.
String fileStamp([DateTime? time]) {
  final now = time ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
}

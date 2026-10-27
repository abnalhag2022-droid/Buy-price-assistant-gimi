import 'dart:io';
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

  /// Returns null when the user cancels. Files larger than [maxBytes] are
  /// refused before they are read into memory.
  Future<PickedFile?> pickFile({required List<String> extensions, required int maxBytes, String? dialogTitle}) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: extensions,
      allowMultiple: false,
      withData: false,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    if (file.size > maxBytes) {
      final megabytes = (maxBytes / (1024 * 1024)).round();
      throw LocalizedFormatException(
        'حجم الملف أكبر من $megabytes ميغابايت.',
        'The file is larger than $megabytes MB.',
      );
    }
    final Uint8List bytes;
    if (file.bytes != null) {
      bytes = file.bytes!;
    } else if (file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    } else {
      throw const LocalizedFormatException('تعذر قراءة الملف المختار.', 'The selected file could not be read.');
    }
    return PickedFile(name: file.name, bytes: bytes);
  }

  /// Asks the user where to save [bytes]. Returns false when cancelled.
  Future<bool> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String extension,
    String? dialogTitle,
  }) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: bytes,
    );
    return path != null;
  }
}

/// "20261027_1530" for file names.
String fileStamp([DateTime? time]) {
  final now = time ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
}

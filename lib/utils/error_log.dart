import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import 'app_info.dart';

class ErrorLogEntry {
  const ErrorLogEntry({required this.time, required this.source, required this.message, this.stack});

  final DateTime time;

  /// Where it was caught: 'flutter' (framework), 'async' (uncaught) or 'handled'.
  final String source;
  final String message;
  final String? stack;

  Map<String, Object?> toJson() => {
        'time': time.toIso8601String(),
        'source': source,
        'message': message,
        if (stack != null) 'stack': stack,
      };

  static ErrorLogEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final time = DateTime.tryParse(json['time']?.toString() ?? '');
    final message = json['message'];
    if (time == null || message is! String) return null;
    return ErrorLogEntry(
      time: time,
      source: json['source']?.toString() ?? 'app',
      message: message,
      stack: json['stack'] as String?,
    );
  }
}

/// Unexpected errors kept on the device so the user can copy them into a
/// support message. Nothing is sent anywhere automatically. The log keeps the
/// newest [maxEntries] entries in app-private storage and can be cleared.
class ErrorLog {
  ErrorLog({Future<String> Function()? directoryProvider})
      : _directoryProvider = directoryProvider ?? sqflite.getDatabasesPath;

  static final ErrorLog instance = ErrorLog();

  static const int maxEntries = 30;
  static const int _maxStackLines = 12;
  static const int _maxMessageLength = 600;

  final Future<String> Function() _directoryProvider;
  final List<ErrorLogEntry> _entries = <ErrorLogEntry>[];
  Future<void> _pendingWrite = Future<void>.value();

  /// Newest first.
  List<ErrorLogEntry> get entries => List<ErrorLogEntry>.unmodifiable(_entries.reversed);

  Future<File> _file() async => File(p.join(await _directoryProvider(), 'error_log.json'));

  /// Loads the saved log. A missing or damaged file is ignored: the log must
  /// never stop the app from starting.
  Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return;
      _entries
        ..clear()
        ..addAll(decoded.map(ErrorLogEntry.fromJson).whereType<ErrorLogEntry>());
    } catch (_) {
      _entries.clear();
    }
  }

  /// Adds an entry and saves the log in the background. Never throws.
  Future<void> record(Object error, StackTrace? stack, {String source = 'handled'}) {
    var message = '${error.runtimeType}: $error';
    if (message.length > _maxMessageLength) message = '${message.substring(0, _maxMessageLength)}…';
    final stackText = stack
        ?.toString()
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .take(_maxStackLines)
        .join('\n');
    _entries.add(ErrorLogEntry(time: DateTime.now(), source: source, message: message, stack: stackText));
    if (_entries.length > maxEntries) _entries.removeRange(0, _entries.length - maxEntries);
    return _queueSave();
  }

  Future<void> clear() {
    _entries.clear();
    return _queueSave();
  }

  Future<void> _queueSave() => _pendingWrite = _pendingWrite.then((_) => _save()).catchError((Object _) {});

  Future<void> _save() async {
    final file = await _file();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(_entries.map((e) => e.toJson()).toList()), flush: true);
    await temp.rename(file.path);
  }

  /// Plain text the user can paste into a support message.
  String report({String? language}) {
    final buffer = StringBuffer()
      ..writeln('${AppInfo.nameEn} ${AppInfo.versionLabel}')
      ..writeln('${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    if (language != null) buffer.writeln('language: $language');
    if (_entries.isEmpty) {
      buffer.writeln('no errors recorded');
      return buffer.toString();
    }
    for (final entry in entries) {
      buffer
        ..writeln('---')
        ..writeln('${entry.time.toIso8601String()} [${entry.source}] ${entry.message}');
      if (entry.stack != null) buffer.writeln(entry.stack);
    }
    return buffer.toString();
  }
}

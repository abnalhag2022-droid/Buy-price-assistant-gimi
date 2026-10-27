import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:buy_price_assistant_gimi/utils/app_info.dart';
import 'package:buy_price_assistant_gimi/utils/error_log.dart';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('gimi_errors_'));
  tearDown(() async => dir.delete(recursive: true));

  ErrorLog newLog() => ErrorLog(directoryProvider: () async => dir.path);

  test('keeps errors across restarts, newest first, up to the limit', () async {
    final log = newLog();
    for (var i = 0; i < ErrorLog.maxEntries + 5; i++) {
      await log.record(StateError('error $i'), StackTrace.current, source: 'flutter');
    }
    final reloaded = newLog();
    await reloaded.load();
    expect(reloaded.entries, hasLength(ErrorLog.maxEntries));
    expect(reloaded.entries.first.message, contains('error ${ErrorLog.maxEntries + 4}'));
    expect(reloaded.entries.first.stack, isNotNull);
    expect(reloaded.entries.first.source, 'flutter');
  });

  test('the report names the app version and every entry; clear empties it', () async {
    final log = newLog();
    await log.record(const FormatException('bad'), null);
    final report = log.report(language: 'ar');
    expect(report, contains(AppInfo.versionLabel));
    expect(report, contains('FormatException'));
    await log.clear();
    final reloaded = newLog();
    await reloaded.load();
    expect(reloaded.entries, isEmpty);
    expect(log.report(), contains('no errors recorded'));
  });

  test('a damaged log file does not stop loading', () async {
    await File('${dir.path}/error_log.json').writeAsString('{not json');
    final log = newLog();
    await log.load();
    expect(log.entries, isEmpty);
    await log.record(Exception('after damage'), null);
    expect(log.entries, hasLength(1));
  });

  test('recording never throws, even when the log cannot be saved', () async {
    final log = ErrorLog(directoryProvider: () async => throw const FileSystemException('read-only'));
    await expectLater(log.record(Exception('x'), null), completes);
    expect(log.entries, hasLength(1));
  });
}

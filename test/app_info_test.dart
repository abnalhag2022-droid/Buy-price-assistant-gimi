import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:buy_price_assistant_gimi/utils/app_info.dart';

void main() {
  test('the version shown in the app is the one Android installs (pubspec.yaml)', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(version, '${AppInfo.version}+${AppInfo.buildNumber}');
  });
}

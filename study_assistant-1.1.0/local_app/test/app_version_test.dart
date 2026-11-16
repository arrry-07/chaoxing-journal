import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/app_version.dart';

void main() {
  test('experience and exam lifecycle release uses frozen version', () {
    expect(AppVersion.name, '1.8.05');
    expect(AppVersion.code, 72);
  });

  test('AppVersion matches pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*([^+\s]+)\+(\d+)\s*$', multiLine: true)
        .firstMatch(pubspec);

    expect(match, isNotNull);
    expect(AppVersion.name, match!.group(1));
    expect(AppVersion.code, int.parse(match.group(2)!));
  });
}

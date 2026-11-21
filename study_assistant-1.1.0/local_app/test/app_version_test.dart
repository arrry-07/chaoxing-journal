import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/app_version.dart';

void main() {
  test('AppVersion matches pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version: (\d+\.\d+\.\d+(?:-dev\.[1-9]\d*)?)\+([1-9]\d*)$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull);
    expect(AppVersion.name, match!.group(1));
    expect(AppVersion.code, int.parse(match.group(2)!));
    expect(AppVersion.releaseName, match.group(1)!.split('-').first);
  });
}

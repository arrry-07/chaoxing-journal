import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/demo_main.dart';

void main() {
  test(
    'four synthetic courses, twelve stable assignments, fresh sync',
    () async {
      final client = DemoClient();
      final first = await client.fetchAssignments();
      final second = await client.fetchAssignments();
      expect(client.courses.length, 4);
      expect(client.succeededCourses, 4);
      expect(client.failedCourses, 0);
      expect(client.issues, isEmpty);
      expect(first.length, 12);
      expect(first.map((a) => a.id), second.map((a) => a.id));
      expect(first.map((a) => a.courseKey).toSet().length, 4);
      expect(first.where((a) => a.deadlineReadFailed).length, 1);
      expect(first.where((a) => a.status == 'submitted').length, 3);
      expect(
        first.any((a) => a.deadlineAt?.isBefore(DateTime.now()) ?? false),
        true,
      );
      expect(first.every((a) => a.submitUrl == null), true);
      expect(client.needsSessionInitialization, false);
    },
  );
  test('recording environment refuses network clients', () {
    final old = HttpOverrides.current;
    HttpOverrides.global = NoNetwork();
    try {
      expect(() => HttpClient(), throwsStateError);
    } finally {
      HttpOverrides.global = old;
    }
  });
}

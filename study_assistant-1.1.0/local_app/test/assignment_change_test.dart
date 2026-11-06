import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/assignment_change.dart';
import 'package:study_assistant_mobile/src/services/assignment_change_log.dart';

Assignment row(String id,
        {String status = 'pending', DateTime? due, bool trusted = true}) =>
    Assignment(
        id: id,
        title: '样例作业',
        courseName: '样例课程',
        requirementsText: '',
        status: status,
        deadlineAt: due,
        deadlineTrusted: trusted,
        lastSyncedAt: DateTime.utc(2026));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'partial empty read and return checks do not establish a complete baseline',
      () async {
    final log = AssignmentChangeLog();
    await log.record([], [], {}, completeSync: false);
    await log.record([], [row('1')], {'1'}, completeSync: false);
    expect(await log.load(), isEmpty);
    await log.record([row('1')], [row('1'), row('2')], {'1', '2'});
    expect(await log.load(), isEmpty);
    await log.record(
        [row('1'), row('2')], [row('1'), row('2'), row('3')], {'3'},
        completeSync: false);
    expect((await log.load()).single.assignmentId, '3');
  });
  test('upgrade with existing records still establishes a quiet first baseline',
      () async {
    final log = AssignmentChangeLog();
    await log.record([row('1')], [row('1'), row('2')], {'1', '2'});
    expect(await log.load(), isEmpty);
  });
  test('first sync establishes baseline and later new work is recorded',
      () async {
    final log = AssignmentChangeLog();
    await log.record([], [row('1')], {'1'});
    expect(await log.load(), isEmpty);
    await log.record([row('1')], [row('1'), row('2')], {'1', '2'});
    expect((await log.load()).single.kind, AssignmentChangeKind.published);
  });
  test(
      'records trusted deadline and status changes, not missing or unknown rows',
      () {
    final old = [row('1', due: DateTime.utc(2026, 11, 8)), row('2')];
    final now = [
      row('1', status: 'submitted', due: DateTime.utc(2026, 11, 9)),
      row('2', status: 'unknown')
    ];
    final changes =
        AssignmentChange.compare(old, now, {'1', '2'}, DateTime.utc(2026));
    expect(changes.map((c) => c.kind),
        [AssignmentChangeKind.deadline, AssignmentChangeKind.status]);
    expect(AssignmentChange.compare(old, [], {}, DateTime.utc(2026)), isEmpty);
  });
  test('untrusted or failed deadline is never reported as a teacher change',
      () {
    expect(
        AssignmentChange.compare(
            [row('1', trusted: false)],
            [row('1', due: DateTime.utc(2026, 11, 8))],
            {'1'},
            DateTime.utc(2026)),
        isEmpty);
  });
}

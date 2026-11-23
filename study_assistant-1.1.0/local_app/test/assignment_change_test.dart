import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/assignment_change.dart';
import 'package:study_assistant_mobile/src/services/assignment_change_log.dart';

Assignment row(String id,
        {String status = 'pending',
        DateTime? due,
        bool trusted = true,
        bool readFailed = false,
        String? rawText,
        DateTime? lastSyncedAt}) =>
    Assignment(
        id: id,
        title: '样例作业',
        courseName: '样例课程',
        requirementsText: '',
        status: status,
        deadlineAt: due,
        deadlineTrusted: trusted,
        deadlineReadFailed: readFailed,
        deadlineRawText: rawText,
        lastSyncedAt: lastSyncedAt ?? DateTime.utc(2026));
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

  test(
      'legacy change JSON decodes cleanly with deterministic id and UTC bounds',
      () {
    final legacy = AssignmentChange.fromJson({
      'id': 'hw-1',
      'title': '实验',
      'course': '计算机网络',
      'kind': 'deadline',
      'at': '2026-11-20T04:00:00Z',
      'before': '2026-11-25T10:00:00Z',
      'after': '2026-11-22T10:00:00Z',
    });
    expect(legacy.effectiveBeforeUtc, DateTime.utc(2026, 11, 25, 10));
    expect(legacy.effectiveAfterUtc, DateTime.utc(2026, 11, 22, 10));
    expect(legacy.effectiveChangeId, isNotEmpty);
    expect(legacy.isAdvanceDeadlineAlert, isTrue);

    final nonIso = AssignmentChange.fromJson({
      'id': 'hw-2',
      'title': '无解析时间',
      'course': '课程',
      'kind': 'deadline',
      'at': '2026-11-20T04:00:00Z',
      'before': '',
      'after': '新时间',
    });
    expect(nonIso.effectiveAfterUtc, isNull);
    expect(nonIso.isAdvanceDeadlineAlert, isFalse);
  });

  test(
      'trusted->earlier triggers advance alert while extension, >72h unknown, read-fail recovery, and backup placeholder do not',
      () {
    final at = DateTime.utc(2026, 11, 20, 4);
    final earlier = AssignmentChange.compare(
      [row('1', due: at.add(const Duration(days: 6)))],
      [row('1', due: at.add(const Duration(days: 2)))],
      {'1'},
      at,
    );
    expect(earlier, hasLength(1));
    expect(earlier.single.isAdvanceDeadlineAlert, isTrue);
    expect(earlier.single.effectiveBeforeUtc, at.add(const Duration(days: 6)));
    expect(earlier.single.effectiveAfterUtc, at.add(const Duration(days: 2)));

    final later = AssignmentChange.compare(
      [row('1', due: at.add(const Duration(days: 2)))],
      [row('1', due: at.add(const Duration(days: 5)))],
      {'1'},
      at,
    );
    expect(later, hasLength(1));
    expect(later.single.isAdvanceDeadlineAlert, isFalse);

    final unknownWithin72h = AssignmentChange.compare(
      [row('2', trusted: false)],
      [row('2', due: at.add(const Duration(hours: 72)))],
      {'2'},
      at,
    );
    expect(unknownWithin72h, hasLength(1));
    expect(unknownWithin72h.single.effectiveBeforeUtc, isNull);
    expect(unknownWithin72h.single.before, '');
    expect(unknownWithin72h.single.isAdvanceDeadlineAlert, isTrue);

    final unknownBeyond72h = AssignmentChange.compare(
      [row('2', trusted: false)],
      [row('2', due: at.add(const Duration(hours: 73)))],
      {'2'},
      at,
    );
    expect(unknownBeyond72h, isEmpty);

    final sameInstantRecovery = AssignmentChange.compare(
      [
        row('3',
            due: at.add(const Duration(hours: 20)),
            trusted: true,
            readFailed: true)
      ],
      [
        row('3',
            due: at.add(const Duration(hours: 20)),
            trusted: true,
            readFailed: false)
      ],
      {'3'},
      at,
    );
    expect(sameInstantRecovery, isEmpty);

    final backupPlaceholder = AssignmentChange.compare(
      [
        row(
          '4',
          due: at.add(const Duration(hours: 24)),
          trusted: false,
          rawText: '备份记录，待同步确认',
          lastSyncedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        )
      ],
      [row('4', due: at.add(const Duration(hours: 24)), trusted: true)],
      {'4'},
      at,
    );
    expect(backupPlaceholder, isEmpty);
  });

  test('record supports deterministic injected clock and distinct changeIds',
      () async {
    final log = AssignmentChangeLog();
    final t1 = DateTime.utc(2026, 11, 20, 4);
    final t2 = DateTime.utc(2026, 11, 20, 8);
    await log.record(
      [],
      [row('1', due: t1.add(const Duration(days: 5)))],
      {'1'},
      at: t1,
    );
    await log.record(
      [row('1', due: t1.add(const Duration(days: 5)))],
      [row('1', due: t1.add(const Duration(days: 3)))],
      {'1'},
      at: t1,
    );
    await log.record(
      [row('1', due: t1.add(const Duration(days: 3)))],
      [row('1', due: t1.add(const Duration(days: 1)))],
      {'1'},
      at: t2,
    );
    final loaded = await log.load();
    expect(loaded, hasLength(2));
    expect(loaded[0].effectiveChangeId, isNot(loaded[1].effectiveChangeId));
    expect(loaded.every((c) => c.isAdvanceDeadlineAlert), isTrue);
  });
}

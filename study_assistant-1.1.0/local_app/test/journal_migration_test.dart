import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';

Assignment work(String id,
        {String status = 'pending', DateTime? time, String? url}) =>
    Assignment(
        id: id,
        title: '同名作业',
        courseName: '数学',
        deadlineAt: DateTime(2026, 11, 8, 18),
        requirementsText: '',
        status: status,
        lastSyncedAt: time ?? DateTime(2026, 11, 4, 8),
        submitUrl: url);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final ids in [
    ['cx:one'],
    ['cx:one', 'snzl:old'],
    ['snzl:old']
  ]) {
    test('upgrade keeps only Chaoxing records: $ids', () async {
      SharedPreferences.setMockInitialValues({
        'local_assignments':
            jsonEncode(ids.map((id) => work(id).toJson()).toList()),
        'local_last_sync_at': '2026-11-04T08:00:00.000',
        'local_hidden_completed_assignment_ids': <String>['snzl:old'],
        'reminder_offsets_minutes': <String>['60', '10'],
      });
      final repo = LocalAssignmentRepository();
      expect((await repo.loadJournal()).map((a) => a.id),
          ids.where((id) => id.startsWith('cx:')));
      expect(await repo.lastSyncAt(),
          ids.contains('cx:one') ? DateTime(2026, 11, 4, 8) : null);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('local_assignments'), false);
      expect(prefs.getStringList('reminder_offsets_minutes'), ['60', '10']);
      expect(prefs.getString('chaoxing_journal_v2'), isNot(contains('snzl:')));
    });
  }
  test(
      'submitted remains in journal, returned reopens, local hide persists independently',
      () async {
    final repo = LocalAssignmentRepository();
    await repo.mergeAndSave([work('cx:1')]);
    expect(
        await repo.mergeAndSave([work('cx:1', status: 'reviewing')]), isEmpty);
    expect((await repo.loadJournal()).single.status, 'reviewing');
    expect(await repo.mergeAndSave([work('cx:1', status: 'unknown')]), isEmpty);
    expect(
        (await repo.mergeAndSave([work('cx:1', status: 'returned')]))
            .single
            .status,
        'returned');
    await repo.updateCompletion('cx:1', true);
    expect(await repo.mergeAndSave([work('cx:1')]), isEmpty);
    await repo.updateCompletion('cx:1', false);
    expect((await repo.loadAssignments()).single.status, 'pending');
  });
  for (final label in ['已完成', '已互评']) {
    test('legacy completed peer review is completed in journal: $label',
        () async {
      final legacy = work('cx:peer')
          .copyWith(title: '互评作业', requirementsText: '互评作业 $label');
      SharedPreferences.setMockInitialValues({
        'local_assignments': jsonEncode([legacy.toJson()]),
      });
      final repo = LocalAssignmentRepository();
      expect((await repo.loadJournal()).single.isCompleted, isTrue);
      expect(await repo.loadAssignments(), isEmpty);
      expect(
          (await LocalAssignmentRepository().loadJournal()).single.isCompleted,
          isTrue);
      await repo.mergeAndSave([legacy.copyWith(status: 'returned')]);
      expect((await repo.loadJournal()).single.status, 'returned');
      expect((await repo.loadAssignments()).single.id, 'cx:peer');
    });
  }
  test(
      'missing rows and failed deadlines preserve data but explicit unlimited clears date',
      () async {
    final repo = LocalAssignmentRepository();
    await repo.mergeAndSave([work('cx:1')]);
    final sync = await repo.lastSyncAt();
    final old = (await repo.loadJournal()).single;
    await repo.mergeAndSave([work('cx:2')], completeSync: false);
    expect(await repo.lastSyncAt(), sync);
    expect((await repo.loadJournal()).length, 2);
    await repo.mergeAndSave(
        [old.copyWith(clearDeadlineAt: true, deadlineReadFailed: true)]);
    expect(
        (await repo.loadJournal()).firstWhere((a) => a.id == 'cx:1').deadlineAt,
        old.deadlineAt);
    await repo.mergeAndSave([old.copyWith(clearDeadlineAt: true)]);
    expect(
        (await repo.loadJournal()).firstWhere((a) => a.id == 'cx:1').deadlineAt,
        isNull);
  });
  test(
      'equal titles across classes never collapse, scoped URL migrates legacy work',
      () async {
    final repo = LocalAssignmentRepository();
    await repo.mergeAndSave([
      work('cx:stu-work:7',
          url: 'https://mooc1.chaoxing.com/work?courseId=1&classId=2&workId=7')
    ]);
    await repo.mergeAndSave(
        [work('cx:work:1:2:7', status: 'submitted'), work('cx:work:1:3:7')]);
    expect((await repo.loadJournal()).length, 2);
    expect((await repo.loadAssignments()).single.id, 'cx:work:1:3:7');
  });
  test('proven activity alias maps to signed work without losing hide',
      () async {
    final repo = LocalAssignmentRepository();
    const url =
        'https://mobilelearn.chaoxing.com/page?courseid=1&jclassId=2&activeId=88';
    await repo.mergeAndSave([work('cx:activity:88', url: url)]);
    await repo.updateCompletion('cx:activity:1:2:88', true);
    await repo.mergeAndSave([
      work('cx:work:1:2:7',
          url:
              'https://mooc1.chaoxing.com/work?courseId=1&classId=2&workId=7&activeId=88')
    ]);
    expect(await repo.loadJournal(), isEmpty);
    await repo.updateCompletion('cx:work:1:2:7', false);
    expect((await repo.loadJournal()).single.id, 'cx:work:1:2:7');
  });
  test(
      'old server-completed hide migrates back into history; manual hide stays',
      () async {
    SharedPreferences.setMockInitialValues({
      'local_assignments': jsonEncode([
        work('cx:submitted', status: 'submitted').toJson(),
        work('cx:manual', status: 'completed')
            .copyWith(completedAt: DateTime(2026, 11, 4))
            .toJson(),
      ]),
      'local_hidden_completed_assignment_ids': <String>[
        'cx:submitted',
        'cx:manual'
      ],
    });
    final repo = LocalAssignmentRepository();
    expect((await repo.loadJournal()).single.id, 'cx:submitted');
    expect(await repo.loadAssignments(), isEmpty);
  });
  test('stale response cannot roll back date, serialized hide cannot be lost',
      () async {
    final repo = LocalAssignmentRepository();
    final latest = work('cx:1', time: DateTime(2026, 11, 4, 10))
        .copyWith(deadlineAt: DateTime(2026, 11, 9, 18));
    await repo.mergeAndSave([latest]);
    await repo.mergeAndSave([work('cx:1')]);
    expect((await repo.loadJournal()).single.deadlineAt, latest.deadlineAt);
    await Future.wait([
      repo.updateCompletion('cx:1', true),
      repo.mergeAndSave([latest])
    ]);
    expect(await repo.loadAssignments(), isEmpty);
  });
  test('student status is explicit and lifecycle numbers are unknown', () {
    for (final text in ['已结束', '1', '2', '截止', '']) {
      expect(Assignment.statusFromChaoxing(text, null), 'unknown');
    }
    for (final entry in {
      '未提交': 'pending',
      '待批阅': 'reviewing',
      '已提交': 'submitted',
      '退回重做': 'returned',
      '未完成': 'pending'
    }.entries) {
      expect(Assignment.statusFromChaoxing(entry.key, null), entry.value);
    }
  });
}

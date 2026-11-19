import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';

void main() {
  test(
    'mergeAssignments skips previously completed assignments when refreshed',
    () {
      final existing = Assignment(
        id: 'web:course-1:work-1',
        courseName: '软件工程',
        title: '需求分析报告',
        deadlineAt: DateTime.parse('2026-05-08T10:00:00.000Z'),
        requirementsText: '提交 PDF',
        status: 'completed',
        completedAt: DateTime.parse('2026-05-05T10:00:00.000Z'),
        lastSyncedAt: DateTime.parse('2026-05-05T09:00:00.000Z'),
      );
      final incoming = Assignment(
        id: 'web:course-1:work-1',
        courseName: '软件工程',
        title: '需求分析报告（更新）',
        deadlineAt: DateTime.parse('2026-05-09T10:00:00.000Z'),
        requirementsText: '提交 PDF 和截图',
        status: 'pending',
        lastSyncedAt: DateTime.parse('2026-05-05T11:00:00.000Z'),
      );

      final merged = LocalAssignmentRepository.mergeAssignments(
        [existing],
        [incoming],
      );

      expect(merged, isEmpty);
    },
  );

  test('mergeAssignments skips assignments hidden by manual completion', () {
    final incoming = Assignment(
      id: 'web:course-1:work-1',
      courseName: '软件工程',
      title: '需求分析报告',
      deadlineAt: DateTime.parse('2026-05-09T10:00:00.000Z'),
      requirementsText: '提交 PDF',
      status: 'pending',
      lastSyncedAt: DateTime.parse('2026-05-05T11:00:00.000Z'),
    );

    final merged = LocalAssignmentRepository.mergeAssignments(
      [],
      [incoming],
      hiddenCompletedIds: {'web:course-1:work-1'},
    );

    expect(merged, isEmpty);
  });

  test('mergeAndSave hides assignments that are waiting for review', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalAssignmentRepository();
    final reviewing = Assignment(
      id: 'cx:activity:reviewing',
      courseName: '大学英语',
      title: '章节作业',
      deadlineAt: DateTime.parse('2026-05-09T10:00:00.000Z'),
      requirementsText: '完成后提交',
      status: 'submitted',
      lastSyncedAt: DateTime.parse('2026-05-05T11:00:00.000Z'),
    );

    final afterSync = await repository.mergeAndSave([reviewing]);
    final afterReload = await repository.loadAssignments();

    expect(afterSync, isEmpty);
    expect(afterReload, isEmpty);
  });

  test('FB-006 submitted null deadline keeps the last trusted deadline',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalAssignmentRepository();
    final trusted = DateTime.parse('2026-11-20T10:00:00.000Z');
    final first = Assignment(
      id: 'cx:work:course:class:submitted',
      courseName: '大学英语',
      title: '已提交作业',
      deadlineAt: trusted,
      requirementsText: '',
      status: 'submitted',
      deadlineTrusted: true,
      deadlineRawText: '2026-11-20 18:00',
      lastSyncedAt: DateTime.parse('2026-11-16T08:00:00.000Z'),
    );
    final refreshed = first.copyWith(
      deadlineTrusted: false,
      clearDeadlineAt: true,
      clearDeadlineRawText: true,
      lastSyncedAt: DateTime.parse('2026-11-16T09:00:00.000Z'),
    );

    await repository.mergeAndSave([first]);
    await repository.mergeAndSave([refreshed]);

    final stored = (await repository.loadJournal())
        .singleWhere((item) => item.id == first.id);
    expect(stored.status, 'submitted');
    expect(stored.deadlineAt!.toUtc(), trusted);
    expect(stored.deadlineTrusted, isTrue);
    expect(stored.deadlineRawText, '2026-11-20 18:00');
  });

  test('start evidence round-trips and survives a failed deadline refresh',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalAssignmentRepository();
    final published = DateTime.utc(2026, 11, 2, 3);
    final available = DateTime.utc(2026, 11, 16, 16);
    final deadline = DateTime.utc(2026, 11, 20, 10);
    final first = Assignment(
      id: 'cx:work:course:class:start',
      courseName: '信息安全技术',
      title: '第二次讨论作业',
      deadlineAt: deadline,
      publishedAt: published,
      availableFromAt: available,
      availableFromText: '2026-11-17 00:00',
      requirementsText: '',
      status: 'pending',
      deadlineTrusted: true,
      deadlineRawText: '2026-11-20 18:00',
      lastSyncedAt: DateTime.utc(2026, 11, 16, 8),
    );
    await repository.mergeAndSave([first]);
    await repository.mergeAndSave([
      first.copyWith(
        deadlineReadFailed: true,
        deadlineTrusted: false,
        clearDeadlineAt: true,
        lastSyncedAt: DateTime.utc(2026, 11, 16, 9),
      )
    ]);

    final stored = (await repository.loadJournal())
        .singleWhere((item) => item.id == first.id);
    expect(stored.deadlineAt!.toUtc(), deadline);
    expect(stored.publishedAt!.toUtc(), published);
    expect(stored.availableFromAt!.toUtc(), available);
    expect(stored.availableFromText, '2026-11-17 00:00');

    final json = stored.toJson();
    expect(json['publishedAt'], published.toIso8601String());
    expect(json['availableFromAt'], available.toIso8601String());
    final restored = Assignment.fromJson({
      ...json,
      'publishedAt': '2026-11-02 11:00',
    });
    expect(restored.publishedAt, isNull);
    expect(restored.availableFromAt!.toUtc(), available);
  });

  test(
    'mergeAssignments keeps unfinished peer review and filters completed peer review',
    () {
      final oldPeerReview = Assignment(
        id: 'cx:stu-work:peer-review',
        courseName: '大学英语',
        title: '互评作业',
        deadlineAt: DateTime.parse('2026-05-08T10:00:00.000Z'),
        requirementsText: '互评作业 已完成',
        status: 'pending',
        lastSyncedAt: DateTime.parse('2026-05-05T09:00:00.000Z'),
      );
      final incoming = Assignment(
        id: 'cx:stu-work:normal',
        courseName: '大学英语',
        title: '章节作业',
        deadlineAt: DateTime.parse('2026-05-09T10:00:00.000Z'),
        requirementsText: '提交 PDF',
        status: 'pending',
        lastSyncedAt: DateTime.parse('2026-05-05T11:00:00.000Z'),
      );
      final incomingPeerReview = Assignment(
        id: 'cx:stu-work:new-peer-review',
        courseName: '大学英语',
        title: '互评作业',
        deadlineAt: DateTime.parse('2026-05-09T10:00:00.000Z'),
        requirementsText: '互评作业 未完成',
        status: 'pending',
        lastSyncedAt: DateTime.parse('2026-05-05T11:00:00.000Z'),
      );

      final merged = LocalAssignmentRepository.mergeAssignments(
        [oldPeerReview],
        [incoming, incomingPeerReview],
      );

      expect(merged.map((item) => item.id), [
        'cx:stu-work:new-peer-review',
        'cx:stu-work:normal',
      ]);
    },
  );

  test(
    'mergeAssignments retains missing pending work until the server confirms its state',
    () {
      final oldPeerReview = Assignment(
        id: 'cx:stu-work:old-peer-review',
        courseName: '大学英语',
        title: '互评作业',
        deadlineAt: DateTime.parse('2026-05-08T10:00:00.000Z'),
        requirementsText: '互评作业',
        status: 'pending',
        lastSyncedAt: DateTime.parse('2026-05-05T09:00:00.000Z'),
      );
      final incoming = Assignment(
        id: 'cx:stu-work:new-work',
        courseName: '大学英语',
        title: '章节作业',
        deadlineAt: DateTime.parse('2026-05-09T10:00:00.000Z'),
        requirementsText: '提交 PDF',
        status: 'pending',
        lastSyncedAt: DateTime.parse('2026-05-05T11:00:00.000Z'),
      );

      final merged = LocalAssignmentRepository.mergeAssignments(
        [oldPeerReview],
        [incoming],
      );

      expect(merged.map((item) => item.id),
          ['cx:stu-work:old-peer-review', 'cx:stu-work:new-work']);
    },
  );

  test(
    'mergeAssignments filters completed peer review from latest sync result',
    () {
      final completedPeerReview = Assignment(
        id: 'cx:stu-work:completed-peer-review',
        courseName: '大学英语',
        title: '互评作业',
        deadlineAt: DateTime.parse('2026-05-09T10:00:00.000Z'),
        requirementsText: '互评作业 已互评',
        status: 'pending',
        lastSyncedAt: DateTime.parse('2026-05-05T11:00:00.000Z'),
      );

      final merged = LocalAssignmentRepository.mergeAssignments([], [
        completedPeerReview,
      ]);

      expect(merged, isEmpty);
    },
  );

  test('updateCompletion hides assignment across later syncs', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalAssignmentRepository();
    final assignment = Assignment(
      id: 'cx:stu-work:work-1',
      courseName: '大学英语',
      title: '章节作业',
      deadlineAt: DateTime.parse('2026-05-09T10:00:00.000Z'),
      requirementsText: '提交 PDF',
      status: 'pending',
      lastSyncedAt: DateTime.parse('2026-05-05T11:00:00.000Z'),
    );

    await repository.mergeAndSave([assignment]);
    final afterComplete = await repository.updateCompletion(
      assignment.id,
      true,
    );
    final afterRefresh = await repository.mergeAndSave([
      assignment.copyWith(
        lastSyncedAt: DateTime.parse('2026-05-05T12:00:00.000Z'),
      ),
    ]);

    expect(afterComplete, isEmpty);
    expect(afterRefresh, isEmpty);
    expect(await repository.loadAssignments(), isEmpty);
  });

  test('batch hide and restore updates every group source atomically',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalAssignmentRepository();
    final first = Assignment(
      id: 'cx:exam:1:2:3',
      source: AssignmentSource.exam,
      exam: const ExamInfo(examId: '3', courseId: '1', clazzId: '2'),
      courseName: '高等数学',
      title: '期末考试',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: DateTime.parse('2026-11-16T08:00:00.000Z'),
    );
    final second = Assignment(
      id: 'cx:examNotice:inbox:notice',
      source: AssignmentSource.exam,
      exam: const ExamInfo(
        examId: 'notice',
        relatedExamId: '3',
        courseId: '1',
        clazzId: '2',
        noticeOnly: true,
      ),
      courseName: '高等数学',
      title: '考试通知',
      deadlineAt: null,
      requirementsText: '',
      status: 'unknown',
      lastSyncedAt: DateTime.parse('2026-11-16T08:01:00.000Z'),
    );

    await repository.mergeAndSave([first, second]);
    await repository.updateCompletionMany([first.id, second.id], true);

    expect(await repository.loadAssignments(), isEmpty);
    expect(
      (await repository.loadHiddenAssignments()).map((item) => item.id).toSet(),
      {first.id, second.id},
    );

    await repository.updateCompletionMany([first.id, second.id], false);
    expect(
      (await repository.loadAssignments()).map((item) => item.id).toSet(),
      {first.id, second.id},
    );
  });

  test('batch hide rejects a stale account/session before writing', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalAssignmentRepository();
    final assignment = Assignment(
      id: 'cx:work:1:2:stale',
      courseName: '大学英语',
      title: '旧会话作业',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: DateTime.parse('2026-11-16T08:00:00.000Z'),
    );
    await repository.mergeAndSave([assignment]);

    await expectLater(
      repository.updateCompletionMany(
        [assignment.id],
        true,
        canCommit: () async => false,
      ),
      throwsStateError,
    );
    expect(await repository.loadHiddenAssignments(), isEmpty);
    expect((await repository.loadAssignments()).single.id, assignment.id);
  });
}

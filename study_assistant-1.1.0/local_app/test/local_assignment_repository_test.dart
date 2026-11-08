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
}

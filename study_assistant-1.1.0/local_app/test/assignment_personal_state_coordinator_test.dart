import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/course_term_preferences.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/models/local_coursework_state.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/pinned_assignments.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_grouping.dart';
import 'package:study_assistant_mobile/src/services/assignment_personal_state_coordinator.dart';
import 'package:study_assistant_mobile/src/services/course_term_catalog.dart';

Assignment _sampleWork(
  String id, {
  String? submitUrl,
  String? persistedCourseTaskKey,
  String status = 'pending',
  DateTime? deadlineAt,
  bool deadlineTrusted = true,
  bool deadlineReadFailed = false,
  ExamInfo? exam,
}) =>
    Assignment(
      id: id,
      courseName: '软件工程',
      title: '作业 $id',
      deadlineAt: deadlineAt,
      requirementsText: '',
      status: status,
      lastSyncedAt: DateTime.utc(2026, 11, 20, 8),
      submitUrl: submitUrl,
      deadlineTrusted: deadlineTrusted,
      deadlineReadFailed: deadlineReadFailed,
      persistedCourseTaskKey: persistedCourseTaskKey,
      exam: exam,
      source: exam != null ? AssignmentSource.exam : null,
    );

void main() {
  group('dailyPlansChanged', () {
    test('returns false for identical items and true for any difference', () {
      const a = [
        DailyPlanItem('a1', '2026-11-27', 30, done: false),
        DailyPlanItem('a2', '2026-11-28', 45, done: true),
      ];
      const same = [
        DailyPlanItem('a1', '2026-11-27', 30, done: false),
        DailyPlanItem('a2', '2026-11-28', 45, done: true),
      ];
      expect(
        AssignmentPersonalStateCoordinator.dailyPlansChanged(a, same),
        isFalse,
      );
      expect(
        AssignmentPersonalStateCoordinator.dailyPlansChanged(a, [a.first]),
        isTrue,
      );
      expect(
        AssignmentPersonalStateCoordinator.dailyPlansChanged(a, const [
          DailyPlanItem('a1', '2026-11-27', 35, done: false),
          DailyPlanItem('a2', '2026-11-28', 45, done: true),
        ]),
        isTrue,
      );
      expect(
        AssignmentPersonalStateCoordinator.dailyPlansChanged(a, const [
          DailyPlanItem('a1', '2026-11-27', 30, done: true),
          DailyPlanItem('a2', '2026-11-28', 45, done: true),
        ]),
        isTrue,
      );
    });
  });

  group('pinAliases and computePrunedPins', () {
    test('builds grouped exam aliases across all group sources', () {
      final primary = _sampleWork(
        'cx:exam:100:200:900',
        exam: ExamInfo(
          examId: '900',
          courseId: '100',
          clazzId: '200',
          startAt: DateTime.utc(2026, 12, 1, 1),
          endAt: DateTime.utc(2026, 12, 1, 3),
          startTrusted: true,
          endTrusted: true,
        ),
      );
      final notice = _sampleWork(
        'cx:examNotice:inbox:901',
        exam: const ExamInfo(
          examId: '901',
          relatedExamId: '900',
          courseId: '100',
          clazzId: '200',
          noticeOnly: true,
        ),
      );
      final groups = AssignmentGrouping.group([primary, notice]);
      final aliases = AssignmentPersonalStateCoordinator.pinAliases(
        primary,
        courseworkGroups: groups,
      );
      expect(
        aliases,
        containsAll([
          'exam:100:200:900',
          'cx:exam:100:200:900',
          'cx:examNotice:inbox:901',
        ]),
      );
    });

    test('migrates legacy aliases and prunes only completed/hidden/ended pins',
        () {
      final now = DateTime.utc(2026, 11, 27, 8);
      final active = _sampleWork(
        'legacy-1',
        submitUrl:
            'https://mooc1.chaoxing.com/mooc2/work/dowork?courseId=100&classId=200&workId=1',
      );
      final localDone = _sampleWork('cx:work:100:200:2');
      final endedExam = _sampleWork(
        'cx:exam:100:200:99',
        exam: ExamInfo(
          examId: '99',
          courseId: '100',
          clazzId: '200',
          startAt: now.subtract(const Duration(hours: 4)),
          endAt: now.subtract(const Duration(hours: 1)),
          startTrusted: true,
          endTrusted: true,
        ),
      );
      final hiddenWork = _sampleWork('cx:work:100:200:3');
      final groups = AssignmentGrouping.group(
        [active, localDone, endedExam, hiddenWork],
        hiddenIds: {hiddenWork.id},
      );
      final notebook = StudyNotebook(entries: [
        ManualEntry(
          id: 'm-active',
          title: '待办',
          kind: 'todo',
          at: now.add(const Duration(days: 1)),
        ),
        ManualEntry(
          id: 'm-done',
          title: '已完成',
          kind: 'todo',
          done: true,
        ),
      ]);
      final current = PinnedAssignments(keys: const [
        'legacy-1',
        'cx:work:100:200:2',
        'cx:exam:100:200:99',
        'cx:work:100:200:3',
        'unfollowed-missing-key',
        'manual:m-active',
        'manual:m-done',
      ], manuallyOrdered: true);

      final pruned = AssignmentPersonalStateCoordinator.computePrunedPins(
        current: current,
        localRecordGroups: groups,
        notebook: notebook,
        now: now,
        isLocallyCompleted: (a) => a.id == localDone.id,
      );

      expect(
        pruned.keys,
        equals(
            ['cx:work:100:200:1', 'unfollowed-missing-key', 'manual:m-active']),
      );
      expect(pruned.manuallyOrdered, isTrue);
    });
  });

  group('validateAndReorderVisiblePins', () {
    test('reorders visible subset while rejecting duplicates or non-pinnable',
        () {
      final current = PinnedAssignments(
        keys: const ['a', 'hidden', 'b', 'c'],
        manuallyOrdered: false,
      );
      final valid =
          AssignmentPersonalStateCoordinator.validateAndReorderVisiblePins(
        current: current,
        visibleOrderedKeys: const [' c ', 'a', 'b'],
        pinnableKeys: const {'a', 'b', 'c'},
      );
      expect(valid, isNotNull);
      expect(valid!.keys, equals(['c', 'hidden', 'a', 'b']));
      expect(valid.manuallyOrdered, isTrue);

      expect(
        AssignmentPersonalStateCoordinator.validateAndReorderVisiblePins(
          current: current,
          visibleOrderedKeys: const ['a', 'a'],
          pinnableKeys: const {'a', 'b', 'c'},
        ),
        isNull,
      );
      expect(
        AssignmentPersonalStateCoordinator.validateAndReorderVisiblePins(
          current: current,
          visibleOrderedKeys: const ['a', 'unpinned'],
          pinnableKeys: const {'a', 'b', 'c', 'unpinned'},
        ),
        isNull,
      );
      expect(
        AssignmentPersonalStateCoordinator.validateAndReorderVisiblePins(
          current: current,
          visibleOrderedKeys: const ['a', 'hidden'],
          pinnableKeys: const {'a', 'b', 'c'},
        ),
        isNull,
      );
    });
  });

  group('manual deadline and local completion state', () {
    test('computes manual deadline state and rejects exams or trusted dates',
        () {
      final undated = _sampleWork(
        'cx:work:100:200:10',
        deadlineTrusted: false,
      );
      final targetAt = DateTime.utc(2026, 12, 2, 12);
      final next =
          AssignmentPersonalStateCoordinator.computeManualDeadlineState(
        currentState: const LocalCourseworkState.empty(),
        target: undated,
        at: targetAt,
      );
      expect(next, isNotNull);
      expect(
        next!.entries['cx:work:100:200:10']?.manualDeadlineAt?.toUtc(),
        targetAt,
      );

      final trustedWork = _sampleWork(
        'cx:work:100:200:11',
        deadlineAt: DateTime.utc(2026, 12, 3, 12),
        deadlineTrusted: true,
      );
      expect(
        AssignmentPersonalStateCoordinator.computeManualDeadlineState(
          currentState: const LocalCourseworkState.empty(),
          target: trustedWork,
          at: targetAt,
        ),
        isNull,
      );

      final exam = _sampleWork(
        'cx:exam:100:200:5',
        exam: const ExamInfo(examId: '5', courseId: '100', clazzId: '200'),
      );
      expect(
        AssignmentPersonalStateCoordinator.computeManualDeadlineState(
          currentState: const LocalCourseworkState.empty(),
          target: exam,
          at: targetAt,
        ),
        isNull,
      );

      final completedState =
          AssignmentPersonalStateCoordinator.computeLocallyCompletedState(
        currentState: next,
        target: undated,
        completed: true,
      );
      expect(
        completedState.entries['cx:work:100:200:10']?.locallyCompleted,
        isTrue,
      );
    });
  });

  group('course term batch updates and filter clearing', () {
    test('normalizes keys, short-circuits no-ops, and clears blocked filter',
        () {
      final keys = AssignmentPersonalStateCoordinator.normalizeCourseKeys(
        [' 100:200 ', '', '   ', '100:200', '300:400'],
      );
      expect(keys, equals({' 100:200 ', '100:200', '300:400'}));
      expect(
        AssignmentPersonalStateCoordinator.hasBatchCourseTermChanges(
          courseKeys: {'100:200'},
        ),
        isFalse,
      );
      expect(
        AssignmentPersonalStateCoordinator.hasBatchCourseTermChanges(
          courseKeys: {'100:200'},
          blockMode: CourseBlockMode.blocked,
        ),
        isTrue,
      );

      final updated =
          AssignmentPersonalStateCoordinator.applyBatchCourseTermUpdates(
        current: const CourseTermPreferences.empty(),
        courseKeys: const {'100:200', '300:400'},
        manualTerm: const AcademicTerm(2026, AcademicSemester.fall),
        updateManualTerm: true,
        archiveMode: CourseArchiveMode.archived,
        blockMode: CourseBlockMode.blocked,
      );
      expect(updated.entryFor('100:200')?.manualTermKey, '2026-fall');
      expect(
          updated.entryFor('100:200')?.archiveMode, CourseArchiveMode.archived);
      expect(updated.entryFor('300:400')?.blockMode, CourseBlockMode.blocked);

      const filters = HomeFilters(
        query: '实验',
        courseKey: '100:200',
        deadline: AssignmentDeadlineFilter.notExpired,
      );
      final cleared =
          AssignmentPersonalStateCoordinator.clearedCourseFilterIfBlocked(
        currentFilters: filters,
        updatedCourseKeys: const {'100:200'},
        isCourseBlocked: (k) => k == '100:200',
      );
      expect(cleared, isNotNull);
      expect(cleared!.courseKey, isNull);
      expect(cleared.query, '实验');
      expect(cleared.deadline, AssignmentDeadlineFilter.notExpired);

      final recalled =
          AssignmentPersonalStateCoordinator.applyDismissCourseRecall(
        current: updated,
        courseKey: '100:200',
        latestRecallEventUtc: null,
        now: DateTime(2026, 11, 27, 10),
      );
      expect(
        recalled.entryFor('100:200')?.archiveMode,
        CourseArchiveMode.auto,
      );
      expect(
        recalled.entryFor('100:200')?.dismissedRecallCursorUtc,
        DateTime(2026, 11, 27, 10).toUtc(),
      );

      expect(
        AssignmentPersonalStateCoordinator.clearedCourseFilterIfBlocked(
          currentFilters: filters,
          updatedCourseKeys: const {'999:888'},
          isCourseBlocked: (_) => true,
        ),
        isNull,
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/local_coursework_state.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/reminder_history.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_grouping.dart';
import 'package:study_assistant_mobile/src/services/assignment_reminder_coordinator.dart';
import 'package:study_assistant_mobile/src/services/background_reminder_gateway.dart';
import 'package:study_assistant_mobile/src/services/daily_summary.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';

Assignment _sampleWork(String id) => Assignment(
      id: id,
      courseName: '计算机网络',
      title: '实验 $id',
      deadlineAt: DateTime.utc(2026, 11, 29, 12),
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: DateTime.utc(2026, 11, 27, 8),
    );

void main() {
  group('ReminderWarningBuckets (9 boundaries)', () {
    test('preserves insertion order across bucketed and direct warnings', () {
      final buckets = ReminderWarningBuckets();
      buckets.addServiceWarning('direct-1');
      buckets.addBucketWarning(ReminderWarningBucket.deadline, 'deadline-1');
      buckets.addServiceWarning('direct-2');
      buckets.addBucketWarning(ReminderWarningBucket.widget, 'widget-1');

      expect(
        buckets.serviceWarnings,
        equals(['direct-1', 'deadline-1', 'direct-2', 'widget-1']),
      );
    });

    test('manualSaveWarnings includes only privacy and manual buckets', () {
      final buckets = ReminderWarningBuckets();
      buckets.addServiceWarning('direct-history');
      buckets.addBucketWarning(ReminderWarningBucket.deadline, 'deadline-warn');
      buckets.addBucketWarning(ReminderWarningBucket.summary, 'summary-warn');
      buckets.addBucketWarning(ReminderWarningBucket.widget, 'widget-warn');
      buckets.addBucketWarning(ReminderWarningBucket.privacy, 'privacy-warn');
      buckets.addBucketWarning(ReminderWarningBucket.manual, 'manual-warn');

      expect(
        buckets.manualSaveWarnings,
        equals(['privacy-warn', 'manual-warn']),
      );
    });

    test('partial clearSelectedBuckets always clears privacy and selected only',
        () {
      final buckets = ReminderWarningBuckets();
      buckets.addServiceWarning('direct-sync-lease');
      buckets.addBucketWarning(ReminderWarningBucket.privacy, 'privacy-warn');
      buckets.addBucketWarning(ReminderWarningBucket.deadline, 'deadline-warn');
      buckets.addBucketWarning(ReminderWarningBucket.summary, 'summary-warn');
      buckets.addBucketWarning(ReminderWarningBucket.manual, 'manual-warn');
      buckets.addBucketWarning(ReminderWarningBucket.widget, 'widget-warn');

      buckets.clearSelectedBuckets(manual: true);

      expect(
        buckets.serviceWarnings,
        equals([
          'direct-sync-lease',
          'deadline-warn',
          'summary-warn',
          'widget-warn',
        ]),
      );
      expect(buckets.manualSaveWarnings, isEmpty);
    });

    test('clearAll clears non-bucket warnings and all five buckets', () {
      final buckets = ReminderWarningBuckets();
      buckets.addServiceWarning('direct-logout');
      for (final bucket in ReminderWarningBucket.values) {
        buckets.addBucketWarning(bucket, '${bucket.name}-warn');
      }
      buckets.clearAll();
      expect(buckets.isEmpty, isTrue);
      expect(buckets.serviceWarnings, isEmpty);
      expect(buckets.manualSaveWarnings, isEmpty);
    });

    test('hasWidgetWarningOnly respects external error flags and non-bucket',
        () {
      final buckets = ReminderWarningBuckets();
      expect(
        buckets.hasWidgetWarningOnly(
          hasRecoveryWarnings: false,
          hasOperationError: false,
          hasRepositoryRecoveryWarning: false,
        ),
        isFalse,
      );

      buckets.addBucketWarning(ReminderWarningBucket.widget, 'widget-only');
      expect(
        buckets.hasWidgetWarningOnly(
          hasRecoveryWarnings: false,
          hasOperationError: false,
          hasRepositoryRecoveryWarning: false,
        ),
        isTrue,
      );
      expect(
        buckets.hasNonQuietServiceWarning(
          hasRecoveryWarnings: false,
          hasOperationError: false,
          hasRepositoryRecoveryWarning: false,
        ),
        isFalse,
      );

      // Impact of the 3 external flags
      expect(
        buckets.hasWidgetWarningOnly(
          hasRecoveryWarnings: true,
          hasOperationError: false,
          hasRepositoryRecoveryWarning: false,
        ),
        isFalse,
      );
      expect(
        buckets.hasWidgetWarningOnly(
          hasRecoveryWarnings: false,
          hasOperationError: true,
          hasRepositoryRecoveryWarning: false,
        ),
        isFalse,
      );
      expect(
        buckets.hasWidgetWarningOnly(
          hasRecoveryWarnings: false,
          hasOperationError: false,
          hasRepositoryRecoveryWarning: true,
        ),
        isFalse,
      );
      expect(
        buckets.hasNonQuietServiceWarning(
          hasRecoveryWarnings: true,
          hasOperationError: false,
          hasRepositoryRecoveryWarning: false,
        ),
        isTrue,
      );

      // Adding a direct non-bucket warning invalidates widget-only status
      buckets.addServiceWarning('direct-warning');
      expect(
        buckets.hasWidgetWarningOnly(
          hasRecoveryWarnings: false,
          hasOperationError: false,
          hasRepositoryRecoveryWarning: false,
        ),
        isFalse,
      );
      expect(
        buckets.hasNonQuietServiceWarning(
          hasRecoveryWarnings: false,
          hasOperationError: false,
          hasRepositoryRecoveryWarning: false,
        ),
        isTrue,
      );
    });

    test('partial clear removes duplicates one-for-one per bucket entry', () {
      final buckets = ReminderWarningBuckets();
      buckets.addServiceWarning('shared-msg');
      buckets.addBucketWarning(ReminderWarningBucket.summary, 'shared-msg');
      buckets.clearSelectedBuckets(summary: true);
      expect(buckets.serviceWarnings, equals(['shared-msg']));
    });
  });

  group('evaluateTestDeadlineNotification', () {
    test('blocks during quiet hours with retry time and active channel', () {
      // 2026-11-27 23:45 local
      final quietNow = DateTime(2026, 11, 27, 23, 45);
      final decision =
          AssignmentReminderCoordinator.evaluateTestDeadlineNotification(
        now: quietNow,
        authenticated: true,
        deadlineChannelId: LocalNotificationService.assignmentV2Channel,
        activeDeadlineChannelId: LocalNotificationService.assignmentV2Channel,
      );
      expect(decision.isBlockedByQuietHours, isTrue);
      expect(
        decision.quietHoursOutcome!.status,
        TestDeadlineNotificationStatus.quietHours,
      );
      expect(
        decision.quietHoursOutcome!.channelId,
        LocalNotificationService.assignmentV2Channel,
      );
      expect(decision.quietHoursOutcome!.warning, contains('07:30'));
    });

    test(
        'selects authenticated channel or falls back to v3 outside quiet hours',
        () {
      final daytimeNow = DateTime(2026, 11, 27, 14, 0);
      final authed =
          AssignmentReminderCoordinator.evaluateTestDeadlineNotification(
        now: daytimeNow,
        authenticated: true,
        deadlineChannelId: LocalNotificationService.assignmentV2Channel,
        activeDeadlineChannelId: LocalNotificationService.assignmentV2Channel,
      );
      expect(authed.isBlockedByQuietHours, isFalse);
      expect(
        authed.targetChannelId,
        LocalNotificationService.assignmentV2Channel,
      );

      final unauthed =
          AssignmentReminderCoordinator.evaluateTestDeadlineNotification(
        now: daytimeNow,
        authenticated: false,
        deadlineChannelId: LocalNotificationService.assignmentV2Channel,
        activeDeadlineChannelId: LocalNotificationService.assignmentV2Channel,
      );
      expect(unauthed.isBlockedByQuietHours, isFalse);
      expect(
        unauthed.targetChannelId,
        LocalNotificationService.assignmentV3Channel,
      );
    });
  });

  group('explainReminder', () {
    test('aggregates degraded warnings across health, plugin, and subject',
        () async {
      final work = _sampleWork('cx:work:1:2:3');
      final groups = AssignmentGrouping.group([work]);

      final explanation = await AssignmentReminderCoordinator.explainReminder(
        kind: 'assignment',
        id: work.id,
        now: DateTime.utc(2026, 11, 27, 6),
        authenticated: true,
        nativeReminderAvailable: true,
        accountHash: 'hash-1',
        nativeSessionEpoch: 2,
        personal: PersonalWorkspace(),
        notebook: StudyNotebook(),
        lastSyncAt: DateTime.utc(2026, 11, 27, 5),
        courseAssignments: [work],
        hiddenAssignmentIds: const {},
        unfollowedCourseKeys: const {},
        reminderOffsetsMinutes: const [60],
        newAssignmentReminderEnabled: true,
        courseworkState: const LocalCourseworkState.empty(),
        allowUrgentNightBreakthrough: false,
        courseworkGroupFor: (id) =>
            groups.where((g) => g.primary.id == id).firstOrNull,
        findAssignment: (id) => id == work.id ? work : null,
        inspectHealth: () async =>
            const ReminderHealth(queryErrors: ['通知权限查询失败']),
        readScheduleEvidence: () async => throw StateError('plugin offline'),
        inspectSubjects: (_) async =>
            throw const ReminderHistoryException('history_err', '历史库不可读'),
        loadPlanState: (_, __) async => throw StateError('plan offline'),
      );

      expect(explanation.subjectKind, 'assignment');
      expect(
        explanation.queryWarnings,
        containsAll([
          '通知权限查询失败',
          contains('系统待投递排期暂时无法读取'),
          '历史库不可读',
          contains('提醒规则状态暂时无法读取'),
        ]),
      );
    });

    test(
        'handles missing assignment, manual branch, summary branch, and invalid kind',
        () async {
      final now = DateTime.utc(2026, 11, 27, 6);
      Future<ReminderExplanation> runExplain(String kind, String id) =>
          AssignmentReminderCoordinator.explainReminder(
            kind: kind,
            id: id,
            now: now,
            authenticated: true,
            nativeReminderAvailable: false,
            accountHash: null,
            nativeSessionEpoch: 0,
            personal: PersonalWorkspace(summaryEnabled: true),
            notebook: StudyNotebook(entries: [
              ManualEntry(
                id: 'm1',
                title: '复习计网',
                kind: 'todo',
                at: now.add(const Duration(hours: 3)),
                remind: true,
              ),
            ]),
            lastSyncAt: now,
            courseAssignments: const [],
            hiddenAssignmentIds: const {},
            unfollowedCourseKeys: const {},
            reminderOffsetsMinutes: const [60],
            newAssignmentReminderEnabled: true,
            courseworkState: const LocalCourseworkState.empty(),
            allowUrgentNightBreakthrough: false,
            courseworkGroupFor: (_) => null,
            findAssignment: (_) => null,
            inspectHealth: () async =>
                const ReminderHealth(notifications: true),
            readScheduleEvidence: () async => PluginScheduleEvidenceSnapshot(
              items: const [],
              error: null,
              checkedAt: now,
            ),
            inspectSubjects: (_) async => ReminderSubjectEvidence(
              checkedAt: now,
              nativeEvents: const [],
              pluginEvidence: const [],
              queryWarnings: const [],
              historyGeneration: 1,
            ),
            loadPlanState: (_, __) async =>
                throw UnimplementedError('not native'),
          );

      final missing = await runExplain('assignment', 'missing-id');
      expect(missing.categories.single.reasonCodes, equals(['removed']));

      final manual = await runExplain('manual', 'm1');
      expect(manual.subjectKind, 'manual');
      expect(manual.displayName, '复习计网');

      final summary = await runExplain('summary', '20261127');
      expect(summary.subjectKind, 'summary');

      await expectLater(
        () => runExplain('unknown', 'x'),
        throwsA(isA<ReminderHistoryException>()),
      );
    });
  });
}

import '../models/assignment.dart';
import '../models/local_coursework_state.dart';
import '../models/personal_workspace.dart';
import '../models/reminder_history.dart';
import '../models/study_notebook.dart';
import 'assignment_grouping.dart';
import 'background_reminder_gateway.dart';
import 'daily_summary.dart';
import 'deadline_quiet_hours_policy.dart';
import 'local_notification_service.dart';
import 'reminder_explanation.dart';

/// Subsystem buckets tracked alongside direct service warnings.
enum ReminderWarningBucket { privacy, deadline, summary, manual, widget }

/// Ordered service warning registry coordinating the 5 subsystem buckets plus
/// direct non-bucket warnings while preserving insertion order.
class ReminderWarningBuckets {
  final List<String> _serviceWarnings = <String>[];
  final Map<ReminderWarningBucket, List<String>> _buckets = {
    for (final bucket in ReminderWarningBucket.values) bucket: <String>[],
  };

  List<String> get serviceWarnings => List.unmodifiable(_serviceWarnings);

  List<String> get manualSaveWarnings => List.unmodifiable([
        ..._buckets[ReminderWarningBucket.privacy]!,
        ..._buckets[ReminderWarningBucket.manual]!,
      ]);

  bool get isEmpty => _serviceWarnings.isEmpty;
  bool get isNotEmpty => _serviceWarnings.isNotEmpty;

  bool any(bool Function(String warning) test) => _serviceWarnings.any(test);

  /// Appends [message] to [bucket] and to the ordered master list.
  void addBucketWarning(ReminderWarningBucket bucket, String message) {
    _buckets[bucket]!.add(message);
    _serviceWarnings.add(message);
  }

  /// Appends a non-bucket warning directly to the ordered master list.
  void addServiceWarning(String message) {
    _serviceWarnings.add(message);
  }

  /// Clears the master warning list (including non-bucket entries) and all
  /// five subsystem buckets.
  void clearAll() {
    _serviceWarnings.clear();
    for (final list in _buckets.values) {
      list.clear();
    }
  }

  /// Always clears [ReminderWarningBucket.privacy] and clears each selected
  /// bucket by removing its entries item-by-item from the master list so
  /// non-bucket warnings and unselected buckets remain intact in order.
  void clearSelectedBuckets({
    bool deadline = false,
    bool summary = false,
    bool manual = false,
    bool widget = false,
  }) {
    _clearBucket(ReminderWarningBucket.privacy);
    if (deadline) _clearBucket(ReminderWarningBucket.deadline);
    if (summary) _clearBucket(ReminderWarningBucket.summary);
    if (manual) _clearBucket(ReminderWarningBucket.manual);
    if (widget) _clearBucket(ReminderWarningBucket.widget);
  }

  void _clearBucket(ReminderWarningBucket bucket) {
    final list = _buckets[bucket]!;
    for (final msg in list) {
      _serviceWarnings.remove(msg);
    }
    list.clear();
  }

  /// Returns `true` only when every service warning comes exclusively from the
  /// widget bucket and no external recovery or operation errors exist.
  bool hasWidgetWarningOnly({
    required bool hasRecoveryWarnings,
    required bool hasOperationError,
    required bool hasRepositoryRecoveryWarning,
  }) {
    final widgetWarnings = _buckets[ReminderWarningBucket.widget]!;
    return widgetWarnings.isNotEmpty &&
        _serviceWarnings.length == widgetWarnings.length &&
        !hasRecoveryWarnings &&
        !hasOperationError &&
        !hasRepositoryRecoveryWarning;
  }

  /// Returns `true` when at least one non-widget-only service warning exists.
  bool hasNonQuietServiceWarning({
    required bool hasRecoveryWarnings,
    required bool hasOperationError,
    required bool hasRepositoryRecoveryWarning,
  }) =>
      _serviceWarnings.isNotEmpty &&
      !hasWidgetWarningOnly(
        hasRecoveryWarnings: hasRecoveryWarnings,
        hasOperationError: hasOperationError,
        hasRepositoryRecoveryWarning: hasRepositoryRecoveryWarning,
      );
}

/// Decision result for a test deadline notification dispatch.
class TestDeadlineNotificationDecision {
  const TestDeadlineNotificationDecision({
    required this.targetChannelId,
    this.quietHoursOutcome,
  });

  final String targetChannelId;
  final TestDeadlineNotificationOutcome? quietHoursOutcome;

  bool get isBlockedByQuietHours => quietHoursOutcome != null;
}

/// Pure coordinator for reminder explanation aggregation, test-notification
/// quiet-hours gating, and manual cancellation outcome generation.
class AssignmentReminderCoordinator {
  const AssignmentReminderCoordinator._();

  /// Evaluates whether a test deadline notification is blocked by quiet hours
  /// and resolves the effective target channel ID.
  static TestDeadlineNotificationDecision evaluateTestDeadlineNotification({
    required DateTime now,
    required bool authenticated,
    required String deadlineChannelId,
    required String activeDeadlineChannelId,
  }) {
    if (DeadlineQuietHoursPolicy.isQuiet(now)) {
      final retryAt = DeadlineQuietHoursPolicy.nextQuietEnd(now);
      final hm =
          '${retryAt.hour.toString().padLeft(2, '0')}:${retryAt.minute.toString().padLeft(2, '0')}';
      return TestDeadlineNotificationDecision(
        targetChannelId: activeDeadlineChannelId,
        quietHoursOutcome: TestDeadlineNotificationOutcome(
          status: TestDeadlineNotificationStatus.quietHours,
          channelId: activeDeadlineChannelId,
          warning: '当前处于夜间静音时段（23:30–07:30），测试提醒不会穿透静音；请在 $hm 后重试。',
          retryAfterAt: retryAt,
        ),
      );
    }
    final targetChannel = authenticated
        ? deadlineChannelId
        : LocalNotificationService.assignmentV3Channel;
    return TestDeadlineNotificationDecision(targetChannelId: targetChannel);
  }

  /// Builds cancellation or failure outcomes for manual entries that were
  /// previously scheduled and are no longer active after saving [current].
  static List<ReminderScheduleOutcome> buildManualCancellationOutcomes({
    required StudyNotebook previous,
    required StudyNotebook current,
    required bool rescheduleSucceeded,
    required DateTime now,
  }) {
    final outcomes = <ReminderScheduleOutcome>[];
    for (final entry in previous.entries) {
      if (entry.done || !entry.remind || entry.at == null) continue;
      final next =
          current.entries.where((item) => item.id == entry.id).firstOrNull;
      final stillScheduled = next != null &&
          !next.done &&
          next.remind &&
          next.at != null &&
          next.at == entry.at &&
          next.at!.subtract(const Duration(minutes: 30)).isAfter(now);
      if (stillScheduled) continue;
      final at = entry.at!.subtract(const Duration(minutes: 30));
      if (!rescheduleSucceeded) {
        outcomes.add(ReminderScheduleOutcome(
          subjectKind: 'manual',
          subjectId: entry.id,
          logicalKey: 'manual:${entry.id}:${at.millisecondsSinceEpoch}',
          category: 'personal',
          stage: 'cancelFailed',
          reasonCode: 'scheduleBatchFailed',
          observedAt: now,
          scheduledAt: at,
          expectedPayload: 'p:${entry.id}',
          evidenceState: 'recoveryPending',
        ));
        continue;
      }
      final String reasonCode;
      if (next == null) {
        reasonCode = 'removed';
      } else if (next.done) {
        reasonCode = 'completed';
      } else if (!next.remind) {
        reasonCode = 'reminderDisabled';
      } else if (next.at == null) {
        reasonCode = 'noDeadline';
      } else if (!next.at!.subtract(const Duration(minutes: 30)).isAfter(now)) {
        reasonCode = 'offsetWindowPassed';
      } else {
        reasonCode = 'scheduleReplaced';
      }
      outcomes.add(ReminderScheduleOutcome(
        subjectKind: 'manual',
        subjectId: entry.id,
        logicalKey: 'manual:${entry.id}:${at.millisecondsSinceEpoch}',
        category: 'personal',
        stage: 'cancelled',
        reasonCode: reasonCode,
        observedAt: now,
        scheduledAt: at,
        expectedPayload: 'p:${entry.id}',
        evidenceState: 'removed',
      ));
    }
    return outcomes;
  }

  /// Gathers health, plugin schedule evidence, and subject history evidence
  /// with degraded-warning aggregation and builds the 3-branch explanation.
  static Future<ReminderExplanation> explainReminder({
    required String kind,
    required String id,
    required DateTime now,
    required bool authenticated,
    required bool nativeReminderAvailable,
    required String? accountHash,
    required int nativeSessionEpoch,
    required PersonalWorkspace personal,
    required StudyNotebook notebook,
    required DateTime? lastSyncAt,
    required List<Assignment> courseAssignments,
    required Set<String> hiddenAssignmentIds,
    required Set<String> unfollowedCourseKeys,
    required List<int> reminderOffsetsMinutes,
    required bool newAssignmentReminderEnabled,
    required LocalCourseworkState courseworkState,
    required bool allowUrgentNightBreakthrough,
    required CourseworkGroup? Function(String id) courseworkGroupFor,
    required Assignment? Function(String id) findAssignment,
    required Future<ReminderHealth> Function() inspectHealth,
    required Future<PluginScheduleEvidenceSnapshot> Function()
        readScheduleEvidence,
    required Future<ReminderSubjectEvidence> Function(
      List<ReminderSubjectRef> refs,
    ) inspectSubjects,
    required Future<ReminderPlanState> Function(
      String accountHash,
      int sessionEpoch,
    ) loadPlanState,
  }) async {
    final warnings = <String>[];
    ReminderHealth? health;
    var healthQueryFailed = false;
    try {
      health = await inspectHealth();
      if (health.queryErrors.isNotEmpty) {
        healthQueryFailed = true;
        warnings.addAll(health.queryErrors);
      }
    } catch (error) {
      healthQueryFailed = true;
      warnings.add('系统通知状态暂时无法读取：$error');
    }

    PluginScheduleEvidenceSnapshot? plugin;
    var pluginQueryFailed = false;
    try {
      plugin = await readScheduleEvidence();
    } catch (error) {
      pluginQueryFailed = true;
      warnings.add('系统待投递排期暂时无法读取：$error');
    }

    ReminderSubjectEvidence? evidence;
    var subjectQueryFailed = false;
    try {
      final refs = switch (kind) {
        'assignment' => [
            for (final source in courseworkGroupFor(id)?.sources ??
                [if (findAssignment(id) != null) findAssignment(id)!])
              ReminderSubjectRef('assignment', source.id),
          ],
        'manual' => [ReminderSubjectRef('manual', id)],
        'summary' => const [ReminderSubjectRef('summary', null)],
        _ => <ReminderSubjectRef>[],
      };
      if (refs.isNotEmpty) {
        evidence = await inspectSubjects(refs);
      }
    } on ReminderHistoryException catch (error) {
      subjectQueryFailed = true;
      warnings.add(error.message);
    } catch (error) {
      subjectQueryFailed = true;
      warnings.add('提醒证据暂时无法读取：$error');
    }

    if (kind == 'assignment') {
      final group = courseworkGroupFor(id);
      final primary = group?.primary ?? findAssignment(id);
      if (primary == null) {
        return ReminderExplanation(
          checkedAt: now,
          subjectKind: kind,
          subjectId: id,
          displayName: '事项已不在当前账号的本机记录中',
          categories: const [
            ReminderCategoryExplanation(
              category: 'deadline',
              status: ReminderExplanationStatus.ineligible,
              reasonCodes: ['removed'],
              nextScheduledAt: null,
              evidenceAt: null,
              actionLabel: null,
            ),
          ],
          queryWarnings: warnings,
        );
      }
      ReminderPlanState? plan;
      if (nativeReminderAvailable && nativeSessionEpoch > 0) {
        try {
          plan = await loadPlanState(accountHash!, nativeSessionEpoch);
        } catch (error) {
          subjectQueryFailed = true;
          warnings.add('提醒规则状态暂时无法读取：$error');
        }
      }
      return ReminderExplanationService.forAssignment(
        primary: primary,
        sources: group?.sources ?? [primary],
        groupHidden: group?.hidden ?? false,
        hiddenAssignmentIds: hiddenAssignmentIds,
        unfollowedCourseKeys: unfollowedCourseKeys,
        plan: plan,
        offsets: reminderOffsetsMinutes,
        newReminderEnabled: newAssignmentReminderEnabled,
        now: now,
        evidence: evidence,
        health: health,
        pluginEvidence: plugin,
        queryWarnings: warnings,
        coursework: courseworkState,
        allowUrgentNightBreakthrough: allowUrgentNightBreakthrough,
        healthQueryFailed: healthQueryFailed,
        pluginQueryFailed: pluginQueryFailed,
        subjectQueryFailed: subjectQueryFailed,
      );
    }
    if (kind == 'manual') {
      final entry = notebook.entries.where((item) => item.id == id).firstOrNull;
      return ReminderExplanationService.forManual(
        entry: entry,
        entryId: id,
        now: now,
        evidence: evidence,
        health: health,
        pluginEvidence: plugin,
        queryWarnings: warnings,
        allowUrgentNightBreakthrough: allowUrgentNightBreakthrough,
        healthQueryFailed: healthQueryFailed,
        pluginQueryFailed: pluginQueryFailed,
        subjectQueryFailed: subjectQueryFailed,
      );
    }
    if (kind == 'summary') {
      final summaryId = int.tryParse(id);
      final notices = DailySummary.build(
        courseAssignments,
        authenticated ? personal : PersonalWorkspace(),
        now,
        lastSyncAt,
        coursework: authenticated
            ? courseworkState
            : const LocalCourseworkState.empty(),
      );
      return ReminderExplanationService.forSummary(
        personal: authenticated ? personal : PersonalWorkspace(),
        summaryId: summaryId,
        now: now,
        evidence: evidence,
        health: health,
        pluginEvidence: plugin,
        queryWarnings: warnings,
        notices: notices,
        healthQueryFailed: healthQueryFailed,
        pluginQueryFailed: pluginQueryFailed,
        subjectQueryFailed: subjectQueryFailed,
      );
    }
    throw const ReminderHistoryException(
      'invalid_history_argument',
      '未知提醒事项类型',
    );
  }
}

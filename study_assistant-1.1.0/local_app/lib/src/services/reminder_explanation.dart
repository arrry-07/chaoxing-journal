import '../models/assignment.dart';
import '../models/personal_workspace.dart';
import '../models/reminder_history.dart';
import '../models/study_notebook.dart';
import 'assignment_reminder_planner.dart';
import 'assignment_query.dart';
import 'background_reminder_gateway.dart';
import 'daily_summary.dart';

class ReminderExplanationService {
  const ReminderExplanationService._();

  static ReminderExplanation forAssignment({
    required Assignment primary,
    required List<Assignment> sources,
    required bool groupHidden,
    required Set<String> hiddenAssignmentIds,
    required Set<String> unfollowedCourseKeys,
    required ReminderPlanState? plan,
    required List<int> offsets,
    required bool newReminderEnabled,
    required DateTime now,
    required ReminderSubjectEvidence? evidence,
    required ReminderHealth? health,
    required PluginScheduleEvidenceSnapshot? pluginEvidence,
    required List<String> queryWarnings,
  }) {
    final categories = <ReminderCategoryExplanation>[];
    final system = _systemReasons(health, health?.assignmentChannel);
    final sourceIds = sources.map((item) => item.id).toSet();
    final snapshots = [
      for (final source in sources)
        AssignmentReminderSnapshot(
          assignment: source,
          hidden: groupHidden || hiddenAssignmentIds.contains(source.id),
          followed: !unfollowedCourseKeys.contains(source.courseKey),
        ),
    ];
    final qualification = _assignmentQualification(
      primary: primary,
      sources: sources,
      snapshots: snapshots,
      groupHidden: groupHidden,
      now: now,
    );

    final newReasons = <String>[
      ...qualification,
      if (!newReminderEnabled) 'newReminderDisabled',
      if (newReminderEnabled && plan == null) 'baselinePending',
      if (newReminderEnabled && plan != null && !plan.baselineCompleted)
        'baselinePending',
      if (newReminderEnabled &&
          plan != null &&
          plan.baselineCompleted &&
          plan.sentNewAssignmentIds.contains(primary.id))
        'alreadySubmitted',
      if (newReminderEnabled &&
          plan != null &&
          plan.baselineCompleted &&
          !plan.sentNewAssignmentIds.contains(primary.id) &&
          plan.knownAssignmentIds.contains(primary.id))
        'alreadyKnown',
      ...system,
    ];
    categories.add(
      _category(
        category: 'newAssignment',
        qualificationReasons: newReasons,
        eligible: qualification.isEmpty &&
            newReminderEnabled &&
            plan?.baselineCompleted == true &&
            !plan!.knownAssignmentIds.contains(primary.id) &&
            !plan.sentNewAssignmentIds.contains(primary.id),
        plannedAt: null,
        evidence: evidence,
        plugin: pluginEvidence,
        subjectIds: sourceIds,
        now: now,
      ),
    );

    final anchorCategory = primary.isExam ? 'examStart' : 'deadline';
    final anchor = _anchor(primary);
    final anchorReasons = <String>[
      ...qualification,
      if (primary.isExam && primary.exam!.noticeOnly) 'examNoticeOnly',
      if (primary.isExam && !primary.hasExamIdentity) 'examUnavailable',
      if (!primary.isExam && !primary.deadlineTrusted) 'deadlineUnknown',
      if (!primary.isExam && primary.deadlineReadFailed) 'deadlineReadFailed',
      if (anchor == null) 'noDeadline',
      if (anchor != null && !anchor.isAfter(now)) 'anchorPassed',
      ...system,
    ];
    final planned = _nextPlanned(primary, offsets, now);
    if (anchor != null &&
        anchor.isAfter(now) &&
        planned == null &&
        offsets.isNotEmpty) {
      anchorReasons.add('offsetWindowPassed');
    }
    categories.add(
      _category(
        category: anchorCategory,
        qualificationReasons: anchorReasons,
        eligible: qualification.isEmpty &&
            anchor != null &&
            anchor.isAfter(now) &&
            (primary.isExam
                ? primary.exam!.startTrusted
                : primary.deadlineTrusted && !primary.deadlineReadFailed),
        plannedAt: planned,
        evidence: evidence,
        plugin: pluginEvidence,
        subjectIds: sourceIds,
        now: now,
      ),
    );
    final plannerReasons = <String>[
      if (offsets.isEmpty) 'reminderDisabled',
      if (!primary.isExam &&
          primary.deadlineBucketAt(now) !=
              AssignmentDeadlineBucket.notExpiredWithDeadline)
        'anchorPassed',
    ];
    if (plannerReasons.isNotEmpty) {
      final index = categories.indexWhere(
        (item) => item.category == anchorCategory,
      );
      final current = categories[index];
      categories[index] = ReminderCategoryExplanation(
        category: current.category,
        status: ReminderExplanationStatus.ineligible,
        reasonCodes: _ordered([...plannerReasons, ...current.reasonCodes]),
        nextScheduledAt: null,
        evidenceAt: current.evidenceAt,
        actionLabel: null,
      );
    }
    return ReminderExplanation(
      checkedAt: now,
      subjectKind: 'assignment',
      subjectId: primary.id,
      displayName: [
        if (primary.courseName.trim().isNotEmpty) primary.courseName.trim(),
        if (primary.title.trim().isNotEmpty) primary.title.trim(),
      ].join(' · '),
      categories: List.unmodifiable(categories),
      queryWarnings: {
        ...queryWarnings,
        ...?evidence?.queryWarnings,
        if (pluginEvidence?.error != null) pluginEvidence!.error!,
      }.toList(),
    );
  }

  static ReminderExplanation forManual({
    required ManualEntry? entry,
    required String entryId,
    required DateTime now,
    required ReminderSubjectEvidence? evidence,
    required ReminderHealth? health,
    required PluginScheduleEvidenceSnapshot? pluginEvidence,
    required List<String> queryWarnings,
  }) {
    final reasons = <String>[];
    DateTime? planned;
    var eligible = false;
    if (entry == null) {
      reasons.add('removed');
    } else if (entry.done) {
      reasons.add('completed');
    } else if (!entry.remind) {
      reasons.add('reminderDisabled');
    } else if (entry.at == null) {
      reasons.add('noDeadline');
    } else {
      planned = entry.at!.subtract(const Duration(minutes: 30));
      if (!planned.isAfter(now)) {
        reasons.add('offsetWindowPassed');
      } else {
        eligible = true;
      }
    }
    reasons.addAll(_systemReasons(health, health?.manualChannel));
    final category = _category(
      category: 'personal',
      qualificationReasons: reasons,
      eligible: eligible,
      plannedAt: planned,
      evidence: evidence,
      plugin: pluginEvidence,
      subjectIds: {entryId},
      now: now,
    );
    return ReminderExplanation(
      checkedAt: now,
      subjectKind: 'manual',
      subjectId: entryId,
      displayName: entry?.title ?? '已移除的个人安排',
      categories: [category],
      queryWarnings: {
        ...queryWarnings,
        ...?evidence?.queryWarnings,
        if (pluginEvidence?.error != null) pluginEvidence!.error!,
      }.toList(),
    );
  }

  static ReminderExplanation forSummary({
    required PersonalWorkspace personal,
    required int? summaryId,
    required DateTime now,
    required ReminderSubjectEvidence? evidence,
    required ReminderHealth? health,
    required PluginScheduleEvidenceSnapshot? pluginEvidence,
    required List<String> queryWarnings,
    required List<SummaryNotice> notices,
  }) {
    final reasons = <String>[
      if (!personal.summaryEnabled) 'reminderDisabled',
      ..._systemReasons(health, health?.summaryChannel),
    ];
    final targetId = summaryId == null || summaryId <= 0 ? null : summaryId;
    final notice = targetId == null
        ? notices.firstOrNull
        : notices.where((item) => item.id == targetId).firstOrNull;
    final category = _category(
      category: 'summary',
      qualificationReasons: reasons,
      eligible: personal.summaryEnabled && notice != null,
      plannedAt: notice?.at,
      evidence: evidence,
      plugin: pluginEvidence,
      subjectIds: targetId == null ? const {} : {'$targetId'},
      now: now,
    );
    return ReminderExplanation(
      checkedAt: now,
      subjectKind: 'summary',
      subjectId: summaryId?.toString(),
      displayName: '每日课业摘要',
      categories: [
        ReminderCategoryExplanation(
          category: category.category,
          status: category.status,
          reasonCodes: _ordered([...category.reasonCodes, 'inexactFallback']),
          nextScheduledAt: category.nextScheduledAt,
          evidenceAt: category.evidenceAt,
          actionLabel: category.actionLabel,
        ),
      ],
      queryWarnings: {
        ...queryWarnings,
        ...?evidence?.queryWarnings,
        if (pluginEvidence?.error != null) pluginEvidence!.error!,
      }.toList(),
    );
  }

  static List<String> _assignmentQualification({
    required Assignment primary,
    required List<Assignment> sources,
    required List<AssignmentReminderSnapshot> snapshots,
    required bool groupHidden,
    required DateTime now,
  }) {
    if (groupHidden || snapshots.every((item) => item.hidden)) {
      return const ['hidden'];
    }
    if (snapshots.every((item) => item.assignment.isCompleted)) {
      return const ['completed'];
    }
    if (snapshots.every((item) => !item.followed)) {
      return const ['unfollowed'];
    }
    if (sources.every((item) => !item.isInAssignmentScope)) {
      return const ['outOfScope'];
    }
    if (primary.isExam) {
      final exam = primary.exam!;
      if (exam.noticeOnly) return const ['examNoticeOnly'];
      if (!primary.hasExamIdentity ||
          exam.lifecycle != 'scheduled' ||
          primary.submitUrl?.isNotEmpty != true) {
        return const ['examUnavailable'];
      }
      if (primary.isCompleted || AssignmentQuery.isExamEnded(primary, now)) {
        return const ['completed'];
      }
      if (!exam.startTrusted || exam.startAt == null) {
        return const ['deadlineUnknown'];
      }
    } else {
      if (!primary.isPendingConfirmed) return const ['statusUnknown'];
      if (!primary.deadlineTrusted) return const ['deadlineUnknown'];
      if (primary.deadlineReadFailed) return const ['deadlineReadFailed'];
      if (primary.deadlineAt == null) return const ['noDeadline'];
    }
    return const [];
  }

  static DateTime? _anchor(Assignment assignment) =>
      assignment.isExam ? assignment.reminderAnchorAt : assignment.deadlineAt;

  static DateTime? _nextPlanned(
    Assignment assignment,
    List<int> offsets,
    DateTime now,
  ) {
    final anchor = _anchor(assignment);
    if (anchor == null) return null;
    final values = [
      for (final offset in offsets)
        if (offset > 0) anchor.subtract(Duration(minutes: offset)),
    ].where((item) => item.isAfter(now)).toList()
      ..sort();
    return values.firstOrNull;
  }

  static ReminderCategoryExplanation _category({
    required String category,
    required List<String> qualificationReasons,
    required bool eligible,
    required DateTime? plannedAt,
    required ReminderSubjectEvidence? evidence,
    required PluginScheduleEvidenceSnapshot? plugin,
    required Set<String> subjectIds,
    required DateTime now,
  }) {
    final reasons = _ordered(qualificationReasons);
    DateTime? evidenceAt;
    DateTime? evidenceScheduledAt;
    var recoveryPending = false;
    if (evidence != null) {
      for (final item in evidence.pluginEvidence.where(
        (item) =>
            (item.subjectId.isEmpty || subjectIds.contains(item.subjectId)) &&
            item.category == category,
      )) {
        evidenceAt = item.evidenceAt ?? evidenceAt;
        if (item.state == 'confirmedScheduled' &&
            item.scheduledAt?.isAfter(now) == true) {
          if (evidenceScheduledAt == null ||
              item.scheduledAt!.isBefore(evidenceScheduledAt)) {
            evidenceScheduledAt = item.scheduledAt;
          }
          final matchesSystem = item.notificationId == null ||
              plugin?.items.any(
                    (systemItem) =>
                        systemItem.id == item.notificationId &&
                        systemItem.pending &&
                        (item.expectedPayload == null ||
                            systemItem.payload == item.expectedPayload),
                  ) ==
                  true;
          if (!matchesSystem && plugin != null && plugin.error == null) {
            reasons.add('scheduleUnconfirmed');
          }
        } else if (item.state == 'recoveryPending') {
          recoveryPending = true;
          reasons.add('recoveryPending');
        } else if (item.state == 'retainedOld') {
          reasons.add('scheduleUnconfirmed');
        }
      }
    }
    if (!eligible) {
      return ReminderCategoryExplanation(
        category: category,
        status: eligibilityFailureReasons(qualificationReasons)
            ? ReminderExplanationStatus.ineligible
            : ReminderExplanationStatus.deferred,
        reasonCodes: reasons,
        nextScheduledAt: null,
        evidenceAt: evidenceAt,
        actionLabel: null,
      );
    }
    final hasSystemBlock = reasons.any(
      const {
        'notificationPermissionOff',
        'channelOff',
        'permissionUnknown',
        'channelUnknown',
        'outsideWindow',
        'cooldown',
        'offsetWindowPassed',
      }.contains,
    );
    if (hasSystemBlock) {
      return ReminderCategoryExplanation(
        category: category,
        status: ReminderExplanationStatus.deferred,
        reasonCodes: reasons,
        nextScheduledAt: evidenceScheduledAt ?? plannedAt,
        evidenceAt: evidenceAt,
        actionLabel: '检查系统通知设置',
      );
    }
    final confirmed = evidenceScheduledAt != null && !recoveryPending;
    return ReminderCategoryExplanation(
      category: category,
      status: confirmed
          ? ReminderExplanationStatus.planned
          : ReminderExplanationStatus.unconfirmed,
      reasonCodes: reasons,
      nextScheduledAt: evidenceScheduledAt ?? plannedAt,
      evidenceAt: evidenceAt,
      actionLabel: confirmed ? null : '重试提醒恢复',
    );
  }

  static bool eligibilityFailureReasons(List<String> reasons) => reasons.any(
        const {
          'completed',
          'hidden',
          'unfollowed',
          'outOfScope',
          'statusUnknown',
          'examNoticeOnly',
          'examUnavailable',
          'noDeadline',
          'anchorPassed',
          'offsetWindowPassed',
          'reminderDisabled',
          'newReminderDisabled',
          'baselinePending',
          'alreadyKnown',
          'alreadySubmitted',
          'removed',
        }.contains,
      );

  static List<String> _systemReasons(
    ReminderHealth? health,
    ReminderChannelHealth? channel,
  ) {
    if (health == null) {
      return const ['permissionUnknown', 'channelUnknown'];
    }
    final result = <String>[];
    if (health.notifications == false) {
      result.add('notificationPermissionOff');
    } else if (health.notifications == null) {
      result.add('permissionUnknown');
    }
    if (channel?.enabled == false) {
      result.add('channelOff');
    } else if (channel == null || channel.enabled == null) {
      result.add('channelUnknown');
    }
    return result;
  }

  static List<String> _ordered(Iterable<String> reasons) {
    const order = [
      'completed',
      'hidden',
      'unfollowed',
      'outOfScope',
      'statusUnknown',
      'examNoticeOnly',
      'examUnavailable',
      'deadlineUnknown',
      'deadlineReadFailed',
      'noDeadline',
      'anchorPassed',
      'offsetWindowPassed',
      'reminderDisabled',
      'baselinePending',
      'alreadyKnown',
      'alreadySubmitted',
      'newReminderDisabled',
      'outsideWindow',
      'cooldown',
      'notificationPermissionOff',
      'channelOff',
      'permissionUnknown',
      'channelUnknown',
      'recoveryPending',
      'scheduleUnconfirmed',
      'queryFailed',
      'inexactFallback',
      'removed',
    ];
    final unique = reasons.toSet().toList()
      ..sort(
        (a, b) {
          final ai = order.indexOf(a);
          final bi = order.indexOf(b);
          return (ai < 0 ? 999 : ai).compareTo(bi < 0 ? 999 : bi);
        },
      );
    return unique;
  }
}

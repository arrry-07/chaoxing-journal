import '../models/assignment.dart';
import '../models/local_coursework_state.dart';
import '../models/personal_workspace.dart';
import '../models/reminder_history.dart';
import '../models/study_notebook.dart';
import 'assignment_reminder_planner.dart';
import 'assignment_query.dart';
import 'background_reminder_gateway.dart';
import 'coursework_deadline.dart';
import 'daily_summary.dart';
import 'daytime_check_policy.dart';
import 'deadline_quiet_hours_policy.dart';

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
    LocalCourseworkState coursework = const LocalCourseworkState.empty(),
    bool allowUrgentNightBreakthrough = false,
    bool healthQueryFailed = false,
    bool pluginQueryFailed = false,
    bool subjectQueryFailed = false,
  }) {
    final primaryEntry = CourseworkDeadline.entryFor(primary, coursework);
    final categories = <ReminderCategoryExplanation>[];
    final sourceIds = sources.map((item) => item.id).toSet();
    final snapshots = [
      for (final source in sources)
        AssignmentReminderSnapshot(
          assignment: source,
          hidden: groupHidden || hiddenAssignmentIds.contains(source.id),
          followed: !unfollowedCourseKeys.contains(source.courseKey),
          courseworkEntry: CourseworkDeadline.entryFor(source, coursework),
        ),
    ];
    final qualification = _assignmentQualification(
      primary: primary,
      sources: sources,
      snapshots: snapshots,
      groupHidden: groupHidden,
      now: now,
      primaryEntry: primaryEntry,
    );

    final hasPendingNewNative = evidence?.nativeEvents.any(
          (item) =>
              item.category == 'newAssignment' &&
              item.state == 'pending' &&
              (item.subjectId == null ||
                  item.subjectId!.isEmpty ||
                  sourceIds.contains(item.subjectId)),
        ) ==
        true;
    final baselinedSources = plan?.baselinedSources ?? const <String>{};
    final allSourcesBaselined = plan != null &&
        sources.isNotEmpty &&
        sources.every(
          (source) =>
              source.reminderSourceKey != null &&
              baselinedSources.contains(source.reminderSourceKey),
        );
    final allKnown = sources.isNotEmpty &&
        sources.every((s) => plan?.knownAssignmentIds.contains(s.id) == true);
    final allSent = sources.isNotEmpty &&
        sources.every((s) => plan?.sentNewAssignmentIds.contains(s.id) == true);
    final newChannel =
        health?.assignmentUpdatesChannel ?? health?.assignmentChannel;
    final newSystem = _systemReasons(
      health,
      newChannel,
      healthQueryFailed: healthQueryFailed,
    );
    final inDaytimeWindow = DaytimeCheckPolicy.isInWindow(now);
    final newReasons = <String>[
      ...qualification,
      if (!newReminderEnabled) 'newReminderDisabled',
      if (newReminderEnabled && !allSourcesBaselined) 'baselinePending',
      if (newReminderEnabled && allSourcesBaselined && allSent)
        'alreadySubmitted',
      if (newReminderEnabled &&
          allSourcesBaselined &&
          !allSent &&
          allKnown &&
          !hasPendingNewNative)
        'alreadyKnown',
      if (newReminderEnabled && hasPendingNewNative && !inDaytimeWindow)
        'outsideWindow',
      ...newSystem,
    ];
    categories.add(
      _category(
        category: 'newAssignment',
        qualificationReasons: newReasons,
        eligible: qualification.isEmpty &&
            newReminderEnabled &&
            allSourcesBaselined &&
            !allSent &&
            (hasPendingNewNative || !allKnown),
        plannedAt:
            inDaytimeWindow ? null : DaytimeCheckPolicy.nextWindowStart(now),
        evidence: evidence,
        plugin: pluginEvidence,
        subjectIds: sourceIds,
        now: now,
        isNativeCategory: true,
        planPendingUpdate: plan?.pendingUpdate == true,
        health: health,
        healthQueryFailed: healthQueryFailed,
        pluginQueryFailed: pluginQueryFailed,
        subjectQueryFailed: subjectQueryFailed,
      ),
    );

    final anchorCategory = primary.isExam ? 'examStart' : 'deadline';
    final anchor = _anchor(primary, entry: primaryEntry);
    final deadlineSystem = _systemReasons(
      health,
      health?.assignmentChannel,
      healthQueryFailed: healthQueryFailed,
    );
    final resolvedDeadline = primary.isExam
        ? null
        : CourseworkDeadline.resolveEntry(primary, primaryEntry);
    final canComputeDeadlineAnchor = primary.isExam
        ? (primary.hasExamIdentity &&
            primary.exam!.startTrusted &&
            !primary.exam!.noticeOnly &&
            primary.exam!.lifecycle == 'scheduled')
        : (primary.isPendingConfirmed &&
            ((primary.deadlineTrusted && !primary.deadlineReadFailed) ||
                resolvedDeadline?.isManual == true));
    final anchorReasons = <String>[
      ...qualification,
      if (anchor == null && canComputeDeadlineAnchor) 'noDeadline',
      if (anchor != null && !anchor.isAfter(now)) 'anchorPassed',
      ...deadlineSystem,
    ];
    final planned = _nextPlanned(
      primary,
      offsets,
      now,
      entry: primaryEntry,
      allowUrgentNightBreakthrough: allowUrgentNightBreakthrough,
    );
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
            offsets.isNotEmpty &&
            anchor != null &&
            anchor.isAfter(now) &&
            planned != null &&
            (primary.isExam
                ? primary.exam!.startTrusted
                : (primary.deadlineTrusted && !primary.deadlineReadFailed) ||
                    resolvedDeadline?.isManual == true),
        plannedAt: planned,
        evidence: evidence,
        plugin: pluginEvidence,
        subjectIds: sourceIds,
        now: now,
        isNativeCategory: true,
        planPendingUpdate: plan?.pendingUpdate == true,
        health: health,
        healthQueryFailed: healthQueryFailed,
        pluginQueryFailed: pluginQueryFailed,
        subjectQueryFailed: subjectQueryFailed,
      ),
    );
    final expiredDeadline = !primary.isExam &&
        CourseworkDeadline.bucketAt(primary, now, entry: primaryEntry) ==
            AssignmentDeadlineBucket.overdue;
    final plannerReasons = <String>[
      if (offsets.isEmpty) 'reminderDisabled',
      if (expiredDeadline) 'anchorPassed',
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
    bool allowUrgentNightBreakthrough = false,
    bool healthQueryFailed = false,
    bool pluginQueryFailed = false,
    bool subjectQueryFailed = false,
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
      final rawCandidate = entry.at!.subtract(const Duration(minutes: 30));
      planned = DeadlineQuietHoursPolicy.adjustManualCandidate(
        candidateAt: rawCandidate,
        eventAt: entry.at!,
        now: now,
        allowUrgentNightBreakthrough: allowUrgentNightBreakthrough,
      );
      if (planned == null) {
        reasons.add('offsetWindowPassed');
      } else {
        eligible = true;
      }
    }
    reasons.addAll(
      _systemReasons(
        health,
        health?.manualChannel,
        healthQueryFailed: healthQueryFailed,
      ),
    );
    final category = _category(
      category: 'personal',
      qualificationReasons: reasons,
      eligible: eligible,
      plannedAt: planned,
      evidence: evidence,
      plugin: pluginEvidence,
      subjectIds: {entryId},
      now: now,
      isNativeCategory: false,
      planPendingUpdate: false,
      health: health,
      healthQueryFailed: healthQueryFailed,
      pluginQueryFailed: pluginQueryFailed,
      subjectQueryFailed: subjectQueryFailed,
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
    bool healthQueryFailed = false,
    bool pluginQueryFailed = false,
    bool subjectQueryFailed = false,
  }) {
    final reasons = <String>[
      if (!personal.summaryEnabled) 'reminderDisabled',
      ..._systemReasons(
        health,
        health?.summaryChannel,
        healthQueryFailed: healthQueryFailed,
      ),
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
      isNativeCategory: false,
      planPendingUpdate: false,
      health: health,
      healthQueryFailed: healthQueryFailed,
      pluginQueryFailed: pluginQueryFailed,
      subjectQueryFailed: subjectQueryFailed,
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
    LocalCourseworkEntry? primaryEntry,
  }) {
    if (groupHidden || snapshots.every((item) => item.hidden)) {
      return const ['hidden'];
    }
    if (snapshots.every((item) =>
        CourseworkDeadline.isEffectivelyCompletedEntry(
            item.assignment, item.courseworkEntry))) {
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
      final resolved = CourseworkDeadline.resolveEntry(primary, primaryEntry);
      if (resolved == null) {
        if (!primary.deadlineTrusted) return const ['deadlineUnknown'];
        if (primary.deadlineReadFailed) return const ['deadlineReadFailed'];
        if (primary.deadlineAt == null) return const ['noDeadline'];
      }
    }
    return const [];
  }

  static DateTime? _anchor(
    Assignment assignment, {
    LocalCourseworkEntry? entry,
  }) =>
      assignment.isExam
          ? assignment.reminderAnchorAt
          : CourseworkDeadline.resolveEntry(assignment, entry)?.at;

  static DateTime? _nextPlanned(
    Assignment assignment,
    List<int> offsets,
    DateTime now, {
    LocalCourseworkEntry? entry,
    bool allowUrgentNightBreakthrough = false,
  }) {
    final snapshot = AssignmentReminderSnapshot(
      assignment: assignment,
      hidden: false,
      followed: true,
      courseworkEntry: entry,
    );
    final anchor = _anchor(assignment, entry: entry);
    if (anchor == null) return null;
    final slots = DeadlineQuietHoursPolicy.planDeadlineSlots(
      deadlineAt: anchor,
      now: now,
      offsetsMinutes: offsets,
      source: snapshot.deadlineSource,
      eventKind: snapshot.eventKind,
      allowUrgentNightBreakthrough: allowUrgentNightBreakthrough,
    );
    return slots.firstOrNull?.notifyAt;
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
    required bool isNativeCategory,
    required bool planPendingUpdate,
    required ReminderHealth? health,
    required bool healthQueryFailed,
    required bool pluginQueryFailed,
    required bool subjectQueryFailed,
  }) {
    final reasons = _ordered(qualificationReasons).toList();
    DateTime? evidenceAt;
    DateTime? confirmedAt;
    DateTime? candidateAt;
    var confirmed = false;
    var recoveryPending = health?.scheduleRecoveryPending == true ||
        (isNativeCategory && planPendingUpdate);
    if (recoveryPending) {
      reasons.add('recoveryPending');
    }

    if (evidence != null) {
      for (final item in evidence.nativeEvents.where(
        (item) =>
            (item.subjectId == null ||
                item.subjectId!.isEmpty ||
                subjectIds.contains(item.subjectId)) &&
            item.category == category,
      )) {
        final itemEvidence = item.evidenceAt ?? item.scheduledAt;
        if (itemEvidence != null &&
            (evidenceAt == null || itemEvidence.isAfter(evidenceAt))) {
          evidenceAt = itemEvidence;
        }
        if (item.state == 'pending') {
          final useWindowStart = category == 'newAssignment' &&
              !DaytimeCheckPolicy.isInWindow(now) &&
              plannedAt != null &&
              (item.scheduledAt == null ||
                  item.scheduledAt!.isBefore(plannedAt));
          final effectiveAt = useWindowStart ? plannedAt : item.scheduledAt;
          final validTime =
              category == 'newAssignment' || effectiveAt?.isAfter(now) == true;
          if (validTime && effectiveAt != null) {
            if (candidateAt == null || effectiveAt.isBefore(candidateAt)) {
              candidateAt = effectiveAt;
            }
          }
          if (item.alarmScheduled == false) {
            reasons.add('scheduleUnconfirmed');
          } else if (validTime && !recoveryPending) {
            confirmed = true;
            final nextAt = effectiveAt ?? plannedAt;
            if (nextAt != null &&
                (confirmedAt == null || nextAt.isBefore(confirmedAt))) {
              confirmedAt = nextAt;
            }
          }
        }
      }
      for (final item in evidence.pluginEvidence.where(
        (item) =>
            (item.subjectId.isEmpty || subjectIds.contains(item.subjectId)) &&
            item.category == category,
      )) {
        final itemEvidence = item.evidenceAt ?? item.scheduledAt;
        if (itemEvidence != null &&
            (evidenceAt == null || itemEvidence.isAfter(evidenceAt))) {
          evidenceAt = itemEvidence;
        }
        if (item.state == 'confirmedScheduled' &&
            item.scheduledAt?.isAfter(now) == true) {
          if (candidateAt == null || item.scheduledAt!.isBefore(candidateAt)) {
            candidateAt = item.scheduledAt;
          }
          final systemCheckOk =
              plugin != null && plugin.error == null && !pluginQueryFailed;
          final matchesSystem = systemCheckOk &&
              item.notificationId != null &&
              plugin.items.any(
                (systemItem) =>
                    systemItem.id == item.notificationId &&
                    systemItem.pending &&
                    (item.expectedPayload == null ||
                        systemItem.payload == item.expectedPayload),
              );
          if (matchesSystem) {
            if (!recoveryPending) {
              confirmed = true;
              if (confirmedAt == null ||
                  item.scheduledAt!.isBefore(confirmedAt)) {
                confirmedAt = item.scheduledAt;
              }
            }
          } else if (systemCheckOk) {
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
        status: eligibilityFailureReasons(reasons)
            ? ReminderExplanationStatus.ineligible
            : ReminderExplanationStatus.deferred,
        reasonCodes: _ordered(reasons),
        nextScheduledAt: null,
        evidenceAt: evidenceAt,
        actionLabel: null,
      );
    }

    final systemSettingBlock = reasons.any(
      const {'notificationPermissionOff', 'channelOff'}.contains,
    );
    final scheduleTimingBlocked = reasons.any(
      const {'outsideWindow', 'cooldown', 'offsetWindowPassed'}.contains,
    );
    if (systemSettingBlock || scheduleTimingBlocked) {
      return ReminderCategoryExplanation(
        category: category,
        status: ReminderExplanationStatus.deferred,
        reasonCodes: _ordered(reasons),
        nextScheduledAt: confirmedAt ?? candidateAt ?? plannedAt,
        evidenceAt: evidenceAt,
        actionLabel: systemSettingBlock ? '检查系统通知设置' : null,
      );
    }

    final anyQueryFailed = healthQueryFailed ||
        subjectQueryFailed ||
        (!isNativeCategory && (pluginQueryFailed || plugin?.error != null)) ||
        (evidence?.queryWarnings.isNotEmpty == true);
    if (anyQueryFailed && (!confirmed || recoveryPending)) {
      reasons.add('queryFailed');
      return ReminderCategoryExplanation(
        category: category,
        status: ReminderExplanationStatus.queryFailed,
        reasonCodes: _ordered(reasons),
        nextScheduledAt: confirmedAt ?? candidateAt ?? plannedAt,
        evidenceAt: evidenceAt,
        actionLabel: '重新查询',
      );
    }

    final unknownSystemBlock = reasons.contains('permissionUnknown') ||
        reasons.contains('channelUnknown');
    if (unknownSystemBlock && !confirmed) {
      return ReminderCategoryExplanation(
        category: category,
        status: ReminderExplanationStatus.deferred,
        reasonCodes: _ordered(reasons),
        nextScheduledAt: confirmedAt ?? candidateAt ?? plannedAt,
        evidenceAt: evidenceAt,
        actionLabel: '检查系统通知设置',
      );
    }

    final finalConfirmed = confirmed &&
        !recoveryPending &&
        !reasons.contains('scheduleUnconfirmed');
    return ReminderCategoryExplanation(
      category: category,
      status: finalConfirmed
          ? ReminderExplanationStatus.planned
          : ReminderExplanationStatus.unconfirmed,
      reasonCodes: _ordered(reasons),
      nextScheduledAt: finalConfirmed
          ? (confirmedAt ?? candidateAt ?? plannedAt)
          : (candidateAt ?? plannedAt),
      evidenceAt: evidenceAt,
      actionLabel: finalConfirmed ? null : '重试提醒恢复',
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
          'deadlineUnknown',
          'deadlineReadFailed',
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
    ReminderChannelHealth? channel, {
    bool healthQueryFailed = false,
  }) {
    if (health == null) {
      return healthQueryFailed
          ? const ['queryFailed']
          : const ['permissionUnknown', 'channelUnknown'];
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
      'quietHours',
      'lateQuietSuppressed',
      'missingDeadlineSource',
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

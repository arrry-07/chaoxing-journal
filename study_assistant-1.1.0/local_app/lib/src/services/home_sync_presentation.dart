import '../models/assignment.dart';
import '../models/sync_report.dart';
import 'assignment_query.dart';

enum HomeSyncAction { none, read, retry, login, verify, settings }

class HomeSyncPresentation {
  const HomeSyncPresentation(
    this.summary,
    this.action, {
    this.showCached = false,
    this.gentle = false,
  });

  final String summary;
  final HomeSyncAction action;
  final bool showCached;
  final bool gentle;

  String? get actionLabel => switch (action) {
        HomeSyncAction.none => null,
        HomeSyncAction.read => '读取作业',
        HomeSyncAction.retry => '重试',
        HomeSyncAction.login => '重新登录',
        HomeSyncAction.verify => '完成验证',
        HomeSyncAction.settings => '去处理'
      };
  static HomeSyncPresentation from(SyncReport report,
      {required bool loading,
      required bool hasCache,
      required DateTime now,
      DateTime? successAt,
      bool? hasPreviousData,
      bool serviceWarning = false}) {
    if (loading || report.phase == SyncPhase.running) {
      return HomeSyncPresentation(
          hasCache ? '正在更新…' : '正在读取作业…', HomeSyncAction.none);
    }
    if (report.phase == SyncPhase.failed || report.phase == SyncPhase.partial) {
      final action =
          report.issues.any((i) => i.kind == SyncIssueKind.authExpired)
              ? HomeSyncAction.login
              : report.issues
                      .any((i) => i.kind == SyncIssueKind.verificationRequired)
                  ? HomeSyncAction.verify
                  : HomeSyncAction.retry;
      bool sourceFailed(String name) => report.sourceResults.any((source) =>
          source.source == name &&
          !source.isNormalDegradation &&
          const {SyncSourcePhase.partial, SyncSourcePhase.failed}
              .contains(source.phase));
      final hasWorkListFailure = sourceFailed('courseWork') ||
          (report.sourceResults.isEmpty &&
              report.issues.any((issue) =>
                  issue.stage != 'detail' &&
                  issue.stage != 'courseNotice' &&
                  issue.stage != 'persistence' &&
                  !issue.stage.startsWith('exam')));
      final hasExamFailure = report.incompleteExamSourceCount > 0;
      final hasClassroomFailure = report.sourceResults.any((source) =>
          source.source.startsWith('classroomActivity:') &&
          !source.isNormalDegradation &&
          const {SyncSourcePhase.partial, SyncSourcePhase.failed}
              .contains(source.phase));
      final hasCourseNoticeFailure = sourceFailed('courseNotice');
      final hasDetailFailure =
          report.issues.any((issue) => issue.stage == 'detail') ||
              report.sourceResults
                  .any((source) => source.detailUnconfirmedCount > 0);
      final hasStorageFailure = report.issues.any((issue) =>
          issue.kind == SyncIssueKind.storage || issue.stage == 'persistence');
      final knownSources = {
        'courseWork',
        'exam',
        'examAccount',
        'examNotice',
        'courseNotice',
      };
      final hasOtherSourceFailure = report.sourceResults.any((source) =>
          !source.isNormalDegradation &&
          const {SyncSourcePhase.partial, SyncSourcePhase.failed}
              .contains(source.phase) &&
          !knownSources.contains(source.source) &&
          !source.source.startsWith('classroomActivity:'));
      final categories = [
        hasWorkListFailure,
        hasDetailFailure,
        hasExamFailure,
        hasClassroomFailure,
        hasCourseNoticeFailure,
        hasStorageFailure,
        hasOtherSourceFailure,
      ].where((value) => value).length;
      if (report.phase != SyncPhase.partial ||
          categories > 0 ||
          report.failedCourses > 0 ||
          report.issues.isNotEmpty) {
        final updatedButNeedsAttention = hasStorageFailure &&
            categories == 1 &&
            report.issues.any((issue) => issue.stage == 'persistence');
        final showCached = hasCache &&
            successAt != null &&
            (hasPreviousData ?? hasCache) &&
            (hasWorkListFailure ||
                hasExamFailure ||
                hasClassroomFailure ||
                hasOtherSourceFailure);
        final partialSummary = updatedButNeedsAttention
            ? '作业数据已保存，但同步状态记录需要处理'
            : categories > 1
                ? '部分课业信息未更新'
                : hasDetailFailure
                    ? '部分截止时间待确认'
                    : hasCourseNoticeFailure
                        ? '部分课程通知未更新'
                        : hasExamFailure
                            ? '部分考试信息未更新'
                            : hasClassroomFailure
                                ? '部分课堂任务未更新'
                                : '部分课程作业未更新';
        final pureNetworkFailure = report.phase == SyncPhase.failed &&
            hasCache &&
            report.issues.isNotEmpty &&
            report.issues.every((i) => i.kind == SyncIssueKind.network);
        if (pureNetworkFailure) {
          return const HomeSyncPresentation(
            '网络暂不可用',
            HomeSyncAction.retry,
            showCached: true,
            gentle: true,
          );
        }
        return HomeSyncPresentation(
            report.phase == SyncPhase.partial
                ? partialSummary
                : hasCache
                    ? '更新失败'
                    : '暂时无法读取作业',
            action,
            showCached:
                report.phase == SyncPhase.failed ? hasCache : showCached);
      }
    }
    if (serviceWarning) {
      return const HomeSyncPresentation(
          '作业已更新，提醒需要处理', HomeSyncAction.settings);
    }
    final updated = report.lastDataSuccessAt ?? successAt;
    if (report.phase == SyncPhase.success || updated != null) {
      if (updated == null) {
        return const HomeSyncPresentation('刚刚更新', HomeSyncAction.none);
      }
      final elapsed = now.difference(updated);
      if (!elapsed.isNegative && elapsed > const Duration(hours: 24)) {
        return HomeSyncPresentation(
          '${elapsed.inDays}天前更新',
          HomeSyncAction.none,
        );
      }
      final local = updated.toLocal();
      return HomeSyncPresentation(
          elapsed.inMinutes < 1
              ? '刚刚更新'
              : '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} 更新',
          HomeSyncAction.none);
    }
    return const HomeSyncPresentation('尚未读取作业', HomeSyncAction.read);
  }
}

class HomeDueSummary {
  const HomeDueSummary({
    required this.dueToday,
    required this.dueIn3Days,
    required this.completedToday,
  });

  final int dueToday;
  final int dueIn3Days;
  final int completedToday;

  factory HomeDueSummary.from(
    List<Assignment> catalogAssignments, {
    required DateTime now,
    AssignmentDisplayIndex? index,
  }) {
    final todayDay = AssignmentQuery.dayKey(now);
    final day3End = DateTime(todayDay.year, todayDay.month, todayDay.day + 2);
    final projected = AssignmentQuery.projectDisplay(
      catalogAssignments,
      index: index,
    );
    final seenKeys = <String>{};
    var dueToday = 0;
    var dueIn3Days = 0;
    var completedToday = 0;

    for (final assignment in projected) {
      if (assignment.isExam) continue;
      if (!assignment.isFormal && !assignment.isSupportedClassroomTask) {
        continue;
      }
      if (assignment.availability == AssignmentAvailability.unavailable) {
        continue;
      }
      final dedupeKey = assignment.courseTaskKey ?? assignment.id;
      if (!seenKeys.add(dedupeKey)) continue;
      if (AssignmentQuery.isArchivedPastTerm(assignment, now) ||
          AssignmentQuery.isArchivedClassroomPractice(assignment, now)) {
        continue;
      }
      final deadline = assignment.deadlineAt;
      if (deadline == null ||
          !assignment.deadlineTrusted ||
          assignment.deadlineReadFailed) {
        continue;
      }
      final dueDay = AssignmentQuery.dayKey(deadline);
      if (assignment.isCompleted) {
        if (dueDay == todayDay) completedToday++;
        continue;
      }
      if (!assignment.isPendingConfirmed ||
          assignment.status == 'overdue' ||
          !deadline.isAfter(now)) {
        continue;
      }
      if (dueDay == todayDay) {
        dueToday++;
        dueIn3Days++;
      } else if (!dueDay.isBefore(todayDay) && !dueDay.isAfter(day3End)) {
        dueIn3Days++;
      }
    }
    return HomeDueSummary(
      dueToday: dueToday,
      dueIn3Days: dueIn3Days,
      completedToday: completedToday,
    );
  }

  String label({required bool compact}) {
    if (dueToday > 0) {
      return compact
          ? '今日 $dueToday · 3日 $dueIn3Days'
          : '今日待交 $dueToday · 3日内 $dueIn3Days';
    }
    final prefix = completedToday > 0 ? '今日已交完' : '今日无待交';
    if (dueIn3Days > 0) {
      return compact ? '$prefix · 3日 $dueIn3Days' : '$prefix · 3日内 $dueIn3Days';
    }
    return prefix;
  }
}

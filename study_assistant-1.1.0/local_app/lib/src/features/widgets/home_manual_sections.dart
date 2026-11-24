import '../../models/assignment.dart';
import '../../models/local_coursework_state.dart';
import '../../services/assignment_query.dart';
import '../../services/assignment_store.dart';
import '../../services/exam_schedule_presentation.dart';
import '../../services/home_manual_timeline.dart';

enum HomeDayHeadingTone { normal, today, undated, overdue }

typedef HomeTimelineSection = ({
  String? heading,
  HomeDayHeadingTone tone,
  String? badge,
  List<HomeTimelineItem> items,
  bool pinned,
});

/// Splits the mixed timeline into the pinned block plus date groups.
///
/// [recovery] keeps full-year headings and disables pinned/date shortcuts for
/// the calendar recovery views.
List<HomeTimelineSection> buildHomeTimelineSections({
  required List<HomeTimelineItem> list,
  required DateTime now,
  required AssignmentStore store,
  required bool recovery,
  required LocalCourseworkState coursework,
  required List<Assignment> examSources,
  required AssignmentDisplayIndex? displayIndex,
}) {
  final sections = <HomeTimelineSection>[];
  var regular = list;

  void flushGroup({
    String? heading,
    HomeDayHeadingTone tone = HomeDayHeadingTone.normal,
    String? badge,
    required List<HomeTimelineItem> rows,
    bool pinned = false,
  }) {
    if (rows.isEmpty) return;
    sections.add((
      heading: heading,
      tone: tone,
      badge: badge,
      items: rows,
      pinned: pinned,
    ));
  }

  if (!recovery && store.isAuthenticated) {
    final pinned = <HomeTimelineItem>[];
    regular = <HomeTimelineItem>[];
    for (final item in list) {
      final isPinned = item.isManual
          ? store.isManualPinned(item.manual!)
          : store.isPinned(item.assignment!) &&
              !store.isHomeAssignmentPreviewOnly(item.assignment!.id);
      if (isPinned) {
        pinned.add(item);
      } else {
        regular.add(item);
      }
    }
    if (pinned.isNotEmpty) {
      DateTime? autoPinnedTime(HomeTimelineItem item) {
        if (item.isManual) return item.displayAt;
        final assignment = item.assignment!;
        if (assignment.isExam) {
          return assignment.exam?.startTrusted == true
              ? assignment.exam!.startAt
              : null;
        }
        return AssignmentQuery.effectiveDeadline(
          assignment,
          coursework: coursework,
        )?.at;
      }

      int compareAutoPinned(
        HomeTimelineItem left,
        HomeTimelineItem right,
      ) {
        final lt = autoPinnedTime(left);
        final rt = autoPinnedTime(right);
        if (lt != null && rt != null) {
          final cmp = lt.compareTo(rt);
          if (cmp != 0) return cmp;
        } else if (lt != null) {
          return -1;
        } else if (rt != null) {
          return 1;
        }
        return left.pinKey.compareTo(right.pinKey);
      }

      final orderedPinned = store.pinnedAssignments.orderItems(
        pinned,
        keyOf: (item) => item.pinKey,
        defaultComparator: compareAutoPinned,
      );
      flushGroup(
        heading: '置顶',
        tone: HomeDayHeadingTone.today,
        rows: orderedPinned,
        pinned: true,
      );
    }
  }

  String? previousKey;
  String? activeHeading;
  String? activeBadge;
  var activeTone = HomeDayHeadingTone.normal;
  var activeRows = <HomeTimelineItem>[];
  var overdueTierAnnounced = false;
  final todayDay = AssignmentQuery.dayKey(now);
  final tomorrowDay = DateTime(todayDay.year, todayDay.month, todayDay.day + 1);

  for (final item in regular) {
    final assignment = item.assignment;
    final bucket = item.bucketAt(now, coursework: coursework);
    final isOverdue = bucket == AssignmentDeadlineBucket.overdue;
    DateTime? badgeDay;
    String? key;
    String? heading;
    if (item.isManual) {
      final at = item.manual!.at;
      if (at != null) {
        final day = AssignmentQuery.dayKey(at);
        badgeDay = day;
        final showYear = recovery || day.year != todayDay.year;
        key = '${showYear ? '' : 'work:'}${day.year}:${day.month}:${day.day}';
        heading = '${showYear ? '${day.year}年' : ''}${day.month}月${day.day}日 '
            '周${'一二三四五六日'[day.weekday - 1]}';
      } else {
        key = 'noDeadline';
        heading = '无截止日期';
      }
    } else if (assignment!.isExam) {
      final stamp = ExamSchedulePresentation.build(
        assignment,
        records: examSources,
        index: displayIndex,
      ).timeline;
      key = stamp?.key;
      heading = stamp?.heading;
      final start = assignment.timelineAt;
      if (start != null && (assignment.timelineTrusted || recovery)) {
        badgeDay = AssignmentQuery.dayKey(start);
      }
    } else {
      final resolvedWorkAt = item.displayAt;
      if (resolvedWorkAt != null) {
        final day = AssignmentQuery.dayKey(resolvedWorkAt);
        badgeDay = day;
        final showYear = recovery || day.year != todayDay.year;
        key = '${showYear ? '' : 'work:'}${day.year}:${day.month}:${day.day}';
        heading = '${showYear ? '${day.year}年' : ''}${day.month}月${day.day}日 '
            '周${'一二三四五六日'[day.weekday - 1]}';
      }
    }
    if (heading == null && !recovery) {
      if (assignment != null &&
          !assignment.isExam &&
          bucket == AssignmentDeadlineBucket.confirmedNoDeadline) {
        key = 'noDeadline';
        heading = '无截止日期';
      } else {
        key = 'undated';
        heading = '无日期与待确认';
      }
    }
    final effectiveKey = isOverdue ? 'overdue:$key' : key;
    if (heading != null && effectiveKey != previousKey) {
      flushGroup(
        heading: activeHeading,
        tone: activeTone,
        badge: activeBadge,
        rows: activeRows,
      );
      activeRows = <HomeTimelineItem>[];
      activeHeading = heading;
      activeBadge = null;
      activeTone = HomeDayHeadingTone.normal;
      if (isOverdue) {
        activeTone = HomeDayHeadingTone.overdue;
        if (!overdueTierAnnounced && !recovery) {
          activeBadge = '已逾期置底';
          overdueTierAnnounced = true;
        }
      } else if (key == 'undated' || key == 'noDeadline') {
        activeTone = HomeDayHeadingTone.undated;
      } else if (badgeDay == todayDay) {
        activeTone = HomeDayHeadingTone.today;
        activeBadge = '今天';
      } else if (!recovery && badgeDay == tomorrowDay) {
        activeTone = HomeDayHeadingTone.today;
        activeBadge = '明天';
      }
    }
    previousKey = effectiveKey;
    activeRows.add(item);
  }

  flushGroup(
    heading: activeHeading,
    tone: activeTone,
    badge: activeBadge,
    rows: activeRows,
  );
  return sections;
}

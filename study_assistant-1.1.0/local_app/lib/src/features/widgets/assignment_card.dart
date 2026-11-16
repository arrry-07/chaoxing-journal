import '../../models/display_preferences.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/journal.dart';
import '../../models/assignment.dart';
import '../../services/assignment_query.dart';
import '../../services/exam_schedule_presentation.dart';

class AssignmentCard extends StatelessWidget {
  const AssignmentCard(
      {super.key,
      required this.assignment,
      required this.now,
      required this.onTap,
      this.onOpenAssignment,
      this.examSources = const [],
      this.opening = false,
      this.compact = false,
      this.countdown = false,
      this.showFullDeadline = true,
      this.deadlinePending = false,
      this.previewOnly = false,
      this.previewSaving = false});
  final Assignment assignment;
  final List<Assignment> examSources;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback? onOpenAssignment;
  final bool opening;
  final bool showFullDeadline;
  final bool deadlinePending, previewOnly, previewSaving;
  final bool compact, countdown;

  static String examStateLabel(Assignment assignment, DateTime now) {
    final exam = assignment.exam!;
    final lifecycle = exam.lifecycle == 'cancelled'
        ? '已取消'
        : exam.lifecycle == 'ended' ||
                (exam.endTrusted &&
                    exam.endAt != null &&
                    !exam.endAt!.isAfter(now))
            ? '已结束'
            : exam.lifecycle == 'inProgress'
                ? '进行中'
                : exam.lifecycle == 'scheduled' ||
                        (exam.startTrusted &&
                            exam.startAt != null &&
                            exam.startAt!.isAfter(now))
                    ? '未开始'
                    : null;
    final personal = assignment.status == 'submitted'
        ? '已提交'
        : assignment.status == 'pending'
            ? lifecycle == '进行中'
                ? '待提交'
                : lifecycle == '未开始'
                    ? '待参加'
                    : '待完成'
            : const {
                'graded': '已批阅',
                'reviewing': '待批阅',
                'completed': '已完成',
                'returned': '已退回'
              }[assignment.status];
    return [
      exam.noticeOnly ? '考试通知' : '考试',
      if (lifecycle != null) lifecycle,
      if (personal != null) personal,
    ].join(' · ');
  }

  static List<String> examScheduleLines(Assignment assignment) {
    final exam = assignment.exam!;
    return [
      ...ExamSchedulePresentation.build(assignment).cardTimeLines,
      if (exam.durationMinutes != null && exam.durationMinutes! > 0)
        '时长 ${exam.durationMinutes} 分钟',
      if (exam.location.trim().isNotEmpty) '地点 ${exam.location.trim()}',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final a = assignment, d = a.timelineAt;
    final bucket = AssignmentQuery.timelineBucketAt(a, now);
    final overdue = bucket == AssignmentDeadlineBucket.overdue;
    final today = d != null &&
        bucket != AssignmentDeadlineBucket.unconfirmed &&
        AssignmentQuery.dayKey(d) == AssignmentQuery.dayKey(now);
    final urgent = overdue
        ? '已逾期${now.difference(d!).inDays > 0 ? '${now.difference(d).inDays}天' : ''}'
        : !a.isExam &&
                a.isPendingConfirmed &&
                a.deadlineTrusted &&
                !a.deadlineReadFailed &&
                today
            ? '今天截止'
            : null;
    final state = a.isExam
        ? examStateLabel(a, now)
        : a.status == 'overdue' &&
                bucket == AssignmentDeadlineBucket.unconfirmed
            ? '状态或截止待确认'
            : a.isSupportedClassroomTask
                ? '任务 · ${a.statusLabel}'
                : a.statusLabel;
    final examSchedule = a.isExam
        ? ExamSchedulePresentation.build(a, records: examSources)
        : null;
    final examLines = a.isExam
        ? <String>[
            if (a.exam!.durationMinutes != null && a.exam!.durationMinutes! > 0)
              '时长 ${a.exam!.durationMinutes} 分钟',
            if (a.exam!.location.trim().isNotEmpty)
              '地点 ${a.exam!.location.trim()}',
          ]
        : const <String>[];
    // Keep the complete schedule available to screen readers and details,
    // while the visual card follows the assignment timeline layout.
    final examSemantics = [
      ...?examSchedule?.detailTimeLines,
      ...examLines,
    ].join('，');
    final deadline = deadlinePending
        ? '正在确认截止时间'
        : a.deadlineReadFailed
            ? d == null
                ? a.deadlineLabel
                : '截止 ${DateFormat('M月d日 HH:mm').format(AssignmentQuery.beijing(d))} · ${a.deadlineLabel}'
            : bucket == AssignmentDeadlineBucket.unconfirmed &&
                    d == null &&
                    a.deadlineTrusted &&
                    !a.deadlineReadFailed
                ? '截止信息待确认'
                : !a.deadlineTrusted
                    ? a.deadlineLabel
                    : d == null
                        ? '无期限'
                        : countdown
                            ? DisplayPreferences.remaining(d, now)
                            : '截止 ${DateFormat('M月d日 HH:mm').format(AssignmentQuery.beijing(d))}';
    final color = urgent != null ? Journal.berry : Journal.ink;
    final hasTime =
        d != null && a.timelineTrusted && (a.isExam || !a.deadlineReadFailed);
    final clock = hasTime
        ? DateFormat('HH:mm').format(AssignmentQuery.beijing(d))
        : examSchedule?.timeline?.clock ?? '';
    final showRail = clock.isNotEmpty || (deadlinePending && !a.isExam);
    // Measure at the user's text scale: a fixed rail clips times at 2× size.
    final timeMeasure = TextPainter(
        text: const TextSpan(text: '00:00', style: Journal.time),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context))
      ..layout();
    final railWidth = timeMeasure.width.ceilToDouble() + 4;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    timeMeasure.dispose();
    final metadata = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.isNotEmpty)
          Text(state, style: Journal.metadata.copyWith(color: Journal.ink)),
        if (previewOnly)
          Text(
            previewSaving ? '正在保存到本机' : '待保存预览',
            style: Journal.metadata.copyWith(
              color: Journal.sage,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (urgent != null)
          Text(urgent,
              style: Journal.metadata
                  .copyWith(color: color, fontWeight: FontWeight.w600)),
        if (a.isExam)
          for (final line in examLines) Text(line, style: Journal.metadata)
        else if (showFullDeadline || countdown || !hasTime)
          Text(deadline, style: Journal.metadata),
      ],
    );
    final onCardTap = previewOnly ? null : onTap;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
          button: onCardTap != null,
          onTap: onCardTap,
          label:
              '${a.title}，${a.courseName}，$state，${previewOnly ? '${previewSaving ? '正在保存到本机' : '待保存预览'}，' : ''}${urgent == null ? '' : '$urgent，'}${a.isExam ? '$examSemantics${a.exam!.startTrusted || a.exam!.endTrusted ? '，北京时间' : ''}' : hasTime ? '截止 ${DateFormat('M月d日 HH:mm').format(AssignmentQuery.beijing(d))}' : deadline}',
          excludeSemantics: true,
          child: SizedBox(
              width: double.infinity,
              child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                      onTap: onCardTap,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                          padding: EdgeInsets.only(
                              top: compact ? 4 : 12,
                              bottom: onOpenAssignment == null
                                  ? (compact ? 4 : 12)
                                  : 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showRail)
                                SizedBox(
                                  width: railWidth,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (deadlinePending && !a.isExam)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: SizedBox.square(
                                            dimension: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              semanticsLabel: '正在确认截止时间',
                                            ),
                                          ),
                                        )
                                      else
                                        Text(clock, style: Journal.time),
                                    ],
                                  ),
                                ),
                              if (showRail) const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                    if (a.title.trim().isNotEmpty)
                                      Text(a.title.trim(),
                                          style: Journal.entryTitle),
                                    if (a.courseName.trim().isNotEmpty) ...[
                                      if (a.title.trim().isNotEmpty)
                                        const SizedBox(height: 4),
                                      Text(a.courseName.trim(),
                                          style: a.title.trim().isEmpty
                                              ? Journal.entryTitle
                                              : Journal.metadata),
                                    ],
                                    if (onOpenAssignment == null) ...[
                                      const SizedBox(height: 4),
                                      metadata,
                                    ],
                                  ])),
                            ],
                          )))))),
      if (onOpenAssignment != null)
        Padding(
          padding: EdgeInsets.only(
              left: largeText || !showRail ? 0 : railWidth + 12, bottom: 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Padding(
                padding: EdgeInsets.only(
                    left: largeText && showRail ? railWidth + 12 : 0),
                child: ExcludeSemantics(
                    child: InkWell(onTap: onCardTap, child: metadata)),
              ),
              TextButton.icon(
                onPressed: previewOnly || opening ? null : onOpenAssignment,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.launch, size: 18),
                label: Text(previewOnly
                    ? '保存后可打开'
                    : opening
                        ? '正在打开…'
                        : a.isExam
                            ? a.exam!.noticeOnly
                                ? '在学习通内查看考试通知'
                                : '在学习通内查看考试'
                            : '在学习通内打开作业'),
              ),
            ],
          ),
        ),
    ]);
  }
}

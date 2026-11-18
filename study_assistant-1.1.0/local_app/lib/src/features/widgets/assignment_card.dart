import '../../models/display_preferences.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/journal.dart';
import '../../models/assignment.dart';
import '../../services/assignment_query.dart';
import '../../services/exam_schedule_presentation.dart';
import 'coursework_status_pill.dart';

class AssignmentCard extends StatelessWidget {
  const AssignmentCard(
      {super.key,
      required this.assignment,
      required this.now,
      required this.onTap,
      this.onOpenAssignment,
      this.examSources = const [],
      this.displayIndex,
      this.opening = false,
      this.compact = false,
      this.countdown = false,
      this.showFullDeadline = true,
      this.deadlinePending = false,
      this.previewOnly = false,
      this.previewSaving = false});
  final Assignment assignment;
  final List<Assignment> examSources;
  final AssignmentDisplayIndex? displayIndex;
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

  CourseworkPillTone _stateTone(Assignment a, AssignmentDeadlineBucket bucket) {
    if (a.isExam) return CourseworkPillTone.exam;
    if (a.isCompleted) return CourseworkPillTone.completed;
    if (bucket == AssignmentDeadlineBucket.unconfirmed ||
        a.status == 'unknown' ||
        !a.deadlineTrusted ||
        a.deadlineReadFailed) {
      return CourseworkPillTone.unconfirmed;
    }
    return CourseworkPillTone.neutral;
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
        ? ExamSchedulePresentation.build(a,
            records: examSources, index: displayIndex)
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
      if (examSchedule?.verificationNote != null)
        examSchedule!.verificationNote!,
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
    final hasTime =
        d != null && a.timelineTrusted && (a.isExam || !a.deadlineReadFailed);
    final clock = hasTime
        ? DateFormat('HH:mm').format(AssignmentQuery.beijing(d))
        : examSchedule?.timeline?.clock ?? '';
    // Undated rows keep the same rail so titles stay in one column.
    final railLabel = clock.isNotEmpty
        ? clock
        : bucket == AssignmentDeadlineBucket.confirmedNoDeadline
            ? '—'
            : '待定';
    // Measure at the user's text scale: a fixed rail clips times at 2× size.
    final timeMeasure = TextPainter(
        text: const TextSpan(text: '00:00', style: Journal.time),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context))
      ..layout();
    final railWidth = timeMeasure.width.ceilToDouble() + 4;
    final largeText = JournalLayout.isLargeText(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    timeMeasure.dispose();

    final isUnconfirmed = bucket == AssignmentDeadlineBucket.unconfirmed ||
        a.deadlineReadFailed ||
        !a.deadlineTrusted;
    final cardBorderColor = urgent != null
        ? Journal.berryBorder
        : isUnconfirmed && !a.isCompleted
            ? Journal.ochreBorder
            : Journal.rule;
    final railRuleColor = urgent != null
        ? Journal.berryBorder
        : isUnconfirmed && !a.isCompleted
            ? Journal.ochreBorder
            : Journal.rule;
    final railTextColor = urgent != null && today
        ? Journal.berry
        : clock.isEmpty
            ? (railLabel == '待定' ? Journal.ochre : Journal.muted)
            : (overdue ? Journal.muted : Journal.ink);

    final pills = <Widget>[
      if (state.isNotEmpty)
        CourseworkStatusPill(
          label: state,
          tone: _stateTone(a, bucket),
        ),
      if (previewOnly)
        CourseworkStatusPill(
          label: previewSaving ? '正在保存到本机' : '待保存预览',
          tone: CourseworkPillTone.unconfirmed,
          icon: Icons.sync_rounded,
        ),
      if (urgent != null)
        CourseworkStatusPill(
          label: urgent,
          tone: overdue
              ? CourseworkPillTone.overdue
              : CourseworkPillTone.urgentToday,
        ),
    ];

    final extraLines = <Widget>[
      if (a.isExam) ...[
        if (clock.isEmpty)
          for (final line in examSchedule?.cardTimeLines ?? const <String>[])
            Text(line, style: Journal.metadata),
        for (final line in examLines) Text(line, style: Journal.metadata),
      ] else if (showFullDeadline || countdown || !hasTime)
        Text(
          deadline,
          style: !hasTime && railLabel == '待定'
              ? Journal.metadata.copyWith(
                  color: Journal.ochre,
                  fontWeight: FontWeight.w600,
                )
              : Journal.metadata,
        ),
    ];

    final metadata = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pills.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: pills,
          ),
        if (extraLines.isNotEmpty) ...[
          if (pills.isNotEmpty) const SizedBox(height: 4),
          ...extraLines,
        ],
      ],
    );

    final onCardTap = previewOnly ? null : onTap;
    final openTooltip = previewOnly
        ? '保存后可打开'
        : opening
            ? '正在打开…'
            : a.isExam
                ? a.exam!.noticeOnly
                    ? '在学习通内查看考试通知'
                    : '在学习通内查看考试'
                : '在学习通内打开作业';
    final shortOpenLabel = previewOnly
        ? '待保存'
        : opening
            ? '正在打开…'
            : a.isExam
                ? '查看考试'
                : '打开作业';

    Widget buildLaunchControl() {
      final enabled = !previewOnly && !opening && onOpenAssignment != null;
      final iconWidget = opening && !reduceMotion
          ? const SizedBox.square(
              dimension: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Journal.ink,
              ),
            )
          : Icon(
              opening ? Icons.hourglass_top_rounded : Icons.open_in_new_rounded,
              size: 16,
              color: enabled ? Journal.ink : Journal.muted,
            );

      if (largeText) {
        return Semantics(
          button: true,
          enabled: enabled,
          label: openTooltip,
          child: Tooltip(
            message: openTooltip,
            child: OutlinedButton.icon(
              key: ValueKey('open-assignment-${a.id}'),
              onPressed: enabled ? onOpenAssignment : null,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                backgroundColor: Journal.parchment,
                side: const BorderSide(color: Journal.ruleStrong),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: iconWidget,
              label: ExcludeSemantics(
                child: Text(
                  shortOpenLabel,
                  style: Journal.metadata.copyWith(
                    color: enabled ? Journal.ink : Journal.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        );
      }

      return Semantics(
        button: true,
        enabled: enabled,
        label: openTooltip,
        excludeSemantics: true,
        child: IconButton(
          key: ValueKey('open-assignment-${a.id}'),
          tooltip: openTooltip,
          onPressed: enabled ? onOpenAssignment : null,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          padding: const EdgeInsets.all(7),
          icon: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Journal.parchment,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Journal.ruleStrong),
            ),
            alignment: Alignment.center,
            child: iconWidget,
          ),
        ),
      );
    }

    final verticalPad = compact ? 6.0 : 12.0;
    const railGap = 10.0;
    const vRuleWidth = 1.5;
    final contentLeftInset = railWidth + railGap + vRuleWidth + railGap;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cardBorderColor, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: onCardTap != null,
            onTap: onCardTap,
            label:
                '${a.title}，${a.courseName}，$state，${previewOnly ? '${previewSaving ? '正在保存到本机' : '待保存预览'}，' : ''}${urgent == null ? '' : '$urgent，'}${a.isExam ? '$examSemantics${a.exam!.startTrusted || a.exam!.endTrusted ? '，北京时间' : ''}' : hasTime ? '截止 ${DateFormat('M月d日 HH:mm').format(AssignmentQuery.beijing(d))}' : deadline}',
            excludeSemantics: true,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onCardTap,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: EdgeInsets.only(
                    top: verticalPad,
                    bottom: onOpenAssignment == null ? verticalPad : 4,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: railWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (deadlinePending && !a.isExam)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: reduceMotion
                                    ? const Icon(
                                        Icons.hourglass_top_rounded,
                                        size: 16,
                                        color: Journal.ochre,
                                        semanticLabel: '正在确认截止时间',
                                      )
                                    : const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Journal.ochre,
                                          semanticsLabel: '正在确认截止时间',
                                        ),
                                      ),
                              )
                            else
                              Text(
                                railLabel,
                                style: Journal.time.copyWith(
                                  color: railTextColor,
                                  fontSize: clock.isEmpty
                                      ? 14
                                      : Journal.time.fontSize,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: railGap),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: railRuleColor,
                                width: vRuleWidth,
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.only(left: railGap),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (a.title.trim().isNotEmpty)
                                Text(
                                  a.title.trim(),
                                  maxLines: largeText ? null : 2,
                                  overflow:
                                      largeText ? null : TextOverflow.ellipsis,
                                  style: overdue
                                      ? Journal.entryTitle.copyWith(
                                          color: const Color(0xFF36453E),
                                        )
                                      : Journal.entryTitle,
                                ),
                              if (a.courseName.trim().isNotEmpty) ...[
                                if (a.title.trim().isNotEmpty)
                                  const SizedBox(height: 3),
                                Text(
                                  a.courseName.trim(),
                                  style: a.title.trim().isEmpty
                                      ? Journal.entryTitle
                                      : Journal.metadata,
                                ),
                              ],
                              if (onOpenAssignment == null) ...[
                                const SizedBox(height: 6),
                                metadata,
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (onOpenAssignment != null)
            Padding(
              padding: EdgeInsets.only(
                left: largeText ? 0 : contentLeftInset,
                bottom: compact ? 4 : 8,
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      left: largeText ? contentLeftInset : 0,
                    ),
                    child: ExcludeSemantics(
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: onCardTap,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: metadata,
                          ),
                        ),
                      ),
                    ),
                  ),
                  buildLaunchControl(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

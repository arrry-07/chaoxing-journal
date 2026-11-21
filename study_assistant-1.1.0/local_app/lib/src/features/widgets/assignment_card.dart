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
      this.inPinnedSection = false,
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
  final bool showFullDeadline, inPinnedSection;
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
    final estimatedEnd =
        inPinnedSection ? examSchedule?.estimatedOvernightEndLabel : null;
    final examLines = a.isExam
        ? <String>[
            if (estimatedEnd != null) '结束（按时长推算） $estimatedEnd',
            if (a.exam!.durationMinutes != null && a.exam!.durationMinutes! > 0)
              '时长 ${a.exam!.durationMinutes} 分钟',
            if (a.exam!.location.trim().isNotEmpty)
              '地点 ${a.exam!.location.trim()}',
          ]
        : const <String>[];
    final examSemantics = [
      ...?examSchedule?.detailTimeLines,
      if (examSchedule?.verificationNote != null)
        examSchedule!.verificationNote!,
      ...examLines,
    ].join('，');
    final startText = a.availableFromAt != null
        ? '开始 ${DateFormat('M月d日 HH:mm').format(AssignmentQuery.beijing(a.availableFromAt!))}'
        : (a.availableFromText?.trim().isNotEmpty == true
            ? '开始 ${a.availableFromText!.trim()}'
            : null);
    String withStart(String value) =>
        startText == null ? value : '$startText · $value';
    final beijingDeadline = d == null ? null : AssignmentQuery.beijing(d);
    final deadlineDate = beijingDeadline == null
        ? ''
        : DateFormat(inPinnedSection &&
                    beijingDeadline.year != AssignmentQuery.beijing(now).year
                ? 'yyyy年M月d日 HH:mm'
                : 'M月d日 HH:mm')
            .format(beijingDeadline);
    final deadline = deadlinePending
        ? '正在确认截止时间'
        : a.deadlineReadFailed
            ? d == null
                ? withStart('截止时间待确认')
                : '截止 $deadlineDate · ${a.deadlineLabel}'
            : bucket == AssignmentDeadlineBucket.unconfirmed &&
                    d == null &&
                    a.deadlineTrusted &&
                    !a.deadlineReadFailed
                ? withStart('截止信息待确认')
                : !a.deadlineTrusted
                    ? withStart(a.deadlineLabel)
                    : d == null
                        ? withStart('无截止日期')
                        : countdown && !inPinnedSection
                            ? DisplayPreferences.remaining(d, now)
                            : '截止 $deadlineDate';
    final hasTime =
        d != null && a.timelineTrusted && (a.isExam || !a.deadlineReadFailed);
    final clock = hasTime
        ? DateFormat('HH:mm').format(AssignmentQuery.beijing(d))
        : examSchedule?.timeline?.clock ?? '';
    final railLabel = clock.isNotEmpty
        ? clock
        : bucket == AssignmentDeadlineBucket.confirmedNoDeadline
            ? '—'
            : '待定';
    final timeMeasure = TextPainter(
        text: const TextSpan(text: '00:00', style: Journal.time),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context))
      ..layout();
    final railWidth = timeMeasure.width.ceilToDouble() + 4;
    final largeText = JournalLayout.isLargeText(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    timeMeasure.dispose();

    final stateTone = _stateTone(a, bucket);
    final hasSpecialStatePill = stateTone != CourseworkPillTone.neutral;
    final railTextColor = urgent != null && today
        ? Journal.berry
        : clock.isEmpty
            ? (railLabel == '待定' ? Journal.ochre : Journal.muted)
            : (overdue ? Journal.muted : Journal.ink.withValues(alpha: 0.88));

    final highlightPills = <Widget>[
      if (state.isNotEmpty && hasSpecialStatePill)
        CourseworkStatusPill(
          label: state,
          tone: stateTone,
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
        if (clock.isEmpty || inPinnedSection)
          for (final line in examSchedule?.cardTimeLines ?? const <String>[])
            Text(line, style: Journal.metadata),
        if (examSchedule?.yearUnconfirmed == true)
          const Text('年份待确认', style: Journal.metadata),
        for (final line in examLines) Text(line, style: Journal.metadata),
      ] else if (showFullDeadline || inPinnedSection || countdown || !hasTime)
        Text(
          deadline,
          style: !hasTime && railLabel == '待定'
              ? Journal.metadata.copyWith(
                  color: Journal.ochre,
                  fontWeight: FontWeight.w600,
                )
              : Journal.metadata,
        ),
      if (!a.isExam && inPinnedSection && countdown && hasTime)
        Text(DisplayPreferences.remaining(d, now), style: Journal.metadata),
    ];

    final hasCourse = a.courseName.trim().isNotEmpty;
    final hasTitle = a.title.trim().isNotEmpty;
    final showPlainInlineState = state.isNotEmpty && !hasSpecialStatePill;

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
              size: 18,
              color: enabled
                  ? Journal.muted.withValues(alpha: 0.9)
                  : Journal.muted.withValues(alpha: 0.45),
            );

      if (largeText) {
        return Semantics(
          container: true,
          button: true,
          enabled: enabled,
          label: openTooltip,
          onTap: enabled ? onOpenAssignment : null,
          excludeSemantics: true,
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
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
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
        container: true,
        button: true,
        enabled: enabled,
        label: openTooltip,
        onTap: enabled ? onOpenAssignment : null,
        excludeSemantics: true,
        child: IconButton(
          key: ValueKey('open-assignment-${a.id}'),
          tooltip: openTooltip,
          onPressed: enabled ? onOpenAssignment : null,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          padding: EdgeInsets.zero,
          icon: iconWidget,
        ),
      );
    }

    final verticalPad = compact ? 9.0 : 13.0;
    const railGap = 10.0;
    final contentLeftInset = railWidth + railGap;

    final bodyColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasTitle)
          Text(
            a.title.trim(),
            maxLines: largeText ? null : 2,
            overflow: largeText ? null : TextOverflow.ellipsis,
            style: overdue
                ? Journal.entryTitle.copyWith(color: const Color(0xFF36453E))
                : Journal.entryTitle,
          )
        else if (hasCourse)
          Text(a.courseName.trim(), style: Journal.entryTitle),
        if ((hasTitle && hasCourse) || showPlainInlineState) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 5,
            runSpacing: 3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (hasTitle && hasCourse)
                Text(a.courseName.trim(), style: Journal.metadata),
              if (hasTitle && hasCourse && showPlainInlineState)
                Text(
                  '·',
                  style: Journal.metadata.copyWith(
                    color: Journal.muted.withValues(alpha: 0.65),
                  ),
                ),
              if (showPlainInlineState) Text(state, style: Journal.metadata),
              if (highlightPills.isNotEmpty && !hasSpecialStatePill)
                ...highlightPills,
            ],
          ),
        ],
        if (highlightPills.isNotEmpty &&
            (hasSpecialStatePill || (!hasCourse && !showPlainInlineState))) ...[
          const SizedBox(height: 5),
          Wrap(
            spacing: 6,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: highlightPills,
          ),
        ],
        if (extraLines.isNotEmpty) ...[
          const SizedBox(height: 4),
          ...extraLines,
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Semantics(
                button: onCardTap != null,
                onTap: onCardTap,
                label:
                    '${a.title}，${a.courseName}，$state，${previewOnly ? '${previewSaving ? '正在保存到本机' : '待保存预览'}，' : ''}${urgent == null ? '' : '$urgent，'}${a.isExam ? '$examSemantics${a.exam!.startTrusted || a.exam!.endTrusted ? '，北京时间' : ''}' : hasTime ? '截止 $deadlineDate${countdown ? '，${DisplayPreferences.remaining(d, now)}' : ''}' : deadline}',
                excludeSemantics: true,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: onCardTap,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: verticalPad),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: railWidth,
                            child: deadlinePending && !a.isExam
                                ? Align(
                                    alignment: Alignment.centerLeft,
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
                                : Text(
                                    railLabel,
                                    style: Journal.time.copyWith(
                                      color: railTextColor,
                                      fontWeight: clock.isEmpty
                                          ? FontWeight.w500
                                          : FontWeight.w600,
                                      fontSize: clock.isEmpty
                                          ? 14
                                          : Journal.time.fontSize,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: railGap),
                          Expanded(child: bodyColumn),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (onOpenAssignment != null && !largeText) ...[
              const SizedBox(width: 4),
              buildLaunchControl(),
            ],
          ],
        ),
        if (onOpenAssignment != null && largeText)
          Padding(
            padding: EdgeInsets.only(left: contentLeftInset, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: buildLaunchControl(),
            ),
          ),
        SizedBox(
          key: ValueKey('assignment-card-gap-${a.id}'),
          height: 4,
        ),
        Padding(
          padding: EdgeInsets.only(left: contentLeftInset),
          child: const Divider(
            height: 1,
            thickness: 0.8,
            color: Journal.rule,
          ),
        ),
      ],
    );
  }
}

import '../../models/display_preferences.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/journal.dart';
import '../../models/assignment.dart';
import '../../services/assignment_query.dart';

class AssignmentCard extends StatelessWidget {
  const AssignmentCard(
      {super.key,
      required this.assignment,
      required this.now,
      required this.onTap,
      this.onOpenAssignment,
      this.opening = false,
      this.compact = false,
      this.countdown = false,
      this.showFullDeadline = true,
      this.deadlinePending = false,
      this.previewOnly = false,
      this.previewSaving = false});
  final Assignment assignment;
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
                : exam.startTrusted &&
                        exam.startAt != null &&
                        exam.startAt!.isAfter(now)
                    ? '未开始'
                    : '考试安排待确认';
    final personal = assignment.status == 'submitted'
        ? '已提交'
        : assignment.status == 'pending' && lifecycle == '未开始'
            ? '待参加'
            : assignment.status == 'pending' && lifecycle == '进行中'
                ? '待提交'
                : '个人提交状态待确认';
    return '${exam.noticeOnly ? '考试通知' : '考试'} · $lifecycle · $personal';
  }

  static List<String> examScheduleLines(Assignment assignment) {
    final exam = assignment.exam!;
    String time(String label, DateTime? at, bool trusted) => at == null
        ? '$label时间待确认'
        : '$label ${DateFormat('yyyy年M月d日 HH:mm').format(AssignmentQuery.beijing(at))}${trusted ? '' : '（待确认）'}';
    return [
      time('开考', exam.startAt, exam.startTrusted),
      time('结束', exam.endAt, exam.endTrusted),
      if (exam.durationMinutes != null && exam.durationMinutes! > 0)
        '时长 ${exam.durationMinutes} 分钟',
      exam.location.trim().isEmpty
          ? exam.noticeOnly
              ? '地点 通知未提供实体考场'
              : '地点 官方考试页未提供实体考场'
          : '地点 ${exam.location.trim()}',
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
    final examLines = a.isExam ? examScheduleLines(a) : const <String>[];
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
    final clock =
        hasTime ? DateFormat('HH:mm').format(AssignmentQuery.beijing(d)) : '—';
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
              '${a.title}，${a.courseName}，$state，${previewOnly ? '${previewSaving ? '正在保存到本机' : '待保存预览'}，' : ''}${urgent == null ? '' : '$urgent，'}${a.isExam ? '${examLines.join('，')}，北京时间' : hasTime ? '截止 ${DateFormat('M月d日 HH:mm').format(AssignmentQuery.beijing(d))}' : deadline}',
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
                              SizedBox(
                                width: railWidth,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (deadlinePending && !a.isExam)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
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
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                    Text(a.title, style: Journal.entryTitle),
                                    const SizedBox(height: 4),
                                    Text(a.courseName, style: Journal.metadata),
                                    if (onOpenAssignment == null) ...[
                                      const SizedBox(height: 4),
                                      metadata,
                                    ],
                                  ])),
                            ],
                          )))))),
      if (onOpenAssignment != null)
        Padding(
          padding:
              EdgeInsets.only(left: largeText ? 0 : railWidth + 12, bottom: 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Padding(
                padding: EdgeInsets.only(left: largeText ? railWidth + 12 : 0),
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

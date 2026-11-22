import '../../models/display_preferences.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../app/journal.dart';
import '../../models/assignment.dart';
import '../../models/local_coursework_state.dart';
import '../../services/assignment_query.dart';
import '../../services/coursework_deadline.dart';
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
      this.courseworkEntry,
      this.opening = false,
      this.compact = false,
      this.countdown = false,
      this.showFullDeadline = true,
      this.showDivider = true,
      this.enableTapFeedback = true,
      this.inPinnedSection = false,
      this.dragHandle,
      this.deadlinePending = false,
      this.previewOnly = false,
      this.previewSaving = false,
      this.contentPadding = EdgeInsets.zero,
      this.onLongPress});
  final Assignment assignment;
  final List<Assignment> examSources;
  final AssignmentDisplayIndex? displayIndex;
  final LocalCourseworkEntry? courseworkEntry;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback? onOpenAssignment;
  final VoidCallback? onLongPress;
  final Widget? dragHandle;
  final EdgeInsetsGeometry contentPadding;
  final bool opening;
  final bool showFullDeadline, inPinnedSection, showDivider, enableTapFeedback;
  final bool deadlinePending, previewOnly, previewSaving;
  final bool compact, countdown;

  static final DateFormat _clockFormat = DateFormat('HH:mm');
  static (
    TextStyle,
    TextStyle,
    TextDirection,
    TextScaler,
    bool
  )? _cachedRailKey;
  static double _cachedRailWidth = 0;

  static double _measureRailWidth(
    TextStyle style,
    TextStyle metaStyle,
    TextDirection direction,
    TextScaler scaler, {
    required bool inPinnedSection,
  }) {
    final key = (style, metaStyle, direction, scaler, inPinnedSection);
    if (_cachedRailKey == key) return _cachedRailWidth;
    double widthFor(String text, TextStyle s) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: s),
        textDirection: direction,
        textScaler: scaler,
      )..layout();
      final w = painter.width.ceilToDouble() + 4;
      painter.dispose();
      return w;
    }

    var width = widthFor('00:00', style);
    if (inPinnedSection) {
      final dateWidth = widthFor('12/31',
          metaStyle.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600));
      final remWidth = widthFor('剩23小时', metaStyle.copyWith(fontSize: 11));
      if (dateWidth > width) width = dateWidth;
      if (remWidth > width) width = remWidth;
    }
    _cachedRailKey = key;
    _cachedRailWidth = width;
    return width;
  }

  static String _compactRemaining(DateTime deadline, DateTime now) {
    final diff = deadline.difference(now);
    if (diff.isNegative || diff.inSeconds <= 0) return '已逾期';
    final minutes = (diff.inMilliseconds / 60000).ceil();
    if (minutes < 60) return '剩$minutes分';
    if (minutes < 1440) return '剩${(minutes / 60).ceil()}小时';
    return '剩${(minutes / 1440).ceil()}天';
  }

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

  CourseworkPillTone _stateTone(
    Assignment a,
    AssignmentDeadlineBucket bucket, {
    bool hasManualDeadline = false,
  }) {
    if (a.isExam) return CourseworkPillTone.exam;
    if (a.isCompleted) return CourseworkPillTone.completed;
    if (bucket == AssignmentDeadlineBucket.unconfirmed ||
        a.status == 'unknown' ||
        (!hasManualDeadline && (!a.deadlineTrusted || a.deadlineReadFailed))) {
      return CourseworkPillTone.unconfirmed;
    }
    return CourseworkPillTone.neutral;
  }

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final a = assignment;
    final resolvedDeadline =
        a.isExam ? null : CourseworkDeadline.resolveEntry(a, courseworkEntry);
    final isManualDeadline = resolvedDeadline?.isManual == true;
    final d = a.isExam ? a.timelineAt : resolvedDeadline?.at;
    final bucket = a.isExam
        ? AssignmentQuery.timelineBucketAt(a, now)
        : CourseworkDeadline.bucketAt(a, now, entry: courseworkEntry);
    final overdue = bucket == AssignmentDeadlineBucket.overdue;
    final today = d != null &&
        bucket != AssignmentDeadlineBucket.unconfirmed &&
        AssignmentQuery.dayKey(d) == AssignmentQuery.dayKey(now);
    final urgent = overdue
        ? '${isManualDeadline ? '手动截止已过' : '已逾期'}${now.difference(d!).inDays > 0 ? '${now.difference(d).inDays}天' : ''}'
        : showFullDeadline &&
                !a.isExam &&
                a.isPendingConfirmed &&
                resolvedDeadline != null &&
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
        : isManualDeadline
            ? countdown && !inPinnedSection
                ? '手动 ${DisplayPreferences.remaining(d!, now)} · 官方待确认'
                : '手动截止 $deadlineDate · 官方待确认'
            : a.deadlineReadFailed
                ? (a.deadlineAt == null
                    ? withStart('截止时间待确认')
                    : '截止 ${DateFormat(inPinnedSection && AssignmentQuery.beijing(a.deadlineAt!).year != AssignmentQuery.beijing(now).year ? 'yyyy年M月d日 HH:mm' : 'M月d日 HH:mm').format(AssignmentQuery.beijing(a.deadlineAt!))} · ${a.deadlineLabel}')
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
        d != null && (a.isExam ? a.timelineTrusted : resolvedDeadline != null);
    final clock = hasTime
        ? _clockFormat.format(AssignmentQuery.beijing(d))
        : examSchedule?.timeline?.clock ?? '';
    final railLabel = clock.isNotEmpty
        ? clock
        : bucket == AssignmentDeadlineBucket.confirmedNoDeadline
            ? '—'
            : '待定';
    final railWidth = _measureRailWidth(
      journal.time,
      journal.metadata,
      Directionality.of(context),
      MediaQuery.textScalerOf(context),
      inPinnedSection: inPinnedSection,
    );
    final largeText = JournalLayout.isLargeText(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final stateTone =
        _stateTone(a, bucket, hasManualDeadline: isManualDeadline);
    final hasSpecialStatePill = stateTone != CourseworkPillTone.neutral;
    final highlightToday = today &&
        !overdue &&
        !a.isCompleted &&
        (a.isExam ? a.timelineTrusted : resolvedDeadline != null);
    final pinUrgent = inPinnedSection &&
        !overdue &&
        !a.isCompleted &&
        d != null &&
        (a.isExam ? a.timelineTrusted : resolvedDeadline != null) &&
        (today || d.difference(now) <= const Duration(hours: 48));
    final railTextColor = (highlightToday || pinUrgent)
        ? journal.berry
        : clock.isEmpty
            ? (railLabel == '待定' ? journal.ochre : journal.muted)
            : (overdue ? journal.muted : journal.ink.withValues(alpha: 0.88));

    final highlightPills = <Widget>[
      if (state.isNotEmpty && hasSpecialStatePill)
        CourseworkStatusPill(
          label: state,
          tone: stateTone,
        ),
      if (isManualDeadline)
        const CourseworkStatusPill(
          label: '手动',
          tone: CourseworkPillTone.neutral,
          icon: Icons.edit_calendar_outlined,
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
            Text(line, style: journal.metadata),
        if (examSchedule?.yearUnconfirmed == true)
          Text('年份待确认', style: journal.metadata),
        for (final line in examLines) Text(line, style: journal.metadata),
      ] else if (showFullDeadline ||
          inPinnedSection ||
          countdown ||
          !hasTime ||
          isManualDeadline)
        Text(
          inPinnedSection && countdown && hasTime
              ? '$deadline · ${DisplayPreferences.remaining(d, now)}'
              : deadline,
          style: !hasTime && railLabel == '待定'
              ? journal.metadata.copyWith(
                  color: journal.ochre,
                  fontWeight: FontWeight.w600,
                )
              : journal.metadata,
        ),
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
      final journal = Journal.of(context);
      final enabled = !previewOnly && !opening && onOpenAssignment != null;
      final iconWidget = opening && !reduceMotion
          ? SizedBox.square(
              dimension: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: journal.ink,
              ),
            )
          : Icon(
              opening ? Icons.hourglass_top_rounded : Icons.open_in_new_rounded,
              size: 18,
              color: enabled
                  ? journal.muted
                  : journal.muted.withValues(alpha: 0.45),
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
                backgroundColor: journal.parchment,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              icon: iconWidget,
              label: ExcludeSemantics(
                child: Text(
                  shortOpenLabel,
                  style: journal.metadata.copyWith(
                    color: enabled ? journal.ink : journal.muted,
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

    final verticalPad = compact ? 8.5 : 12.0;
    const railGap = 10.0;
    final contentLeftInset = railWidth + railGap;
    final contentRight =
        contentPadding.resolve(Directionality.of(context)).right;
    final hasInlineLaunch = onOpenAssignment != null && !largeText;
    final hasInlineDrag = dragHandle != null && !largeText;
    final topRightReserve = (hasInlineLaunch ? 48.0 : 0.0) +
        (hasInlineDrag ? 34.0 : 0.0) +
        ((hasInlineLaunch || hasInlineDrag) ? 6.0 : 0.0);
    final titlePadding = EdgeInsets.only(
      right: (hasInlineLaunch || hasInlineDrag)
          ? (topRightReserve - contentRight)
              .clamp(0.0, topRightReserve)
              .toDouble()
          : 0.0,
    );

    Widget buildPinnedRail() {
      if (d == null || !hasTime) {
        return Text(
          railLabel,
          style: journal.time.copyWith(
            color: railTextColor,
            fontWeight: clock.isEmpty ? FontWeight.w500 : FontWeight.w600,
            fontSize: clock.isEmpty ? 14 : journal.time.fontSize,
          ),
        );
      }
      final beijingD = AssignmentQuery.beijing(d);
      final todayDay = AssignmentQuery.dayKey(now);
      final tomorrowDay =
          DateTime(todayDay.year, todayDay.month, todayDay.day + 1);
      final dueDay = AssignmentQuery.dayKey(d);
      final dateLabel = dueDay == todayDay
          ? '今天'
          : dueDay == tomorrowDay
              ? '明天'
              : '${beijingD.month}/${beijingD.day}';
      final remLabel = overdue
          ? (isManualDeadline ? '手动已过' : '已逾期')
          : _compactRemaining(d, now);
      final dateColor = pinUrgent ? journal.berry : journal.muted;
      final clockColor =
          pinUrgent ? journal.berry : (overdue ? journal.muted : journal.ink);
      final remColor = pinUrgent ? journal.berry : journal.muted;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            dateLabel,
            style: journal.metadata.copyWith(
              color: dateColor,
              fontSize: 11.5,
              height: 1.22,
              fontWeight: pinUrgent ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          Text(
            clock,
            style: journal.time.copyWith(
              color: clockColor,
              fontWeight: FontWeight.w600,
              height: 1.22,
            ),
          ),
          Text(
            remLabel,
            style: journal.metadata.copyWith(
              color: remColor,
              fontSize: 11,
              height: 1.22,
            ),
          ),
        ],
      );
    }

    final bodyColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasTitle)
          Padding(
            padding: titlePadding,
            child: Text(
              a.title.trim(),
              maxLines: largeText ? null : 2,
              overflow: largeText ? null : TextOverflow.ellipsis,
              style: overdue
                  ? journal.entryTitle.copyWith(
                      color: journal.isDark ? journal.muted : journal.ochre,
                    )
                  : journal.entryTitle,
            ),
          )
        else if (hasCourse)
          Padding(
            padding: titlePadding,
            child: Text(a.courseName.trim(), style: journal.entryTitle),
          ),
        if (!largeText && hasTitle && hasCourse && showPlainInlineState) ...[
          const SizedBox(height: 4),
          _CourseStateLine(
            course: a.courseName.trim(),
            state: state,
            journal: journal,
          ),
          if (highlightPills.isNotEmpty) ...[
            const SizedBox(height: 5),
            Wrap(
              spacing: 6,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: highlightPills,
            ),
          ],
        ] else ...[
          if ((hasTitle && hasCourse) || showPlainInlineState) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 5,
              runSpacing: 3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (hasTitle && hasCourse)
                  Text(a.courseName.trim(), style: journal.metadata),
                if (hasTitle && hasCourse && showPlainInlineState)
                  Text(
                    '·',
                    style: journal.metadata,
                  ),
                if (showPlainInlineState) Text(state, style: journal.metadata),
                if (highlightPills.isNotEmpty && !hasSpecialStatePill)
                  ...highlightPills,
              ],
            ),
          ],
          if (highlightPills.isNotEmpty &&
              (hasSpecialStatePill ||
                  (!hasCourse && !showPlainInlineState))) ...[
            const SizedBox(height: 5),
            Wrap(
              spacing: 6,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: highlightPills,
            ),
          ],
        ],
        if (extraLines.isNotEmpty) ...[
          const SizedBox(height: 4),
          ...extraLines,
        ],
      ],
    );

    return Stack(
      children: [
        Padding(
          padding: contentPadding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: hasInlineLaunch ? 52 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  button: onCardTap != null,
                  onTap: onCardTap,
                  label:
                      '${a.title}，${a.courseName}，$state，${previewOnly ? '${previewSaving ? '正在保存到本机' : '待保存预览'}，' : ''}${urgent == null ? '' : '$urgent，'}${a.isExam ? '$examSemantics${a.exam!.startTrusted || a.exam!.endTrusted ? '，北京时间' : ''}' : hasTime ? '截止 $deadlineDate${countdown ? '，${DisplayPreferences.remaining(d, now)}' : ''}' : deadline}',
                  excludeSemantics: true,
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      enableFeedback: enableTapFeedback,
                      onTap: onCardTap,
                      onLongPress: previewOnly ? null : onLongPress,
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
                                          ? Icon(
                                              Icons.hourglass_top_rounded,
                                              size: 16,
                                              color: journal.ochre,
                                              semanticLabel: '正在确认截止时间',
                                            )
                                          : SizedBox.square(
                                              dimension: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: journal.ochre,
                                                semanticsLabel: '正在确认截止时间',
                                              ),
                                            ),
                                    )
                                  : inPinnedSection
                                      ? buildPinnedRail()
                                      : Text(
                                          railLabel,
                                          style: journal.time.copyWith(
                                            color: railTextColor,
                                            fontWeight: clock.isEmpty
                                                ? FontWeight.w500
                                                : FontWeight.w600,
                                            fontSize: clock.isEmpty
                                                ? 14
                                                : journal.time.fontSize,
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
                if ((onOpenAssignment != null || dragHandle != null) &&
                    largeText)
                  Padding(
                    padding: EdgeInsets.only(left: contentLeftInset, bottom: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (onOpenAssignment != null) buildLaunchControl(),
                        if (dragHandle != null) dragHandle!,
                      ],
                    ),
                  ),
                if (showDivider) ...[
                  SizedBox(
                    key: ValueKey('assignment-card-gap-${a.id}'),
                    height: 4,
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: contentLeftInset),
                    child: Divider(
                      height: 1,
                      thickness: 0.8,
                      color: journal.rule,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (hasInlineLaunch || hasInlineDrag)
          Positioned(
            top: compact ? 0 : 2,
            right: 2,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasInlineLaunch) buildLaunchControl(),
                if (hasInlineDrag) dragHandle!,
              ],
            ),
          ),
      ],
    );
  }
}

class _CourseStateLine extends StatelessWidget {
  const _CourseStateLine({
    required this.course,
    required this.state,
    required this.journal,
  });

  static final RegExp _trailingPunctuation = RegExp(r'[（(\[【《「『·\-—\s]+$');

  final String course;
  final String state;
  final JournalPalette journal;

  @override
  Widget build(BuildContext context) {
    final style = journal.metadata;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        maxLines: 1,
        textDirection: direction,
        textScaler: scaler,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final dotWidth = measure('·');
        final stateWidth = measure(state);
        final suffixWidth = dotWidth + stateWidth + 10.0;
        final available = (constraints.maxWidth - suffixWidth)
            .clamp(0.0, constraints.maxWidth);

        var displayCourse = course;
        if (measure(course) > available - 0.5) {
          final runes = course.runes.toList();
          final fitWidth = (available - 1.0).clamp(0.0, available);
          var low = 1;
          var high = runes.length;
          var best = 0;
          while (low <= high) {
            final mid = (low + high) ~/ 2;
            final candidate = '${String.fromCharCodes(runes.take(mid))}…';
            if (measure(candidate) <= fitWidth) {
              best = mid;
              low = mid + 1;
            } else {
              high = mid - 1;
            }
          }
          if (best > 0) {
            final raw = String.fromCharCodes(runes.take(best)).trimRight();
            final trimmed = raw.replaceFirst(_trailingPunctuation, '');
            displayCourse = trimmed.isEmpty ? '$raw…' : '$trimmed…';
          }
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                displayCourse,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            const SizedBox(width: 5),
            Text('·', style: style),
            const SizedBox(width: 5),
            Text(state, style: style),
          ],
        );
      },
    );
  }
}

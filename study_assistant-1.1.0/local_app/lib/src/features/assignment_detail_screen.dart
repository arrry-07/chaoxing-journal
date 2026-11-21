import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/journal.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/assignment.dart';
import '../services/assignment_grouping.dart';
import '../services/assignment_store.dart';
import '../services/interaction_feedback_service.dart';
import '../services/assignment_query.dart';
import '../services/exam_schedule_presentation.dart';
import '../services/assignment_web_link.dart';
import '../services/external_link_service.dart';
import 'assignment_list_screen.dart' show AssignmentRecoveryScope;
import 'widgets/assignment_card.dart';
import 'widgets/coursework_status_pill.dart';

class AssignmentDetailScreen extends StatefulWidget {
  const AssignmentDetailScreen({
    super.key,
    required this.store,
    required this.assignmentId,
    this.clock,
  });

  final AssignmentStore store;
  final String assignmentId;
  final DateTime Function()? clock;

  @override
  State<AssignmentDetailScreen> createState() => _AssignmentDetailScreenState();
}

class _AssignmentDetailScreenState extends State<AssignmentDetailScreen>
    with WidgetsBindingObserver {
  final _links = ExternalLinkService();
  bool _opening = false, _hiding = false, _refreshing = false;
  bool _togglingPin = false;
  String? _actionMessage;
  _DetailNoticeTarget? _actionMessageTarget;
  Timer? _clock;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _now = widget.clock?.call() ?? DateTime.now();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => _refreshClock());
  }

  void _refreshClock() {
    if (!mounted) return;
    setState(() => _now = widget.clock?.call() ?? DateTime.now());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshClock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    super.dispose();
  }

  String get _itemLabel {
    final assignment = widget.store.findAnyAssignment(widget.assignmentId);
    return assignment?.isExam == true
        ? assignment!.exam!.noticeOnly
            ? '考试通知'
            : '考试'
        : assignment?.isSupportedClassroomTask == true
            ? '任务'
            : '作业';
  }

  String? get _currentUrl {
    final assignment = widget.store.findAnyAssignment(widget.assignmentId);
    return assignment == null
        ? null
        : AssignmentWebLink.validatedUrl(assignment);
  }

  Future<void> _openWeb() async {
    if (_opening) return;
    final url = _currentUrl;
    if (url == null) return;
    setState(() {
      _opening = true;
      _actionMessage = null;
      _actionMessageTarget = null;
    });
    widget.store.beginAssignmentVisit(widget.assignmentId);
    final opened = await _links.openBrowser(url);
    if (!opened) widget.store.cancelAssignmentVisit(widget.assignmentId);
    if (!mounted) return;
    setState(() {
      _opening = false;
      _actionMessage = opened
          ? '已请求浏览器打开。页面是否可用、登录及提交状态请在网页中核对。'
          : '未能启动浏览器，请重试，或刷新作业信息后复制链接。';
      _actionMessageTarget = _DetailNoticeTarget.opening;
    });
  }

  Future<void> _openAssignment() async {
    if (_opening) return;
    final url = _currentUrl;
    if (url == null) return;
    setState(() {
      _opening = true;
      _actionMessage = null;
      _actionMessageTarget = null;
    });
    widget.store.beginAssignmentVisit(widget.assignmentId);
    final target = await _links.openAssignment(url);
    if (target == AssignmentLaunchTarget.unavailable) {
      widget.store.cancelAssignmentVisit(widget.assignmentId);
    }
    if (!mounted) return;
    setState(() {
      _opening = false;
      _actionMessage = target.message;
      _actionMessageTarget = _DetailNoticeTarget.opening;
    });
  }

  Future<void> _refresh() async {
    if (_refreshing || widget.store.isLoading) return;
    setState(() {
      _refreshing = true;
      _actionMessage = null;
      _actionMessageTarget = null;
    });
    var message = '刷新已结束，请核对最新截止时间和提交状态。';
    try {
      await widget.store.syncAssignments();
      if (widget.store.error != null) {
        message = '刷新未完成，请查看同步详情后重试。';
      }
    } catch (_) {
      message = '刷新失败，请稍后重试。';
    }
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      _actionMessage = message;
      _actionMessageTarget = _DetailNoticeTarget.records;
    });
  }

  Future<void> _copyLink() async {
    if (_currentUrl == null) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('复制$_itemLabel链接'),
              content: Text('链接含$_itemLabel访问参数，请只在本人设备使用，勿转发或公开。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('确认复制')),
              ],
            ));
    if (!mounted || confirmed != true) return;
    // A sync or account change may have replaced the assignment during the dialog.
    final url = _currentUrl;
    if (url == null) return;
    var message = '链接已复制，请只在本人设备使用。';
    try {
      await Clipboard.setData(ClipboardData(text: url));
    } on PlatformException {
      message = '复制失败，请稍后重试。';
    } on MissingPluginException {
      message = '当前设备不支持复制链接。';
    }
    if (mounted) {
      setState(() {
        _actionMessage = message;
        _actionMessageTarget = _DetailNoticeTarget.records;
      });
    }
  }

  Future<void> _togglePin(Assignment assignment) async {
    if (_togglingPin) return;
    final store = widget.store;
    final accountEpoch = store.accountEpoch;
    final wasPinned = store.isPinned(assignment);
    final routeId = widget.assignmentId;
    setState(() {
      _togglingPin = true;
      if (_actionMessageTarget == _DetailNoticeTarget.pin) {
        _actionMessage = null;
        _actionMessageTarget = null;
      }
    });
    var saved = false;
    try {
      saved = await store.togglePin(assignment);
    } catch (_) {
      saved = false;
    }
    if (!mounted) return;
    final current = widget.store == store &&
        store.accountEpoch == accountEpoch &&
        widget.assignmentId == routeId;
    if (saved && current) {
      InteractionFeedback.trigger(store.display,
          kind: store.isPinned(assignment)
              ? InteractionSoundKind.pin
              : InteractionSoundKind.unpin);
    }
    setState(() {
      _togglingPin = false;
      if (saved || !current) return;
      _actionMessage = wasPinned ? '取消置顶失败，请稍后重试。' : '置顶失败，请稍后重试。';
      _actionMessageTarget = _DetailNoticeTarget.pin;
    });
  }

  Future<void> _hide() async {
    if (_hiding) return;
    setState(() {
      _hiding = true;
      _actionMessage = null;
      _actionMessageTarget = null;
    });
    final original = widget.store.findAnyAssignment(widget.assignmentId);
    final group =
        original == null ? null : widget.store.courseworkGroupFor(original.id);
    final sources =
        group?.sources.map((assignment) => assignment.id).toList() ??
            (original == null ? const <String>[] : [original.id]);
    var hidden = false;
    try {
      hidden = await widget.store.setAssignmentsHidden(sources, true);
    } catch (_) {
      hidden = false;
    }
    if (!mounted) return;
    if (hidden) {
      GoRouter.maybeOf(context)?.go('/assignments');
      return;
    }
    setState(() {
      _hiding = false;
      _actionMessage = '隐藏失败，请稍后重试；整组来源均未作为完成结果提交。';
      _actionMessageTarget = _DetailNoticeTarget.records;
    });
  }

  Future<void> _restore(CourseworkGroup? group, Assignment original) async {
    if (_hiding) return;
    setState(() {
      _hiding = true;
      _actionMessage = null;
      _actionMessageTarget = null;
    });
    var restored = false;
    try {
      restored = group != null
          ? await widget.store.setCourseworkGroupHidden(group, false)
          : await widget.store.setAssignmentsHidden([original.id], false);
    } catch (_) {
      restored = false;
    }
    if (!mounted) return;
    setState(() {
      _hiding = false;
      _actionMessage = restored ? '已恢复到课业清单' : '恢复失败，请稍后重试。';
      _actionMessageTarget =
          restored ? _DetailNoticeTarget.records : _DetailNoticeTarget.restore;
    });
  }

  String _sourceType(Assignment source) {
    if (source.isExam) {
      return source.exam!.noticeOnly ? '考试通知' : '正式考试';
    }
    if (source.isSupportedClassroomTask) return '课堂任务';
    return switch (source.source) {
      AssignmentSource.courseWork => '正式作业',
      AssignmentSource.manual => '个人记录',
      AssignmentSource.legacyUnknown => '历史来源',
      AssignmentSource.classroomActivity => '课堂任务',
      AssignmentSource.exam => '考试',
    };
  }

  Future<void> _showSourceDetail(Assignment source) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('原始来源详情'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${_sourceType(source)} · ${source.statusLabel}'),
                const SizedBox(height: 8),
                Text(source.courseName),
                if (source.title.trim().isNotEmpty) Text(source.title),
                const SizedBox(height: 8),
                Text(
                  '读取时间：${DateFormat('yyyy-MM-dd HH:mm').format(source.lastSyncedAt)}',
                ),
                if (source.requirementsText.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(source.requirementsText),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final journal = Journal.of(context);
        final original = widget.store.findAnyAssignment(widget.assignmentId);
        final sourceGroup = original == null
            ? null
            : widget.store.courseworkGroupFor(original.id);
        final isHidden = sourceGroup?.hidden == true;
        final courseSources = widget.store.courseAssignments;
        final projectionRecords = original == null
            ? courseSources
            : <Assignment>[
                ...courseSources,
                if (sourceGroup != null)
                  for (final src in sourceGroup.sources)
                    if (!courseSources.any((item) => item.id == src.id))
                      src
                    else if (!courseSources
                        .any((item) => item.id == original.id))
                      original,
              ];
        // Use the same display projection as the list; actions above keep
        // resolving the original ID so supplementation cannot rewrite records.
        final assignment = original == null
            ? null
            : AssignmentQuery.projectDisplay(projectionRecords)
                    .where((a) => a.id == original.id)
                    .firstOrNull ??
                original;
        if (assignment == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('此作业尚未在当前账号的本机记录中找到，请刷新后重试。'),
                if (_actionMessage != null)
                  Semantics(liveRegion: true, child: Text(_actionMessage!)),
                TextButton.icon(
                  onPressed:
                      _refreshing || widget.store.isLoading ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                  label: Text(_refreshing ? '正在刷新…' : '刷新作业信息'),
                ),
                FilledButton.icon(
                  onPressed: () => context.go('/assignments'),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('返回主页'),
                ),
              ]),
            ),
          );
        }

        final exam = assignment.isExam ? assignment.exam : null;
        final sources = sourceGroup?.sources ?? <Assignment>[assignment];
        final schedule = exam == null
            ? null
            : ExamSchedulePresentation.build(assignment,
                records: projectionRecords);
        final examLines = exam == null
            ? const <String>[]
            : <String>[
                ...schedule!.detailTimeLines,
                if (exam.durationMinutes != null && exam.durationMinutes! > 0)
                  '时长 ${exam.durationMinutes} 分钟',
                if (exam.location.trim().isNotEmpty)
                  '地点 ${exam.location.trim()}',
              ];
        final hasExamTime = exam != null &&
            ((exam.startTrusted && exam.startAt != null) ||
                (exam.endTrusted && exam.endAt != null));
        final unverified = exam != null &&
            (!exam.startTrusted ||
                exam.startAt == null ||
                !exam.endTrusted ||
                exam.endAt == null ||
                !const {
                  'pending',
                  'submitted',
                  'graded',
                  'reviewing',
                  'completed',
                  'returned'
                }.contains(assignment.status));
        final unverifiedTimes = <String>[
          if (exam != null && exam.startAt != null && !exam.startTrusted)
            '开考（未核实） ${DateFormat('yyyy年M月d日 HH:mm').format(AssignmentQuery.beijing(exam.startAt!))}',
          if (exam != null && exam.endAt != null && !exam.endTrusted)
            '结束（未核实） ${DateFormat('yyyy年M月d日 HH:mm').format(AssignmentQuery.beijing(exam.endAt!))}',
        ];
        final bucket = AssignmentQuery.timelineBucketAt(assignment, _now);
        final overdue = bucket == AssignmentDeadlineBucket.overdue;
        final today = assignment.timelineAt != null &&
            bucket != AssignmentDeadlineBucket.unconfirmed &&
            AssignmentQuery.dayKey(assignment.timelineAt!) ==
                AssignmentQuery.dayKey(_now);
        final urgentLabel = overdue
            ? '已逾期${_now.difference(assignment.timelineAt!).inDays > 0 ? '${_now.difference(assignment.timelineAt!).inDays}天' : ''}'
            : !assignment.isExam &&
                    assignment.isPendingConfirmed &&
                    assignment.deadlineTrusted &&
                    !assignment.deadlineReadFailed &&
                    today
                ? '今天截止'
                : null;
        final statusLabel = assignment.isExam
            ? AssignmentCard.examStateLabel(assignment, _now)
            : assignment.statusLabel;
        final statusTone = assignment.isExam
            ? CourseworkPillTone.exam
            : assignment.isCompleted
                ? CourseworkPillTone.completed
                : (bucket == AssignmentDeadlineBucket.unconfirmed ||
                        assignment.status == 'unknown' ||
                        !assignment.deadlineTrusted ||
                        assignment.deadlineReadFailed)
                    ? CourseworkPillTone.unconfirmed
                    : CourseworkPillTone.neutral;
        final cleanRequirements = assignment.requirementsText.trim();
        final showRequirements = cleanRequirements.isNotEmpty &&
            cleanRequirements != assignment.title.trim();
        final displayCourse = assignment.courseName.trim();
        final displayTitle = assignment.title.trim().isNotEmpty
            ? assignment.title.trim()
            : displayCourse;
        final showCourseLabel =
            displayCourse.isNotEmpty && displayCourse != displayTitle;
        final statusWidgets = <Widget>[
          if (statusLabel.isNotEmpty &&
              statusTone == CourseworkPillTone.neutral)
            Text(statusLabel, style: journal.metadata),
          if (statusLabel.isNotEmpty &&
              statusTone != CourseworkPillTone.neutral)
            CourseworkStatusPill(
              label: statusLabel,
              tone: statusTone,
            ),
          if (urgentLabel != null)
            CourseworkStatusPill(
              label: urgentLabel,
              tone: overdue
                  ? CourseworkPillTone.overdue
                  : CourseworkPillTone.urgentToday,
            ),
        ];
        final showRawDeadline = !assignment.isExam &&
            assignment.deadlineRawText != null &&
            (!assignment.deadlineTrusted ||
                assignment.deadlineAt == null ||
                assignment.deadlineReadFailed);
        final verificationNotes = <String>[
          if (schedule?.verificationNote != null)
            schedule!.verificationNote!
          else if (unverified)
            '部分信息尚未核实',
          if (!assignment.isExam &&
              !assignment.deadlineTrusted &&
              assignment.deadlineAt != null)
            '历史截止时间待确认，不参与日历和提醒',
          if (showRawDeadline) assignment.deadlineRawText!,
          if (!assignment.isExam &&
              assignment.deadlineReadFailed &&
              assignment.deadlineAt != null)
            assignment.deadlineLabel,
        ];
        final hasTimeLine = assignment.isExam ? examLines.isNotEmpty : true;
        final String timeText;
        if (assignment.isExam) {
          timeText = '${examLines.join('\n')}${hasExamTime ? '\n（北京时间）' : ''}';
        } else {
          String fullBeijingTime(DateTime value) =>
              '${DateFormat('yyyy年M月d日 HH:mm', 'zh_CN').format(AssignmentQuery.beijing(value))}（北京时间）';

          final start = assignment.availableFromAt;
          final startText = assignment.availableFromText?.trim() ?? '';
          final deadline = assignment.deadlineAt;
          final deadlinePrefix =
              !assignment.deadlineTrusted || assignment.deadlineReadFailed
                  ? '历史截止（未核实） '
                  : '截止：';
          timeText = [
            if (start != null)
              '开始：${fullBeijingTime(start)}'
            else if (startText.isNotEmpty)
              '开始：$startText',
            if (deadline != null)
              '$deadlinePrefix${fullBeijingTime(deadline)}'
            else
              assignment.deadlineLabel,
          ].join('\n');
        }
        final pinTarget = original != null &&
                !isHidden &&
                AssignmentRecoveryScope.of(context) == null &&
                widget.store.canTogglePin(original)
            ? original
            : null;
        final pinned = pinTarget != null && widget.store.isPinned(pinTarget);
        final showOpeningNotice = _actionMessage != null &&
            _actionMessageTarget == _DetailNoticeTarget.opening;
        final showRecordsNotice = _actionMessage != null &&
            _actionMessageTarget == _DetailNoticeTarget.records;
        final showRestoreNotice = _actionMessage != null &&
            _actionMessageTarget == _DetailNoticeTarget.restore;

        return Material(
          color: journal.paper,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        key: const ValueKey('assignment-detail-back'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: () => context.canPop()
                            ? context.pop()
                            : context.go('/assignments'),
                        icon: const Icon(Icons.arrow_back_rounded, size: 20),
                        label: const Text('返回'),
                      ),
                      if (pinTarget != null)
                        TextButton.icon(
                          key: const ValueKey('assignment-detail-pin'),
                          style: TextButton.styleFrom(
                            enableFeedback: false,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            minimumSize: const Size(48, 48),
                            foregroundColor:
                                pinned ? journal.ink : journal.muted,
                          ),
                          onPressed: _togglingPin || _hiding
                              ? null
                              : () => _togglePin(pinTarget),
                          icon: Icon(
                            pinned ? Icons.push_pin : Icons.push_pin_outlined,
                            size: 18,
                          ),
                          label: Text(pinned ? '已置顶' : '置顶'),
                        ),
                    ],
                  ),
                  if (_actionMessageTarget == _DetailNoticeTarget.pin &&
                      _actionMessage != null)
                    _DetailActionNotice(
                      key: const ValueKey('assignment-pin-result'),
                      message: _actionMessage!,
                    ),
                  const SizedBox(height: 8),
                  Material(
                    key: const ValueKey('assignment-detail-sheet'),
                    color: journal.sheet,
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showCourseLabel) ...[
                            Text(
                              displayCourse,
                              key: const ValueKey('assignment-detail-course'),
                              style: journal.metadata,
                            ),
                            const SizedBox(height: 4),
                          ],
                          if (displayTitle.isNotEmpty)
                            Text(
                              displayTitle,
                              key: const ValueKey('assignment-detail-title'),
                              style: journal.section.copyWith(
                                fontSize: 22,
                                height: 1.36,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (statusWidgets.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              key: const ValueKey('assignment-detail-status'),
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: statusWidgets,
                            ),
                          ],
                          if (hasTimeLine) ...[
                            const SizedBox(height: 10),
                            Divider(
                              height: 1,
                              thickness: 0.8,
                              color: journal.rule,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.schedule_rounded,
                                    size: 18,
                                    color:
                                        overdue ? journal.berry : journal.muted,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    timeText,
                                    key: const ValueKey(
                                        'assignment-detail-time'),
                                    style: journal.time.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (verificationNotes.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              key: const ValueKey(
                                  'assignment-detail-verification'),
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: journal.ochreBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (var i = 0;
                                      i < verificationNotes.length;
                                      i++) ...[
                                    if (i > 0) const SizedBox(height: 4),
                                    Text(
                                      verificationNotes[i],
                                      style: journal.metadata.copyWith(
                                        color: journal.ochre,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          if (unverifiedTimes.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Theme(
                              data: Theme.of(context).copyWith(
                                dividerColor: Colors.transparent,
                              ),
                              child: ExpansionTile(
                                key: const ValueKey(
                                    'assignment-unverified-times'),
                                tilePadding: EdgeInsets.zero,
                                childrenPadding:
                                    const EdgeInsets.only(bottom: 2),
                                title: Text(
                                  '未核实的时间记录',
                                  style: journal.metadata.copyWith(
                                    color: journal.ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                children: [
                                  for (final line in unverifiedTimes)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 4),
                                        child: Text(
                                          line,
                                          style: journal.metadata,
                                        ),
                                      ),
                                    ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '时间记录尚未核实，仅供参考，不作为当前考试安排。以上时间均为北京时间。',
                                      style: journal.metadata.copyWith(
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (isHidden) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: journal.parchment,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.visibility_off_outlined,
                                color: journal.muted,
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '当前课业已在本机隐藏，不参与首页、日历、统计、小组件与提醒',
                                  style: journal.metadata,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: journal.sheet,
                            ),
                            onPressed: _hiding || _opening || _refreshing
                                ? null
                                : () => _restore(sourceGroup, original!),
                            icon:
                                const Icon(Icons.visibility_outlined, size: 18),
                            label: const Text('恢复到课业清单'),
                          ),
                          if (showRestoreNotice) ...[
                            const SizedBox(height: 10),
                            _DetailActionNotice(message: _actionMessage!),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (showRequirements) ...[
                    const SizedBox(height: 16),
                    Text(
                      cleanRequirements,
                      key: const ValueKey('assignment-detail-requirements'),
                      style: journal.metadata.copyWith(
                        color: journal.ink,
                        fontSize: 14.5,
                        height: 1.55,
                      ),
                    ),
                  ],
                  if (sources.length > 1) ...[
                    const SizedBox(height: 14),
                    ExpansionTile(
                      key: const ValueKey('assignment-source-records'),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      title: Text(
                        '来源记录 · ${sources.length} 条',
                        style: journal.metadata.copyWith(
                          color: journal.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      children: [
                        for (final source in sources)
                          ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            title: Text(
                              '${_sourceType(source)} · ${source.statusLabel}',
                            ),
                            subtitle: Text(
                              '读取 ${DateFormat('yyyy-MM-dd HH:mm').format(source.lastSyncedAt)}',
                            ),
                            trailing: TextButton(
                              onPressed: () => _showSourceDetail(source),
                              child: const Text('查看'),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const ValueKey('assignment-detail-open'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: _opening || _hiding || _currentUrl == null
                        ? null
                        : _openAssignment,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(_opening
                        ? '正在打开…'
                        : assignment.isExam
                            ? '在学习通内查看$_itemLabel'
                            : '在学习通内打开作业'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('assignment-detail-open-web'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: Colors.transparent,
                      side: BorderSide.none,
                      alignment: Alignment.center,
                    ),
                    onPressed: _opening || _hiding || _currentUrl == null
                        ? null
                        : _openWeb,
                    icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                    label: Text(_opening ? '正在请求浏览器…' : '打开$_itemLabel网页'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '将在学习通内打开$_itemLabel网页；也可主动选择浏览器打开，可能需要另行登录。返回后可刷新核对提交状态。',
                    style: journal.metadata.copyWith(fontSize: 12.5),
                  ),
                  if (_currentUrl == null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '$_itemLabel链接暂不可用，请刷新信息；尚未开放时请稍后重试。',
                      style: journal.metadata.copyWith(
                        color: journal.ochre,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  if (showOpeningNotice) ...[
                    const SizedBox(height: 10),
                    _DetailActionNotice(
                      key: const ValueKey('assignment-open-result'),
                      message: _actionMessage!,
                    ),
                  ],
                  const SizedBox(height: 18),
                  Divider(
                    height: 1,
                    thickness: 0.8,
                    color: journal.rule,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '手记工具',
                    style: journal.metadata.copyWith(
                      color: journal.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _DetailToolButton(
                    onPressed: () => context.push(
                      '/personal/${Uri.encodeComponent(widget.assignmentId)}',
                    ),
                    icon: Icons.edit_note_rounded,
                    label: '个人清单与备注',
                    iconSize: 20,
                  ),
                  const SizedBox(height: 8),
                  _DetailToolPair(
                    children: [
                      if (!isHidden)
                        _DetailToolButton(
                          onPressed: () => context.push('/plan'),
                          icon: Icons.checklist_rounded,
                          label: '安排每日计划',
                        ),
                      _DetailToolButton(
                        onPressed: () => context.push(
                          '/reminder-status/assignment/'
                          '${Uri.encodeComponent(assignment.id)}',
                        ),
                        icon: Icons.notifications_active_outlined,
                        label: '提醒状态',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Divider(
                    height: 1,
                    thickness: 0.8,
                    color: journal.rule,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '记录管理',
                    style: journal.metadata.copyWith(
                      color: journal.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _DetailToolPair(
                    children: [
                      _DetailToolButton(
                        onPressed:
                            _refreshing || widget.store.isLoading || _hiding
                                ? null
                                : _refresh,
                        icon: Icons.refresh_rounded,
                        label: _refreshing ? '正在刷新…' : '刷新$_itemLabel信息',
                      ),
                      _DetailToolButton(
                        onPressed:
                            _currentUrl == null || _hiding ? null : _copyLink,
                        icon: Icons.copy_outlined,
                        label: '复制$_itemLabel链接',
                        iconSize: 17,
                      ),
                    ],
                  ),
                  if (showRecordsNotice) ...[
                    const SizedBox(height: 10),
                    _DetailActionNotice(
                      key: const ValueKey('assignment-records-result'),
                      message: _actionMessage!,
                    ),
                  ],
                  if (!isHidden && !assignment.isCompleted) ...[
                    const SizedBox(height: 8),
                    _DetailToolButton(
                      key: const ValueKey('assignment-detail-hide'),
                      onPressed:
                          _hiding || _opening || _refreshing ? null : _hide,
                      icon: Icons.visibility_off_outlined,
                      label: sources.length > 1
                          ? '在本机隐藏此$_itemLabel（${sources.length} 条来源）'
                          : '在本机隐藏此$_itemLabel',
                      foregroundColor: journal.berry,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _DetailNoticeTarget { opening, records, restore, pin }

class _DetailActionNotice extends StatelessWidget {
  const _DetailActionNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Journal.of(context).sage.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Semantics(
          liveRegion: true,
          child: Text(
            message,
            style: Journal.of(context).metadata.copyWith(
                  color: Journal.of(context).ink,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      );
}

class _DetailToolPair extends StatelessWidget {
  const _DetailToolPair({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final scaledBodySize = MediaQuery.textScalerOf(context).scale(14);
          final useColumns = constraints.maxWidth >= 312 &&
              scaledBodySize <= 18.2 &&
              children.length == 2;
          if (useColumns) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: children[0]),
                const SizedBox(width: 8),
                Expanded(child: children[1]),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                children[i],
              ],
            ],
          );
        },
      );
}

class _DetailToolButton extends StatelessWidget {
  const _DetailToolButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.iconSize = 18,
    this.foregroundColor,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final double iconSize;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: TextButton(
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            foregroundColor: foregroundColor ?? Journal.of(context).ink,
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          onPressed: onPressed,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: iconSize),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: Journal.of(context).metadata.copyWith(
                        color: onPressed == null
                            ? Journal.of(context).muted.withValues(alpha: 0.55)
                            : foregroundColor ?? Journal.of(context).ink,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                ),
              ),
            ],
          ),
        ),
      );
}

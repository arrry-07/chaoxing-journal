import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/journal.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/assignment.dart';
import '../services/assignment_grouping.dart';
import '../services/assignment_store.dart';
import '../services/assignment_query.dart';
import '../services/exam_schedule_presentation.dart';
import '../services/assignment_web_link.dart';
import '../services/external_link_service.dart';
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
  String? _actionMessage;
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
    });
  }

  Future<void> _openAssignment() async {
    if (_opening) return;
    final url = _currentUrl;
    if (url == null) return;
    setState(() {
      _opening = true;
      _actionMessage = null;
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
    });
  }

  Future<void> _refresh() async {
    if (_refreshing || widget.store.isLoading) return;
    setState(() {
      _refreshing = true;
      _actionMessage = null;
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
    if (mounted) setState(() => _actionMessage = message);
  }

  Future<void> _hide() async {
    if (_hiding) return;
    setState(() {
      _hiding = true;
      _actionMessage = null;
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
    });
  }

  Future<void> _restore(CourseworkGroup? group, Assignment original) async {
    if (_hiding) return;
    setState(() {
      _hiding = true;
      _actionMessage = null;
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

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(48, 44),
                ),
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go('/assignments'),
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                label: const Text('返回'),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (urgentLabel != null)
                  CourseworkStatusPill(
                    label: urgentLabel,
                    tone: overdue
                        ? CourseworkPillTone.overdue
                        : CourseworkPillTone.urgentToday,
                  ),
                if (statusLabel.isNotEmpty)
                  CourseworkStatusPill(
                    label: statusLabel,
                    tone: statusTone,
                  ),
                if (assignment.courseName.trim().isNotEmpty &&
                    assignment.title.trim().isNotEmpty)
                  Text(
                    assignment.courseName.trim(),
                    style: Journal.metadata.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Journal.muted,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (assignment.title.trim().isNotEmpty)
              Text(
                assignment.title.trim(),
                style: Journal.section.copyWith(
                  fontSize: 22,
                  height: 1.36,
                  fontWeight: FontWeight.w700,
                ),
              )
            else if (assignment.courseName.trim().isNotEmpty)
              Text(
                assignment.courseName.trim(),
                style: Journal.section,
              ),
            const SizedBox(height: 16),
            if (_actionMessage != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Journal.sage.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Journal.sageBorder),
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _actionMessage!,
                    style: Journal.metadata.copyWith(
                      color: Journal.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (isHidden) ...[
              Card(
                color: Journal.parchment,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Icon(
                            Icons.visibility_off_outlined,
                            color: Journal.muted,
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '当前课业已在本机隐藏，不参与首页、日历、统计、小组件与提醒',
                              style: Journal.metadata,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Journal.sheet,
                        ),
                        onPressed: _hiding || _opening || _refreshing
                            ? null
                            : () => _restore(sourceGroup, original!),
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('恢复到课业清单'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (exam == null || examLines.isNotEmpty)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.event_available_rounded,
                            size: 20,
                            color: overdue ? Journal.berry : Journal.ink,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              assignment.isExam
                                  ? '${examLines.join('\n')}${hasExamTime ? '\n（北京时间）' : ''}'
                                  : assignment.deadlineAt == null
                                      ? assignment.deadlineLabel
                                      : '${!assignment.deadlineTrusted || assignment.deadlineReadFailed ? '历史截止（未核实） ' : ''}${DateFormat('yyyy年M月d日 HH:mm', 'zh_CN').format(AssignmentQuery.beijing(assignment.deadlineAt!))}（北京时间）',
                              style: Journal.metadata.copyWith(
                                color: Journal.ink,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (verificationNotes.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Journal.ochreBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Journal.ochreBorder),
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
                                style: Journal.metadata.copyWith(
                                  color: Journal.ochre,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (unverifiedTimes.isNotEmpty)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('未核实的时间记录'),
                        children: [
                          for (final line in unverifiedTimes) Text(line),
                          const Text('时间记录尚未核实，仅供参考，不作为当前考试安排。以上时间均为北京时间。'),
                        ],
                      ),
                    if (showRequirements) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1, color: Journal.rule),
                      ),
                      Text(
                        cleanRequirements,
                        style: Journal.metadata.copyWith(
                          color: Journal.ink,
                          fontSize: 14,
                          height: 1.55,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(48, 44),
                      ),
                      onPressed: () => context.push(
                          '/personal/${Uri.encodeComponent(widget.assignmentId)}'),
                      icon: const Icon(Icons.edit_note_rounded, size: 20),
                      label: const Text('个人清单与备注'),
                    ),
                    if (!isHidden)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(48, 44),
                        ),
                        onPressed: () => context.push('/plan'),
                        icon: const Icon(Icons.checklist_rounded, size: 18),
                        label: const Text('安排每日计划'),
                      ),
                  ],
                ),
              ),
            ),
            if (sources.length > 1) ...[
              const SizedBox(height: 12),
              Card(
                child: ExpansionTile(
                  key: const ValueKey('assignment-source-records'),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: Text('来源记录 · ${sources.length} 条'),
                  children: [
                    for (final source in sources)
                      ListTile(
                        dense: true,
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
              ),
            ],
            const SizedBox(height: 18),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Journal.parchment,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Journal.rule),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
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
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        backgroundColor: Journal.sheet,
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
                      style: Journal.metadata.copyWith(fontSize: 12.5),
                    ),
                    if (_currentUrl == null) ...[
                      const SizedBox(height: 6),
                      Text(
                        '$_itemLabel链接暂不可用，请刷新信息；尚未开放时请稍后重试。',
                        style: Journal.metadata.copyWith(
                          color: Journal.ochre,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    const Padding(
                      padding: EdgeInsets.only(top: 10, bottom: 4),
                      child: Divider(height: 1, color: Journal.rule),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed:
                              _refreshing || widget.store.isLoading || _hiding
                                  ? null
                                  : _refresh,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label:
                              Text(_refreshing ? '正在刷新…' : '刷新$_itemLabel信息'),
                        ),
                        TextButton.icon(
                          onPressed:
                              _currentUrl == null || _hiding ? null : _copyLink,
                          icon: const Icon(Icons.copy_outlined, size: 17),
                          label: Text('复制$_itemLabel链接'),
                        ),
                        TextButton.icon(
                          onPressed: () => context.push(
                            '/reminder-status/assignment/'
                            '${Uri.encodeComponent(assignment.id)}',
                          ),
                          icon: const Icon(Icons.notifications_active_outlined,
                              size: 18),
                          label: const Text('提醒状态'),
                        ),
                        if (!isHidden && !assignment.isCompleted)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Journal.berry,
                            ),
                            onPressed: _hiding || _opening || _refreshing
                                ? null
                                : _hide,
                            icon: const Icon(Icons.visibility_off_outlined,
                                size: 18),
                            label: Text(
                              sources.length > 1
                                  ? '在本机隐藏此$_itemLabel（${sources.length} 条来源）'
                                  : '在本机隐藏此$_itemLabel',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

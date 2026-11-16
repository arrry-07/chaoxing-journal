import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/journal.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../services/assignment_store.dart';
import '../services/assignment_query.dart';
import '../services/exam_schedule_presentation.dart';
import '../services/assignment_web_link.dart';
import '../services/external_link_service.dart';
import 'widgets/assignment_card.dart';

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
    final assignment = widget.store.findAssignment(widget.assignmentId);
    return assignment?.isExam == true
        ? assignment!.exam!.noticeOnly
            ? '考试通知'
            : '考试'
        : assignment?.isSupportedClassroomTask == true
            ? '任务'
            : '作业';
  }

  String? get _currentUrl {
    final assignment = widget.store.findAssignment(widget.assignmentId);
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
    final epoch = widget.store.accountEpoch;
    final original = widget.store.findAssignment(widget.assignmentId);
    final sources = original == null
        ? const <String>[]
        : {
            original.id,
            ...AssignmentQuery.displaySources(
                    original, widget.store.courseAssignments)
                .map((a) => a.id),
          }.toList();
    var hidden = sources.isNotEmpty;
    try {
      // Snapshot all source IDs before the first reload. Do not archive records
      // from a replacement account if the session changes between writes.
      for (final id in sources) {
        if (widget.store.accountEpoch != epoch ||
            !await widget.store.hideAssignment(id) ||
            widget.store.accountEpoch != epoch) {
          hidden = false;
          break;
        }
      }
    } catch (_) {
      hidden = false;
      // Preserve the detail view for retry, including persistence exceptions.
    }
    if (!mounted) return;
    if (hidden) {
      context.go('/assignments');
      return;
    }
    setState(() {
      _hiding = false;
      _actionMessage = '隐藏失败，请稍后重试；部分记录可能已隐藏，可在本机记录中恢复。';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final original = widget.store.findAssignment(widget.assignmentId);
        // Use the same display projection as the list; actions above keep
        // resolving the original ID so supplementation cannot rewrite records.
        final assignment = original == null
            ? null
            : AssignmentQuery.projectDisplay(widget.store.courseAssignments)
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
        final schedule = exam == null
            ? null
            : ExamSchedulePresentation.build(assignment,
                records: widget.store.courseAssignments);
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
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go('/assignments'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回'),
              ),
            ),
            const SizedBox(height: 8),
            if (assignment.courseName.trim().isNotEmpty)
              Text(
                assignment.courseName.trim(),
                style: assignment.title.trim().isEmpty
                    ? Journal.section
                    : Theme.of(context).textTheme.labelLarge,
              ),
            const SizedBox(height: 8),
            if (assignment.title.trim().isNotEmpty)
              Text(
                assignment.title.trim(),
                style: const TextStyle(
                    fontSize: 26,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: Journal.ink),
              ),
            const SizedBox(height: 16),
            if (exam == null || examLines.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.event_available),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          assignment.isExam
                              ? '${examLines.join('\n')}${hasExamTime ? '\n（北京时间）' : ''}'
                              : assignment.deadlineAt == null
                                  ? assignment.deadlineLabel
                                  : '${!assignment.deadlineTrusted || assignment.deadlineReadFailed ? '历史截止（未核实） ' : ''}${DateFormat('yyyy年M月d日 HH:mm', 'zh_CN').format(AssignmentQuery.beijing(assignment.deadlineAt!))}（北京时间）',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(assignment.isExam
                          ? AssignmentCard.examStateLabel(assignment, _now)
                          : assignment.statusLabel),
                      if (schedule?.verificationNote != null)
                        Text(schedule!.verificationNote!)
                      else if (unverified)
                        const Text('部分信息尚未核实'),
                      if (unverifiedTimes.isNotEmpty)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('未核实的时间记录'),
                          children: [
                            for (final line in unverifiedTimes) Text(line),
                            const Text('时间记录尚未核实，仅供参考，不作为当前考试安排。以上时间均为北京时间。'),
                          ],
                        ),
                      if (!assignment.isExam &&
                          !assignment.deadlineTrusted &&
                          assignment.deadlineAt != null)
                        const Text('历史截止时间待确认，不参与日历和提醒'),
                      if (!assignment.isExam &&
                          assignment.deadlineRawText != null)
                        Text(assignment.deadlineRawText!),
                      if (!assignment.isExam &&
                          assignment.deadlineReadFailed &&
                          assignment.deadlineAt != null)
                        Text(assignment.deadlineLabel),
                      if (assignment.requirementsText.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(assignment.requirementsText)
                      ]
                    ]),
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
                onPressed: () => context.push(
                    '/personal/${Uri.encodeComponent(widget.assignmentId)}'),
                icon: const Icon(Icons.edit_note),
                label: const Text('个人清单与备注')),
            TextButton.icon(
                onPressed: () => context.push('/plan'),
                icon: const Icon(Icons.checklist),
                label: const Text('安排每日计划')),
            FilledButton.icon(
              onPressed: _opening || _hiding || _currentUrl == null
                  ? null
                  : _openAssignment,
              icon: const Icon(Icons.launch),
              label: Text(_opening
                  ? '正在打开…'
                  : assignment.isExam
                      ? '在学习通内查看$_itemLabel'
                      : '在学习通内打开作业'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed:
                  _opening || _hiding || _currentUrl == null ? null : _openWeb,
              icon: const Icon(Icons.open_in_browser),
              label: Text(_opening ? '正在请求浏览器…' : '打开$_itemLabel网页'),
            ),
            const SizedBox(height: 8),
            Text('将在学习通内打开$_itemLabel网页；也可主动选择浏览器打开，可能需要另行登录。返回后可刷新核对提交状态。'),
            if (_currentUrl == null) ...[
              const SizedBox(height: 8),
              Text('$_itemLabel链接暂不可用，请刷新信息；尚未开放时请稍后重试。'),
            ],
            if (_actionMessage != null) ...[
              const SizedBox(height: 8),
              Semantics(liveRegion: true, child: Text(_actionMessage!)),
            ],
            Wrap(spacing: 8, children: [
              TextButton.icon(
                onPressed: _refreshing || widget.store.isLoading || _hiding
                    ? null
                    : _refresh,
                icon: const Icon(Icons.refresh),
                label: Text(_refreshing ? '正在刷新…' : '刷新$_itemLabel信息'),
              ),
              TextButton.icon(
                onPressed: _currentUrl == null || _hiding ? null : _copyLink,
                icon: const Icon(Icons.copy_outlined),
                label: Text('复制$_itemLabel链接'),
              ),
            ]),
            const SizedBox(height: 12),
            if (!assignment.isCompleted)
              TextButton.icon(
                onPressed: _hiding || _opening || _refreshing ? null : _hide,
                icon: const Icon(Icons.visibility_off_outlined),
                label: Text('在本机隐藏此$_itemLabel'),
              ),
          ],
        );
      },
    );
  }
}

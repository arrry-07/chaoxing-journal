import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/journal.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/assignment.dart';
import '../models/assignment_change.dart';
import '../models/personal_workspace.dart';
import '../services/assignment_grouping.dart';
import '../services/assignment_store.dart';
import '../services/coursework_deadline.dart';
import '../services/interaction_feedback_service.dart';
import '../services/assignment_query.dart';
import '../services/exam_schedule_presentation.dart';
import '../services/assignment_web_link.dart';
import '../services/external_link_service.dart';
import 'assignment_list_screen.dart' show AssignmentRecoveryScope;
import 'widgets/assignment_card.dart';
import 'widgets/coursework_status_pill.dart';
import 'widgets/journal_buttons.dart';
import 'widgets/journal_grouped_card.dart';

class DetailRequirementsDisplay {
  const DetailRequirementsDisplay({
    required this.title,
    required this.body,
    required this.rawText,
    required this.trimmedRedundantLines,
  });

  final String title;
  final String body;
  final String rawText;
  final bool trimmedRedundantLines;
}

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

  static DetailRequirementsDisplay formatRequirementsForDisplay(
    Assignment assignment, {
    required String displayTitle,
    required String displayCourse,
    required bool hasTrustedFullExamRange,
  }) {
    final rawText = assignment.requirementsText.trim();
    if (!assignment.isExam || rawText.isEmpty) {
      return DetailRequirementsDisplay(
        title: assignment.isExam ? '考试说明' : '要求与说明',
        body: rawText,
        rawText: rawText,
        trimmedRedundantLines: false,
      );
    }

    String normalize(String text) =>
        text.replaceAll(RegExp(r'\s+'), '').toLowerCase();

    final exam = assignment.exam;
    final normTitle = normalize(displayTitle);
    final normCourse = normalize(displayCourse);
    final hasDuration =
        exam?.durationMinutes != null && exam!.durationMinutes! > 0;
    final location = exam?.location.trim() ?? '';
    final normLocation = normalize(location);

    final kept = <String>[];
    var trimmed = false;
    var hasTipPrefix = false;

    final kvRegex = RegExp(r'^([^：:]+)[：:](.*)$');
    final tipPrefixRegex = RegExp(r'^(?:温馨提示|考试提示|注意事项|提示)[：:]\s*');

    for (final rawLine in rawText.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (tipPrefixRegex.hasMatch(line)) {
        hasTipPrefix = true;
        final stripped = line.replaceFirst(tipPrefixRegex, '').trim();
        if (stripped.isNotEmpty) {
          kept.add(stripped);
        } else {
          trimmed = true;
        }
        continue;
      }

      final kv = kvRegex.firstMatch(line);
      if (kv != null) {
        final key = kv.group(1)!.trim();
        final value = kv.group(2)!.trim();
        final normValue = normalize(value);

        if (key == '试卷名称' || key == '考试名称' || key == '课程名称') {
          if (normValue.isEmpty ||
              normValue == normTitle ||
              normValue == normCourse) {
            trimmed = true;
            continue;
          }
        }
        if ((key == '考试时间' || key == '开考时间') && hasTrustedFullExamRange) {
          trimmed = true;
          continue;
        }
        if ((key == '答题时长' || key == '考试时长') && hasDuration) {
          final minutesMatch = RegExp(r'(\d+)').firstMatch(value);
          if (minutesMatch != null &&
              minutesMatch.group(1) == '${exam.durationMinutes}') {
            trimmed = true;
            continue;
          }
        }
        if ((key == '考试地点' || key == '地点') &&
            normLocation.isNotEmpty &&
            (normValue.isEmpty || normValue == normLocation)) {
          trimmed = true;
          continue;
        }
      }

      kept.add(line);
    }

    return DetailRequirementsDisplay(
      title: hasTipPrefix ? '考试提示' : '考试说明',
      body: kept.join('\n'),
      rawText: rawText,
      trimmedRedundantLines: trimmed,
    );
  }

  @override
  State<AssignmentDetailScreen> createState() => _AssignmentDetailScreenState();
}

class _AssignmentDetailScreenState extends State<AssignmentDetailScreen>
    with WidgetsBindingObserver {
  final _links = ExternalLinkService();
  bool _opening = false, _hiding = false, _refreshing = false;
  bool _togglingPin = false;
  bool _savingManualDeadline = false;
  String? _actionMessage;
  _DetailNoticeTarget? _actionMessageTarget;
  Timer? _clock;
  late DateTime _now;
  AssignmentChange? _presentedDeadlineAlert;
  final Set<String> _attemptedAckChangeIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _now = widget.clock?.call() ?? DateTime.now();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => _refreshClock());
  }

  @override
  void didUpdateWidget(covariant AssignmentDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assignmentId != widget.assignmentId ||
        oldWidget.store != widget.store) {
      _presentedDeadlineAlert = null;
      _attemptedAckChangeIds.clear();
    }
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
    final before = widget.store.syncReport;
    final beforeEpoch = widget.store.accountEpoch;
    var message = '刷新已结束，请核对最新截止时间和提交状态。';
    try {
      await widget.store.syncAssignments();
      InteractionFeedback.triggerSyncDoneIfReady(
        prefs: widget.store.display,
        before: before,
        after: widget.store.syncReport,
        beforeEpoch: beforeEpoch,
        afterEpoch: widget.store.accountEpoch,
        operationError: widget.store.error,
      );
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

  Future<void> _pickManualDeadline(
    Assignment assignment, {
    DateTime? existing,
  }) async {
    if (_savingManualDeadline) return;
    final store = widget.store;
    final epoch = store.accountEpoch;
    final routeId = widget.assignmentId;
    final beijing = AssignmentQuery.beijing(existing ?? _now);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime(beijing.year, beijing.month, beijing.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2200, 12, 31),
    );
    if (!mounted || pickedDate == null) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: existing != null
          ? TimeOfDay(hour: beijing.hour, minute: beijing.minute)
          : const TimeOfDay(hour: 23, minute: 59),
    );
    if (!mounted || pickedTime == null) return;
    final utcInstant = DateTime.utc(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    ).subtract(const Duration(hours: 8));
    setState(() {
      _savingManualDeadline = true;
      if (_actionMessageTarget == _DetailNoticeTarget.manual) {
        _actionMessage = null;
        _actionMessageTarget = null;
      }
    });
    var saved = false;
    try {
      saved = await store.setManualDeadline(assignment, utcInstant.toLocal());
    } catch (_) {
      saved = false;
    }
    if (!mounted) return;
    final current = widget.store == store &&
        store.accountEpoch == epoch &&
        widget.assignmentId == routeId;
    if (saved && current) {
      InteractionFeedback.trigger(store.display);
    }
    setState(() {
      _savingManualDeadline = false;
      if (!current) return;
      _actionMessage = saved ? '已保存手动截止时间，官方截止仍待确认。' : '手动截止时间保存失败，请稍后重试。';
      _actionMessageTarget = _DetailNoticeTarget.manual;
    });
  }

  Future<void> _clearManualDeadline(Assignment assignment) async {
    if (_savingManualDeadline) return;
    final store = widget.store;
    final epoch = store.accountEpoch;
    final routeId = widget.assignmentId;
    setState(() {
      _savingManualDeadline = true;
      if (_actionMessageTarget == _DetailNoticeTarget.manual) {
        _actionMessage = null;
        _actionMessageTarget = null;
      }
    });
    var cleared = false;
    try {
      cleared = await store.setManualDeadline(assignment, null);
    } catch (_) {
      cleared = false;
    }
    if (!mounted) return;
    final current = widget.store == store &&
        store.accountEpoch == epoch &&
        widget.assignmentId == routeId;
    if (cleared && current) {
      InteractionFeedback.trigger(store.display);
    }
    setState(() {
      _savingManualDeadline = false;
      if (!current) return;
      _actionMessage = cleared ? '已清除手动截止记录。' : '清除手动截止失败，请稍后重试。';
      _actionMessageTarget = _DetailNoticeTarget.manual;
    });
  }

  Future<void> _toggleLocallyCompleted(
    Assignment assignment,
    bool completed,
  ) async {
    if (_savingManualDeadline) return;
    final store = widget.store;
    final epoch = store.accountEpoch;
    final routeId = widget.assignmentId;
    setState(() {
      _savingManualDeadline = true;
      if (_actionMessageTarget == _DetailNoticeTarget.records) {
        _actionMessage = null;
        _actionMessageTarget = null;
      }
    });
    var saved = false;
    try {
      saved = await store.setLocallyCompleted(assignment, completed);
    } catch (_) {
      saved = false;
    }
    if (!mounted) return;
    final current = widget.store == store &&
        store.accountEpoch == epoch &&
        widget.assignmentId == routeId;
    if (saved && current) {
      InteractionFeedback.trigger(
        store.display,
        kind: completed
            ? InteractionSoundKind.complete
            : InteractionSoundKind.tap,
      );
    }
    setState(() {
      _savingManualDeadline = false;
      if (!current) return;
      _actionMessage = saved
          ? (completed ? '已标记为本机已完成，待办提醒已暂停并退顶。' : '已撤销本机完成标记。')
          : '本机完成状态更新失败，请稍后重试。';
      _actionMessageTarget = _DetailNoticeTarget.records;
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
                  '读取时间：${DateFormat('yyyy-MM-dd HH:mm').format(source.lastSyncedAt.toLocal())}',
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
        final courseworkTarget = original ?? assignment;
        final courseworkEntry =
            widget.store.courseworkEntryFor(courseworkTarget);
        final localDoneOnly = !assignment.isExam &&
            CourseworkDeadline.isLocallyCompletedEntry(
              assignment,
              courseworkEntry,
            );
        final effectivelyCompleted = assignment.isCompleted || localDoneOnly;
        final latestDeadlineChange =
            widget.store.latestDeadlineChangeFor(assignment);
        final liveDeadlineAlert = effectivelyCompleted
            ? null
            : widget.store.activeDeadlineAlertFor(assignment);
        final displayDeadlineAlert = effectivelyCompleted ||
                (_presentedDeadlineAlert != null &&
                    latestDeadlineChange != null &&
                    latestDeadlineChange.effectiveChangeId !=
                        _presentedDeadlineAlert!.effectiveChangeId &&
                    liveDeadlineAlert == null)
            ? null
            : (liveDeadlineAlert ?? _presentedDeadlineAlert);
        if (liveDeadlineAlert != null) {
          final changeId = liveDeadlineAlert.effectiveChangeId;
          if (_presentedDeadlineAlert?.effectiveChangeId != changeId ||
              !_attemptedAckChangeIds.contains(changeId)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _presentedDeadlineAlert = liveDeadlineAlert;
              if (_attemptedAckChangeIds.add(changeId)) {
                unawaited(widget.store.acknowledgeDeadlineAlert(changeId));
              }
            });
          }
        }
        final directPersonal = widget.store.personal.work[widget.assignmentId];
        final fallbackPersonal =
            directPersonal == null && assignment.id != widget.assignmentId
                ? widget.store.personal.work[assignment.id]
                : null;
        final personalTargetId =
            directPersonal != null ? widget.assignmentId : assignment.id;
        final personalWork = directPersonal ?? fallbackPersonal;
        final notePreviewText = personalWork?.note.trim() ?? '';
        final personalSteps = personalWork?.steps ?? const <PersonalStep>[];
        final showPersonalPreview = personalWork != null &&
            (notePreviewText.isNotEmpty || personalSteps.isNotEmpty);
        final resolvedDeadline = assignment.isExam
            ? null
            : CourseworkDeadline.resolveEntry(assignment, courseworkEntry);
        final manualAt = courseworkEntry?.manualDeadlineAt;
        final hasActiveManual = resolvedDeadline?.isManual == true;
        final canEditManual = !assignment.isExam &&
            CourseworkDeadline.canSetManualDeadline(
              assignment,
              entry: courseworkEntry,
            );
        final effectiveAt =
            assignment.isExam ? assignment.timelineAt : resolvedDeadline?.at;
        final bucket = assignment.isExam
            ? AssignmentQuery.timelineBucketAt(assignment, _now)
            : CourseworkDeadline.bucketAt(
                assignment,
                _now,
                entry: courseworkEntry,
              );
        final overdue =
            !effectivelyCompleted && bucket == AssignmentDeadlineBucket.overdue;
        final today = effectiveAt != null &&
            bucket != AssignmentDeadlineBucket.unconfirmed &&
            AssignmentQuery.dayKey(effectiveAt) == AssignmentQuery.dayKey(_now);
        final urgentLabel = effectivelyCompleted
            ? null
            : overdue
                ? '${hasActiveManual ? '手动截止已过' : '已逾期'}${_now.difference(effectiveAt!).inDays > 0 ? '${_now.difference(effectiveAt).inDays}天' : ''}'
                : !assignment.isExam &&
                        assignment.isPendingConfirmed &&
                        resolvedDeadline != null &&
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
                        (!hasActiveManual &&
                            (!assignment.deadlineTrusted ||
                                assignment.deadlineReadFailed)))
                    ? CourseworkPillTone.unconfirmed
                    : CourseworkPillTone.neutral;
        final cleanRequirements = assignment.requirementsText.trim();
        final showRequirements = cleanRequirements.isNotEmpty &&
            cleanRequirements != assignment.title.trim();
        final displayCourse = assignment.courseName.trim();
        final displayTitle = assignment.title.trim().isNotEmpty
            ? assignment.title.trim()
            : displayCourse;
        final isGenericExamLabel = assignment.isExam &&
            const {'考试通知', '账号考试', '课程考试', '考试'}.contains(displayCourse);
        final showCourseLabel = displayCourse.isNotEmpty &&
            displayCourse != displayTitle &&
            !isGenericExamLabel;
        final hasTrustedFullExamRange = exam != null &&
            exam.startTrusted &&
            exam.startAt != null &&
            exam.endTrusted &&
            exam.endAt != null;
        final reqDisplay = AssignmentDetailScreen.formatRequirementsForDisplay(
          assignment,
          displayTitle: displayTitle,
          displayCourse: displayCourse,
          hasTrustedFullExamRange: hasTrustedFullExamRange,
        );
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
          if (localDoneOnly)
            const CourseworkStatusPill(
              label: '本机标记',
              tone: CourseworkPillTone.completed,
              icon: Icons.check_circle_outline_rounded,
            ),
          if (hasActiveManual)
            const CourseworkStatusPill(
              label: '手动截止',
              tone: CourseworkPillTone.neutral,
              icon: Icons.edit_calendar_outlined,
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
          if (hasActiveManual) '官方截止仍待确认，当前日历与提醒已按手动截止投影。',
          if (!assignment.isExam &&
              !assignment.deadlineTrusted &&
              assignment.deadlineAt != null &&
              !hasActiveManual)
            '历史截止时间待确认，不参与日历和提醒',
          if (showRawDeadline) assignment.deadlineRawText!,
          if (!assignment.isExam &&
              assignment.deadlineReadFailed &&
              assignment.deadlineAt != null)
            assignment.deadlineLabel,
        ];
        final hasTimeLine = assignment.isExam ? examLines.isNotEmpty : true;
        final workStart = assignment.availableFromAt;
        final workStartText = assignment.availableFromText?.trim() ?? '';
        final workDeadline = assignment.deadlineAt;
        final hasWorkBeijingTime = !assignment.isExam &&
            (workStart != null || workDeadline != null || manualAt != null);
        final workTimeRows = assignment.isExam
            ? const <({
                IconData icon,
                Color iconColor,
                String label,
                String value,
              })>[]
            : <({
                IconData icon,
                Color iconColor,
                String label,
                String value,
              })>[
                if (workStart != null)
                  (
                    icon: Icons.play_circle_outline_rounded,
                    iconColor: journal.muted,
                    label: '开始',
                    value: DateFormat('yyyy年M月d日 HH:mm', 'zh_CN')
                        .format(AssignmentQuery.beijing(workStart)),
                  )
                else if (workStartText.isNotEmpty)
                  (
                    icon: Icons.play_circle_outline_rounded,
                    iconColor: journal.muted,
                    label: '开始',
                    value: workStartText,
                  ),
                if (workDeadline != null)
                  (
                    icon: Icons.schedule_rounded,
                    iconColor: !hasActiveManual && overdue
                        ? journal.berry
                        : journal.muted,
                    label: !assignment.deadlineTrusted ||
                            assignment.deadlineReadFailed
                        ? '历史截止（未核实）'
                        : '截止',
                    value: DateFormat('yyyy年M月d日 HH:mm', 'zh_CN')
                        .format(AssignmentQuery.beijing(workDeadline)),
                  )
                else
                  (
                    icon: Icons.schedule_rounded,
                    iconColor: journal.muted,
                    label: '截止',
                    value: assignment.deadlineLabel,
                  ),
                if (manualAt != null)
                  (
                    icon: Icons.edit_calendar_outlined,
                    iconColor: hasActiveManual && overdue
                        ? journal.berry
                        : journal.ink,
                    label: hasActiveManual ? '手动截止（官方待确认）' : '手动旧记录（已被官方接管）',
                    value: DateFormat('yyyy年M月d日 HH:mm', 'zh_CN')
                        .format(AssignmentQuery.beijing(manualAt)),
                  ),
              ];
        final showManualNotice = _actionMessage != null &&
            _actionMessageTarget == _DetailNoticeTarget.manual;
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: journal.cardBorder, width: 0.8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
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
                                fontSize: 20.5,
                                height: 1.34,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (statusWidgets.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              key: const ValueKey('assignment-detail-status'),
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: statusWidgets,
                            ),
                          ],
                          if (hasTimeLine) ...[
                            const SizedBox(height: 12),
                            Divider(
                              height: 1,
                              thickness: 0.6,
                              color: journal.divider,
                            ),
                            const SizedBox(height: 12),
                            if (assignment.isExam)
                              Column(
                                key: const ValueKey('assignment-detail-time'),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '考试安排',
                                          style: journal.metadata.copyWith(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      if (hasExamTime)
                                        Text(
                                          '北京时间',
                                          style: journal.metadata.copyWith(
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  for (var i = 0;
                                      i < examLines.length;
                                      i++) ...[
                                    if (i > 0) const SizedBox(height: 6),
                                    _ExamDetailRow(line: examLines[i]),
                                  ],
                                ],
                              )
                            else
                              Column(
                                key: const ValueKey('assignment-detail-time'),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '时间安排',
                                          style: journal.metadata.copyWith(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      if (hasWorkBeijingTime)
                                        Text(
                                          '北京时间',
                                          style: journal.metadata.copyWith(
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  for (var i = 0;
                                      i < workTimeRows.length;
                                      i++) ...[
                                    if (i > 0) const SizedBox(height: 8),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 2),
                                          child: Icon(
                                            workTimeRows[i].icon,
                                            size: 17,
                                            color: workTimeRows[i].iconColor,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                workTimeRows[i].label,
                                                style:
                                                    journal.metadata.copyWith(
                                                  fontSize: 12.5,
                                                ),
                                              ),
                                              const SizedBox(height: 1),
                                              Text(
                                                workTimeRows[i].value,
                                                style: journal.time.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (!assignment.isExam &&
                                      (canEditManual || manualAt != null)) ...[
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        if (canEditManual)
                                          OutlinedButton.icon(
                                            key: const ValueKey(
                                                'assignment-set-manual-deadline'),
                                            style: OutlinedButton.styleFrom(
                                              minimumSize: const Size(48, 48),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8),
                                              foregroundColor: journal.ink,
                                              backgroundColor:
                                                  journal.parchment,
                                              side: BorderSide(
                                                color: journal.cardBorder,
                                                width: 0.8,
                                              ),
                                            ),
                                            onPressed: _savingManualDeadline ||
                                                    _refreshing ||
                                                    _hiding
                                                ? null
                                                : () => _pickManualDeadline(
                                                      courseworkTarget,
                                                      existing: manualAt,
                                                    ),
                                            icon: const Icon(
                                              Icons.edit_calendar_outlined,
                                              size: 17,
                                            ),
                                            label: Text(hasActiveManual
                                                ? '修改手动截止'
                                                : '手动设置截止时间'),
                                          ),
                                        if (manualAt != null)
                                          TextButton.icon(
                                            key: const ValueKey(
                                                'assignment-clear-manual-deadline'),
                                            style: TextButton.styleFrom(
                                              minimumSize: const Size(48, 48),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 8),
                                              foregroundColor: journal.berry,
                                            ),
                                            onPressed: _savingManualDeadline ||
                                                    _refreshing ||
                                                    _hiding
                                                ? null
                                                : () => _clearManualDeadline(
                                                    courseworkTarget),
                                            icon: const Icon(
                                                Icons.clear_rounded,
                                                size: 17),
                                            label: Text(hasActiveManual
                                                ? '清除手动截止'
                                                : '清除手动旧记录'),
                                          ),
                                      ],
                                    ),
                                  ],
                                  if (showManualNotice) ...[
                                    const SizedBox(height: 8),
                                    _DetailActionNotice(
                                      key: const ValueKey(
                                          'assignment-manual-deadline-result'),
                                      message: _actionMessage!,
                                    ),
                                  ],
                                ],
                              ),
                          ],
                          if (displayDeadlineAlert != null) ...[
                            const SizedBox(height: 12),
                            _DetailDeadlineAlertBanner(
                              alert: displayDeadlineAlert,
                            ),
                          ],
                          if (verificationNotes.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              key: const ValueKey(
                                  'assignment-detail-verification'),
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: journal.ochreBg.withValues(
                                  alpha: journal.isDark ? 0.65 : 0.72,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: journal.ochreBorder,
                                  width: 0.7,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Icon(
                                      Icons.info_outline_rounded,
                                      size: 15,
                                      color: journal.ochre,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (var i = 0;
                                            i < verificationNotes.length;
                                            i++) ...[
                                          if (i > 0) const SizedBox(height: 4),
                                          Text(
                                            verificationNotes[i],
                                            style: journal.metadata.copyWith(
                                              color: journal.ochre,
                                              fontSize: 12.5,
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
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
                  if (showPersonalPreview) ...[
                    const SizedBox(height: 12),
                    _DetailPersonalNotePreviewCard(
                      targetAssignmentId: personalTargetId,
                      note: notePreviewText,
                      steps: personalSteps,
                    ),
                  ],
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
                    const SizedBox(height: 14),
                    JournalGroupedCard(
                      title: reqDisplay.title,
                      dividerIndent: 16,
                      children: [
                        if (reqDisplay.body.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              12,
                              16,
                              reqDisplay.trimmedRedundantLines ? 10 : 14,
                            ),
                            child: Text(
                              reqDisplay.body,
                              key: const ValueKey(
                                  'assignment-detail-requirements'),
                              style: journal.metadata.copyWith(
                                color: journal.ink,
                                fontSize: 14.5,
                                height: 1.55,
                              ),
                            ),
                          ),
                        if (reqDisplay.trimmedRedundantLines)
                          _RawNoticeTile(
                            tileKey: reqDisplay.body.isEmpty
                                ? const ValueKey(
                                    'assignment-detail-requirements')
                                : null,
                            rawText: reqDisplay.rawText,
                          ),
                      ],
                    ),
                  ],
                  if (sources.length > 1) ...[
                    const SizedBox(height: 14),
                    JournalGroupedCard(
                      children: [
                        Theme(
                          data: Theme.of(context)
                              .copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            key: const ValueKey('assignment-source-records'),
                            tilePadding:
                                const EdgeInsets.symmetric(horizontal: 14),
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
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14),
                                  title: Text(
                                    '${_sourceType(source)} · ${source.statusLabel}',
                                  ),
                                  subtitle: Text(
                                    '读取 ${DateFormat('yyyy-MM-dd HH:mm').format(source.lastSyncedAt.toLocal())}',
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
                    ),
                  ],
                  const SizedBox(height: 16),
                  JournalPrimaryButton(
                    buttonKey: const ValueKey('assignment-detail-open'),
                    height: 46,
                    backgroundColor: journal.isDark
                        ? journal.primaryFill
                        : const Color(0xFF34322F),
                    foregroundColor: journal.isDark
                        ? journal.onPrimaryFill
                        : const Color(0xFFFFF7EC),
                    onPressed: _opening || _hiding || _currentUrl == null
                        ? null
                        : _openAssignment,
                    icon: Icons.open_in_new_rounded,
                    label: _opening
                        ? '正在打开…'
                        : assignment.isExam
                            ? '在学习通内查看$_itemLabel'
                            : '在学习通内打开作业',
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton.icon(
                      key: const ValueKey('assignment-detail-open-web'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        foregroundColor: journal.ink,
                        disabledForegroundColor: journal.muted,
                        textStyle: journal.metadata.copyWith(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onPressed: _opening || _hiding || _currentUrl == null
                          ? null
                          : _openWeb,
                      icon: const Icon(Icons.open_in_browser_rounded, size: 17),
                      label: Text(_opening ? '正在请求浏览器…' : '打开$_itemLabel网页'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '将在学习通内打开$_itemLabel网页；浏览器打开可能需要另行登录，返回可刷新核对状态。',
                      style: journal.metadata.copyWith(
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
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
                  const SizedBox(height: 16),
                  JournalGroupedCard(
                    title: '手记工具',
                    dividerIndent: 16,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: _DetailToolButton(
                          onPressed: () => context.push(
                            '/personal/${Uri.encodeComponent(widget.assignmentId)}',
                          ),
                          icon: Icons.edit_note_rounded,
                          label: '个人清单与备注',
                          iconSize: 20,
                        ),
                      ),
                      if (!isHidden &&
                          !assignment.isExam &&
                          !assignment.isCompleted)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: _DetailToolButton(
                            key: const ValueKey(
                                'assignment-detail-local-complete'),
                            onPressed:
                                _savingManualDeadline || _hiding || _refreshing
                                    ? null
                                    : () => _toggleLocallyCompleted(
                                          courseworkTarget,
                                          !localDoneOnly,
                                        ),
                            icon: localDoneOnly
                                ? Icons.undo_rounded
                                : Icons.check_circle_outline_rounded,
                            label: localDoneOnly ? '撤销本机完成标记' : '标记为本机已完成',
                          ),
                        ),
                      if (!isHidden)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: _DetailToolButton(
                            onPressed: () => context.push('/plan'),
                            icon: Icons.checklist_rounded,
                            label: '安排每日计划',
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: _DetailToolButton(
                          onPressed: () => context.push(
                            '/reminder-status/assignment/'
                            '${Uri.encodeComponent(assignment.id)}',
                          ),
                          icon: Icons.notifications_active_outlined,
                          label: '提醒状态',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  JournalGroupedCard(
                    title: '记录管理',
                    dividerIndent: 16,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: _DetailToolButton(
                          onPressed:
                              _refreshing || widget.store.isLoading || _hiding
                                  ? null
                                  : _refresh,
                          icon: Icons.refresh_rounded,
                          label: _refreshing ? '正在刷新…' : '刷新$_itemLabel信息',
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: _DetailToolButton(
                          onPressed:
                              _currentUrl == null || _hiding ? null : _copyLink,
                          icon: Icons.copy_outlined,
                          label: '复制$_itemLabel链接',
                          iconSize: 17,
                        ),
                      ),
                      if (showRecordsNotice)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          child: _DetailActionNotice(
                            key: const ValueKey('assignment-records-result'),
                            message: _actionMessage!,
                          ),
                        ),
                      if (!isHidden && !assignment.isCompleted)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: _DetailToolButton(
                            key: const ValueKey('assignment-detail-hide'),
                            onPressed: _hiding || _opening || _refreshing
                                ? null
                                : _hide,
                            icon: Icons.visibility_off_outlined,
                            label: sources.length > 1
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
        );
      },
    );
  }
}

enum _DetailNoticeTarget { opening, records, restore, pin, manual }

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

class _DetailToolButton extends StatelessWidget {
  const _DetailToolButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.iconSize = 18,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final double iconSize;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: TextButton(
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            foregroundColor: Journal.of(context).ink,
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
                            : Journal.of(context).ink,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: onPressed == null
                      ? Journal.of(context).muted.withValues(alpha: 0.35)
                      : Journal.of(context).muted,
                ),
              ),
            ],
          ),
        ),
      );
}

class _ExamDetailRow extends StatelessWidget {
  const _ExamDetailRow({required this.line});

  final String line;

  IconData _iconFor(String text) {
    if (text.startsWith('开考')) return Icons.play_circle_outline_rounded;
    if (text.startsWith('结束')) return Icons.stop_circle_outlined;
    if (text.startsWith('时长')) return Icons.timer_outlined;
    if (text.startsWith('地点')) return Icons.place_outlined;
    return Icons.schedule_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(_iconFor(line), size: 17, color: journal.muted),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            line,
            style: journal.time.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _RawNoticeTile extends StatelessWidget {
  const _RawNoticeTile({this.tileKey, required this.rawText});

  final Key? tileKey;
  final String rawText;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: tileKey,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: Text(
          '查看通知原文',
          style: journal.metadata.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              rawText,
              style: journal.metadata.copyWith(
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailDeadlineAlertBanner extends StatelessWidget {
  const _DetailDeadlineAlertBanner({required this.alert});

  final AssignmentChange alert;

  static String _formatBeijing(DateTime utcTime) =>
      DateFormat('yyyy年M月d日 HH:mm').format(AssignmentQuery.beijing(utcTime));

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final beforeUtc = alert.effectiveBeforeUtc;
    final afterUtc = alert.effectiveAfterUtc;
    final oldLabel = beforeUtc == null ? '待确认' : _formatBeijing(beforeUtc);
    final newLabel = afterUtc == null ? '待确认' : _formatBeijing(afterUtc);
    final headline = beforeUtc == null ? '时间变更：官方截止已明确' : '时间变更：官方截止已提前';
    return Container(
      key: const ValueKey('assignment-detail-deadline-alert'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: journal.berryBg.withValues(
          alpha: journal.isDark ? 0.65 : 0.85,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: journal.berryBorder,
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.update_rounded,
              size: 16,
              color: journal.berry,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: journal.metadata.copyWith(
                    color: journal.berry,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '原截止：$oldLabel → 新截止：$newLabel（北京时间）',
                  style: journal.metadata.copyWith(
                    color: journal.ink,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailPersonalNotePreviewCard extends StatelessWidget {
  const _DetailPersonalNotePreviewCard({
    required this.targetAssignmentId,
    required this.note,
    required this.steps,
  });

  final String targetAssignmentId;
  final String note;
  final List<PersonalStep> steps;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final doneSteps = steps.where((s) => s.done).length;
    return Material(
      key: const ValueKey('assignment-detail-personal-preview'),
      color: journal.sheet,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: journal.cardBorder, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => GoRouter.maybeOf(context)?.push(
          '/personal/${Uri.encodeComponent(targetAssignmentId)}',
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.edit_note_rounded,
                    size: 19,
                    color: journal.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '个人便签',
                            style: journal.metadata.copyWith(
                              color: journal.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (steps.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: journal.parchment,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '清单 $doneSteps/${steps.length}',
                                style: journal.metadata.copyWith(
                                  fontSize: 11.5,
                                  color: journal.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: journal.metadata.copyWith(
                            color: journal.ink,
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                        ),
                      ] else if (steps.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          steps
                              .firstWhere(
                                (s) => !s.done,
                                orElse: () => steps.first,
                              )
                              .text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: journal.metadata.copyWith(
                            color: journal.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: journal.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

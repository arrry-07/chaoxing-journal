import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/journal.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../services/assignment_store.dart';
import '../services/assignment_query.dart';
import '../services/assignment_web_link.dart';
import '../services/external_link_service.dart';

class AssignmentDetailScreen extends StatefulWidget {
  const AssignmentDetailScreen({
    super.key,
    required this.store,
    required this.assignmentId,
  });

  final AssignmentStore store;
  final String assignmentId;

  @override
  State<AssignmentDetailScreen> createState() => _AssignmentDetailScreenState();
}

class _AssignmentDetailScreenState extends State<AssignmentDetailScreen> {
  final _links = ExternalLinkService();
  bool _opening = false, _hiding = false, _refreshing = false;
  String? _actionMessage;

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
              title: const Text('复制作业链接'),
              content: const Text('链接含作业访问参数，请只在本人设备使用，勿转发或公开。'),
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
    var hidden = false;
    try {
      hidden = await widget.store.hideAssignment(widget.assignmentId);
    } catch (_) {
      // Preserve the detail view for retry, including persistence exceptions.
    }
    if (!mounted) return;
    if (hidden) {
      context.go('/assignments');
      return;
    }
    setState(() {
      _hiding = false;
      _actionMessage = '隐藏失败，请稍后重试；本机记录仍保留。';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final assignment = widget.store.findAssignment(widget.assignmentId);
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
            Text(
              assignment.courseName,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Text(
              assignment.title,
              style: const TextStyle(
                  fontSize: 26,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: Journal.ink),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.event_available),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        assignment.deadlineAt == null
                            ? assignment.deadlineLabel
                            : '${DateFormat('yyyy年M月d日 HH:mm', 'zh_CN').format(AssignmentQuery.beijing(assignment.deadlineAt!))}（北京时间）',
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
                      Text(assignment.statusLabel),
                      if (!assignment.deadlineTrusted &&
                          assignment.deadlineAt != null)
                        const Text('历史截止时间待确认，不参与日历和提醒'),
                      if (assignment.deadlineRawText != null)
                        Text(assignment.deadlineRawText!),
                      if (assignment.deadlineReadFailed &&
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
              label: Text(_opening ? '正在打开…' : '去学习通完成'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed:
                  _opening || _hiding || _currentUrl == null ? null : _openWeb,
              icon: const Icon(Icons.open_in_browser),
              label: Text(_opening ? '正在请求浏览器…' : '打开作业网页'),
            ),
            const SizedBox(height: 8),
            const Text('通过学习通打开作业网页；可能需要另行登录。返回后可刷新核对提交状态。'),
            if (_currentUrl == null) ...[
              const SizedBox(height: 8),
              const Text('作业链接暂不可用，请刷新作业信息；尚未开放的作业请稍后重试。'),
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
                label: Text(_refreshing ? '正在刷新…' : '刷新作业信息'),
              ),
              TextButton.icon(
                onPressed: _currentUrl == null || _hiding ? null : _copyLink,
                icon: const Icon(Icons.copy_outlined),
                label: const Text('复制作业链接'),
              ),
            ]),
            const SizedBox(height: 12),
            if (!assignment.isCompleted)
              TextButton.icon(
                onPressed: _hiding || _opening || _refreshing ? null : _hide,
                icon: const Icon(Icons.visibility_off_outlined),
                label: const Text('在本机隐藏此作业'),
              ),
          ],
        );
      },
    );
  }
}

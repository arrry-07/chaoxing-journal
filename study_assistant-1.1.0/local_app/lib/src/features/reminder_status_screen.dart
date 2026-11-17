import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/reminder_history.dart';
import '../services/assignment_store.dart';
import '../services/permission_settings_service.dart';
import 'reminder_history_screen.dart';

class ReminderStatusScreen extends StatefulWidget {
  const ReminderStatusScreen({
    super.key,
    required this.store,
    required this.kind,
    required this.id,
    this.permissionSettingsService = const PermissionSettingsService(),
  });

  final AssignmentStore store;
  final String kind;
  final String id;
  final PermissionSettingsService permissionSettingsService;

  @override
  State<ReminderStatusScreen> createState() => _ReminderStatusScreenState();
}

class _ReminderStatusScreenState extends State<ReminderStatusScreen> {
  ReminderExplanation? _explanation;
  String? _error;
  bool _loading = false;
  bool _retrying = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await widget.store.explainReminder(
        kind: widget.kind,
        id: widget.id,
      );
      if (!mounted) return;
      setState(() => _explanation = value);
    } on ReminderHistoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '提醒原因暂时无法读取：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _statusLabel(ReminderExplanationStatus status) => switch (status) {
        ReminderExplanationStatus.planned => '已计划',
        ReminderExplanationStatus.deferred => '暂缓',
        ReminderExplanationStatus.ineligible => '不会提醒',
        ReminderExplanationStatus.unconfirmed => '结果未确认',
        ReminderExplanationStatus.queryFailed => '查询失败',
      };

  Color _statusColor(BuildContext context, ReminderExplanationStatus status) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      ReminderExplanationStatus.planned => scheme.primary,
      ReminderExplanationStatus.deferred => scheme.tertiary,
      ReminderExplanationStatus.ineligible => scheme.outline,
      ReminderExplanationStatus.unconfirmed => scheme.error,
      ReminderExplanationStatus.queryFailed => scheme.error,
    };
  }

  Future<void> _openSystemSettings() async {
    final result =
        await widget.permissionSettingsService.openNotificationSettingsResult();
    if (!mounted) return;
    final text = switch (result) {
      SettingsOpenResult.direct => '已打开系统通知设置',
      SettingsOpenResult.listFallback => '未能直达通知设置，已打开系统设置列表',
      SettingsOpenResult.appDetailsFallback => '已打开应用详情，请进入通知设置核对',
      SettingsOpenResult.unavailable => '无法打开系统设置，请手动查找本应用',
    };
    setState(() => _message = text);
  }

  Future<void> _retryRecovery() async {
    if (_loading || _retrying) return;
    setState(() {
      _retrying = true;
      _message = null;
    });
    try {
      await widget.store.retryReminderRecovery();
      if (!mounted) return;
      setState(() => _message = '提醒恢复已重新执行，请核对下方状态');
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = '提醒恢复仍未完成：$error');
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final explanation = _explanation;
    return Scaffold(
      appBar: AppBar(title: const Text('提醒状态')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (explanation != null) ...[
            Text(
              explanation.displayName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '查询时间 ${DateFormat('yyyy-MM-dd HH:mm:ss').format(explanation.checkedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            for (final category in explanation.categories) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              reminderCategoryLabels[category.category] ?? '提醒',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Chip(
                            label: Text(_statusLabel(category.status)),
                            labelStyle: TextStyle(
                              color: _statusColor(context, category.status),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (category.nextScheduledAt != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '下一次计划：${DateFormat('M月d日 HH:mm').format(category.nextScheduledAt!)}',
                        ),
                      ],
                      if (category.evidenceAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '系统排期证据：${DateFormat('M月d日 HH:mm:ss').format(category.evidenceAt!)}',
                        ),
                      ],
                      if (category.reasonCodes.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        for (final reason in category.reasonCodes)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '· ${reminderReasonLabels[reason] ?? '其他原因'}',
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (explanation.queryWarnings.isNotEmpty) ...[
              const Divider(),
              Text(
                '部分证据未读取',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final warning in explanation.queryWarnings)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('· $warning'),
                ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (widget.kind == 'assignment')
                  OutlinedButton(
                    onPressed: () => context.go(
                      '/assignments/${Uri.encodeComponent(widget.id)}',
                    ),
                    child: const Text('查看课业详情'),
                  ),
                OutlinedButton(
                  onPressed: () => context.go('/reminders'),
                  child: const Text('打开提醒设置'),
                ),
                OutlinedButton(
                  onPressed: _openSystemSettings,
                  child: const Text('系统通知设置'),
                ),
                FilledButton(
                  onPressed: _loading || _retrying ? null : _retryRecovery,
                  child: Text(_retrying ? '正在重试…' : '重试提醒恢复'),
                ),
              ],
            ),
          ],
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Semantics(
                liveRegion: true,
                child: Text(_message!),
              ),
            ),
        ],
      ),
    );
  }
}

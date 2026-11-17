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
    this.hasUnsavedEdits = false,
    this.permissionSettingsService = const PermissionSettingsService(),
  });

  final AssignmentStore store;
  final String kind;
  final String id;
  final bool hasUnsavedEdits;
  final PermissionSettingsService permissionSettingsService;

  @override
  State<ReminderStatusScreen> createState() => _ReminderStatusScreenState();
}

class _ReminderStatusScreenState extends State<ReminderStatusScreen>
    with WidgetsBindingObserver {
  ReminderExplanation? _explanation;
  String? _error;
  bool _loading = false;
  bool _retrying = false;
  String? _message;
  int _requestToken = 0;
  String? _accountHash;
  int _accountEpoch = 0;
  int _nativeEpoch = 0;
  int _historyGeneration = 0;

  (String?, int, int, int) _currentIdentity() => (
        widget.store.accountHash,
        widget.store.accountEpoch,
        widget.store.nativeSessionEpoch,
        widget.store.reminderHistoryGeneration,
      );

  @override
  void initState() {
    super.initState();
    final id = _currentIdentity();
    _accountHash = id.$1;
    _accountEpoch = id.$2;
    _nativeEpoch = id.$3;
    _historyGeneration = id.$4;
    WidgetsBinding.instance.addObserver(this);
    widget.store.addListener(_handleStoreChanged);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(_handleStoreChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load(force: true);
    }
  }

  void _handleStoreChanged() {
    final next = _currentIdentity();
    if (next ==
        (_accountHash, _accountEpoch, _nativeEpoch, _historyGeneration)) {
      return;
    }
    _accountHash = next.$1;
    _accountEpoch = next.$2;
    _nativeEpoch = next.$3;
    _historyGeneration = next.$4;
    if (!mounted) return;
    setState(() {
      _explanation = null;
      _error = null;
      _message = null;
    });
    _load(force: true);
  }

  Future<void> _load({bool force = false}) async {
    if (_loading && !force) return;
    final token = ++_requestToken;
    final startIdentity = _currentIdentity();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await widget.store.explainReminder(
        kind: widget.kind,
        id: widget.id,
      );
      if (!mounted ||
          token != _requestToken ||
          startIdentity != _currentIdentity()) {
        return;
      }
      setState(() => _explanation = value);
    } on ReminderHistoryException catch (error) {
      if (!mounted ||
          token != _requestToken ||
          startIdentity != _currentIdentity()) {
        return;
      }
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted ||
          token != _requestToken ||
          startIdentity != _currentIdentity()) {
        return;
      }
      setState(() => _error = '提醒原因暂时无法读取：$error');
    } finally {
      if (mounted && token == _requestToken) {
        setState(() => _loading = false);
      }
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
      final warnings = <String>{
        if (widget.store.operationError != null) widget.store.operationError!,
        ...widget.store.serviceWarnings,
      }.toList();
      setState(() {
        _message = warnings.isEmpty
            ? '提醒恢复已重新执行，请核对下方状态'
            : '提醒恢复仍有未完成项：${warnings.join('；')}';
      });
      await _load(force: true);
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
      appBar: AppBar(
        title: const Text('提醒状态'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : () => _load(force: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (widget.hasUnsavedEdits) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                '当前展示已保存事项的提醒状态；编辑页中的未保存修改需保存后才会生效。',
              ),
            ),
          ],
          if (_error != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            if (explanation == null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _loading ? null : () => _load(force: true),
                child: const Text('重新查询'),
              ),
            ],
          ],
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
                    onPressed: () async {
                      await context.push(
                        '/assignments/${Uri.encodeComponent(widget.id)}',
                      );
                      if (mounted) await _load(force: true);
                    },
                    child: const Text('查看课业详情'),
                  ),
                OutlinedButton(
                  onPressed: () async {
                    await context.push('/reminders');
                    if (mounted) await _load(force: true);
                  },
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

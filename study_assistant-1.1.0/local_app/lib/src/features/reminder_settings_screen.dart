import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../app/journal.dart';
import '../models/reminder_rule_limits.dart';

import '../services/assignment_store.dart';
import '../services/permission_settings_service.dart';
import '../services/reminder_rule_store.dart';

class ReminderSettingsScreen extends StatefulWidget {
  const ReminderSettingsScreen({
    super.key,
    required this.assignmentStore,
    this.permissionSettingsService = const PermissionSettingsService(),
  });

  final AssignmentStore assignmentStore;
  final PermissionSettingsService permissionSettingsService;

  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen>
    with WidgetsBindingObserver {
  static const _presetOffsets = {
    1440: '提前 1 天',
    180: '提前 3 小时',
    30: '提前 30 分钟',
    10: '提前 10 分钟',
  };

  final _customHoursController = TextEditingController();
  final _customMinutesController = TextEditingController();
  final Set<int> _offsets = {};
  bool _saving = false;
  bool? _listenerGranted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _offsets.addAll(widget.assignmentStore.reminderOffsetsMinutes);
    unawaited(_refreshListenerGranted());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _customHoursController.dispose();
    _customMinutesController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshListenerGranted();
  }

  Future<void> _refreshListenerGranted() async {
    final granted =
        await widget.permissionSettingsService.isNotificationListenerEnabled();
    if (mounted) setState(() => _listenerGranted = granted);
  }

  @override
  Widget build(BuildContext context) {
    final customOffsets = _offsets
        .where((item) => !_presetOffsets.containsKey(item))
        .toList()
      ..sort((a, b) => b.compareTo(a));

    return Scaffold(
        appBar: AppBar(
            leading: IconButton(
                tooltip: '返回我的',
                icon: const Icon(Icons.arrow_back),
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/profile'))),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const JournalHeading('提醒设置',
                  eyebrow: 'CAMPUS JOURNAL   /   MEMO'),
              const SizedBox(height: 6),
              Text(
                '保存后会重新安排所有未完成作业的本地通知，自定义提醒支持精确到分钟',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (ReminderRuleStore.requiresReview(_offsets.toList())) ...[
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      '旧版提醒规则已保留，但超过365天的规则目前不会参与提醒调度。请调整到365天以内后再使用。\n'
                      '当前版本每份作业最多使用32条、最长365天；保存前请移除超出范围的规则。',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (widget.assignmentStore.notificationPrivacyPending) ...[
                const Text('旧详细提醒尚未清理，隐私设置未完全生效。'),
                TextButton(
                    onPressed: _saving ? null : () => _savePrivacy(false),
                    child: const Text('重试清理旧提醒')),
              ],
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('通知显示详细内容'),
                  subtitle:
                      const Text('默认隐藏课程、作业与个人事项详情；开启后可能在锁屏显示。系统设置仍会影响显示。'),
                  value: widget.assignmentStore.notificationDetails,
                  onChanged: _saving ? null : _savePrivacy),
              OutlinedButton.icon(
                  onPressed: () => context.push('/reminder-health'),
                  icon: const Icon(Icons.health_and_safety_outlined),
                  label: const Text('提醒体检与每日摘要')),
              const SizedBox(height: 16),
              Text(
                '作业后台检查',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      key: const ValueKey('background-check-switch'),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      title: const Text('白天后台检查'),
                      subtitle: const Text(
                        '08:00 至次日 00:00 低频检查；默认每 4 小时，不承诺整点执行',
                      ),
                      value: widget.assignmentStore.backgroundCheckEnabled,
                      onChanged: _saving ? null : _saveBackgroundCheckEnabled,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final option in const {
                            120: '2 小时',
                            240: '4 小时',
                            360: '6 小时',
                          }.entries)
                            ChoiceChip(
                              key:
                                  ValueKey('background-interval-${option.key}'),
                              label: Text(option.value),
                              selected: widget.assignmentStore
                                      .backgroundCheckIntervalMinutes ==
                                  option.key,
                              onSelected: _saving ||
                                      !widget.assignmentStore
                                          .backgroundCheckEnabled
                                  ? null
                                  : (_) => _saveBackgroundInterval(option.key),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      key: const ValueKey('notification-listener-switch'),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      title: const Text('学习通通知触发核对'),
                      subtitle: Text(
                        _listenerGranted == true
                            ? '已授权；只处理学习通通知信号，正文不落盘'
                            : '需单独授予系统通知使用权；默认关闭',
                      ),
                      value: widget.assignmentStore.notificationListenerEnabled,
                      onChanged: _saving ? null : _saveNotificationListener,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      key: const ValueKey('new-assignment-switch'),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      title: const Text('新增正式作业提醒'),
                      subtitle: const Text(
                        '首次完整同步只建立基线；之后同一次检查发现多条时合并提醒',
                      ),
                      value:
                          widget.assignmentStore.newAssignmentReminderEnabled,
                      onChanged: _saving ? null : _saveNewAssignmentReminder,
                    ),
                  ],
                ),
              ),
              Text(
                '提醒权限',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.notifications_active_outlined),
                      title: const Text('通知权限'),
                      subtitle: const Text('允许系统通知，关闭后不会弹出提醒'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _requestNotificationPermission,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.notifications_paused_outlined),
                      title: const Text('通知使用权'),
                      subtitle: Text(
                        _listenerGranted == true
                            ? '系统已授权学习通通知信号核对'
                            : '未授权；不影响白天定时检查',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await _openPermissionSettings(
                            widget.permissionSettingsService
                                .openNotificationListenerSettingsResult,
                            destination: '通知使用权设置');
                        await _refreshListenerGranted();
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.alarm_on_outlined),
                      title: const Text('精确闹钟'),
                      subtitle: const Text('用于按分钟准时提醒，关闭后系统可能延迟通知'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openPermissionSettings(
                        widget.permissionSettingsService
                            .openExactAlarmSettingsResult,
                        destination: '精确闹钟设置',
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.lock_clock_outlined),
                      title: const Text('截止提醒通知渠道'),
                      subtitle: const Text(
                        '控制截止提醒的锁屏、横幅和声音；不提供独立锁屏设置页',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openPermissionSettings(
                        widget.permissionSettingsService
                            .openLockScreenNotificationSettingsResult,
                        destination: '截止提醒通知渠道',
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.battery_saver_outlined),
                      title: const Text('电池优化'),
                      subtitle: const Text(
                        '打开系统电池优化列表；请找到“学习通课业手记”并自行核对',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openPermissionSettings(
                        widget.permissionSettingsService
                            .openBatterySettingsResult,
                        destination: '电池优化设置',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      for (final item in _presetOffsets.entries)
                        CheckboxListTile(
                          value: _offsets.contains(item.key),
                          onChanged: (checked) =>
                              _toggleOffset(item.key, checked),
                          title: Text(item.value),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '自定义提醒',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customHoursController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: '小时',
                        prefixIcon: Icon(Icons.schedule),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _customMinutesController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: '分钟',
                        prefixIcon: Icon(Icons.timer_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _addCustomOffset,
                    child: const Text('添加'),
                  ),
                ],
              ),
              if (customOffsets.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      for (final offset in customOffsets)
                        ListTile(
                          leading:
                              const Icon(Icons.notifications_active_outlined),
                          title: Text(_labelFor(offset)),
                          trailing: IconButton(
                            onPressed: () =>
                                setState(() => _offsets.remove(offset)),
                            icon: const Icon(Icons.delete_outline),
                            tooltip: '删除',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _offsets.isEmpty || _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_saving ? '保存中' : '保存提醒规则'),
              ),
            ],
          ),
        ));
  }

  void _toggleOffset(int offset, bool? checked) {
    if ((checked ?? false) &&
        !_offsets.contains(offset) &&
        _offsets.length >= ReminderRuleLimits.maxRuleCount) {
      _showMessage('最多保存 32 条提醒规则');
      return;
    }
    setState(() {
      if (checked ?? false) {
        _offsets.add(offset);
      } else {
        _offsets.remove(offset);
      }
    });
  }

  void _addCustomOffset() {
    final hours = int.tryParse(_customHoursController.text.trim()) ?? 0;
    final minutes = int.tryParse(_customMinutesController.text.trim()) ?? 0;
    if (hours < 0 || minutes < 0) {
      _showMessage('请输入有效的小时和分钟');
      return;
    }
    final totalMinutes = hours * 60 + minutes;
    if (totalMinutes <= 0) {
      _showMessage('请输入大于 0 的提醒时间');
      return;
    }
    if (totalMinutes > ReminderRuleLimits.maxOffsetMinutes) {
      _showMessage('自定义提醒最长提前 365 天');
      return;
    }
    if (!_offsets.contains(totalMinutes) &&
        _offsets.length >= ReminderRuleLimits.maxRuleCount) {
      _showMessage('最多保存 32 条提醒规则');
      return;
    }
    setState(() {
      _offsets.add(totalMinutes);
      _customHoursController.clear();
      _customMinutesController.clear();
    });
  }

  Future<void> _saveBackgroundCheckEnabled(bool value) async {
    setState(() => _saving = true);
    try {
      final saved =
          await widget.assignmentStore.saveBackgroundCheckEnabled(value);
      if (mounted) {
        _showMessage(saved
            ? value
                ? '白天后台检查已开启'
                : '白天后台检查已关闭；通知监听和缓存截止提醒不受影响'
            : widget.assignmentStore.operationError ?? '设置保存失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final granted = await widget.assignmentStore.notificationService
          .requestNotificationsPermission();
      if (!mounted) return;
      if (!granted) {
        await _openPermissionSettings(
          widget.permissionSettingsService.openNotificationSettingsResult,
          destination: '通知设置',
        );
      } else {
        _showMessage('通知权限已开启');
      }
    } catch (_) {
      if (mounted) {
        await _openPermissionSettings(
          widget.permissionSettingsService.openNotificationSettingsResult,
          destination: '通知设置',
        );
      }
    }
  }

  Future<void> _saveBackgroundInterval(int minutes) async {
    setState(() => _saving = true);
    try {
      final saved = await widget.assignmentStore
          .saveBackgroundCheckIntervalMinutes(minutes);
      if (mounted) {
        _showMessage(saved
            ? '后台检查间隔已保存'
            : widget.assignmentStore.operationError ?? '设置保存失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveNotificationListener(bool value) async {
    setState(() => _saving = true);
    try {
      final saved =
          await widget.assignmentStore.saveNotificationListenerEnabled(value);
      if (!mounted) return;
      if (!saved) {
        _showMessage(widget.assignmentStore.operationError ?? '设置保存失败，请重试');
        return;
      }
      if (value && _listenerGranted != true) {
        final result = await widget.permissionSettingsService
            .openNotificationListenerSettingsResult();
        if (!mounted) return;
        _showMessage(switch (result) {
          SettingsOpenResult.direct => '请在系统页面中授予“学习通课业手记”通知使用权，返回后会自动刷新状态',
          SettingsOpenResult.listFallback =>
            '已打开通知使用权列表，请选择“学习通课业手记”并授予权限，返回后会自动刷新状态',
          SettingsOpenResult.appDetailsFallback =>
            '未能直达通知使用权设置，已打开“学习通课业手记”的应用详情',
          SettingsOpenResult.unavailable =>
            '无法打开通知使用权设置，请手动在手机系统设置中搜索“学习通课业手记”',
        });
      } else {
        _showMessage(value ? '通知触发核对已开启' : '通知触发核对已关闭');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveNewAssignmentReminder(bool value) async {
    setState(() => _saving = true);
    try {
      final saved =
          await widget.assignmentStore.saveNewAssignmentReminderEnabled(value);
      if (mounted) {
        _showMessage(saved
            ? value
                ? '新增正式作业提醒已开启'
                : '新增正式作业提醒已关闭；截止提醒仍由原规则控制'
            : widget.assignmentStore.operationError ?? '设置保存失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _savePrivacy(bool value) async {
    setState(() => _saving = true);
    try {
      await widget.assignmentStore.saveNotificationDetails(value);
      if (mounted) {
        _showMessage(widget.assignmentStore.error ?? '通知隐私已保存，待发提醒已更新');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (ReminderRuleStore.requiresReview(_offsets.toList())) {
      _showMessage('旧版提醒规则已保留，请先移除超出 32 条或 365 天的规则再保存');
      return;
    }
    setState(() => _saving = true);
    try {
      final saved =
          await widget.assignmentStore.saveReminderRule(_offsets.toList());
      if (!mounted) return;
      final operationError = widget.assignmentStore.operationError;
      final hasWarnings = widget.assignmentStore.serviceWarnings.isNotEmpty ||
          widget.assignmentStore.recoveryWarning != null;
      _showMessage(widget.assignmentStore.saveFeedback(
        saved,
        successMessage: hasWarnings ? '提醒时间已保存' : '提醒时间已保存，作业通知已更新',
        failureMessage: operationError == null
            ? '保存失败，请稍后重试；当前选择已保留'
            : '保存失败：$operationError；当前选择已保留',
      ));
    } catch (_) {
      if (mounted) _showMessage('保存失败，请稍后重试；当前选择已保留');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openPermissionSettings(
    Future<SettingsOpenResult> Function() openSettings, {
    required String destination,
  }) async {
    final result = await openSettings();
    if (!mounted) return;
    if (result == SettingsOpenResult.direct) return;
    _showMessage(switch (result) {
      SettingsOpenResult.direct => '',
      SettingsOpenResult.listFallback =>
        '未能直达$destination，已打开相关系统设置列表；请查找“学习通课业手记”',
      SettingsOpenResult.appDetailsFallback =>
        '未能直达$destination，已打开“学习通课业手记”的应用详情',
      SettingsOpenResult.unavailable =>
        '无法打开$destination，请手动在手机系统设置中搜索“学习通课业手记”',
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _labelFor(int offsetMinutes) {
    if (offsetMinutes % 1440 == 0) {
      return '提前 ${offsetMinutes ~/ 1440} 天';
    }
    final hours = offsetMinutes ~/ 60;
    final minutes = offsetMinutes % 60;
    if (hours > 0 && minutes > 0) {
      return '提前 $hours 小时 $minutes 分钟';
    }
    if (hours > 0) {
      return '提前 $hours 小时';
    }
    return '提前 $minutes 分钟';
  }
}

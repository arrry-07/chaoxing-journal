import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../app/journal.dart';

import '../services/assignment_store.dart';
import '../services/permission_settings_service.dart';

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

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
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

  @override
  void initState() {
    super.initState();
    _offsets.addAll(widget.assignmentStore.reminderOffsetsMinutes);
  }

  @override
  void dispose() {
    _customHoursController.dispose();
    _customMinutesController.dispose();
    super.dispose();
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
              const SizedBox(height: 16),
              OutlinedButton.icon(
                  onPressed: () => context.push('/reminder-health'),
                  icon: const Icon(Icons.health_and_safety_outlined),
                  label: const Text('提醒体检与每日摘要')),
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
                      onTap: () => _openPermissionSettings(
                        widget
                            .permissionSettingsService.openNotificationSettings,
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.alarm_on_outlined),
                      title: const Text('精确闹钟'),
                      subtitle: const Text('用于按分钟准时提醒，关闭后系统可能延迟通知'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openPermissionSettings(
                        widget.permissionSettingsService.openExactAlarmSettings,
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.lock_clock_outlined),
                      title: const Text('锁屏提醒'),
                      subtitle: const Text('允许提醒显示在锁屏、横幅和通知中心'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openPermissionSettings(
                        widget.permissionSettingsService
                            .openLockScreenNotificationSettings,
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.battery_saver_outlined),
                      title: const Text('后台与自启动'),
                      subtitle: const Text('降低系统休眠、清后台后漏提醒的概率'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openPermissionSettings(
                        widget.permissionSettingsService.openBatterySettings,
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
    setState(() {
      _offsets.add(totalMinutes);
      _customHoursController.clear();
      _customMinutesController.clear();
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.assignmentStore.saveReminderRule(_offsets.toList());
      if (!mounted) return;
      _showMessage(widget.assignmentStore.error == null
          ? '提醒时间已保存，作业通知已更新'
          : '保存失败，请稍后重试；当前选择已保留');
    } catch (_) {
      if (mounted) _showMessage('保存失败，请稍后重试；当前选择已保留');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openPermissionSettings(
    Future<bool> Function() openSettings,
  ) async {
    final opened = await openSettings();
    if (!mounted) return;
    if (!opened) {
      _showMessage('无法打开系统设置，请在手机设置里搜索"学习通作业提醒"');
    }
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

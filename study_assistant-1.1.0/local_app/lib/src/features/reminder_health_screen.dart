import 'package:flutter/material.dart';
import '../services/assignment_store.dart';
import '../services/background_reminder_gateway.dart';
import '../services/daily_summary.dart';
import '../services/permission_settings_service.dart';

class ReminderHealthScreen extends StatefulWidget {
  const ReminderHealthScreen({
    super.key,
    required this.store,
    this.permissionSettingsService = const PermissionSettingsService(),
  });
  final AssignmentStore store;
  final PermissionSettingsService permissionSettingsService;
  @override
  State<ReminderHealthScreen> createState() => _HealthState();
}

class _HealthState extends State<ReminderHealthScreen>
    with WidgetsBindingObserver {
  ReminderHealth? health;
  BackgroundReminderHealth? backgroundHealth;
  bool busy = false;
  String? message;
  late final int epoch;
  @override
  void initState() {
    super.initState();
    epoch = widget.store.accountEpoch;
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    if (!mounted || busy) return;
    setState(() => busy = true);
    ReminderHealth? value;
    var failed = false;
    BackgroundReminderHealth? nativeValue;
    try {
      value = await widget.store.notificationService.inspectHealth();
      nativeValue = await widget.store.inspectBackgroundReminderHealth();
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      if (value != null) health = value;
      backgroundHealth = nativeValue;
      busy = false;
      if (failed) message = '提醒状态读取失败，请稍后重试';
    });
  }

  String state(bool? v) => v == null
      ? '暂时无法读取'
      : v
          ? '已开启'
          : '未开启';
  String channelState(ReminderChannelHealth? value) => value?.label ?? '状态未知';
  Future<void> summary(bool enabled, int hour, int minute) async {
    if (busy) return;
    setState(() => busy = true);
    final ok = await widget.store
        .savePersonal((w) => w.withSummary(enabled, hour, minute), epoch);
    if (!mounted) return;
    setState(() {
      busy = false;
      message = ok
          ? widget.store.error == null
              ? '设置已保存；请核对下方已安排摘要数量。'
              : '设置已保存，但提醒仍需处理：${widget.store.error}'
          : '保存失败，请重试';
    });
    await refresh();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final p = widget.store.personal;
        return Scaffold(
            appBar: AppBar(title: const Text('提醒体检')),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              Text('先确认提醒能到达',
                  style: Theme.of(context).textTheme.headlineSmall),
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('权限开启和已安排不等于一定送达。厂商省电、锁屏设置与应用被强制停止都可能影响提醒。')),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('系统通知权限'),
                  subtitle: Text(state(health?.notifications)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openPermissionSettings(
                        widget.permissionSettingsService
                            .openNotificationSettingsResult,
                        destination: '通知设置',
                      )),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('作业变化通知渠道'),
                  subtitle:
                      Text(channelState(health?.assignmentUpdatesChannel)),
                  onTap: () => _openNotificationChannel(
                        'assignment_updates',
                        '作业变化通知渠道',
                      )),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('截止提醒通知渠道'),
                  subtitle: Text(channelState(health?.assignmentChannel)),
                  onTap: () => _openNotificationChannel(
                        'assignment_deadlines',
                        '截止提醒通知渠道',
                      )),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('每日摘要通知渠道'),
                  subtitle: Text(channelState(health?.summaryChannel)),
                  onTap: () => _openNotificationChannel(
                        'daily_summary',
                        '每日摘要通知渠道',
                      )),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('个人日程通知渠道'),
                  subtitle: Text(channelState(health?.manualChannel)),
                  onTap: () => _openNotificationChannel(
                        'personal_schedule',
                        '个人日程通知渠道',
                      )),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('提醒批次恢复状态'),
                  subtitle: Text(health?.scheduleRecoveryPending == true
                      ? '有未完成的调度事务，旧提醒已保留或正在清理；请重试恢复'
                      : '没有待恢复的调度事务')),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('精确提醒权限'),
                  subtitle: Text(state(health?.exact)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openPermissionSettings(
                        widget.permissionSettingsService
                            .openExactAlarmSettingsResult,
                        destination: '精确闹钟设置',
                      )),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('学习通通知使用权'),
                  subtitle: Text(
                    backgroundHealth?.notificationListenerEnabled == true
                        ? backgroundHealth?.notificationListenerGranted == true
                            ? '应用开关已开启，系统已授权'
                            : '应用开关已开启，但系统尚未授权'
                        : '应用中默认关闭',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openPermissionSettings(
                        widget.permissionSettingsService
                            .openNotificationListenerSettingsResult,
                        destination: '通知使用权设置',
                      )),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('电池优化'),
                  subtitle: const Text(
                    '打开系统优化列表，请找到“学习通课业手记”自行核对；应用无法保证长期后台运行',
                  ),
                  onTap: () => _openPermissionSettings(
                        widget.permissionSettingsService
                            .openBatterySettingsResult,
                        destination: '电池优化设置',
                      )),
              Text(
                  '原生作业截止事件：${backgroundHealth?.pendingDeadlineCount ?? health?.pending ?? '未知'} 条\n'
                  '待处理新增作业事件：${backgroundHealth?.pendingNewCount ?? '未知'} 条\n'
                  '已安排摘要：${health?.summaryPending ?? '未知'} 条\n'
                  '已安排个人提醒：${health?.manualPending ?? '未知'} 条\n'
                  '新增提醒基线：${backgroundHealth == null ? '当前平台不适用' : backgroundHealth!.baselineCompleted ? '已建立' : '待首次完整同步'}\n'
                  '下次后台检查：${backgroundHealth?.nextCheckAt == null ? widget.store.nextBackgroundCheckAt?.toLocal().toString().substring(0, 16) ?? '未安排' : backgroundHealth!.nextCheckAt!.toLocal().toString().substring(0, 16)}\n'
                  '最近完整同步：${widget.store.lastSyncAt?.toLocal().toString().substring(0, 16) ?? '尚无完整同步'}'),
              if (backgroundHealth?.migrationPending == true)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '提醒迁移或快照恢复尚未完成，系统已暂停不确定的作业自动投递。',
                  ),
                ),
              if (backgroundHealth?.lastFailure != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('最近后台失败：${backgroundHealth!.lastFailure}'),
                ),
              const SizedBox(height: 12),
              Wrap(spacing: 12, children: [
                OutlinedButton(
                    onPressed: busy ? null : refresh,
                    child: const Text('重新体检')),
                if (health?.scheduleRecoveryPending == true)
                  OutlinedButton(
                      onPressed: busy
                          ? null
                          : () async {
                              setState(() => busy = true);
                              try {
                                await widget.store.notificationService
                                    .recoverPendingSchedules();
                                if (mounted) {
                                  setState(() => message = '提醒恢复操作已完成，请核对安排数量');
                                }
                              } catch (error) {
                                if (mounted) {
                                  setState(() => message = '提醒恢复仍未完成：$error');
                                }
                              }
                              if (mounted) setState(() => busy = false);
                              if (!mounted) return;
                              await refresh();
                            },
                      child: const Text('重试提醒恢复')),
                FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            setState(() => busy = true);
                            final ok = await widget.store.notificationService
                                .showTestNotification();
                            if (!mounted) return;
                            setState(() {
                              busy = false;
                              message = ok
                                  ? '已请求系统显示测试通知。请拉下通知栏亲自核对是否收到。'
                                  : '未能请求测试通知，请先检查通知权限和渠道。';
                            });
                          },
                    child: const Text('发送测试通知'))
              ]),
              const Divider(height: 32),
              Text('每日摘要', style: Theme.of(context).textTheme.titleLarge),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: p.summaryEnabled,
                  onChanged: busy
                      ? null
                      : (v) => summary(v, p.summaryHour, p.summaryMinute),
                  title: const Text('每天一次课业摘要')),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      '北京时间 ${p.summaryHour.toString().padLeft(2, '0')}:${p.summaryMinute.toString().padLeft(2, '0')}'),
                  trailing: const Icon(Icons.schedule),
                  onTap: busy
                      ? null
                      : () async {
                          final t = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay(
                                  hour: p.summaryHour,
                                  minute: p.summaryMinute));
                          if (mounted && t != null) {
                            await summary(p.summaryEnabled, t.hour, t.minute);
                          }
                        }),
              const Text(
                  '摘要按当前快照预安排未来7天，包含当天截止与个人计划数量；进入应用、同步或修改设置后更新。超过7天未打开将停止摘要，不能在后台自动获取新作业。默认关闭，近似时间送达。'),
              if (busy)
                const Padding(
                    padding: EdgeInsets.all(12),
                    child: LinearProgressIndicator()),
              if (message != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Semantics(liveRegion: true, child: Text(message!))),
            ]));
      });

  Future<void> _openNotificationChannel(
    String channelId,
    String destination,
  ) =>
      _openPermissionSettings(
        () => widget.permissionSettingsService
            .openNotificationChannelSettingsResult(channelId),
        destination: destination,
      );

  Future<void> _openPermissionSettings(
    Future<SettingsOpenResult> Function() openSettings, {
    required String destination,
  }) async {
    final result = await openSettings();
    if (!mounted || result == SettingsOpenResult.direct) return;
    final text = switch (result) {
      SettingsOpenResult.direct => '',
      SettingsOpenResult.listFallback =>
        '未能直达$destination，已打开相关系统设置列表；请查找“学习通课业手记”',
      SettingsOpenResult.appDetailsFallback =>
        '未能直达$destination，已打开“学习通课业手记”的应用详情',
      SettingsOpenResult.unavailable =>
        '无法打开$destination，请手动在手机系统设置中搜索“学习通课业手记”',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

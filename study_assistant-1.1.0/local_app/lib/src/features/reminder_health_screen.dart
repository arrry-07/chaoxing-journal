import 'package:flutter/material.dart';
import '../services/assignment_store.dart';
import '../services/daily_summary.dart';
import '../services/permission_settings_service.dart';

class ReminderHealthScreen extends StatefulWidget {
  const ReminderHealthScreen({super.key, required this.store});
  final AssignmentStore store;
  @override
  State<ReminderHealthScreen> createState() => _HealthState();
}

class _HealthState extends State<ReminderHealthScreen>
    with WidgetsBindingObserver {
  ReminderHealth? health;
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
    if (busy) return;
    setState(() => busy = true);
    final value = await widget.store.notificationService.inspectHealth();
    if (mounted) {
      setState(() {
        health = value;
        busy = false;
      });
    }
  }

  String state(bool? v) => v == null
      ? '暂时无法读取'
      : v
          ? '已开启'
          : '未开启';
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
                  onTap: () => const PermissionSettingsService()
                      .openNotificationSettings()),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('截止提醒通知渠道'),
                  subtitle: Text(state(health?.channelEnabled)),
                  onTap: () => const PermissionSettingsService()
                      .openNotificationSettings()),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('精确提醒权限'),
                  subtitle: Text(state(health?.exact)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => const PermissionSettingsService()
                      .openExactAlarmSettings()),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('后台与省电设置'),
                  subtitle: const Text('此项需在系统中自行核对，应用无法保证长期后台运行'),
                  onTap: () =>
                      const PermissionSettingsService().openBatterySettings()),
              Text(
                  '已安排截止提醒：${health?.pending ?? '未知'} 条\n已安排摘要：${health?.summaryPending ?? '未知'} 条\n最近完整同步：${widget.store.lastSyncAt?.toLocal().toString().substring(0, 16) ?? '尚无完整同步'}'),
              const SizedBox(height: 12),
              Wrap(spacing: 12, children: [
                OutlinedButton(
                    onPressed: busy ? null : refresh,
                    child: const Text('重新体检')),
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
}

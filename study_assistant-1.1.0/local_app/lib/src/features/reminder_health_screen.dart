import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/journal.dart';
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
  String? healthError;
  String? backgroundError;
  DateTime? healthCheckedAt;
  DateTime? backgroundCheckedAt;
  bool backgroundUnsupported = false;
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
    _loadHealth(force: true);
  }

  @override
  void didUpdateWidget(covariant ReminderHealthScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store)) {
      oldWidget.store.removeListener(_handleStoreChanged);
      final id = _currentIdentity();
      _accountHash = id.$1;
      _accountEpoch = id.$2;
      _nativeEpoch = id.$3;
      _historyGeneration = id.$4;
      widget.store.addListener(_handleStoreChanged);
      _loadHealth(force: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(_handleStoreChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _loadHealth(force: true);
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
      health = null;
      backgroundHealth = null;
      message = null;
      healthError = null;
      backgroundError = null;
      healthCheckedAt = null;
      backgroundCheckedAt = null;
      backgroundUnsupported = false;
    });
    _loadHealth(force: true);
  }

  Future<void> refresh() => _loadHealth(force: false);

  Future<void> _loadHealth({required bool force}) async {
    if (!mounted || (busy && !force)) return;
    final token = ++_requestToken;
    final startIdentity = _currentIdentity();
    setState(() => busy = true);
    ReminderHealth? value;
    String? healthFailure;
    BackgroundReminderHealth? nativeValue;
    String? nativeFailure;
    try {
      value = await widget.store.notificationService.inspectHealth();
    } catch (_) {
      healthFailure = '系统通知与排期体检暂时无法读取，可重试';
    }
    try {
      nativeValue = await widget.store.inspectBackgroundReminderHealth();
    } catch (_) {
      nativeFailure = '原生后台提醒状态暂时无法读取，可重试';
    }
    if (!mounted ||
        token != _requestToken ||
        startIdentity != _currentIdentity()) {
      return;
    }
    final now = DateTime.now();
    setState(() {
      busy = false;
      healthError = healthFailure;
      if (healthFailure == null && value != null) {
        health = value;
        healthCheckedAt = now;
      }
      backgroundError = nativeFailure;
      if (nativeFailure == null) {
        // A null result means the bridge is not available on this platform;
        // it is not an inspection failure and must not keep stale native
        // counts as if they were current.
        backgroundHealth = nativeValue;
        backgroundUnsupported = nativeValue == null;
        backgroundCheckedAt = nativeValue == null ? null : now;
      }
    });
  }

  String get inspectionError => [
        if (healthError != null) healthError!,
        if (backgroundError != null) backgroundError!,
      ].join('；');

  bool get hasStaleResult =>
      (healthError != null && health != null) ||
      (backgroundError != null && backgroundHealth != null);

  static String _clock(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  String get lastResultLabel {
    final times = [
      if (healthError != null && health != null) healthCheckedAt,
      if (backgroundError != null && backgroundHealth != null)
        backgroundCheckedAt,
    ].whereType<DateTime>().toList()
      ..sort();
    final latest = times.isEmpty ? null : times.last;
    return latest == null
        ? '以下标注“上次结果”的数据来自上次成功读取，本次未更新。'
        : '以下标注“上次结果”的数据来自上次成功读取（${_clock(latest)}），本次未更新。';
  }

  String state(bool? v) => v == null
      ? (healthError != null ? '暂时无法读取，可重试' : '暂时无法读取')
      : v
          ? healthError != null
              ? '已开启（上次结果）'
              : '已开启'
          : healthError != null
              ? '未开启（上次结果）'
              : '未开启';

  String channelState(ReminderChannelHealth? value) {
    if (value == null) {
      return healthError != null ? '暂时无法读取，可重试' : '状态未知';
    }
    return healthError != null ? '${value.label}（上次结果）' : value.label;
  }

  String _nativeText(String Function(BackgroundReminderHealth) read) {
    final value = backgroundHealth;
    if (value == null) {
      if (backgroundUnsupported) return '当前平台不适用';
      return backgroundError != null ? '暂时无法读取，可重试' : '暂时无法读取';
    }
    final text = read(value);
    return backgroundError != null ? '$text（上次结果）' : text;
  }

  String get notificationListenerText =>
      _nativeText((value) => value.notificationListenerEnabled
          ? value.notificationListenerGranted
              ? '应用开关已开启，系统已授权'
              : '应用开关已开启，但系统尚未授权'
          : '应用中默认关闭');

  String get baselineText =>
      _nativeText((value) => value.baselineCompleted ? '已建立' : '待首次完整同步');

  String _localCount(int? value) {
    if (value == null) {
      return healthError != null ? '暂时无法读取，可重试' : '未知';
    }
    return healthError != null ? '$value 条（上次结果）' : '$value 条';
  }

  String get recoveryText {
    final value = health;
    if (value == null) {
      return healthError != null ? '暂时无法读取，可重试' : '状态未知';
    }
    final text = value.scheduleRecoveryPending
        ? '有未完成的调度事务，旧提醒已保留或正在清理；请重试恢复'
        : '没有待恢复的调度事务';
    return healthError != null ? '$text（上次结果）' : text;
  }

  bool get _showRecoveryOnTop =>
      health?.scheduleRecoveryPending == true || healthError != null;

  Widget _buildOverviewCard() {
    final current = health;
    final issues = <String>[];
    if (current?.notifications == false) {
      issues.add('系统通知权限未开启');
    }
    final channels = <(String, ReminderChannelHealth?)>[
      ('作业变化渠道', current?.assignmentUpdatesChannel),
      ('截止提醒渠道', current?.assignmentChannel),
      ('每日摘要渠道', current?.summaryChannel),
      ('个人日程渠道', current?.manualChannel),
    ];
    for (final (name, channel) in channels) {
      switch (channel?.status) {
        case ReminderChannelStatus.disabled:
          issues.add('$name已关闭');
        case ReminderChannelStatus.missing:
          issues.add('$name尚未创建');
        case ReminderChannelStatus.queryFailed:
          issues.add('$name读取失败');
        case ReminderChannelStatus.enabled:
        case ReminderChannelStatus.unsupported:
        case null:
          break;
      }
    }
    if (current?.scheduleRecoveryPending == true) {
      issues.add('存在待恢复的调度事务');
    }

    final hasPositiveSignal = current != null &&
        (current.notifications == true ||
            channels.any(
              (entry) => entry.$2?.status == ReminderChannelStatus.enabled,
            ));

    final String title;
    final String detail;
    final Color accent;
    final IconData icon;

    if (current == null && healthError == null) {
      title = busy ? '正在核对系统通知与渠道状态…' : '通知体检准备就绪';
      detail = '正在检查通知权限、四个通知渠道与精确闹钟设置。';
      accent = Journal.muted;
      icon = Icons.hourglass_top_outlined;
    } else if (issues.isNotEmpty) {
      title = '有 ${issues.length} 项提醒设置或事务需关注';
      detail = issues.join('、');
      accent = Journal.berry;
      icon = Icons.warning_amber_rounded;
    } else if (healthError != null) {
      title = '部分通知体检项尚未确认';
      detail = '请先查看下方错误信息，处理后点击“重新体检”。';
      accent = Journal.berry;
      icon = Icons.error_outline;
    } else if (hasPositiveSignal) {
      title = '基础通知权限与渠道已开启';
      detail = current.exact == false
          ? '精确闹钟未开启，提醒时间可能受系统省电策略顺延。'
          : '建议顺便发送测试通知，确认系统栏与锁屏横幅可见。';
      accent = Journal.ink;
      icon = Icons.verified_outlined;
    } else {
      title = '基础通知状态暂待系统确认';
      detail = '当前环境未返回明确权限或渠道状态，请先点击各项检查或发送测试通知。';
      accent = Journal.muted;
      icon = Icons.info_outline;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Journal.entryTitle.copyWith(color: accent),
                  ),
                  const SizedBox(height: 4),
                  Text(detail, style: Journal.metadata),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> summary(bool enabled, int hour, int minute) async {
    if (busy) return;
    setState(() => busy = true);
    final ok = await widget.store.savePersonal(
        (w) => w.withSummary(enabled, hour, minute), widget.store.accountEpoch);
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
            backgroundColor: Journal.paper,
            appBar: AppBar(
              backgroundColor: Journal.paper,
              title: const Text('提醒体检'),
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const JournalHeading(
                  '先确认提醒能到达',
                  eyebrow: 'CAMPUS JOURNAL   /   HEALTH',
                ),
                const SizedBox(height: 8),
                const Text(
                  '权限开启和已安排不等于一定送达。厂商省电、锁屏设置与应用被强制停止都可能影响提醒。',
                  style: Journal.metadata,
                ),
                const SizedBox(height: 6),
                const Text(
                  '先核对：系统通知权限 → 四个通知渠道 → 发送测试通知。',
                  style: Journal.metadata,
                ),
                const SizedBox(height: 10),
                _buildOverviewCard(),
                if (inspectionError.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      inspectionError,
                      style: Journal.metadata.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                if (hasStaleResult) ...[
                  const SizedBox(height: 4),
                  Text(lastResultLabel, style: Journal.metadata),
                ],
                if (_showRecoveryOnTop) ...[
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      dense: true,
                      title: const Text('提醒批次恢复状态'),
                      subtitle: Text(recoveryText),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        dense: true,
                        title: const Text('系统通知权限'),
                        subtitle: Text(state(health?.notifications)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openPermissionSettings(
                          widget.permissionSettingsService
                              .openNotificationSettingsResult,
                          destination: '通知设置',
                        ),
                      ),
                      const Divider(height: 1, color: Journal.rule),
                      ListTile(
                        dense: true,
                        title: const Text('作业变化通知渠道'),
                        subtitle: Text(
                            channelState(health?.assignmentUpdatesChannel)),
                        onTap: () => _openNotificationChannel(
                          'assignment_updates',
                          '作业变化通知渠道',
                        ),
                      ),
                      const Divider(height: 1, color: Journal.rule),
                      ListTile(
                        dense: true,
                        title: const Text('截止提醒通知渠道'),
                        subtitle: Text(channelState(health?.assignmentChannel)),
                        onTap: () => _openNotificationChannel(
                          'assignment_deadlines',
                          '截止提醒通知渠道',
                        ),
                      ),
                      const Divider(height: 1, color: Journal.rule),
                      ListTile(
                        dense: true,
                        title: const Text('每日摘要通知渠道'),
                        subtitle: Text(channelState(health?.summaryChannel)),
                        onTap: () => _openNotificationChannel(
                          'daily_summary',
                          '每日摘要通知渠道',
                        ),
                      ),
                      const Divider(height: 1, color: Journal.rule),
                      ListTile(
                        dense: true,
                        title: const Text('个人日程通知渠道'),
                        subtitle: Text(channelState(health?.manualChannel)),
                        onTap: () => _openNotificationChannel(
                          'personal_schedule',
                          '个人日程通知渠道',
                        ),
                      ),
                      const Divider(height: 1, color: Journal.rule),
                      ListTile(
                        dense: true,
                        title: const Text('精确提醒权限'),
                        subtitle: Text(state(health?.exact)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openPermissionSettings(
                          widget.permissionSettingsService
                              .openExactAlarmSettingsResult,
                          destination: '精确闹钟设置',
                        ),
                      ),
                      const Divider(height: 1, color: Journal.rule),
                      ListTile(
                        dense: true,
                        title: const Text('学习通通知使用权'),
                        subtitle: Text(notificationListenerText),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openPermissionSettings(
                          widget.permissionSettingsService
                              .openNotificationListenerSettingsResult,
                          destination: '通知使用权设置',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        dense: true,
                        title: const Text('提醒记录与原因'),
                        subtitle: const Text('查看最近安排、延后、提交、撤销和受阻记录'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/reminder-history'),
                      ),
                      const Divider(height: 1, color: Journal.rule),
                      ListTile(
                        dense: true,
                        title: const Text('每日摘要提醒状态'),
                        subtitle: const Text('查看摘要规则、系统渠道和最近排期证据'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/reminder-status/summary/0'),
                      ),
                      const Divider(height: 1, color: Journal.rule),
                      ListTile(
                        dense: true,
                        title: const Text('本应用电池与后台设置'),
                        subtitle: const Text(
                          '打开应用详情后，请进入电池或后台运行设置自行核对；应用无法保证长期后台运行',
                        ),
                        onTap: () => _openPermissionSettings(
                          widget.permissionSettingsService
                              .openBatterySettingsResult,
                          destination: '本应用电池与后台设置',
                          batterySettings: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Column(
                    children: [
                      const ExpansionTile(
                        tilePadding: EdgeInsets.symmetric(horizontal: 16),
                        title: Text('排查步骤'),
                        childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '1. 确认系统通知权限和四个通知渠道已开启。\n'
                              '2. 若使用学习通通知触发核对，授予通知使用权。\n'
                              '3. 需要准时提醒时开启精确闹钟，并核对电池与后台设置。\n'
                              '4. 仍不生效时，先点“发送测试通知”，再查看“提醒记录与原因”。',
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 1, color: Journal.rule),
                      ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        title: const Text('技术信息'),
                        subtitle: const Text('事件计数、调度事务、同步时间和最近后台失败'),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${!_showRecoveryOnTop ? '提醒批次恢复状态：$recoveryText\n' : ''}'
                              '原生作业截止事件：${_nativeText((value) => '${value.pendingDeadlineCount} 条')}\n'
                              '待处理新增作业事件：${_nativeText((value) => '${value.pendingNewCount} 条')}\n'
                              '已安排摘要：${_localCount(health?.summaryPending)}\n'
                              '已安排个人提醒：${_localCount(health?.manualPending)}\n'
                              '新增提醒基线：$baselineText\n'
                              '下次后台检查：${backgroundHealth?.nextCheckAt == null ? widget.store.nextBackgroundCheckAt?.toLocal().toString().substring(0, 16) ?? '未安排' : backgroundHealth!.nextCheckAt!.toLocal().toString().substring(0, 16)}${backgroundError != null && backgroundHealth?.nextCheckAt != null ? '（上次结果）' : ''}\n'
                              '最近完整同步：${widget.store.lastSyncAt?.toLocal().toString().substring(0, 16) ?? '尚无完整同步'}',
                            ),
                          ),
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
                              child: Text(
                                  '最近后台失败：${backgroundHealth!.lastFailure}'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: busy ? null : refresh,
                      child: const Text('重新体检'),
                    ),
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
                                    setState(
                                        () => message = '提醒恢复操作已完成，请核对安排数量');
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
                        child: const Text('重试提醒恢复'),
                      ),
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
                      child: const Text('发送测试通知'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('每日摘要', style: Journal.section),
                        const SizedBox(height: 4),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: p.summaryEnabled,
                          onChanged: busy
                              ? null
                              : (v) =>
                                  summary(v, p.summaryHour, p.summaryMinute),
                          title: const Text('每天一次课业摘要'),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '北京时间 ${p.summaryHour.toString().padLeft(2, '0')}:${p.summaryMinute.toString().padLeft(2, '0')}',
                          ),
                          trailing: const Icon(Icons.schedule),
                          onTap: busy
                              ? null
                              : () async {
                                  final t = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay(
                                      hour: p.summaryHour,
                                      minute: p.summaryMinute,
                                    ),
                                  );
                                  if (mounted && t != null) {
                                    await summary(
                                        p.summaryEnabled, t.hour, t.minute);
                                  }
                                },
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '摘要按当前快照预安排未来7天，包含当天截止与个人计划数量；进入应用、同步或修改设置后更新。超过7天未打开将停止摘要，不能在后台自动获取新作业。默认关闭，近似时间送达。',
                          style: Journal.metadata,
                        ),
                      ],
                    ),
                  ),
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: LinearProgressIndicator(),
                  ),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Semantics(liveRegion: true, child: Text(message!)),
                  ),
              ],
            ),
          );
        },
      );

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
    bool batterySettings = false,
  }) async {
    final result = await openSettings();
    if (!mounted || result == SettingsOpenResult.direct) return;
    final text = switch (result) {
      SettingsOpenResult.direct => '',
      SettingsOpenResult.listFallback =>
        '未能直达$destination，已打开相关系统设置列表；请查找“学习通课业手记”',
      SettingsOpenResult.appDetailsFallback => batterySettings
          ? '已打开“学习通课业手记”的应用详情，请进入电池或后台运行设置自行核对'
          : '未能直达$destination，已打开“学习通课业手记”的应用详情',
      SettingsOpenResult.unavailable =>
        '无法打开$destination，请手动在手机系统设置中搜索“学习通课业手记”',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../app/journal.dart';
import '../app/journal_motion.dart';
import '../app/transient_feedback.dart';
import '../models/reminder_rule_limits.dart';
import '../services/assignment_store.dart';
import '../services/background_reminder_gateway.dart';
import '../services/daily_summary.dart';
import '../services/local_notification_service.dart';
import '../services/permission_settings_service.dart';
import '../services/reminder_rule_store.dart';
import 'widgets/journal_buttons.dart';
import 'widgets/journal_expansion_tile.dart';
import 'widgets/journal_grouped_card.dart';

class ReminderSettingsScreen extends StatefulWidget {
  const ReminderSettingsScreen({
    super.key,
    required this.assignmentStore,
    this.permissionSettingsService = const PermissionSettingsService(),
    this.initialExpandHealth = false,
  });

  final AssignmentStore assignmentStore;
  final PermissionSettingsService permissionSettingsService;
  final bool initialExpandHealth;

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
  bool _savingRules = false;
  bool _healthBusy = false;
  bool _testingNotification = false;
  bool _testingManualNotification = false;
  bool _previewingChime = false;
  bool? _listenerGranted;

  ReminderHealth? _health;
  BackgroundReminderHealth? _backgroundHealth;
  String? _healthMessage;
  String? _healthError;
  String? _backgroundError;
  DateTime? _healthCheckedAt;
  DateTime? _backgroundCheckedAt;
  bool _backgroundUnsupported = false;
  int _requestToken = 0;

  String? _accountHash;
  int _accountEpoch = 0;
  int _nativeEpoch = 0;
  int _historyGeneration = 0;

  (String?, int, int, int) _currentIdentity() => (
        widget.assignmentStore.accountHash,
        widget.assignmentStore.accountEpoch,
        widget.assignmentStore.nativeSessionEpoch,
        widget.assignmentStore.reminderHistoryGeneration,
      );

  @override
  void initState() {
    super.initState();
    final id = _currentIdentity();
    _accountHash = id.$1;
    _accountEpoch = id.$2;
    _nativeEpoch = id.$3;
    _historyGeneration = id.$4;
    _offsets.addAll(widget.assignmentStore.reminderOffsetsMinutes);
    WidgetsBinding.instance.addObserver(this);
    widget.assignmentStore.addListener(_handleStoreChanged);
    unawaited(_refreshListenerGranted());
    unawaited(_loadHealth(force: true));
  }

  @override
  void didUpdateWidget(covariant ReminderSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.assignmentStore, widget.assignmentStore)) {
      oldWidget.assignmentStore.removeListener(_handleStoreChanged);
      final id = _currentIdentity();
      _accountHash = id.$1;
      _accountEpoch = id.$2;
      _nativeEpoch = id.$3;
      _historyGeneration = id.$4;
      _offsets
        ..clear()
        ..addAll(widget.assignmentStore.reminderOffsetsMinutes);
      widget.assignmentStore.addListener(_handleStoreChanged);
      unawaited(_refreshListenerGranted());
      unawaited(_loadHealth(force: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.assignmentStore.removeListener(_handleStoreChanged);
    _customHoursController.dispose();
    _customMinutesController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshListenerGranted());
      unawaited(_loadHealth(force: true));
    }
  }

  void _handleStoreChanged() {
    final next = _currentIdentity();
    final identityChanged =
        next != (_accountHash, _accountEpoch, _nativeEpoch, _historyGeneration);
    if (identityChanged) {
      _accountHash = next.$1;
      _accountEpoch = next.$2;
      _nativeEpoch = next.$3;
      _historyGeneration = next.$4;
      if (mounted) {
        setState(() {
          _health = null;
          _backgroundHealth = null;
          _healthMessage = null;
          _healthError = null;
          _backgroundError = null;
          _healthCheckedAt = null;
          _backgroundCheckedAt = null;
          _backgroundUnsupported = false;
          _offsets
            ..clear()
            ..addAll(widget.assignmentStore.reminderOffsetsMinutes);
        });
        unawaited(_loadHealth(force: true));
      }
      return;
    }

    if (!_savingRules &&
        !ReminderRuleStore.requiresReview(_offsets.toList()) &&
        mounted) {
      final stored = widget.assignmentStore.reminderOffsetsMinutes.toSet();
      if (_offsets.length != stored.length ||
          !_offsets.every(stored.contains)) {
        setState(() {
          _offsets
            ..clear()
            ..addAll(stored);
        });
      }
    }
  }

  Future<void> _refreshListenerGranted() async {
    final granted =
        await widget.permissionSettingsService.isNotificationListenerEnabled();
    if (mounted) setState(() => _listenerGranted = granted);
  }

  Future<void> _loadHealth({required bool force}) async {
    if (!mounted || (_healthBusy && !force)) return;
    final token = ++_requestToken;
    final startIdentity = _currentIdentity();
    setState(() => _healthBusy = true);
    ReminderHealth? value;
    String? healthFailure;
    BackgroundReminderHealth? nativeValue;
    String? nativeFailure;
    try {
      value = await widget.assignmentStore.notificationService.inspectHealth();
    } catch (_) {
      healthFailure = '系统通知与排期体检暂时无法读取，可重试';
    }
    try {
      nativeValue =
          await widget.assignmentStore.inspectBackgroundReminderHealth();
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
      _healthBusy = false;
      _healthError = healthFailure;
      if (healthFailure == null && value != null) {
        _health = value;
        _healthCheckedAt = now;
      }
      _backgroundError = nativeFailure;
      if (nativeFailure == null) {
        _backgroundHealth = nativeValue;
        _backgroundUnsupported = nativeValue == null;
        _backgroundCheckedAt = nativeValue == null ? null : now;
      }
    });
  }

  String get _inspectionError => [
        if (_healthError != null) _healthError!,
        if (_backgroundError != null) _backgroundError!,
      ].join('；');

  bool get _hasStaleResult =>
      (_healthError != null && _health != null) ||
      (_backgroundError != null && _backgroundHealth != null);

  static String _clock(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  String get _lastResultLabel {
    final times = [
      if (_healthError != null && _health != null) _healthCheckedAt,
      if (_backgroundError != null && _backgroundHealth != null)
        _backgroundCheckedAt,
    ].whereType<DateTime>().toList()
      ..sort();
    final latest = times.isEmpty ? null : times.last;
    return latest == null
        ? '以下标注“上次结果”的数据来自上次成功读取，本次未更新。'
        : '以下标注“上次结果”的数据来自上次成功读取（${_clock(latest)}），本次未更新。';
  }

  String _stateText(bool? v) => v == null
      ? (_healthError != null ? '暂时无法读取，可重试' : '暂时无法读取')
      : v
          ? _healthError != null
              ? '已开启（上次结果）'
              : '已开启'
          : _healthError != null
              ? '未开启（上次结果）'
              : '未开启';

  String _channelStateText(ReminderChannelHealth? value) {
    if (value == null) {
      return _healthError != null ? '暂时无法读取，可重试' : '状态未知';
    }
    return _healthError != null ? '${value.label}（上次结果）' : value.label;
  }

  String _nativeText(String Function(BackgroundReminderHealth) read) {
    final value = _backgroundHealth;
    if (value == null) {
      if (_backgroundUnsupported) return '当前平台不适用';
      return _backgroundError != null ? '暂时无法读取，可重试' : '暂时无法读取';
    }
    final text = read(value);
    return _backgroundError != null ? '$text（上次结果）' : text;
  }

  String get _notificationListenerText =>
      _nativeText((value) => value.notificationListenerEnabled
          ? value.notificationListenerGranted
              ? '应用开关已开启，系统已授权'
              : '应用开关已开启，但系统尚未授权'
          : '应用中默认关闭');

  String get _baselineText =>
      _nativeText((value) => value.baselineCompleted ? '已建立' : '待首次完整同步');

  String _localCount(int? value) {
    if (value == null) {
      return _healthError != null ? '暂时无法读取，可重试' : '未知';
    }
    return _healthError != null ? '$value 条（上次结果）' : '$value 条';
  }

  String get _recoveryText {
    final value = _health;
    if (value == null) {
      return _healthError != null ? '暂时无法读取，可重试' : '状态未知';
    }
    final text = value.scheduleRecoveryPending
        ? '有未完成的调度事务，旧提醒已保留或正在清理；请重试恢复'
        : '没有待恢复的调度事务';
    return _healthError != null ? '$text（上次结果）' : text;
  }

  String get _exactAlarmText {
    final base = _stateText(_health?.exact);
    if (_health?.exact == false) {
      return '$base · 未开启精确闹钟，提醒可能延迟';
    }
    return base;
  }

  String get _batterySettingsText {
    final ignoring = _health?.ignoringBatteryOptimizations;
    if (ignoring == true) {
      return '系统已忽略电池优化；打开应用详情后，请进入电池或后台运行设置自行核对';
    }
    if (ignoring == false) {
      return '受系统电池优化限制（可能延迟）；打开应用详情后，请进入电池或后台运行设置自行核对';
    }
    return '打开应用详情后，请进入电池或后台运行设置自行核对';
  }

  String get _deadlineChannelSummaryText {
    if (widget.assignmentStore.isUsingV3DeadlineChannel) {
      return 'v3（${LocalNotificationService.assignmentV3Channel}）';
    }
    if (widget.assignmentStore.isUsingV2DeadlineChannel) {
      return 'v2（${LocalNotificationService.assignmentV2Channel}）';
    }
    return 'v1（${LocalNotificationService.assignmentChannel}）';
  }

  String get _lockscreenPrivacyText {
    final show = _health?.lockscreenShowNotifications;
    final allowPrivate = _health?.lockscreenAllowPrivateNotifications;
    final channelVis = _health?.assignmentChannel?.lockscreenVisibility;
    if (show == null && allowPrivate == null && channelVis == null) {
      return '未读到系统锁屏策略（以系统设置为准）';
    }
    if (show == false) {
      return '系统锁屏已关闭通知显示';
    }
    if (channelVis == -1) {
      return '当前截止渠道在锁屏已设为不显示';
    }
    if (allowPrivate == false || channelVis == 0) {
      return '系统锁屏仅显示脱敏摘要';
    }
    return '系统锁屏允许显示通知（按应用隐私设置输出）';
  }

  Future<void> _enableV3DeadlineChannel() async {
    if (_saving || _healthBusy) return;
    setState(() => _saving = true);
    try {
      final saved = await widget.assignmentStore.saveDeadlineChannelId(
        LocalNotificationService.assignmentV3Channel,
      );
      if (!mounted) return;
      if (saved) {
        final warnings = widget.assignmentStore.serviceWarnings;
        setState(() {
          _healthMessage = warnings.isNotEmpty
              ? '已启用新版有声截止渠道（v3），但提醒仍需处理：${warnings.first}'
              : '已启用新版有声截止渠道（v3），未完成课业提醒已重新安排。';
        });
        await _loadHealth(force: true);
      } else {
        setState(() {
          _healthMessage =
              widget.assignmentStore.operationError ?? '启用新版有声渠道失败，请重试';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _previewChime() async {
    if (_previewingChime || _healthBusy) return;
    setState(() => _previewingChime = true);
    try {
      final result = await widget.assignmentStore.notificationService
          .previewNotificationChime();
      if (!mounted) return;
      setState(() {
        if (!result.supported) {
          _healthMessage = '当前环境不支持直接试听清铃（请使用“发送测试有声提醒”确认）。';
        } else if (result.isPhoneMutedOrVibrate) {
          _healthMessage = '当前手机处于静音或振动模式，无法听到试听铃声；请切换为响铃模式后再试。';
        } else if (result.isNotificationVolumeZero) {
          final volText = result.notificationStreamMaxVolume != null &&
                  result.notificationStreamVolume != null
              ? '（${result.notificationStreamVolume}/${result.notificationStreamMaxVolume}）'
              : '';
          _healthMessage = '当前系统通知音量为 0 或已静音$volText，无法听到试听铃声；请按音量键调高通知音量后再试。';
        } else if (result.played) {
          _healthMessage = '已播放内置清铃提示音（如未听到，请调高系统通知音量）。';
        } else {
          _healthMessage = '试听清铃未能播放，请检查系统通知音量后重试。';
        }
      });
      await _loadHealth(force: true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _healthMessage = '试听清铃未能播放，请检查系统通知音量后重试。';
      });
    } finally {
      if (mounted) {
        setState(() => _previewingChime = false);
      }
    }
  }

  Future<void> _updateSummary(bool enabled, int hour, int minute) async {
    if (_saving || _healthBusy) return;
    setState(() => _healthBusy = true);
    final ok = await widget.assignmentStore.savePersonal(
        (w) => w.withSummary(enabled, hour, minute),
        widget.assignmentStore.accountEpoch);
    if (!mounted) return;
    setState(() {
      _healthBusy = false;
      _healthMessage = ok
          ? widget.assignmentStore.error == null
              ? '每日摘要设置已保存'
              : '设置已保存，但提醒仍需处理：${widget.assignmentStore.error}'
          : '保存失败，请重试';
    });
    await _loadHealth(force: true);
  }

  Widget _buildHealthSummaryCard(JournalPalette journal) {
    final current = _health;
    final showNotificationVolumeWarning =
        current?.isNotificationVolumeZero == true &&
            current?.isPhoneMutedOrVibrate != true;
    final issues = <String>[];
    if (current?.notifications == false) {
      issues.add('系统通知权限未开启');
    }
    final channels = <(String, ReminderChannelHealth?)>[
      ('新增作业渠道', current?.assignmentUpdatesChannel),
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
    void checkChannelAudioAndVibration(
      ReminderChannelHealth? channel,
      String name,
    ) {
      if (channel?.status != ReminderChannelStatus.enabled) return;
      if (channel?.soundMuted == true) {
        issues.add('$name在系统中已静音');
      }
      if (channel?.vibrationEnabled == false) {
        issues.add('$name振动已关闭');
      }
    }

    checkChannelAudioAndVibration(current?.assignmentUpdatesChannel, '新增作业渠道');
    checkChannelAudioAndVibration(current?.assignmentChannel, '截止提醒渠道');
    checkChannelAudioAndVibration(current?.summaryChannel, '每日摘要渠道');
    checkChannelAudioAndVibration(current?.manualChannel, '个人日程渠道');
    if (showNotificationVolumeWarning) {
      issues.add('系统通知音量为 0 或已静音');
    }
    if (current?.scheduleRecoveryPending == true) {
      issues.add('存在待恢复的调度事务');
    }
    if (current?.queryErrors.isNotEmpty == true ||
        _backgroundHealth?.queryErrors.isNotEmpty == true) {
      issues.add('部分系统状态读取失败，请下拉重试或检查系统权限');
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

    if (current == null && _healthError == null) {
      title = _healthBusy ? '正在核对系统通知与渠道状态…' : '通知体检准备就绪';
      detail = '自动检查通知权限、通知渠道与精确闹钟状态。';
      accent = journal.muted;
      icon = Icons.hourglass_top_outlined;
    } else if (issues.isNotEmpty) {
      title = '有 ${issues.length} 项提醒状态需关注';
      detail = issues.join('、');
      accent = journal.berry;
      icon = Icons.warning_amber_rounded;
    } else if (_healthError != null) {
      title = '部分通知体检项尚未确认';
      detail = '可点击“重新体检”再次核对。';
      accent = journal.berry;
      icon = Icons.error_outline_rounded;
    } else if (hasPositiveSignal) {
      title = '基础通知权限与渠道已开启';
      detail = current.exact == false
          ? '精确闹钟未开启，提醒可能受系统省电策略顺延。'
          : '建议发一条测试通知，确认锁屏与横幅正常显示。';
      accent = journal.ink;
      icon = Icons.verified_outlined;
    } else {
      title = '基础通知状态暂待系统确认';
      detail = '当前环境未返回明确状态，可发送测试通知确认。';
      accent = journal.muted;
      icon = Icons.info_outline_rounded;
    }

    return JournalGroupedCard(
      title: '提醒状态与体检',
      infoTitle: '提醒边界说明',
      infoItems: const [
        '权限开启与已安排不等于绝对准时送达：厂商省电策略、锁屏限制或应用被强制停止都可能拦截后台提醒。',
        '每日摘要按当前快照预安排未来 7 天，超过 7 天未打开应用将停止摘要，且不会在后台自动拉取新作业。',
        '全套通知渠道已升级至内置清铃有声 v3（截止提醒、新增作业、每日摘要与待办提醒）；如曾调整系统铃声或静音规则，可点击下方渠道条目核对。',
        '若某条课业提醒异常，可在下方查看「提醒记录与原因」。',
      ],
      dividerIndent: 16,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
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
                          style: journal.entryTitle.copyWith(color: accent),
                        ),
                        const SizedBox(height: 3),
                        Text(detail, style: journal.metadata),
                      ],
                    ),
                  ),
                ],
              ),
              if (_inspectionError.isNotEmpty) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _inspectionError,
                    style: journal.metadata.copyWith(color: journal.berry),
                  ),
                ),
              ],
              if (_hasStaleResult) ...[
                const SizedBox(height: 4),
                Text(_lastResultLabel, style: journal.metadata),
              ],
              if (current?.scheduleRecoveryPending == true) ...[
                const SizedBox(height: 8),
                Text(
                  '提醒批次恢复状态：$_recoveryText',
                  style: journal.metadata.copyWith(color: journal.berry),
                ),
              ],
              if (_healthMessage != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _healthMessage!,
                    style: journal.metadata.copyWith(color: journal.ink),
                  ),
                ),
              ],
              if (current?.isPhoneMutedOrVibrate == true) ...[
                const SizedBox(height: 8),
                Container(
                  key: const ValueKey('reminder-health-ringer-warning'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: journal.ochreBg.withValues(
                      alpha: journal.isDark ? 0.65 : 0.72,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: journal.ochreBorder, width: 0.7),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.volume_off_outlined,
                          size: 16,
                          color: journal.ochre,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '当前手机处于静音或振动模式，系统不会播放提醒铃声。',
                          style:
                              journal.metadata.copyWith(color: journal.ochre),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (showNotificationVolumeWarning) ...[
                const SizedBox(height: 8),
                Container(
                  key: const ValueKey(
                    'reminder-health-notification-volume-warning',
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: journal.ochreBg.withValues(
                      alpha: journal.isDark ? 0.65 : 0.72,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: journal.ochreBorder, width: 0.7),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.notifications_off_outlined,
                          size: 16,
                          color: journal.ochre,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          current?.notificationStreamMaxVolume != null &&
                                  current?.notificationStreamVolume != null
                              ? '当前系统通知音量为 ${current!.notificationStreamVolume}/${current.notificationStreamMaxVolume}'
                                  '${current.notificationStreamMuted == true ? '（已静音）' : ''}，即使处于响铃模式也不会播放提醒铃声；请按音量键调高通知音量。'
                              : '当前系统通知音量为 0 或已静音，即使处于响铃模式也不会播放提醒铃声；请按音量键调高通知音量。',
                          style:
                              journal.metadata.copyWith(color: journal.ochre),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (current?.isDndActive == true) ...[
                const SizedBox(height: 8),
                Container(
                  key: const ValueKey('reminder-health-dnd-warning'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: journal.ochreBg.withValues(
                      alpha: journal.isDark ? 0.65 : 0.72,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: journal.ochreBorder, width: 0.7),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.do_not_disturb_on_outlined,
                          size: 16,
                          color: journal.ochre,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '当前已开启系统勿扰模式，可能拦截提醒声音或弹窗。',
                          style:
                              journal.metadata.copyWith(color: journal.ochre),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  JournalPrimaryButton(
                    key: const ValueKey('send-test-notification-button'),
                    expanded: false,
                    height: 42,
                    label: '发送测试有声提醒',
                    loading: _testingNotification,
                    onPressed: _healthBusy || _testingNotification
                        ? null
                        : () async {
                            setState(() => _testingNotification = true);
                            try {
                              final outcome = await widget.assignmentStore
                                  .sendTestDeadlineNotification();
                              if (!mounted) return;
                              setState(() {
                                _healthMessage = switch (outcome.status) {
                                  TestDeadlineNotificationStatus.scheduled =>
                                    '已安排测试有声提醒（约 3 秒后送达）；点击后建议 3 秒内切回桌面或锁屏观察响铃、振动与横幅（部分国产系统前台会抑制提醒音与横幅）。',
                                  TestDeadlineNotificationStatus.posted =>
                                    '已请求系统显示测试有声提醒；点击后建议 3 秒内切回桌面或锁屏观察响铃、振动与横幅（部分国产系统前台会抑制提醒音与横幅）。',
                                  TestDeadlineNotificationStatus.quietHours =>
                                    outcome.warning ??
                                        '当前处于夜间静音时段（23:30–07:30），测试提醒不会穿透静音；请在 07:30 后重试。',
                                  TestDeadlineNotificationStatus.blocked =>
                                    outcome.warning ?? '未能请求测试通知，请检查通知权限与渠道。',
                                };
                              });
                            } finally {
                              if (mounted) {
                                setState(() => _testingNotification = false);
                              }
                            }
                          },
                  ),
                  if (!widget.assignmentStore.isUsingV3DeadlineChannel)
                    JournalSecondaryButton(
                      key: const ValueKey('enable-v3-deadline-channel'),
                      expanded: false,
                      height: 42,
                      label: '启用新版有声截止渠道（v3）',
                      onPressed: _saving || _healthBusy
                          ? null
                          : _enableV3DeadlineChannel,
                    ),
                  JournalSecondaryButton(
                    buttonKey:
                        const ValueKey('preview-notification-chime-button'),
                    expanded: false,
                    height: 42,
                    icon: Icons.music_note_outlined,
                    label: _previewingChime ? '试听中…' : '试听清铃',
                    onPressed:
                        _healthBusy || _previewingChime ? null : _previewChime,
                  ),
                  JournalSecondaryButton(
                    expanded: false,
                    height: 42,
                    label: '重新体检',
                    onPressed:
                        _healthBusy ? null : () => _loadHealth(force: false),
                  ),
                  JournalSecondaryButton(
                    buttonKey:
                        const ValueKey('send-test-manual-notification-button'),
                    expanded: false,
                    height: 42,
                    label: _testingManualNotification ? '正在发送…' : '测试待办提醒',
                    onPressed: _healthBusy || _testingManualNotification
                        ? null
                        : () async {
                            setState(() => _testingManualNotification = true);
                            try {
                              final ok = await widget
                                  .assignmentStore.notificationService
                                  .showTestManualNotification(
                                delay: const Duration(seconds: 3),
                              );
                              if (!mounted) return;
                              setState(() {
                                _healthMessage = ok
                                    ? '已安排待办测试提醒（约 3 秒后送达）；点击后建议 3 秒内切回桌面或锁屏观察响铃、振动与横幅（部分国产系统前台会抑制提醒音与横幅）。'
                                    : '未能发送待办测试提醒，请检查通知权限与待办提醒渠道。';
                              });
                              await _loadHealth(force: true);
                            } catch (_) {
                              if (!mounted) return;
                              setState(() {
                                _healthMessage = '未能发送待办测试提醒，请检查通知权限与待办提醒渠道。';
                              });
                            } finally {
                              if (mounted) {
                                setState(
                                    () => _testingManualNotification = false);
                              }
                            }
                          },
                  ),
                  JournalSecondaryButton(
                    buttonKey:
                        const ValueKey('open-system-notification-settings'),
                    expanded: false,
                    height: 42,
                    label: '打开系统通知设置',
                    onPressed: () => _openPermissionSettings(
                      widget.permissionSettingsService
                          .openNotificationSettingsResult,
                      destination: '系统通知设置',
                    ),
                  ),
                  if (current?.scheduleRecoveryPending == true)
                    JournalSecondaryButton(
                      expanded: false,
                      height: 42,
                      label: '重试提醒恢复',
                      onPressed: _healthBusy
                          ? null
                          : () async {
                              setState(() => _healthBusy = true);
                              try {
                                await widget.assignmentStore.notificationService
                                    .recoverPendingSchedules();
                                if (mounted) {
                                  setState(
                                      () => _healthMessage = '提醒恢复已执行，请核对状态');
                                }
                              } catch (error) {
                                if (mounted) {
                                  setState(
                                      () => _healthMessage = '提醒恢复仍未完成：$error');
                                }
                              }
                              if (mounted) setState(() => _healthBusy = false);
                              if (mounted) await _loadHealth(force: true);
                            },
                    ),
                ],
              ),
            ],
          ),
        ),
        JournalGroupTile(
          icon: Icons.history_rounded,
          title: '提醒记录与原因',
          subtitle: '查看最近安排、延后、撤销和受阻记录',
          onTap: () => context.push('/reminder-history'),
        ),
        JournalExpansionTile(
          initiallyExpanded: widget.initialExpandHealth,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text('权限、通知渠道与技术详情', style: journal.entryTitle),
          subtitle: Text('点击核对系统权限、四条通知渠道与后台计数', style: journal.metadata),
          children: [
            Divider(
                height: 0.6,
                thickness: 0.6,
                indent: 16,
                endIndent: 16,
                color: journal.divider),
            ListTile(
              dense: true,
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('通知权限'),
              subtitle: Text(_stateText(_health?.notifications)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _requestNotificationPermission,
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.lock_clock_outlined),
              title: const Text('截止提醒通知渠道'),
              subtitle: Text(_channelStateText(_health?.assignmentChannel)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _openNotificationChannel(
                widget.assignmentStore.activeDeadlineChannelId,
                '截止提醒通知渠道',
              ),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.sync_outlined),
              title: const Text('新增作业通知渠道'),
              subtitle:
                  Text(_channelStateText(_health?.assignmentUpdatesChannel)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _openNotificationChannel(
                LocalNotificationService.assignmentUpdatesV3Channel,
                '新增作业通知渠道',
              ),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.summarize_outlined),
              title: const Text('每日摘要通知渠道'),
              subtitle: Text(_channelStateText(_health?.summaryChannel)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _openNotificationChannel(
                LocalNotificationService.summaryV3Channel,
                '每日摘要通知渠道',
              ),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.event_note_outlined),
              title: const Text('个人日程通知渠道'),
              subtitle: Text(_channelStateText(_health?.manualChannel)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _openNotificationChannel(
                LocalNotificationService.manualV3Channel,
                '个人日程通知渠道',
              ),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.alarm_on_outlined),
              title: const Text('精确闹钟'),
              subtitle: Text(_exactAlarmText),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _openPermissionSettings(
                widget.permissionSettingsService.openExactAlarmSettingsResult,
                destination: '精确闹钟设置',
              ),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.notifications_paused_outlined),
              title: const Text('学习通通知使用权'),
              subtitle: Text(_notificationListenerText),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                await _openPermissionSettings(
                  widget.permissionSettingsService
                      .openNotificationListenerSettingsResult,
                  destination: '通知使用权设置',
                );
                await _refreshListenerGranted();
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.battery_saver_outlined),
              title: const Text('本应用电池与后台设置'),
              subtitle: Text(_batterySettingsText),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _openPermissionSettings(
                widget.permissionSettingsService.openBatterySettingsResult,
                destination: '本应用电池与后台设置',
                batterySettings: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '技术状态 · 调度事务：$_recoveryText\n'
                    '截止渠道：$_deadlineChannelSummaryText · 静默新作业渠道：${_channelStateText(_health?.silentChannel)}\n'
                    '系统通知音量：${_health?.notificationStreamVolume == null ? '未知' : '${_health!.notificationStreamVolume}/${_health?.notificationStreamMaxVolume ?? '?'}'}${_health?.notificationStreamMuted == true ? '（已静音）' : ''} · 锁屏隐私策略：$_lockscreenPrivacyText\n'
                    '原生作业截止事件：${_nativeText((v) => '${v.pendingDeadlineCount} 条')} · 待处理新增作业事件：${_nativeText((v) => '${v.pendingNewCount} 条')}\n'
                    '已安排摘要：${_localCount(_health?.summaryPending)} · 个人提醒：${_localCount(_health?.manualPending)} · 新增基线：$_baselineText\n'
                    '下次后台检查：${_backgroundHealth?.nextCheckAt == null ? widget.assignmentStore.nextBackgroundCheckAt?.toLocal().toString().substring(0, 16) ?? '未安排' : _backgroundHealth!.nextCheckAt!.toLocal().toString().substring(0, 16)}'
                    '${_backgroundError != null && _backgroundHealth?.nextCheckAt != null ? '（上次结果）' : ''}\n'
                    '最近完整同步：${widget.assignmentStore.lastSyncAt?.toLocal().toString().substring(0, 16) ?? '尚无完整同步'}',
                    style: journal.metadata.copyWith(fontSize: 12),
                  ),
                  if (_backgroundHealth?.migrationPending == true) ...[
                    const SizedBox(height: 6),
                    Text(
                      '提醒迁移或快照恢复尚未完成，系统已暂停不确定的作业自动投递。',
                      style: journal.metadata.copyWith(color: journal.berry),
                    ),
                  ],
                  if (_backgroundHealth?.lastFailure != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '最近后台失败：${_backgroundHealth!.lastFailure}',
                      style: journal.metadata.copyWith(color: journal.berry),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.assignmentStore,
      builder: (context, _) {
        final journal = Journal.of(context);
        final p = widget.assignmentStore.personal;
        final customOffsets = _offsets
            .where((item) => !_presetOffsets.containsKey(item))
            .toList()
          ..sort((a, b) => b.compareTo(a));
        final needsReview = ReminderRuleStore.requiresReview(_offsets.toList());
        final activePreset = ReminderRuleStore.matchPreset(_offsets);

        return Scaffold(
          backgroundColor: journal.paper,
          appBar: AppBar(
            backgroundColor: journal.paper,
            leading: IconButton(
              tooltip: '返回我的',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/profile'),
            ),
            title: const Text('提醒与通知'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _buildHealthSummaryCard(journal),
              const SizedBox(height: 14),
              if (needsReview) ...[
                JournalGroupedCard(
                  backgroundColor: journal.berryBg,
                  padding: const EdgeInsets.all(14),
                  children: [
                    Text(
                      '旧版提醒规则已保留（超过 32 条或 365 天不会参与调度）。请删除超限规则，删至合规后将自动保存生效。',
                      style: journal.metadata.copyWith(color: journal.berry),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              JournalGroupedCard(
                title: '提前提醒时间',
                infoTitle: '提前提醒规则说明',
                infoItems: const [
                  '勾选或增减提醒时间后立即保存生效，并重新安排所有未完成课业的本机通知。',
                  '自定义提醒支持精确到分钟，最长提前 365 天，最多保留 32 条规则（至少保留 1 条）。',
                ],
                dividerIndent: 16,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                activePreset == null
                                    ? '当前：自定义（${_offsets.length} 条）'
                                    : '当前：${activePreset.label}',
                                key: const ValueKey(
                                  'reminder-preset-mode-label',
                                ),
                                style: journal.entryTitle,
                              ),
                            ),
                            if (activePreset !=
                                ReminderFrequencyPreset.recommended)
                              TextButton(
                                key: const ValueKey('reminder-preset-reset'),
                                onPressed: _saving
                                    ? null
                                    : () => _applyPreset(
                                          ReminderFrequencyPreset.recommended,
                                        ),
                                child: const Text('恢复默认'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final preset in ReminderFrequencyPreset.values)
                              ChoiceChip(
                                key: ValueKey('reminder-preset-${preset.name}'),
                                label: Text(preset.label),
                                selected: activePreset == preset,
                                onSelected: _saving
                                    ? null
                                    : (selected) {
                                        if (selected &&
                                            activePreset != preset) {
                                          _applyPreset(preset);
                                        }
                                      },
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          activePreset?.description ?? '已按你的选择自由增减；点击上方档位可一键切换',
                          style: journal.metadata,
                        ),
                      ],
                    ),
                  ),
                  for (final item in _presetOffsets.entries)
                    CheckboxListTile(
                      value: _offsets.contains(item.key),
                      onChanged: _saving
                          ? null
                          : (checked) => _toggleOffset(item.key, checked),
                      title: Text(item.value, style: journal.entryTitle),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        InputDecoration buildTimeInputDecoration(
                          String hint,
                          IconData icon,
                        ) =>
                            InputDecoration(
                              hintText: hint,
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.fromLTRB(4, 11, 8, 11),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 36,
                              ),
                              prefixIcon: Padding(
                                padding:
                                    const EdgeInsets.only(left: 10, right: 4),
                                child: Icon(
                                  icon,
                                  size: 17,
                                  color: journal.muted,
                                ),
                              ),
                            );

                        final hoursField = TextField(
                          controller: _customHoursController,
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          decoration: buildTimeInputDecoration(
                            '小时',
                            Icons.schedule_rounded,
                          ),
                        );
                        final minutesField = TextField(
                          controller: _customMinutesController,
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          decoration: buildTimeInputDecoration(
                            '分钟',
                            Icons.timer_outlined,
                          ),
                        );

                        final stacked = constraints.maxWidth < 276 ||
                            JournalLayout.isLargeText(context);
                        if (stacked) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: hoursField),
                                  const SizedBox(width: 8),
                                  Expanded(child: minutesField),
                                ],
                              ),
                              const SizedBox(height: 8),
                              JournalPrimaryButton(
                                expanded: true,
                                height: 44,
                                label: '添加',
                                onPressed: _saving ? null : _addCustomOffset,
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: hoursField),
                            const SizedBox(width: 8),
                            Expanded(child: minutesField),
                            const SizedBox(width: 8),
                            JournalPrimaryButton(
                              expanded: false,
                              height: 44,
                              label: '添加',
                              onPressed: _saving ? null : _addCustomOffset,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  for (final offset in customOffsets)
                    ListTile(
                      leading: const Icon(
                        Icons.notifications_active_outlined,
                        size: 20,
                      ),
                      title: Text(_labelFor(offset), style: journal.entryTitle),
                      trailing: IconButton(
                        onPressed: _saving ? null : () => _removeOffset(offset),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '删除',
                      ),
                    ),
                  SwitchListTile(
                    key: const ValueKey('night-breakthrough-switch'),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    title: Text('允许 ≤1 小时死线穿透夜间静音', style: journal.entryTitle),
                    subtitle: Text(
                      '默认 23:30 至次日 07:30 静音并提前于 22:30 提醒；开启后仅距截止 ≤1 小时可穿透（仍受系统音量与勿扰限制）',
                      style: journal.metadata,
                    ),
                    value: widget
                        .assignmentStore.allowUrgentDeadlineNightBreakthrough,
                    onChanged: _saving ? null : _saveNightBreakthrough,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              JournalGroupedCard(
                title: '后台检查与每日摘要',
                dividerIndent: 16,
                children: [
                  if (widget.assignmentStore.notificationPrivacyPending)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '旧详细提醒尚未清理，隐私设置未完全生效。',
                              style: journal.metadata
                                  .copyWith(color: journal.berry),
                            ),
                          ),
                          TextButton(
                            onPressed:
                                _saving ? null : () => _savePrivacy(false),
                            child: const Text('重试清理'),
                          ),
                        ],
                      ),
                    ),
                  SwitchListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    title: Text('通知显示详细内容', style: journal.entryTitle),
                    subtitle: Text(
                      '开启后可能在锁屏显示课程与作业名称（系统锁屏设置仍会限制）',
                      style: journal.metadata,
                    ),
                    value: widget.assignmentStore.notificationDetails,
                    onChanged: _saving ? null : _savePrivacy,
                  ),
                  SwitchListTile(
                    key: const ValueKey('background-check-switch'),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    title: Text('白天后台检查', style: journal.entryTitle),
                    subtitle: Text(
                      '08:00 至次日 00:00 低频检查；不承诺整点准时执行',
                      style: journal.metadata,
                    ),
                    value: widget.assignmentStore.backgroundCheckEnabled,
                    onChanged: _saving ? null : _saveBackgroundCheckEnabled,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
                            key: ValueKey('background-interval-${option.key}'),
                            label: Text(option.value),
                            selected: widget.assignmentStore
                                    .backgroundCheckIntervalMinutes ==
                                option.key,
                            onSelected: _saving ||
                                    !widget
                                        .assignmentStore.backgroundCheckEnabled
                                ? null
                                : (_) => _saveBackgroundInterval(option.key),
                          ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    key: const ValueKey('notification-listener-switch'),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    title: Text('学习通通知触发核对', style: journal.entryTitle),
                    subtitle: Text(
                      _listenerGranted == true
                          ? '已授权；只处理学习通通知信号，正文不落盘'
                          : '需单独授予系统通知使用权；默认关闭',
                      style: journal.metadata,
                    ),
                    value: widget.assignmentStore.notificationListenerEnabled,
                    onChanged: _saving ? null : _saveNotificationListener,
                  ),
                  SwitchListTile(
                    key: const ValueKey('new-assignment-switch'),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    title: Text('新增正式作业提醒', style: journal.entryTitle),
                    subtitle: Text(
                      '首次完整同步建立基线；单次检查发现多条时合并提醒',
                      style: journal.metadata,
                    ),
                    value: widget.assignmentStore.newAssignmentReminderEnabled,
                    onChanged: _saving ? null : _saveNewAssignmentReminder,
                  ),
                  SwitchListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    title: Text('每天一次课业摘要', style: journal.entryTitle),
                    subtitle: Text(
                      '按当前快照预排未来 7 天（不会在后台自动拉取新作业）',
                      style: journal.metadata,
                    ),
                    value: p.summaryEnabled,
                    onChanged: _healthBusy || _saving
                        ? null
                        : (v) =>
                            _updateSummary(v, p.summaryHour, p.summaryMinute),
                  ),
                  JournalGroupTile(
                    icon: Icons.schedule_rounded,
                    title: '每日摘要发送时间',
                    trailingText:
                        '北京时间 ${p.summaryHour.toString().padLeft(2, '0')}:${p.summaryMinute.toString().padLeft(2, '0')}',
                    onTap: _healthBusy || _saving
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
                              await _updateSummary(
                                  p.summaryEnabled, t.hour, t.minute);
                            }
                          },
                  ),
                  JournalGroupTile(
                    icon: Icons.fact_check_outlined,
                    title: '每日摘要提醒状态',
                    subtitle: '查看摘要规则、系统渠道与最近排期证据',
                    onTap: () => context.push('/reminder-status/summary/0'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _applyOffsetMutation(Set<int> next) async {
    // Safeguard 1: ReminderRuleStore.normalizeOffsets([]) resets to default
    // [1440, 720, 360, 180, 60, 30]; block removing the final offset here.
    if (next.isEmpty) {
      _showMessage('至少保留 1 个提前提醒时间');
      return;
    }

    // Safeguard 2: Legacy out-of-range rules (>32 or >365d) must be trimmed
    // in local state before invoking saveReminderRule.
    if (ReminderRuleStore.requiresReview(next.toList())) {
      setState(() {
        _offsets
          ..clear()
          ..addAll(next);
      });
      _showMessage('请继续删除超出 32 条或 365 天的旧规则，删至合规后将自动保存');
      return;
    }

    // Safeguard 3: Serialize rule saves and roll back on failure.
    final previous = Set<int>.of(_offsets);
    final snapshot = next.toList();
    setState(() {
      _offsets
        ..clear()
        ..addAll(next);
      _saving = true;
      _savingRules = true;
    });
    JournalMotion.tap(widget.assignmentStore.display);

    try {
      final saved = await widget.assignmentStore.saveReminderRule(snapshot);
      if (!mounted) return;
      if (!saved) {
        setState(() {
          _offsets
            ..clear()
            ..addAll(previous);
        });
        final operationError = widget.assignmentStore.operationError;
        _showMessage(operationError == null
            ? '保存失败，已恢复原提醒时间'
            : '保存失败：$operationError；已恢复原提醒时间');
        return;
      }
      if (widget.assignmentStore.serviceWarnings.isNotEmpty) {
        _showMessage(
          '提醒时间已保存；提醒安排失败：${widget.assignmentStore.serviceWarnings.first}',
        );
      } else if (widget.assignmentStore.recoveryWarning != null) {
        _showMessage('提醒时间已保存；提醒恢复仍需检查');
      } else {
        _showMessage('提醒时间已保存，作业通知已更新');
      }
      unawaited(_loadHealth(force: true));
    } catch (_) {
      if (mounted) {
        setState(() {
          _offsets
            ..clear()
            ..addAll(previous);
        });
        _showMessage('保存失败，已恢复原提醒时间');
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _savingRules = false;
        });
      }
    }
  }

  void _toggleOffset(int offset, bool? checked) {
    if (_saving) return;
    if ((checked ?? false) &&
        !_offsets.contains(offset) &&
        _offsets.length >= ReminderRuleLimits.maxRuleCount &&
        !ReminderRuleStore.requiresReview(_offsets.toList())) {
      _showMessage('最多保存 32 条提醒规则');
      return;
    }
    final next = Set<int>.of(_offsets);
    if (checked ?? false) {
      next.add(offset);
    } else {
      next.remove(offset);
    }
    unawaited(_applyOffsetMutation(next));
  }

  void _removeOffset(int offset) {
    if (_saving) return;
    final next = Set<int>.of(_offsets)..remove(offset);
    unawaited(_applyOffsetMutation(next));
  }

  void _applyPreset(ReminderFrequencyPreset preset) {
    if (_saving) return;
    unawaited(_applyOffsetMutation(preset.offsetsMinutes.toSet()));
  }

  void _addCustomOffset() {
    if (_saving) return;
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
    final next = Set<int>.of(_offsets)..add(totalMinutes);
    _customHoursController.clear();
    _customMinutesController.clear();
    unawaited(_applyOffsetMutation(next));
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
        if (saved) unawaited(_loadHealth(force: true));
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
        unawaited(_loadHealth(force: true));
      }
    } on PlatformException catch (error) {
      debugPrint('[ReminderSettings] requestPermission: ${error.runtimeType}');
      if (mounted) {
        await _openPermissionSettings(
          widget.permissionSettingsService.openNotificationSettingsResult,
          destination: '通知设置',
        );
      }
    } on MissingPluginException catch (error) {
      debugPrint('[ReminderSettings] requestPermission: ${error.runtimeType}');
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
        if (saved) unawaited(_loadHealth(force: true));
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
      unawaited(_loadHealth(force: true));
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

  Future<void> _saveNightBreakthrough(bool value) async {
    setState(() => _saving = true);
    try {
      final saved = await widget.assignmentStore
          .saveAllowUrgentDeadlineNightBreakthrough(value);
      if (mounted) {
        _showMessage(saved
            ? widget.assignmentStore.serviceWarnings.isNotEmpty
                ? '夜间穿透设置已保存，但提醒仍需处理：${widget.assignmentStore.serviceWarnings.first}'
                : value
                    ? '已允许 ≤1 小时紧急死线在夜间静音时段提醒'
                    : '已关闭夜间静音穿透，23:30–07:30 默认静音'
            : widget.assignmentStore.operationError ?? '设置保存失败，请重试');
        if (saved) unawaited(_loadHealth(force: true));
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
    _showMessage(switch (result) {
      SettingsOpenResult.direct => '',
      SettingsOpenResult.listFallback =>
        '未能直达$destination，已打开相关系统设置列表；请查找“学习通课业手记”',
      SettingsOpenResult.appDetailsFallback => batterySettings
          ? '已打开“学习通课业手记”的应用详情，请进入电池或后台运行设置自行核对'
          : '未能直达$destination，已打开“学习通课业手记”的应用详情',
      SettingsOpenResult.unavailable =>
        '无法打开$destination，请手动在手机系统设置中搜索“学习通课业手记”',
    });
  }

  void _showMessage(String message) {
    showJournalMessage(context, message);
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

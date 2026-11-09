import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/assignment.dart';
import 'reminder_rule_store.dart';
import 'daily_summary.dart';
import '../models/personal_workspace.dart';
import '../models/study_notebook.dart';

typedef NotificationPayloadHandler = void Function(String payload);

class LocalNotificationService {
  LocalNotificationService(
      {NotificationPayloadHandler? onPayload,
      FlutterLocalNotificationsPlugin? plugin})
      : _onPayload = onPayload,
        _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  String? lastWarning;
  bool showDetails = false;
  static const assignmentChannel = 'assignment_deadlines';
  static const summaryChannel = 'daily_summary';
  static const manualChannel = 'personal_schedule';
  static const _permissionsChannel =
      MethodChannel('study_assistant/permissions');
  static const _androidChannels = <AndroidNotificationChannel>[
    AndroidNotificationChannel(
      assignmentChannel,
      '作业截止提醒',
      description: '学习通作业截止前提醒',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      summaryChannel,
      '每日课业摘要',
      description: '基于最近一次本机快照的课业摘要',
      importance: Importance.defaultImportance,
    ),
    AndroidNotificationChannel(
      manualChannel,
      '个人待办与考试提醒',
      description: '个人待办和考试开始前提醒',
      importance: Importance.high,
    ),
  ];

  Future<void>? _pluginInitialization;
  final Map<String, Future<void>> _channelCreations = {};
  bool _pluginInitialized = false;
  static Future<void> _scheduleMutationQueue = Future<void>.value();
  static const _scheduleCategories = ['assignments', 'manual', 'summary'];
  static const _scheduleJournalPrefix = 'notification_schedule_v2_journal_';
  static const _scheduleActivePrefix = 'notification_schedule_v2_active_';

  /// Privacy tightening must not retain detailed alarms if replacement fails.
  Future<void> cancelPrivateSchedules() async {
    await _ensurePluginInitialized();
    await _runScheduleMutation(() async {
      final prefs = await SharedPreferences.getInstance();
      final ids = <int>{};
      final validActiveManifests = <String>{};
      final validJournals = <String>{};
      final damagedActiveManifests = <String>{};
      final damagedJournals = <String>{};
      final damaged = <String>[];
      Object? systemReadFailure;

      // Privacy cleanup must not be coupled to recovery of an unrelated
      // category. Even if a manifest is damaged, the OS pending-request list
      // still identifies scheduled private payloads that can be cancelled.
      try {
        final pending = await _plugin.pendingNotificationRequests();
        ids.addAll(pending
            .where((item) => _isPrivatePayload(item.payload))
            .map((item) => item.id));
      } catch (error) {
        systemReadFailure = error;
      }

      // Delivered notifications no longer appear in the pending-request
      // list. Include still-visible notifications so a damaged or missing
      // manifest cannot leave lock-screen content behind unnoticed.
      try {
        final active = await _plugin.getActiveNotifications();
        ids.addAll(active
            .where(
                (item) => _isPrivateActiveNotification(item) && item.id != null)
            .map((item) => item.id!));
      } catch (error) {
        systemReadFailure ??= error;
      }

      for (final category in _scheduleCategories) {
        try {
          final activeIds = _readActiveIds(prefs, category);
          if (prefs.containsKey(_activeKey(category))) {
            validActiveManifests.add(category);
          }
          ids.addAll(activeIds);
        } catch (error) {
          damagedActiveManifests.add(category);
          damaged.add('$category 已生效提醒清单损坏：$error');
        }
        try {
          final journal = _readJournal(prefs, category);
          if (journal != null) {
            ids.addAll(journal['oldIds'] as List<int>);
            ids.addAll(journal['newIds'] as List<int>);
            validJournals.add(category);
          }
        } catch (error) {
          damagedJournals.add(category);
          damaged.add('$category 提醒事务记录损坏：$error');
        }
      }

      final failures = await _cancelIds(ids);
      if (failures.isNotEmpty) {
        lastWarning = '隐私提醒清理未完成，部分通知仍可能保留：${failures.join('; ')}';
        throw StateError(lastWarning!);
      }

      // If the OS list could not be read, do not erase otherwise-valid
      // manifests: they are still needed to retry the unknown remainder.
      if (systemReadFailure != null) {
        lastWarning = '已取消可识别的隐私提醒，但系统通知状态读取失败，无法确认清理完整性：$systemReadFailure';
        throw StateError(lastWarning!);
      }

      try {
        for (final category in _scheduleCategories) {
          // A corrupt journal may contain the only copy of staged or already
          // delivered IDs. Keep all metadata for that category for diagnosis.
          if (damagedJournals.contains(category)) continue;
          final activeIsDamaged = damagedActiveManifests.contains(category);
          final journalIsValid = validJournals.contains(category);
          // A valid journal contains the complete old/new ID sets, so after
          // cancelling both sets it can safely repair a damaged active list.
          if (activeIsDamaged && !journalIsValid) continue;
          if (validActiveManifests.contains(category) || activeIsDamaged) {
            await _writeActiveIds(prefs, category, const []);
          }
          if (journalIsValid) await _removeJournal(prefs, category);
        }
      } catch (error) {
        lastWarning = '已取消可识别的隐私提醒，但本机恢复记录清理失败：$error';
        throw StateError(lastWarning!);
      }

      for (final category
          in validJournals.intersection(damagedActiveManifests)) {
        damaged.removeWhere((item) => item.startsWith('$category 已生效提醒清单损坏：'));
      }

      if (damaged.isNotEmpty) {
        // Keep damaged records visible for manual recovery. Their delivered
        // notification IDs cannot be reconstructed from pending requests.
        lastWarning = '已尽可能清理可识别的隐私提醒，但部分历史通知无法确认：${damaged.join('；')}';
        throw StateError(lastWarning!);
      }
      lastWarning = null;
    });
  }

  NotificationPayloadHandler? _onPayload;
  String? _pendingPayload;
  Future<void> rescheduleManual(List<ManualEntry> entries) async {
    lastWarning = null;
    await _ensurePluginInitialized();
    final schedules = <(ManualEntry, DateTime)>[];
    final seen = <String>{};
    var reminderWindowMissed = false;
    for (final e in entries.where((e) => !e.done && e.remind && e.at != null)) {
      final at = e.at!.subtract(const Duration(minutes: 30));
      if (!at.isAfter(DateTime.now())) {
        reminderWindowMissed = true;
        continue;
      }
      if (!seen.add(e.id)) {
        throw StateError('个人提醒存在重复标识，请修改后重试');
      }
      schedules.add((e, at));
    }
    if (reminderWindowMissed) {
      lastWarning =
          _appendWarning(lastWarning, '部分个人安排的提前30分钟提醒时间已过，本次未安排提醒；请调整时间或关闭提醒');
    }
    if (schedules.isNotEmpty) {
      await _ensureAndroidChannel(manualChannel);
      if (defaultTargetPlatform == TargetPlatform.android) {
        // Scheduling can succeed even while Android suppresses delivery due
        // to the app permission or the user's channel setting. Surface that
        // distinction to the caller instead of reporting an unqualified save.
        final health = await inspectHealth();
        if (health.notifications == false) {
          lastWarning =
              _appendWarning(lastWarning, '系统通知权限已关闭，个人安排已保存，但系统不会显示提醒');
        } else if (health.notifications == null) {
          lastWarning = _appendWarning(lastWarning, '无法确认系统通知权限，请在提醒体检中检查');
        }
        final channelStatus = health.manualChannel?.status;
        if (channelStatus == ReminderChannelStatus.disabled) {
          lastWarning =
              _appendWarning(lastWarning, '个人日程通知渠道已被系统关闭，已保存的安排不会显示提醒');
        } else if (channelStatus == ReminderChannelStatus.missing ||
            channelStatus == ReminderChannelStatus.queryFailed) {
          lastWarning = _appendWarning(lastWarning, '无法确认个人日程通知渠道状态，请在提醒体检中检查');
        }
        if (health.exact == false) {
          lastWarning = _appendWarning(lastWarning, '系统未授予精确闹钟权限，个人提醒可能延迟触发');
        }
      }
    }
    try {
      await _replaceScheduleBatch(
        category: 'manual',
        belongs: (payload) => payload?.startsWith('p:') ?? false,
        schedules: schedules,
        schedule: (id, item) {
          final (entry, at) = item as (ManualEntry, DateTime);
          return _zonedSchedule(
              id: id,
              channelId: manualChannel,
              title: entry.kind == 'exam' ? '个人考试提醒' : '个人待办提醒',
              body: showDetails
                  ? '${entry.title} · 30分钟后到时，请核对个人安排'
                  : '有个人安排即将到时，请打开课业手记查看',
              notifyAt: at,
              payload: 'p:${entry.id}');
        },
      );
    } catch (error) {
      lastWarning = _appendWarning(lastWarning, '个人日程提醒批次未能完成：$error');
      rethrow;
    }
  }

  Future<ReminderHealth> inspectHealth() async {
    bool? allowed, exact;
    int? pending, summary, manual;
    var scheduleRecoveryPending = true;
    try {
      scheduleRecoveryPending = await hasPendingScheduleRecovery();
    } catch (_) {
      scheduleRecoveryPending = true;
    }
    final channels = await _inspectChannelHealth();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      allowed = await android?.areNotificationsEnabled();
    } catch (_) {}
    try {
      exact = await android?.canScheduleExactNotifications();
    } catch (_) {}
    try {
      final list = await _plugin.pendingNotificationRequests();
      pending = list.where((n) => n.payload?.startsWith('a:') ?? false).length;
      summary = list.where((n) => n.payload == 'd:summary').length;
      manual = list.where((n) => n.payload?.startsWith('p:') ?? false).length;
    } catch (_) {}
    return ReminderHealth(
        notifications: allowed,
        exact: exact,
        assignmentChannel: channels.$1,
        summaryChannel: channels.$2,
        manualChannel: channels.$3,
        pending: pending,
        summaryPending: summary,
        manualPending: manual,
        scheduleRecoveryPending: scheduleRecoveryPending);
  }

  Future<bool> showTestNotification() => _runScheduleMutation(() async {
        // Enqueue before initialization/health awaits so account/privacy cleanup
        // also retires a test notification whose display request is still in flight.
        try {
          await _ensureReadyForScheduling(assignmentChannel);
          final health = await inspectHealth();
          final channelStatus = health.assignmentChannel?.status;
          if (health.notifications != true ||
              (channelStatus != ReminderChannelStatus.enabled &&
                  channelStatus != ReminderChannelStatus.unsupported)) {
            return false;
          }
          await _plugin.show(
              DailySummary.baseId + 8,
              '课业手记测试通知',
              '如果看到了这条通知，当前显示链路可用；不代表未来后台提醒一定送达。',
              const NotificationDetails(
                  android: AndroidNotificationDetails(
                      assignmentChannel, '作业截止提醒',
                      importance: Importance.high, priority: Priority.high)),
              payload: 't:notification-test');
          return true;
        } catch (_) {
          return false;
        }
      });

  Future<void> rescheduleSummary(List<Assignment> assignments,
      PersonalWorkspace personal, DateTime? lastSync) async {
    lastWarning = null;
    await _ensurePluginInitialized();
    final desired =
        DailySummary.build(assignments, personal, DateTime.now(), lastSync);
    if (desired.isNotEmpty) await _ensureAndroidChannel(summaryChannel);
    try {
      await _replaceScheduleBatch(
        category: 'summary',
        belongs: (payload) => payload == 'd:summary',
        schedules: desired,
        schedule: (id, item) {
          final notice = item as SummaryNotice;
          return _plugin.zonedSchedule(
              id,
              '今日课业摘要',
              showDetails ? notice.body : '今日课业摘要已准备好，请打开课业手记查看',
              tz.TZDateTime.from(notice.at, tz.local),
              NotificationDetails(
                  android: AndroidNotificationDetails(summaryChannel, '每日课业摘要',
                      importance: Importance.defaultImportance,
                      visibility: NotificationVisibility.private)),
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
              payload: 'd:summary');
        },
      );
    } catch (error) {
      lastWarning = _appendWarning(lastWarning, '每日摘要提醒批次未能完成：$error');
      rethrow;
    }
  }

  static String formatDeadlineRemainingText(int offsetMinutes) {
    final safeMinutes = offsetMinutes < 0 ? 0 : offsetMinutes;
    final days = safeMinutes ~/ 1440;
    final hours = (safeMinutes % 1440) ~/ 60;
    final minutes = safeMinutes % 60;
    final parts = <String>[
      if (days > 0) '$days 天',
      if (hours > 0) '$hours 小时',
      if (minutes > 0 || (days == 0 && hours == 0)) '$minutes 分钟',
    ];
    return '还剩 ${parts.join(' ')}截止';
  }

  void setPayloadHandler(NotificationPayloadHandler? onPayload) {
    _onPayload = onPayload;
    final pendingPayload = _pendingPayload;
    if (onPayload != null && pendingPayload != null) {
      _pendingPayload = null;
      onPayload(pendingPayload);
    }
  }

  Future<void> initializeSafely({NotificationPayloadHandler? onPayload}) async {
    try {
      await initialize(onPayload: onPayload);
    } catch (_) {
      lastWarning ??= '提醒初始化失败，请检查系统通知设置';
    }
  }

  Future<void> initialize({NotificationPayloadHandler? onPayload}) async {
    if (onPayload != null) {
      setPayloadHandler(onPayload);
    }
    await _ensurePluginInitialized();
    final failures = <String>[];
    try {
      await _ensureAllAndroidChannels();
    } catch (error) {
      failures.add('渠道初始化：$error');
    }
    try {
      await recoverPendingSchedules();
    } catch (error) {
      failures.add('提醒事务恢复：$error');
    }
    if (failures.isNotEmpty) {
      lastWarning = failures.join('；');
      throw StateError(lastWarning!);
    }
    lastWarning = null;
  }

  /// Retries durable schedule-batch recovery after an interrupted or failed
  /// replacement. Safe to call repeatedly and after process restart.
  Future<void> recoverPendingSchedules() async {
    await _ensurePluginInitialized();
    await _runScheduleMutation(_recoverAllScheduleTransactionsLocked);
  }

  Future<bool> hasPendingScheduleRecovery() async {
    final prefs = await SharedPreferences.getInstance();
    final activeIdsByCategory = <String, Set<int>>{};
    for (final category in _scheduleCategories) {
      try {
        if (prefs.getString(_journalKey(category)) != null) return true;
        activeIdsByCategory[category] = _readActiveIds(prefs, category).toSet();
      } catch (_) {
        // A damaged active-ID manifest is also a recovery condition. Do not
        // silently report a healthy schedule when privacy cleanup can no
        // longer identify notifications that have already been delivered.
        return true;
      }
    }
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final item in pending) {
        if (item.id < 2000000000) continue;
        final category = _scheduleCategoryForPayload(item.payload);
        if (category != null &&
            !activeIdsByCategory[category]!.contains(item.id)) {
          return true;
        }
      }
    } catch (_) {
      return true;
    }
    try {
      final active = await _plugin.getActiveNotifications();
      for (final item in active) {
        final id = item.id;
        if (id == null || id < 2000000000) continue;
        final category = _scheduleCategoryForPayload(item.payload);
        if (category != null && !activeIdsByCategory[category]!.contains(id)) {
          return true;
        }
      }
    } catch (_) {
      return true;
    }
    return false;
  }

  Future<void> _ensurePluginInitialized() async {
    if (_pluginInitialized) return;
    final active = _pluginInitialization;
    if (active != null) return active;
    final initialization = _initializePlugin();
    _pluginInitialization = initialization;
    try {
      await initialization;
      _pluginInitialized = true;
    } catch (_) {
      if (identical(_pluginInitialization, initialization)) {
        _pluginInitialization = null;
      }
      rethrow;
    }
  }

  Future<void> _initializePlugin() async {
    timezone_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    const android = AndroidInitializationSettings('@drawable/app_icon');
    const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false);
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchResponse = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchResponse != null) {
      _handleNotificationResponse(launchResponse);
    }
  }

  Future<void> _ensureReadyForScheduling(String channelId) async {
    await _ensurePluginInitialized();
    await _ensureAndroidChannel(channelId);
  }

  Future<void> _ensureAllAndroidChannels() async {
    final failures = <String>[];
    for (final channel in _androidChannels) {
      try {
        await _ensureAndroidChannel(channel.id);
      } catch (error) {
        failures.add('${channel.id}: $error');
      }
    }
    if (failures.isNotEmpty) {
      throw StateError('通知渠道初始化失败：${failures.join('；')}');
    }
  }

  Future<void> _ensureAndroidChannel(String channelId) async {
    final channel =
        _androidChannels.where((item) => item.id == channelId).firstOrNull;
    if (channel == null) throw ArgumentError.value(channelId, 'channelId');
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    final active = _channelCreations[channelId];
    if (active != null) return active;
    final creation = _createAndroidChannel(android, channel);
    _channelCreations[channelId] = creation;
    try {
      await creation;
    } finally {
      if (identical(_channelCreations[channelId], creation)) {
        _channelCreations.remove(channelId);
      }
    }
  }

  Future<void> _replaceScheduleBatch({
    required String category,
    required bool Function(String?) belongs,
    required List<Object> schedules,
    required Future<void> Function(int id, Object item) schedule,
  }) async {
    await _runScheduleMutation(() async {
      await _recoverScheduleTransactionLocked(category);
      final prefs = await SharedPreferences.getInstance();
      final pending = await _plugin.pendingNotificationRequests();
      final oldIds = <int>{
        ..._readActiveIds(prefs, category),
        ...pending
            .where((item) => belongs(item.payload))
            .map((item) => item.id),
      };
      final reserved = <int>{...pending.map((item) => item.id)};
      for (final otherCategory in _scheduleCategories) {
        try {
          reserved.addAll(_readActiveIds(prefs, otherCategory));
        } catch (error) {
          if (otherCategory == category) rethrow;
          lastWarning = _appendWarning(
              lastWarning, '$otherCategory 的已生效提醒清单损坏，已隔离该类别并保留现有通知');
        }
        try {
          final otherJournal = _readJournal(prefs, otherCategory);
          if (otherJournal != null) {
            reserved.addAll(otherJournal['oldIds'] as List<int>);
            reserved.addAll(otherJournal['newIds'] as List<int>);
          }
        } catch (error) {
          if (otherCategory == category) rethrow;
          lastWarning = _appendWarning(
              lastWarning, '$otherCategory 的提醒事务记录损坏，已隔离该类别并保留现有通知');
        }
      }
      final newIds = _allocateNotificationIds(schedules.length, reserved);
      final journal = <String, Object>{
        'version': 2,
        'category': category,
        'phase': 'staging',
        'oldIds': oldIds.toList()..sort(),
        'newIds': newIds,
      };
      await _writeJournal(prefs, category, journal);

      try {
        for (var index = 0; index < schedules.length; index++) {
          await schedule(newIds[index], schedules[index]);
        }
      } catch (error, stack) {
        final compensationFailures = await _cancelIds(newIds);
        if (compensationFailures.isEmpty) {
          try {
            await _removeJournal(prefs, category);
          } catch (cleanupError) {
            lastWarning = '新提醒安排失败，补偿通知已取消，但事务记录清理失败；下次启动将继续恢复';
            throw StateError('$error；事务记录清理失败：$cleanupError');
          }
          Error.throwWithStackTrace(error, stack);
        }
        lastWarning = '新提醒安排失败，部分临时提醒未能撤销；旧提醒已保留，系统将在下次启动或重试时继续恢复';
        throw StateError('$error；补偿取消失败：${compensationFailures.join('; ')}');
      }

      final committed = <String, Object>{...journal, 'phase': 'committed'};
      try {
        await _writeJournal(prefs, category, committed);
      } catch (error, stack) {
        // A preferences write can fail after the platform has already made
        // the value durable. Never cancel the new batch until a read-back
        // proves that the committed marker was not persisted.
        String? persisted;
        var stateVerified = false;
        try {
          await prefs.reload();
          persisted = prefs.getString(_journalKey(category));
          stateVerified = true;
        } catch (_) {
          stateVerified = false;
        }
        final committedRaw = jsonEncode(committed);
        final stagingRaw = jsonEncode(journal);
        if (stateVerified && persisted == committedRaw) {
          await _recoverScheduleTransactionLocked(category);
          return;
        }
        if (!stateVerified || (persisted != stagingRaw && persisted != null)) {
          lastWarning = '提醒提交状态无法核实；新旧提醒和事务记录均予以保留，请重试恢复，勿手动清理通知';
          throw StateError('$error；无法确认事务记录当前状态，已保留新旧批次');
        }
        if (persisted == null) {
          // The previously durable staging record is unexpectedly absent.
          // Recreate it before compensation so a process restart can finish
          // cleanup if this operation is interrupted again.
          try {
            await _writeJournal(prefs, category, journal);
          } catch (repairError) {
            lastWarning = '事务提交失败且无法重建恢复记录；新旧提醒均予以保留，需人工检查本机提醒状态';
            throw StateError('$error；恢复记录重建失败：$repairError');
          }
        }
        final compensationFailures = await _cancelIds(newIds);
        if (compensationFailures.isNotEmpty) {
          lastWarning = '提醒批次提交失败，临时提醒撤销未完成；旧提醒已保留，请重试恢复';
          throw StateError('$error；补偿取消失败：${compensationFailures.join('; ')}');
        }
        try {
          await _removeJournal(prefs, category);
        } catch (cleanupError) {
          lastWarning = '新提醒已取消，但事务记录清理失败；请重试提醒恢复';
          throw StateError('$error；事务记录清理失败：$cleanupError');
        }
        Error.throwWithStackTrace(error, stack);
      }

      // Once the committed marker is durable, the new batch is authoritative.
      // A failed old-batch cancellation leaves a committed journal for retry.
      await _recoverScheduleTransactionLocked(category);
    });
  }

  Future<T> _runScheduleMutation<T>(Future<T> Function() action) async {
    final previous = _scheduleMutationQueue;
    final completed = Completer<void>();
    _scheduleMutationQueue = completed.future;
    try {
      await previous;
      return await action();
    } finally {
      completed.complete();
    }
  }

  Future<void> _recoverAllScheduleTransactionsLocked() async {
    final failures = <String>[];
    final activeIdsByCategory = <String, Set<int>>{};
    final hasActiveManifestByCategory = <String, bool>{};
    final blockedOrphanCategories = <String>{};
    for (final category in _scheduleCategories) {
      final prefs = await SharedPreferences.getInstance();
      try {
        await _recoverScheduleTransactionLocked(category);
        activeIdsByCategory[category] = _readActiveIds(prefs, category).toSet();
        hasActiveManifestByCategory[category] =
            prefs.containsKey(_activeKey(category));
      } catch (error) {
        failures.add('$category: $error');
        // A v2 journal carries its owning category. If it has been copied or
        // swapped into another category's key, do not reinterpret the IDs as
        // an orphan of the embedded category and guess which phase won.
        try {
          final raw = prefs.getString(_journalKey(category));
          final decoded = raw == null ? null : jsonDecode(raw);
          final owner = decoded is Map ? decoded['category'] : null;
          if (owner is String &&
              _scheduleCategories.contains(owner) &&
              owner != category) {
            blockedOrphanCategories.add(owner);
          } else if (decoded is Map && decoded['version'] == 1) {
            final legacyIds = <int>{
              if (decoded['oldIds'] is List)
                ...(decoded['oldIds'] as List).whereType<int>(),
              if (decoded['newIds'] is List)
                ...(decoded['newIds'] as List).whereType<int>(),
            };
            for (final other
                in _scheduleCategories.where((item) => item != category)) {
              try {
                if (legacyIds
                    .intersection(_readActiveIds(prefs, other).toSet())
                    .isNotEmpty) {
                  blockedOrphanCategories.add(other);
                }
              } catch (_) {
                // The damaged manifest is handled by its own category pass.
              }
            }
            try {
              final pending = await _plugin.pendingNotificationRequests();
              final active = await _plugin.getActiveNotifications();
              for (final item in pending) {
                final owner = _scheduleCategoryForPayload(item.payload);
                if (legacyIds.contains(item.id) &&
                    owner != null &&
                    owner != category) {
                  blockedOrphanCategories.add(owner);
                }
              }
              for (final item in active) {
                final id = item.id;
                final owner = _scheduleCategoryForPayload(item.payload);
                if (id != null &&
                    legacyIds.contains(id) &&
                    owner != null &&
                    owner != category) {
                  blockedOrphanCategories.add(owner);
                }
              }
            } catch (_) {
              // The primary v1 ownership check already failed closed.
            }
          }
        } catch (_) {
          // The primary recovery error already records unreadable metadata.
        }
      }
    }
    final orphaned = <String, Set<int>>{};
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final item in pending) {
        if (item.id >= 2000000000) {
          final category = _scheduleCategoryForPayload(item.payload);
          if (category != null && activeIdsByCategory.containsKey(category)) {
            final foreignManifest = activeIdsByCategory.entries
                .where((entry) =>
                    entry.key != category && entry.value.contains(item.id))
                .firstOrNull;
            if (foreignManifest != null) {
              blockedOrphanCategories.add(category);
              failures.add(
                  '$category 通知 ID 同时登记在 ${foreignManifest.key} 清单，已保留并等待核对');
            } else if (!activeIdsByCategory[category]!.contains(item.id)) {
              orphaned.putIfAbsent(category, () => <int>{}).add(item.id);
            }
          }
        }
      }
    } catch (error) {
      failures.add('待投递通知扫描失败: $error');
    }
    try {
      // A transaction notification may have fired while the process was
      // stopped. It is then absent from pendingNotificationRequests but still
      // visible in NotificationManager; include it in orphan reconciliation.
      final active = await _plugin.getActiveNotifications();
      for (final item in active) {
        final id = item.id;
        if (id == null || id < 2000000000) continue;
        final category = _scheduleCategoryForPayload(item.payload);
        if (category != null && activeIdsByCategory.containsKey(category)) {
          final foreignManifest = activeIdsByCategory.entries
              .where(
                  (entry) => entry.key != category && entry.value.contains(id))
              .firstOrNull;
          if (foreignManifest != null) {
            blockedOrphanCategories.add(category);
            failures.add(
                '$category 当前可见通知 ID 同时登记在 ${foreignManifest.key} 清单，已保留并等待核对');
          } else if (!activeIdsByCategory[category]!.contains(id)) {
            orphaned.putIfAbsent(category, () => <int>{}).add(id);
          }
        }
      }
    } catch (error) {
      failures.add('当前可见通知扫描失败: $error');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final entry in orphaned.entries) {
        final category = entry.key;
        if (blockedOrphanCategories.contains(category)) {
          failures.add('$category 的事务记录出现在其他类别，已保留通知并等待人工核对');
          continue;
        }
        if (hasActiveManifestByCategory[category] != true) {
          failures.add('$category 存在未登记的事务通知，但有效提醒清单缺失，无法安全判断新旧批次；已保留通知');
          continue;
        }
        final oldIds = activeIdsByCategory[category]!.toList()..sort();
        final newIds = entry.value.toList()..sort();
        try {
          await _writeJournal(prefs, category, {
            'version': 2,
            'category': category,
            'phase': 'staging',
            'oldIds': oldIds,
            'newIds': newIds,
          });
          await _recoverScheduleTransactionLocked(category);
        } catch (error) {
          // If no durable journal can be written, still attempt cancellation.
          // A failed cancellation remains discoverable in the OS pending list.
          final cancelFailures = await _cancelIds(newIds);
          if (cancelFailures.isNotEmpty) {
            failures.add(
                '$category 存在未登记的事务通知，恢复记录写入失败且取消失败：${cancelFailures.join('; ')}；$error');
            continue;
          }
          try {
            // If the journal write actually reached storage before its
            // acknowledgement failed, finish removing that now-resolved
            // staging record instead of leaving a permanent false warning.
            await _recoverScheduleTransactionLocked(category);
          } catch (cleanupError) {
            failures.add('$category 未登记通知已取消，但恢复记录仍未能收敛：$cleanupError');
          }
        }
      }
    } catch (error) {
      failures.add('未登记的通知事务: $error');
    }
    if (failures.isNotEmpty) {
      lastWarning = '提醒恢复仍有未完成操作：${failures.join('；')}';
      throw StateError(lastWarning!);
    }
    lastWarning = null;
  }

  Future<void> _recoverScheduleTransactionLocked(String category) async {
    final prefs = await SharedPreferences.getInstance();
    final journal = _readJournal(prefs, category);
    if (journal == null) return;
    if (journal['version'] == 1) {
      await _verifyLegacyJournalOwnership(category, journal, prefs);
    } else {
      await _verifyV2JournalOwnership(category, journal, prefs);
    }
    final phase = journal['phase'] as String;
    final oldIds = journal['oldIds'] as List<int>;
    final newIds = journal['newIds'] as List<int>;
    if (phase == 'staging') {
      final failures = await _cancelIds(newIds);
      if (failures.isNotEmpty) {
        lastWarning = '提醒批次尚未提交，临时通知撤销失败：${failures.join('; ')}';
        throw StateError(lastWarning!);
      }
      await _removeJournal(prefs, category);
      return;
    }
    if (phase == 'committed') {
      final failures = await _cancelIds(oldIds);
      if (failures.isNotEmpty) {
        lastWarning = '新提醒批次已生效，旧通知清理失败：${failures.join('; ')}';
        throw StateError(lastWarning!);
      }
      await _writeActiveIds(prefs, category, newIds);
      await _removeJournal(prefs, category);
      return;
    }
    throw FormatException('未知提醒事务阶段：$phase');
  }

  Future<void> _verifyV2JournalOwnership(
    String category,
    Map<String, dynamic> journal,
    SharedPreferences prefs,
  ) async {
    final transactionIds = <int>{
      ...(journal['oldIds'] as List<int>),
      ...(journal['newIds'] as List<int>),
    };
    for (final other in _scheduleCategories.where((item) => item != category)) {
      final foreignIds = _readActiveIds(prefs, other).toSet();
      if (transactionIds.intersection(foreignIds).isNotEmpty) {
        throw FormatException('v2 $category 事务包含 $other 类别的通知 ID');
      }
    }

    final pending = await _plugin.pendingNotificationRequests();
    final active = await _plugin.getActiveNotifications();
    void verifyVisible(int id, String? owner) {
      if (!transactionIds.contains(id)) return;
      if (owner == null) {
        throw FormatException('v2 $category 事务 ID 缺少可证明的类别归属');
      }
      if (owner != category) {
        throw FormatException('v2 $category 事务 ID 实际属于 $owner 通知类别');
      }
    }

    for (final item in pending) {
      verifyVisible(item.id, _scheduleCategoryForPayload(item.payload));
    }
    for (final item in active) {
      final id = item.id;
      if (id == null || !transactionIds.contains(id)) continue;
      var owner = _scheduleCategoryForPayload(item.payload);
      final channelOwner = _scheduleCategoryForChannel(item.channelId);
      if (owner != null && channelOwner != null && owner != channelOwner) {
        throw FormatException('v2 $category 事务 ID 的 payload 与原生渠道归属冲突');
      }
      // Android v18 omits payload for delivered notifications. A matching
      // native channel is independent category evidence for a v2 journal with
      // explicit category and non-overlapping manifests. Do not guess from an
      // ID alone, an unknown nonempty payload, or a tagged notification.
      if (owner == null &&
          (item.payload == null || item.payload!.isEmpty) &&
          item.tag == null) {
        owner = channelOwner;
      }
      verifyVisible(id, owner);
    }
  }

  Future<void> _verifyLegacyJournalOwnership(
    String category,
    Map<String, dynamic> journal,
    SharedPreferences prefs,
  ) async {
    final oldIds = (journal['oldIds'] as List<int>).toSet();
    final newIds = (journal['newIds'] as List<int>).toSet();
    final transactionIds = {...oldIds, ...newIds};
    var foreignManifestUnreadable = false;

    for (final other in _scheduleCategories.where((item) => item != category)) {
      try {
        final foreignIds = _readActiveIds(prefs, other).toSet();
        if (transactionIds.intersection(foreignIds).isNotEmpty) {
          throw FormatException('旧版 $category 事务包含已登记在 $other 类别的通知 ID');
        }
      } on FormatException catch (error) {
        if (error.message.contains('已登记在')) rethrow;
        foreignManifestUnreadable = true;
      }
    }

    final pending = await _plugin.pendingNotificationRequests();
    final active = await _plugin.getActiveNotifications();
    var visibleTransactionIdMatches = false;
    void verifyVisible(int id, String? payload) {
      if (!transactionIds.contains(id)) return;
      final owner = _scheduleCategoryForPayload(payload);
      if (owner != null && owner != category) {
        throw FormatException('旧版 $category 事务 ID 实际属于 $owner 通知类别');
      }
      if (owner == category) {
        visibleTransactionIdMatches = true;
      }
    }

    for (final item in pending) {
      verifyVisible(item.id, item.payload);
    }
    for (final item in active) {
      final id = item.id;
      if (id != null) verifyVisible(id, item.payload);
    }

    // v1 did not persist its owning category. A manifest stored beside the
    // journal is not independent evidence: both keys may have been copied or
    // swapped together. Require at least one transaction ID to remain visible
    // in the OS with a payload that proves this category. Otherwise preserve
    // the journal rather than destructively guessing its owner.
    if (!visibleTransactionIdMatches || foreignManifestUnreadable) {
      throw const FormatException('旧版提醒事务缺少类别归属证据，已保留原通知等待人工核对');
    }
  }

  Map<String, dynamic>? _readJournal(SharedPreferences prefs, String category) {
    final raw = prefs.getString(_journalKey(category));
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        !const [1, 2].contains(decoded['version']) ||
        (decoded['version'] == 2 && decoded['category'] != category) ||
        (decoded['category'] != null && decoded['category'] != category) ||
        !const ['staging', 'committed'].contains(decoded['phase'])) {
      throw const FormatException('提醒事务记录格式无效');
    }
    List<int> ids(dynamic value, {bool transactional = false}) {
      if (value is! List ||
          value.any((id) =>
              id is! int ||
              id < 0 ||
              id > 0x7fffffff ||
              (transactional && id < 2000000000))) {
        throw const FormatException('提醒事务 ID 列表无效');
      }
      final result = value.cast<int>();
      if (result.toSet().length != result.length) {
        throw const FormatException('提醒事务 ID 重复');
      }
      return result;
    }

    final oldIds = ids(decoded['oldIds']);
    final newIds = ids(decoded['newIds'], transactional: true);
    if (oldIds.toSet().intersection(newIds.toSet()).isNotEmpty) {
      throw const FormatException('提醒事务新旧 ID 重叠');
    }
    return {
      'version': decoded['version'] as int,
      if (decoded['category'] is String) 'category': decoded['category'],
      'phase': decoded['phase'] as String,
      'oldIds': oldIds,
      'newIds': newIds,
    };
  }

  List<int> _readActiveIds(SharedPreferences prefs, String category) {
    final raw = prefs.getStringList(_activeKey(category)) ?? const [];
    final ids = <int>[];
    for (final item in raw) {
      final id = int.tryParse(item);
      if (id == null || id < 0 || id > 0x7fffffff) {
        throw FormatException('已生效提醒 ID 无效：$category');
      }
      ids.add(id);
    }
    if (ids.toSet().length != ids.length) {
      throw FormatException('已生效提醒 ID 重复：$category');
    }
    return ids;
  }

  Future<void> _writeJournal(SharedPreferences prefs, String category,
      Map<String, Object> journal) async {
    final encoded = jsonEncode(journal);
    Object? writeFailure;
    try {
      if (await prefs.setString(_journalKey(category), encoded)) return;
      writeFailure = StateError('提醒事务记录写入返回失败');
    } catch (error) {
      writeFailure = error;
    }
    try {
      await prefs.reload();
      if (prefs.getString(_journalKey(category)) == encoded) return;
    } catch (verifyError) {
      throw StateError('提醒事务记录写入结果无法核实：$writeFailure；$verifyError');
    }
    throw StateError('提醒事务记录未能持久化：$writeFailure');
  }

  Future<void> _writeActiveIds(
      SharedPreferences prefs, String category, List<int> ids) async {
    final encoded = ids.map((id) => '$id').toList();
    if (!await prefs.setStringList(_activeKey(category), encoded)) {
      await prefs.reload();
      if (!listEquals(prefs.getStringList(_activeKey(category)), encoded)) {
        throw StateError('已生效提醒清单未能持久化');
      }
    }
  }

  Future<void> _removeJournal(SharedPreferences prefs, String category) async {
    if (!await prefs.remove(_journalKey(category))) {
      await prefs.reload();
      if (prefs.getString(_journalKey(category)) != null) {
        throw StateError('提醒事务记录未能清理');
      }
    }
  }

  Future<List<String>> _cancelIds(Iterable<int> ids) async {
    final failures = <String>[];
    for (final id in ids.toSet()) {
      try {
        await _plugin.cancel(id);
      } catch (error) {
        failures.add('$id: $error');
      }
    }
    return failures;
  }

  List<int> _allocateNotificationIds(int count, Set<int> reserved) {
    final random = Random.secure();
    final result = <int>[];
    while (result.length < count) {
      // Keep new transactional IDs outside every legacy namespace:
      // assignment IDs (<1.7b), manual IDs (1.8b), and summary/test IDs (1.9b).
      const firstTransactionalId = 2000000000;
      final candidate = firstTransactionalId +
          random.nextInt(0x7fffffff - firstTransactionalId);
      if (reserved.add(candidate)) result.add(candidate);
    }
    return result;
  }

  static String _journalKey(String category) =>
      '$_scheduleJournalPrefix$category';
  static String _activeKey(String category) =>
      '$_scheduleActivePrefix$category';

  static bool _isPrivatePayload(String? payload) =>
      payload?.startsWith('a:') == true ||
      payload?.startsWith('p:') == true ||
      payload?.startsWith('d:') == true ||
      // The health-check notification is private too. It is not a scheduled
      // transaction, so it is cleaned by payload/active scanning rather than
      // being assigned to a category journal.
      payload?.startsWith('t:') == true;

  static bool _isPrivateActiveNotification(ActiveNotification item) {
    // Android plugin v18 returns id/channelId/tag for delivered notifications,
    // but omits payload. These three app-owned channels contain private work
    // content (including the test notification); all production posts are
    // untagged. This fallback is only for full privacy cleanup, never journal
    // recovery, where category ownership must remain fail-closed.
    return item.tag == null &&
        (_isPrivatePayload(item.payload) ||
            const {assignmentChannel, summaryChannel, manualChannel}
                .contains(item.channelId));
  }

  static String? _scheduleCategoryForPayload(String? payload) {
    if (payload?.startsWith('a:') == true) return 'assignments';
    if (payload?.startsWith('p:') == true) return 'manual';
    if (payload?.startsWith('d:') == true) return 'summary';
    return null;
  }

  static String? _scheduleCategoryForChannel(String? channel) =>
      switch (channel) {
        assignmentChannel => 'assignments',
        manualChannel => 'manual',
        summaryChannel => 'summary',
        _ => null,
      };

  static String _appendWarning(String? current, String next) =>
      current == null || current.isEmpty ? next : '$next；$current';

  Future<void> _createAndroidChannel(
    AndroidFlutterLocalNotificationsPlugin android,
    AndroidNotificationChannel channel,
  ) async {
    // Do not re-register an existing channel. Android protects most behavioral
    // settings, but createNotificationChannel may update the channel label and
    // description; querying first also preserves a user's custom channel name.
    final existing = await android.getNotificationChannels();
    if (existing == null) {
      throw StateError('无法确认通知渠道 ${channel.id} 是否存在');
    }
    if (existing.any((item) => item.id == channel.id)) return;
    await android.createNotificationChannel(channel);
  }

  Future<(ReminderChannelHealth, ReminderChannelHealth, ReminderChannelHealth)>
      _inspectChannelHealth() async {
    const unsupported =
        ReminderChannelHealth(ReminderChannelStatus.unsupported);
    const failed = ReminderChannelHealth(ReminderChannelStatus.queryFailed);
    if (defaultTargetPlatform != TargetPlatform.android) {
      return (unsupported, unsupported, unsupported);
    }

    final int? sdkInt;
    try {
      sdkInt = await _permissionsChannel.invokeMethod<int>('getAndroidSdkInt');
    } catch (_) {
      return (failed, failed, failed);
    }
    if (sdkInt == null) return (failed, failed, failed);
    if (sdkInt < 26) return (unsupported, unsupported, unsupported);

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return (failed, failed, failed);
    try {
      final channels = await android.getNotificationChannels();
      if (channels == null) return (failed, failed, failed);
      ReminderChannelHealth status(String id) {
        final channel = channels.where((item) => item.id == id).firstOrNull;
        if (channel == null) {
          return const ReminderChannelHealth(ReminderChannelStatus.missing);
        }
        return ReminderChannelHealth(
          channel.importance == Importance.none
              ? ReminderChannelStatus.disabled
              : ReminderChannelStatus.enabled,
          importance: channel.importance.value,
        );
      }

      return (
        status(assignmentChannel),
        status(summaryChannel),
        status(manualChannel),
      );
    } catch (_) {
      return (failed, failed, failed);
    }
  }

  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {
    lastWarning = null;
    try {
      await _ensurePluginInitialized();
      final offsets = ReminderRuleStore.normalizeOffsets(offsetsMinutes);
      final schedules = <(Assignment, int)>[];
      final seen = <String>{};
      for (final assignment in assignments.where((item) =>
          !item.isCompleted &&
          item.deadlineTrusted &&
          !item.deadlineReadFailed)) {
        for (final offset in offsets) {
          final at = assignment.deadlineAt?.subtract(Duration(minutes: offset));
          if (at == null || !at.isAfter(DateTime.now())) continue;
          if (!seen.add('${assignment.id}:$offset')) {
            throw StateError('作业提醒存在重复标识，请重新同步后重试');
          }
          schedules.add((assignment, offset));
        }
      }
      if (schedules.isNotEmpty) {
        await _ensureAndroidChannel(assignmentChannel);
      }
      await _replaceScheduleBatch(
        category: 'assignments',
        belongs: (payload) => payload?.startsWith('a:') ?? false,
        schedules: schedules,
        schedule: (id, item) {
          final (assignment, offset) = item as (Assignment, int);
          return _scheduleAssignmentReminder(assignment, offset, id);
        },
      );
    } catch (error) {
      lastWarning =
          _appendWarning(lastWarning, '提醒批次未能完整更新：$error；旧提醒已尽量保留，请重试');
    }
  }

  Future<void> _scheduleAssignmentReminder(
    Assignment assignment,
    int offset,
    int notificationId,
  ) async {
    final notifyAt = assignment.deadlineAt?.subtract(Duration(minutes: offset));
    if (notifyAt == null || notifyAt.difference(DateTime.now()).isNegative) {
      return;
    }
    await _zonedSchedule(
      id: notificationId,
      channelId: assignmentChannel,
      title: '作业即将截止',
      body: showDetails
          ? '${assignment.courseName} · ${assignment.title}，${formatDeadlineRemainingText(offset)}'
          : '有作业即将截止，请打开课业手记查看',
      notifyAt: notifyAt,
      payload:
          'a:studyassistant:///assignments/${Uri.encodeComponent(assignment.id)}',
    );
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) {
      return;
    }
    final routePayload =
        payload.startsWith('a:') ? payload.substring(2) : payload;
    final handler = _onPayload;
    if (handler == null) {
      _pendingPayload = routePayload;
      return;
    }
    handler(routePayload);
  }

  Future<void> _zonedSchedule({
    required int id,
    required String channelId,
    required String title,
    required String body,
    required DateTime notifyAt,
    required String payload,
  }) async {
    await _trySchedule(
      id: id,
      channelId: channelId,
      title: title,
      body: body,
      notifyAt: notifyAt,
      payload: payload,
      mode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> _trySchedule({
    required int id,
    required String channelId,
    required String title,
    required String body,
    required DateTime notifyAt,
    required String payload,
    required AndroidScheduleMode mode,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(notifyAt, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelId == manualChannel ? '个人待办与考试提醒' : '作业截止提醒',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            visibility: showDetails
                ? NotificationVisibility.public
                : NotificationVisibility.private,
            ticker: title,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentList: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.active,
          ),
        ),
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } catch (_) {
      if (mode == AndroidScheduleMode.exactAllowWhileIdle) {
        await _trySchedule(
          id: id,
          channelId: channelId,
          title: title,
          body: body,
          notifyAt: notifyAt,
          payload: payload,
          mode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        lastWarning = _appendWarning(lastWarning, '精确提醒不可用，已改为系统允许的近似时间提醒');
      } else {
        rethrow;
      }
    }
  }
}

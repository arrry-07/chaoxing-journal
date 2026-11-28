// Explicit receivers mark calls that must dispatch through the service class.
// ignore_for_file: unnecessary_this

part of 'local_notification_service.dart';

extension _LocalNotificationSchedulers on LocalNotificationService {
  Future<void> _rescheduleManual(List<ManualEntry> entries) async {
    lastWarning = null;
    lastManualNotice = null;
    lastScheduleOutcomes = const [];
    lastQuietHoursSkippedManualIds = const {};
    lastMissedWindowManualIds = const {};
    await _ensurePluginInitialized();
    final now = _clock();
    final schedules = <(ManualEntry, DateTime)>[];
    final validIds = <String>{};
    final quietHoursSkippedIds = <String>{};
    final missedWindowIds = <String>{};
    final seen = <String>{};
    for (final e in entries.where((e) => !e.done && e.remind && e.at != null)) {
      final rawAt = e.at!.subtract(const Duration(minutes: 30));
      if (!rawAt.isAfter(now)) {
        missedWindowIds.add(e.id);
        continue;
      }
      if (!seen.add(e.id)) {
        throw StateError('个人提醒存在重复标识，请修改后重试');
      }
      final at = DeadlineQuietHoursPolicy.adjustManualCandidate(
        candidateAt: rawAt,
        eventAt: e.at!,
        now: now,
        allowUrgentNightBreakthrough: allowUrgentNightBreakthrough,
        location: _location,
      );
      if (at == null) {
        quietHoursSkippedIds.add(e.id);
        continue;
      }
      validIds.add(e.id);
      schedules.add((e, at));
    }
    lastQuietHoursSkippedManualIds =
        Set<String>.unmodifiable(quietHoursSkippedIds);
    lastMissedWindowManualIds = Set<String>.unmodifiable(missedWindowIds);
    if (missedWindowIds.isNotEmpty) {
      lastManualNotice = '部分个人安排的提前30分钟提醒时间已过，本次未安排提醒；请调整时间或关闭提醒';
    }
    if (schedules.isNotEmpty) {
      await _ensureAndroidChannel(LocalNotificationService.manualV3Channel);
      if (defaultTargetPlatform == TargetPlatform.android) {
        // Scheduling can succeed even while Android suppresses delivery due
        // to the app permission or the user's channel setting. Surface that
        // distinction to the caller instead of reporting an unqualified save.
        final health = await this.inspectHealth();
        if (health.notifications == false) {
          lastWarning = NotificationSchedulePolicy.appendWarning(
              lastWarning, '系统通知权限已关闭，个人安排已保存，但系统不会显示提醒');
        } else if (health.notifications == null) {
          lastWarning = NotificationSchedulePolicy.appendWarning(
              lastWarning, '无法确认系统通知权限，请在提醒体检中检查');
        }
        final channelStatus = health.manualChannel?.status;
        if (channelStatus == ReminderChannelStatus.disabled) {
          lastWarning = NotificationSchedulePolicy.appendWarning(
              lastWarning, '个人日程通知渠道已被系统关闭，已保存的安排不会显示提醒');
        } else if (channelStatus == ReminderChannelStatus.missing ||
            channelStatus == ReminderChannelStatus.queryFailed) {
          lastWarning = NotificationSchedulePolicy.appendWarning(
              lastWarning, '无法确认个人日程通知渠道状态，请在提醒体检中检查');
        }
        if (health.exact == false) {
          lastWarning = NotificationSchedulePolicy.appendWarning(
              lastWarning, '系统未授予精确闹钟权限，个人提醒可能延迟触发');
        }
      }
    }
    try {
      final ids = await _replaceScheduleBatch(
        category: 'manual',
        belongs: (payload) => payload?.startsWith('p:') ?? false,
        retainOldPayload: (payload) {
          if (payload == null || !payload.startsWith('p:')) return false;
          return validIds.contains(payload.substring(2));
        },
        schedules: schedules,
        schedule: (id, item) {
          final (entry, at) = item as (ManualEntry, DateTime);
          final remainingMinutes =
              entry.at!.difference(at).inMinutes.clamp(1, 525600);
          return _zonedSchedule(
              id: id,
              channelId: LocalNotificationService.manualV3Channel,
              title: entry.kind == 'exam' ? '考试提醒' : '待办提醒',
              body: showDetails
                  ? '${entry.title} · $remainingMinutes分钟后到时，请核对个人安排'
                  : '有个人安排即将到时，请打开课业手记查看',
              notifyAt: at,
              payload: 'p:${entry.id}');
        },
      );
      lastScheduleOutcomes = [
        for (var index = 0; index < schedules.length; index++)
          ReminderScheduleOutcome(
            subjectKind: 'manual',
            subjectId: schedules[index].$1.id,
            logicalKey:
                'manual:${schedules[index].$1.id}:${schedules[index].$2.millisecondsSinceEpoch}',
            category: 'personal',
            stage: 'scheduled',
            observedAt: _clock(),
            scheduledAt: schedules[index].$2,
            notificationId: ids[index],
            expectedPayload: 'p:${schedules[index].$1.id}',
            evidenceState: 'confirmedScheduled',
          ),
      ];
    } catch (error) {
      lastWarning = NotificationSchedulePolicy.appendWarning(
          lastWarning, '个人日程提醒批次未能完成：$error');
      lastScheduleOutcomes = [
        for (final (entry, at) in schedules)
          ReminderScheduleOutcome(
            subjectKind: 'manual',
            subjectId: entry.id,
            logicalKey: 'manual:${entry.id}:${at.millisecondsSinceEpoch}',
            category: 'personal',
            stage: 'scheduleFailed',
            reasonCode: 'scheduleBatchFailed',
            observedAt: _clock(),
            scheduledAt: at,
            expectedPayload: 'p:${entry.id}',
            evidenceState: 'recoveryPending',
          ),
      ];
      rethrow;
    }
  }

  Future<bool> _showTestManualNotification({
    Duration delay = Duration.zero,
  }) =>
      _runScheduleMutation(() async {
        _pendingManualTestTimer?.cancel();
        _pendingManualTestTimer = null;
        try {
          await _ensureReadyForScheduling(
              LocalNotificationService.manualV3Channel);
          final health = await this.inspectHealth();
          final channelStatus = health.manualChannel?.status;
          if (health.notifications != true ||
              (channelStatus != ReminderChannelStatus.enabled &&
                  channelStatus != ReminderChannelStatus.unsupported)) {
            return false;
          }
          final details = NotificationDetails(
            android: _audibleAndroidDetails(
              channelId: LocalNotificationService.manualV3Channel,
              channelName: '待办与考试提醒',
              channelDescription: '待办和考试开始前提醒',
              ticker: '待办测试提醒',
            ),
          );
          if (delay <= Duration.zero) {
            await _plugin.show(
              DailySummary.baseId + 9,
              '待办测试提醒',
              '如果你能听到清铃提示音或看到通知横幅，待办与考试通知渠道工作正常。',
              details,
              payload: 't:manual-notification-test',
            );
          } else {
            late final Timer timer;
            timer = Timer(delay, () {
              if (identical(_pendingManualTestTimer, timer)) {
                _pendingManualTestTimer = null;
              }
              unawaited(
                _plugin
                    .show(
                      DailySummary.baseId + 9,
                      '待办测试提醒',
                      '如果你能听到清铃提示音或看到通知横幅，待办与考试通知渠道工作正常。',
                      details,
                      payload: 't:manual-notification-test',
                    )
                    .catchError((_) {}),
              );
            });
            _pendingManualTestTimer = timer;
          }
          return true;
        } on PlatformException catch (error) {
          debugPrint('[Notification] showTestManual: ${error.runtimeType}');
          return false;
        } on MissingPluginException catch (error) {
          debugPrint('[Notification] showTestManual: ${error.runtimeType}');
          return false;
        } on StateError catch (error) {
          debugPrint('[Notification] showTestManual: ${error.runtimeType}');
          return false;
        }
      });

  Future<bool> _showTestNotification() => _runScheduleMutation(() async {
        // Enqueue before initialization/health awaits so account/privacy cleanup
        // also retires a test notification whose display request is still in flight.
        try {
          final targetChannel =
              NotificationSchedulePolicy.normalizeDeadlineChannelId(
                      activeDeadlineChannelId) ??
                  LocalNotificationService.assignmentV3Channel;
          await _ensureReadyForScheduling(targetChannel);
          final health = await this.inspectHealth();
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
              NotificationDetails(
                  android: _audibleAndroidDetails(
                channelId: targetChannel,
                channelName:
                    NotificationSchedulePolicy.channelNameForId(targetChannel),
                ticker: '课业手记测试通知',
              )),
              payload: 't:notification-test');
          return true;
        } on PlatformException catch (error) {
          debugPrint('[Notification] showTest: ${error.runtimeType}');
          return false;
        } on MissingPluginException catch (error) {
          debugPrint('[Notification] showTest: ${error.runtimeType}');
          return false;
        } on StateError catch (error) {
          debugPrint('[Notification] showTest: ${error.runtimeType}');
          return false;
        }
      });

  Future<void> _rescheduleSummary(List<Assignment> assignments,
      PersonalWorkspace personal, DateTime? lastSync) async {
    lastWarning = null;
    lastScheduleOutcomes = const [];
    await _ensurePluginInitialized();
    final now = _clock();
    final desired = DailySummary.build(
      assignments,
      personal,
      now,
      lastSync,
      coursework: courseworkState,
    );
    if (desired.isNotEmpty) {
      await _ensureAndroidChannel(LocalNotificationService.summaryV3Channel);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final prior = _readSummaryEvidence(prefs);
      final ids = await _replaceScheduleBatch(
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
                  android: _audibleAndroidDetails(
                channelId: LocalNotificationService.summaryV3Channel,
                channelName: '每日课业摘要',
                channelDescription: '基于最近一次本机快照的课业摘要',
                ticker: '今日课业摘要',
              )),
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
              payload: 'd:summary');
        },
      );
      final desiredKeys = <String>{
        for (final notice in desired)
          'summary:${notice.at.millisecondsSinceEpoch}',
      };
      final observedAt = _clock();
      final cancellations = <ReminderScheduleOutcome>[
        for (final prev in prior)
          if (prev.scheduledAtMs > now.millisecondsSinceEpoch &&
              !desiredKeys.contains(prev.logicalKey))
            ReminderScheduleOutcome(
              subjectKind: 'summary',
              logicalKey: prev.logicalKey,
              category: 'summary',
              stage: 'cancelled',
              reasonCode: (!personal.summaryEnabled || desired.isEmpty)
                  ? 'reminderDisabled'
                  : 'scheduleReplaced',
              observedAt: observedAt,
              scheduledAt:
                  DateTime.fromMillisecondsSinceEpoch(prev.scheduledAtMs),
              notificationId: prev.notificationId,
              expectedPayload: 'd:summary',
              evidenceState: 'removed',
            ),
      ];
      final currentRecords = [
        for (var index = 0; index < desired.length; index++)
          {
            'logicalKey': 'summary:${desired[index].at.millisecondsSinceEpoch}',
            'scheduledAtMs': desired[index].at.millisecondsSinceEpoch,
            'notificationId': ids[index],
          },
      ];
      if (currentRecords.isEmpty) {
        await prefs.remove(LocalNotificationService._summaryEvidenceKey);
      } else {
        await prefs.setString(LocalNotificationService._summaryEvidenceKey,
            jsonEncode(currentRecords));
      }
      lastScheduleOutcomes = [
        ...cancellations,
        for (var index = 0; index < desired.length; index++)
          ReminderScheduleOutcome(
            subjectKind: 'summary',
            logicalKey: 'summary:${desired[index].at.millisecondsSinceEpoch}',
            category: 'summary',
            stage: 'scheduled',
            observedAt: observedAt,
            scheduledAt: desired[index].at,
            notificationId: ids[index],
            expectedPayload: 'd:summary',
            evidenceState: 'confirmedScheduled',
          ),
      ];
    } catch (error) {
      lastWarning = NotificationSchedulePolicy.appendWarning(
          lastWarning, '每日摘要提醒批次未能完成：$error');
      lastScheduleOutcomes = [
        for (final notice in desired)
          ReminderScheduleOutcome(
            subjectKind: 'summary',
            logicalKey: 'summary:${notice.at.millisecondsSinceEpoch}',
            category: 'summary',
            stage: 'scheduleFailed',
            reasonCode: 'scheduleBatchFailed',
            observedAt: _clock(),
            scheduledAt: notice.at,
            expectedPayload: 'd:summary',
            evidenceState: 'recoveryPending',
          ),
      ];
      rethrow;
    }
  }

  void _setPayloadHandler(NotificationPayloadHandler? onPayload) {
    _onPayload = onPayload;
    final pendingPayload = _pendingPayload;
    if (onPayload != null && pendingPayload != null) {
      _pendingPayload = null;
      onPayload(pendingPayload);
    }
  }

  Future<void> _initializeSafely(
      {NotificationPayloadHandler? onPayload}) async {
    try {
      await this.initialize(onPayload: onPayload);
    } catch (error) {
      debugPrint('[Notification] initialize: ${error.runtimeType}');
      lastWarning ??= '提醒初始化失败，请检查系统通知设置';
    }
  }

  Future<void> _initialize({NotificationPayloadHandler? onPayload}) async {
    if (onPayload != null) {
      this.setPayloadHandler(onPayload);
    }
    await _ensurePluginInitialized();
    final failures = <String>[];
    try {
      await _ensureAllAndroidChannels();
    } catch (error) {
      failures.add('渠道初始化：$error');
    }
    try {
      await this.recoverPendingSchedules();
    } catch (error) {
      failures.add('提醒事务恢复：$error');
    }
    if (failures.isNotEmpty) {
      lastWarning = failures.join('；');
      throw StateError(lastWarning!);
    }
    lastWarning = null;
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

  Future<void> _rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {
    lastWarning = null;
    lastDeadlineScheduleFailed = false;
    try {
      await _ensurePluginInitialized();
      final offsets = ReminderRuleStore.normalizeOffsets(offsetsMinutes);
      final schedules = <(Assignment, DateTime, int)>[];
      final seen = <String>{};
      final now = _clock();
      for (final assignment in assignments) {
        final snapshot = AssignmentReminderSnapshot(
          assignment: assignment,
          hidden: false,
          followed: true,
          courseworkEntry:
              CourseworkDeadline.entryFor(assignment, courseworkState),
        );
        if (!snapshot.eligibleAt(now)) continue;
        final source = snapshot.deadlineSource;
        if (source == DeadlineScheduleSource.unknown) continue;
        final anchor = snapshot.anchorAt;
        if (anchor == null || !anchor.isAfter(now)) continue;
        final slots = DeadlineQuietHoursPolicy.planDeadlineSlots(
          deadlineAt: anchor,
          now: now,
          offsetsMinutes: offsets,
          source: source,
          eventKind: snapshot.eventKind,
          allowUrgentNightBreakthrough: allowUrgentNightBreakthrough,
          location: _location,
        );
        for (final slot in slots) {
          final epochMs = slot.notifyAt.toUtc().millisecondsSinceEpoch;
          if (!seen.add('${assignment.id}:$epochMs')) {
            throw StateError('作业提醒存在重复标识，请重新同步后重试');
          }
          final remaining = anchor
              .toUtc()
              .difference(slot.notifyAt.toUtc())
              .inMinutes
              .clamp(1, 525600);
          schedules.add((assignment, slot.notifyAt, remaining));
        }
      }
      final targetDeadlineChannel =
          NotificationSchedulePolicy.normalizeDeadlineChannelId(
                  activeDeadlineChannelId) ??
              LocalNotificationService.assignmentV3Channel;
      if (schedules.isNotEmpty) {
        await _ensureAndroidChannel(targetDeadlineChannel);
      }
      await _replaceScheduleBatch(
        category: 'assignments',
        belongs: (payload) => payload?.startsWith('a:') ?? false,
        schedules: schedules,
        schedule: (id, item) {
          final (assignment, notifyAt, remainingMinutes) =
              item as (Assignment, DateTime, int);
          return _scheduleAssignmentReminder(
            assignment,
            notifyAt,
            remainingMinutes,
            id,
            channelId: targetDeadlineChannel,
          );
        },
      );
    } catch (error) {
      lastDeadlineScheduleFailed = true;
      lastWarning = NotificationSchedulePolicy.appendWarning(
          lastWarning, '提醒批次未能完整更新：$error；旧提醒已尽量保留，请重试');
    }
  }

  Future<void> _scheduleAssignmentReminder(
    Assignment assignment,
    DateTime notifyAt,
    int remainingMinutes,
    int notificationId, {
    String channelId = LocalNotificationService.assignmentV3Channel,
  }) async {
    if (!notifyAt.toUtc().isAfter(_clock().toUtc())) {
      return;
    }
    await _zonedSchedule(
      id: notificationId,
      channelId: channelId,
      title: assignment.isExam ? '考试即将开考' : '作业即将截止',
      body: showDetails
          ? '${assignment.courseName} · ${assignment.title}，${LocalNotificationService.formatDeadlineRemainingText(remainingMinutes, examStart: assignment.isExam)}'
          : assignment.isExam
              ? '有考试即将开考，请打开课业手记查看'
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
          android: _audibleAndroidDetails(
            channelId: channelId,
            channelName: NotificationSchedulePolicy.channelNameForId(channelId),
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
    } on PlatformException catch (error) {
      debugPrint('[Notification] schedule: ${error.runtimeType}');
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
        lastWarning = NotificationSchedulePolicy.appendWarning(
            lastWarning, '精确提醒不可用，已改为系统允许的近似时间提醒');
      } else {
        rethrow;
      }
    }
  }
}

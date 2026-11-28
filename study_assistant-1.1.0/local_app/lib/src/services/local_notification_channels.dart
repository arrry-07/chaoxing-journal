// Explicit receivers mark calls that must dispatch through the service class.
// ignore_for_file: unnecessary_this

part of 'local_notification_service.dart';

AndroidNotificationChannel _buildAudibleChannel(
  String id,
  String name,
  String description,
) =>
    AndroidNotificationChannel(
      id,
      name,
      description: description,
      importance: Importance.high,
      playSound: true,
      sound: LocalNotificationService.chimeSound,
      audioAttributesUsage: AudioAttributesUsage.notification,
      enableVibration: true,
      vibrationPattern: LocalNotificationService.defaultVibrationPattern,
      showBadge: true,
    );

List<AndroidNotificationChannel> _buildAndroidChannels() => [
      _buildAudibleChannel(
        LocalNotificationService.assignmentV3Channel,
        '作业截止提醒',
        '学习通作业截止与考试开考提醒',
      ),
      _buildAudibleChannel(
        LocalNotificationService.assignmentUpdatesV3Channel,
        '新增作业提醒',
        '学习通新增作业与考试有声提醒',
      ),
      _buildAudibleChannel(
        LocalNotificationService.summaryV3Channel,
        '每日课业摘要',
        '基于最近一次本机快照的课业摘要',
      ),
      _buildAudibleChannel(
        LocalNotificationService.manualV3Channel,
        '待办与考试提醒',
        '待办和考试开始前提醒',
      ),
    ];

Map<String, AndroidNotificationChannel> _buildExtraChannels() => {
      LocalNotificationService.assignmentChannel:
          const AndroidNotificationChannel(
        LocalNotificationService.assignmentChannel,
        '作业截止提醒',
        description: '学习通作业截止前提醒',
        importance: Importance.high,
      ),
      LocalNotificationService.assignmentV2Channel: _buildAudibleChannel(
        LocalNotificationService.assignmentV2Channel,
        '作业截止提醒',
        '学习通作业截止与考试开考提醒',
      ),
      LocalNotificationService.assignmentUpdatesChannel:
          const AndroidNotificationChannel(
        LocalNotificationService.assignmentUpdatesChannel,
        '作业变化提醒',
        description: '学习通正式作业新增提醒',
        importance: Importance.defaultImportance,
      ),
      LocalNotificationService.assignmentUpdatesV2Channel: _buildAudibleChannel(
        LocalNotificationService.assignmentUpdatesV2Channel,
        '新增作业提醒',
        '学习通新增作业与考试有声提醒',
      ),
      LocalNotificationService.summaryChannel: const AndroidNotificationChannel(
        LocalNotificationService.summaryChannel,
        '每日课业摘要',
        description: '基于最近一次本机快照的课业摘要',
        importance: Importance.defaultImportance,
      ),
      LocalNotificationService.summaryV2Channel: _buildAudibleChannel(
        LocalNotificationService.summaryV2Channel,
        '每日课业摘要',
        '基于最近一次本机快照的课业摘要',
      ),
      LocalNotificationService.manualChannel: const AndroidNotificationChannel(
        LocalNotificationService.manualChannel,
        '待办与考试提醒',
        description: '待办和考试开始前提醒',
        importance: Importance.high,
      ),
      LocalNotificationService.manualV2Channel: _buildAudibleChannel(
        LocalNotificationService.manualV2Channel,
        '待办与考试提醒',
        '待办和考试开始前提醒',
      ),
      LocalNotificationService.assignmentSilentChannel:
          const AndroidNotificationChannel(
        LocalNotificationService.assignmentSilentChannel,
        '静默作业通知',
        description: '未知截止时间的新增作业静默提示',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
    };

AndroidNotificationDetails _audibleAndroidDetails({
  required String channelId,
  required String channelName,
  String? channelDescription,
  String? ticker,
}) =>
    AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: LocalNotificationService.chimeSound,
      audioAttributesUsage: AudioAttributesUsage.notification,
      enableVibration: true,
      vibrationPattern: LocalNotificationService.defaultVibrationPattern,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.private,
      onlyAlertOnce: false,
      ticker: ticker,
    );

extension _LocalNotificationChannels on LocalNotificationService {
  AndroidNotificationChannel? _channelForId(String channelId) {
    for (final channel in LocalNotificationService._androidChannels) {
      if (channel.id == channelId) return channel;
    }
    return LocalNotificationService._extraChannels[channelId];
  }

  Future<String> _resolveDefaultDeadlineChannel(
      {String? storedChannelId}) async {
    final explicit =
        NotificationSchedulePolicy.normalizeDeadlineChannelId(storedChannelId);
    if (explicit != null) return explicit;
    return LocalNotificationService.assignmentV3Channel;
  }

  Future<NotificationChimePreviewResult> _previewNotificationChime() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const NotificationChimePreviewResult(
        played: false,
        supported: false,
      );
    }
    try {
      final raw = await LocalNotificationService._permissionsChannel
          .invokeMethod<Object?>('previewNotificationChime');
      if (raw is! Map<Object?, Object?>) {
        return const NotificationChimePreviewResult(
          played: false,
          supported: false,
        );
      }
      return NotificationChimePreviewResult(
        played: raw['played'] == true,
        supported: true,
        notificationStreamVolume:
            (raw['notificationStreamVolume'] as num?)?.toInt(),
        notificationStreamMaxVolume:
            (raw['notificationStreamMaxVolume'] as num?)?.toInt(),
        notificationStreamMuted: raw['notificationStreamMuted'] as bool?,
        ringerMode: raw['ringerMode'] as String?,
        interruptionFilter: raw['interruptionFilter'] as String?,
      );
    } on MissingPluginException {
      return const NotificationChimePreviewResult(
        played: false,
        supported: false,
      );
    } on PlatformException {
      return const NotificationChimePreviewResult(
        played: false,
        supported: false,
      );
    } on TypeError {
      return const NotificationChimePreviewResult(
        played: false,
        supported: false,
      );
    }
  }

  Future<ReminderHealth> _inspectHealth() async {
    final errors = <String>[];
    final scheduleRecoveryPending = await _healthQuery(
          _readScheduleRecovery,
          errors,
          '提醒排期恢复状态读取失败',
        ) ??
        true;
    final nativeDetails = await _readNativeHealthDetails();
    final channels = await _inspectChannelHealth(errors, nativeDetails);
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final allowed = android == null
        ? null
        : await _healthQuery(
            android.areNotificationsEnabled, errors, '通知权限读取失败');
    final exact = android == null
        ? null
        : await _healthQuery(
            android.canScheduleExactNotifications, errors, '精确闹钟权限读取失败');
    final pending = await _healthQuery(
      _plugin.pendingNotificationRequests,
      errors,
      '系统待投递提醒读取失败',
    );
    return ReminderHealth(
        notifications: allowed,
        exact: exact,
        assignmentChannel: channels.activeDeadline,
        assignmentUpdatesChannel: channels.updates,
        summaryChannel: channels.summary,
        manualChannel: channels.manual,
        activeDeadlineChannelId: activeDeadlineChannelId,
        legacyDeadlineChannel: channels.legacyV1,
        v2DeadlineChannel: channels.v2,
        v3DeadlineChannel: channels.v3,
        silentChannel: channels.silent,
        ignoringBatteryOptimizations:
            nativeDetails?['ignoringBatteryOptimizations'] as bool?,
        lockscreenShowNotifications:
            nativeDetails?['lockscreenShowNotifications'] as bool?,
        ringerMode: nativeDetails?['ringerMode'] as String?,
        interruptionFilter: nativeDetails?['interruptionFilter'] as String?,
        notificationStreamVolume:
            (nativeDetails?['notificationStreamVolume'] as num?)?.toInt(),
        notificationStreamMaxVolume:
            (nativeDetails?['notificationStreamMaxVolume'] as num?)?.toInt(),
        notificationStreamMuted:
            nativeDetails?['notificationStreamMuted'] as bool?,
        lockscreenAllowPrivateNotifications:
            nativeDetails?['lockscreenAllowPrivateNotifications'] as bool?,
        pending:
            pending?.where((n) => n.payload?.startsWith('a:') ?? false).length,
        summaryPending: pending?.where((n) => n.payload == 'd:summary').length,
        manualPending:
            pending?.where((n) => n.payload?.startsWith('p:') ?? false).length,
        scheduleRecoveryPending: scheduleRecoveryPending,
        queryErrors: List.unmodifiable(errors));
  }

  Future<Map<Object?, Object?>?> _readNativeHealthDetails() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final raw = await LocalNotificationService._permissionsChannel
          .invokeMethod<Object?>('inspectNotificationHealthDetails');
      return raw is Map<Object?, Object?> ? raw : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<T?> _healthQuery<T>(
    Future<T?> Function() read,
    List<String> errors,
    String message,
  ) async {
    try {
      final value = await read();
      if (value == null) errors.add(message);
      return value;
    } catch (error) {
      errors.add(message);
      debugPrint('[ReminderHealth] $message (${error.runtimeType})');
      return null;
    }
  }

  Future<void> _migrateLegacyManualChannelIfNeeded(
    List<ManualEntry> entries,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final (:android, :existingIds) = await _readExistingAndroidChannelIds();
    if (android == null || existingIds == null) return;
    final legacyIds = [
      if (existingIds.contains(LocalNotificationService.manualChannel))
        LocalNotificationService.manualChannel,
      if (existingIds.contains(LocalNotificationService.manualV2Channel))
        LocalNotificationService.manualV2Channel,
    ];
    if (legacyIds.isEmpty) return;
    await _ensureAndroidChannel(LocalNotificationService.manualV3Channel);
    await this.rescheduleManual(entries);
    for (final legacyId in legacyIds) {
      await _retireLegacyChannel(android, legacyId);
    }
  }

  Future<void> _migrateLegacySummaryChannelIfNeeded(
    List<Assignment> assignments,
    PersonalWorkspace personal,
    DateTime? lastSync,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final (:android, :existingIds) = await _readExistingAndroidChannelIds();
    if (android == null || existingIds == null) return;
    final legacyIds = [
      if (existingIds.contains(LocalNotificationService.summaryChannel))
        LocalNotificationService.summaryChannel,
      if (existingIds.contains(LocalNotificationService.summaryV2Channel))
        LocalNotificationService.summaryV2Channel,
    ];
    if (legacyIds.isEmpty) return;
    await _ensureAndroidChannel(LocalNotificationService.summaryV3Channel);
    await this.rescheduleSummary(assignments, personal, lastSync);
    for (final legacyId in legacyIds) {
      await _retireLegacyChannel(android, legacyId);
    }
  }

  Future<void> _retireLegacyUpdatesAndDeadlineChannelsIfNeeded({
    required bool retireDeadlineV1,
    Future<bool> Function()? beforeRetireDeadlineV1,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final (:android, :existingIds) = await _readExistingAndroidChannelIds();
    if (android == null || existingIds == null) return;
    final legacyUpdateIds = [
      if (existingIds
          .contains(LocalNotificationService.assignmentUpdatesChannel))
        LocalNotificationService.assignmentUpdatesChannel,
      if (existingIds
          .contains(LocalNotificationService.assignmentUpdatesV2Channel))
        LocalNotificationService.assignmentUpdatesV2Channel,
    ];
    if (legacyUpdateIds.isNotEmpty) {
      await _ensureAndroidChannel(
          LocalNotificationService.assignmentUpdatesV3Channel);
      for (final legacyId in legacyUpdateIds) {
        await _retireLegacyChannel(android, legacyId);
      }
    }
    final legacyDeadlineIds = [
      if (existingIds.contains(LocalNotificationService.assignmentChannel))
        LocalNotificationService.assignmentChannel,
      if (existingIds.contains(LocalNotificationService.assignmentV2Channel))
        LocalNotificationService.assignmentV2Channel,
    ];
    if (retireDeadlineV1 && legacyDeadlineIds.isNotEmpty) {
      await _ensureAndroidChannel(LocalNotificationService.assignmentV3Channel);
      if (beforeRetireDeadlineV1 != null) {
        final readyToRetire = await beforeRetireDeadlineV1();
        if (!readyToRetire) return;
      }
      for (final legacyId in legacyDeadlineIds) {
        await _retireLegacyChannel(android, legacyId);
      }
    }
  }

  Future<
      ({
        AndroidFlutterLocalNotificationsPlugin? android,
        Set<String>? existingIds,
      })> _readExistingAndroidChannelIds() async {
    try {
      await _ensurePluginInitialized();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return (android: null, existingIds: null);
      final existing = await android.getNotificationChannels();
      if (existing == null) return (android: android, existingIds: null);
      return (
        android: android,
        existingIds: {for (final item in existing) item.id},
      );
    } on MissingPluginException {
      return (android: null, existingIds: null);
    } on UnimplementedError {
      return (android: null, existingIds: null);
    } on Error catch (error) {
      // Unmocked headless host unit tests never run Android's registerWith(),
      // leaving flutter_local_notifications' late _instance uninitialized.
      if (error.toString().startsWith('LateInitializationError:')) {
        return (android: null, existingIds: null);
      }
      rethrow;
    }
  }

  Future<bool> _requestNotificationsPermission() async {
    await _ensurePluginInitialized();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    return await android.requestNotificationsPermission() ?? false;
  }

  Future<void> _ensureAllAndroidChannels() async {
    final failures = <String>[];
    for (final channel in LocalNotificationService._androidChannels) {
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
    final channel = _channelForId(channelId);
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
    if (existing.any((item) => item.id == channel.id)) {
      return;
    }
    await android.createNotificationChannel(channel);
  }

  Future<void> _retireLegacyChannel(
    AndroidFlutterLocalNotificationsPlugin android,
    String channelId,
  ) async {
    try {
      await android.deleteNotificationChannel(channelId);
    } catch (_) {
      // Legacy channel retirement is best-effort for older Android/mock plugins.
    }
  }

  Future<
      ({
        ReminderChannelHealth activeDeadline,
        ReminderChannelHealth updates,
        ReminderChannelHealth summary,
        ReminderChannelHealth manual,
        ReminderChannelHealth legacyV1,
        ReminderChannelHealth v2,
        ReminderChannelHealth v3,
        ReminderChannelHealth silent,
      })> _inspectChannelHealth(
    List<String> errors,
    Map<Object?, Object?>? nativeDetails,
  ) async {
    const unsupported =
        ReminderChannelHealth(ReminderChannelStatus.unsupported);
    const failed = ReminderChannelHealth(ReminderChannelStatus.queryFailed);
    if (defaultTargetPlatform != TargetPlatform.android) {
      return (
        activeDeadline: unsupported,
        updates: unsupported,
        summary: unsupported,
        manual: unsupported,
        legacyV1: unsupported,
        v2: unsupported,
        v3: unsupported,
        silent: unsupported,
      );
    }

    final sdkInt = await _healthQuery(
      () => LocalNotificationService._permissionsChannel
          .invokeMethod<int>('getAndroidSdkInt'),
      errors,
      'Android 系统版本读取失败',
    );
    if (sdkInt == null) {
      return (
        activeDeadline: failed,
        updates: failed,
        summary: failed,
        manual: failed,
        legacyV1: failed,
        v2: failed,
        v3: failed,
        silent: failed,
      );
    }
    if (sdkInt < 26) {
      return (
        activeDeadline: unsupported,
        updates: unsupported,
        summary: unsupported,
        manual: unsupported,
        legacyV1: unsupported,
        v2: unsupported,
        v3: unsupported,
        silent: unsupported,
      );
    }

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      errors.add('通知渠道状态读取失败');
      return (
        activeDeadline: failed,
        updates: failed,
        summary: failed,
        manual: failed,
        legacyV1: failed,
        v2: failed,
        v3: failed,
        silent: failed,
      );
    }
    final channels = await _healthQuery(
      android.getNotificationChannels,
      errors,
      '通知渠道状态读取失败',
    );
    if (channels == null) {
      return (
        activeDeadline: failed,
        updates: failed,
        summary: failed,
        manual: failed,
        legacyV1: failed,
        v2: failed,
        v3: failed,
        silent: failed,
      );
    }
    final detailChannels = nativeDetails?['channels'] as Map<Object?, Object?>?;
    ReminderChannelHealth status(String id) {
      final rawDetail = detailChannels?[id] as Map<Object?, Object?>?;
      final channel = channels.where((item) => item.id == id).firstOrNull;
      if (channel == null) {
        return ReminderChannelHealth(
          ReminderChannelStatus.missing,
          channelId: rawDetail == null ? null : id,
        );
      }
      return ReminderChannelHealth(
        channel.importance == Importance.none
            ? ReminderChannelStatus.disabled
            : ReminderChannelStatus.enabled,
        importance: channel.importance.value,
        channelId: rawDetail == null ? null : id,
        soundMuted: rawDetail?['soundMuted'] as bool?,
        customSound: rawDetail?['customSound'] as bool?,
        vibrationEnabled: rawDetail?['vibrationEnabled'] as bool?,
        lockscreenVisibility:
            (rawDetail?['lockscreenVisibility'] as num?)?.toInt(),
      );
    }

    final targetDeadlineId =
        NotificationSchedulePolicy.normalizeDeadlineChannelId(
                activeDeadlineChannelId) ??
            LocalNotificationService.assignmentV3Channel;
    return (
      activeDeadline: status(targetDeadlineId),
      updates: status(LocalNotificationService.assignmentUpdatesV3Channel),
      summary: status(LocalNotificationService.summaryV3Channel),
      manual: status(LocalNotificationService.manualV3Channel),
      legacyV1: status(LocalNotificationService.assignmentChannel),
      v2: status(LocalNotificationService.assignmentV2Channel),
      v3: status(LocalNotificationService.assignmentV3Channel),
      silent: status(LocalNotificationService.assignmentSilentChannel),
    );
  }
}

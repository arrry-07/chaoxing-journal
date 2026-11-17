import 'dart:async';

import 'package:flutter/services.dart';

import '../models/reminder_history.dart';
import 'assignment_reminder_planner.dart';
import 'background_check_settings.dart';

/// A native reminder operation failed after the bridge was reported available.
/// Critical callers must surface this instead of treating a missing result as
/// success (notably [BackgroundReminderGateway.isSessionCurrent] and
/// [BackgroundReminderGateway.applyPlan]).
class BackgroundReminderGatewayException implements Exception {
  const BackgroundReminderGatewayException(this.method, this.cause);

  final String method;
  final Object cause;

  @override
  String toString() => '后台提醒操作失败（$method）：$cause';
}

enum BackgroundSyncTrigger {
  manual,
  daytime,
  notificationSignal,
  foregroundDue,
}

enum NotificationRemoteAuthorization {
  granted,
  outsideWindow,
  stale,
}

class NotificationRemoteStartContext {
  const NotificationRemoteStartContext({
    required this.accountHash,
    required this.sessionEpoch,
    required this.claimToken,
    required this.workerId,
  });

  final String accountHash;
  final int sessionEpoch;
  final String claimToken;
  final String workerId;
}

class SyncLeaseResult {
  const SyncLeaseResult({
    required this.acquired,
    required this.waited,
    required this.lastAttemptAt,
    required this.lastFullSuccessAt,
  });

  final bool acquired;
  final bool waited;
  final DateTime? lastAttemptAt;
  final DateTime? lastFullSuccessAt;
}

class ReminderPlanState {
  const ReminderPlanState({
    required this.accountHash,
    required this.sessionEpoch,
    required this.baselineCompleted,
    required this.knownAssignmentIds,
    required this.sentNewAssignmentIds,
    required this.lastAttemptAt,
    required this.lastFullSuccessAt,
    required this.pendingUpdate,
    required this.mutationVersion,
    Set<String>? baselinedSources,
  }) : baselinedSources = baselinedSources ??
            (baselineCompleted ? const {'courseWork'} : const {});

  final String accountHash;
  final int sessionEpoch;
  final bool baselineCompleted;
  final Set<String> baselinedSources;
  final Set<String> knownAssignmentIds;
  final Set<String> sentNewAssignmentIds;
  final DateTime? lastAttemptAt;
  final DateTime? lastFullSuccessAt;
  final bool pendingUpdate;
  final int mutationVersion;
}

class ReminderPlanApplyResult {
  const ReminderPlanApplyResult({
    required this.scheduledDeadlineCount,
    required this.pendingNewCount,
    required this.warning,
  });

  final int scheduledDeadlineCount;
  final int pendingNewCount;
  final String? warning;
}

class BackgroundReminderHealth {
  const BackgroundReminderHealth({
    required this.backgroundEnabled,
    required this.intervalMinutes,
    required this.newAssignmentReminderEnabled,
    required this.notificationListenerEnabled,
    required this.notificationListenerGranted,
    required this.nextCheckAt,
    required this.pendingNewCount,
    required this.pendingDeadlineCount,
    required this.baselineCompleted,
    required this.pendingSignalCount,
    required this.migrationPending,
    required this.lastFailure,
  });

  final bool backgroundEnabled;
  final int intervalMinutes;
  final bool newAssignmentReminderEnabled;
  final bool notificationListenerEnabled;
  final bool notificationListenerGranted;
  final DateTime? nextCheckAt;
  final int pendingNewCount;
  final int pendingDeadlineCount;
  final bool baselineCompleted;
  final int pendingSignalCount;
  final bool migrationPending;
  final String? lastFailure;
}

class BackgroundReminderGateway {
  const BackgroundReminderGateway({
    MethodChannel channel =
        const MethodChannel('study_assistant/background_reminders'),
    this.operationTimeout = const Duration(seconds: 10),
    this.syncLeaseTimeout = const Duration(seconds: 130),
    this.writeLeaseTimeout = const Duration(seconds: 65),
  }) : _channel = channel;

  final MethodChannel _channel;
  final Duration operationTimeout;
  final Duration syncLeaseTimeout;
  final Duration writeLeaseTimeout;

  // Keep the const gateway usable in default arguments. Only acknowledged write
  // grants are retained, and failed releases stay here so they can be retried.
  static final _writeRequests = Expando<Map<String, List<String>>>();
  static int _requestSequence = 0;
  Map<String, List<String>> get _confirmedWrites =>
      _writeRequests[this] ??= <String, List<String>>{};

  Future<bool> isAvailable() async =>
      await _invokeTimed<bool>('ping', null, const Duration(seconds: 2)) ??
      false;

  Future<int> ensureActiveAccount(String accountHash) =>
      _epoch('ensureActiveAccount', {'accountHash': accountHash});

  Future<int> switchAccount({
    required String? previousAccountHash,
    required String accountHash,
  }) =>
      _epoch('switchAccount', {
        'previousAccountHash': previousAccountHash,
        'accountHash': accountHash,
      });

  Future<int> rotateSessionEpoch(String accountHash) =>
      _epoch('rotateSessionEpoch', {'accountHash': accountHash});

  Future<int> clearActiveAccount(String accountHash) =>
      _epoch('clearActiveAccount', {'accountHash': accountHash});

  Future<int> _epoch(String method, Map<String, Object?> arguments) async {
    final epoch = await _invokeStrict<Object>(method, arguments);
    if (epoch is! int || epoch <= 0) {
      throw BackgroundReminderGatewayException(method, '原生会话代次无效');
    }
    return epoch;
  }

  Future<bool> isSessionCurrent(
    String accountHash,
    int sessionEpoch,
  ) async =>
      await _invoke<bool>('isSessionCurrent', {
        'accountHash': accountHash,
        'sessionEpoch': sessionEpoch,
      }) ??
      false;

  Future<void> updateSettings(
    String accountHash,
    int sessionEpoch,
    BackgroundCheckSettings settings, {
    required bool showDetails,
    bool reconcileSchedules = true,
  }) async {
    await _invokeStrictVoid('updateSettings', {
      'accountHash': accountHash,
      'sessionEpoch': sessionEpoch,
      ...settings.toJson(),
      'showDetails': showDetails,
      'reconcileSchedules': reconcileSchedules,
    });
  }

  Future<void> reconcileDaytimeSchedule({
    required DateTime? targetAt,
    required bool enabled,
    required int intervalMinutes,
  }) async {
    await _invokeStrictVoid('reconcileDaytimeSchedule', {
      'targetAt': targetAt?.toUtc().toIso8601String(),
      'enabled': enabled,
      'intervalMinutes': intervalMinutes,
    });
  }

  Future<SyncLeaseResult> acquireSyncLease({
    required String accountHash,
    required String requestId,
    required DateTime requestedAt,
  }) async {
    final arguments = <String, Object?>{
      'accountHash': accountHash,
      'requestId': requestId,
      'requestedAt': requestedAt.toUtc().toIso8601String(),
    };
    try {
      final value = await _invokeStrict<Map<Object?, Object?>>(
        'acquireSyncLease',
        arguments,
        timeout: syncLeaseTimeout,
      );
      if (value['acquired'] is! bool || value['waited'] is! bool) {
        throw const BackgroundReminderGatewayException(
            'acquireSyncLease', '原生租约结果无效');
      }
      if (value['acquired'] == true &&
          !await _invokeStrict<bool>('confirmSyncLease', arguments)) {
        throw const BackgroundReminderGatewayException(
            'confirmSyncLease', '原生租约未确认');
      }
      return SyncLeaseResult(
        acquired: value['acquired'] == true,
        waited: value['waited'] == true,
        lastAttemptAt: _date(value['lastAttemptAt']),
        lastFullSuccessAt: _date(value['lastFullSuccessAt']),
      );
    } catch (error, stack) {
      await _cancelUncertainAcquisition(
          'cancelSyncLeaseAcquisition', arguments, error);
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> releaseSyncLease({
    required String accountHash,
    required String requestId,
  }) async {
    await _invokeStrictVoid('releaseSyncLease', {
      'accountHash': accountHash,
      'requestId': requestId,
    });
  }

  Future<bool> acquireWriteLease(String owner) async {
    final requestId = 'dart-${DateTime.now().microsecondsSinceEpoch}-'
        '${_requestSequence++}';
    final arguments = <String, Object?>{'owner': owner, 'requestId': requestId};
    try {
      final acquired = await _invokeStrict<bool>(
        'acquireWriteLease',
        arguments,
        timeout: writeLeaseTimeout,
      );
      if (!acquired) return false;
      if (!await _invokeStrict<bool>('confirmWriteLease', arguments)) {
        throw const BackgroundReminderGatewayException(
            'confirmWriteLease', '原生租约未确认');
      }
      (_confirmedWrites[owner] ??= []).add(requestId);
      return true;
    } catch (error, stack) {
      await _cancelUncertainAcquisition(
          'cancelWriteLeaseAcquisition', arguments, error);
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> releaseWriteLease(String owner) async {
    final requests = _confirmedWrites[owner];
    if (requests == null || requests.isEmpty) {
      throw const BackgroundReminderGatewayException(
          'releaseWriteLease', '没有可释放的已确认写租约');
    }
    final requestId = requests.last;
    await _invokeStrictVoid('releaseWriteLease', {
      'owner': owner,
      'requestId': requestId,
    });
    requests.removeLast();
    if (requests.isEmpty) _confirmedWrites.remove(owner);
  }

  Future<void> _cancelUncertainAcquisition(
    String method,
    Map<String, Object?> arguments,
    Object primaryError,
  ) async {
    try {
      await _invokeStrictVoid(method, arguments);
    } catch (cleanupError) {
      throw BackgroundReminderGatewayException(
          method, '租约状态未确认；取得失败：$primaryError；取消失败：$cleanupError');
    }
  }

  Future<ReminderPlanState> loadPlanState({
    required String accountHash,
    required int sessionEpoch,
  }) async {
    final value = await _invokeStrict<Map<Object?, Object?>>('loadPlanState', {
      'accountHash': accountHash,
      'sessionEpoch': sessionEpoch,
    });
    return ReminderPlanState(
      accountHash: accountHash,
      sessionEpoch: sessionEpoch,
      baselineCompleted: value['baselineCompleted'] == true,
      baselinedSources: value.containsKey('baselinedSources')
          ? _strings(value['baselinedSources'])
          : null,
      knownAssignmentIds: _strings(value['knownAssignmentIds']),
      sentNewAssignmentIds: _strings(value['sentNewAssignmentIds']),
      lastAttemptAt: _date(value['lastAttemptAt']),
      lastFullSuccessAt: _date(value['lastFullSuccessAt']),
      pendingUpdate: value['pendingUpdate'] == true,
      mutationVersion: value['mutationVersion'] as int? ?? 0,
    );
  }

  Future<void> markPendingUpdate({
    required String accountHash,
    required int sessionEpoch,
  }) async {
    await _invokeStrictVoid('markPendingUpdate', {
      'accountHash': accountHash,
      'sessionEpoch': sessionEpoch,
    });
  }

  Future<NotificationRemoteAuthorization> authorizeNotificationRemoteStart(
    NotificationRemoteStartContext context,
  ) async {
    final value = await _invokeStrict<String>(
      'authorizeNotificationRemoteStart',
      {
        'accountHash': context.accountHash,
        'sessionEpoch': context.sessionEpoch,
        'claimToken': context.claimToken,
        'workerId': context.workerId,
      },
    );
    return switch (value) {
      'granted' => NotificationRemoteAuthorization.granted,
      'outsideWindow' => NotificationRemoteAuthorization.outsideWindow,
      'stale' => NotificationRemoteAuthorization.stale,
      _ => throw const BackgroundReminderGatewayException(
          'authorizeNotificationRemoteStart', '原生授权结果无效'),
    };
  }

  Future<ReminderHistoryControl> getReminderHistoryControl({
    String? accountHash,
    int? sessionEpoch,
  }) async {
    final value = await _invokeHistory<Map<Object?, Object?>>(
      'getReminderHistoryControl',
      {
        if (accountHash != null) 'accountHash': accountHash,
        if (sessionEpoch != null) 'sessionEpoch': sessionEpoch,
      },
    );
    final generation = _requiredNonNegativeInt(
      value['historyGeneration'],
      'historyGeneration',
    );
    final recording = value['recordingEnabled'];
    final ownerMatches = value['ownerMatches'];
    final purgePending = value['purgePending'];
    if (recording is! bool || ownerMatches is! bool || purgePending is! bool) {
      throw const ReminderHistoryException(
        'invalid_history_argument',
        '原生提醒历史控制结果不完整',
      );
    }
    return ReminderHistoryControl(
      historyGeneration: generation,
      recordingEnabled: recording,
      ownerMatches: ownerMatches,
      purgePending: purgePending,
      purgeToken: value['purgeToken'] as String?,
    );
  }

  Future<ReminderObservationContext> acquireReminderObservationContext({
    required String accountHash,
    required int sessionEpoch,
  }) async {
    final value = await _invokeHistory<Map<Object?, Object?>>(
      'acquireReminderObservationContext',
      {'accountHash': accountHash, 'sessionEpoch': sessionEpoch},
    );
    return _readObservationContext(value);
  }

  Future<String> appendReminderObservation({
    required ReminderObservationContext context,
    required ReminderObservation observation,
  }) async {
    final value = await _invokeHistory<String>(
      'appendReminderObservation',
      {
        'context': context.toJson(),
        'observation': observation.toJson(),
      },
    );
    if (!const {'inserted', 'duplicate', 'expired', 'stale', 'unavailable'}
        .contains(value)) {
      throw const ReminderHistoryException(
        'invalid_history_argument',
        '原生提醒记录写入结果无效',
      );
    }
    return value;
  }

  Future<ReminderScheduleOutcomeResult> recordReminderScheduleOutcome({
    required ReminderObservationContext context,
    required List<ReminderScheduleOutcome> outcomes,
  }) async {
    final value = await _invokeHistory<Map<Object?, Object?>>(
      'recordReminderScheduleOutcome',
      {
        'context': context.toJson(),
        'outcomes': outcomes.map((item) => item.toJson()).toList(),
      },
    );
    int read(String key) => _requiredNonNegativeInt(value[key], key);
    return ReminderScheduleOutcomeResult(
      evidenceUpdated: read('evidenceUpdated'),
      evidenceIgnored: read('evidenceIgnored'),
      inserted: read('inserted'),
      duplicate: read('duplicate'),
      expired: read('expired'),
      warning: value['warning'] as String?,
    );
  }

  Future<ReminderHistoryPage> listReminderHistory({
    required ReminderObservationContext context,
    int? snapshotMaxId,
    int? beforeId,
    String? category,
    List<ReminderSubjectRef> subjectRefs = const [],
  }) async {
    if ((snapshotMaxId != null && snapshotMaxId <= 0) ||
        (beforeId != null && beforeId <= 0)) {
      throw const ReminderHistoryException(
        'invalid_history_argument',
        '提醒记录游标必须为正整数',
      );
    }
    final value = await _invokeHistory<Map<Object?, Object?>>(
      'listReminderHistory',
      {
        'context': context.toJson(),
        if (snapshotMaxId != null) 'snapshotMaxId': snapshotMaxId,
        if (beforeId != null) 'beforeId': beforeId,
        if (category != null) 'category': category,
        if (subjectRefs.isNotEmpty)
          'subjectRefs': subjectRefs
              .map((item) => {
                    'kind': item.kind,
                    if (item.id != null) 'id': item.id,
                  })
              .toList(),
      },
    );
    final items = value['items'];
    if (items is! List) {
      throw const ReminderHistoryException(
        'invalid_history_argument',
        '原生提醒记录列表无效',
      );
    }
    return ReminderHistoryPage(
      items: items
          .whereType<Map<Object?, Object?>>()
          .map(_readHistoryItem)
          .toList(),
      snapshotMaxId:
          _requiredNonNegativeInt(value['snapshotMaxId'], 'snapshotMaxId'),
      nextBeforeId: (value['nextBeforeId'] as num?)?.toInt(),
      checkedAt: _requiredDate(value['checkedAt'], 'checkedAt'),
      historyGeneration: _requiredNonNegativeInt(
          value['historyGeneration'], 'historyGeneration'),
    );
  }

  Future<ReminderSubjectEvidence> inspectReminderSubjects({
    required ReminderObservationContext context,
    required List<ReminderSubjectRef> subjectRefs,
  }) async {
    final value = await _invokeHistory<Map<Object?, Object?>>(
      'inspectReminderSubjects',
      {
        'context': context.toJson(),
        'subjectRefs': subjectRefs
            .map((item) => {
                  'kind': item.kind,
                  if (item.id != null) 'id': item.id,
                })
            .toList(),
      },
    );
    final native = value['nativeEvents'];
    final plugin = value['pluginEvidence'];
    if (native is! List || plugin is! List) {
      throw const ReminderHistoryException(
        'invalid_history_argument',
        '原生提醒证据结果无效',
      );
    }
    return ReminderSubjectEvidence(
      checkedAt: _requiredDate(value['checkedAt'], 'checkedAt'),
      nativeEvents: native
          .whereType<Map<Object?, Object?>>()
          .map(_readNativeEvidence)
          .toList(),
      pluginEvidence: plugin
          .whereType<Map<Object?, Object?>>()
          .map(_readPluginEvidence)
          .toList(),
      queryWarnings:
          (value['queryWarnings'] as List?)?.whereType<String>().toList() ??
              const [],
      historyGeneration: _requiredNonNegativeInt(
          value['historyGeneration'], 'historyGeneration'),
    );
  }

  Future<ReminderHistoryLogoutStart> beginReminderHistoryLogout({
    required int expectedHistoryGeneration,
    required String requestId,
    required String accountHash,
    required int sessionEpoch,
  }) async {
    final value = await _invokeHistory<Map<Object?, Object?>>(
      'beginReminderHistoryLogout',
      {
        'expectedHistoryGeneration': expectedHistoryGeneration,
        'requestId': requestId,
        'accountHash': accountHash,
        'sessionEpoch': sessionEpoch,
      },
    );
    final token = value['purgeToken'];
    final state = value['state'];
    if (state != 'pending' || token is! String || token.isEmpty) {
      throw const ReminderHistoryException(
        'invalid_history_argument',
        '原生提醒历史退出结果无效',
      );
    }
    return ReminderHistoryLogoutStart(
      historyGeneration: _requiredNonNegativeInt(
          value['historyGeneration'], 'historyGeneration'),
      purgeToken: token,
    );
  }

  Future<ReminderHistoryLogoutFinish> finishReminderHistoryLogout(
    String purgeToken,
  ) async {
    final value = await _invokeHistory<Map<Object?, Object?>>(
      'finishReminderHistoryLogout',
      {'purgeToken': purgeToken},
    );
    if (value['cleared'] != true) {
      throw const ReminderHistoryException(
        'invalid_history_argument',
        '原生提醒历史清理结果无效',
      );
    }
    return ReminderHistoryLogoutFinish(
      cleared: true,
      historyGeneration: _requiredNonNegativeInt(
          value['historyGeneration'], 'historyGeneration'),
    );
  }

  Future<int> enableReminderHistorySession({
    required String accountHash,
    required int sessionEpoch,
    required int expectedHistoryGeneration,
  }) async {
    final value = await _invokeHistory<Map<Object?, Object?>>(
      'enableReminderHistorySession',
      {
        'accountHash': accountHash,
        'sessionEpoch': sessionEpoch,
        'expectedHistoryGeneration': expectedHistoryGeneration,
      },
    );
    if (value['recordingEnabled'] != true) {
      throw const ReminderHistoryException(
        'invalid_history_argument',
        '原生提醒历史启用结果无效',
      );
    }
    return _requiredNonNegativeInt(
      value['historyGeneration'],
      'historyGeneration',
    );
  }

  Future<ReminderPlanApplyResult> applyPlan({
    required String accountHash,
    required int sessionEpoch,
    required AssignmentReminderPlan plan,
    required DateTime completedAt,
    required String? failure,
    required bool syncCompleted,
    required int expectedMutationVersion,
  }) async {
    final value = await _invokeStrict<Map<Object?, Object?>>('applyPlan', {
      'accountHash': accountHash,
      'sessionEpoch': sessionEpoch,
      'completedAt': completedAt.toUtc().toIso8601String(),
      'failure': failure,
      'syncCompleted': syncCompleted,
      'expectedMutationVersion': expectedMutationVersion,
      'baselineCompleted': plan.baselineCompleted,
      'baselinedSources': plan.baselinedSources.toList(),
      'knownAssignmentIds': plan.knownAssignmentIds.toList(),
      'snapshots': plan.snapshotJson,
      'events': plan.eventJson,
    });
    return ReminderPlanApplyResult(
      scheduledDeadlineCount: value['scheduledDeadlineCount'] as int? ?? 0,
      pendingNewCount: value['pendingNewCount'] as int? ?? 0,
      warning: value['warning'] as String?,
    );
  }

  Future<void> recordAttempt({
    required String accountHash,
    required int sessionEpoch,
    required DateTime attemptedAt,
    required bool dataSucceeded,
    required bool fullSucceeded,
    required String? failure,
  }) async {
    await _invokeStrictVoid('recordAttempt', {
      'accountHash': accountHash,
      'sessionEpoch': sessionEpoch,
      'attemptedAt': attemptedAt.toUtc().toIso8601String(),
      'dataSucceeded': dataSucceeded,
      'fullSucceeded': fullSucceeded,
      'failure': failure,
    });
  }

  Future<BackgroundReminderHealth> inspectHealth({
    required String accountHash,
    required int sessionEpoch,
  }) async {
    final value = await _invokeStrict<Map<Object?, Object?>>('inspectHealth', {
      'accountHash': accountHash,
      'sessionEpoch': sessionEpoch,
    });
    for (final key in [
      'backgroundEnabled',
      'newAssignmentReminderEnabled',
      'notificationListenerEnabled',
      'notificationListenerGranted',
      'baselineCompleted',
      'migrationPending',
    ]) {
      if (value[key] is! bool) {
        throw const BackgroundReminderGatewayException(
            'inspectHealth', '原生体检结果不完整');
      }
    }
    for (final key in [
      'intervalMinutes',
      'pendingNewCount',
      'pendingDeadlineCount',
      'pendingSignalCount'
    ]) {
      if (value[key] is! int || (value[key] as int) < 0) {
        throw const BackgroundReminderGatewayException(
            'inspectHealth', '原生体检计数无效');
      }
    }
    return BackgroundReminderHealth(
      backgroundEnabled: value['backgroundEnabled'] as bool,
      intervalMinutes: value['intervalMinutes'] as int,
      newAssignmentReminderEnabled:
          value['newAssignmentReminderEnabled'] as bool,
      notificationListenerEnabled: value['notificationListenerEnabled'] as bool,
      notificationListenerGranted: value['notificationListenerGranted'] as bool,
      nextCheckAt: _date(value['nextCheckAt']),
      pendingNewCount: value['pendingNewCount'] as int,
      pendingDeadlineCount: value['pendingDeadlineCount'] as int,
      baselineCompleted: value['baselineCompleted'] as bool,
      pendingSignalCount: value['pendingSignalCount'] as int,
      migrationPending: value['migrationPending'] as bool,
      lastFailure: value['lastFailure'] as String?,
    );
  }

  Future<void> cancelAssignmentReminders(String accountHash) async {
    await _invokeStrictVoid(
        'cancelAssignmentReminders', {'accountHash': accountHash});
  }

  Future<void> cancelAssignmentDeliveryKeepEvents(String accountHash) async {
    await _invokeStrictVoid(
      'cancelAssignmentDeliveryKeepEvents',
      {'accountHash': accountHash},
    );
  }

  Future<void> consumeNotificationSignal({
    required String accountHash,
    required int version,
  }) async {
    await _invokeStrictVoid('consumeNotificationSignal', {
      'accountHash': accountHash,
      'version': version,
    });
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? arguments]) =>
      _invokeTimed<T>(method, arguments, const Duration(seconds: 10));

  /// Critical reminder operations must not degrade a failed platform call into
  /// a successful-looking empty result. Callers gate this method behind
  /// [isAvailable]; once the bridge is expected, any failure (including a
  /// missing plugin) is surfaced as [BackgroundReminderGatewayException].
  Future<T> _invokeStrict<T>(
    String method,
    Map<String, Object?>? arguments, {
    Duration? timeout,
  }) async {
    try {
      final value = await _channel
          .invokeMethod<T>(method, arguments)
          .timeout(timeout ?? operationTimeout);
      if (value == null) {
        throw BackgroundReminderGatewayException(method, '原生通道未返回结果');
      }
      return value;
    } on BackgroundReminderGatewayException {
      rethrow;
    } on MissingPluginException catch (error) {
      throw BackgroundReminderGatewayException(method, error);
    } on PlatformException catch (error) {
      throw BackgroundReminderGatewayException(
          method, error.message ?? error.code);
    } on TimeoutException catch (error) {
      throw BackgroundReminderGatewayException(method, error);
    } catch (error) {
      throw BackgroundReminderGatewayException(method, error);
    }
  }

  // A void MethodChannel operation normally succeeds with a null reply. Only
  // transport completion is evidence here; data operations use _invokeStrict.
  Future<void> _invokeStrictVoid(
    String method,
    Map<String, Object?>? arguments,
  ) async {
    try {
      await _channel
          .invokeMethod<void>(method, arguments)
          .timeout(operationTimeout);
    } catch (error) {
      throw BackgroundReminderGatewayException(method, error);
    }
  }

  Future<T?> _invokeTimed<T>(
    String method,
    Map<String, Object?>? arguments,
    Duration timeout,
  ) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments).timeout(timeout);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      // Pure unit tests and desktop platforms may not initialize a binary
      // messenger. Native delivery is an enhancement there; local plugin
      // fallback remains responsible for reminders.
      return null;
    }
  }

  Future<T> _invokeHistory<T>(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final value = await _channel
          .invokeMethod<T>(method, arguments)
          .timeout(operationTimeout);
      if (value == null) {
        throw ReminderHistoryException(
          'history_unavailable',
          '原生提醒历史通道未返回结果（$method）',
        );
      }
      return value;
    } on ReminderHistoryException {
      rethrow;
    } on MissingPluginException catch (error) {
      throw ReminderHistoryException('history_unavailable', '$error');
    } on PlatformException catch (error) {
      throw ReminderHistoryException(
        error.code,
        error.message ?? error.code,
      );
    } on TimeoutException catch (error) {
      throw ReminderHistoryException('history_unavailable', '$error');
    } catch (error) {
      throw ReminderHistoryException('history_unavailable', '$error');
    }
  }

  static ReminderObservationContext _readObservationContext(
    Map<Object?, Object?> value,
  ) {
    final accountHash = value['accountHash'];
    if (accountHash is! String || accountHash.isEmpty) {
      throw const ReminderHistoryException(
        'invalid_history_argument',
        '提醒记录上下文缺少账号',
      );
    }
    return ReminderObservationContext(
      accountHash: accountHash,
      sessionEpoch:
          _requiredNonNegativeInt(value['sessionEpoch'], 'sessionEpoch'),
      historyGeneration: _requiredNonNegativeInt(
          value['historyGeneration'], 'historyGeneration'),
      operationSequence: _requiredNonNegativeInt(
          value['operationSequence'], 'operationSequence'),
    );
  }

  static ReminderHistoryItem _readHistoryItem(Map<Object?, Object?> value) {
    final category = value['category'];
    final stage = value['stage'];
    final subjectKind = value['subjectKind'];
    final logicalKey = value['logicalKey'];
    final observationId = value['observationId'];
    if (category is! String ||
        stage is! String ||
        subjectKind is! String ||
        logicalKey is! String ||
        observationId is! String) {
      throw const ReminderHistoryException(
        'invalid_history_argument',
        '提醒记录条目字段无效',
      );
    }
    return ReminderHistoryItem(
      id: _requiredNonNegativeInt(value['id'], 'id'),
      observationId: observationId,
      operationSequence: _requiredNonNegativeInt(
          value['operationSequence'], 'operationSequence'),
      subjectKind: subjectKind,
      subjectId: value['subjectId'] as String?,
      logicalKey: logicalKey,
      category: category,
      stage: stage,
      reasonCode: value['reasonCode'] as String?,
      observedAt: _requiredDate(value['observedAt'], 'observedAt'),
      scheduledAt: _optionalDate(value['scheduledAt']),
      notificationId: (value['notificationId'] as num?)?.toInt(),
      batchKey: value['batchKey'] as String?,
    );
  }

  static ReminderNativeSubjectEvidence _readNativeEvidence(
    Map<Object?, Object?> value,
  ) {
    final subjectKind = value['subjectKind'];
    final subjectId = value['subjectId'];
    final eventId = value['eventId'];
    final category = value['category'];
    final logicalKey = value['logicalKey'];
    final state = value['state'];
    if (subjectKind is! String ||
        subjectId is! String ||
        eventId is! String ||
        category is! String ||
        logicalKey is! String ||
        state is! String) {
      throw const ReminderHistoryException(
        'invalid_history_argument',
        '原生提醒证据字段无效',
      );
    }
    return ReminderNativeSubjectEvidence(
      subjectKind: subjectKind,
      subjectId: subjectId,
      eventId: eventId,
      category: category,
      logicalKey: logicalKey,
      state: state,
      scheduledAt: _optionalDate(value['scheduledAt']),
      notificationId: (value['notificationId'] as num?)?.toInt(),
      evidenceAt: _optionalDate(value['evidenceAt']),
    );
  }

  static ReminderPluginSubjectEvidence _readPluginEvidence(
    Map<Object?, Object?> value,
  ) {
    final subjectKind = value['subjectKind'];
    final subjectId = value['subjectId'];
    final logicalKey = value['logicalKey'];
    final category = value['category'];
    final state = value['state'];
    if (subjectKind is! String ||
        logicalKey is! String ||
        category is! String ||
        state is! String) {
      throw const ReminderHistoryException(
        'invalid_history_argument',
        '插件提醒证据字段无效',
      );
    }
    return ReminderPluginSubjectEvidence(
      subjectKind: subjectKind,
      subjectId: subjectId is String ? subjectId : '',
      logicalKey: logicalKey,
      category: category,
      state: state,
      scheduledAt: _optionalDate(value['scheduledAt']),
      notificationId: (value['notificationId'] as num?)?.toInt(),
      expectedPayload: value['expectedPayload'] as String?,
      evidenceAt: _optionalDate(value['evidenceAt']),
    );
  }

  static int _requiredNonNegativeInt(Object? value, String field) {
    if (value is int && value >= 0) return value;
    if (value is num && value >= 0) return value.toInt();
    throw ReminderHistoryException(
      'invalid_history_argument',
      '提醒记录字段 $field 无效',
    );
  }

  static DateTime _requiredDate(Object? value, String field) {
    final date = _optionalDate(value);
    if (date == null) {
      throw ReminderHistoryException(
        'invalid_history_argument',
        '提醒记录时间 $field 无效',
      );
    }
    return date;
  }

  static DateTime? _optionalDate(Object? value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true)
          .toLocal();
    }
    if (value is String) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }

  static Set<String> _strings(Object? value) =>
      value is List ? value.whereType<String>().toSet() : <String>{};

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

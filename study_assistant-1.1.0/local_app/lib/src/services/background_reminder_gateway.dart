import 'dart:async';

import 'package:flutter/services.dart';

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
  });

  final String accountHash;
  final int sessionEpoch;
  final bool baselineCompleted;
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
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<bool> isAvailable() async =>
      await _invokeTimed<bool>('ping', null, const Duration(seconds: 2)) ??
      false;

  Future<int> ensureActiveAccount(String accountHash) async =>
      await _invoke<int>('ensureActiveAccount', {'accountHash': accountHash}) ??
      0;

  Future<int> switchAccount({
    required String? previousAccountHash,
    required String accountHash,
  }) async =>
      await _invoke<int>('switchAccount', {
        'previousAccountHash': previousAccountHash,
        'accountHash': accountHash,
      }) ??
      0;

  Future<int> rotateSessionEpoch(String accountHash) async =>
      await _invoke<int>('rotateSessionEpoch', {'accountHash': accountHash}) ??
      0;

  Future<int> clearActiveAccount(String accountHash) async =>
      await _invoke<int>('clearActiveAccount', {'accountHash': accountHash}) ??
      0;

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
  }) async {
    await _invoke<void>('updateSettings', {
      'accountHash': accountHash,
      'sessionEpoch': sessionEpoch,
      ...settings.toJson(),
      'showDetails': showDetails,
    });
  }

  Future<void> reconcileDaytimeSchedule({
    required DateTime? targetAt,
    required bool enabled,
    required int intervalMinutes,
  }) async {
    await _invoke<void>('reconcileDaytimeSchedule', {
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
    final value = await _invokeTimed<Map<Object?, Object?>>(
      'acquireSyncLease',
      {
        'accountHash': accountHash,
        'requestId': requestId,
        'requestedAt': requestedAt.toUtc().toIso8601String(),
      },
      const Duration(seconds: 130),
    );
    return SyncLeaseResult(
      acquired: value?['acquired'] == true,
      waited: value?['waited'] == true,
      lastAttemptAt: _date(value?['lastAttemptAt']),
      lastFullSuccessAt: _date(value?['lastFullSuccessAt']),
    );
  }

  Future<void> releaseSyncLease({
    required String accountHash,
    required String requestId,
  }) async {
    await _invoke<void>('releaseSyncLease', {
      'accountHash': accountHash,
      'requestId': requestId,
    });
  }

  Future<bool> acquireWriteLease(String owner) async {
    return await _invokeTimed<bool>(
          'acquireWriteLease',
          {'owner': owner},
          const Duration(seconds: 65),
        ) ??
        false;
  }

  Future<void> releaseWriteLease(String owner) async {
    await _invoke<void>('releaseWriteLease', {'owner': owner});
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
    await _invoke<void>('markPendingUpdate', {
      'accountHash': accountHash,
      'sessionEpoch': sessionEpoch,
    });
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
    await _invoke<void>('recordAttempt', {
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
    final value = await _invoke<Map<Object?, Object?>>('inspectHealth', {
      'accountHash': accountHash,
      'sessionEpoch': sessionEpoch,
    });
    return BackgroundReminderHealth(
      backgroundEnabled: value?['backgroundEnabled'] == true,
      intervalMinutes: value?['intervalMinutes'] as int? ?? 240,
      newAssignmentReminderEnabled:
          value?['newAssignmentReminderEnabled'] == true,
      notificationListenerEnabled:
          value?['notificationListenerEnabled'] == true,
      notificationListenerGranted:
          value?['notificationListenerGranted'] == true,
      nextCheckAt: _date(value?['nextCheckAt']),
      pendingNewCount: value?['pendingNewCount'] as int? ?? 0,
      pendingDeadlineCount: value?['pendingDeadlineCount'] as int? ?? 0,
      baselineCompleted: value?['baselineCompleted'] == true,
      pendingSignalCount: value?['pendingSignalCount'] as int? ?? 0,
      migrationPending: value?['migrationPending'] == true,
      lastFailure: value?['lastFailure'] as String?,
    );
  }

  Future<void> cancelAssignmentReminders(String accountHash) async {
    await _invoke<void>(
        'cancelAssignmentReminders', {'accountHash': accountHash});
  }

  Future<void> cancelAssignmentDeliveryKeepEvents(String accountHash) async {
    await _invoke<void>(
      'cancelAssignmentDeliveryKeepEvents',
      {'accountHash': accountHash},
    );
  }

  Future<void> consumeNotificationSignal({
    required String accountHash,
    required int version,
  }) async {
    await _invoke<void>('consumeNotificationSignal', {
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
    Map<String, Object?>? arguments,
  ) async {
    try {
      final value = await _channel
          .invokeMethod<T>(method, arguments)
          .timeout(const Duration(seconds: 10));
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

  static Set<String> _strings(Object? value) =>
      value is List ? value.whereType<String>().toSet() : <String>{};

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

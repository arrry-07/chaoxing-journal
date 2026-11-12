import 'dart:async';

import 'package:flutter/services.dart';
import 'package:study_assistant_mobile/src/services/background_check_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/services/assignment_reminder_planner.dart';
import 'package:study_assistant_mobile/src/services/background_reminder_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('study_assistant/background_reminders');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
          code: 'native_failure', message: 'synthetic failure');
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('strictVoidAllowsSuccessfulNullReply', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    const gateway = BackgroundReminderGateway();
    await gateway.updateSettings(
        'hash',
        1,
        const BackgroundCheckSettings(
          enabled: true,
          intervalMinutes: 240,
          notificationListenerEnabled: false,
          newAssignmentReminderEnabled: true,
          migratedFromLegacy: false,
        ),
        showDetails: false);
    await gateway.markPendingUpdate(accountHash: 'hash', sessionEpoch: 1);
    await gateway.cancelAssignmentDeliveryKeepEvents('hash');
    await gateway.reconcileDaytimeSchedule(
      targetAt: null,
      enabled: false,
      intervalMinutes: 240,
    );
  });

  test('criticalControlsNeverSwallowNativeFailures', () async {
    const gateway = BackgroundReminderGateway();
    for (final operation in <Future<Object?> Function()>[
      () => gateway.ensureActiveAccount('hash'),
      () =>
          gateway.switchAccount(previousAccountHash: null, accountHash: 'hash'),
      () => gateway.clearActiveAccount('hash'),
      () => gateway.markPendingUpdate(accountHash: 'hash', sessionEpoch: 1),
      () => gateway.cancelAssignmentDeliveryKeepEvents('hash'),
      () => gateway.reconcileDaytimeSchedule(
            targetAt: null,
            enabled: false,
            intervalMinutes: 240,
          ),
    ]) {
      await expectLater(
          operation(), throwsA(isA<BackgroundReminderGatewayException>()));
    }
  });

  test('accountEpochMustBePositive', () async {
    const gateway = BackgroundReminderGateway();
    for (final result in <Object?>[null, 0, -1, '1']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => result);
      await expectLater(gateway.ensureActiveAccount('hash'),
          throwsA(isA<BackgroundReminderGatewayException>()));
      await expectLater(
          gateway.switchAccount(previousAccountHash: null, accountHash: 'hash'),
          throwsA(isA<BackgroundReminderGatewayException>()));
    }
  });

  test('syncLeaseMustBeConfirmedBeforeBusinessReceivesIt', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'acquireSyncLease') {
        return {
          'acquired': true,
          'waited': false,
          'lastAttemptAt': null,
          'lastFullSuccessAt': null,
        };
      }
      if (call.method == 'confirmSyncLease') return false;
      return null;
    });
    const gateway = BackgroundReminderGateway();
    await expectLater(
        gateway.acquireSyncLease(
          accountHash: 'hash',
          requestId: 'request',
          requestedAt: DateTime.now(),
        ),
        throwsA(isA<BackgroundReminderGatewayException>()));
    expect(calls,
        ['acquireSyncLease', 'confirmSyncLease', 'cancelSyncLeaseAcquisition']);
  });

  test('timedOutAcquisitionCancelsItsRequestAndNeverConfirmsLateGrant',
      () async {
    final grant = Completer<Object?>();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'acquireSyncLease') return grant.future;
      return null;
    });
    const gateway =
        BackgroundReminderGateway(syncLeaseTimeout: Duration(milliseconds: 1));
    await expectLater(
        gateway.acquireSyncLease(
          accountHash: 'hash',
          requestId: 'late',
          requestedAt: DateTime.now(),
        ),
        throwsA(isA<BackgroundReminderGatewayException>()));
    grant.complete({'acquired': true, 'waited': false});
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((call) => call.method),
        ['acquireSyncLease', 'cancelSyncLeaseAcquisition']);
    expect((calls.last.arguments as Map)['requestId'], 'late');
  });

  test('cancellationFailureIsReportedAsUnconfirmedLeaseState', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'cancelWriteLeaseAcquisition') {
        throw PlatformException(code: 'cancel_failed');
      }
      if (call.method == 'confirmWriteLease') return false;
      return true;
    });
    const gateway = BackgroundReminderGateway();
    await expectLater(
        gateway.acquireWriteLease('owner'),
        throwsA(
            predicate((Object error) => error.toString().contains('租约状态未确认'))));
  });

  test('writeLeaseReentryReleasesOnlyConfirmedRequestInLifoOrder', () async {
    final acquired = <String>[];
    final released = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final arguments = call.arguments as Map;
      if (call.method == 'acquireWriteLease') {
        acquired.add(arguments['requestId'] as String);
      }
      if (call.method == 'releaseWriteLease') {
        released.add(arguments['requestId'] as String);
        return null;
      }
      return true;
    });
    const gateway = BackgroundReminderGateway();
    expect(await gateway.acquireWriteLease('reentrant-owner'), isTrue);
    expect(await gateway.acquireWriteLease('reentrant-owner'), isTrue);
    await gateway.releaseWriteLease('reentrant-owner');
    await gateway.releaseWriteLease('reentrant-owner');
    expect(acquired.toSet(), hasLength(2));
    expect(released, acquired.reversed.toList());
  });

  test('nativeHealthFailureNeverFabricatesZeroCounts', () async {
    const gateway = BackgroundReminderGateway();
    await expectLater(
        gateway.inspectHealth(accountHash: 'hash', sessionEpoch: 1),
        throwsA(isA<BackgroundReminderGatewayException>()));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => <String, Object?>{});
    await expectLater(
        gateway.inspectHealth(accountHash: 'hash', sessionEpoch: 1),
        throwsA(isA<BackgroundReminderGatewayException>()));
  });

  test('strictVoidAllowsSuccessfulNullReply', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    const gateway = BackgroundReminderGateway();
    await gateway.updateSettings(
        'hash',
        1,
        const BackgroundCheckSettings(
            enabled: true,
            intervalMinutes: 240,
            notificationListenerEnabled: false,
            newAssignmentReminderEnabled: true,
            migratedFromLegacy: false),
        showDetails: false);
    await gateway.markPendingUpdate(accountHash: 'hash', sessionEpoch: 1);
    await gateway.cancelAssignmentDeliveryKeepEvents('hash');
    await gateway.reconcileDaytimeSchedule(
        targetAt: null, enabled: false, intervalMinutes: 240);
  });

  test('criticalControlsSurfaceNativeFailure', () async {
    const gateway = BackgroundReminderGateway();
    for (final operation in <Future<Object?> Function()>[
      () => gateway.ensureActiveAccount('hash'),
      () =>
          gateway.switchAccount(previousAccountHash: null, accountHash: 'hash'),
      () => gateway.clearActiveAccount('hash'),
      () => gateway.updateSettings(
          'hash',
          1,
          const BackgroundCheckSettings(
              enabled: true,
              intervalMinutes: 240,
              notificationListenerEnabled: false,
              newAssignmentReminderEnabled: true,
              migratedFromLegacy: false),
          showDetails: false),
      () => gateway.markPendingUpdate(accountHash: 'hash', sessionEpoch: 1),
      () => gateway.cancelAssignmentDeliveryKeepEvents('hash'),
      () => gateway.reconcileDaytimeSchedule(
          targetAt: null, enabled: false, intervalMinutes: 240),
      () => gateway.releaseSyncLease(accountHash: 'hash', requestId: 'request'),
    ]) {
      await expectLater(
          operation(), throwsA(isA<BackgroundReminderGatewayException>()));
    }
  });

  test('accountEpochMustBePositive', () async {
    const gateway = BackgroundReminderGateway();
    for (final epoch in <Object?>[null, 0, -1, '1']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => epoch);
      await expectLater(gateway.ensureActiveAccount('hash'),
          throwsA(isA<BackgroundReminderGatewayException>()));
      await expectLater(
          gateway.switchAccount(previousAccountHash: null, accountHash: 'hash'),
          throwsA(isA<BackgroundReminderGatewayException>()));
    }
  });

  test('nativeHealthFailureNeverFabricatesZeroCounts', () async {
    const gateway = BackgroundReminderGateway();
    await expectLater(
        gateway.inspectHealth(accountHash: 'hash', sessionEpoch: 1),
        throwsA(isA<BackgroundReminderGatewayException>()));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => <String, Object?>{});
    await expectLater(
        gateway.inspectHealth(accountHash: 'hash', sessionEpoch: 1),
        throwsA(isA<BackgroundReminderGatewayException>()));
  });

  test('syncLeaseRequiresConfirmationAndCancelsFailedConfirmation', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'acquireSyncLease') {
        return {'acquired': true, 'waited': false};
      }
      if (call.method == 'confirmSyncLease') return false;
      return null;
    });
    const gateway = BackgroundReminderGateway();
    await expectLater(
        gateway.acquireSyncLease(
            accountHash: 'hash',
            requestId: 'request',
            requestedAt: DateTime.now()),
        throwsA(isA<BackgroundReminderGatewayException>()));
    expect(calls,
        ['acquireSyncLease', 'confirmSyncLease', 'cancelSyncLeaseAcquisition']);
  });

  test('timedOutAcquisitionCancelsBeforeLateGrant', () async {
    final acquired = Completer<Object?>();
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      calls.add(call.method);
      if (call.method == 'acquireSyncLease') return acquired.future;
      return Future<Object?>.value(null);
    });
    const gateway =
        BackgroundReminderGateway(syncLeaseTimeout: Duration(milliseconds: 10));
    await expectLater(
        gateway.acquireSyncLease(
            accountHash: 'hash',
            requestId: 'timeout',
            requestedAt: DateTime.now()),
        throwsA(isA<BackgroundReminderGatewayException>()));
    acquired.complete({'acquired': true, 'waited': false});
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['acquireSyncLease', 'cancelSyncLeaseAcquisition']);
  });

  test('failedAcquisitionCancellationRemainsExplicitlyUnconfirmed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'acquireSyncLease') {
        return {'acquired': true, 'waited': false};
      }
      throw PlatformException(code: 'cleanup_failed');
    });
    const gateway = BackgroundReminderGateway();
    await expectLater(
        gateway.acquireSyncLease(
            accountHash: 'hash',
            requestId: 'request',
            requestedAt: DateTime.now()),
        throwsA(predicate<Object>((error) =>
            error is BackgroundReminderGatewayException &&
            error.toString().contains('租约状态未确认'))));
  });

  test('writeLeaseReentryReleasesExactConfirmedRequestsInReverseOrder',
      () async {
    final requests = <String>[];
    final releases = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      if (call.method == 'acquireWriteLease') {
        requests.add(args['requestId'] as String);
        return true;
      }
      if (call.method == 'confirmWriteLease') {
        expect(requests, contains(args['requestId']));
        return true;
      }
      if (call.method == 'releaseWriteLease') {
        releases.add(args['requestId'] as String);
      }
      return null;
    });
    const gateway = BackgroundReminderGateway();
    expect(await gateway.acquireWriteLease('reentrant'), isTrue);
    expect(await gateway.acquireWriteLease('reentrant'), isTrue);
    expect(requests.toSet(), hasLength(2));
    await gateway.releaseWriteLease('reentrant');
    await gateway.releaseWriteLease('reentrant');
    expect(releases, requests.reversed.toList());
    await expectLater(gateway.releaseWriteLease('reentrant'),
        throwsA(isA<BackgroundReminderGatewayException>()));
  });

  test('failedWriteReleaseKeepsRequestForRetry', () async {
    final requests = <String>[];
    var fail = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'acquireWriteLease' ||
          call.method == 'confirmWriteLease') {
        return true;
      }
      requests.add((call.arguments as Map)['requestId'] as String);
      if (fail) throw PlatformException(code: 'release_failed');
      return null;
    });
    const gateway = BackgroundReminderGateway();
    await gateway.acquireWriteLease('retry');
    await expectLater(gateway.releaseWriteLease('retry'),
        throwsA(isA<BackgroundReminderGatewayException>()));
    fail = false;
    await gateway.releaseWriteLease('retry');
    expect(requests, hasLength(2));
    expect(requests.first, requests.last);
  });

  test('isSessionCurrent fails closed when the native call fails', () async {
    const gateway = BackgroundReminderGateway();
    expect(await gateway.isSessionCurrent('hash', 1), isFalse);
  });

  test('loadPlanState surfaces a native failure', () async {
    const gateway = BackgroundReminderGateway();
    await expectLater(
      gateway.loadPlanState(accountHash: 'hash', sessionEpoch: 1),
      throwsA(isA<BackgroundReminderGatewayException>()),
    );
  });

  test('applyPlan surfaces a native failure instead of zero counts', () async {
    const gateway = BackgroundReminderGateway();
    await expectLater(
      gateway.applyPlan(
        accountHash: 'hash',
        sessionEpoch: 1,
        plan: const AssignmentReminderPlan(
          snapshots: <AssignmentReminderSnapshot>[],
          newEvents: <AssignmentReminderEvent>[],
          deadlineEvents: <AssignmentReminderEvent>[],
          knownAssignmentIds: <String>{},
          baselineCompleted: false,
        ),
        completedAt: DateTime.utc(2026, 1, 1),
        failure: null,
        syncCompleted: false,
        expectedMutationVersion: 0,
      ),
      throwsA(isA<BackgroundReminderGatewayException>()),
    );
  });

  test('applyPlan surfaces a missing native result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    const gateway = BackgroundReminderGateway();
    await expectLater(
      gateway.applyPlan(
        accountHash: 'hash',
        sessionEpoch: 1,
        plan: const AssignmentReminderPlan(
          snapshots: <AssignmentReminderSnapshot>[],
          newEvents: <AssignmentReminderEvent>[],
          deadlineEvents: <AssignmentReminderEvent>[],
          knownAssignmentIds: <String>{},
          baselineCompleted: false,
        ),
        completedAt: DateTime.utc(2026, 1, 1),
        failure: null,
        syncCompleted: false,
        expectedMutationVersion: 0,
      ),
      throwsA(isA<BackgroundReminderGatewayException>()),
    );
  });
}

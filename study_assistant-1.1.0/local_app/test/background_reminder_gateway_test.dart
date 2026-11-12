import 'package:flutter/services.dart';
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

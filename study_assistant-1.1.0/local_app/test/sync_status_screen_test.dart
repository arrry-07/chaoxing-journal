import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/features/sync_status_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  testWidgets('sync status links to the single background-check setting',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SyncStatusScreen(store: store))),
    );

    expect(find.text('白天后台检查'), findsOneWidget);
    expect(find.text('调整后台检查与提醒'), findsOneWidget);
    expect(find.byKey(const ValueKey('auto-sync-option-15')), findsNothing);
    expect(find.byKey(const ValueKey('auto-sync-option-30')), findsNothing);
    expect(find.byKey(const ValueKey('auto-sync-option-60')), findsNothing);
    expect(find.byKey(const ValueKey('auto-sync-option-custom')), findsNothing);
    expect(find.byKey(const ValueKey('auto-sync-option-off')), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('legacy disabled background check remains visibly disabled',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SyncStatusScreen(store: store))),
    );

    expect(store.backgroundCheckEnabled, isFalse);
    expect(find.textContaining('已关闭；手动刷新'), findsOneWidget);
  });
}

class _MemorySessionStore extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'student';

  @override
  Future<String?> readChaoxingDisplayName() async => null;

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _NoopNotificationService extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}
}

class _NoopWidgetSnapshotService extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

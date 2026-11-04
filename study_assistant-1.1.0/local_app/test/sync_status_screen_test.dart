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
  testWidgets('renders auto sync interval choices as compact option tiles',
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

    expect(
      find.byWidgetPredicate((widget) => widget is SegmentedButton<int>),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('auto-sync-option-15')), findsOneWidget);
    expect(find.byKey(const ValueKey('auto-sync-option-30')), findsOneWidget);
    expect(find.byKey(const ValueKey('auto-sync-option-60')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('auto-sync-option-custom')), findsOneWidget);
    expect(find.byKey(const ValueKey('auto-sync-option-off')), findsOneWidget);
  });

  testWidgets('saves custom auto sync interval in minutes', (tester) async {
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

    expect(find.textContaining('耗电量'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '7');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(store.autoSyncIntervalMinutes, 7);
    expect(find.text('自定义'), findsOneWidget);
    expect(find.text('自动同步时间已保存'), findsOneWidget);

    await store.saveAutoSyncIntervalMinutes(0);
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
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}
}

class _NoopWidgetSnapshotService extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

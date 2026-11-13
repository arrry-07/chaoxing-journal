import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_changes_screen.dart';
import 'package:study_assistant_mobile/src/features/profile_arrangements_screen.dart';
import 'package:study_assistant_mobile/src/features/profile_records_screen.dart';
import 'package:study_assistant_mobile/src/features/profile_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Session extends SecureSessionStore {}

class _Notifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
}

class _Widgets extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

AssignmentStore _store() => AssignmentStore(
      sessionStore: _Session(),
      notificationService: _Notifications(),
      widgetSnapshotService: _Widgets(),
    );

GoRouter _router(AssignmentStore store) => GoRouter(
      initialLocation: '/profile',
      routes: [
        ShellRoute(
          builder: (_, __, child) =>
              AppShell(assignmentStore: store, child: child),
          routes: [
            GoRoute(
              path: '/profile',
              builder: (_, __) => ProfileScreen(store: store),
            ),
            GoRoute(
              path: '/profile/arrangements',
              builder: (_, __) => ProfileArrangementsScreen(store: store),
            ),
            GoRoute(
              path: '/profile/records',
              builder: (_, __) => ProfileRecordsScreen(store: store),
            ),
            for (final path in ['/agenda', '/plan', '/terms', '/records'])
              GoRoute(
                path: path,
                builder: (_, __) => Scaffold(
                  appBar: AppBar(title: Text(path)),
                  body: const SizedBox(),
                ),
              ),
            GoRoute(
              path: '/changes',
              builder: (_, __) => AssignmentChangesScreen(store: store),
            ),
          ],
        ),
      ],
    );

void main() {
  testWidgets('learning settings expose four primary entries and child pages',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = _store();
    addTearDown(store.dispose);
    final router = _router(store);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
      theme: StudyAssistantTheme.light,
      routerConfig: router,
    ));
    await tester.pumpAndSettle();

    for (final label in ['同步学习通', '个人安排', '显示与小组件', '学习记录']) {
      await tester.scrollUntilVisible(find.text(label), 180);
      expect(find.text(label), findsOneWidget);
    }

    await tester.scrollUntilVisible(find.text('个人安排'), -180);
    await tester.tap(find.text('个人安排'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileArrangementsScreen), findsOneWidget);
    expect(find.text('个人待办与考试'), findsOneWidget);
    expect(find.text('每日计划'), findsOneWidget);

    await tester.tap(find.text('个人待办与考试'));
    await tester.pumpAndSettle();
    expect(find.text('/agenda'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ProfileArrangementsScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('学习记录'), 180);
    await tester.tap(find.text('学习记录'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileRecordsScreen), findsOneWidget);
    for (final label in ['学期归档', '本地记录', '已隐藏作业', '作业变化']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('作业变化'));
    await tester.pumpAndSettle();
    expect(find.byType(AssignmentChangesScreen), findsOneWidget);
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileRecordsScreen), findsOneWidget);
  });

  testWidgets('plan keeps the profile navigation destination selected',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = _store();
    addTearDown(store.dispose);
    final router = _router(store);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
      theme: StudyAssistantTheme.light,
      routerConfig: router,
    ));
    await tester.pumpAndSettle();

    router.push('/plan');
    await tester.pumpAndSettle();
    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navigation.selectedIndex, 3);
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('submenu pages fit $width at text scale $scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = _store();
        addTearDown(store.dispose);

        Future<void> show(Widget page, String lastEntry) async {
          await tester.pumpWidget(MaterialApp(
            theme: StudyAssistantTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
              ),
              child: child!,
            ),
            home: page,
          ));
          await tester.scrollUntilVisible(find.text(lastEntry), 180);
          expect(find.text(lastEntry), findsOneWidget);
          expect(tester.takeException(), isNull);
        }

        await show(ProfileArrangementsScreen(store: store), '每日计划');
        await show(ProfileRecordsScreen(store: store), '作业变化');
      });
    }
  }
}

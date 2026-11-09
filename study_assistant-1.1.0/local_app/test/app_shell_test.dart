import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  testWidgets('bottom navigation uses assignments calendar stats and profile',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    final router = GoRouter(
      initialLocation: '/assignments',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(
            assignmentStore: store,
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/assignments',
              builder: (context, state) => const Text('作业页'),
            ),
            GoRoute(
              path: '/calendar',
              builder: (context, state) => const Text('日历页'),
            ),
            GoRoute(
              path: '/stats',
              builder: (context, state) => const Text('统计页'),
            ),
            GoRoute(
              path: '/profile',
              builder: (context, state) => const Text('我的页'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(
        theme: StudyAssistantTheme.light, routerConfig: router));

    expect(find.text('作业'), findsOneWidget);
    expect(find.text('日历'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('同步'), findsNothing);
    expect(find.text('提醒'), findsNothing);

    const labels = ['作业', '日历', '统计', '我的'];
    const icons = [
      (Icons.assignment_outlined, Icons.assignment),
      (Icons.calendar_today_outlined, Icons.calendar_today),
      (Icons.bar_chart_outlined, Icons.bar_chart),
      (Icons.person_outline, Icons.person),
    ];
    // Include both entering and leaving statistics, and returning to home.
    for (final selected in [0, 1, 2, 3, 2, 0]) {
      await tester.tap(find.text(labels[selected]));
      await tester.pumpAndSettle();
      expect(find.text('${labels[selected]}页'), findsOneWidget);
      expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          selected);
      for (var i = 0; i < labels.length; i++) {
        final color = i == selected ? Journal.ink : Journal.muted;
        final label = tester.widget<RichText>(find.descendant(
            of: find.text(labels[i]), matching: find.byType(RichText)));
        expect(label.text.style?.color, color, reason: '${labels[i]} label');
        final icon = find.byIcon(i == selected ? icons[i].$2 : icons[i].$1);
        final glyph = tester.widget<RichText>(
            find.descendant(of: icon, matching: find.byType(RichText)));
        expect(glyph.text.style?.color, color, reason: '${labels[i]} icon');
      }
    }
  });
}

class _MemorySessionStore extends SecureSessionStore {}

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

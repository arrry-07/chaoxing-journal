import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_floating_nav_bar.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_picker_sheet.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  testWidgets(
      'floating bottom navigation uses 4 primary tabs and hides on secondary routes',
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
              builder: (context, state) => const Text('首页内容'),
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
            GoRoute(
              path: '/courses',
              builder: (context, state) => const Text('我的课程二级页'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(
        theme: StudyAssistantTheme.light, routerConfig: router));

    expect(find.byType(JournalFloatingNavBar), findsOneWidget);
    expect(find.byType(JournalNavIcon), findsNWidgets(4));
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('日历'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('同步'), findsNothing);
    expect(find.text('提醒'), findsNothing);

    const labels = ['首页', '日历', '统计', '我的'];
    const pages = ['首页内容', '日历页', '统计页', '我的页'];
    for (final selected in [0, 1, 2, 3, 2, 0]) {
      await tester.tap(find.text(labels[selected]));
      await tester.pumpAndSettle();
      expect(find.text(pages[selected]), findsOneWidget);
      expect(
        tester
            .widget<JournalFloatingNavBar>(find.byType(JournalFloatingNavBar))
            .selectedIndex,
        selected,
      );
      for (var i = 0; i < labels.length; i++) {
        final color = i == selected ? Journal.ink : Journal.muted;
        final label = tester.widget<RichText>(find.descendant(
            of: find.text(labels[i]), matching: find.byType(RichText)));
        expect(label.text.style?.color, color, reason: '${labels[i]} label');
        final icon = tester.widget<JournalNavIcon>(
          find.byType(JournalNavIcon).at(i),
        );
        expect(icon.selected, i == selected);
        expect(icon.color, color, reason: '${labels[i]} icon');
      }
    }

    router.push('/courses');
    await tester.pumpAndSettle();
    expect(find.text('我的课程二级页'), findsOneWidget);
    expect(find.byType(JournalFloatingNavBar), findsNothing);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(JournalFloatingNavBar), findsOneWidget);
  });

  testWidgets(
      'floating bottom navigation stays hidden on pushed route after refreshListenable fires',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    final router = GoRouter(
      initialLocation: '/profile',
      refreshListenable: store,
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(
            assignmentStore: store,
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/assignments',
              builder: (context, state) => const Text('首页内容'),
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
            GoRoute(
              path: '/courses',
              builder: (context, state) => const Text('我的课程二级页'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(
      theme: StudyAssistantTheme.light,
      routerConfig: router,
    ));
    await tester.pumpAndSettle();
    expect(find.byType(JournalFloatingNavBar), findsOneWidget);

    router.push('/courses');
    await tester.pumpAndSettle();
    expect(find.text('我的课程二级页'), findsOneWidget);
    expect(find.byType(JournalFloatingNavBar), findsNothing);

    await store.saveDisplay(
      store.display.copyWith(compact: !store.display.compact),
    );
    await tester.pumpAndSettle();
    expect(find.text('我的课程二级页'), findsOneWidget);
    expect(
      find.byType(JournalFloatingNavBar),
      findsNothing,
      reason: 'Pushed secondary page must keep hiding nav bar after refresh',
    );

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('我的页'), findsOneWidget);
    expect(
      tester
          .widget<JournalFloatingNavBar>(find.byType(JournalFloatingNavBar))
          .selectedIndex,
      3,
    );
  });

  testWidgets('JournalPickerSheet supports search filtering and selection',
      (tester) async {
    String? picked;
    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                picked = await showJournalPickerSheet<String>(
                  context,
                  title: '选择课程',
                  selectedValue: 'a',
                  searchable: true,
                  options: const [
                    JournalPickerOption(value: 'a', label: '高等数学'),
                    JournalPickerOption(value: 'b', label: '大学物理'),
                    JournalPickerOption(value: 'c', label: '计算机网络'),
                  ],
                );
              },
              child: const Text('打开抽屉'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('打开抽屉'));
    await tester.pumpAndSettle();
    expect(find.text('选择课程'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.enterText(find.byType(TextField), '物理');
    await tester.pumpAndSettle();
    expect(find.text('高等数学'), findsNothing);
    expect(find.text('大学物理'), findsOneWidget);

    await tester.tap(find.text('大学物理'));
    await tester.pumpAndSettle();
    expect(picked, 'b');
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

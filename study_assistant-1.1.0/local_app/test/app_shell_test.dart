import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_back_navigation_policy.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_floating_nav_bar.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_picker_sheet.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

import 'review_core_remediation_test.dart' as f;

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

  group('Phase 1B Android system back priority', () {
    test('AppBackNavigationPolicy enforces priority and 2-second window', () {
      var now = DateTime.utc(2026, 11, 23, 2, 0, 0);
      final policy = AppBackNavigationPolicy(clock: () => now);

      expect(
        policy.decide(
          currentUri: Uri.parse('/assignments'),
          canPopNavigator: true,
        ),
        AppBackAction.popNavigator,
      );
      expect(
        policy.decide(
          currentUri: Uri.parse('/assignments?scope=noDeadline'),
          canPopNavigator: false,
        ),
        AppBackAction.goHome,
      );
      expect(
        policy.decide(
          currentUri: Uri.parse('/calendar'),
          canPopNavigator: false,
        ),
        AppBackAction.goHome,
      );

      expect(
        policy.decide(
          currentUri: Uri.parse('/assignments'),
          canPopNavigator: false,
        ),
        AppBackAction.armHomeExit,
      );
      now = now.add(const Duration(milliseconds: 2000));
      expect(
        policy.decide(
          currentUri: Uri.parse('/assignments'),
          canPopNavigator: false,
        ),
        AppBackAction.exitApp,
      );

      // Expired window (> 2s) arms again instead of exiting.
      expect(
        policy.decide(
          currentUri: Uri.parse('/assignments'),
          canPopNavigator: false,
        ),
        AppBackAction.armHomeExit,
      );
      now = now.add(const Duration(milliseconds: 2001));
      expect(
        policy.decide(
          currentUri: Uri.parse('/assignments'),
          canPopNavigator: false,
        ),
        AppBackAction.armHomeExit,
      );

      // Clock moving backwards resets cleanly rather than exiting.
      now = now.subtract(const Duration(milliseconds: 500));
      expect(
        policy.decide(
          currentUri: Uri.parse('/assignments'),
          canPopNavigator: false,
        ),
        AppBackAction.armHomeExit,
      );
    });

    testWidgets(
        'back dismisses modal first, preserves pushed tab/scroll, recovers stackless links, and exits on 2s double-back',
        (tester) async {
      SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
      var now = DateTime.utc(2026, 11, 23, 2, 0, 0);
      var exitCalls = 0;
      final session = f.Session();
      final store = _ShellTestStore(sessionStore: session);
      await store.restoreSession();
      addTearDown(store.dispose);

      final overlaySignal = OverlayResetNotifier();
      addTearDown(overlaySignal.dispose);
      final rootObserver = AppNavigationObserver(overlaySignal.markChanged);
      final shellObserver = AppNavigationObserver(overlaySignal.markChanged);
      final calScroll = ScrollController();
      addTearDown(calScroll.dispose);

      late GoRouter router;
      router = GoRouter(
        initialLocation: '/assignments',
        observers: [rootObserver],
        routes: [
          ShellRoute(
            observers: [shellObserver],
            builder: (context, state, child) => AppShell(
              assignmentStore: store,
              clock: () => now,
              onExitApp: () async => exitCalls++,
              overlayResetListenable: overlaySignal,
              child: child,
            ),
            routes: [
              GoRoute(
                path: '/assignments',
                builder: (context, state) => Builder(
                  builder: (homeContext) => Column(
                    children: [
                      Text(state.uri.queryParameters['scope'] == null
                          ? '普通首页'
                          : '恢复页:${state.uri.queryParameters['scope']}'),
                      TextButton(
                        onPressed: () {
                          unawaited(showModalBottomSheet<void>(
                            context: homeContext,
                            useRootNavigator: true,
                            builder: (_) => const SizedBox(
                              height: 180,
                              child: Center(child: Text('过滤抽屉')),
                            ),
                          ));
                        },
                        child: const Text('打开弹层'),
                      ),
                    ],
                  ),
                ),
              ),
              GoRoute(
                path: '/assignments/:id',
                builder: (_, s) => Text('详情:${s.pathParameters['id']}'),
              ),
              GoRoute(
                path: '/calendar',
                builder: (_, __) => ListView.builder(
                  key: const PageStorageKey('calendar-scroll'),
                  controller: calScroll,
                  itemCount: 40,
                  itemExtent: 60,
                  itemBuilder: (_, i) => Text('日历条目 $i'),
                ),
              ),
              GoRoute(
                path: '/stats',
                builder: (_, __) => const Text('统计页'),
              ),
              GoRoute(
                path: '/profile',
                builder: (_, __) => const Text('我的页'),
              ),
              GoRoute(
                path: '/courses',
                builder: (_, __) => const Text('二级页面'),
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

      // 1. Clean home first back -> shows exit prompt, second within 2s exits.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('再滑一次退出课业手记'), findsOneWidget);
      expect(exitCalls, 0);

      // Opening modal overlay resets the 2s exit timer and pops modal first.
      await tester.tap(find.text('打开弹层'));
      await tester.pumpAndSettle();
      expect(find.text('过滤抽屉'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('过滤抽屉'), findsNothing);
      expect(exitCalls, 0);

      // Next back within 1s arms again instead of exiting because modal reset it.
      now = now.add(const Duration(milliseconds: 500));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('再滑一次退出课业手记'), findsOneWidget);
      expect(exitCalls, 0);

      // Lifecycle resume resets timer.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      now = now.add(const Duration(milliseconds: 400));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(exitCalls, 0);

      // Account epoch/identity change resets timer.
      session.account = 'student-b';
      await store.restoreSession();
      await tester.pump();
      now = now.add(const Duration(milliseconds: 400));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(exitCalls, 0);

      // Second back within 2s exits cleanly.
      now = now.add(const Duration(milliseconds: 1500));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(exitCalls, 1);

      // 2. Pushed secondary page & pushed recovery route keep source tab & scroll.
      await tester.tap(find.text('日历'));
      await tester.pumpAndSettle();
      calScroll.jumpTo(300);
      await tester.pumpAndSettle();
      unawaited(router.push('/assignments?scope=noDeadline'));
      await tester.pumpAndSettle();
      expect(find.text('恢复页:noDeadline'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsOneWidget);
      expect(calScroll.offset, 300);
      expect(
        tester
            .widget<JournalFloatingNavBar>(find.byType(JournalFloatingNavBar))
            .selectedIndex,
        1,
      );

      unawaited(router.push('/courses'));
      await tester.pumpAndSettle();
      expect(find.text('二级页面'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsOneWidget);
      expect(calScroll.offset, 300);

      // 3. Stackless recovery & stackless secondary deep link return to clean home.
      router.go('/assignments?scope=deadlinePending');
      await tester.pumpAndSettle();
      expect(find.text('恢复页:deadlinePending'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('普通首页'), findsOneWidget);
      expect(exitCalls, 1);

      router.go('/assignments/cx%3Awork%3A1');
      await tester.pumpAndSettle();
      expect(find.text('详情:cx:work:1'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('普通首页'), findsOneWidget);
      expect(exitCalls, 1);

      // 4. All three non-home tabs return to home without exiting.
      for (final tab in ['日历', '统计', '我的']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('普通首页'), findsOneWidget, reason: 'from $tab');
        expect(exitCalls, 1);
      }

      // 5. Timeout > 2s re-arms instead of exiting.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(exitCalls, 1);
      now = now.add(const Duration(milliseconds: 2100));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(exitCalls, 1);
      now = now.add(const Duration(milliseconds: 800));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(exitCalls, 2);

      await tester.pumpWidget(const SizedBox());
    });
  });
}

class _ShellTestStore extends AssignmentStore {
  _ShellTestStore({required super.sessionStore})
      : super(
          notificationService: f.Notifications(),
          widgetSnapshotService: f.WidgetService(),
          chaoxingClient: f.Client(),
        );

  @override
  Future<bool> runDueAutoSync({DateTime? now}) async => false;
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

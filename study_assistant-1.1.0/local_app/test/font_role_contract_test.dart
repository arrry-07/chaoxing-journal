import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/calendar_screen.dart';
import 'package:study_assistant_mobile/src/features/display_settings_screen.dart';
import 'package:study_assistant_mobile/src/features/login_screen.dart';
import 'package:study_assistant_mobile/src/features/profile_screen.dart';
import 'package:study_assistant_mobile/src/features/stats_screen.dart';
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

class _Store extends AssignmentStore {
  _Store()
      : super(
          sessionStore: _Session(),
          notificationService: _Notifications(),
          widgetSnapshotService: _Widgets(),
        );

  @override
  Future<bool> runDueAutoSync({DateTime? now}) async => false;
}

TextStyle _renderedStyle(WidgetTester tester, Finder textFinder) {
  final richText = tester.widget<RichText>(
    find.descendant(of: textFinder, matching: find.byType(RichText)).first,
  );
  return richText.text.style ?? const TextStyle();
}

bool _wrongRole({
  required bool title,
  required TextStyle style,
}) {
  if (title) {
    return style.fontFamily != Journal.titleFamily ||
        style.fontWeight != FontWeight.w400;
  }
  return style.fontFamily != Journal.bodyFamily;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('main page headings use WenKai while UI copy uses sans-serif',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _Store();
    addTearDown(store.dispose);
    final now = DateTime(2026, 11, 18, 10);

    final pages = <({String title, Widget child})>[
      (
        title: '课业手记',
        child: AssignmentListScreen(store: store),
      ),
      (
        title: '课业日历',
        child: CalendarScreen(store: store, clock: () => now),
      ),
      (
        title: '课业统计',
        child: StatsScreen(store: store, clock: () => now),
      ),
      (
        title: '我的手帐',
        child: ProfileScreen(store: store),
      ),
    ];

    for (final page in pages) {
      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(body: page.child),
      ));
      await tester.pumpAndSettle();
      final titleStyle = _renderedStyle(tester, find.text(page.title));
      expect(titleStyle.fontFamily, Journal.titleFamily,
          reason: '${page.title} title family');
      expect(titleStyle.fontWeight, FontWeight.w400,
          reason: '${page.title} title weight');
      expect(titleStyle.fontSize, 30, reason: '${page.title} title size');
      expect(titleStyle.height, 1.25, reason: '${page.title} title height');
    }

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: Scaffold(body: ProfileScreen(store: store)),
    ));
    await tester.pumpAndSettle();
    expect(
      _renderedStyle(tester, find.text('设置')).fontFamily,
      Journal.bodyFamily,
    );
  });

  testWidgets(
      'settings, inputs, dialogs and floating navigation use modern sans-serif',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _Store();
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: DisplaySettingsScreen(store: store),
    ));
    await tester.pumpAndSettle();
    for (final label in ['首页显示', '紧凑密度']) {
      expect(
        _renderedStyle(tester, find.text(label)).fontFamily,
        Journal.bodyFamily,
        reason: label,
      );
    }

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: LoginScreen(store: store),
    ));
    await tester.pumpAndSettle();
    final inputs = tester.widgetList<EditableText>(find.byType(EditableText));
    expect(inputs, isNotEmpty);
    for (final input in inputs) {
      expect(input.style.fontFamily, Journal.bodyFamily);
    }

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: Scaffold(body: ProfileScreen(store: store)),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('关于我们'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('关于我们'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关于我们'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutDialog), findsOneWidget);
    expect(
      _renderedStyle(tester, find.text('学习通课业手记')).fontFamily,
      Journal.bodyFamily,
    );

    final router = GoRouter(
      initialLocation: '/assignments',
      routes: [
        ShellRoute(
          builder: (_, __, child) =>
              AppShell(assignmentStore: store, child: child),
          routes: [
            GoRoute(
              path: '/assignments',
              builder: (_, __) => AssignmentListScreen(store: store),
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
    for (final label in ['首页', '日历', '统计', '我的']) {
      expect(
        _renderedStyle(tester, find.text(label)).fontFamily,
        Journal.bodyFamily,
        reason: 'bottom navigation $label',
      );
    }
  });

  testWidgets('font role contract rejects bold headlines and WenKai body copy',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: const Scaffold(
        body: Column(children: [
          Text(
            '错误标题',
            style: TextStyle(
              fontFamily: Journal.titleFamily,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text('错误正文', style: TextStyle(fontFamily: Journal.titleFamily)),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(
      _wrongRole(
        title: true,
        style: _renderedStyle(tester, find.text('错误标题')),
      ),
      isTrue,
    );
    expect(
      _wrongRole(
        title: false,
        style: _renderedStyle(tester, find.text('错误正文')),
      ),
      isTrue,
    );
  });
}

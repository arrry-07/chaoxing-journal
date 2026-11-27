import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_deep_links.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/manual_agenda_screen.dart';
import 'package:study_assistant_mobile/src/features/manual_entry_detail_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/home_manual_actions.dart';
import 'package:study_assistant_mobile/src/features/widgets/manual_home_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class _TestSession extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'student-m6';

  @override
  Future<String?> readChaoxingPassword() async => 'secret';

  @override
  Future<String?> readChaoxingDisplayName() async => '测试同学';

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _NoopNotifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}

  @override
  Future<void> rescheduleManual(List<ManualEntry> entries) async {}

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}

  @override
  Future<void> rescheduleSummary(
    List<Assignment> items,
    PersonalWorkspace personal,
    DateTime? lastSync,
  ) async {}
}

class _NoopSnapshot extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

Future<AssignmentStore> _buildStore(
  DateTime now, {
  List<ManualEntry> entries = const [],
}) async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  FlutterSecureStorage.setMockInitialValues({});
  final store = AssignmentStore(
    sessionStore: _TestSession(),
    notificationService: _NoopNotifications(),
    widgetSnapshotService: _NoopSnapshot(),
    clock: () => now,
  );
  await store.restoreSession();
  if (entries.isNotEmpty) {
    await store.saveNotebook(
      (_) => StudyNotebook(entries: entries),
      store.accountEpoch,
    );
  }
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
    tzdata.initializeTimeZones();
  });

  testWidgets(
      'M6: ManualHomeCard renders 待办/考试 + 自己添加 pills and 2-line note preview',
      (tester) async {
    final now = DateTime.utc(2026, 11, 25, 2, 0);
    for (final dark in [false, true]) {
      final entry = ManualEntry(
        id: 'todo-note',
        kind: ManualEntry.kindTodo,
        title: '提交实验总结',
        course: '软件工程',
        note: '第一行提示内容\n第二行补充说明与格式要求，需要仔细检查页眉和签名。',
        at: now.add(const Duration(hours: 3)),
      );
      final exam = ManualEntry(
        id: 'exam-card',
        kind: ManualEntry.kindExam,
        title: '编译原理期末测验',
        at: now.add(const Duration(days: 1)),
      );
      await tester.pumpWidget(MaterialApp(
        theme: dark ? StudyAssistantTheme.dark : StudyAssistantTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              ManualHomeCard(
                entry: entry,
                now: now,
                onTap: () {},
                onToggleDone: () {},
              ),
              ManualHomeCard(
                entry: exam,
                now: now,
                onTap: () {},
                onToggleDone: () {},
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('待办'), findsOneWidget);
      expect(find.text('考试'), findsOneWidget);
      expect(find.text('自己添加'), findsNWidgets(2));
      expect(find.text('手动待办'), findsNothing);
      expect(find.text('手动考试'), findsNothing);
      expect(find.text('提前30分提醒'), findsNothing);
      final noteWidget = tester.widget<Text>(find.textContaining('第一行提示内容'));
      expect(noteWidget.maxLines, 2);
      expect(noteWidget.overflow, TextOverflow.ellipsis);
    }
  });

  testWidgets(
      'M6: ManualEntryEditor places 待办/考试 below title and supports initialKind',
      (tester) async {
    final now = DateTime.utc(2026, 11, 25, 2, 0);
    final store = await _buildStore(now);
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: ManualEntryEditor(store: store, initialKind: ManualEntry.kindExam),
    ));
    await tester.pumpAndSettle();

    final titleTop = tester.getTopLeft(find.byType(TextFormField).first).dy;
    final segmentTop = tester.getTopLeft(find.text('待办')).dy;
    expect(titleTop, lessThan(segmentTop));
    expect(find.text('考试'), findsOneWidget);
    expect(find.text('考试必须填写时间'), findsOneWidget);
  });

  testWidgets(
      'M6: ManualEntryDetailScreen displays D13 quiet-hours warning only for skipped future reminder, copies note, toggles done, deletes, and handles missing entry across themes at 320dp@2x',
      (tester) async {
    // 23:10 local wall time across any runner TZ (UTC / CST / PST)
    final now = DateTime(2026, 11, 25, 23, 10);
    final quietEntry = ManualEntry(
      id: 'm-quiet',
      kind: ManualEntry.kindTodo,
      title: '凌晨前提交报告',
      course: '软件工程',
      location: '教二 301',
      minutes: 45,
      note: '附上测试截图和版本号',
      at: DateTime(2026, 11, 26, 0, 10), // cand=23:40 local
      remind: true,
    );
    final daytimeEntry = ManualEntry(
      id: 'm-day',
      kind: ManualEntry.kindExam,
      title: '下午上机考试',
      at: DateTime(2026, 11, 26, 14, 0),
      remind: true,
    );
    final store = await _buildStore(now, entries: [quietEntry, daytimeEntry]);
    addTearDown(store.dispose);

    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    for (final dark in [false, true]) {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: dark ? StudyAssistantTheme.dark : StudyAssistantTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: ManualEntryDetailScreen(
          key: ValueKey('m6-detail-quiet-$dark'),
          store: store,
          entryId: 'm-quiet',
          clock: () => now,
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'dark=$dark');
      expect(find.byKey(const ValueKey('manual-detail-title')), findsOneWidget);
      expect(find.text('自己添加'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('manual-detail-quiet-hours-notice')),
        findsOneWidget,
      );

      // Copy note
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('manual-detail-copy-note')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('manual-detail-copy-note')));
      await tester.pumpAndSettle();
      expect(copiedText, '附上测试截图和版本号');
    }

    // Daytime entry must NOT show quiet-hours notice
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: ManualEntryDetailScreen(
        store: store,
        entryId: 'm-day',
        clock: () => now,
      ),
    ));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('manual-detail-quiet-hours-notice')),
      findsNothing,
    );

    // Full GoRouter flow: Home card tap -> Detail -> Toggle done -> Delete with confirm -> returns home
    final router = GoRouter(
      initialLocation: '/assignments',
      routes: [
        GoRoute(
          path: '/assignments',
          builder: (context, _) {
            final actions = HomeManualActions(
              store: store,
              feedback: (_, {action, actionLabel}) {},
              isMounted: () => true,
            );
            return Scaffold(
              body: ListView(
                children: [
                  for (final e in store.notebook.entries)
                    buildHomeManualTile(
                      store: store,
                      now: now,
                      entry: e,
                      actions: actions,
                    ),
                ],
              ),
            );
          },
        ),
        GoRoute(
          path: '/assignments/manual/:id',
          builder: (_, state) => ManualEntryDetailScreen(
            store: store,
            entryId: state.pathParameters['id']!,
            clock: () => now,
          ),
        ),
        GoRoute(
          path: '/assignments/manual/:id/edit',
          builder: (_, state) => ManualEntryEditor(
            store: store,
            entryId: state.pathParameters['id'],
            routeScope: '/assignments',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(
      theme: StudyAssistantTheme.light,
      routerConfig: router,
    ));
    await tester.pumpAndSettle();

    // Tapping manual card opens detail screen (not editor)
    await tester.tap(find.text('凌晨前提交报告'));
    await tester.pumpAndSettle();
    expect(find.byType(ManualEntryDetailScreen), findsOneWidget);
    expect(find.byType(ManualEntryEditor), findsNothing);

    // Toggle done
    final toggleDone = find.byKey(const ValueKey('manual-detail-toggle-done'));
    await tester.scrollUntilVisible(toggleDone, 180,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(toggleDone);
    await tester.pumpAndSettle();
    await tester.tap(toggleDone);
    await tester.pumpAndSettle();
    expect(store.notebook.entries.firstWhere((e) => e.id == 'm-quiet').done,
        isTrue);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('标为未完成'), findsOneWidget);

    // Check reminder status link & note header height parity
    final detailHeader = find.text('安排详情');
    final noteHeader = find.text('备注');
    expect(detailHeader, findsOneWidget);
    expect(noteHeader, findsOneWidget);
    final detailCardBox = tester.getSize(
      find.ancestor(of: detailHeader, matching: find.byType(Container)).first,
    );
    final noteCardBox = tester.getSize(
      find.ancestor(of: noteHeader, matching: find.byType(Container)).first,
    );
    expect((noteCardBox.height - detailCardBox.height).abs(),
        lessThanOrEqualTo(6.0));
    final copyButtonSize =
        tester.getSize(find.byKey(const ValueKey('manual-detail-copy-note')));
    expect(copyButtonSize.width, greaterThanOrEqualTo(44));
    expect(copyButtonSize.height, greaterThanOrEqualTo(40));
    expect(
      find.byKey(const ValueKey('manual-detail-reminder-status')),
      findsOneWidget,
    );

    // Top app bar should no longer have duplicate edit button; bottom edit button routes to /edit
    expect(find.byKey(const ValueKey('manual-detail-edit')), findsNothing);
    final editBtn = find.byKey(const ValueKey('manual-detail-edit-button'));
    await tester.scrollUntilVisible(editBtn, 180,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(editBtn);
    await tester.pumpAndSettle();
    await tester.tap(editBtn);
    await tester.pumpAndSettle();
    expect(find.byType(ManualEntryEditor), findsOneWidget);
    Navigator.of(tester.element(find.byType(ManualEntryEditor))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(ManualEntryDetailScreen), findsOneWidget);

    // Delete with confirm returns to home and removes entry
    final deleteBtn = find.byKey(const ValueKey('manual-detail-delete'));
    await tester.scrollUntilVisible(deleteBtn, 180,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(deleteBtn);
    await tester.pumpAndSettle();
    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('删除'),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.notebook.entries.any((e) => e.id == 'm-quiet'), isFalse);
    expect(find.byType(ManualEntryDetailScreen), findsNothing);

    // Missing entry renders safe state
    router.go('/assignments/manual/does-not-exist');
    await tester.pumpAndSettle();
    expect(find.text('未找到这条个人安排'), findsOneWidget);
  });

  test(
      'M6 D13: rescheduleManual separates quiet-hours skips from lastWarning and uses 待办提醒/考试提醒 titles',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    const permissions = MethodChannel('study_assistant/permissions');
    final scheduledCalls = <Map<Object?, Object?>>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(permissions, (call) async {
      if (call.method == 'getAndroidSdkInt') return 35;
      return null;
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'getNotificationAppLaunchDetails':
          return {'notificationLaunchedApp': false};
        case 'pendingNotificationRequests':
        case 'getActiveNotifications':
          return <Map<String, Object?>>[];
        case 'getNotificationChannels':
          return <Map<String, Object?>>[
            {
              'id': LocalNotificationService.manualV3Channel,
              'name': '待办与考试提醒',
              'description': '',
              'groupId': null,
              'showBadge': true,
              'importance': 4,
              'sound': null,
              'playSound': true,
              'enableLights': false,
              'enableVibration': true,
              'vibrationPattern': null,
              'ledColor': 0,
              'audioAttributesUsage': 5,
            },
          ];
        case 'areNotificationsEnabled':
        case 'canScheduleExactNotifications':
          return true;
        case 'zonedSchedule':
          scheduledCalls.add(Map<Object?, Object?>.from(call.arguments as Map));
          return null;
        default:
          return true;
      }
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(permissions, null);
    });

    final futureBase = DateTime.now().toUtc().add(const Duration(days: 2));
    final now = DateTime.utc(
      futureBase.year,
      futureBase.month,
      futureBase.day,
      15,
      10,
    ); // 23:10 Beijing
    final service = LocalNotificationService(
      clock: () => now,
      location: tz.getLocation('Asia/Shanghai'),
    );
    final quietTodo = ManualEntry(
      id: 'm-quiet-skip',
      kind: ManualEntry.kindTodo,
      title: '凌晨待办',
      at: now.add(const Duration(hours: 1)), // 00:10+1 Beijing -> quiet skip
      remind: true,
    );
    final dayExam = ManualEntry(
      id: 'm-day-exam',
      kind: ManualEntry.kindExam,
      title: '白天考试',
      at: now.add(
        const Duration(hours: 14, minutes: 50),
      ), // 14:00+1 Beijing -> scheduled
      remind: true,
    );
    final dayTodo = ManualEntry(
      id: 'm-day-todo',
      kind: ManualEntry.kindTodo,
      title: '白天待办',
      at: now.add(
        const Duration(hours: 15, minutes: 50),
      ), // 15:00+1 Beijing -> scheduled
      remind: true,
    );

    await service.rescheduleManual([quietTodo, dayExam, dayTodo]);

    expect(service.lastQuietHoursSkippedManualIds, {'m-quiet-skip'});
    expect(service.lastWarning, isNull);
    expect(scheduledCalls.map((c) => c['title']).toList(), ['考试提醒', '待办提醒']);
  });

  testWidgets(
      'M6 Gate 1: ManualHomeCard shows quiet-hours/missed-window status honestly and AppDeepLinks retains manual detail redirect',
      (tester) async {
    expect(
      AppDeepLinks.validatedAssignmentLocation('/assignments/manual/m-123'),
      '/assignments/manual/m-123',
    );
    expect(
      AppDeepLinks.validatedAssignmentLocation('/assignments/manual/..'),
      isNull,
    );

    final now = DateTime(2026, 11, 25, 23, 10);
    final quietEntry = ManualEntry(
      id: 'm-q',
      kind: ManualEntry.kindTodo,
      title: '凌晨待办',
      at: DateTime(2026, 11, 26, 0, 10), // cand=23:40 local -> quiet skip
      remind: true,
    );
    final soonEntry = ManualEntry(
      id: 'm-s',
      kind: ManualEntry.kindExam,
      title: '快到点考试',
      at: now.add(const Duration(minutes: 15)),
      remind: true,
    );

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: Scaffold(
        body: ListView(
          children: [
            ManualHomeCard(
              entry: quietEntry,
              now: now,
              onTap: () {},
              onToggleDone: () {},
            ),
            ManualHomeCard(
              entry: soonEntry,
              now: now,
              onTap: () {},
              onToggleDone: () {},
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('夜间静音时段未排期'), findsOneWidget);
    expect(find.textContaining('不足30分未排提醒'), findsOneWidget);
    expect(find.textContaining('提前30分提醒'), findsNothing);
  });
}

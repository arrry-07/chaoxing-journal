import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Failure injection into the persistence boundary used by SharedPreferences.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:study_assistant_mobile/main.dart';
import 'package:study_assistant_mobile/src/features/reminder_settings_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_reminder_planner.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/background_check_settings.dart';
import 'package:study_assistant_mobile/src/services/background_reminder_gateway.dart';
import 'package:study_assistant_mobile/src/services/daily_summary.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/permission_settings_service.dart';
import 'package:study_assistant_mobile/src/services/reminder_rule_store.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
  });

  Future<void> scrollTo(
    WidgetTester tester,
    Finder finder, [
    double delta = 200,
  ]) =>
      tester.scrollUntilVisible(
        finder,
        delta,
        scrollable: find.byType(Scrollable).first,
      );

  testWidgets('shows permission controls needed for reminders', (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final notifService = _NoopNotificationService();
    final sessionStore = _MemorySessionStore();
    final store = AssignmentStore(
      sessionStore: sessionStore,
      notificationService: notifService,
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderSettingsScreen(
            assignmentStore: store,
            initialExpandHealth: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('提醒状态与体检'), findsOneWidget);
    await scrollTo(tester, find.text('通知权限'));
    expect(find.text('通知权限'), findsOneWidget);
    await scrollTo(tester, find.text('精确闹钟'));
    expect(find.text('精确闹钟'), findsOneWidget);
    await scrollTo(tester, find.text('截止提醒通知渠道'));
    expect(find.text('截止提醒通知渠道'), findsOneWidget);
    await scrollTo(tester, find.text('本应用电池与后台设置'));
    expect(find.text('本应用电池与后台设置'), findsOneWidget);
    await scrollTo(tester, find.text('提前提醒时间'));
    expect(find.text('提前提醒时间'), findsOneWidget);
  });

  testWidgets('missing setting activity explains where to search manually',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    final service = _ScriptedPermissionSettingsService(
      exactAlarmResult: SettingsOpenResult.unavailable,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderSettingsScreen(
            assignmentStore: store,
            permissionSettingsService: service,
            initialExpandHealth: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(ListTile, '精确闹钟').first;
    await scrollTo(tester, tile);
    await Scrollable.ensureVisible(tester.element(tile), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.exactAlarmChecks, 1);
    expect(
      find.textContaining('手机系统设置中搜索“学习通课业手记”'),
      findsOneWidget,
    );
    expect(find.textContaining('学习通作业提醒'), findsNothing);
  });

  testWidgets('missing notification channel explains the list fallback',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    final service = _ScriptedPermissionSettingsService(
      channelResult: SettingsOpenResult.listFallback,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderSettingsScreen(
            assignmentStore: store,
            permissionSettingsService: service,
            initialExpandHealth: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(ListTile, '截止提醒通知渠道').first;
    await scrollTo(tester, tile);
    await Scrollable.ensureVisible(tester.element(tile), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.channelId, 'assignment_deadlines');
    expect(
      find.textContaining('已打开相关系统设置列表'),
      findsOneWidget,
    );
  });

  testWidgets('battery fallback explains that app details were opened',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    final service = _ScriptedPermissionSettingsService(
      batteryResult: SettingsOpenResult.appDetailsFallback,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderSettingsScreen(
            assignmentStore: store,
            permissionSettingsService: service,
            initialExpandHealth: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(ListTile, '本应用电池与后台设置').first;
    await scrollTo(tester, tile);
    await Scrollable.ensureVisible(tester.element(tile), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('已打开“学习通课业手记”的应用详情'),
      findsOneWidget,
    );
    expect(find.textContaining('请进入电池或后台运行设置自行核对'), findsWidgets);
  });

  testWidgets('resuming refreshes notification listener state', (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    final service = _ScriptedPermissionSettingsService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderSettingsScreen(
            assignmentStore: store,
            permissionSettingsService: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.listenerChecks, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(service.listenerChecks, 2);
  });

  testWidgets('refreshes listener permission when the page opens',
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
      MaterialApp(
        home: Scaffold(
          body: ReminderSettingsScreen(
            assignmentStore: store,
            permissionSettingsService:
                const _GrantedPermissionSettingsService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await scrollTo(tester, find.textContaining('已授权'));
    expect(find.textContaining('已授权'), findsOneWidget);
  });

  testWidgets('background checks expose only 2, 4 and 6 hour choices',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'auto_sync_interval_minutes': 60,
    });
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderSettingsScreen(assignmentStore: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(store.backgroundCheckIntervalMinutes, 240);
    await scrollTo(
      tester,
      find.byKey(const ValueKey('background-check-switch')),
    );
    expect(
        find.byKey(const ValueKey('background-check-switch')), findsOneWidget);
    await scrollTo(
      tester,
      find.byKey(const ValueKey('background-interval-360')),
    );
    expect(
        find.byKey(const ValueKey('background-interval-120')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('background-interval-240')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('background-interval-360')), findsOneWidget);
    await scrollTo(
      tester,
      find.byKey(const ValueKey('new-assignment-switch')),
    );
    expect(find.byKey(const ValueKey('notification-listener-switch')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('new-assignment-switch')), findsOneWidget);

    final choice120 = find.byKey(const ValueKey('background-interval-120'));
    await Scrollable.ensureVisible(tester.element(choice120), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(choice120);
    await tester.pumpAndSettle();
    expect(store.backgroundCheckIntervalMinutes, 120);
  });

  testWidgets('adds and removes a custom reminder time', (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final notifService = _NoopNotificationService();
    final sessionStore = _MemorySessionStore();
    final store = AssignmentStore(
      sessionStore: sessionStore,
      notificationService: notifService,
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderSettingsScreen(assignmentStore: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await scrollTo(tester, find.text('添加'));
    await Scrollable.ensureVisible(
      tester.element(find.text('添加')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), '45');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(find.text('提前 45 分钟'), findsOneWidget);
    await Scrollable.ensureVisible(
      tester.element(find.byIcon(Icons.delete_outline).last),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline).last);
    await tester.pumpAndSettle();

    expect(find.text('提前 45 分钟'), findsNothing);
  });

  testWidgets('adds a custom reminder with hours and minutes', (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final notifService = _NoopNotificationService();
    final sessionStore = _MemorySessionStore();
    final store = AssignmentStore(
      sessionStore: sessionStore,
      notificationService: notifService,
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderSettingsScreen(assignmentStore: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await scrollTo(tester, find.text('添加'));
    await Scrollable.ensureVisible(
      tester.element(find.text('添加')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '1');
    await tester.enterText(find.byType(TextField).at(1), '30');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(find.text('提前 1 小时 30 分钟'), findsOneWidget);
  });

  testWidgets('custom reminders enforce the backup limit and deduplicate',
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
      MaterialApp(
        home: Scaffold(
          body: ReminderSettingsScreen(assignmentStore: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> add(String hours, String minutes) async {
      await scrollTo(tester, find.text('添加'));
      await Scrollable.ensureVisible(
        tester.element(find.text('添加')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), hours);
      await tester.enterText(find.byType(TextField).at(1), minutes);
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();
    }

    await add('0', '1');
    expect(find.text('提前 1 分钟'), findsOneWidget);
    await add('0', '1');
    expect(find.text('提前 1 分钟'), findsOneWidget);
    await add('8760', '0');
    expect(find.text('提前 365 天'), findsOneWidget);
    await add('8760', '1');
    expect(find.text('提前 365 天 1 分钟'), findsNothing);
    expect(find.text('自定义提醒最长提前 365 天'), findsOneWidget);
  });

  test('reminder storage rejects offsets outside the backup limit', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ReminderRuleStore();

    expect(ReminderRuleStore.normalizeOffsets([1, 1, 525600]), [525600, 1]);
    await expectLater(
      store.saveOffsetsMinutes([525601]),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a false write result is confirmed by reloaded durable content',
      () async {
    SharedPreferences.setMockInitialValues({
      'reminder_offsets_minutes': ['30'],
    });
    final prefs = await SharedPreferences.getInstance();
    SharedPreferencesStorePlatform.instance = _PersistThenReportFalseStore({
      for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
    });
    final reminderStore = ReminderRuleStore();

    final saved = await reminderStore.saveOffsetsMinutes([30, 60]);

    expect(saved, [60, 30]);
    expect(prefs.getStringList('reminder_offsets_minutes'), ['60', '30']);
  });

  test('a false write result with unchanged durable value fails explicitly',
      () async {
    SharedPreferences.setMockInitialValues({
      'reminder_offsets_minutes': ['30'],
    });
    final prefs = await SharedPreferences.getInstance();
    _installFailingStore(prefs, {'flutter.reminder_offsets_minutes'});

    await expectLater(
      ReminderRuleStore().saveOffsetsMinutes([30, 60]),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('未能保存'),
      )),
    );

    expect(prefs.getStringList('reminder_offsets_minutes'), ['30']);
  });

  test('a false write result with partial durable mismatch is rejected',
      () async {
    SharedPreferences.setMockInitialValues({
      'reminder_offsets_minutes': ['30'],
    });
    final prefs = await SharedPreferences.getInstance();
    SharedPreferencesStorePlatform.instance =
        _PersistAlternateThenReportFalseStore(
      {
        for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
      },
      alternate: ['60', '180'],
    );

    await expectLater(
      ReminderRuleStore().saveOffsetsMinutes([30, 60]),
      throwsStateError,
    );

    expect(prefs.getStringList('reminder_offsets_minutes'), ['60', '180']);
  });

  test('reload failure reports an uncertain persistence result', () async {
    SharedPreferences.setMockInitialValues({
      'reminder_offsets_minutes': ['30'],
    });
    final prefs = await SharedPreferences.getInstance();
    SharedPreferencesStorePlatform.instance = _ReloadFailingWriteStore({
      for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
    });

    await expectLater(
      ReminderRuleStore().saveOffsetsMinutes([30, 60]),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('无法确认'),
      )),
    );
  });

  test('failed reminder persistence does not trigger new scheduling', () async {
    SharedPreferences.setMockInitialValues({
      'auto_sync_interval_minutes': 0,
      'reminder_offsets_minutes': ['30'],
    });
    final notifications = _NoopNotificationService();
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: notifications,
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    notifications.assignmentsScheduled = 0;
    final prefs = await SharedPreferences.getInstance();
    _installFailingStore(prefs, {'flutter.reminder_offsets_minutes'});

    expect(await store.saveReminderRule([30, 60]), isFalse);

    expect(store.reminderOffsetsMinutes, [30]);
    expect(notifications.assignmentsScheduled, 0);
  });

  test('confirmed false result saves rules and triggers scheduling', () async {
    SharedPreferences.setMockInitialValues({
      'auto_sync_interval_minutes': 0,
      'reminder_offsets_minutes': ['30'],
    });
    final notifications = _NoopNotificationService();
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: notifications,
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    notifications.assignmentsScheduled = 0;
    final prefs = await SharedPreferences.getInstance();
    SharedPreferencesStorePlatform.instance = _PersistThenReportFalseStore({
      for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
    });

    expect(await store.saveReminderRule([30, 60]), isTrue);

    expect(store.reminderOffsetsMinutes, [60, 30]);
    expect(notifications.assignmentsScheduled, 1);
  });

  test('reminder storage enforces 32 rules without truncating stored rules',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = ReminderRuleStore();
    final maximumRules = List.generate(32, (index) => index + 1);

    expect(await store.saveOffsetsMinutes(maximumRules), hasLength(32));
    expect(await store.loadOffsetsMinutes(), hasLength(32));
    await expectLater(
      store.saveOffsetsMinutes([...maximumRules, 33]),
      throwsA(isA<ArgumentError>()),
    );

    final deduplicated = await store.saveOffsetsMinutes(
      [...maximumRules, maximumRules.first],
    );
    expect(deduplicated, hasLength(32));
    expect(deduplicated.toSet(), hasLength(32));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'reminder_offsets_minutes',
      [for (var value = 1; value <= 33; value++) '$value'],
    );
    expect(await store.loadOffsetsMinutes(), hasLength(33));
  });

  test('old reminder rules load without truncation or range filtering',
      () async {
    final legacyRules = [
      for (var value = 1; value <= 32; value++) '$value',
      '${400 * 24 * 60}',
    ];
    SharedPreferences.setMockInitialValues({
      'reminder_offsets_minutes': legacyRules,
    });
    final store = ReminderRuleStore();

    final loaded = await store.loadOffsetsMinutes();

    expect(loaded, hasLength(33));
    expect(loaded, contains(400 * 24 * 60));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('reminder_offsets_minutes'), legacyRules);
  });

  testWidgets('reminder screen rejects a 33rd rule before adding it',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'auto_sync_interval_minutes': 0,
      'reminder_offsets_minutes': [
        for (var value = 1; value <= 32; value++) '$value'
      ],
    });
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderSettingsScreen(assignmentStore: store),
        ),
      ),
    );

    await scrollTo(tester, find.text('添加'));
    await Scrollable.ensureVisible(
      tester.element(find.text('添加')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), '45');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('添加')),
      alignment: 0.5,
    );
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(find.text('提前 45 分钟'), findsNothing);
    expect(find.text('最多保存 32 条提醒规则'), findsOneWidget);
  });

  testWidgets('legacy over-limit rules stay visible and auto-save once trimmed',
      (tester) async {
    final legacyRules = [
      for (var value = 1; value <= 32; value++) '$value',
      '${400 * 24 * 60}',
    ];
    SharedPreferences.setMockInitialValues({
      'auto_sync_interval_minutes': 0,
      'reminder_offsets_minutes': legacyRules,
    });
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderSettingsScreen(assignmentStore: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(store.reminderOffsetsMinutes, hasLength(33));
    expect(store.reminderOffsetsMinutes, contains(400 * 24 * 60));
    expect(find.textContaining('旧版提醒规则已保留'), findsOneWidget);
    await scrollTo(tester, find.text('提前 400 天'));
    expect(find.text('提前 400 天'), findsOneWidget);
    await scrollTo(tester, find.text('提前 32 分钟'));
    expect(find.text('提前 32 分钟'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('reminder_offsets_minutes'), legacyRules);

    await scrollTo(tester, find.text('提前 400 天'), -200);
    final legacyTile = find.widgetWithText(ListTile, '提前 400 天');
    await Scrollable.ensureVisible(
      tester.element(legacyTile),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: legacyTile,
        matching: find.byIcon(Icons.delete_outline),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('提前 400 天'), findsNothing);

    final adjusted = prefs
        .getStringList('reminder_offsets_minutes')!
        .map(int.parse)
        .toList();
    expect(adjusted, hasLength(32));
    expect(adjusted, isNot(contains(400 * 24 * 60)));
  });

  testWidgets('normal bounded reminder rule toggle saves immediately',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'auto_sync_interval_minutes': 0,
      'reminder_offsets_minutes': ['1440', '180', '30'],
    });
    final notifications = _NoopNotificationService();
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: notifications,
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    notifications.assignmentsScheduled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderSettingsScreen(assignmentStore: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('旧版提醒规则已保留'), findsNothing);
    final choice = find.widgetWithText(CheckboxListTile, '提前 10 分钟');
    await scrollTo(tester, choice);
    await Scrollable.ensureVisible(tester.element(choice), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(choice);
    await tester.pumpAndSettle();

    expect(store.reminderOffsetsMinutes, [1440, 180, 30, 10]);
    expect(find.textContaining('提醒时间已保存'), findsOneWidget);
    expect(notifications.assignmentsScheduled, 1);
  });

  testWidgets('confirmed unchanged durable write reports save success',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'auto_sync_interval_minutes': 0,
      'reminder_offsets_minutes': ['1440'],
    });
    final service = _NoopNotificationService();
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: service,
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    final prefs = await SharedPreferences.getInstance();
    _installFailingStore(prefs, {'flutter.reminder_offsets_minutes'});
    await prefs.reload();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderSettingsScreen(assignmentStore: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await scrollTo(tester, find.text('添加'));
    await Scrollable.ensureVisible(
      tester.element(find.text('添加')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '24');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(store.reminderOffsetsMinutes, [1440]);
    expect(find.textContaining('保存失败'), findsNothing);
    expect(find.textContaining('提醒时间已保存'), findsOneWidget);
  });

  testWidgets(
      'reminder scheduling failure reports both saved and schedule failure warning',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'auto_sync_interval_minutes': 0,
      'reminder_offsets_minutes': ['1440'],
    });
    final service = _NoopNotificationService();
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: service,
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    service.failAssignments = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderSettingsScreen(assignmentStore: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final choice = find.widgetWithText(CheckboxListTile, '提前 30 分钟');
    await scrollTo(tester, choice);
    await Scrollable.ensureVisible(tester.element(choice), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(choice);
    await tester.pumpAndSettle();

    expect(store.reminderOffsetsMinutes, [1440, 30]);
    expect(
      find.textContaining('提醒时间已保存；提醒安排失败'),
      findsOneWidget,
    );
    expect(find.textContaining('保存失败'), findsNothing);
  });

  testWidgets('instant-save reminder change leaves without a discard prompt',
      (tester) async {
    final store = await _launchApp(tester, '/reminders');
    final preset = find.widgetWithText(CheckboxListTile, '提前 1 天');
    await scrollTo(tester, preset);
    await Scrollable.ensureVisible(tester.element(preset), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(preset);
    await tester.pumpAndSettle();

    expect(tester.widget<CheckboxListTile>(preset).value, isTrue);
    expect(store.reminderOffsetsMinutes, [1440, 30]);
    unawaited(tester.binding.handlePopRoute());
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的提醒规则？'), findsNothing);
  });

  testWidgets('ruleControlsLockedWhileSavePending', (tester) async {
    SharedPreferences.setMockInitialValues({
      'auto_sync_interval_minutes': 0,
      'reminder_offsets_minutes': ['30', '45'],
    });
    final store = _GatedRuleStore();
    addTearDown(store.dispose);
    await store.restoreSession();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReminderSettingsScreen(assignmentStore: store),
      ),
    ));
    await tester.pumpAndSettle();
    final preset = find.widgetWithText(CheckboxListTile, '提前 1 天');
    await scrollTo(tester, preset);
    await Scrollable.ensureVisible(tester.element(preset), alignment: 0.5);
    await tester.pumpAndSettle();

    await tester.tap(preset);
    await tester.pump();
    expect(store.calls, hasLength(1));

    expect(tester.widget<CheckboxListTile>(preset).onChanged, isNull);
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.enabled, isFalse);
    }
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '添加'))
            .onPressed,
        isNull);
    final deleteIcon = find.byIcon(Icons.delete_outline);
    await scrollTo(tester, deleteIcon);
    final deleteButton = find.ancestor(
      of: deleteIcon,
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(deleteButton).onPressed, isNull);

    await tester.tap(preset, warnIfMissed: false);
    await tester.pump();
    expect(store.calls, hasLength(1));

    store.gate.complete(true);
    await tester.pumpAndSettle();
    expect(store.calls.single.toSet(), {30, 45, 1440});
    expect(find.textContaining('提醒时间已保存'), findsOneWidget);
  });

  testWidgets('failedInstantSaveRollsBackAndAllowsRetry', (tester) async {
    final store = await _gatedStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReminderSettingsScreen(assignmentStore: store),
      ),
    ));
    await tester.pumpAndSettle();
    final preset = find.widgetWithText(CheckboxListTile, '提前 1 天');
    await scrollTo(tester, preset);
    await Scrollable.ensureVisible(tester.element(preset), alignment: 0.5);
    await tester.pumpAndSettle();

    await tester.tap(preset);
    await tester.pump();
    expect(store.calls, hasLength(1));
    store.gate.complete(false);
    await tester.pumpAndSettle();

    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(preset).value, isFalse);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    store.gate = Completer<bool>();
    await tester.tap(preset);
    await tester.pump();
    expect(store.calls, hasLength(2));
    store.gate.complete(true);
    await tester.pumpAndSettle();

    expect(store.calls.last.toSet(), {30, 1440});
    expect(tester.widget<CheckboxListTile>(preset).value, isTrue);
    expect(find.textContaining('提醒时间已保存'), findsOneWidget);
  });

  testWidgets('blockingRemovalOfFinalReminderOffset', (tester) async {
    final store = await _gatedStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReminderSettingsScreen(assignmentStore: store),
      ),
    ));
    await tester.pumpAndSettle();
    final preset = find.widgetWithText(CheckboxListTile, '提前 30 分钟');
    await scrollTo(tester, preset);
    await Scrollable.ensureVisible(tester.element(preset), alignment: 0.5);
    await tester.pumpAndSettle();

    await tester.tap(preset);
    await tester.pumpAndSettle();

    expect(store.calls, isEmpty);
    expect(tester.widget<CheckboxListTile>(preset).value, isTrue);
    expect(find.text('至少保留 1 个提前提醒时间'), findsOneWidget);
  });

  testWidgets('immediate settings persist independently of reminder rules',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'auto_sync_interval_minutes': 0,
      'reminder_offsets_minutes': ['30'],
    });
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    final initialDetails = store.notificationDetails;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReminderSettingsScreen(assignmentStore: store),
      ),
    ));
    await tester.pumpAndSettle();

    final detailsTile = find.widgetWithText(SwitchListTile, '通知显示详细内容');
    await scrollTo(tester, detailsTile);
    await Scrollable.ensureVisible(tester.element(detailsTile), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(detailsTile);
    await tester.pumpAndSettle();

    expect(store.notificationDetails, !initialDetails);
    expect(store.reminderOffsetsMinutes, [30]);
  });

  testWidgets('Phase 4A night breakthrough switch defaults off and toggles',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReminderSettingsScreen(assignmentStore: store),
      ),
    ));
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey('night-breakthrough-switch'));
    await scrollTo(tester, toggle);
    await Scrollable.ensureVisible(tester.element(toggle), alignment: 0.5);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(store.allowUrgentDeadlineNightBreakthrough, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(store.allowUrgentDeadlineNightBreakthrough, isTrue);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(find.textContaining('夜间静音时段提醒'), findsOneWidget);
  });

  testWidgets(
      'Phase 4B presets: brand-new defaults to recommended, existing rules kept, preset atomic save & failure rollback',
      (tester) async {
    // 1. Brand-new user with empty prefs loads 推荐冲刺 [1440, 720, 360, 180, 60, 30].
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final notifications = _NoopNotificationService();
    final brandNewStore = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: notifications,
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(brandNewStore.dispose);
    await brandNewStore.restoreSession();
    expect(brandNewStore.reminderOffsetsMinutes, [1440, 720, 360, 180, 60, 30]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReminderSettingsScreen(assignmentStore: brandNewStore),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('当前：推荐冲刺'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('reminder-preset-recommended')),
          )
          .selected,
      isTrue,
    );
    expect(find.byKey(const ValueKey('reminder-preset-reset')), findsNothing);

    // Tap 温和 -> saves once with [1440, 180].
    notifications.assignmentsScheduled = 0;
    final gentle = find.byKey(const ValueKey('reminder-preset-gentle'));
    await Scrollable.ensureVisible(tester.element(gentle), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(gentle);
    await tester.pumpAndSettle();
    expect(brandNewStore.reminderOffsetsMinutes, [1440, 180]);
    expect(notifications.assignmentsScheduled, 1);
    expect(find.text('当前：温和'), findsOneWidget);

    // Edit checkbox manually -> switches label to 自定义 and exposes 恢复默认.
    final checkTen = find.widgetWithText(CheckboxListTile, '提前 10 分钟');
    await scrollTo(tester, checkTen);
    await Scrollable.ensureVisible(tester.element(checkTen), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(checkTen);
    await tester.pumpAndSettle();
    expect(brandNewStore.reminderOffsetsMinutes, [1440, 180, 10]);
    expect(find.textContaining('当前：自定义'), findsOneWidget);
    final resetBtn = find.byKey(const ValueKey('reminder-preset-reset'));
    expect(resetBtn, findsOneWidget);
    await Scrollable.ensureVisible(tester.element(resetBtn), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(resetBtn);
    await tester.pumpAndSettle();
    expect(brandNewStore.reminderOffsetsMinutes, [1440, 720, 360, 180, 60, 30]);
    expect(find.text('当前：推荐冲刺'), findsOneWidget);

    // 2. Existing user [1440, 180, 30] is preserved without auto-rewrite.
    SharedPreferences.setMockInitialValues({
      'auto_sync_interval_minutes': 0,
      'reminder_offsets_minutes': ['1440', '180', '30'],
    });
    final existingStore = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(existingStore.dispose);
    await existingStore.restoreSession();
    expect(existingStore.reminderOffsetsMinutes, [1440, 180, 30]);

    // 3. Atomic preset save failure rolls back UI selection.
    final gated = await _gatedStore();
    addTearDown(gated.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReminderSettingsScreen(assignmentStore: gated),
      ),
    ));
    await tester.pumpAndSettle();
    final intensive = find.byKey(const ValueKey('reminder-preset-intensive'));
    await Scrollable.ensureVisible(tester.element(intensive), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(intensive);
    await tester.pump();
    expect(gated.calls, hasLength(1));
    expect(
      gated.calls.single.toSet(),
      ReminderFrequencyPreset.intensive.offsetsMinutes.toSet(),
    );
    gated.gate.complete(false);
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(
      tester.widget<ChoiceChip>(intensive).selected,
      isFalse,
    );
  });

  testWidgets(
      'health card flags muted sound and disabled vibration and shows exact alarm, battery, and lockscreen details',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final notif = _DetailedHealthNotificationService(
      const ReminderHealth(
        notifications: true,
        exact: false,
        assignmentChannel: ReminderChannelHealth(
          ReminderChannelStatus.enabled,
          importance: 4,
          channelId: LocalNotificationService.assignmentChannel,
          soundMuted: true,
          vibrationEnabled: false,
          lockscreenVisibility: 0,
        ),
        assignmentUpdatesChannel: ReminderChannelHealth(
          ReminderChannelStatus.enabled,
          importance: 3,
        ),
        summaryChannel: ReminderChannelHealth(
          ReminderChannelStatus.enabled,
          importance: 3,
        ),
        manualChannel: ReminderChannelHealth(
          ReminderChannelStatus.enabled,
          importance: 4,
        ),
        silentChannel: ReminderChannelHealth(
          ReminderChannelStatus.enabled,
          importance: 2,
          soundMuted: true,
          vibrationEnabled: false,
        ),
        activeDeadlineChannelId: LocalNotificationService.assignmentChannel,
        ignoringBatteryOptimizations: false,
        lockscreenShowNotifications: true,
        lockscreenAllowPrivateNotifications: false,
      ),
    );
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: notif,
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      clock: () => DateTime(2030, 11, 20, 10, 0),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderSettingsScreen(
            assignmentStore: store,
            initialExpandHealth: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('有 2 项提醒状态需关注'), findsOneWidget);
    expect(find.textContaining('截止提醒渠道在系统中已静音'), findsOneWidget);
    expect(find.textContaining('截止提醒渠道振动已关闭'), findsOneWidget);
    expect(find.textContaining('未开启精确闹钟，提醒可能延迟'), findsOneWidget);
    expect(find.textContaining('受系统电池优化限制（可能延迟）'), findsOneWidget);
    expect(find.textContaining('v1（assignment_deadlines）'), findsOneWidget);
    expect(find.textContaining('系统锁屏仅显示脱敏摘要'), findsOneWidget);
  });

  testWidgets(
      'enabling v2 deadline channel hides v2 button and routes channel settings tap to v2',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final notif = _DetailedHealthNotificationService(
      const ReminderHealth(
        notifications: true,
        exact: true,
        assignmentChannel: ReminderChannelHealth(
          ReminderChannelStatus.enabled,
          importance: 4,
        ),
      ),
    );
    final permissions = _ScriptedPermissionSettingsService();
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: notif,
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      clock: () => DateTime(2030, 11, 20, 10, 0),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderSettingsScreen(
            assignmentStore: store,
            permissionSettingsService: permissions,
            initialExpandHealth: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final v2Button = find.byKey(const ValueKey('enable-v2-deadline-channel'));
    expect(v2Button, findsOneWidget);
    expect(find.text('启用新版有声截止渠道（v2）'), findsOneWidget);

    await tester.tap(v2Button);
    await tester.pumpAndSettle();

    expect(store.isUsingV2DeadlineChannel, isTrue);
    expect(v2Button, findsNothing);
    expect(find.textContaining('v2（assignment_deadlines_v2）'), findsOneWidget);

    final channelTile = find.widgetWithText(ListTile, '截止提醒通知渠道').first;
    await scrollTo(tester, channelTile);
    await tester.tap(channelTile);
    await tester.pumpAndSettle();
    expect(permissions.channelId, LocalNotificationService.assignmentV2Channel);
  });

  testWidgets(
      'send test audible notification button reports daytime schedule and nighttime quiet block',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final gateway = _TestAudibleGateway();
    final dayStore = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _DetailedHealthNotificationService(
        const ReminderHealth(notifications: true, exact: true),
      ),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      backgroundReminderGateway: gateway,
      nativeReminderDeliveryEnabled: true,
      manageBackgroundSchedule: false,
      clock: () => DateTime(2030, 11, 20, 10, 0),
    );
    addTearDown(dayStore.dispose);
    await dayStore.restoreSession();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderSettingsScreen(
            assignmentStore: dayStore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final testButton =
        find.byKey(const ValueKey('send-test-notification-button'));
    expect(testButton, findsOneWidget);
    expect(find.text('发送测试有声提醒'), findsOneWidget);
    await tester.tap(testButton);
    await tester.pumpAndSettle();
    expect(gateway.sendCalls, 1);
    expect(find.textContaining('已安排测试有声提醒'), findsOneWidget);

    final nightStore = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _DetailedHealthNotificationService(
        const ReminderHealth(notifications: true, exact: true),
      ),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      backgroundReminderGateway: gateway,
      nativeReminderDeliveryEnabled: true,
      manageBackgroundSchedule: false,
      clock: () => DateTime(2030, 11, 20, 23, 45),
    );
    addTearDown(nightStore.dispose);
    await nightStore.restoreSession();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderSettingsScreen(
            key: ValueKey(nightStore),
            assignmentStore: nightStore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('send-test-notification-button')));
    await tester.pumpAndSettle();
    expect(gateway.sendCalls, 1);
    expect(find.textContaining('当前处于夜间静音时段'), findsOneWidget);
  });
}

Future<AssignmentStore> _launchApp(WidgetTester tester, String location) async {
  SharedPreferences.setMockInitialValues({
    'auto_sync_interval_minutes': 0,
    'reminder_offsets_minutes': ['30'],
  });
  final store = _LaunchStore();
  addTearDown(store.dispose);
  await store.restoreSession();
  tester.binding.platformDispatcher.defaultRouteNameTestValue = location;
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  await tester.pumpWidget(StudyAssistantApp(
    assignmentStore: store,
    notificationService: _NoopNotificationService(),
  ));
  await tester.pumpAndSettle();
  return store;
}

Future<_GatedRuleStore> _gatedStore() async {
  SharedPreferences.setMockInitialValues({
    'auto_sync_interval_minutes': 0,
    'reminder_offsets_minutes': ['30'],
  });
  final store = _GatedRuleStore();
  await store.restoreSession();
  return store;
}

class _LaunchStore extends AssignmentStore {
  _LaunchStore()
      : super(
          sessionStore: _MemorySessionStore(),
          notificationService: _NoopNotificationService(),
          widgetSnapshotService: _NoopWidgetSnapshotService(),
        );

  @override
  Future<bool> runDueAutoSync({DateTime? now}) async => false;
}

class _GatedRuleStore extends AssignmentStore {
  _GatedRuleStore()
      : super(
          sessionStore: _MemorySessionStore(),
          notificationService: _NoopNotificationService(),
          widgetSnapshotService: _NoopWidgetSnapshotService(),
        );

  final calls = <List<int>>[];
  Completer<bool> gate = Completer<bool>();

  @override
  Future<bool> saveReminderRule(List<int> offsetsMinutes) {
    calls.add(List<int>.of(offsetsMinutes));
    return gate.future;
  }
}

class _NoopNotificationService extends LocalNotificationService {
  bool failAssignments = false;
  int assignmentsScheduled = 0;

  @override
  Future<bool> isLegacyAssignmentMigrationComplete() async => true;

  @override
  Future<void> cancelPrivateSchedules() async {}

  @override
  Future<void> rescheduleManual(List<ManualEntry> items) async {}

  @override
  Future<void> rescheduleSummary(List<Assignment> items,
      PersonalWorkspace personal, DateTime? lastSync) async {}

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {
    assignmentsScheduled++;
    if (failAssignments) throw StateError('schedule unavailable');
  }
}

class _MemorySessionStore extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'student';

  @override
  Future<String?> readChaoxingDisplayName() async => null;

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _GrantedPermissionSettingsService extends PermissionSettingsService {
  const _GrantedPermissionSettingsService();

  @override
  Future<bool> isNotificationListenerEnabled() async => true;
}

class _ScriptedPermissionSettingsService extends PermissionSettingsService {
  _ScriptedPermissionSettingsService({
    this.exactAlarmResult = SettingsOpenResult.direct,
    this.channelResult = SettingsOpenResult.direct,
    this.batteryResult = SettingsOpenResult.direct,
  });

  final SettingsOpenResult exactAlarmResult;
  final SettingsOpenResult channelResult;
  final SettingsOpenResult batteryResult;
  int listenerChecks = 0;
  int exactAlarmChecks = 0;
  String? channelId;

  @override
  Future<bool> isNotificationListenerEnabled() async {
    listenerChecks++;
    return false;
  }

  @override
  Future<SettingsOpenResult> openExactAlarmSettingsResult() async {
    exactAlarmChecks++;
    return exactAlarmResult;
  }

  @override
  Future<SettingsOpenResult> openNotificationChannelSettingsResult(
    String channelId,
  ) async {
    this.channelId = channelId;
    return channelResult;
  }

  @override
  Future<SettingsOpenResult> openBatterySettingsResult() async => batteryResult;
}

class _NoopWidgetSnapshotService extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

void _installFailingStore(
  SharedPreferences prefs,
  Set<String> failingKeys,
) {
  final values = {
    for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!
  };
  SharedPreferencesStorePlatform.instance =
      _FailSelectedWrites(values, failingKeys);
}

class _FailSelectedWrites extends InMemorySharedPreferencesStore {
  _FailSelectedWrites(super.data, this.failingKeys) : super.withData();

  final Set<String> failingKeys;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (failingKeys.contains(key)) return false;
    return super.setValue(valueType, key, value);
  }
}

class _PersistThenReportFalseStore extends InMemorySharedPreferencesStore {
  _PersistThenReportFalseStore(super.data) : super.withData();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    await super.setValue(valueType, key, value);
    return false;
  }
}

class _PersistAlternateThenReportFalseStore
    extends InMemorySharedPreferencesStore {
  _PersistAlternateThenReportFalseStore(
    super.data, {
    required this.alternate,
  }) : super.withData();

  final List<String> alternate;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.reminder_offsets_minutes') {
      await super.setValue(valueType, key, alternate);
    } else {
      await super.setValue(valueType, key, value);
    }
    return false;
  }
}

class _ReloadFailingWriteStore extends InMemorySharedPreferencesStore {
  _ReloadFailingWriteStore(super.data) : super.withData();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    await super.setValue(valueType, key, value);
    return false;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    throw StateError('synthetic reload failure');
  }
}

class _DetailedHealthNotificationService extends _NoopNotificationService {
  _DetailedHealthNotificationService(this.nextHealth);

  final ReminderHealth nextHealth;

  @override
  Future<ReminderHealth> inspectHealth() async => nextHealth;
}

class _TestAudibleGateway extends BackgroundReminderGateway {
  int sendCalls = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<int> ensureActiveAccount(String accountHash) async => 1;

  @override
  Future<int> clearActiveAccount(String accountHash) async => 1;

  @override
  Future<bool> isSessionCurrent(String accountHash, int sessionEpoch) async =>
      true;

  @override
  Future<void> updateSettings(
    String accountHash,
    int sessionEpoch,
    BackgroundCheckSettings settings, {
    required bool showDetails,
    bool reconcileSchedules = true,
    bool allowUrgentNightBreakthrough = false,
    String? deadlineChannelId,
  }) async {}

  @override
  Future<void> reconcileDaytimeSchedule({
    required DateTime? targetAt,
    required bool enabled,
    required int intervalMinutes,
  }) async {}

  @override
  Future<void> cancelAssignmentDeliveryKeepEvents(String accountHash) async {}

  @override
  Future<void> markPendingUpdate({
    required String accountHash,
    required int sessionEpoch,
  }) async {}

  @override
  Future<bool> acquireWriteLease(String owner) async => true;

  @override
  Future<void> releaseWriteLease(String owner) async {}

  @override
  Future<ReminderPlanState> loadPlanState({
    required String accountHash,
    required int sessionEpoch,
  }) async =>
      ReminderPlanState(
        accountHash: accountHash,
        sessionEpoch: sessionEpoch,
        baselineCompleted: true,
        knownAssignmentIds: const {},
        sentNewAssignmentIds: const {},
        lastAttemptAt: null,
        lastFullSuccessAt: null,
        pendingUpdate: false,
        mutationVersion: 0,
      );

  @override
  Future<ReminderPlanApplyResult> applyPlan({
    required String accountHash,
    required int sessionEpoch,
    required AssignmentReminderPlan plan,
    required DateTime completedAt,
    required String? failure,
    required bool syncCompleted,
    required int expectedMutationVersion,
  }) async =>
      const ReminderPlanApplyResult(
        scheduledDeadlineCount: 0,
        pendingNewCount: 0,
        warning: null,
      );

  @override
  Future<BackgroundReminderHealth> inspectHealth({
    required String accountHash,
    required int sessionEpoch,
  }) async =>
      const BackgroundReminderHealth(
        backgroundEnabled: true,
        intervalMinutes: 240,
        newAssignmentReminderEnabled: false,
        notificationListenerEnabled: false,
        notificationListenerGranted: false,
        nextCheckAt: null,
        pendingNewCount: 0,
        pendingDeadlineCount: 0,
        baselineCompleted: true,
        pendingSignalCount: 0,
        migrationPending: false,
        lastFailure: null,
      );

  @override
  Future<TestDeadlineNotificationOutcome> sendTestDeadlineNotification({
    String? accountHash,
    String? channelId,
    int delayMillis = 3000,
  }) async {
    sendCalls++;
    return TestDeadlineNotificationOutcome(
      status: TestDeadlineNotificationStatus.scheduled,
      channelId: channelId,
    );
  }
}

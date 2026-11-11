import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Failure injection into the persistence boundary used by SharedPreferences.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:study_assistant_mobile/src/features/reminder_settings_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/permission_settings_service.dart';
import 'package:study_assistant_mobile/src/services/reminder_rule_store.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
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
          body: ReminderSettingsScreen(assignmentStore: store),
        ),
      ),
    );

    expect(find.text('提醒权限'), findsOneWidget);
    expect(find.text('通知权限'), findsOneWidget);
    expect(find.text('精确闹钟'), findsOneWidget);
    expect(find.text('锁屏提醒'), findsOneWidget);
    expect(find.text('后台与自启动'), findsOneWidget);
    expect(find.text('保存后会重新安排所有未完成作业的本地通知，自定义提醒支持精确到分钟'), findsOneWidget);
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

    expect(find.textContaining('已授权'), findsNWidgets(2));
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

    expect(store.backgroundCheckIntervalMinutes, 240);
    expect(
        find.byKey(const ValueKey('background-check-switch')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('background-interval-120')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('background-interval-240')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('background-interval-360')), findsOneWidget);
    expect(find.byKey(const ValueKey('notification-listener-switch')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('new-assignment-switch')), findsOneWidget);

    await tester
        .ensureVisible(find.byKey(const ValueKey('background-interval-120')));
    await tester.tap(find.byKey(const ValueKey('background-interval-120')));
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

    await tester.ensureVisible(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), '45');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(find.text('提前 45 分钟'), findsOneWidget);

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

    await tester.ensureVisible(find.text('添加'));
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

    Future<void> add(String hours, String minutes) async {
      await tester.ensureVisible(find.text('添加'));
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

    await tester.ensureVisible(find.text('添加'));
    await tester.enterText(find.byType(TextField).at(1), '45');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('添加'));
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(find.text('提前 45 分钟'), findsNothing);
    expect(find.text('最多保存 32 条提醒规则'), findsOneWidget);
  });

  testWidgets(
      'legacy over-limit rules stay visible and require explicit review',
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

    expect(store.reminderOffsetsMinutes, hasLength(33));
    expect(store.reminderOffsetsMinutes, contains(400 * 24 * 60));
    expect(find.textContaining('旧版提醒规则已保留'), findsOneWidget);
    expect(find.text('提前 400 天'), findsOneWidget);
    expect(find.text('提前 32 分钟'), findsOneWidget);
    expect(
      find.textContaining('超过365天的规则目前不会参与提醒调度'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('保存提醒规则'));
    await tester.tap(find.text('保存提醒规则'));
    await tester.pumpAndSettle();

    expect(find.textContaining('请先移除超出 32 条或 365 天的规则'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('reminder_offsets_minutes'), legacyRules);

    final legacyTile = find.widgetWithText(ListTile, '提前 400 天');
    await tester.ensureVisible(legacyTile);
    await tester.tap(
      find.descendant(
        of: legacyTile,
        matching: find.byIcon(Icons.delete_outline),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('提前 400 天'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    final saveButton = find.widgetWithText(FilledButton, '保存提醒规则');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final adjusted = prefs
        .getStringList('reminder_offsets_minutes')!
        .map(int.parse)
        .toList();
    expect(adjusted, hasLength(32));
    expect(adjusted, isNot(contains(400 * 24 * 60)));
  });

  testWidgets('normal bounded reminder rules still save unchanged',
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

    expect(find.textContaining('旧版提醒规则已保留'), findsNothing);
    await tester.ensureVisible(find.text('保存提醒规则'));
    await tester.tap(find.text('保存提醒规则'));
    await tester.pumpAndSettle();

    expect(store.reminderOffsetsMinutes, [1440, 180, 30]);
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

    await tester.ensureVisible(find.text('保存提醒规则'));
    await tester.tap(find.text('保存提醒规则'));
    await tester.pumpAndSettle();

    expect(store.reminderOffsetsMinutes, [1440]);
    expect(find.textContaining('提醒设置未能保存'), findsNothing);
    expect(find.textContaining('提醒时间已保存'), findsOneWidget);
  });

  testWidgets('reminder scheduling failure still reports settings saved',
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

    await tester.ensureVisible(find.text('保存提醒规则'));
    await tester.tap(find.text('保存提醒规则'));
    await tester.pumpAndSettle();

    expect(store.reminderOffsetsMinutes, [1440]);
    expect(
      find.textContaining('提醒时间已保存；提醒安排失败'),
      findsOneWidget,
    );
    expect(find.textContaining('保存失败'), findsNothing);
  });
}

class _NoopNotificationService extends LocalNotificationService {
  bool failAssignments = false;
  int assignmentsScheduled = 0;

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

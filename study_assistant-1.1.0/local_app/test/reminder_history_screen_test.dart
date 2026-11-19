import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/manual_agenda_screen.dart';
import 'package:study_assistant_mobile/src/features/reminder_health_screen.dart';
import 'package:study_assistant_mobile/src/features/reminder_history_screen.dart';
import 'package:study_assistant_mobile/src/features/reminder_status_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/reminder_history.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/background_reminder_gateway.dart';
import 'package:study_assistant_mobile/src/services/daily_summary.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _MemorySession extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'student-a';

  @override
  Future<String?> readChaoxingDisplayName() async => '测试';

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _FakeNotificationService extends LocalNotificationService {
  ReminderHealth nextHealth = const ReminderHealth(
    notifications: true,
    assignmentChannel: ReminderChannelHealth(ReminderChannelStatus.enabled),
    manualChannel: ReminderChannelHealth(ReminderChannelStatus.enabled),
    summaryChannel: ReminderChannelHealth(ReminderChannelStatus.enabled),
    scheduleRecoveryPending: false,
  );
  int healthCalls = 0;

  @override
  Future<ReminderHealth> inspectHealth() async {
    healthCalls++;
    return nextHealth;
  }

  @override
  Future<PluginScheduleEvidenceSnapshot> readScheduleEvidence() async =>
      PluginScheduleEvidenceSnapshot(
        items: const [],
        error: null,
        checkedAt: DateTime.now(),
      );
}

class _NoopSnapshot extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _ScreenTestStore extends AssignmentStore {
  _ScreenTestStore({
    _FakeNotificationService? notifications,
  }) : super(
          sessionStore: _MemorySession(),
          notificationService: notifications ?? _FakeNotificationService(),
          widgetSnapshotService: _NoopSnapshot(),
          manageBackgroundSchedule: false,
        );

  String? _hash = 'hash-a';
  int _epoch = 1;
  int _nativeEpoch = 1;
  int _generation = 1;
  StudyNotebook _notebook = StudyNotebook();
  Future<ReminderHistoryPage> Function(String? category)? onLoadHistory;
  Future<ReminderExplanation> Function(String kind, String id)?
      onExplainReminder;
  Future<BackgroundReminderHealth?> Function()? onInspectBackgroundHealth;

  @override
  bool get isAuthenticated => true;

  @override
  String? get accountHash => _hash;

  @override
  int get accountEpoch => _epoch;

  @override
  int get nativeSessionEpoch => _nativeEpoch;

  @override
  int get reminderHistoryGeneration => _generation;

  @override
  StudyNotebook get notebook => _notebook;

  void setNotebookForTest(StudyNotebook next) {
    _notebook = next;
    notifyListeners();
  }

  void switchIdentityForTest({
    required String hash,
    required int epoch,
    required int generation,
  }) {
    _hash = hash;
    _epoch = epoch;
    _nativeEpoch = epoch;
    _generation = generation;
    notifyListeners();
  }

  @override
  Future<ReminderHistoryPage> loadReminderHistory({
    int? snapshotMaxId,
    int? beforeId,
    String? category,
    List<ReminderSubjectRef> subjectRefs = const [],
  }) =>
      onLoadHistory!(category);

  @override
  Future<ReminderExplanation> explainReminder({
    required String kind,
    required String id,
  }) =>
      onExplainReminder!(kind, id);

  @override
  Future<BackgroundReminderHealth?> inspectBackgroundReminderHealth() async =>
      onInspectBackgroundHealth?.call();

  List<String> nextServiceWarnings = const [];

  @override
  List<String> get serviceWarnings => nextServiceWarnings;

  @override
  Future<void> retryReminderRecovery() async {}
}

ReminderHistoryItem _historyItem({
  required int id,
  String category = 'deadline',
  String stage = 'scheduled',
  String logicalKey = 'evt-1',
  String? reasonCode,
  DateTime? scheduledAt,
}) =>
    ReminderHistoryItem(
      id: id,
      observationId: 'obs-$id',
      operationSequence: id,
      subjectKind: 'assignment',
      subjectId: 'cx:work:1:2:1',
      logicalKey: logicalKey,
      category: category,
      stage: stage,
      reasonCode: reasonCode,
      observedAt: DateTime(2026, 11, 18, 12, 0, id),
      scheduledAt: scheduledAt ?? DateTime(2026, 11, 18, 14, 0),
      notificationId: 10,
      batchKey: null,
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
  });

  group('ReminderHistoryScreen regressions', () {
    testWidgets('switching category mid-load discards stale response',
        (tester) async {
      final firstLoad = Completer<ReminderHistoryPage>();
      final secondLoad = Completer<ReminderHistoryPage>();
      final requestedCategories = <String?>[];
      final store = _ScreenTestStore()
        ..onLoadHistory = (category) {
          requestedCategories.add(category);
          return requestedCategories.length == 1
              ? firstLoad.future
              : secondLoad.future;
        };
      addTearDown(store.dispose);

      await tester.pumpWidget(MaterialApp(
        home: ReminderHistoryScreen(store: store),
      ));
      await tester.pump();

      await tester.tap(find.widgetWithText(ChoiceChip, '截止提醒'));
      await tester.pump();

      expect(requestedCategories, [null, 'deadline']);

      firstLoad.complete(ReminderHistoryPage(
        items: [
          _historyItem(
            id: 1,
            category: 'backgroundCheck',
            logicalKey: 'bg-1',
          ),
        ],
        snapshotMaxId: 1,
        nextBeforeId: null,
        checkedAt: DateTime(2026, 11, 18, 12, 0),
        historyGeneration: 1,
      ));
      await tester.pump();

      secondLoad.complete(ReminderHistoryPage(
        items: [
          _historyItem(
            id: 2,
            category: 'deadline',
            logicalKey: 'dl-1',
            reasonCode: 'scheduleReplaced',
          ),
        ],
        snapshotMaxId: 2,
        nextBeforeId: null,
        checkedAt: DateTime(2026, 11, 18, 12, 1),
        historyGeneration: 1,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('后台提醒检查'), findsNothing);
      expect(find.textContaining('提醒时间已调整'), findsOneWidget);
    });

    testWidgets(
        'initial error shows retry button instead of empty message and refresh error preserves cache',
        (tester) async {
      var calls = 0;
      final store = _ScreenTestStore()
        ..onLoadHistory = (_) async {
          calls++;
          if (calls == 1) {
            throw const ReminderHistoryException(
              'history_unavailable',
              '初次加载失败',
            );
          }
          if (calls == 2) {
            return ReminderHistoryPage(
              items: [_historyItem(id: 5, logicalKey: 'dl-cached')],
              snapshotMaxId: 5,
              nextBeforeId: null,
              checkedAt: DateTime(2026, 11, 18, 12, 5),
              historyGeneration: 1,
            );
          }
          throw const ReminderHistoryException(
            'history_unavailable',
            '刷新网络抖动',
          );
        };
      addTearDown(store.dispose);

      await tester.pumpWidget(MaterialApp(
        home: ReminderHistoryScreen(store: store),
      ));
      await tester.pumpAndSettle();

      expect(find.text('最近 30 天没有符合条件的提醒记录'), findsNothing);
      expect(find.text('提醒记录当前不可用或仍在清理'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '重试'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, '重试'));
      await tester.pumpAndSettle();

      expect(find.textContaining('已安排'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      expect(find.text('提醒记录当前不可用或仍在清理'), findsOneWidget);
      expect(find.textContaining('已安排'), findsOneWidget);
    });

    testWidgets('adjacent items with different scheduledAt are not folded',
        (tester) async {
      final store = _ScreenTestStore()
        ..onLoadHistory = (_) async => ReminderHistoryPage(
              items: [
                _historyItem(
                  id: 2,
                  logicalKey: 'same-key',
                  scheduledAt: DateTime(2026, 11, 18, 16, 0),
                ),
                _historyItem(
                  id: 1,
                  logicalKey: 'same-key',
                  scheduledAt: DateTime(2026, 11, 18, 14, 0),
                ),
              ],
              snapshotMaxId: 2,
              nextBeforeId: null,
              checkedAt: DateTime(2026, 11, 18, 12, 0),
              historyGeneration: 1,
            );
      addTearDown(store.dispose);

      await tester.pumpWidget(MaterialApp(
        home: ReminderHistoryScreen(store: store),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('目标 11月18日 16:00'), findsOneWidget);
      expect(find.textContaining('目标 11月18日 14:00'), findsOneWidget);
    });
  });

  group('Identity isolation across screens', () {
    testWidgets(
        'history, status, and health screens clear old account data on identity switch',
        (tester) async {
      final notifications = _FakeNotificationService();
      late final _ScreenTestStore store;
      store = _ScreenTestStore(notifications: notifications);
      store.onLoadHistory = (_) async {
        if (store.accountHash == 'hash-a') {
          return ReminderHistoryPage(
            items: [_historyItem(id: 1, logicalKey: 'a-key')],
            snapshotMaxId: 1,
            nextBeforeId: null,
            checkedAt: DateTime(2026, 11, 18, 12, 0),
            historyGeneration: 1,
          );
        }
        return ReminderHistoryPage(
          items: const [],
          snapshotMaxId: 0,
          nextBeforeId: null,
          checkedAt: DateTime(2026, 11, 18, 12, 1),
          historyGeneration: 2,
        );
      };
      store.onExplainReminder = (_, __) async {
        if (store.accountHash == 'hash-a') {
          return ReminderExplanation(
            checkedAt: DateTime(2026, 11, 18, 12, 0),
            subjectKind: 'summary',
            subjectId: '0',
            displayName: '账号A摘要',
            categories: const [],
            queryWarnings: const [],
          );
        }
        return ReminderExplanation(
          checkedAt: DateTime(2026, 11, 18, 12, 1),
          subjectKind: 'summary',
          subjectId: '0',
          displayName: '账号B摘要',
          categories: const [],
          queryWarnings: const [],
        );
      };
      addTearDown(store.dispose);

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MaterialApp(
        home: Column(
          children: [
            Expanded(child: ReminderHistoryScreen(store: store)),
            Expanded(
              child: ReminderStatusScreen(
                store: store,
                kind: 'summary',
                id: '0',
              ),
            ),
            Expanded(child: ReminderHealthScreen(store: store)),
          ],
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('账号A摘要'), findsOneWidget);

      notifications.nextHealth = const ReminderHealth(
        notifications: false,
        assignmentChannel:
            ReminderChannelHealth(ReminderChannelStatus.disabled),
        manualChannel: ReminderChannelHealth(ReminderChannelStatus.disabled),
        summaryChannel: ReminderChannelHealth(ReminderChannelStatus.disabled),
        scheduleRecoveryPending: false,
      );
      store.switchIdentityForTest(hash: 'hash-b', epoch: 2, generation: 2);
      await tester.pumpAndSettle();

      expect(find.text('账号A摘要'), findsNothing);
      expect(find.text('账号B摘要'), findsOneWidget);
      expect(find.textContaining('目标 11月18日 14:00'), findsNothing);
      expect(find.text('最近 30 天没有符合条件的提醒记录'), findsOneWidget);
    });
  });

  group('Navigation back stack & manual draft preservation', () {
    testWidgets(
        'manual editor preserves unsaved draft when opening reminder status and returning',
        (tester) async {
      final store = _ScreenTestStore()
        ..onExplainReminder = (_, __) async => ReminderExplanation(
              checkedAt: DateTime(2026, 11, 18, 12, 0),
              subjectKind: 'manual',
              subjectId: 'm-1',
              displayName: '原保存日程',
              categories: const [],
              queryWarnings: const [],
            );
      addTearDown(store.dispose);

      final entry = ManualEntry(
        id: 'm-1',
        title: '原保存日程',
        kind: 'todo',
        at: DateTime(2026, 11, 20, 10, 0),
        remind: true,
        done: false,
      );
      store.setNotebookForTest(StudyNotebook(entries: [entry]));

      await tester.pumpWidget(MaterialApp(
        home: ManualEntryEditor(store: store, entry: entry),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        '未保存草稿标题',
      );
      await tester.pump();

      await tester.ensureVisible(find.text('提醒状态'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('提醒状态'));
      await tester.pumpAndSettle();

      expect(find.text('提醒状态'), findsOneWidget);
      expect(
        find.text('当前展示已保存事项的提醒状态；编辑页中的未保存修改需保存后才会生效。'),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('未保存草稿标题'), findsOneWidget);
    });

    testWidgets(
        'status screen supports initial failure retry and lifecycle resume reload',
        (tester) async {
      var calls = 0;
      final store = _ScreenTestStore()
        ..onExplainReminder = (_, __) async {
          calls++;
          if (calls == 1) {
            throw const ReminderHistoryException(
              'history_unavailable',
              '首次读取失败',
            );
          }
          return ReminderExplanation(
            checkedAt: DateTime(2026, 11, 18, 12, calls),
            subjectKind: 'assignment',
            subjectId: 'a-1',
            displayName: '恢复作业 第$calls次',
            categories: const [],
            queryWarnings: const [],
          );
        };
      addTearDown(store.dispose);

      await tester.pumpWidget(MaterialApp(
        home: ReminderStatusScreen(
          store: store,
          kind: 'assignment',
          id: 'a-1',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('首次读取失败'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, '重新查询'));
      await tester.pumpAndSettle();

      expect(find.text('恢复作业 第2次'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('恢复作业 第3次'), findsOneWidget);
    });

    testWidgets('push navigation keeps back stack and AppShell highlights 我的',
        (tester) async {
      final store = _ScreenTestStore();
      store.onLoadHistory = (_) async => ReminderHistoryPage(
            items: [_historyItem(id: 1)],
            snapshotMaxId: 1,
            nextBeforeId: null,
            checkedAt: DateTime(2026, 11, 18, 12, 0),
            historyGeneration: 1,
          );
      store.onExplainReminder = (_, __) async => ReminderExplanation(
            checkedAt: DateTime(2026, 11, 18, 12, 0),
            subjectKind: 'summary',
            subjectId: '0',
            displayName: '每日摘要',
            categories: const [],
            queryWarnings: const [],
          );
      addTearDown(store.dispose);

      final router = GoRouter(
        initialLocation: '/reminder-health',
        routes: [
          ShellRoute(
            builder: (_, __, child) =>
                AppShell(assignmentStore: store, child: child),
            routes: [
              GoRoute(
                path: '/reminder-health',
                builder: (_, __) => ReminderHealthScreen(store: store),
              ),
              GoRoute(
                path: '/reminder-history',
                builder: (_, __) => ReminderHistoryScreen(store: store),
              ),
              GoRoute(
                path: '/reminder-status/:kind/:id',
                builder: (_, s) => ReminderStatusScreen(
                  store: store,
                  kind: s.pathParameters['kind']!,
                  id: s.pathParameters['id']!,
                ),
              ),
              GoRoute(
                path: '/reminders',
                builder: (_, __) => const Scaffold(body: Text('提醒设置占位')),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final target = find.text('提醒记录与原因');
      await tester.dragUntilVisible(
        target,
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 3);
      expect(router.canPop(), isTrue);

      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('提醒体检'), findsOneWidget);
    });

    testWidgets(
        'H6: status screen surfaces serviceWarnings after retryReminderRecovery',
        (tester) async {
      final store = _ScreenTestStore()
        ..nextServiceWarnings = const ['隐私清理未确认']
        ..onExplainReminder = (_, __) async => ReminderExplanation(
              checkedAt: DateTime(2026, 11, 18, 12, 0),
              subjectKind: 'assignment',
              subjectId: 'a-1',
              displayName: '测试作业',
              categories: const [],
              queryWarnings: const [],
            );
      addTearDown(store.dispose);

      await tester.pumpWidget(MaterialApp(
        home: ReminderStatusScreen(
          store: store,
          kind: 'assignment',
          id: 'a-1',
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '重试提醒恢复'));
      await tester.pumpAndSettle();
      expect(find.textContaining('隐私清理未确认'), findsOneWidget);
    });

    testWidgets(
        'M4: status screen reloads when returning from pushed reminders route',
        (tester) async {
      var calls = 0;
      final store = _ScreenTestStore()
        ..onExplainReminder = (_, __) async {
          calls++;
          return ReminderExplanation(
            checkedAt: DateTime(2026, 11, 18, 12, calls),
            subjectKind: 'assignment',
            subjectId: 'a-1',
            displayName: '恢复作业 第$calls次',
            categories: const [],
            queryWarnings: const [],
          );
        };
      addTearDown(store.dispose);

      final router = GoRouter(
        initialLocation: '/reminder-status/assignment/a-1',
        routes: [
          GoRoute(
            path: '/reminder-status/:kind/:id',
            builder: (_, s) => ReminderStatusScreen(
              store: store,
              kind: s.pathParameters['kind']!,
              id: s.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/reminders',
            builder: (context, __) => Scaffold(
              body: ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('返回状态页'),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(calls, 1);

      await tester.tap(find.widgetWithText(OutlinedButton, '打开提醒设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('返回状态页'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.text('恢复作业 第2次'), findsOneWidget);
    });

    testWidgets(
        'L2: manual editor pushes reminder status via GoRouter with unsaved=1',
        (tester) async {
      final store = _ScreenTestStore()
        ..onExplainReminder = (_, __) async => ReminderExplanation(
              checkedAt: DateTime(2026, 11, 18, 12, 0),
              subjectKind: 'manual',
              subjectId: 'm-1',
              displayName: '个人待办',
              categories: const [],
              queryWarnings: const [],
            );
      addTearDown(store.dispose);

      final entry = ManualEntry(
        id: 'm-1',
        title: '原待办标题',
        kind: 'todo',
        at: DateTime(2026, 11, 20, 10, 0),
        remind: true,
        done: false,
      );
      String? pushedLocation;
      final router = GoRouter(
        initialLocation: '/agenda',
        routes: [
          GoRoute(
            path: '/agenda',
            builder: (_, __) => ManualEntryEditor(store: store, entry: entry),
          ),
          GoRoute(
            path: '/reminder-status/:kind/:id',
            builder: (_, s) {
              pushedLocation = s.uri.toString();
              return ReminderStatusScreen(
                store: store,
                kind: s.pathParameters['kind']!,
                id: s.pathParameters['id']!,
                hasUnsavedEdits: s.uri.queryParameters['unsaved'] == '1',
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '未保存的新标题');
      await tester.pumpAndSettle();

      final statusBtn = find.text('提醒状态');
      await tester.ensureVisible(statusBtn);
      await tester.pumpAndSettle();
      await tester.tap(statusBtn);
      await tester.pumpAndSettle();

      expect(pushedLocation, '/reminder-status/manual/m-1?unsaved=1');
      expect(find.textContaining('未保存修改需保存后才会生效'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('未保存的新标题'), findsOneWidget);
    });
  });
}

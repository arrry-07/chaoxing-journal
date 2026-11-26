import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_buttons.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_grouped_card.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_pixel_buddy.dart';
import 'package:study_assistant_mobile/src/features/widgets/manual_home_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/assignment_sync_progress.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Notifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}

  @override
  Future<void> rescheduleManual(List<ManualEntry> items) async {}

  @override
  Future<void> rescheduleSummary(
    List<Assignment> items,
    PersonalWorkspace personal,
    DateTime? lastSync,
  ) async {}
}

class _Snapshot extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _MemorySessionStore extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'student-v1903';

  @override
  Future<String?> readChaoxingPassword() async => 'secret';

  @override
  Future<String?> readChaoxingDisplayName() async => '手记同学';

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _ControllableStore extends AssignmentStore {
  _ControllableStore({super.clock})
      : super(
          sessionStore: _MemorySessionStore(),
          notificationService: _Notifications(),
          widgetSnapshotService: _Snapshot(),
        );

  Completer<void>? syncGate;
  SyncReport nextReport = const SyncReport(phase: SyncPhase.success);
  AssignmentSyncProgress? mockProgress;

  @override
  AssignmentSyncProgress? get homeSyncProgress =>
      mockProgress ?? super.homeSyncProgress;

  @override
  Future<void> syncAssignments() async {
    final gate = syncGate;
    if (gate != null) {
      await gate.future;
    }
    syncReport = nextReport;
    notifyListeners();
  }
}

Assignment _work(
  String id, {
  String course = '高等数学',
  required String title,
  DateTime? due,
  bool deadlineTrusted = true,
  String status = 'pending',
  required DateTime syncedAt,
}) =>
    Assignment(
      id: 'cx:work:1:2:$id',
      courseName: course,
      title: title,
      deadlineAt: due,
      deadlineTrusted: deadlineTrusted,
      deadlineReadFailed: due == null && !deadlineTrusted,
      requirementsText: '',
      status: status,
      lastSyncedAt: syncedAt,
    );

ManualEntry _manual(
  String id, {
  String title = '手动任务',
  DateTime? at,
}) =>
    ManualEntry(
      id: id,
      title: title,
      kind: ManualEntry.kindTodo,
      course: '高等数学',
      at: at,
    );

Future<_ControllableStore> _createStore({
  List<Assignment> assignments = const [],
  List<ManualEntry> entries = const [],
  DateTime Function()? clock,
  SyncReport? initialReport,
}) async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  FlutterSecureStorage.setMockInitialValues({});
  final store = _ControllableStore(clock: clock);
  await store.restoreSession();
  if (assignments.isNotEmpty) {
    await store.repository.mergeAndSave(assignments);
    await store.restoreSession();
  }
  if (entries.isNotEmpty) {
    await store.saveNotebook(
      (_) => StudyNotebook(entries: entries),
      store.accountEpoch,
    );
  }
  if (initialReport != null) {
    store.syncReport = initialReport;
    store.notifyListeners();
  }
  return store;
}

Future<void> _pumpHome(
  WidgetTester tester,
  AssignmentStore store, {
  required DateTime now,
  ThemeData? theme,
  double textScale = 1.0,
  bool disableAnimations = false,
}) async {
  final router = GoRouter(
    initialLocation: '/assignments',
    routes: [
      GoRoute(
        path: '/assignments',
        builder: (_, __) => Scaffold(
          body: AssignmentListScreen(store: store, clock: () => now),
        ),
      ),
      GoRoute(
        path: '/sync',
        builder: (_, __) => const Scaffold(body: Text('同步详情页')),
      ),
      GoRoute(
        path: '/agenda',
        builder: (_, __) => const Scaffold(body: Text('待办页')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MaterialApp.router(
      theme: theme ?? StudyAssistantTheme.light,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

JournalGroupedCard _sectionCardForText(WidgetTester tester, String text) {
  final itemFinder = find.text(text);
  expect(itemFinder, findsOneWidget);
  return tester.widget<JournalGroupedCard>(
    find
        .ancestor(of: itemFinder, matching: find.byType(JournalGroupedCard))
        .first,
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));

  group('M1 · home ambient glow, emphasized cards, and unframed chrome', () {
    testWidgets(
        'ambient glow fades out past 110dp, only pinned/today cards emphasize, and top chrome stays unframed',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0); // Beijing 10:00
      final pinnedWork = _work(
        'pinned-1',
        title: '置顶课程实验',
        due: now.add(const Duration(days: 5)),
        syncedAt: now,
      );
      final todayWork = _work(
        'today-1',
        title: '今天到期作业',
        due: now.add(const Duration(hours: 6)),
        syncedAt: now,
      );
      final tomorrowWork = _work(
        'tomorrow-1',
        title: '明天到期作业',
        due: now.add(const Duration(days: 1, hours: 6)),
        syncedAt: now,
      );
      final futureWork = _work(
        'future-1',
        title: '未来常规作业',
        due: now.add(const Duration(days: 4, hours: 6)),
        syncedAt: now,
      );
      final noDeadlineWork = _work(
        'nodue-1',
        title: '无截止作业',
        due: null,
        deadlineTrusted: true,
        syncedAt: now,
      );
      final overdueWork = _work(
        'overdue-1',
        title: '逾期未交作业',
        due: now.subtract(const Duration(days: 1)),
        syncedAt: now,
      );

      final store = await _createStore(
        assignments: [
          pinnedWork,
          todayWork,
          tomorrowWork,
          futureWork,
          noDeadlineWork,
          overdueWork,
          for (var i = 0; i < 6; i++)
            _work(
              'filler-$i',
              title: '填充作业 $i',
              due: now.add(Duration(days: 6 + i, hours: 3)),
              syncedAt: now,
            ),
        ],
        clock: () => now,
        initialReport:
            SyncReport(phase: SyncPhase.success, lastDataSuccessAt: now),
      );
      addTearDown(store.dispose);
      await store.togglePin(pinnedWork);

      await _pumpHome(tester, store, now: now);

      expect(find.byKey(const ValueKey('home-ambient-glow')), findsOneWidget);

      // Top 4 action buttons & status/summary stay unframed.
      for (final key in const [
        ValueKey('home-agenda-entry'),
        ValueKey('home-theme-toggle'),
        ValueKey('home-more-menu'),
        ValueKey('home-sync-status'),
        ValueKey('home-due-summary'),
      ]) {
        final target = find.byKey(key);
        expect(target, findsOneWidget);
        expect(
          find.ancestor(of: target, matching: find.byType(JournalGroupedCard)),
          findsNothing,
        );
        expect(
          find.ancestor(of: target, matching: find.byType(Card)),
          findsNothing,
        );
      }
      final statusMaterial = tester.widget<Material>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('home-sync-status')),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(statusMaterial.type, MaterialType.transparency);

      // Only pinned and today cards carry emphasized: true.
      expect(_sectionCardForText(tester, '置顶课程实验').emphasized, isTrue);
      expect(_sectionCardForText(tester, '今天到期作业').emphasized, isTrue);
      expect(_sectionCardForText(tester, '明天到期作业').emphasized, isFalse);

      await tester.scrollUntilVisible(
        find.text('未来常规作业'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(_sectionCardForText(tester, '未来常规作业').emphasized, isFalse);

      await tester.scrollUntilVisible(
        find.text('无截止作业'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(_sectionCardForText(tester, '无截止作业').emphasized, isFalse);

      await tester.scrollUntilVisible(
        find.text('逾期未交作业'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(_sectionCardForText(tester, '逾期未交作业').emphasized, isFalse);

      // Once scrolled >= 110dp, ambient glow fades out completely.
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-ambient-glow')), findsNothing);
    });
  });

  group(
      'M2 · pixel buddy integration, moods, whisper, sync spinner & responsive',
      () {
    testWidgets(
        'title buddy size, sliver mini buddy, showPixelBuddy toggle, and 4 moods',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0);
      final store = await _createStore(
        assignments: [
          _work(
            'today-1',
            title: '今日急单',
            due: now.add(const Duration(hours: 4)),
            syncedAt: now,
          ),
          for (var i = 0; i < 8; i++)
            _work(
              'future-$i',
              title: '后续作业 $i',
              due: now.add(Duration(days: 2 + i, hours: 3)),
              syncedAt: now,
            ),
        ],
        clock: () => now,
        initialReport:
            SyncReport(phase: SyncPhase.success, lastDataSuccessAt: now),
      );
      addTearDown(store.dispose);

      await _pumpHome(tester, store, now: now);

      // Initial render keeps single '课业手记' title Text and 22dp buddy at 360dp.
      expect(find.text('课业手记'), findsOneWidget);
      final titleBuddyFinder = find.byKey(const ValueKey('home-pixel-buddy'));
      expect(titleBuddyFinder, findsOneWidget);
      final titleBuddy = tester.widget<JournalPixelBuddy>(titleBuddyFinder);
      expect(titleBuddy.size, 22.0);
      expect(titleBuddy.mood, JournalPixelBuddyMood.dueToday);
      expect(
        find.byKey(const ValueKey('home-sliver-pixel-buddy')),
        findsNothing,
      );

      // Scrolling down reveals the floating mini buddy.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
      await tester.pumpAndSettle();
      final sliverBuddyFinder =
          find.byKey(const ValueKey('home-sliver-pixel-buddy'));
      expect(sliverBuddyFinder, findsOneWidget);
      final sliverBuddy = tester.widget<JournalPixelBuddy>(sliverBuddyFinder);
      expect(sliverBuddy.mini, isTrue);
      expect(sliverBuddy.mood, JournalPixelBuddyMood.dueToday);

      // Toggling showPixelBuddy hides/shows both instances immediately.
      await store.saveDisplay(store.display.copyWith(showPixelBuddy: false));
      await tester.pumpAndSettle();
      expect(titleBuddyFinder, findsNothing);
      expect(sliverBuddyFinder, findsNothing);

      await store.saveDisplay(store.display.copyWith(showPixelBuddy: true));
      await tester.pumpAndSettle();
      expect(titleBuddyFinder, findsOneWidget);
      expect(sliverBuddyFinder, findsOneWidget);

      // Switch to idle mood: dueToday == 0, completedToday == 0, non-empty list.
      store.replaceAssignmentsForTest([
        _work(
          'tomorrow-only',
          title: '明日作业',
          due: now.add(const Duration(days: 1, hours: 4)),
          syncedAt: now,
        ),
      ]);
      store.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        tester.widget<JournalPixelBuddy>(titleBuddyFinder).mood,
        JournalPixelBuddyMood.idle,
      );

      // Switch to allClear mood: dueToday == 0 and completedToday > 0.
      store.replaceAssignmentsForTest([
        _work(
          'done-today',
          title: '今日已完成',
          due: now.add(const Duration(hours: 3)),
          status: 'submitted',
          syncedAt: now,
        ),
      ]);
      store.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        tester.widget<JournalPixelBuddy>(titleBuddyFinder).mood,
        JournalPixelBuddyMood.allClear,
      );
    });

    testWidgets(
        'tap whisper auto-restores after 2s without timeout; busy & errors take priority',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0);
      final store = await _createStore(
        assignments: [
          _work(
            'today-1',
            title: '今日课业',
            due: now.add(const Duration(hours: 5)),
            syncedAt: now,
          ),
        ],
        clock: () => now,
        initialReport:
            SyncReport(phase: SyncPhase.success, lastDataSuccessAt: now),
      );
      addTearDown(store.dispose);

      await _pumpHome(tester, store, now: now);
      expect(find.text('刚刚更新'), findsOneWidget);

      // Tap buddy -> whisper appears in home-sync-status, restores after 2s.
      await tester.tap(find.byKey(const ValueKey('home-pixel-buddy')));
      await tester.pump();
      expect(find.text('刚刚更新'), findsNothing);
      expect(find.text('今日待办1项，稳步推进'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2050));
      await tester.pumpAndSettle();
      expect(find.text('刚刚更新'), findsOneWidget);
      expect(find.text('今日待办1项，稳步推进'), findsNothing);

      // Busy state drives rotating spinner glyph + sync phrase + preserves _syncProgressLabel.
      store.syncGate = Completer<void>();
      store.mockProgress = AssignmentSyncProgress(
        stage: AssignmentSyncStage.courses,
        assignments: const [],
        pendingDetailIds: const {},
        resolvedCount: 0,
        attemptedCount: 0,
      );
      await tester.tap(find.byTooltip('刷新作业'));
      await tester.pump();
      expect(
        tester
            .widget<JournalPixelBuddy>(
                find.byKey(const ValueKey('home-pixel-buddy')))
            .mood,
        JournalPixelBuddyMood.syncing,
      );
      final statusFinder = find.byKey(const ValueKey('home-sync-status'));
      expect(
        find.descendant(
          of: statusFinder,
          matching: find.text(kJournalSpinnerGlyphs[0]),
        ),
        findsOneWidget,
      );
      expect(find.text('翻阅课表中…'), findsOneWidget);
      expect(find.text('正在读取课程'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 180));
      expect(
        find.descendant(
          of: statusFinder,
          matching: find.text(kJournalSpinnerGlyphs[1]),
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 180));
      expect(
        find.descendant(
          of: statusFinder,
          matching: find.text(kJournalSpinnerGlyphs[2]),
        ),
        findsOneWidget,
      );

      // Tapping buddy during busy does not overwrite sync phrase.
      await tester.tap(find.byKey(const ValueKey('home-pixel-buddy')));
      await tester.pump();
      expect(find.text('翻阅课表中…'), findsOneWidget);

      // Finish busy with failure -> error state takes priority over whisper.
      store.mockProgress = null;
      store.nextReport = const SyncReport(
        phase: SyncPhase.failed,
        issues: [SyncIssue(SyncIssueKind.authExpired, 'expired')],
      );
      store.syncGate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('更新失败 · 显示上次记录'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-pixel-buddy')));
      await tester.pumpAndSettle();
      expect(find.text('更新失败 · 显示上次记录'), findsOneWidget);
      expect(find.text('今日待办1项，稳步推进'), findsNothing);
    });

    testWidgets(
        '320dp@2x large text renders zero overflow in light/dark and reduced motion freezes spinner',
        (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0);
      final store = await _createStore(
        assignments: [
          for (var i = 0; i < 6; i++)
            _work(
              'item-$i',
              title: '大字窄屏作业 $i',
              due: now.add(Duration(hours: 2 + i)),
              syncedAt: now,
            ),
        ],
        clock: () => now,
        initialReport:
            SyncReport(phase: SyncPhase.success, lastDataSuccessAt: now),
      );
      addTearDown(store.dispose);

      for (final theme in [
        StudyAssistantTheme.light,
        StudyAssistantTheme.dark
      ]) {
        await _pumpHome(
          tester,
          store,
          now: now,
          theme: theme,
          textScale: 2.0,
        );
        expect(tester.takeException(), isNull);
        final buddy = tester.widget<JournalPixelBuddy>(
          find.byKey(const ValueKey('home-pixel-buddy')),
        );
        expect(buddy.size, 20.0);

        await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('home-sliver-pixel-buddy')),
          findsNothing,
        );
      }

      // Reduced motion keeps busy spinner glyph fixed at '✻'.
      tester.view.physicalSize = const Size(412, 915);
      store.syncGate = Completer<void>();
      store.nextReport = const SyncReport(phase: SyncPhase.success);
      await _pumpHome(
        tester,
        store,
        now: now,
        disableAnimations: true,
      );
      await tester.tap(find.byTooltip('刷新作业'));
      await tester.pump();
      expect(find.text('✻'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 360));
      expect(find.text('✻'), findsOneWidget);
      store.syncGate!.complete();
      await tester.pumpAndSettle();
    });
  });

  group(
      'M3 · home pills press scale, modal sheet motion, and pin/complete micro-bounce',
      () {
    testWidgets(
        'home action pills use JournalPressableScale(0.97) and filter sheet applies modalSheetAnimationStyle',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0);
      final store = await _createStore(
        assignments: [
          _work(
            'w1',
            title: '高数练习',
            due: now.add(const Duration(hours: 4)),
            syncedAt: now,
          ),
        ],
        clock: () => now,
      );
      addTearDown(store.dispose);

      await _pumpHome(tester, store, now: now);

      for (final finder in [
        find.text('搜索与筛选'),
        find.byKey(const ValueKey('current-home-sort')),
        find.byKey(const ValueKey('home-add-manual')),
      ]) {
        final pressable = tester.widget<JournalPressableScale>(
          find
              .ancestor(
                of: finder,
                matching: find.byType(JournalPressableScale),
              )
              .first,
        );
        expect(pressable.pressScale, 0.97);
      }

      // Press down on add pill -> scales below 1.0, release -> settles back to 1.0.
      final addPill = find.byKey(const ValueKey('home-add-manual'));
      final pressScaleFinder = find
          .ancestor(
            of: addPill,
            matching: find.byType(JournalPressableScale),
          )
          .first;
      final g = await tester.startGesture(tester.getCenter(addPill));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      final transformDown = tester.widget<Transform>(
        find
            .descendant(
              of: pressScaleFinder,
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(transformDown.transform.storage[0], lessThan(1.0));
      // Cancel gesture so press springs back to 1.0 without navigating away.
      await g.cancel();
      await tester.pumpAndSettle();
      final transformUp = tester.widget<Transform>(
        find
            .descendant(
              of: pressScaleFinder,
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(transformUp.transform.storage[0], 1.0);

      // Filter modal bottom sheet opens with normal duration and settles cleanly.
      await tester.tap(find.byKey(const ValueKey('current-home-sort')));
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('搜索、筛选与排序'), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('搜索、筛选与排序'), findsNothing);

      // Under reduced motion, modal sheet opens immediately on first frame.
      await _pumpHome(tester, store, now: now, disableAnimations: true);
      await tester.tap(find.byKey(const ValueKey('current-home-sort')));
      await tester.pump();
      expect(find.text('搜索、筛选与排序'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pump(const Duration(milliseconds: 360));
      await tester.pumpAndSettle();
    });

    testWidgets(
        'pinning assignment or manual entry triggers JournalMicroBounce, and completing manual entry fires pulse',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0);
      final assignment = _work(
        'pin-a',
        title: '可置顶作业',
        due: now.add(const Duration(days: 2)),
        syncedAt: now,
      );
      final manual = _manual(
        'm-pin',
        title: '可置顶手动待办',
        at: now.add(const Duration(hours: 6)),
      );
      final store = await _createStore(
        assignments: [assignment],
        entries: [manual],
        clock: () => now,
      );
      addTearDown(store.dispose);

      await _pumpHome(tester, store, now: now);

      // Pin assignment via context menu -> increments outer JournalMicroBounce pulse.
      await tester.longPress(find.text('可置顶作业'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('置顶'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));

      final assignmentBounce = tester.widget<JournalMicroBounce>(
        find
            .ancestor(
              of: find.byKey(ValueKey('assignment-${assignment.id}')),
              matching: find.byType(JournalMicroBounce),
            )
            .first,
      );
      expect(assignmentBounce.pulse, 1);
      final assignmentScale = tester.widget<Transform>(
        find
            .descendant(
              of: find
                  .ancestor(
                    of: find.byKey(ValueKey('assignment-${assignment.id}')),
                    matching: find.byType(JournalMicroBounce),
                  )
                  .first,
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(assignmentScale.transform.storage[0], greaterThan(1.0));
      await tester.pumpAndSettle();

      // Pin manual entry via context menu -> passes bouncePulse to ManualHomeCard.
      await tester.longPress(find.text('可置顶手动待办'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('置顶').last);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));

      final manualCard = tester.widget<ManualHomeCard>(
        find.byKey(const ValueKey('manual-m-pin')),
      );
      expect(manualCard.bouncePulse, 1);
      final manualScale = tester.widget<Transform>(
        find
            .descendant(
              of: find.byKey(const ValueKey('manual-m-pin')),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(manualScale.transform.storage[0], greaterThan(1.0));
      await tester.pumpAndSettle();

      // Complete manual entry -> completes cleanly and invokes HomeManualActions.completeWithUndo.
      await tester.tap(find.byKey(const ValueKey('complete-manual-m-pin')));
      await tester.pumpAndSettle();
      expect(store.notebook.entries.single.done, isTrue);
      expect(tester.takeException(), isNull);

      // Reduced motion skips bounce increment on pin.
      final assignment2 = _work(
        'pin-reduced',
        title: '减弱动态作业',
        due: now.add(const Duration(days: 3)),
        syncedAt: now,
      );
      await store.repository.mergeAndSave([assignment2]);
      await store.restoreSession();
      await _pumpHome(tester, store, now: now, disableAnimations: true);
      await tester.longPress(find.text('减弱动态作业'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('置顶').last);
      await tester.pumpAndSettle();
      final reducedBounce = tester.widget<JournalMicroBounce>(
        find
            .ancestor(
              of: find.byKey(ValueKey('assignment-${assignment2.id}')),
              matching: find.byType(JournalMicroBounce),
            )
            .first,
      );
      expect(reducedBounce.pulse, 0);
    });
  });
}

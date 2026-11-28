import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/display_preferences.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/pinned_assignments.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
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
}

class _Snapshot extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _MemorySessionStore extends SecureSessionStore {
  String? account = 'student-1';

  @override
  Future<String?> readChaoxingAccount() async => account;

  @override
  Future<String?> readChaoxingPassword() async =>
      account == null ? null : 'secret';

  @override
  Future<String?> readChaoxingDisplayName() async => '测试同学';

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;

  @override
  Future<void> clear() async {
    account = null;
  }
}

class _ControllablePinRepo extends LocalAssignmentRepository {
  Completer<void>? saveStarted;
  Completer<void>? saveGate;
  Object? gateError;
  int saveCalls = 0;

  @override
  Future<void> savePinnedAssignments(
      PinnedAssignments pins, String account) async {
    saveCalls++;
    final started = saveStarted;
    if (started != null && !started.isCompleted) started.complete();
    final gate = saveGate;
    if (gate != null) {
      saveGate = null;
      await gate.future;
    }
    final err = gateError;
    if (err != null) {
      gateError = null;
      throw err;
    }
    await super.savePinnedAssignments(pins, account);
  }
}

Assignment _work(
  String id, {
  String title = '高等数学作业',
  DateTime? due,
  String? submitUrl,
  required DateTime syncedAt,
}) =>
    Assignment(
      id: 'cx:work:1:2:$id',
      courseName: '高等数学',
      title: title,
      deadlineAt: due,
      deadlineTrusted: due != null,
      requirementsText: '',
      status: 'pending',
      submitUrl: submitUrl,
      lastSyncedAt: syncedAt,
    );

Future<AssignmentStore> _authenticatedStore(List<Assignment> items) async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  FlutterSecureStorage.setMockInitialValues({});
  final store = AssignmentStore(
    sessionStore: _MemorySessionStore(),
    notificationService: _Notifications(),
    widgetSnapshotService: _Snapshot(),
  );
  await store.restoreSession();
  await store.repository.mergeAndSave(items);
  await store.restoreSession();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixedMorning = DateTime(2026, 11, 22, 10, 0);

  testWidgets(
      'right swipe toggles today plan (30 min default) and left swipe toggles pin',
      (tester) async {
    final due = fixedMorning.add(const Duration(days: 1));
    final item = _work('w1', title: '手势作业一', due: due, syncedAt: fixedMorning);
    final store = await _authenticatedStore([item]);
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
          body: AssignmentListScreen(store: store, clock: () => fixedMorning),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.byKey(ValueKey('assignment-${item.id}'));
    expect(tile, findsOneWidget);

    // Right swipe beyond 72dp threshold adds to today's plan with 30 minutes.
    await tester.drag(tile, const Offset(140, 0));
    await tester.pumpAndSettle();

    final day = PersonalWorkspace.dayKey(fixedMorning);
    expect(
      store.personal.plans
          .where((p) => p.day == day && p.assignmentId == item.id)
          .single
          .minutes,
      30,
    );
    expect(find.text('已加入今日计划（30 分钟）'), findsOneWidget);

    // Second right swipe removes from today's plan.
    await tester.drag(tile, const Offset(140, 0));
    await tester.pumpAndSettle();
    expect(
      store.personal.plans
          .where((p) => p.day == day && p.assignmentId == item.id),
      isEmpty,
    );
    expect(find.text('已移出今日计划'), findsOneWidget);

    // Left swipe beyond -68dp threshold pins and then unpins.
    await tester.drag(tile, const Offset(-140, 0));
    await tester.pumpAndSettle();
    expect(store.isPinned(item), isTrue);
    expect(find.text('置顶'), findsOneWidget);

    await tester.drag(tile, const Offset(-140, 0));
    await tester.pumpAndSettle();
    expect(store.isPinned(item), isFalse);
  });

  testWidgets('long press opens context menu and supports hide with undo',
      (tester) async {
    final due = fixedMorning.add(const Duration(days: 2));
    final item = _work(
      'w2',
      title: '长按菜单作业',
      due: due,
      submitUrl: 'https://mooc1.chaoxing.com/work/view?workid=w2',
      syncedAt: fixedMorning,
    );
    final store = await _authenticatedStore([item]);
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
          body: AssignmentListScreen(store: store, clock: () => fixedMorning),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('长按菜单作业'));
    await tester.pumpAndSettle();

    expect(find.text('在学习通打开'), findsOneWidget);
    expect(find.text('置顶'), findsOneWidget);
    expect(find.text('加入今日计划'), findsOneWidget);
    expect(find.text('复制链接'), findsOneWidget);
    expect(find.text('在本机隐藏'), findsOneWidget);

    await tester.tap(find.text('在本机隐藏'));
    await tester.pumpAndSettle();

    expect(find.text('长按菜单作业'), findsNothing);
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('长按菜单作业'), findsOneWidget);
  });

  testWidgets('home deduplicates today badge and merges pinned countdown line',
      (tester) async {
    final now = fixedMorning;
    final todayDue = now.add(const Duration(hours: 3));
    final item =
        _work('w3', title: '今日合并时间作业', due: todayDue, syncedAt: fixedMorning);
    final store = await _authenticatedStore([item]);
    addTearDown(store.dispose);
    await store.saveDisplay(const DisplayPreferences(countdown: true));

    await tester.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
          body: AssignmentListScreen(store: store, clock: () => now),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Group header owns '今天'; card must not repeat '今天截止' pill.
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('今天截止'), findsNothing);
    expect(find.text('剩3小时'), findsOneWidget);

    // Pin the item and check merged single metadata line in pinned section.
    await store.togglePin(item);
    await tester.pumpAndSettle();
    expect(find.text('置顶'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data ?? '').startsWith('截止 ') &&
            (w.data ?? '').contains(' · 剩余'),
      ),
      findsOneWidget,
    );

    // Standalone AssignmentCard with showFullDeadline=true still keeps '今天截止'.
    await tester.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
          body: AssignmentCard(
            assignment: item,
            now: now,
            showFullDeadline: true,
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('今天截止'), findsOneWidget);
  });

  group('v1.93.1 M1 · pinned drag-to-reorder regression', () {
    Future<void> dragHandleByOffset(
      WidgetTester tester,
      Finder handleFinder, {
      required Offset startOffsetFromCenter,
      required Offset dragDelta,
    }) async {
      final start = tester.getCenter(handleFinder) + startOffsetFromCenter;
      final gesture = await tester.startGesture(start);
      // Small steps so multi-drag & arena resolve realistically.
      const steps = 8;
      for (var i = 1; i <= steps; i++) {
        await gesture.moveBy(dragDelta / steps.toDouble());
        await tester.pump(const Duration(milliseconds: 24));
      }
      await gesture.up();
      await tester.pump();
    }

    testWidgets(
        'assignment pinned handles expose 44x48 opaque target, right-edge clearance, off-center & center drag, swipe/tooltip/tap isolation, and reload persistence',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final w1 = _work(
        'pin-a',
        title: '置顶甲作业',
        due: fixedMorning.add(const Duration(hours: 6)),
        submitUrl: 'https://mooc1.chaoxing.com/work/view?workid=a',
        syncedAt: fixedMorning,
      );
      final w2 = _work(
        'pin-b',
        title: '置顶乙作业',
        due: fixedMorning.add(const Duration(hours: 12)),
        submitUrl: 'https://mooc1.chaoxing.com/work/view?workid=b',
        syncedAt: fixedMorning,
      );
      final store = await _authenticatedStore([w1, w2]);
      addTearDown(store.dispose);
      await store.togglePin(w1);
      await store.togglePin(w2);
      final k1 = AssignmentStore.pinKeyOf(w1);
      final k2 = AssignmentStore.pinKeyOf(w2);

      var pushedDetails = false;
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => Scaffold(
              body:
                  AssignmentListScreen(store: store, clock: () => fixedMorning),
            ),
          ),
          GoRoute(
            path: '/assignments/:id',
            builder: (_, __) {
              pushedDetails = true;
              return const Scaffold(body: Text('detail'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: StudyAssistantTheme.light,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      final handle1 = find.byKey(ValueKey('pinned-drag-handle-$k1'));
      final handle2 = find.byKey(ValueKey('pinned-drag-handle-$k2'));
      expect(handle1, findsOneWidget);
      expect(handle2, findsOneWidget);

      final handleRect = tester.getRect(handle1);
      expect(handleRect.size, const Size(44, 48));
      expect(412.0 - handleRect.right, greaterThanOrEqualTo(24.0));

      final card1 = find.byKey(ValueKey('assignment-${w1.id}'));
      final card2 = find.byKey(ValueKey('assignment-${w2.id}'));
      final cardHeight = tester.getSize(card1).height;
      expect(
        tester.getTopLeft(card1).dy,
        lessThan(tester.getTopLeft(card2).dy),
      );

      // Off-center diagonal drag (-14, -14 from center) must still drag w1 below w2
      // without triggering card tap, horizontal swipe, or Tooltip.
      await dragHandleByOffset(
        tester,
        handle1,
        startOffsetFromCenter: const Offset(-14, -14),
        dragDelta: Offset(12, cardHeight + 28),
      );
      await tester.pumpAndSettle();

      expect(pushedDetails, isFalse);
      expect(find.text('拖动调整置顶顺序'), findsNothing);
      expect(find.text('已加入今日计划（30 分钟）'), findsNothing);
      expect(find.text('已取消置顶'), findsNothing);
      expect(
        tester.getTopLeft(card2).dy,
        lessThan(tester.getTopLeft(card1).dy),
      );
      expect(store.pinnedKeys.take(2).toList(), [k2, k1]);

      // Center drag on w2 brings w1 back to first, then verify cold-reload persistence.
      await dragHandleByOffset(
        tester,
        handle2,
        startOffsetFromCenter: Offset.zero,
        dragDelta: Offset(-8, cardHeight + 28),
      );
      await tester.pumpAndSettle();

      expect(store.pinnedKeys.take(2).toList(), [k1, k2]);
      final reloaded = AssignmentStore(
        sessionStore: _MemorySessionStore(),
        notificationService: _Notifications(),
        widgetSnapshotService: _Snapshot(),
      );
      addTearDown(reloaded.dispose);
      await reloaded.restoreSession();
      expect(reloaded.pinnedKeys.take(2).toList(), [k1, k2]);
    });

    testWidgets(
        'manual cards reorder in compact and largeText modes, context menu move works, and FB-005 overdue stays last',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final normalDue = _work(
        'reg-normal',
        title: '常规未来作业',
        due: fixedMorning.add(const Duration(days: 2)),
        syncedAt: fixedMorning,
      );
      final overdue = _work(
        'reg-overdue',
        title: '常规逾期作业',
        due: fixedMorning.subtract(const Duration(days: 1)),
        syncedAt: fixedMorning,
      );
      final m1 = ManualEntry(
        id: 'm1',
        title: '手动置顶一',
        kind: ManualEntry.kindTodo,
        course: '线性代数',
        at: fixedMorning.add(const Duration(hours: 3)),
      );
      final m2 = ManualEntry(
        id: 'm2',
        title: '手动置顶二',
        kind: ManualEntry.kindTodo,
        course: '概率论',
        at: fixedMorning.add(const Duration(hours: 5)),
      );

      final store = await _authenticatedStore([overdue, normalDue]);
      addTearDown(store.dispose);
      await store.saveDisplay(const DisplayPreferences(compact: true));
      await store.saveNotebook(
        (_) => StudyNotebook(entries: [m1, m2]),
        store.accountEpoch,
      );
      await store.toggleManualPin(m1);
      await store.toggleManualPin(m2);
      final mk1 = AssignmentStore.manualPinKeyOf(m1);
      final mk2 = AssignmentStore.manualPinKeyOf(m2);

      // Pump in compact + largeText mode (textScale 1.6 puts handle inside Wrap).
      await tester.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(412, 915),
              textScaler: TextScaler.linear(1.6),
            ),
            child: Scaffold(
              body:
                  AssignmentListScreen(store: store, clock: () => fixedMorning),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final mh1 = find.byKey(ValueKey('pinned-drag-handle-$mk1'));
      expect(mh1, findsOneWidget);
      expect(tester.getSize(mh1), const Size(44, 48));

      final mc1 = find.byKey(ValueKey('manual-${m1.id}'));
      final mc2 = find.byKey(ValueKey('manual-${m2.id}'));
      final cardHeight = tester.getSize(mc1).height;

      await dragHandleByOffset(
        tester,
        mh1,
        startOffsetFromCenter: const Offset(12, -14),
        dragDelta: Offset(0, cardHeight + 32),
      );
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(mc2).dy, lessThan(tester.getTopLeft(mc1).dy));
      expect(store.pinnedKeys.take(2).toList(), [mk2, mk1]);

      // Long-press context menu "置顶下移" moves m2 back below m1.
      await tester.longPress(find.text('手动置顶二'));
      await tester.pumpAndSettle();
      expect(find.text('置顶下移'), findsOneWidget);
      await tester.tap(find.text('置顶下移'));
      await tester.pumpAndSettle();
      expect(store.pinnedKeys.take(2).toList(), [mk1, mk2]);

      // FB-005 non-pinned invariant: normal future item stays above overdue item.
      final normalFinder = find.byKey(ValueKey('assignment-${normalDue.id}'));
      final overdueFinder = find.byKey(ValueKey('assignment-${overdue.id}'));
      expect(
        tester.getTopLeft(normalFinder).dy,
        lessThan(tester.getTopLeft(overdueFinder).dy),
      );
    });

    testWidgets(
        'optimistic reorder holds new visual order while disk save is pending and rolls back on failure or account switch',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
      FlutterSecureStorage.setMockInitialValues({});
      final repo = _ControllablePinRepo();
      final session = _MemorySessionStore();
      final w1 = _work(
        'opt-a',
        title: '乐观置顶一',
        due: fixedMorning.add(const Duration(hours: 4)),
        syncedAt: fixedMorning,
      );
      final w2 = _work(
        'opt-b',
        title: '乐观置顶二',
        due: fixedMorning.add(const Duration(hours: 8)),
        syncedAt: fixedMorning,
      );
      final store = AssignmentStore(
        repository: repo,
        sessionStore: session,
        notificationService: _Notifications(),
        widgetSnapshotService: _Snapshot(),
      );
      addTearDown(store.dispose);
      await store.restoreSession();
      await repo.mergeAndSave([w1, w2]);
      await store.restoreSession();
      await store.togglePin(w1);
      await store.togglePin(w2);
      final k1 = AssignmentStore.pinKeyOf(w1);
      final k2 = AssignmentStore.pinKeyOf(w2);

      await tester.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          home: Scaffold(
            body: AssignmentListScreen(store: store, clock: () => fixedMorning),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final handle1 = find.byKey(ValueKey('pinned-drag-handle-$k1'));
      final card1 = find.byKey(ValueKey('assignment-${w1.id}'));
      final card2 = find.byKey(ValueKey('assignment-${w2.id}'));
      final cardHeight = tester.getSize(card1).height;

      // 1. Hold save pending and fail it: immediate post-release frame must NOT snap back,
      //    then once save fails, UI rolls back to [w1, w2].
      final failStarted = Completer<void>();
      final failGate = Completer<void>();
      repo.saveStarted = failStarted;
      repo.saveGate = failGate;
      repo.gateError = StaleSessionWriteException('stale session');

      await dragHandleByOffset(
        tester,
        handle1,
        startOffsetFromCenter: Offset.zero,
        dragDelta: Offset(0, cardHeight + 28),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await failStarted.future;
      await tester.pump();

      // Store has not committed yet, but optimistic UI must hold [w2, w1].
      expect(store.pinnedKeys.take(2).toList(), [k1, k2]);
      expect(
        tester.getTopLeft(card2).dy,
        lessThan(tester.getTopLeft(card1).dy),
      );

      failGate.complete();
      await tester.pumpAndSettle();
      expect(store.pinnedKeys.take(2).toList(), [k1, k2]);
      expect(
        tester.getTopLeft(card1).dy,
        lessThan(tester.getTopLeft(card2).dy),
      );

      final firstSave = Completer<void>();
      final firstSaveStarted = Completer<void>();
      repo.saveStarted = firstSaveStarted;
      repo.saveGate = firstSave;
      await dragHandleByOffset(
        tester,
        handle1,
        startOffsetFromCenter: Offset.zero,
        dragDelta: Offset(0, cardHeight + 28),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await firstSaveStarted.future;
      expect(
          tester.getTopLeft(card2).dy, lessThan(tester.getTopLeft(card1).dy));

      final secondSave = Completer<void>();
      final secondSaveStarted = Completer<void>();
      repo.saveStarted = secondSaveStarted;
      repo.saveGate = secondSave;
      await dragHandleByOffset(
        tester,
        handle1,
        startOffsetFromCenter: Offset.zero,
        dragDelta: Offset(0, -cardHeight - 28),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(
          tester.getTopLeft(card1).dy, lessThan(tester.getTopLeft(card2).dy));
      firstSave.complete();
      await secondSaveStarted.future;
      await tester.pump();
      expect(store.pinnedKeys.take(2).toList(), [k2, k1]);
      expect(
          tester.getTopLeft(card1).dy, lessThan(tester.getTopLeft(card2).dy));
      secondSave.complete();
      await tester.pumpAndSettle();
      expect(store.pinnedKeys.take(2).toList(), [k1, k2]);

      // Hold save pending and switch/logout account.
      final switchStarted = Completer<void>();
      final switchGate = Completer<void>();
      repo.saveStarted = switchStarted;
      repo.saveGate = switchGate;

      await dragHandleByOffset(
        tester,
        handle1,
        startOffsetFromCenter: Offset.zero,
        dragDelta: Offset(0, cardHeight + 28),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await switchStarted.future;
      await tester.pump();
      expect(
        tester.getTopLeft(card2).dy,
        lessThan(tester.getTopLeft(card1).dy),
      );

      final logoutFuture = store.logout();
      switchGate.complete();
      await logoutFuture;
      await tester.pumpAndSettle();
      expect(store.isAuthenticated, isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}

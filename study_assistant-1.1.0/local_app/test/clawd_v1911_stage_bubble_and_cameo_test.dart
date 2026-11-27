import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/calendar_screen.dart';
import 'package:study_assistant_mobile/src/features/manual_agenda_screen.dart';
import 'package:study_assistant_mobile/src/features/profile_screen.dart';
import 'package:study_assistant_mobile/src/features/stats_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/clawd_speech_bubble.dart';
import 'package:study_assistant_mobile/src/features/widgets/clawd_title_stage.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_pixel_buddy.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/display_preferences.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/clawd_companion_controller.dart';
import 'package:study_assistant_mobile/src/services/interaction_feedback_service.dart';
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

  @override
  Future<void> saveAssignmentsForContext(
    List<Assignment> assignments, {
    bool authenticated = true,
    dynamic range,
  }) async {}
}

class _Session extends SecureSessionStore {
  String? account = 'student-clawd-v1911';

  @override
  Future<String?> readChaoxingAccount() async => account;

  @override
  Future<String?> readChaoxingPassword() async =>
      account == null ? null : 'secret';

  @override
  Future<String?> readChaoxingDisplayName() async => '手记同学';

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;

  @override
  Future<void> clear() async {
    account = null;
  }
}

Assignment _work(
  String id, {
  String course = '软件工程',
  required String title,
  DateTime? due,
  String status = 'pending',
  required DateTime syncedAt,
}) =>
    Assignment(
      id: 'cx:work:1:2:$id',
      courseName: course,
      title: title,
      deadlineAt: due,
      deadlineTrusted: due != null,
      requirementsText: '',
      status: status,
      lastSyncedAt: syncedAt,
    );

Future<AssignmentStore> _createSeededStore({
  required DateTime now,
  List<Assignment> assignments = const [],
  List<ManualEntry> entries = const [],
  _Session? session,
}) async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  FlutterSecureStorage.setMockInitialValues({});
  final store = AssignmentStore(
    sessionStore: session ?? _Session(),
    notificationService: _Notifications(),
    widgetSnapshotService: _Snapshot(),
    clock: () => now,
  );
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
  store.syncReport =
      SyncReport(phase: SyncPhase.success, lastDataSuccessAt: now);
  store.notifyListeners();
  return store;
}

GoRouter _buildShellRouter(
  AssignmentStore store, {
  required DateTime Function() clock,
  ValueChanged<ClawdPageContextSnapshot>? onClawdBubbleTap,
  bool noTransitionPages = false,
}) {
  Page<void> tabPage(GoRouterState state, Widget child) {
    if (!noTransitionPages) {
      return MaterialPage<void>(key: state.pageKey, child: child);
    }
    return NoTransitionPage<void>(key: state.pageKey, child: child);
  }

  return GoRouter(
    initialLocation: '/assignments',
    routes: [
      ShellRoute(
        builder: (_, __, child) => AppShell(
          assignmentStore: store,
          clock: clock,
          onClawdBubbleTap: onClawdBubbleTap,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/assignments',
            pageBuilder: (_, state) => tabPage(
              state,
              AssignmentListScreen(
                store: store,
                clock: clock,
              ),
            ),
          ),
          GoRoute(
            path: '/calendar',
            pageBuilder: (_, state) => tabPage(
              state,
              CalendarScreen(store: store, clock: clock),
            ),
          ),
          GoRoute(
            path: '/stats',
            pageBuilder: (_, state) => tabPage(
              state,
              StatsScreen(store: store, clock: clock),
            ),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (_, state) => tabPage(
              state,
              ProfileScreen(store: store),
            ),
          ),
          GoRoute(
            path: '/agenda',
            builder: (_, __) => ManualAgendaScreen(store: store),
          ),
        ],
      ),
    ],
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));

  group('M1 · controller lifecycle, account reset, and bubble extension hook',
      () {
    test('proactive cooldown (>=15 min), silent guards, and account reset', () {
      var current = DateTime(2026, 11, 26, 8, 15); // local morning window
      final controller = ClawdCompanionController(clock: () => current);
      addTearDown(controller.dispose);

      const snapshot = ClawdPageContextSnapshot(
        tab: ClawdPrimaryTab.home,
        dueToday: 2,
        dueIn3Days: 3,
      );
      controller.updateEnvironment(
        displayPrefs: const DisplayPreferences(),
        appResumed: true,
        tickerEnabled: true,
        reducedMotion: false,
        isSyncing: false,
        hasSyncErrorOrPending: false,
        snapshot: snapshot,
      );

      expect(controller.maybeEmitProactiveBubble(), isTrue);
      expect(controller.activeBubble?.text, '早安，今日有2项待办哦');

      // Dismiss and retry immediately -> greeting bucket cooled down, falls through to dueToday bucket.
      controller.dismissBubble();
      expect(controller.maybeEmitProactiveBubble(), isTrue);
      expect(controller.activeBubble?.text, '今日还剩2项临期课业');

      // Both morning greeting & dueToday buckets are cooled down inside 15m.
      controller.dismissBubble();
      current = current.add(const Duration(minutes: 10));
      expect(controller.maybeEmitProactiveBubble(), isFalse);

      // Advance past 15m -> greeting bucket fires again.
      current = current.add(const Duration(minutes: 6));
      expect(controller.maybeEmitProactiveBubble(), isTrue);

      // Late-night window (23:10) after clearing previous bucket.
      controller.resetForAccountChange();
      current = DateTime(2026, 11, 26, 23, 10);
      controller.updateEnvironment(
        snapshot: const ClawdPageContextSnapshot(
          tab: ClawdPrimaryTab.home,
          dueToday: 0,
          completedToday: 0,
        ),
      );
      expect(controller.maybeEmitProactiveBubble(), isTrue);
      expect(controller.activeBubble?.text, '夜深啦，忙完这一笔早点休息');

      // Silent when syncing, error, reducedMotion, or paused.
      controller.dismissBubble();
      controller.updateEnvironment(isSyncing: true);
      expect(controller.maybeEmitProactiveBubble(), isFalse);
      controller.updateEnvironment(
          isSyncing: false, hasSyncErrorOrPending: true);
      expect(controller.maybeEmitProactiveBubble(), isFalse);
      controller.updateEnvironment(
          hasSyncErrorOrPending: false, reducedMotion: true);
      expect(controller.maybeEmitProactiveBubble(), isFalse);
      controller.updateEnvironment(reducedMotion: false, appResumed: false);
      expect(controller.maybeEmitProactiveBubble(), isFalse);
    });

    testWidgets(
        'AppShell shares controller across tabs, resets on account change, and forwards sanitized snapshot on bubble hook',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0);
      final session = _Session();
      final store = await _createSeededStore(
        now: now,
        session: session,
        assignments: [
          _work(
            'today-1',
            course: '机密课程名称ABC',
            title: '实验报告',
            due: now.add(const Duration(hours: 4)),
            syncedAt: now,
          ),
        ],
      );
      addTearDown(store.dispose);

      ClawdPageContextSnapshot? hookedSnapshot;
      final router = _buildShellRouter(
        store,
        clock: () => now,
        onClawdBubbleTap: (snap) => hookedSnapshot = snap,
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: StudyAssistantTheme.light,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      // Tap home buddy -> bubble appears; tap bubble -> extension hook receives sanitized snapshot.
      await tester.tap(find.byKey(const ValueKey('home-pixel-buddy')));
      await tester.pump();
      expect(find.byKey(const ValueKey('clawd-speech-bubble')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('clawd-speech-bubble')));
      await tester.pump();
      expect(hookedSnapshot, isNotNull);
      expect(hookedSnapshot!.routePath, '/assignments');
      expect(hookedSnapshot!.dueToday, 1);

      // Switch to Calendar tab -> shared controller retains tapCount/comboCount.
      await tester.tap(find.text('日历'));
      await tester.pumpAndSettle();
      final calendarCameo = find.byKey(const ValueKey('calendar-pixel-buddy'));
      expect(calendarCameo, findsOneWidget);
      final controller = ClawdCompanionScope.of(
        tester.element(calendarCameo),
      );
      expect(controller.tapCount, 1);

      // Second quick tap on Calendar continues combo to 2.
      await tester.tap(calendarCameo);
      await tester.pump();
      expect(controller.tapCount, 2);
      expect(controller.comboCount, 2);
      expect(find.byKey(const ValueKey('clawd-speech-bubble')), findsOneWidget);

      // Switch to Stats & Profile -> cameos present; secondary route '/agenda' hides Clawd.
      await tester.tap(find.text('统计'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('stats-pixel-buddy')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('stats-pixel-buddy')));
      await tester.pump();
      expect(find.byKey(const ValueKey('clawd-speech-bubble')), findsOneWidget);

      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile-pixel-buddy')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-pixel-buddy')));
      await tester.pump();
      expect(find.byKey(const ValueKey('clawd-speech-bubble')), findsOneWidget);

      router.push('/agenda');
      await tester.pumpAndSettle();
      expect(find.byType(JournalPixelBuddy), findsNothing);
      expect(find.byKey(const ValueKey('clawd-speech-bubble')), findsNothing);
      router.pop();
      await tester.pumpAndSettle();

      // Switch to homeOnly -> secondary tab cameos hide, home keeps Clawd.
      await store.saveDisplay(
        store.display.copyWith(clawdVisibility: ClawdVisibilityMode.homeOnly),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile-pixel-buddy')), findsNothing);
      await tester.tap(find.text('首页'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-pixel-buddy')), findsOneWidget);

      // Switch to off -> home Clawd also hides.
      await store.saveDisplay(
        store.display.copyWith(clawdVisibility: ClawdVisibilityMode.off),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-pixel-buddy')), findsNothing);

      // Account change resets interaction memory & combo.
      session.account = 'student-another';
      await store.restoreSession();
      await tester.pumpAndSettle();
      expect(controller.tapCount, 0);
      expect(controller.comboCount, 0);
      expect(controller.activeBubble, isNull);
    });
  });

  group(
      'M1 regression · NoTransitionPage tab switches keep shared Clawd interactive',
      () {
    testWidgets(
        'departing primary tabs do not poison shared tickerEnabled or snapshots',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0);
      final store = await _createSeededStore(
        now: now,
        assignments: [
          _work(
            'today-1',
            title: '路由切换回归作业',
            due: now.add(const Duration(hours: 4)),
            syncedAt: now,
          ),
        ],
      );
      addTearDown(store.dispose);

      final router = _buildShellRouter(
        store,
        clock: () => now,
        noTransitionPages: true,
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: StudyAssistantTheme.light,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      const bubbleFinder = ValueKey('clawd-speech-bubble');
      await tester.tap(find.byKey(const ValueKey('home-pixel-buddy')));
      await tester.pump();
      expect(find.byKey(bubbleFinder), findsOneWidget);

      await tester.tap(find.text('日历'));
      await tester.pump();
      final calendarBuddy = find.byKey(const ValueKey('calendar-pixel-buddy'));
      expect(calendarBuddy, findsOneWidget);
      final calendarController =
          ClawdCompanionScope.of(tester.element(calendarBuddy));
      expect(calendarController.tickerEnabled, isTrue);
      expect(calendarController.latestSnapshot?.tab, ClawdPrimaryTab.calendar);

      await tester.tap(calendarBuddy);
      await tester.pump();
      expect(find.byKey(bubbleFinder), findsOneWidget);
      expect(calendarController.activeBubble?.tab, ClawdPrimaryTab.calendar);
      final calendarTitleRect = tester.getRect(find.text('课业日历'));
      final calendarBuddyRect = tester.getRect(calendarBuddy);
      final calendarBubbleRect = tester.getRect(find.byKey(bubbleFinder));
      // The keyed rect includes the 6dp upward pointer, so compare the pill
      // body top against the title to prove the text itself is not covered.
      final calendarPillTop = calendarBubbleRect.top + 6.0;
      expect(
        calendarPillTop,
        greaterThanOrEqualTo(calendarTitleRect.bottom + 2.0 - 0.1),
      );
      expect(
        calendarPillTop,
        lessThanOrEqualTo(calendarTitleRect.bottom + 12.0),
      );
      expect(
        calendarPillTop,
        greaterThanOrEqualTo(calendarBuddyRect.bottom - 0.1),
      );
      expect(
        calendarBubbleRect.top,
        lessThanOrEqualTo(calendarBuddyRect.bottom + 8.0),
      );
      expect(
        (calendarBubbleRect.center.dx - calendarBuddyRect.center.dx).abs(),
        lessThanOrEqualTo(4.0),
      );
      expect(
        find.descendant(
          of: find.byKey(bubbleFinder),
          matching: find.textContaining('今天'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('统计'));
      await tester.pump();
      final statsBuddy = find.byKey(const ValueKey('stats-pixel-buddy'));
      expect(statsBuddy, findsOneWidget);
      final statsController =
          ClawdCompanionScope.of(tester.element(statsBuddy));
      expect(statsController.tickerEnabled, isTrue);
      expect(statsController.latestSnapshot?.tab, ClawdPrimaryTab.stats);

      await tester.tap(statsBuddy);
      await tester.pump();
      expect(find.byKey(bubbleFinder), findsOneWidget);
      expect(statsController.activeBubble?.tab, ClawdPrimaryTab.stats);
      final statsTitleBottom = tester.getRect(find.text('课业统计')).bottom;
      final statsBuddyBottom = tester.getRect(statsBuddy).bottom;
      final statsBubbleRect = tester.getRect(find.byKey(bubbleFinder));
      expect(
        statsBubbleRect.top,
        greaterThanOrEqualTo(statsTitleBottom + 2.0 - 0.1),
      );
      expect(
        statsBubbleRect.top,
        lessThanOrEqualTo(statsBuddyBottom + 8.0),
      );

      await tester.tap(find.text('我的'));
      await tester.pump();
      final profileBuddy = find.byKey(const ValueKey('profile-pixel-buddy'));
      expect(profileBuddy, findsOneWidget);
      final profileController =
          ClawdCompanionScope.of(tester.element(profileBuddy));
      expect(profileController.tickerEnabled, isTrue);
      expect(profileController.latestSnapshot?.tab, ClawdPrimaryTab.profile);

      await tester.tap(profileBuddy);
      await tester.pump();
      expect(find.byKey(bubbleFinder), findsOneWidget);
      expect(profileController.activeBubble?.tab, ClawdPrimaryTab.profile);
      final profileTitleBottom = tester.getRect(find.text('我的手帐')).bottom;
      final profileBuddyBottom = tester.getRect(profileBuddy).bottom;
      final profileBubbleRect = tester.getRect(find.byKey(bubbleFinder));
      expect(
        profileBubbleRect.top,
        greaterThanOrEqualTo(profileTitleBottom + 2.0 - 0.1),
      );
      expect(
        profileBubbleRect.top,
        lessThanOrEqualTo(profileBuddyBottom + 8.0),
      );

      await tester.tap(find.text('首页'));
      await tester.pump();
      final homeBuddy = find.byKey(const ValueKey('home-pixel-buddy'));
      expect(homeBuddy, findsOneWidget);
      final homeController = ClawdCompanionScope.of(tester.element(homeBuddy));
      expect(homeController.tickerEnabled, isTrue);
      expect(homeController.latestSnapshot?.tab, ClawdPrimaryTab.home);

      await tester.tap(homeBuddy);
      await tester.pump();
      expect(find.byKey(bubbleFinder), findsOneWidget);
      expect(homeController.activeBubble?.tab, ClawdPrimaryTab.home);
      final homeBubbleRect = tester.getRect(find.byKey(bubbleFinder));
      final syncStatusRect =
          tester.getRect(find.byKey(const ValueKey('home-sync-status')));
      expect(
        homeBubbleRect.top,
        greaterThanOrEqualTo(syncStatusRect.bottom + 2.0 - 0.1),
      );
    });

    testWidgets(
        'secondary routes pause proactive bubbles and resume scheduling on pop',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0);
      final store = await _createSeededStore(
        now: now,
        assignments: [
          _work(
            'today-1',
            title: '主动冒泡暂停回归作业',
            due: now.add(const Duration(hours: 4)),
            syncedAt: now,
          ),
        ],
      );
      addTearDown(store.dispose);

      final router = _buildShellRouter(store, clock: () => now);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: StudyAssistantTheme.light,
          routerConfig: router,
        ),
      );
      await tester.pump();

      final homeBuddy = find.byKey(const ValueKey('home-pixel-buddy'));
      expect(homeBuddy, findsOneWidget);
      final controller = ClawdCompanionScope.of(tester.element(homeBuddy));
      final bubbleIds = <int>{};
      ClawdSpeechMessage? lastBubble;
      void recordBubble() {
        final bubble = controller.activeBubble;
        if (bubble != null && bubble.id != lastBubble?.id) {
          lastBubble = bubble;
          bubbleIds.add(bubble.id);
        }
      }

      controller.addListener(recordBubble);
      addTearDown(() => controller.removeListener(recordBubble));

      // Push a secondary route inside the initial 3.2s proactive window.
      router.push('/agenda');
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(controller.activeBubble, isNull);
      expect(find.byKey(const ValueKey('clawd-speech-bubble')), findsNothing);
      expect(bubbleIds, isEmpty);

      // Popping back to home resumes the schedule without a consumed cooldown.
      router.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 3300));
      expect(bubbleIds.length, 1);
      expect(controller.activeBubble, isNotNull);
      expect(controller.activeBubble?.tab, ClawdPrimaryTab.home);
      expect(find.byKey(const ValueKey('clawd-speech-bubble')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(milliseconds: 2600));
    });
  });

  group(
      'M2 & M3 · equal-height stage, Shimeji gestures, bubble & zero blue stars',
      () {
    testWidgets(
        'equal-height 38dp at >=350dp, zero blue stars, pure status row, tap-to-dismiss & scroll isolation',
        (tester) async {
      tester.view.physicalSize = const Size(824, 1830);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0);
      final store = await _createSeededStore(
        now: now,
        assignments: [
          _work(
            'today-1',
            title: '高数习题',
            due: now.add(const Duration(hours: 3)),
            syncedAt: now,
          ),
          for (var i = 0; i < 14; i++)
            _work(
              'future-$i',
              title: '长列表课业 $i',
              due: now.add(Duration(days: 2 + i)),
              syncedAt: now,
            ),
        ],
      );
      addTearDown(store.dispose);

      final router = _buildShellRouter(store, clock: () => now);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: StudyAssistantTheme.light,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      // 1. Equal-height 38dp buddy and zero Icons.auto_awesome_rounded anywhere on home.
      final buddyFinder = find.byKey(const ValueKey('home-pixel-buddy'));
      expect(tester.widget<JournalPixelBuddy>(buddyFinder).size, 38.0);
      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.auto_awesome_rounded,
        ),
        findsNothing,
      );

      // 2. Pure status row stays '刚刚更新' while ClawdSpeechBubble displays text and tap dismisses it.
      expect(find.text('刚刚更新'), findsOneWidget);
      await tester.tap(buddyFinder);
      await tester.pump();
      expect(find.text('刚刚更新'), findsOneWidget);
      final bubbleFinder = find.byKey(const ValueKey('clawd-speech-bubble'));
      expect(bubbleFinder, findsOneWidget);
      expect(
        tester.getRect(bubbleFinder).right,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const ValueKey('home-agenda-entry'))).left -
              7.5,
        ),
      );
      await tester.tap(bubbleFinder);
      await tester.pumpAndSettle();
      expect(bubbleFinder, findsNothing);

      // 3. 3+ combo triggers tsundere bubble & long-press triggers pet bubble.
      await tester.tap(buddyFinder);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(buddyFinder);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(buddyFinder);
      await tester.pump();
      expect(bubbleFinder, findsOneWidget);
      final tsundereWidget = tester.widget<ClawdSpeechBubble>(bubbleFinder);
      expect(tsundereWidget.message.isTsundere, isTrue);

      await tester.longPress(buddyFinder);
      await tester.pump();
      expect(
        find.descendant(
          of: bubbleFinder,
          matching: find.textContaining('呼噜'),
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 2600));
      await tester.pumpAndSettle();

      // 4. Dragging Clawd grabs & springs back cleanly within safe boundary left of action buttons.
      final startCenter = tester.getCenter(buddyFinder);
      final drag = await tester.startGesture(startCenter);
      await drag.moveBy(const Offset(180, -8));
      await tester.pump();
      expect(
        tester.getRect(buddyFinder).right,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const ValueKey('home-agenda-entry'))).left,
        ),
      );
      expect(find.text('呜哇！快放我下来，够不着字啦！'), findsOneWidget);
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.text('噗咚，安全着陆！'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 5. Scroll isolation: dragging vertically from '课业手记' text scrolls ListView cleanly.
      final titleTextCenter = tester.getCenter(find.text('课业手记'));
      await tester.dragFrom(titleTextCenter, const Offset(0, -240));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('home-sliver-pixel-buddy')),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.auto_awesome_rounded,
        ),
        findsNothing,
      );
    });

    testWidgets(
        'autonomous Shimeji choreography settles cleanly and degrades under disableAnimations / recoveryScope / 320dp@2x',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0);
      final store = await _createSeededStore(
        now: now,
        assignments: [
          _work(
            'today-1',
            title: '舞台巡逻测试',
            due: now.add(const Duration(hours: 4)),
            syncedAt: now,
          ),
        ],
      );
      addTearDown(store.dispose);

      final router = _buildShellRouter(store, clock: () => now);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: StudyAssistantTheme.dark,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      // Advance past autonomous Shimeji choreography timer (2600-4500ms) -> settles with zero timeout.
      await tester.pump(const Duration(milliseconds: 3000));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Recovery scope degrades ClawdTitleStage to stationary mode.
      router.go('/assignments?scope=noDeadline');
      await tester.pumpAndSettle();
      final recoveryStage =
          tester.widget<ClawdTitleStage>(find.byType(ClawdTitleStage));
      expect(recoveryStage.allowStageMotion, isFalse);

      // 320dp @ 2x textScale degrades cleanly with zero overflow.
      tester.view.physicalSize = const Size(320, 720);
      router.go('/assignments');
      await tester.pumpWidget(
        MaterialApp.router(
          theme: StudyAssistantTheme.dark,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2.0),
              disableAnimations: true,
            ),
            child: child!,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final degradedStage =
          tester.widget<ClawdTitleStage>(find.byType(ClawdTitleStage));
      expect(degradedStage.allowStageMotion, isFalse);
      expect(degradedStage.buddySize, 24.0);
    });
  });

  group('M4 · InteractionFeedback 8-bit Clawd channel & syncTick throttle', () {
    testWidgets(
        'clawdJump/clawdCombo2/clawdCombo3 are never swallowed by tap throttle and clawdSyncTick enforces >=320ms without haptics',
        (tester) async {
      InteractionFeedback.debugReset();
      addTearDown(InteractionFeedback.debugReset);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      try {
        var current = DateTime(2026, 11, 26, 10, 0, 0);
        InteractionFeedback.now = () => current;

        final calls = <Map<String, dynamic>>[];
        const channel = MethodChannel('study_assistant/interaction_sound');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
            (call) async {
          calls.add(Map<String, dynamic>.from(call.arguments as Map));
          return null;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null));

        const prefs =
            DisplayPreferences(soundEnabled: true, hapticsEnabled: true);

        // Rapid combo taps within 30ms (< 90ms tap throttle) must all fire.
        InteractionFeedback.trigger(prefs,
            kind: InteractionSoundKind.clawdJump);
        current = current.add(const Duration(milliseconds: 30));
        InteractionFeedback.trigger(prefs,
            kind: InteractionSoundKind.clawdCombo2);
        current = current.add(const Duration(milliseconds: 30));
        InteractionFeedback.trigger(prefs,
            kind: InteractionSoundKind.clawdCombo3);
        await tester.pump();

        expect(
          calls.map((c) => c['kind']).toList(),
          ['clawdJump', 'clawdCombo2', 'clawdCombo3'],
        );
        expect(calls.every((c) => c['sound'] == true && c['haptics'] == true),
            isTrue);

        // clawdSyncTick enforces >= 320ms throttle and ALWAYS passes haptics: false.
        calls.clear();
        InteractionFeedback.trigger(prefs,
            kind: InteractionSoundKind.clawdSyncTick);
        current = current.add(const Duration(milliseconds: 180));
        InteractionFeedback.trigger(prefs,
            kind: InteractionSoundKind.clawdSyncTick);
        current = current.add(const Duration(milliseconds: 150)); // 330ms total
        InteractionFeedback.trigger(prefs,
            kind: InteractionSoundKind.clawdSyncTick);
        await tester.pump();

        expect(calls.length, 2);
        expect(
          calls.every(
            (c) =>
                c['kind'] == 'clawdSyncTick' &&
                c['sound'] == true &&
                c['haptics'] == false,
          ),
          isTrue,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group(
      'Gate 1 regressions · bubble bounds, shared pulse, standalone calendar, reduced motion, unified warning',
      () {
    testWidgets(
        'ClawdSpeechBubble pointer stays inside actual pill width on Stats, Profile, short home landing bubble, and 330dp sliver',
        (tester) async {
      // 1) Unit geometry check on short text with right-anchored & oversized left offsets.
      final now = DateTime.utc(2026, 11, 26, 2, 0);
      await tester.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          home: Scaffold(
            body: Center(
              child: ClawdSpeechBubble(
                key: const ValueKey('short-right-bubble'),
                message: ClawdSpeechMessage(
                  id: 1,
                  text: '嗨！',
                  tab: ClawdPrimaryTab.stats,
                  createdAt: now,
                ),
                maxWidth: 220.0,
                pointerOffsetFromRight: 20.0,
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final shortRect =
          tester.getRect(find.byKey(const ValueKey('short-right-bubble')));
      expect(shortRect.width, lessThan(100.0));
      final shortPainter = tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byKey(const ValueKey('short-right-bubble')),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter!;
      final clampedRightCenter = ClawdSpeechBubble.clampPointerCenterX(
        actualWidth: shortRect.width,
        pointerOffsetFromRight: 20.0,
      );
      expect(clampedRightCenter, greaterThanOrEqualTo(14.0));
      expect(clampedRightCenter, lessThanOrEqualTo(shortRect.width - 14.0));
      expect(shortPainter.shouldRepaint(shortPainter), isFalse);

      // 2) Stats & Profile pages keep short bubble + pointer strictly inside screen and bubble outline.
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final store = await _createSeededStore(now: now);
      addTearDown(store.dispose);
      final router = _buildShellRouter(store, clock: () => now);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: StudyAssistantTheme.light,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('统计'));
      await tester.pumpAndSettle();
      final statsTitleRect = tester.getRect(find.text('课业统计'));
      final statsBuddyFinder = find.byKey(const ValueKey('stats-pixel-buddy'));
      final statsBuddyRect = tester.getRect(statsBuddyFinder);
      expect(statsBuddyRect.left, greaterThanOrEqualTo(statsTitleRect.right));
      expect(
          statsBuddyRect.left - statsTitleRect.right, lessThanOrEqualTo(16.0));
      await tester.tap(statsBuddyFinder);
      await tester.pumpAndSettle();
      final statsBubbleFinder =
          find.byKey(const ValueKey('clawd-speech-bubble'));
      final statsBubbleRect = tester.getRect(statsBubbleFinder);
      expect(statsBubbleRect.left, greaterThanOrEqualTo(0.0));
      expect(statsBubbleRect.right, lessThanOrEqualTo(360.0));
      expect(statsBubbleRect.top,
          greaterThanOrEqualTo(statsBuddyRect.bottom + 2.0));
      final statsBubbleWidget =
          tester.widget<ClawdSpeechBubble>(statsBubbleFinder);
      final statsPtrOffset = statsBubbleWidget.pointerAnchor?.offset;
      expect(statsPtrOffset, isNotNull);
      expect(
        statsBubbleRect.left + statsPtrOffset!,
        closeTo(statsBuddyRect.center.dx, 1.5),
      );
      final statsPtrX = statsBubbleRect.left +
          ClawdSpeechBubble.clampPointerCenterX(
            actualWidth: statsBubbleRect.width,
            dynamicOffset: statsPtrOffset,
          );
      expect(statsPtrX, greaterThanOrEqualTo(statsBubbleRect.left + 14.0));
      expect(statsPtrX, lessThanOrEqualTo(statsBubbleRect.right - 14.0));

      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      final profileTitleRect = tester.getRect(find.text('我的手帐'));
      final profileBuddyFinder =
          find.byKey(const ValueKey('profile-pixel-buddy'));
      final profileBuddyRect = tester.getRect(profileBuddyFinder);
      expect(
          profileBuddyRect.left, greaterThanOrEqualTo(profileTitleRect.right));
      expect(
        profileBuddyRect.left - profileTitleRect.right,
        lessThanOrEqualTo(16.0),
      );
      await tester.tap(profileBuddyFinder);
      await tester.pumpAndSettle();
      final profileBubbleFinder =
          find.byKey(const ValueKey('clawd-speech-bubble'));
      final profileBubbleRect = tester.getRect(profileBubbleFinder);
      expect(profileBubbleRect.left, greaterThanOrEqualTo(0.0));
      expect(profileBubbleRect.right, lessThanOrEqualTo(360.0));
      expect(profileBubbleRect.top,
          greaterThanOrEqualTo(profileBuddyRect.bottom + 2.0));
      final profileBubbleWidget =
          tester.widget<ClawdSpeechBubble>(profileBubbleFinder);
      final profilePtrOffset = profileBubbleWidget.pointerAnchor?.offset;
      expect(profilePtrOffset, isNotNull);
      expect(
        profileBubbleRect.left + profilePtrOffset!,
        closeTo(profileBuddyRect.center.dx, 1.5),
      );
      final profilePtrX = profileBubbleRect.left +
          ClawdSpeechBubble.clampPointerCenterX(
            actualWidth: profileBubbleRect.width,
            dynamicOffset: profilePtrOffset,
          );
      expect(profilePtrX, greaterThanOrEqualTo(profileBubbleRect.left + 14.0));
      expect(profilePtrX, lessThanOrEqualTo(profileBubbleRect.right - 14.0));

      // 3) Home right-side landing short bubble ('噗咚，安全着陆！') stays inside stage & avoids 4 action buttons.
      final seededListStore = await _createSeededStore(
        now: now,
        assignments: [
          for (var i = 0; i < 14; i++)
            _work(
              'narrow-$i',
              title: '窄屏列表作业 $i',
              due: now.add(Duration(days: 1 + i)),
              syncedAt: now,
            ),
        ],
      );
      addTearDown(seededListStore.dispose);
      final narrowRouter = _buildShellRouter(seededListStore, clock: () => now);
      addTearDown(narrowRouter.dispose);

      tester.view.physicalSize = const Size(412, 915);
      await tester.pumpWidget(
        MaterialApp.router(
          theme: StudyAssistantTheme.light,
          routerConfig: narrowRouter,
        ),
      );
      await tester.pumpAndSettle();

      final homeBuddyFinder = find.byKey(const ValueKey('home-pixel-buddy'));
      final drag = await tester.startGesture(tester.getCenter(homeBuddyFinder));
      await drag.moveBy(const Offset(180, -4));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.text('噗咚，安全着陆！'), findsOneWidget);
      final landingBubble =
          tester.getRect(find.byKey(const ValueKey('clawd-speech-bubble')));
      final agendaRect =
          tester.getRect(find.byKey(const ValueKey('home-agenda-entry')));
      expect(landingBubble.left, greaterThanOrEqualTo(16.0 - 0.1));
      expect(landingBubble.right, lessThanOrEqualTo(agendaRect.left - 7.5));
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pumpAndSettle();

      // 4) 330dp narrow screen sliver bubble stays strictly <= safeRight (330 - 18 - 4*48 - 8 = 112.0).
      tester.view.physicalSize = const Size(330, 720);
      await tester.pumpWidget(
        MaterialApp.router(
          theme: StudyAssistantTheme.light,
          routerConfig: narrowRouter,
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -320));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-sliver-pixel-buddy')));
      await tester.pump();
      final sliverBubbleRect =
          tester.getRect(find.byKey(const ValueKey('clawd-speech-bubble')));
      expect(sliverBubbleRect.left, greaterThanOrEqualTo(18.0 - 0.1));
      expect(sliverBubbleRect.right, lessThanOrEqualTo(112.0 + 0.1));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 2600));
      await tester.pumpAndSettle();
    });

    testWidgets(
        'cross-tab taps share single 1200ms combo and 4th rapid tap increments transientPulse to replay tsunderePuff',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0);
      final store = await _createSeededStore(now: now);
      addTearDown(store.dispose);
      final router = _buildShellRouter(store, clock: () => now);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: StudyAssistantTheme.light,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('home-pixel-buddy')));
      await tester.pump();
      await tester.tap(find.text('日历'));
      await tester.pumpAndSettle();

      final calendarBuddy = find.byKey(const ValueKey('calendar-pixel-buddy'));
      final controller = ClawdCompanionScope.of(tester.element(calendarBuddy));
      expect(controller.comboCount, 1);

      await tester.tap(calendarBuddy);
      await tester.pump(const Duration(milliseconds: 80));
      expect(controller.comboCount, 2);

      await tester.tap(calendarBuddy);
      await tester.pump(const Duration(milliseconds: 80));
      expect(controller.comboCount, 3);
      expect(controller.transientPose, ClawdTransientPose.tsundere);
      final pulseAt3 = controller.transientPulse;

      await tester.tap(calendarBuddy);
      await tester.pump();
      expect(controller.comboCount, 4);
      expect(controller.transientPose, ClawdTransientPose.tsundere);
      expect(controller.transientPulse, pulseAt3 + 1);
      final buddyWidget = tester.widget<JournalPixelBuddy>(
        find.descendant(
          of: calendarBuddy,
          matching: find.byType(JournalPixelBuddy),
        ),
      );
      expect(buddyWidget.poseOverride, JournalPixelBuddyPose.tsunderePuff);
      expect(buddyWidget.posePulse, controller.transientPulse);

      await tester.pump(const Duration(milliseconds: 2600));
      await tester.pumpAndSettle();
    });

    testWidgets(
        'standalone CalendarScreen resets local controller on account switch and logout',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0);
      final session = _Session();
      final store = await _createSeededStore(now: now, session: session);
      addTearDown(store.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          home: Scaffold(body: CalendarScreen(store: store, clock: () => now)),
        ),
      );
      await tester.pumpAndSettle();

      final cameo = find.byKey(const ValueKey('calendar-pixel-buddy'));
      await tester.tap(cameo);
      await tester.pump();
      expect(find.byKey(const ValueKey('clawd-speech-bubble')), findsOneWidget);

      session.account = 'student-calendar-switched';
      await store.restoreSession();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('clawd-speech-bubble')), findsNothing);

      // Re-tap then logout -> clears local bubble & state.
      await tester.tap(cameo);
      await tester.pump();
      expect(find.byKey(const ValueKey('clawd-speech-bubble')), findsOneWidget);
      await store.logout();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('clawd-speech-bubble')), findsNothing);
    });

    testWidgets(
        'disableAnimations skips long-press petting transient pose on stage and controller',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0);
      final store = await _createSeededStore(now: now);
      addTearDown(store.dispose);
      final router = _buildShellRouter(store, clock: () => now);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: StudyAssistantTheme.light,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final homeBuddy = find.byKey(const ValueKey('home-pixel-buddy'));
      final controller = ClawdCompanionScope.of(tester.element(homeBuddy));
      await tester.longPress(homeBuddy);
      await tester.pumpAndSettle();
      expect(controller.transientPose, ClawdTransientPose.none);
      expect(controller.petCount, 0);

      controller.startPet(
        snapshot: const ClawdPageContextSnapshot(tab: ClawdPrimaryTab.home),
      );
      expect(controller.transientPose, ClawdTransientPose.none);
      expect(controller.petCount, 0);
    });

    testWidgets(
        'AppShell and all 4 primary tabs agree on hasSyncErrorOrPending under non-quiet warning without overwriting',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0);
      SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
      FlutterSecureStorage.setMockInitialValues({});
      final store = _WarningStore(clock: () => now);
      await store.restoreSession();
      store.syncReport =
          SyncReport(phase: SyncPhase.success, lastDataSuccessAt: now);
      addTearDown(store.dispose);

      final router = _buildShellRouter(store, clock: () => now);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: StudyAssistantTheme.light,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      final controller = ClawdCompanionScope.of(
        tester.element(find.byKey(const ValueKey('home-pixel-buddy'))),
      );
      expect(controller.hasSyncErrorOrPending, isTrue);

      for (final tab in ['日历', '统计', '我的', '首页']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(controller.hasSyncErrorOrPending, isTrue,
            reason: 'tab=$tab overwrote hasSyncErrorOrPending');
      }
    });
  });

  group('v1.92.0 Stage A · overlap fixes, degradation cleanup & polish', () {
    testWidgets(
        'home non-sliver bubble avoids home-sync-status and right actions in light/dark themes and 320dp@2x',
        (tester) async {
      final now = DateTime.utc(2026, 11, 26, 2, 0);
      final store = await _createSeededStore(
        now: now,
        assignments: [
          for (var i = 0; i < 6; i++)
            _work(
              'due-$i',
              title: '课业 $i',
              due: now.add(Duration(hours: 2 + i)),
              syncedAt: now,
            ),
        ],
      );
      addTearDown(store.dispose);

      for (final theme in [
        StudyAssistantTheme.light,
        StudyAssistantTheme.dark,
      ]) {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final router = _buildShellRouter(store, clock: () => now);
        addTearDown(router.dispose);

        await tester.pumpWidget(
          MaterialApp.router(
            theme: theme,
            routerConfig: router,
          ),
        );
        await tester.pumpAndSettle();

        final buddyFinder = find.byKey(const ValueKey('home-pixel-buddy'));
        final syncStatusFinder = find.byKey(const ValueKey('home-sync-status'));
        final bubbleFinder = find.byKey(const ValueKey('clawd-speech-bubble'));
        final agendaFinder = find.byKey(const ValueKey('home-agenda-entry'));

        // Single-line bubble.
        await tester.tap(buddyFinder);
        await tester.pumpAndSettle();
        expect(bubbleFinder, findsOneWidget);
        var bubbleRect = tester.getRect(bubbleFinder);
        var statusRect = tester.getRect(syncStatusFinder);
        var agendaRect = tester.getRect(agendaFinder);
        expect(bubbleRect.overlaps(statusRect), isFalse);
        expect(bubbleRect.top, greaterThanOrEqualTo(statusRect.bottom + 1.5));
        expect(bubbleRect.right, lessThanOrEqualTo(agendaRect.left - 7.5));

        // 3+ rapid combo triggers long 2-line tsundere bubble -> still zero overlap.
        await tester.tap(buddyFinder);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tap(buddyFinder);
        await tester.pumpAndSettle();
        expect(
          tester.widget<ClawdSpeechBubble>(bubbleFinder).message.isTsundere,
          isTrue,
        );
        bubbleRect = tester.getRect(bubbleFinder);
        statusRect = tester.getRect(syncStatusFinder);
        agendaRect = tester.getRect(agendaFinder);
        expect(bubbleRect.overlaps(statusRect), isFalse);
        expect(bubbleRect.top, greaterThanOrEqualTo(statusRect.bottom + 1.5));
        expect(bubbleRect.right, lessThanOrEqualTo(agendaRect.left - 7.5));

        await tester.pump(const Duration(milliseconds: 2600));
        await tester.pumpAndSettle();

        // 320dp @ 2x large text -> zero overflow and zero overlap with home-sync-status.
        tester.view.physicalSize = const Size(320, 720);
        await tester.pumpWidget(
          MaterialApp.router(
            theme: theme,
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2.0),
              ),
              child: child!,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(buddyFinder);
        await tester.pumpAndSettle();
        expect(bubbleFinder, findsOneWidget);
        bubbleRect = tester.getRect(bubbleFinder);
        statusRect = tester.getRect(syncStatusFinder);
        expect(bubbleRect.overlaps(statusRect), isFalse);
        expect(bubbleRect.top, greaterThanOrEqualTo(statusRect.bottom + 1.5));
        expect(bubbleRect.right, lessThanOrEqualTo(320.0));
        expect(tester.takeException(), isNull);

        await tester.pump(const Duration(milliseconds: 2600));
        await tester.pumpAndSettle();
      }
    });

    testWidgets(
        'all 6 ClawdTitleStage choreo cycles and drag-release stay strictly right of title text',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0);
      final store = await _createSeededStore(now: now);
      addTearDown(store.dispose);
      final router = _buildShellRouter(store, clock: () => now);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: StudyAssistantTheme.light,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      final titleFinder = find.text('课业手记');
      final buddyFinder = find.byKey(const ValueKey('home-pixel-buddy'));
      final agendaFinder = find.byKey(const ValueKey('home-agenda-entry'));

      void expectSafeBounds(String phase) {
        final titleRect = tester.getRect(titleFinder);
        final buddyRect = tester.getRect(buddyFinder);
        final agendaRect = tester.getRect(agendaFinder);
        expect(
          buddyRect.overlaps(titleRect),
          isFalse,
          reason: '$phase: buddyRect=$buddyRect overlaps titleRect=$titleRect',
        );
        expect(
          buddyRect.left,
          greaterThanOrEqualTo(titleRect.right - 0.01),
          reason: '$phase: buddy left moved onto title text',
        );
        expect(
          buddyRect.right,
          lessThanOrEqualTo(agendaRect.left + 0.01),
          reason: '$phase: buddy crossed right actions boundary',
        );
      }

      expectSafeBounds('initial-rest');

      for (var cycle = 0; cycle < 6; cycle++) {
        final beforeRect = tester.getRect(buddyFinder);
        final delayMs = 2600 + (cycle * 439) % 1901;
        await tester.pump(Duration(milliseconds: delayMs - 250));
        var maxDelta = 0.0;
        for (var frame = 0; frame < 16; frame++) {
          await tester.pump(const Duration(milliseconds: 80));
          expectSafeBounds('cycle-$cycle-frame-$frame');
          final curRect = tester.getRect(buddyFinder);
          maxDelta = math.max(
            maxDelta,
            (curRect.center - beforeRect.center).distance,
          );
        }
        expect(
          maxDelta,
          greaterThan(1.5),
          reason: 'cycle-$cycle: Clawd did not displace during flight',
        );
        await tester.pumpAndSettle();
        expectSafeBounds('cycle-$cycle-settled');
      }

      // Drag buddy onto the title text on the left, release -> springs back strictly right of title.
      final titleCenter = tester.getCenter(titleFinder);
      final drag = await tester.startGesture(tester.getCenter(buddyFinder));
      await drag.moveTo(titleCenter);
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expectSafeBounds('drag-drop-settled');

      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pumpAndSettle();
    });

    testWidgets(
        'allowStageMotion degradation clears controller.transientPose without build-phase error',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0);
      final store = await _createSeededStore(now: now);
      addTearDown(store.dispose);
      final router = _buildShellRouter(store, clock: () => now);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: StudyAssistantTheme.light,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      final buddyFinder = find.byKey(const ValueKey('home-pixel-buddy'));
      final controller = ClawdCompanionScope.of(tester.element(buddyFinder));

      // Trigger transient pose via tap, then degrade via recoveryScope.
      await tester.tap(buddyFinder);
      await tester.pump();
      expect(controller.transientPose, ClawdTransientPose.wave);

      var postDegradeNotifications = 0;
      void countControllerNotify() => postDegradeNotifications++;
      controller.addListener(countControllerNotify);
      addTearDown(() => controller.removeListener(countControllerNotify));

      router.go('/assignments?scope=noDeadline');
      await tester.pump();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(postDegradeNotifications, greaterThanOrEqualTo(1));
      expect(
        tester
            .widget<ClawdTitleStage>(find.byType(ClawdTitleStage))
            .allowStageMotion,
        isFalse,
      );
      expect(controller.transientPose, ClawdTransientPose.none);

      // Return to normal, trigger transient pose, then degrade via narrow width < 330dp.
      router.go('/assignments');
      await tester.pumpAndSettle();
      await tester.tap(buddyFinder);
      await tester.pump();
      expect(controller.transientPose, isNot(ClawdTransientPose.none));

      tester.view.physicalSize = const Size(320, 720);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<ClawdTitleStage>(find.byType(ClawdTitleStage))
            .allowStageMotion,
        isFalse,
      );
      expect(controller.transientPose, ClawdTransientPose.none);

      await tester.pump(const Duration(milliseconds: 2600));
      await tester.pumpAndSettle();
    });

    testWidgets(
        'endPet lingers petSquint for ~600ms, clears after 650ms, and cancels cleanly on interruption',
        (tester) async {
      final controller = ClawdCompanionController();
      addTearDown(controller.dispose);
      controller.updateEnvironment(
        displayPrefs: const DisplayPreferences(),
        appResumed: true,
        tickerEnabled: true,
        reducedMotion: false,
        isSyncing: false,
        hasSyncErrorOrPending: false,
      );

      const snapshot = ClawdPageContextSnapshot(tab: ClawdPrimaryTab.home);
      controller.startPet(snapshot: snapshot);
      expect(controller.transientPose, ClawdTransientPose.petting);

      controller.endPet();
      expect(controller.transientPose, ClawdTransientPose.petting);

      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.transientPose, ClawdTransientPose.petting);

      await tester.pump(const Duration(milliseconds: 350));
      expect(controller.transientPose, ClawdTransientPose.none);

      // New interaction / reset cancels linger timer cleanly.
      controller.startPet(snapshot: snapshot);
      controller.endPet();
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.transientPose, ClawdTransientPose.petting);
      controller.resetForAccountChange();
      expect(controller.transientPose, ClawdTransientPose.none);
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Stats & Profile dismiss bubble on scroll and all 3 secondary tabs treat SyncPhase.running as busy',
        (tester) async {
      tester.view.physicalSize = const Size(360, 560);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0);
      final store = await _createSeededStore(
        now: now,
        assignments: [
          for (var i = 0; i < 6; i++)
            _work(
              'stat-$i',
              course: '课程$i',
              title: '作业$i',
              due: now.add(Duration(days: i + 1)),
              syncedAt: now,
            ),
        ],
      );
      addTearDown(store.dispose);

      final router = _buildShellRouter(store, clock: () => now);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: StudyAssistantTheme.light,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      // 1. Stats: tap cameo -> bubble shows; scroll ListView -> bubble dismisses.
      await tester.tap(find.text('统计'));
      await tester.pumpAndSettle();
      final statsCameo = find.byKey(const ValueKey('stats-pixel-buddy'));
      final controller = ClawdCompanionScope.of(tester.element(statsCameo));
      await tester.tap(statsCameo);
      await tester.pump();
      expect(find.byKey(const ValueKey('clawd-speech-bubble')), findsOneWidget);

      await tester.drag(find.byType(ListView).first, const Offset(0, -140));
      await tester.pump();
      expect(find.byKey(const ValueKey('clawd-speech-bubble')), findsNothing);

      // 2. Profile: tap cameo -> bubble shows; scroll ListView -> bubble dismisses.
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-pixel-buddy')));
      await tester.pump();
      expect(find.byKey(const ValueKey('clawd-speech-bubble')), findsOneWidget);

      await tester.drag(find.byType(ListView).first, const Offset(0, -140));
      await tester.pump();
      expect(find.byKey(const ValueKey('clawd-speech-bubble')), findsNothing);

      // 3. Calendar / Stats / Profile treat SyncPhase.running as busy (isSyncing: true).
      for (final tab in ['日历', '统计', '我的']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        store.syncReport = const SyncReport(phase: SyncPhase.running);
        store.notifyListeners();
        await tester.pump();
        expect(controller.isSyncing, isTrue,
            reason: 'tab=$tab ignored SyncPhase.running');

        store.syncReport =
            SyncReport(phase: SyncPhase.success, lastDataSuccessAt: now);
        store.notifyListeners();
        await tester.pump();
        expect(controller.isSyncing, isFalse);
      }

      // 4. Calendar hides active bubble when SyncPhase.running is active.
      await tester.tap(find.text('日历'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('calendar-pixel-buddy')));
      await tester.pump();
      expect(find.byKey(const ValueKey('clawd-speech-bubble')), findsOneWidget);
      store.syncReport = const SyncReport(phase: SyncPhase.running);
      store.notifyListeners();
      await tester.pump();
      expect(find.byKey(const ValueKey('clawd-speech-bubble')), findsNothing);
      store.syncReport =
          SyncReport(phase: SyncPhase.success, lastDataSuccessAt: now);
      store.notifyListeners();
      await tester.pumpAndSettle();
    });

    testWidgets(
        'ClawdTitleStage petting lingers petSquint at ~300ms after release and resets to normal after 650ms with zero settle timeout',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0);
      final store = await _createSeededStore(now: now);
      addTearDown(store.dispose);
      final router = _buildShellRouter(store, clock: () => now);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: StudyAssistantTheme.light,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      final buddyFinder = find.byKey(const ValueKey('home-pixel-buddy'));
      final gesture = await tester.startGesture(tester.getCenter(buddyFinder));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        tester.widget<JournalPixelBuddy>(buddyFinder).poseOverride,
        JournalPixelBuddyPose.petSquint,
      );

      await gesture.up();
      await tester.pump();
      expect(
        tester.widget<JournalPixelBuddy>(buddyFinder).poseOverride,
        JournalPixelBuddyPose.petSquint,
      );

      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<JournalPixelBuddy>(buddyFinder).poseOverride,
        JournalPixelBuddyPose.petSquint,
      );

      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester.widget<JournalPixelBuddy>(buddyFinder).poseOverride,
        JournalPixelBuddyPose.petSquint,
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.widget<JournalPixelBuddy>(buddyFinder).poseOverride,
        JournalPixelBuddyPose.normal,
      );

      await tester.pump(const Duration(milliseconds: 2600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Stats & Profile cameo bubbles stay anchored below cameo and clear of title after scroll+rebuild+top and 24dp micro-scroll, and home 24dp micro-scroll avoids sync status',
        (tester) async {
      tester.view.physicalSize = const Size(360, 560);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0);
      final store = await _createSeededStore(
        now: now,
        assignments: [
          for (var i = 0; i < 12; i++)
            Assignment(
              id: 'cx:work:1:${10 + i}:scroll-$i',
              courseName: '课程$i',
              title: '作业$i',
              deadlineAt: now.add(Duration(days: i + 1)),
              deadlineTrusted: true,
              requirementsText: '',
              status: 'pending',
              lastSyncedAt: now,
            ),
        ],
      );
      addTearDown(store.dispose);

      final router = _buildShellRouter(store, clock: () => now);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: StudyAssistantTheme.light,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      // Home micro-scroll 24dp (within 18..36dp transition band) keeps bubble below home-sync-status.
      await tester.tap(find.byKey(const ValueKey('home-pixel-buddy')));
      await tester.pump();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -42));
      await tester.pumpAndSettle();
      final homeScroll =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      expect(homeScroll.pixels, inInclusiveRange(20.0, 28.0));
      final homeBubbleRect =
          tester.getRect(find.byKey(const ValueKey('clawd-speech-bubble')));
      final homeStatusRect =
          tester.getRect(find.byKey(const ValueKey('home-sync-status')));
      expect(homeBubbleRect.overlaps(homeStatusRect), isFalse);
      expect(homeBubbleRect.top, greaterThanOrEqualTo(homeStatusRect.bottom));
      await tester.tap(find.byKey(const ValueKey('clawd-speech-bubble')));
      await tester.pumpAndSettle();

      // Home sliver tap in transition band (~34dp) and immediate scroll back to top both keep bubble clear of home-sync-status.
      homeScroll.jumpTo(34.0);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-sliver-pixel-buddy')));
      await tester.pump();
      final sliverTransitionBubble =
          tester.getRect(find.byKey(const ValueKey('clawd-speech-bubble')));
      final sliverTransitionStatus =
          tester.getRect(find.byKey(const ValueKey('home-sync-status')));
      expect(
        sliverTransitionBubble.overlaps(sliverTransitionStatus),
        isFalse,
        reason:
            'sliver transition bubble=$sliverTransitionBubble overlaps status=$sliverTransitionStatus',
      );
      expect(
        sliverTransitionBubble.top,
        greaterThanOrEqualTo(sliverTransitionStatus.bottom),
      );
      homeScroll.jumpTo(0.0);
      await tester.pump();
      final backToTopBubble =
          tester.getRect(find.byKey(const ValueKey('clawd-speech-bubble')));
      final backToTopStatus =
          tester.getRect(find.byKey(const ValueKey('home-sync-status')));
      expect(
        backToTopBubble.overlaps(backToTopStatus),
        isFalse,
        reason:
            'sliver-to-top bubble=$backToTopBubble overlaps status=$backToTopStatus',
      );
      expect(
        backToTopBubble.top,
        greaterThanOrEqualTo(backToTopStatus.bottom),
      );
      await tester.tap(find.byKey(const ValueKey('clawd-speech-bubble')));
      await tester.pumpAndSettle();

      Future<void> verifyCameoAndTitleBounds(
        String label, {
        required Finder titleFinder,
        required Finder cameoFinder,
      }) async {
        final bubbleFinder = find.byKey(const ValueKey('clawd-speech-bubble'));
        expect(bubbleFinder, findsOneWidget, reason: '$label: bubble missing');
        final bubbleRect = tester.getRect(bubbleFinder);
        final titleRect = tester.getRect(titleFinder);
        final cameoRect = tester.getRect(cameoFinder);
        final anchorFloor = cameoRect.bottom > titleRect.bottom
            ? cameoRect.bottom
            : titleRect.bottom;
        expect(
          bubbleRect.top,
          greaterThanOrEqualTo(cameoRect.bottom + 2.0),
          reason:
              '$label: bubble top=${bubbleRect.top} < cameo bottom=${cameoRect.bottom}',
        );
        expect(
          bubbleRect.top,
          lessThanOrEqualTo(anchorFloor + 12.0),
          reason:
              '$label: bubble top=${bubbleRect.top} drifted too far below anchorFloor=$anchorFloor',
        );
        expect(
          bubbleRect.overlaps(titleRect),
          isFalse,
          reason: '$label: bubble=$bubbleRect overlaps title=$titleRect',
        );
        expect(
          bubbleRect.overlaps(cameoRect),
          isFalse,
          reason: '$label: bubble=$bubbleRect overlaps cameo=$cameoRect',
        );
      }

      // StatsScreen: scroll 48dp -> rebuild via term filter -> scroll back to top -> tap cameo.
      await tester.tap(find.text('统计'));
      await tester.pumpAndSettle();
      final statsListFinder = find.byType(ListView).first;
      final statsScroll = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: statsListFinder,
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      await tester.timedDrag(
        statsListFinder,
        const Offset(0, -48),
        const Duration(milliseconds: 500),
      );
      await tester.pumpAndSettle();
      expect(statsScroll.pixels, inInclusiveRange(44.0, 52.0));

      await tester.tap(find.byKey(const ValueKey('stats-term-scope-allTerms')));
      await tester.pumpAndSettle();

      await tester.drag(statsListFinder, const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(statsScroll.pixels, 0.0);

      final statsTitleFinder = find.text('课业统计');
      final statsCameoFinder = find.byKey(const ValueKey('stats-pixel-buddy'));
      await tester.tap(statsCameoFinder);
      await tester.pumpAndSettle();
      await verifyCameoAndTitleBounds(
        'stats-rebuild-top',
        titleFinder: statsTitleFinder,
        cameoFinder: statsCameoFinder,
      );
      await tester.tap(find.byKey(const ValueKey('clawd-speech-bubble')));
      await tester.pumpAndSettle();

      // StatsScreen: micro-scroll 24dp from top -> tap cameo.
      await tester.timedDrag(
        statsListFinder,
        const Offset(0, -24),
        const Duration(milliseconds: 400),
      );
      await tester.pumpAndSettle();
      expect(statsScroll.pixels, inInclusiveRange(20.0, 28.0));
      await tester.tap(statsCameoFinder);
      await tester.pumpAndSettle();
      await verifyCameoAndTitleBounds(
        'stats-micro-24dp',
        titleFinder: statsTitleFinder,
        cameoFinder: statsCameoFinder,
      );
      await tester.tap(find.byKey(const ValueKey('clawd-speech-bubble')));
      await tester.pumpAndSettle();

      // ProfileScreen: scroll 48dp -> rebuild via theme switch -> scroll back to top -> tap cameo.
      tester.view.physicalSize = const Size(360, 660);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      final profileListFinder = find.byType(ListView).first;
      final profileScroll = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: profileListFinder,
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      Future<void> dragProfileToOffset(double targetOffset) async {
        final before = profileScroll.pixels;
        await tester.timedDragFrom(
          tester.getTopLeft(profileListFinder) + const Offset(8, 140),
          Offset(0, before - targetOffset),
          const Duration(milliseconds: 500),
        );
        await tester.pumpAndSettle();
        expect((profileScroll.pixels - before).abs(), greaterThan(8.0));
        if ((profileScroll.pixels - targetOffset).abs() > 4.0) {
          profileScroll.jumpTo(
            targetOffset.clamp(0.0, profileScroll.maxScrollExtent),
          );
          await tester.pumpAndSettle();
        }
      }

      await dragProfileToOffset(48.0);
      expect(profileScroll.pixels, inInclusiveRange(44.0, 52.0));

      await tester.tap(find.text(JournalThemeMode.dark.label));
      await tester.pumpAndSettle();
      expect(store.display.themeMode, JournalThemeMode.dark);

      await tester.drag(profileListFinder, const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(profileScroll.pixels, 0.0);

      final profileTitleFinder = find.text('我的手帐');
      final profileCameoFinder =
          find.byKey(const ValueKey('profile-pixel-buddy'));
      await tester.tap(profileCameoFinder);
      await tester.pumpAndSettle();
      await verifyCameoAndTitleBounds(
        'profile-rebuild-top',
        titleFinder: profileTitleFinder,
        cameoFinder: profileCameoFinder,
      );
      await tester.tap(find.byKey(const ValueKey('clawd-speech-bubble')));
      await tester.pumpAndSettle();

      // ProfileScreen: micro-scroll 24dp from top -> tap cameo.
      await dragProfileToOffset(24.0);
      expect(profileScroll.pixels, inInclusiveRange(20.0, 28.0));
      await tester.tap(profileCameoFinder);
      await tester.pumpAndSettle();
      await verifyCameoAndTitleBounds(
        'profile-micro-24dp',
        titleFinder: profileTitleFinder,
        cameoFinder: profileCameoFinder,
      );
      await tester.tap(find.byKey(const ValueKey('clawd-speech-bubble')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'CalendarScreen anchors cameo bubble dynamically, dismisses on vertical scroll, preserves bubble across horizontal month swipe, and re-aligns at top',
        (tester) async {
      tester.view.physicalSize = const Size(360, 560);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 26, 2, 0);
      final store = await _createSeededStore(
        now: now,
        assignments: [
          for (var i = 0; i < 10; i++)
            Assignment(
              id: 'cx:work:1:${20 + i}:cal-$i',
              courseName: '课程$i',
              title: '日历作业$i',
              deadlineAt: now.add(Duration(hours: i + 1)),
              deadlineTrusted: true,
              requirementsText: '',
              status: 'pending',
              lastSyncedAt: now,
            ),
        ],
      );
      addTearDown(store.dispose);

      final router = _buildShellRouter(store, clock: () => now);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: StudyAssistantTheme.light,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('日历'));
      await tester.pumpAndSettle();

      final titleFinder = find.text('课业日历');
      final cameoFinder = find.byKey(const ValueKey('calendar-pixel-buddy'));
      final bubbleFinder = find.byKey(const ValueKey('clawd-speech-bubble'));
      final agendaButtonFinder = find.text('个人待办');
      expect(agendaButtonFinder, findsOneWidget);
      expect(find.text('个人待办与考试'), findsNothing);
      expect(
        tester.getRect(agendaButtonFinder).left,
        greaterThan(tester.getRect(titleFinder).right),
      );

      void expectBubbleAligned(String label) {
        expect(bubbleFinder, findsOneWidget, reason: '$label: bubble missing');
        final bubbleRect = tester.getRect(bubbleFinder);
        final titleRect = tester.getRect(titleFinder);
        final cameoRect = tester.getRect(cameoFinder);
        final anchorFloor = cameoRect.bottom > titleRect.bottom
            ? cameoRect.bottom
            : titleRect.bottom;
        expect(
          bubbleRect.top,
          greaterThanOrEqualTo(cameoRect.bottom + 2.0),
          reason:
              '$label: bubble top=${bubbleRect.top} < cameo bottom=${cameoRect.bottom}',
        );
        expect(
          bubbleRect.top,
          lessThanOrEqualTo(anchorFloor + 12.0),
          reason:
              '$label: bubble top=${bubbleRect.top} drifted below anchorFloor=$anchorFloor',
        );
        expect(
          bubbleRect.overlaps(titleRect),
          isFalse,
          reason: '$label: bubble=$bubbleRect overlaps title=$titleRect',
        );
        expect(
          bubbleRect.overlaps(cameoRect),
          isFalse,
          reason: '$label: bubble=$bubbleRect overlaps cameo=$cameoRect',
        );
      }

      // 1. Tap cameo at top -> aligned dynamically below title & cameo.
      await tester.tap(cameoFinder);
      await tester.pumpAndSettle();
      expectBubbleAligned('calendar-top');

      // 2. Horizontal month PageView swipe must NOT dismiss the active bubble.
      final monthPageView = find.byType(PageView).first;
      await tester.drag(monthPageView, const Offset(-260, 0));
      await tester.pumpAndSettle();
      expect(find.text('2026年12月'), findsOneWidget);
      expect(find.text('回今天'), findsOneWidget);
      expectBubbleAligned('calendar-after-month-swipe');

      // Swipe back to current month so today's rich agenda keeps ListView scrollable.
      await tester.tap(find.text('回今天'));
      await tester.pumpAndSettle();
      expect(find.text('2026年11月'), findsOneWidget);

      // 3. Vertical scroll > 0.5dp dismisses the bubble immediately.
      final calendarListFinder = find.byType(ListView).first;
      final calendarScroll = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: calendarListFinder,
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      expect(calendarScroll.maxScrollExtent, greaterThan(48.0));

      await tester.drag(calendarListFinder, const Offset(0, -120));
      await tester.pump();
      expect(bubbleFinder, findsNothing);
      await tester.pumpAndSettle();

      // 4. Scroll back to top -> re-tap cameo aligns cleanly.
      await tester.drag(calendarListFinder, const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(calendarScroll.pixels, 0.0);
      await tester.tap(cameoFinder);
      await tester.pumpAndSettle();
      expectBubbleAligned('calendar-back-to-top');
      await tester.tap(bubbleFinder);
      await tester.pumpAndSettle();

      // 5. Micro-scroll ~24dp -> re-tap cameo proves dynamic top (not hardcoded 56dp).
      await tester.timedDragFrom(
        tester.getTopLeft(calendarListFinder) + const Offset(8, 100),
        const Offset(0, -24),
        const Duration(milliseconds: 500),
      );
      await tester.pumpAndSettle();
      expect(calendarScroll.pixels, inInclusiveRange(20.0, 28.0));
      await tester.tap(cameoFinder);
      await tester.pumpAndSettle();
      final microBubbleTop = tester.getRect(bubbleFinder).top;
      expect(microBubbleTop, lessThan(44.0));
      expectBubbleAligned('calendar-micro-24dp');
      expect(tester.takeException(), isNull);
    });
  });
}

class _WarningStore extends AssignmentStore {
  _WarningStore({super.clock})
      : super(
          sessionStore: _Session(),
          notificationService: _Notifications(),
          widgetSnapshotService: _Snapshot(),
        );

  @override
  bool get hasNonQuietServiceWarning => true;

  @override
  String? get recoveryWarning => '本机记录恢复提示';
}

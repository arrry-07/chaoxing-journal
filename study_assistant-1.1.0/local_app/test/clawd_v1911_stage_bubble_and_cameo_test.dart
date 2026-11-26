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
}) {
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
            builder: (_, __) => AssignmentListScreen(
              store: store,
              clock: clock,
            ),
          ),
          GoRoute(
            path: '/calendar',
            builder: (_, __) => CalendarScreen(store: store, clock: clock),
          ),
          GoRoute(
            path: '/stats',
            builder: (_, __) => StatsScreen(store: store, clock: clock),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, __) => ProfileScreen(store: store),
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
      await tester.tap(find.byKey(const ValueKey('stats-pixel-buddy')));
      await tester.pumpAndSettle();
      final statsBubbleRect =
          tester.getRect(find.byKey(const ValueKey('clawd-speech-bubble')));
      expect(statsBubbleRect.left, greaterThanOrEqualTo(0.0));
      expect(statsBubbleRect.right, lessThanOrEqualTo(360.0));
      final statsPtrX = statsBubbleRect.left +
          ClawdSpeechBubble.clampPointerCenterX(
            actualWidth: statsBubbleRect.width,
            pointerOffsetFromRight: 20.0,
          );
      expect(statsPtrX, greaterThanOrEqualTo(statsBubbleRect.left + 14.0));
      expect(statsPtrX, lessThanOrEqualTo(statsBubbleRect.right - 14.0));

      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-pixel-buddy')));
      await tester.pumpAndSettle();
      final profileBubbleRect =
          tester.getRect(find.byKey(const ValueKey('clawd-speech-bubble')));
      expect(profileBubbleRect.left, greaterThanOrEqualTo(0.0));
      expect(profileBubbleRect.right, lessThanOrEqualTo(360.0));
      final profilePtrX = profileBubbleRect.left +
          ClawdSpeechBubble.clampPointerCenterX(
            actualWidth: profileBubbleRect.width,
            pointerOffsetFromRight: 20.0,
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

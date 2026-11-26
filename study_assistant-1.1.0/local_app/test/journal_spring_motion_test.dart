import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal_motion.dart';
import 'package:study_assistant_mobile/src/features/stats_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_buttons.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_expansion_tile.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_picker_sheet.dart';
import 'package:study_assistant_mobile/src/features/widgets/manual_home_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/course_term_catalog.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _TestSessionStore extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'student-spring';
  @override
  Future<String?> readChaoxingPassword() async => 'pw';
  @override
  Future<String?> readChaoxingDisplayName() async => '测试同学';
  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _NoopNotifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}
  @override
  Future<void> rescheduleManual(List<ManualEntry> items) async {}
}

class _NoopSnapshot extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

void main() {
  group('M3 · JournalMotion spring presets & modalSheetAnimationStyle', () {
    test('presets, springTolerance, and springFor compatibility match spec',
        () {
      expect(JournalMotion.criticalSpring.mass, 1.0);
      expect(JournalMotion.criticalSpring.stiffness, 420.0);
      expect(JournalMotion.criticalSpring.damping, 41.0);

      expect(JournalMotion.pressSpring.mass, 1.0);
      expect(JournalMotion.pressSpring.stiffness, 620.0);
      expect(JournalMotion.pressSpring.damping, 42.0);

      expect(JournalMotion.popSpring.mass, 1.0);
      expect(JournalMotion.popSpring.stiffness, 500.0);
      expect(JournalMotion.popSpring.damping, 28.0);

      expect(JournalMotion.springTolerance.distance, 1e-3);
      expect(JournalMotion.springTolerance.velocity, 1e-3);

      final simDefault = JournalMotion.springFor(
        JournalMotion.criticalSpring,
        start: 0.0,
        end: 1.0,
      );
      expect(simDefault.tolerance.distance, 1e-3);
      expect(simDefault.tolerance.velocity, 1e-3);
      expect(simDefault.isDone(5.0), isTrue);
      expect(simDefault.x(5.0), 1.0);

      const customTol = Tolerance(distance: 1e-4, velocity: 1e-4);
      final simCustom = JournalMotion.springFor(
        JournalMotion.interactiveSpring,
        start: 0.0,
        end: 2.0,
        velocity: 1.5,
        tolerance: customTol,
      );
      expect(simCustom.tolerance.distance, 1e-4);
      expect(simCustom.tolerance.velocity, 1e-4);
    });

    testWidgets('modalSheetAnimationStyle honors disableAnimations',
        (tester) async {
      late AnimationStyle normalStyle;
      late AnimationStyle reducedStyle;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Builder(
            builder: (context) {
              normalStyle = JournalMotion.modalSheetAnimationStyle(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              reducedStyle = JournalMotion.modalSheetAnimationStyle(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(normalStyle.duration, const Duration(milliseconds: 280));
      expect(normalStyle.reverseDuration, const Duration(milliseconds: 210));
      expect(normalStyle.curve, JournalMotion.criticalCurve);
      expect(normalStyle.curve!.transform(0.0), 0.0);
      expect(normalStyle.curve!.transform(1.0), 1.0);
      var prevCurveValue = 0.0;
      for (var i = 0; i <= 20; i++) {
        final v = normalStyle.curve!.transform(i / 20.0);
        expect(v, inInclusiveRange(0.0, 1.0));
        expect(v, greaterThanOrEqualTo(prevCurveValue));
        prevCurveValue = v;
      }
      expect(reducedStyle, AnimationStyle.noAnimation);
      expect(reducedStyle.duration, Duration.zero);
      expect(reducedStyle.reverseDuration, Duration.zero);
    });
  });

  group('M3 · JournalPressableScale & JournalMicroBounce', () {
    testWidgets(
        'JournalPressableScale handles interruptible press/release, reduced motion, and enabled=false',
        (tester) async {
      double readScale() {
        final t = tester.widget<Transform>(
          find
              .descendant(
                of: find.byType(JournalPressableScale),
                matching: find.byType(Transform),
              )
              .first,
        );
        return t.transform.storage[0];
      }

      var enabled = true;
      late StateSetter setHostState;

      await tester.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          home: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return Scaffold(
                body: Center(
                  child: JournalPressableScale(
                    enabled: enabled,
                    pressScale: 0.92,
                    child: const SizedBox(
                      width: 120,
                      height: 48,
                      child: Center(child: Text('弹性按钮')),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );

      expect(readScale(), 1.0);

      // Press down and capture mid-press scale.
      final g1 = await tester.startGesture(tester.getCenter(find.text('弹性按钮')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      final downScale = readScale();
      expect(downScale, lessThan(1.0));
      expect(downScale, greaterThanOrEqualTo(0.92));

      // Release, then interrupt mid-rebound with another press.
      await g1.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final reboundingScale = readScale();
      expect(reboundingScale, greaterThan(downScale));

      final g2 = await tester.startGesture(tester.getCenter(find.text('弹性按钮')));
      await tester.pump();
      // Continuous handoff without snapping back to 1.0 or pressScale.
      expect(readScale(), closeTo(reboundingScale, 0.03));
      await tester.pump(const Duration(milliseconds: 64));
      expect(readScale(), lessThan(reboundingScale));

      // Disable while pressed -> snaps back to 1.0 on the very same frame.
      setHostState(() => enabled = false);
      await tester.pump();
      expect(readScale(), 1.0);

      await g2.up();
      await tester.pumpAndSettle();
      expect(readScale(), 1.0);

      // Reduced motion keeps scale fixed at 1.0.
      await tester.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const Scaffold(
            body: Center(
              child: JournalPressableScale(
                pressScale: 0.92,
                child: SizedBox(
                  width: 120,
                  height: 48,
                  child: Center(child: Text('减弱按钮')),
                ),
              ),
            ),
          ),
        ),
      );
      final g3 = await tester.startGesture(tester.getCenter(find.text('减弱按钮')));
      await tester.pump(const Duration(milliseconds: 48));
      expect(readScale(), 1.0);
      await g3.up();
      await tester.pumpAndSettle();
      expect(readScale(), 1.0);
    });

    testWidgets(
        'JournalMicroBounce is silent on mount, bounces on pulse increment, and respects reduced motion',
        (tester) async {
      double readBounceScale() {
        final t = tester.widget<Transform>(
          find
              .descendant(
                of: find.byType(JournalMicroBounce),
                matching: find.byType(Transform),
              )
              .first,
        );
        return t.transform.storage[0];
      }

      var pulse = 1; // Non-zero initial pulse must NOT auto-play on mount.
      var reduced = false;
      late StateSetter setHostState;

      await tester.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          home: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: Scaffold(
                  body: Center(
                    child: JournalMicroBounce(
                      pulse: pulse,
                      peakScale: 1.05,
                      child: const SizedBox(
                        width: 120,
                        height: 48,
                        child: Text('微弹卡片'),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );

      // First mount stays strictly at 1.0.
      await tester.pump(const Duration(milliseconds: 48));
      expect(readBounceScale(), 1.0);
      await tester.pumpAndSettle();
      expect(readBounceScale(), 1.0);

      // Increment pulse triggers popSpring peak > 1.0 then settles to 1.0.
      setHostState(() => pulse = 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      expect(readBounceScale(), greaterThan(1.01));
      await tester.pumpAndSettle();
      expect(readBounceScale(), 1.0);

      // Reduced motion keeps scale at 1.0 even when pulse increments.
      setHostState(() {
        reduced = true;
        pulse = 3;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      expect(readBounceScale(), 1.0);
      await tester.pumpAndSettle();
      expect(readBounceScale(), 1.0);
    });
  });

  group('M3 · _StatsTermScopeBar & JournalExpansionTile springs', () {
    testWidgets(
        'StatsScreen 4-scope bar redirects smoothly on rapid taps without overflow at 320dp@2x',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
      final now = DateTime.utc(2026, 11, 20, 4);
      final store = AssignmentStore(
        sessionStore: _TestSessionStore(),
        notificationService: _NoopNotifications(),
        widgetSnapshotService: _NoopSnapshot(),
      );
      addTearDown(store.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2.0),
            ),
            child: child!,
          ),
          home: StatsScreen(store: store, clock: () => now),
        ),
      );
      await tester.pumpAndSettle();

      final indicatorFinder =
          find.byKey(const ValueKey('stats-term-scope-indicator'));
      final startX = tester.getTopLeft(indicatorFinder).dx;

      // Rapidly tap allTerms -> currentAcademicYear -> pastTerms without waiting.
      await tester.tap(
        find.byKey(
            ValueKey('stats-term-scope-${CourseTermScope.allTerms.name}')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      final towardAllX = tester.getTopLeft(indicatorFinder).dx;
      expect(towardAllX, greaterThan(startX));

      await tester.tap(
        find.byKey(
          ValueKey(
            'stats-term-scope-${CourseTermScope.currentAcademicYear.name}',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 32));
      await tester.tap(
        find.byKey(
          ValueKey('stats-term-scope-${CourseTermScope.pastTerms.name}'),
        ),
      );
      await tester.pumpAndSettle();

      final pastRect = tester.getRect(
        find.byKey(
          ValueKey('stats-term-scope-${CourseTermScope.pastTerms.name}'),
        ),
      );
      final settledCenter = tester.getCenter(indicatorFinder).dx;
      expect(settledCenter, closeTo(pastRect.center.dx, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'JournalExpansionTile rotates chevron critically without overshoot and reverses on interrupt',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          home: const Scaffold(
            body: JournalExpansionTile(
              toggleKey: ValueKey('spring-exp-toggle'),
              title: Text('弹簧折叠项'),
              children: [Text('子内容')],
            ),
          ),
        ),
      );

      Transform readChevronTransform() => tester.widget<Transform>(
            find
                .ancestor(
                  of: find.byIcon(Icons.expand_more_rounded),
                  matching: find.byType(Transform),
                )
                .first,
          );

      expect(readChevronTransform().transform.storage[0], closeTo(1.0, 1e-3));

      // Tap to expand and verify smooth progression without exceeding pi.
      await tester.tap(find.byKey(const ValueKey('spring-exp-toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      final midCos = readChevronTransform().transform.storage[0];
      final midSin = readChevronTransform().transform.storage[1];
      expect(midCos, lessThan(1.0));
      expect(midCos, greaterThan(-1.0));
      expect(midSin, greaterThanOrEqualTo(-1e-3));

      // Tap again mid-flight to collapse back to 0.
      await tester.tap(find.byKey(const ValueKey('spring-exp-toggle')));
      await tester.pumpAndSettle();
      expect(readChevronTransform().transform.storage[0], closeTo(1.0, 1e-3));
      expect(readChevronTransform().transform.storage[1], closeTo(0.0, 1e-3));
      expect(find.text('子内容'), findsNothing);
    });
  });

  group('M3 · showJournalPickerSheet & ManualHomeCard interactions', () {
    testWidgets(
        'showJournalPickerSheet uses BouncingScrollPhysics, upward rubber-band drag, downward dismiss, and reduced motion',
        (tester) async {
      for (final reduced in [false, true]) {
        String? picked;
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey('picker-spring-$reduced'),
            theme: StudyAssistantTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      picked = await showJournalPickerSheet<String>(
                        context,
                        title: '选择课程',
                        options: [
                          for (var i = 0; i < 12; i++)
                            JournalPickerOption(value: 'c-$i', label: '课程 $i'),
                        ],
                      );
                    },
                    child: const Text('打开列表'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('打开列表'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        final handleFinder =
            find.byKey(const ValueKey('journal-picker-drag-handle'));
        final midOpenY = tester.getTopLeft(handleFinder).dy;
        await tester.pumpAndSettle();
        final settledOpenY = tester.getTopLeft(handleFinder).dy;
        if (reduced) {
          expect(midOpenY, closeTo(settledOpenY, 0.01));
        } else {
          expect(midOpenY, greaterThan(settledOpenY));
        }

        final listView = tester.widget<ListView>(find.byType(ListView));
        expect(listView.physics, isA<BouncingScrollPhysics>());

        // Check JournalFilterPill inside picker tree also uses JournalPressableScale.
        final initialHandleY = settledOpenY;

        // Upward drag on handle: rubber-band displacement when !reduced, 0 when reduced.
        final upDrag =
            await tester.startGesture(tester.getCenter(handleFinder));
        await upDrag.moveBy(const Offset(0, -60));
        await tester.pump();
        final pulledHandleY = tester.getTopLeft(handleFinder).dy;
        if (reduced) {
          expect(pulledHandleY, closeTo(initialHandleY, 0.01));
        } else {
          expect(pulledHandleY, lessThan(initialHandleY));
          expect(initialHandleY - pulledHandleY, lessThan(24.0));
        }
        await upDrag.up();
        await tester.pumpAndSettle();
        expect(
            tester.getTopLeft(handleFinder).dy, closeTo(initialHandleY, 0.01));

        // Downward drag on handle still triggers ModalBottomSheet dismiss!
        await tester.drag(handleFinder, const Offset(0, 420));
        await tester.pumpAndSettle();
        expect(find.text('选择课程'), findsNothing);
        expect(picked, isNull);
      }
    });

    testWidgets(
        'showJournalPickerSheet upward rubber-band and mid-rebound regrab preserve search focus, query text, and list scroll offset',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await showJournalPickerSheet<String>(
                      context,
                      title: '选择课程',
                      searchable: true,
                      options: [
                        for (var i = 0; i < 24; i++)
                          JournalPickerOption(value: 'c-$i', label: '课程 $i'),
                      ],
                    );
                  },
                  child: const Text('打开可搜索列表'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开可搜索列表'));
      await tester.pumpAndSettle();

      // Scroll the picker ListView first.
      await tester.drag(find.byType(ListView), const Offset(0, -180));
      await tester.pumpAndSettle();
      final listScrollable = Scrollable.of(tester.element(find.text('课程 6')));
      final scrolledOffset = listScrollable.position.pixels;
      expect(scrolledOffset, greaterThan(20.0));

      // Focus the search field and type query text matching all items.
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '课程');
      await tester.pump();

      bool hasSearchFocus() {
        final editable = tester.widget<EditableText>(find.byType(EditableText));
        return editable.focusNode.hasFocus;
      }

      String readSearchText() => tester
          .widget<EditableText>(find.byType(EditableText))
          .controller
          .text;

      expect(hasSearchFocus(), isTrue);
      expect(readSearchText(), '课程');
      expect(
        Scrollable.of(tester.element(find.text('课程 6'))).position.pixels,
        closeTo(scrolledOffset, 0.5),
      );

      final handleFinder =
          find.byKey(const ValueKey('journal-picker-drag-handle'));
      final initialHandleY = tester.getTopLeft(handleFinder).dy;

      // Upward pull -> preserves focus, text, and scroll offset.
      final g1 = await tester.startGesture(tester.getCenter(handleFinder));
      await g1.moveBy(const Offset(0, -60));
      await tester.pump();
      expect(tester.getTopLeft(handleFinder).dy, lessThan(initialHandleY));
      expect(hasSearchFocus(), isTrue);
      expect(readSearchText(), '课程');
      expect(
        Scrollable.of(tester.element(find.text('课程 6'))).position.pixels,
        closeTo(scrolledOffset, 0.5),
      );

      // Release, pump mid-rebound frame, then grab again mid-rebound.
      await g1.up();
      await tester.pump(const Duration(milliseconds: 24));
      final midReboundY = tester.getTopLeft(handleFinder).dy;
      expect(midReboundY, lessThan(initialHandleY));
      expect(hasSearchFocus(), isTrue);
      expect(readSearchText(), '课程');
      expect(
        Scrollable.of(tester.element(find.text('课程 6'))).position.pixels,
        closeTo(scrolledOffset, 0.5),
      );

      final g2 = await tester.startGesture(tester.getCenter(handleFinder));
      await g2.moveBy(const Offset(0, -50));
      await tester.pump();
      expect(tester.getTopLeft(handleFinder).dy, lessThan(midReboundY));
      expect(hasSearchFocus(), isTrue);
      expect(readSearchText(), '课程');
      expect(
        Scrollable.of(tester.element(find.text('课程 6'))).position.pixels,
        closeTo(scrolledOffset, 0.5),
      );

      await g2.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(handleFinder).dy, closeTo(initialHandleY, 0.01));
      expect(hasSearchFocus(), isTrue);
      expect(readSearchText(), '课程');
      expect(
        Scrollable.of(tester.element(find.text('课程 6'))).position.pixels,
        closeTo(scrolledOffset, 0.5),
      );

      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
    });

    testWidgets(
        'JournalFilterPill wraps JournalPressableScale(pressScale: 0.97)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          home: Scaffold(
            body: Center(
              child: JournalFilterPill(
                label: '全部课程',
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      final pressable = tester.widget<JournalPressableScale>(
        find.descendant(
          of: find.byType(JournalFilterPill),
          matching: find.byType(JournalPressableScale),
        ),
      );
      expect(pressable.pressScale, 0.97);
    });

    testWidgets(
        'ManualHomeCard complete button scales to 0.92 and bouncePulse triggers micro-bounce',
        (tester) async {
      final now = DateTime.utc(2026, 11, 20, 4);
      const entry = ManualEntry(
        id: 'm-spring-1',
        title: '完成线性代数习题',
        kind: ManualEntry.kindTodo,
      );
      var pulse = 0;
      late StateSetter setHostState;

      await tester.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          home: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return Scaffold(
                body: ManualHomeCard(
                  entry: entry,
                  now: now,
                  bouncePulse: pulse,
                  onTap: () {},
                  onToggleDone: () {},
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final completeFinder =
          find.byKey(const ValueKey('complete-manual-m-spring-1'));
      final pressable = tester.widget<JournalPressableScale>(
        find.ancestor(
          of: completeFinder,
          matching: find.byType(JournalPressableScale),
        ),
      );
      expect(pressable.pressScale, 0.92);

      // Pressing complete button scales down.
      final g = await tester.startGesture(tester.getCenter(completeFinder));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      final pressTransform = tester.widget<Transform>(
        find
            .descendant(
              of: find.ancestor(
                of: completeFinder,
                matching: find.byType(JournalPressableScale),
              ),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(pressTransform.transform.storage[0], lessThan(1.0));
      await g.up();
      await tester.pumpAndSettle();

      // Incrementing bouncePulse triggers JournalMicroBounce then settles to 1.0.
      double readCardBounceScale() => tester
          .widget<Transform>(
            find
                .descendant(
                  of: find.byType(JournalMicroBounce),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform
          .storage[0];

      expect(readCardBounceScale(), 1.0);
      setHostState(() => pulse = 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      expect(readCardBounceScale(), greaterThan(1.005));
      await tester.pumpAndSettle();
      expect(readCardBounceScale(), 1.0);
    });
  });
}

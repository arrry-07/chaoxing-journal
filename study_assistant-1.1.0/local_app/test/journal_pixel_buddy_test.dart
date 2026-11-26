import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_pixel_buddy.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_sliver_header.dart';
import 'package:study_assistant_mobile/src/models/assignment_sync_progress.dart';
import 'package:study_assistant_mobile/src/models/display_preferences.dart';
import 'package:study_assistant_mobile/src/services/clawd_companion_controller.dart';
import 'package:study_assistant_mobile/src/services/interaction_feedback_service.dart';

void main() {
  test('spinner glyphs and sync/tap phrase helpers stay concise', () {
    expect(kJournalSpinnerGlyphs, ['·', '✢', '✳', '✶', '✻', '✽']);

    for (final stage in <AssignmentSyncStage?>[
      ...AssignmentSyncStage.values,
      null
    ]) {
      for (var tick = 0; tick < 8; tick++) {
        final phrase = journalBuddySyncPhrase(stage, tick);
        expect(phrase, isNotEmpty);
        expect(phrase.length, lessThanOrEqualTo(12),
            reason: 'stage=$stage tick=$tick phrase=$phrase');
      }
    }

    final scenarios = <({int dueToday, int dueIn3Days, int completedToday})>[
      (dueToday: 0, dueIn3Days: 0, completedToday: 0),
      (dueToday: 3, dueIn3Days: 5, completedToday: 1),
      (dueToday: 120, dueIn3Days: 150, completedToday: 0),
      (dueToday: 0, dueIn3Days: 4, completedToday: 2),
      (dueToday: 0, dueIn3Days: 120, completedToday: 120),
      (dueToday: 0, dueIn3Days: 2, completedToday: 0),
      (dueToday: 0, dueIn3Days: 120, completedToday: 0),
    ];

    for (final s in scenarios) {
      final seen = <String>{};
      for (var tap = -1; tap < 10; tap++) {
        final whisper = journalBuddyTapWhisper(
          dueToday: s.dueToday,
          dueIn3Days: s.dueIn3Days,
          completedToday: s.completedToday,
          tapCount: tap,
        );
        expect(whisper, isNotEmpty);
        expect(whisper.length, lessThanOrEqualTo(12),
            reason: '$s tap=$tap whisper=$whisper');
        seen.add(whisper);
      }
      expect(seen.length, greaterThanOrEqualTo(2));
    }
  });

  testWidgets(
      'all 5 states render cleanly in light and dark without pumpAndSettle timeout',
      (t) async {
    for (final theme in [StudyAssistantTheme.light, StudyAssistantTheme.dark]) {
      for (final mood in [
        JournalPixelBuddyMood.idle,
        JournalPixelBuddyMood.dueToday,
        JournalPixelBuddyMood.allClear,
      ]) {
        var taps = 0;
        await t.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Center(
                child: JournalPixelBuddy(
                  mood: mood,
                  onTap: () => taps++,
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);

        await t.tap(find.byType(JournalPixelBuddy));
        await t.pumpAndSettle();
        expect(taps, 1);
        expect(t.takeException(), isNull);
      }

      // Syncing state steps cleanly across 180ms frames.
      await t.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Center(
              child: JournalPixelBuddy(mood: JournalPixelBuddyMood.syncing),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 180));
      await t.pump(const Duration(milliseconds: 180));
      await t.pump(const Duration(milliseconds: 180));
      expect(t.takeException(), isNull);
    }
  });

  testWidgets(
      'external syncTickListenable drives syncing without duplicate timer',
      (t) async {
    final tick = ValueNotifier<int>(0);
    addTearDown(tick.dispose);

    await t.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
          body: Center(
            child: JournalPixelBuddy(
              mood: JournalPixelBuddyMood.syncing,
              syncTickListenable: tick,
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    tick.value = 1;
    await t.pump();
    tick.value = 2;
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'lifecycle pause, TickerMode, reduced motion, and dispose cancel timers',
      (t) async {
    InteractionFeedback.debugReset();
    addTearDown(InteractionFeedback.debugReset);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final messenger = t.binding.defaultBinaryMessenger;
    const soundChannel = MethodChannel('study_assistant/interaction_sound');
    final feedbackKinds = <String>[];
    messenger.setMockMethodCallHandler(soundChannel, (call) async {
      feedbackKinds.add((call.arguments as Map)['kind'] as String);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(soundChannel, null));

    try {
      // 1. Reduced motion: tap still triggers feedback & onTap, no spring/timers.
      var taps = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Center(
                child: JournalPixelBuddy(
                  mood: JournalPixelBuddyMood.syncing,
                  displayPrefs: const DisplayPreferences(),
                  onTap: () => taps++,
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(JournalPixelBuddy));
      await t.pumpAndSettle();
      expect(taps, 1);
      expect(feedbackKinds, ['tap']);

      // 2. TickerMode disabled stops syncing/idle & tap jump cleanly.
      await t.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          home: const TickerMode(
            enabled: false,
            child: Scaffold(
              body: Center(
                child: JournalPixelBuddy(mood: JournalPixelBuddyMood.syncing),
              ),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull);

      // 3. AppLifecycleState pause and resume.
      await t.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          home: const Scaffold(
            body: Center(
              child: JournalPixelBuddy(mood: JournalPixelBuddyMood.syncing),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 180));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump(const Duration(milliseconds: 400));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump(const Duration(milliseconds: 180));
      expect(t.takeException(), isNull);

      // 4. Tap then immediately dispose while wave/spring/sync timers are active.
      await t.tap(find.byType(JournalPixelBuddy));
      await t.pump(const Duration(milliseconds: 30));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 5));
      expect(t.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('semantics and hit target sizing for default and mini buddy',
      (t) async {
    final semantics = t.ensureSemantics();
    try {
      await t.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          home: Scaffold(
            body: Column(
              children: [
                JournalPixelBuddy(
                  key: const ValueKey('default-interactive'),
                  onTap: () {},
                ),
                const JournalPixelBuddy(
                  key: ValueKey('mini-static'),
                  mini: true,
                ),
              ],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();

      final defaultFinder = find.byKey(const ValueKey('default-interactive'));
      final miniFinder = find.byKey(const ValueKey('mini-static'));

      final defaultSize = t.getSize(defaultFinder);
      expect(defaultSize.height, inInclusiveRange(40.0, 44.0));
      expect(defaultSize.width, greaterThanOrEqualTo(40.0));

      final miniSize = t.getSize(miniFinder);
      expect(miniSize.height, lessThan(40.0));
      expect(miniSize.width, lessThan(40.0));

      final defaultSemanticsWidget = t.widget<Semantics>(
        find.descendant(
          of: defaultFinder,
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == '像素伙伴，轻点互动',
          ),
        ),
      );
      expect(defaultSemanticsWidget.properties.button, isTrue);

      final miniSemanticsWidget = t.widget<Semantics>(
        find.descendant(
          of: miniFinder,
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == '像素伙伴，轻点互动',
          ),
        ),
      );
      expect(miniSemanticsWidget.properties.button, isFalse);

      final defaultNode = t.getSemantics(defaultFinder);
      expect(defaultNode.label, '像素伙伴，轻点互动');
      expect(defaultNode.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue);

      final miniNode = t.getSemantics(miniFinder);
      expect(miniNode.label, '像素伙伴，轻点互动');
      expect(
          miniNode.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'JournalSliverHeader preserves <=18 offset contract and shows titleTrailing',
      (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: const Scaffold(
          body: JournalSliverHeader(
            title: '课业手记',
            scrollOffset: 18.0,
            actions: [Icon(Icons.refresh)],
            titleTrailing: JournalPixelBuddy(mini: true),
            statusContent: Text('悬浮状态'),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('课业手记'), findsNothing);
    expect(find.byType(JournalPixelBuddy), findsNothing);
    expect(find.text('悬浮状态'), findsNothing);

    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: Scaffold(
            body: JournalSliverHeader(
              title: '课业手记',
              scrollOffset: 60.0,
              actions: const [Icon(Icons.refresh), Icon(Icons.more_horiz)],
              titleTrailing: JournalPixelBuddy(
                mini: true,
                onTap: () {},
              ),
              statusContent: const Text('今日待办1项，稳步推进'),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('课业手记'), findsOneWidget);
    expect(find.byType(JournalPixelBuddy), findsOneWidget);
    expect(find.text('今日待办1项，稳步推进'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('journalBuddyTapWhisper supports comboCount 1/2/3+ within 12 chars', () {
    expect(
      journalBuddyTapWhisper(
        dueToday: 1,
        dueIn3Days: 2,
        completedToday: 0,
        tapCount: 0,
        comboCount: 1,
      ),
      '今日待办1项，稳步推进',
    );

    final scenarios = <({int dueToday, int dueIn3Days, int completedToday})>[
      (dueToday: 0, dueIn3Days: 0, completedToday: 0),
      (dueToday: 2, dueIn3Days: 4, completedToday: 1),
      (dueToday: 0, dueIn3Days: 3, completedToday: 1),
      (dueToday: 0, dueIn3Days: 3, completedToday: 0),
    ];

    for (final combo in [1, 2, 3, 5]) {
      for (final s in scenarios) {
        final seen = <String>{};
        for (var tap = 0; tap < 8; tap++) {
          final phrase = journalBuddyTapWhisper(
            dueToday: s.dueToday,
            dueIn3Days: s.dueIn3Days,
            completedToday: s.completedToday,
            tapCount: tap,
            comboCount: combo,
          );
          expect(phrase, isNotEmpty);
          expect(phrase.length, lessThanOrEqualTo(12),
              reason: 'combo=$combo $s tap=$tap phrase=$phrase');
          seen.add(phrase);
        }
        expect(seen.length, greaterThanOrEqualTo(3));
      }
    }
  });

  testWidgets(
      'JournalSliverHeader uses borderless gradient, 5-stop IgnorePointer feather, and skips BackdropFilter in reduced motion',
      (t) async {
    Future<void> pumpHeader(ThemeData theme, {bool disableAnimations = false}) {
      return t.pumpWidget(
        MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: const Scaffold(
              body: JournalSliverHeader(
                title: '课业手记',
                scrollOffset: 72.0,
                actions: [Icon(Icons.refresh)],
                titleTrailing: JournalPixelBuddy(mini: true),
              ),
            ),
          ),
        ),
      );
    }

    for (final entry in <({
      ThemeData theme,
      double topAlpha,
      double midAlpha,
      double baseAlpha,
    })>[
      (
        theme: StudyAssistantTheme.light,
        topAlpha: 0.95,
        midAlpha: 0.90,
        baseAlpha: 0.84,
      ),
      (
        theme: StudyAssistantTheme.dark,
        topAlpha: 0.95,
        midAlpha: 0.91,
        baseAlpha: 0.86,
      ),
    ]) {
      await pumpHeader(entry.theme);
      await t.pumpAndSettle();

      final expectedPaper = entry.theme.extension<JournalPalette>()!.paper;
      final backdropFinder = find.byType(BackdropFilter);
      expect(backdropFinder, findsOneWidget);
      final backdrop = t.widget<BackdropFilter>(backdropFinder);
      expect(
        backdrop.filter,
        ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
      );

      final featherFinder =
          find.byKey(const ValueKey('journal-sliver-header-feather'));
      expect(featherFinder, findsOneWidget);
      expect(t.getSize(featherFinder).height, 18.0);

      final ignoreAncestor = t.widget<IgnorePointer>(
        find
            .ancestor(
              of: featherFinder,
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(ignoreAncestor.ignoring, isTrue);

      final featherBox = t.widget<DecoratedBox>(featherFinder);
      final featherGradient =
          (featherBox.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(featherGradient.stops, [0.0, 0.22, 0.50, 0.78, 1.0]);
      final expectedFeatherAlphas = [
        entry.baseAlpha,
        entry.baseAlpha * 0.78,
        entry.baseAlpha * 0.42,
        entry.baseAlpha * 0.14,
        0.0,
      ];
      expect(featherGradient.colors.length, 5);
      for (var i = 0; i < 5; i++) {
        expect(featherGradient.colors[i].a,
            closeTo(expectedFeatherAlphas[i], 1e-3),
            reason: 'feather stop[$i] alpha mismatch');
        expect(
          featherGradient.colors[i].toARGB32() & 0x00FFFFFF,
          expectedPaper.toARGB32() & 0x00FFFFFF,
        );
      }

      final bodyContainers = t
          .widgetList<Container>(
            find.descendant(
              of: find.byType(JournalSliverHeader),
              matching: find.byType(Container),
            ),
          )
          .where((c) => c.decoration is BoxDecoration)
          .toList();
      expect(bodyContainers.length, 1);
      final bodyDec = bodyContainers.single.decoration! as BoxDecoration;
      expect(bodyDec.border, isNull);
      final bodyGradient = bodyDec.gradient! as LinearGradient;
      expect(bodyGradient.stops, [0.0, 0.68, 1.0]);
      expect(bodyGradient.colors.length, 3);
      expect(bodyGradient.colors[0].a, closeTo(entry.topAlpha, 1e-3));
      expect(bodyGradient.colors[1].a, closeTo(entry.midAlpha, 1e-3));
      expect(bodyGradient.colors[2].a, closeTo(entry.baseAlpha, 1e-3));
    }

    // Reduced motion skips BackdropFilter, uses 0.97/0.93/0.90 body alphas, and keeps 5-stop feather skirt.
    await pumpHeader(StudyAssistantTheme.light, disableAnimations: true);
    await t.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    final reducedBodyContainer = t
        .widgetList<Container>(
          find.descendant(
            of: find.byType(JournalSliverHeader),
            matching: find.byType(Container),
          ),
        )
        .where((c) => c.decoration is BoxDecoration)
        .single;
    final reducedBodyGradient =
        (reducedBodyContainer.decoration! as BoxDecoration).gradient!
            as LinearGradient;
    expect(reducedBodyGradient.stops, [0.0, 0.68, 1.0]);
    expect(reducedBodyGradient.colors[0].a, closeTo(0.97, 1e-3));
    expect(reducedBodyGradient.colors[1].a, closeTo(0.93, 1e-3));
    expect(reducedBodyGradient.colors[2].a, closeTo(0.90, 1e-3));

    final reducedFeather = t.widget<DecoratedBox>(
      find.byKey(const ValueKey('journal-sliver-header-feather')),
    );
    final reducedGradient = (reducedFeather.decoration as BoxDecoration)
        .gradient! as LinearGradient;
    expect(reducedGradient.stops, [0.0, 0.22, 0.50, 0.78, 1.0]);
    final expectedReducedAlphas = [
      0.90,
      0.90 * 0.78,
      0.90 * 0.42,
      0.90 * 0.14,
      0.0,
    ];
    for (var i = 0; i < 5; i++) {
      expect(
          reducedGradient.colors[i].a, closeTo(expectedReducedAlphas[i], 1e-3));
    }

    // Real Stack hit-test: tapping button directly under 18dp feather skirt passes through.
    var buttonTapped = false;
    await t.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                top: 52.0,
                left: 0,
                right: 0,
                height: 24.0,
                child: TextButton(
                  key: const ValueKey('under-feather-button'),
                  onPressed: () => buttonTapped = true,
                  child: const Text('under-feather'),
                ),
              ),
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: JournalSliverHeader(
                  title: '课业手记',
                  scrollOffset: 72.0,
                  actions: [Icon(Icons.refresh)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final featherRect =
        t.getRect(find.byKey(const ValueKey('journal-sliver-header-feather')));
    final buttonRect =
        t.getRect(find.byKey(const ValueKey('under-feather-button')));
    expect(featherRect.overlaps(buttonRect), isTrue);
    await t.tapAt(featherRect.center);
    await t.pump();
    expect(buttonTapped, isTrue);
  });

  testWidgets(
      'idle rotation, 1/2/3-tap combo, celebratePulse, and non-zero initState settle cleanly',
      (t) async {
    var pulse = 4;
    await t.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  JournalPixelBuddy(
                    mood: JournalPixelBuddyMood.allClear,
                    celebratePulse: pulse,
                    onTap: () {},
                  ),
                  TextButton(
                    key: const ValueKey('trigger-cheer'),
                    onPressed: () => setState(() => pulse++),
                    child: const Text('cheer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // Non-zero initState celebratePulse must not start any animation.
    final buddyFinder = find.byType(JournalPixelBuddy);
    final initPainterBefore = t
        .widget<CustomPaint>(
          find.descendant(
            of: buddyFinder,
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    await t.pump(const Duration(milliseconds: 120));
    final initPainterAfter = t
        .widget<CustomPaint>(
          find.descendant(
            of: buddyFinder,
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    expect(initPainterAfter.shouldRepaint(initPainterBefore), isFalse);
    await t.pumpAndSettle();

    // Advance across multiple idle steps (6 actions in allClear) without timeouts.
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 3300));
      await t.pump(const Duration(milliseconds: 180));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }

    // Trigger celebratePulse cheer while original widget is mounted.
    final beforeCheerPainter = t
        .widget<CustomPaint>(
          find.descendant(
            of: buddyFinder,
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    await t.tap(find.byKey(const ValueKey('trigger-cheer')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 160));
    final duringCheerPainter = t
        .widget<CustomPaint>(
          find.descendant(
            of: buddyFinder,
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    expect(duringCheerPainter.shouldRepaint(beforeCheerPainter), isTrue);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);

    // Single-source controller drives combo (1/2/3+ -> tsundere) cleanly under pumpAndSettle.
    final comboController = ClawdCompanionController();
    addTearDown(comboController.dispose);
    comboController.updateEnvironment(
      displayPrefs: const DisplayPreferences(),
      appResumed: true,
      tickerEnabled: true,
      reducedMotion: false,
      isSyncing: false,
      hasSyncErrorOrPending: false,
      snapshot: const ClawdPageContextSnapshot(tab: ClawdPrimaryTab.home),
    );
    await t.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
          body: Center(
            child: AnimatedBuilder(
              animation: comboController,
              builder: (context, _) => JournalPixelBuddy(
                mood: JournalPixelBuddyMood.allClear,
                poseOverride: switch (comboController.transientPose) {
                  ClawdTransientPose.none => JournalPixelBuddyPose.normal,
                  ClawdTransientPose.wave => JournalPixelBuddyPose.wave,
                  ClawdTransientPose.doubleStar =>
                    JournalPixelBuddyPose.doubleStar,
                  ClawdTransientPose.tsundere =>
                    JournalPixelBuddyPose.tsunderePuff,
                  ClawdTransientPose.petting => JournalPixelBuddyPose.petSquint,
                  ClawdTransientPose.grabbed =>
                    JournalPixelBuddyPose.grabbedFlail,
                  ClawdTransientPose.landing => JournalPixelBuddyPose.landing,
                  ClawdTransientPose.cheer => JournalPixelBuddyPose.cheer,
                },
                posePulse: comboController.transientPulse,
                enableIdleActions: false,
                onTap: () => comboController.registerTap(
                  snapshot: const ClawdPageContextSnapshot(
                    tab: ClawdPrimaryTab.home,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(buddyFinder);
    await t.pump(const Duration(milliseconds: 120));
    await t.tap(buddyFinder);
    await t.pump(const Duration(milliseconds: 120));
    await t.tap(buddyFinder);
    await t.pump(const Duration(milliseconds: 120));
    await t.tap(buddyFinder);
    await t.pump(const Duration(milliseconds: 120));
    expect(comboController.comboCount, 4);
    expect(comboController.transientPose, ClawdTransientPose.tsundere);
    await t.pump(const Duration(milliseconds: 2600));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'Clawd pixel geometry has 4 equal discrete legs and clean sky spacing in allClear',
      (t) async {
    Future<({Uint8List rgba, int width, int height})> rasterize(
      CustomPainter painter,
      Size logicalSize, {
      double dpr = 1.0,
    }) async {
      final w = (logicalSize.width * dpr).round();
      final h = (logicalSize.height * dpr).round();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      if (dpr != 1.0) {
        canvas.scale(dpr, dpr);
      }
      painter.paint(canvas, logicalSize);
      final picture = recorder.endRecording();
      final image = await picture.toImage(w, h);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      picture.dispose();
      return (rgba: byteData!.buffer.asUint8List(), width: w, height: h);
    }

    List<({int start, int end})> opaqueRunsOnRow(
      ({Uint8List rgba, int width, int height}) img,
      int y,
    ) {
      final runs = <({int start, int end})>[];
      int? runStart;
      for (var x = 0; x < img.width; x++) {
        final alpha = img.rgba[(y * img.width + x) * 4 + 3];
        if (alpha > 200) {
          runStart ??= x;
        } else if (runStart != null) {
          runs.add((start: runStart, end: x));
          runStart = null;
        }
      }
      if (runStart != null) {
        runs.add((start: runStart, end: img.width));
      }
      return runs;
    }

    // 1) Resting idle at 56x56 @ 1x: Row 9 (y=42) & Row 10 (y=46) have 4 equal discrete legs.
    await t.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: const Scaffold(
          body: Center(
            child: JournalPixelBuddy(
              mood: JournalPixelBuddyMood.idle,
              size: 56,
            ),
          ),
        ),
      ),
    );
    final idlePainter = t
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(JournalPixelBuddy),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;

    final idleImg = await t.runAsync(
      () => rasterize(idlePainter, const Size(56, 56)),
    );
    final legRunsRow9 = opaqueRunsOnRow(idleImg!, 42);
    final legRunsRow10 = opaqueRunsOnRow(idleImg, 46);
    expect(legRunsRow9.length, 4);
    expect(legRunsRow10.length, 4);
    for (final run in [...legRunsRow9, ...legRunsRow10]) {
      expect(run.end - run.start, 4);
    }

    // 2) Mini 19dp @ 3x DPR: all 4 legs remain strictly equal physical width (4px, zero 2:1 distortion).
    await t.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(devicePixelRatio: 3.0),
          child: Scaffold(
            body: Center(
              child: JournalPixelBuddy(
                mood: JournalPixelBuddyMood.idle,
                mini: true,
                size: 19,
              ),
            ),
          ),
        ),
      ),
    );
    final miniPainter = t
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(JournalPixelBuddy),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    final miniImg = await t.runAsync(
      () => rasterize(miniPainter, const Size(19, 19), dpr: 3.0),
    );
    final miniLegRuns = opaqueRunsOnRow(miniImg!, 42);
    expect(miniLegRuns.length, 4);
    final widths = miniLegRuns.map((r) => r.end - r.start).toSet();
    expect(widths, {4});

    // 3) allClear at 56x56 @ 1x: zero top-left horns and empty Row 2 air gap above Row 3 head.
    await t.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: const Scaffold(
          body: Center(
            child: JournalPixelBuddy(
              mood: JournalPixelBuddyMood.allClear,
              size: 56,
            ),
          ),
        ),
      ),
    );
    final allClearPainter = t
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(JournalPixelBuddy),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    final allClearImg = await t.runAsync(
      () => rasterize(allClearPainter, const Size(56, 56)),
    );
    // Top-left (cols 0..2, rows 0..2 => x in 0..11, y in 4..15) must be 100% transparent.
    for (var y = 4; y < 16; y++) {
      for (var x = 0; x < 12; x++) {
        final alpha = allClearImg!.rgba[(y * allClearImg.width + x) * 4 + 3];
        expect(alpha, 0, reason: 'unexpected top-left pixel at ($x,$y)');
      }
    }
    // Row 2 across entire width (y in 12..15) must be 100% transparent air gap.
    for (var y = 12; y < 16; y++) {
      expect(opaqueRunsOnRow(allClearImg!, y), isEmpty,
          reason: 'Row 2 air gap must remain clear at y=$y');
    }
    // Top-right Row 0..1 has restrained sparkle.
    expect(opaqueRunsOnRow(allClearImg!, 6), isNotEmpty);
    expect(opaqueRunsOnRow(allClearImg, 10), isNotEmpty);
  });

  testWidgets(
      'syncing mood and allowTapCombo:false isolate combo/particles and reset to tap 1 on recovery',
      (t) async {
    Future<({Uint8List rgba, int width, int height})> rasterize(
      CustomPainter painter,
      Size logicalSize,
    ) async {
      final w = logicalSize.width.round();
      final h = logicalSize.height.round();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, logicalSize);
      final picture = recorder.endRecording();
      final image = await picture.toImage(w, h);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      picture.dispose();
      return (rgba: byteData!.buffer.asUint8List(), width: w, height: h);
    }

    int countOpaquePixelsInRect(
      ({Uint8List rgba, int width, int height}) img,
      Rect rect,
    ) {
      var count = 0;
      for (var y = rect.top.toInt(); y < rect.bottom.toInt(); y++) {
        for (var x = rect.left.toInt(); x < rect.right.toInt(); x++) {
          if (img.rgba[(y * img.width + x) * 4 + 3] > 0) {
            count++;
          }
        }
      }
      return count;
    }

    InteractionFeedback.debugReset();
    addTearDown(InteractionFeedback.debugReset);
    var fakeNow = DateTime(2026, 11, 26, 10, 0);
    InteractionFeedback.now = () => fakeNow;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final messenger = t.binding.defaultBinaryMessenger;
    const soundChannel = MethodChannel('study_assistant/interaction_sound');
    final feedbackKinds = <String>[];
    messenger.setMockMethodCallHandler(soundChannel, (call) async {
      feedbackKinds.add((call.arguments as Map)['kind'] as String);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(soundChannel, null));

    try {
      var taps = 0;
      final controller = ClawdCompanionController();
      addTearDown(controller.dispose);
      const snapshot = ClawdPageContextSnapshot(tab: ClawdPrimaryTab.home);
      controller.updateEnvironment(
        displayPrefs: const DisplayPreferences(),
        appResumed: true,
        tickerEnabled: true,
        reducedMotion: false,
        isSyncing: false,
        hasSyncErrorOrPending: false,
        snapshot: snapshot,
      );

      await t.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          home: Scaffold(
            body: Center(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final pose = switch (controller.transientPose) {
                    ClawdTransientPose.none => JournalPixelBuddyPose.normal,
                    ClawdTransientPose.wave => JournalPixelBuddyPose.wave,
                    ClawdTransientPose.doubleStar =>
                      JournalPixelBuddyPose.doubleStar,
                    ClawdTransientPose.tsundere =>
                      JournalPixelBuddyPose.tsunderePuff,
                    ClawdTransientPose.petting =>
                      JournalPixelBuddyPose.petSquint,
                    ClawdTransientPose.grabbed =>
                      JournalPixelBuddyPose.grabbedFlail,
                    ClawdTransientPose.landing => JournalPixelBuddyPose.landing,
                    ClawdTransientPose.cheer => JournalPixelBuddyPose.cheer,
                  };
                  return JournalPixelBuddy(
                    mood: controller.isSyncing
                        ? JournalPixelBuddyMood.syncing
                        : JournalPixelBuddyMood.idle,
                    allowTapCombo: !controller.isSyncing &&
                        !controller.hasSyncErrorOrPending,
                    poseOverride: pose,
                    posePulse: controller.transientPulse,
                    syncTickListenable: controller.syncTick,
                    size: 56,
                    displayPrefs: const DisplayPreferences(),
                    enableIdleActions: false,
                    onTap: () {
                      taps++;
                      controller.registerTap(snapshot: snapshot);
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );
      final buddyFinder = find.byType(JournalPixelBuddy);
      CustomPainter currentPainter() => t
          .widget<CustomPaint>(
            find.descendant(
              of: buddyFinder,
              matching: find.byType(CustomPaint),
            ),
          )
          .painter!;

      // Build combo to 2 in idle via single-source controller, then transition into syncing.
      fakeNow = fakeNow.add(const Duration(milliseconds: 100));
      await t.tap(buddyFinder);
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      fakeNow = fakeNow.add(const Duration(milliseconds: 100));
      await t.tap(buddyFinder);
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(controller.comboCount, 2);
      controller.updateEnvironment(isSyncing: true);
      await t.pump();

      // Tap 3 times during syncing: onTap & feedback still fire, zero particles/combo.
      final tapsBeforeSyncing = taps;
      fakeNow = fakeNow.add(const Duration(milliseconds: 100));
      await t.tap(buddyFinder);
      await t.pump();
      await t.pump(const Duration(milliseconds: 55));
      fakeNow = fakeNow.add(const Duration(milliseconds: 100));
      await t.tap(buddyFinder);
      await t.pump();
      await t.pump(const Duration(milliseconds: 55));
      fakeNow = fakeNow.add(const Duration(milliseconds: 100));
      await t.tap(buddyFinder);
      await t.pump();
      await t.pump(const Duration(milliseconds: 115));
      expect(taps - tapsBeforeSyncing, 3);
      expect(controller.comboCount, 0);
      expect(feedbackKinds.where((k) => k == 'tap').length, 5);
      expect(
        feedbackKinds
            .skip(4)
            .where((k) => k == 'clawdJump' || k == 'clawdCombo2'),
        isEmpty,
      );

      final syncingImg = await t.runAsync(
        () => rasterize(currentPainter(), const Size(56, 56)),
      );
      expect(
        countOpaquePixelsInRect(syncingImg!, const Rect.fromLTWH(0, 0, 56, 12)),
        0,
        reason: 'syncing mood must never emit floating sky particles',
      );

      // Exit syncing -> next tap must start fresh from tap 1 (tapWave: no particles, right arm raised).
      controller.updateEnvironment(isSyncing: false);
      await t.pump();
      fakeNow = fakeNow.add(const Duration(milliseconds: 100));
      await t.tap(buddyFinder);
      await t.pump();
      await t.pump(const Duration(milliseconds: 120));
      expect(controller.comboCount, 1);
      final recoveredImg = await t.runAsync(
        () => rasterize(currentPainter(), const Size(56, 56)),
      );
      expect(
        countOpaquePixelsInRect(
            recoveredImg!, const Rect.fromLTWH(0, 0, 56, 12)),
        0,
        reason: 'first tap after syncing must be tap 1 tapWave (no star/heart)',
      );
      await t.pump(const Duration(milliseconds: 2600));
      await t.pumpAndSettle();

      // hasSyncErrorOrPending: true (allowTapCombo: false) clears combo and ignores tap combo/particles while preserving onTap.
      fakeNow = fakeNow.add(const Duration(milliseconds: 100));
      await t.tap(buddyFinder);
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      fakeNow = fakeNow.add(const Duration(milliseconds: 100));
      await t.tap(buddyFinder);
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(controller.comboCount, 2);
      controller.updateEnvironment(hasSyncErrorOrPending: true);
      await t.pumpAndSettle();

      final tapsBeforeDisabled = taps;
      fakeNow = fakeNow.add(const Duration(milliseconds: 100));
      await t.tap(buddyFinder);
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      fakeNow = fakeNow.add(const Duration(milliseconds: 100));
      await t.tap(buddyFinder);
      await t.pump();
      await t.pump(const Duration(milliseconds: 115));
      expect(taps - tapsBeforeDisabled, 2);
      expect(controller.comboCount, 0);
      final disabledImg = await t.runAsync(
        () => rasterize(currentPainter(), const Size(56, 56)),
      );
      expect(
        countOpaquePixelsInRect(
            disabledImg!, const Rect.fromLTWH(0, 0, 56, 16)),
        0,
        reason: 'allowTapCombo:false must not render tap combo particles',
      );

      // Re-enable -> first tap starts from tap 1 (no star/heart particles).
      controller.updateEnvironment(hasSyncErrorOrPending: false);
      await t.pump();
      fakeNow = fakeNow.add(const Duration(milliseconds: 100));
      await t.tap(buddyFinder);
      await t.pump();
      await t.pump(const Duration(milliseconds: 120));
      expect(controller.comboCount, 1);
      final reenabledImg = await t.runAsync(
        () => rasterize(currentPainter(), const Size(56, 56)),
      );
      expect(
        countOpaquePixelsInRect(
            reenabledImg!, const Rect.fromLTWH(0, 0, 56, 12)),
        0,
        reason: 'first tap after allowTapCombo recovery must be tap 1 tapWave',
      );
      await t.pump(const Duration(milliseconds: 2600));
      await t.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'tapDoubleStar and tapDoubleHeart peak frames (t=0.25) keep particles strictly above Clawd forehead and eyes',
      (t) async {
    Future<({Uint8List rgba, int width, int height})> rasterize(
      CustomPainter painter,
      Size logicalSize,
    ) async {
      final w = logicalSize.width.round();
      final h = logicalSize.height.round();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, logicalSize);
      final picture = recorder.endRecording();
      final image = await picture.toImage(w, h);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      picture.dispose();
      return (rgba: byteData!.buffer.asUint8List(), width: w, height: h);
    }

    int pixelArgb(
      ({Uint8List rgba, int width, int height}) img,
      int x,
      int y,
    ) {
      final i = (y * img.width + x) * 4;
      final r = img.rgba[i];
      final g = img.rgba[i + 1];
      final b = img.rgba[i + 2];
      final a = img.rgba[i + 3];
      return (a << 24) | (r << 16) | (g << 8) | b;
    }

    int countOpaqueInSky(
      ({Uint8List rgba, int width, int height}) img, {
      required int maxY,
    }) {
      var count = 0;
      for (var y = 0; y < maxY; y++) {
        for (var x = 0; x < img.width; x++) {
          if (img.rgba[(y * img.width + x) * 4 + 3] > 0) {
            count++;
          }
        }
      }
      return count;
    }

    void expectCleanForeheadAndEyes(
      ({Uint8List rgba, int width, int height}) img, {
      required String phase,
    }) {
      // At 56x56 @ 1x, cell=4, originY=4; at t=0.25 hopPx=-7 -> effectiveOriginY=-3.
      // Clawd torso top edge (row 3) is at y=9: forehead cols 3..10 (x 12..44, y 9..13)
      // must be pure highlight (#FFEDA083), and eyes (x 16..20 & 36..40, y 13..21)
      // must be pure eye (#FF1F2328) with zero particle overlap.
      for (var y = 9; y < 13; y++) {
        for (var x = 12; x < 44; x++) {
          expect(
            pixelArgb(img, x, y),
            0xFFEDA083,
            reason: '$phase forehead pixel at ($x,$y) overwritten by particle',
          );
        }
      }
      for (var y = 13; y < 21; y++) {
        for (final eyeXStart in [16, 36]) {
          for (var x = eyeXStart; x < eyeXStart + 4; x++) {
            expect(
              pixelArgb(img, x, y),
              0xFF1F2328,
              reason: '$phase eye pixel at ($x,$y) overwritten by particle',
            );
          }
        }
      }
    }

    var pose = JournalPixelBuddyPose.normal;
    var posePulse = 0;
    late StateSetter updatePose;

    await t.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                updatePose = setState;
                return JournalPixelBuddy(
                  mood: JournalPixelBuddyMood.idle,
                  poseOverride: pose,
                  posePulse: posePulse,
                  enableIdleActions: false,
                  size: 56,
                  onTap: () {},
                );
              },
            ),
          ),
        ),
      ),
    );
    final buddyFinder = find.byType(JournalPixelBuddy);
    CustomPainter currentPainter() => t
        .widget<CustomPaint>(
          find.descendant(
            of: buddyFinder,
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;

    // Trigger tapDoubleStar via poseOverride + posePulse -> advance 115ms (t=0.25 peak frame).
    updatePose(() {
      pose = JournalPixelBuddyPose.doubleStar;
      posePulse = 1;
    });
    await t.pump();
    await t.pump(const Duration(milliseconds: 115));

    final starPeakImg = await t.runAsync(
      () => rasterize(currentPainter(), const Size(56, 56)),
    );
    expect(
      countOpaqueInSky(starPeakImg!, maxY: 9),
      greaterThan(0),
      reason: 'tapDoubleStar t=0.25 must render star pixels above y=9',
    );
    expectCleanForeheadAndEyes(starPeakImg, phase: 'tapDoubleStar');

    // Trigger tapDoubleHeart via poseOverride + posePulse -> advance 120ms (t=0.25 peak frame).
    updatePose(() {
      pose = JournalPixelBuddyPose.doubleHeart;
      posePulse = 2;
    });
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));

    final heartPeakImg = await t.runAsync(
      () => rasterize(currentPainter(), const Size(56, 56)),
    );
    expect(
      countOpaqueInSky(heartPeakImg!, maxY: 9),
      greaterThan(0),
      reason: 'tapDoubleHeart t=0.25 must render heart pixels above y=9',
    );
    expectCleanForeheadAndEyes(heartPeakImg, phase: 'tapDoubleHeart');

    await t.pumpAndSettle();
  });

  testWidgets(
      'incrementing posePulse replays identical tsunderePuff pose and landing squash settles cleanly',
      (t) async {
    var pose = JournalPixelBuddyPose.tsunderePuff;
    var pulse = 1;
    late StateSetter updatePose;

    await t.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                updatePose = setState;
                return JournalPixelBuddy(
                  size: 38.0,
                  poseOverride: pose,
                  posePulse: pulse,
                  enableIdleActions: false,
                  handleGestures: false,
                );
              },
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final beforeReplay = t
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(JournalPixelBuddy),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;

    // 4th+ tap keeps tsunderePuff while incrementing posePulse -> must replay animation from 0.
    updatePose(() => pulse = 2);
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    final duringReplay = t
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(JournalPixelBuddy),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    expect(duringReplay.shouldRepaint(beforeReplay), isTrue);
    await t.pumpAndSettle();

    // Landing squash-and-recover settles cleanly.
    updatePose(() {
      pose = JournalPixelBuddyPose.landing;
      pulse = 3;
    });
    await t.pump();
    await t.pump(const Duration(milliseconds: 140));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'Clawd 2.0 Shimeji poses render crisply in light & dark themes and settle cleanly',
      (t) async {
    for (final theme in [StudyAssistantTheme.light, StudyAssistantTheme.dark]) {
      for (final pose in [
        JournalPixelBuddyPose.sitDangle,
        JournalPixelBuddyPose.napZzz,
        JournalPixelBuddyPose.climbEdge,
        JournalPixelBuddyPose.hangSlipFlip,
        JournalPixelBuddyPose.petSquint,
        JournalPixelBuddyPose.grabbedFlail,
        JournalPixelBuddyPose.tsunderePuff,
        JournalPixelBuddyPose.landing,
      ]) {
        await t.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Center(
                child: JournalPixelBuddy(
                  size: 38.0,
                  poseOverride: pose,
                  poseProgress: 0.45,
                  facingSign: -1,
                  enableIdleActions: false,
                  handleGestures: false,
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'pose=$pose threw');
      }
    }
  });
}

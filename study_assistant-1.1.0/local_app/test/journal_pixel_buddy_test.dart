import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_pixel_buddy.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_sliver_header.dart';
import 'package:study_assistant_mobile/src/models/assignment_sync_progress.dart';
import 'package:study_assistant_mobile/src/models/display_preferences.dart';
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
}

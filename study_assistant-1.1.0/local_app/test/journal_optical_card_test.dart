import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_floating_detail_header.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_grouped_card.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_picker_sheet.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

const _inkKey = ValueKey('optical-card-ink');
const _emphasizedKey = ValueKey('optical-card-emphasized');

JournalPalette _paletteFor(ThemeData theme) =>
    theme.extension<JournalPalette>()!;

Future<void> _pumpCards(WidgetTester tester, ThemeData theme) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              JournalGroupedCard(
                key: _inkKey,
                children: const [
                  SizedBox(height: 44),
                  SizedBox(height: 44),
                ],
              ),
              const SizedBox(height: 24),
              JournalGroupedCard(
                key: _emphasizedKey,
                emphasized: true,
                children: const [
                  SizedBox(height: 44),
                  SizedBox(height: 44),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  ));
}

BoxDecoration _cardDecoration(WidgetTester tester, Key key) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(of: find.byKey(key), matching: find.byType(DecoratedBox))
        .first,
  );
  return box.decoration as BoxDecoration;
}

Material _cardMaterial(WidgetTester tester, Key key) => tester.widget<Material>(
      find
          .descendant(of: find.byKey(key), matching: find.byType(Material))
          .first,
    );

// Material wraps its child in a `_ShapeBorderPaint` CustomPaint, so the card's
// own surface painter is the inner (last) CustomPaint in depth-first order for
// these fixtures, whose row children are plain SizedBoxes.
CustomPaint _cardPaint(WidgetTester tester, Key key) =>
    tester.widget<CustomPaint>(
      find
          .descendant(of: find.byKey(key), matching: find.byType(CustomPaint))
          .last,
    );

double _contrastRatio(Color fg, Color bg) {
  final l1 = fg.computeLuminance();
  final l2 = bg.computeLuminance();
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  group('JournalPalette optical & input tokens', () {
    test('light palette exposes the documented values', () {
      const palette = JournalPalette.light;
      expect(palette.inputFill, const Color(0xFFF8F7F4));
      expect(palette.inputBorder, const Color(0xFF8E8B82));
      expect(palette.inputBorderDisabled, const Color(0xFFD6D4CC));
      expect(palette.cardShadowContact, const Color(0x071F2328));
      expect(palette.cardShadowAmbient, const Color(0x0A1F2328));
      expect(palette.cardTopHighlight, const Color(0xB8FFFFFF));
      expect(palette.cardEmphasisTintStart, const Color(0x0F3D63DD));
      expect(palette.cardEmphasisTintEnd, const Color(0x003D63DD));
      expect(palette.cardEmphasisBar, const Color(0xCC3D63DD));
      expect(palette.cardEmphasisBarGlow, const Color(0x2E3D63DD));
      // Existing tokens must not drift while the optical layer is added.
      expect(palette.paper, Journal.paper);
      expect(palette.sheet, Journal.sheet);
      expect(palette.sageBorder, Journal.sageBorder);
      expect(_contrastRatio(palette.inputBorder, palette.paper),
          greaterThanOrEqualTo(3.0));
      expect(_contrastRatio(palette.inputBorder, palette.inputFill),
          greaterThanOrEqualTo(3.0));
    });

    test('dark palette exposes the documented values', () {
      const palette = JournalPalette.dark;
      expect(palette.inputFill, const Color(0xFF1B1A17));
      expect(palette.inputBorder, const Color(0xFF7A756C));
      expect(palette.inputBorderDisabled, const Color(0xFF423F39));
      expect(palette.cardShadowContact, const Color(0x24000000));
      expect(palette.cardShadowAmbient, const Color(0x38000000));
      expect(palette.cardTopHighlight, const Color(0x18FFF8EB));
      expect(palette.cardEmphasisTintStart, const Color(0x1888A8F8));
      expect(palette.cardEmphasisTintEnd, const Color(0x0488A8F8));
      expect(palette.cardEmphasisBar, const Color(0xCC88A8F8));
      expect(palette.cardEmphasisBarGlow, const Color(0x3688A8F8));
      expect(palette.cardBorder, const Color(0x14FFF8EB));
      expect(palette.sageBorder, const Color(0xFF3D4C6E));
      expect(_contrastRatio(palette.inputBorder, palette.sheet),
          greaterThanOrEqualTo(3.0));
      expect(_contrastRatio(palette.inputBorder, palette.sheetElevated),
          greaterThanOrEqualTo(3.0));
      expect(_contrastRatio(palette.inputBorder, palette.inputFill),
          greaterThanOrEqualTo(3.0));
    });

    test('copyWith carries every optical and input token', () {
      final light = JournalPalette.light;
      const changed = Color(0xFF123456);
      final copy = light.copyWith(
        inputFill: changed,
        inputBorder: changed,
        inputBorderDisabled: changed,
        cardShadowContact: changed,
        cardShadowAmbient: changed,
        cardTopHighlight: changed,
        cardEmphasisTintStart: changed,
        cardEmphasisTintEnd: changed,
        cardEmphasisBar: changed,
        cardEmphasisBarGlow: changed,
      );
      expect(copy.inputFill, changed);
      expect(copy.inputBorder, changed);
      expect(copy.inputBorderDisabled, changed);
      expect(copy.cardShadowContact, changed);
      expect(copy.cardShadowAmbient, changed);
      expect(copy.cardTopHighlight, changed);
      expect(copy.cardEmphasisTintStart, changed);
      expect(copy.cardEmphasisTintEnd, changed);
      expect(copy.cardEmphasisBar, changed);
      expect(copy.cardEmphasisBarGlow, changed);
      expect(copy.paper, light.paper);
      expect(copy.cardBorder, light.cardBorder);
      expect(copy, isNot(equals(light)));
    });

    test('copyWith() without arguments equals the source palette', () {
      final clone = JournalPalette.light.copyWith();
      expect(clone, equals(JournalPalette.light));
      expect(clone.hashCode, JournalPalette.light.hashCode);
      expect(JournalPalette.dark.copyWith(), equals(JournalPalette.dark));
    });

    test('equality and hashCode react to each optical and input token', () {
      final mutations = <String, JournalPalette Function()>{
        'inputFill': () =>
            JournalPalette.light.copyWith(inputFill: const Color(0xFF000001)),
        'inputBorder': () =>
            JournalPalette.light.copyWith(inputBorder: const Color(0xFF000002)),
        'inputBorderDisabled': () => JournalPalette.light
            .copyWith(inputBorderDisabled: const Color(0xFF00000A)),
        'cardShadowContact': () => JournalPalette.light
            .copyWith(cardShadowContact: const Color(0xFF000003)),
        'cardShadowAmbient': () => JournalPalette.light
            .copyWith(cardShadowAmbient: const Color(0xFF000004)),
        'cardTopHighlight': () => JournalPalette.light
            .copyWith(cardTopHighlight: const Color(0xFF000005)),
        'cardEmphasisTintStart': () => JournalPalette.light
            .copyWith(cardEmphasisTintStart: const Color(0xFF000006)),
        'cardEmphasisTintEnd': () => JournalPalette.light
            .copyWith(cardEmphasisTintEnd: const Color(0xFF000007)),
        'cardEmphasisBar': () => JournalPalette.light
            .copyWith(cardEmphasisBar: const Color(0xFF000008)),
        'cardEmphasisBarGlow': () => JournalPalette.light
            .copyWith(cardEmphasisBarGlow: const Color(0xFF000009)),
      };
      for (final entry in mutations.entries) {
        final mutated = entry.value();
        expect(mutated, isNot(equals(JournalPalette.light)),
            reason: '${entry.key} must participate in operator ==');
        expect(mutated.hashCode, isNot(JournalPalette.light.hashCode),
            reason: '${entry.key} must participate in hashCode');
      }
    });

    test('lerp interpolates every optical and input token', () {
      const light = JournalPalette.light;
      const dark = JournalPalette.dark;
      final mid = light.lerp(dark, 0.5);
      expect(mid.isDark, dark.isDark);
      expect(mid.inputFill, Color.lerp(light.inputFill, dark.inputFill, 0.5));
      expect(mid.inputBorder,
          Color.lerp(light.inputBorder, dark.inputBorder, 0.5));
      expect(mid.inputBorderDisabled,
          Color.lerp(light.inputBorderDisabled, dark.inputBorderDisabled, 0.5));
      expect(mid.cardShadowContact,
          Color.lerp(light.cardShadowContact, dark.cardShadowContact, 0.5));
      expect(mid.cardShadowAmbient,
          Color.lerp(light.cardShadowAmbient, dark.cardShadowAmbient, 0.5));
      expect(mid.cardTopHighlight,
          Color.lerp(light.cardTopHighlight, dark.cardTopHighlight, 0.5));
      expect(
          mid.cardEmphasisTintStart,
          Color.lerp(
              light.cardEmphasisTintStart, dark.cardEmphasisTintStart, 0.5));
      expect(mid.cardEmphasisTintEnd,
          Color.lerp(light.cardEmphasisTintEnd, dark.cardEmphasisTintEnd, 0.5));
      expect(mid.cardEmphasisBar,
          Color.lerp(light.cardEmphasisBar, dark.cardEmphasisBar, 0.5));
      expect(mid.cardEmphasisBarGlow,
          Color.lerp(light.cardEmphasisBarGlow, dark.cardEmphasisBarGlow, 0.5));
      expect(light.lerp(dark, 0), equals(light));
      expect(light.lerp(dark, 1), equals(dark));
    });

    test(
        'Journal.uiFamily isolates numeric/pill styles from display/body serif',
        () {
      expect(Journal.uiFamily, 'sans-serif');
      for (final style in [Journal.time, Journal.statHero, Journal.pillLabel]) {
        expect(style.fontFamily, Journal.uiFamily);
        expect(
            style.fontFeatures, contains(const FontFeature.tabularFigures()));
      }
      for (final style in [
        Journal.display,
        Journal.pageTitle,
        Journal.section,
        Journal.entryTitle,
        Journal.metadata,
      ]) {
        expect(style.fontFamily, Journal.displayFamily);
      }
    });

    test(
        'StudyAssistantTheme configures 5-state input borders and >=4.5:1 text contrast',
        () {
      for (final theme in [
        StudyAssistantTheme.light,
        StudyAssistantTheme.dark,
      ]) {
        final palette = _paletteFor(theme);
        final dec = theme.inputDecorationTheme;
        expect(dec.filled, isTrue);
        expect(dec.fillColor, palette.inputFill);
        expect((dec.enabledBorder as OutlineInputBorder).borderSide.color,
            palette.inputBorder);
        expect((dec.focusedBorder as OutlineInputBorder).borderSide.color,
            palette.accent);
        expect((dec.errorBorder as OutlineInputBorder).borderSide.color,
            palette.berry);
        expect((dec.focusedErrorBorder as OutlineInputBorder).borderSide.color,
            palette.berry);
        expect((dec.disabledBorder as OutlineInputBorder).borderSide.color,
            palette.inputBorderDisabled);
        expect(_contrastRatio(dec.hintStyle!.color!, palette.inputFill),
            greaterThanOrEqualTo(4.5));
        expect(_contrastRatio(dec.labelStyle!.color!, palette.inputFill),
            greaterThanOrEqualTo(4.5));
        expect(_contrastRatio(dec.errorStyle!.color!, palette.inputFill),
            greaterThanOrEqualTo(4.5));
      }
    });
  });

  group('M1 system overlay, de-blurred detail header & picker border', () {
    testWidgets(
        'AppShell wraps Scaffold with AnnotatedRegion<SystemUiOverlayStyle>',
        (tester) async {
      final store = AssignmentStore(
        sessionStore: SecureSessionStore(),
        notificationService: LocalNotificationService(),
        widgetSnapshotService: WidgetSnapshotService(),
      );
      addTearDown(store.dispose);
      for (final theme in [
        StudyAssistantTheme.light,
        StudyAssistantTheme.dark,
      ]) {
        final palette = _paletteFor(theme);
        final router = GoRouter(
          initialLocation: '/assignments',
          routes: [
            ShellRoute(
              builder: (_, __, child) =>
                  AppShell(assignmentStore: store, child: child),
              routes: [
                GoRoute(
                  path: '/assignments',
                  builder: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(
          key: ValueKey(palette.isDark),
          theme: theme,
          routerConfig: router,
        ));
        await tester.pumpAndSettle();
        final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find
              .ancestor(
                of: find.byType(Scaffold),
                matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
              )
              .first,
        );
        expect(region.value.statusBarColor, Colors.transparent);
        expect(region.value.systemNavigationBarColor, palette.paper);
        expect(
          region.value.statusBarIconBrightness,
          palette.isDark ? Brightness.light : Brightness.dark,
        );
      }
    });

    testWidgets(
        'JournalFloatingDetailHeader omits BackdropFilter and uses solid paper + divider',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
          body: JournalFloatingDetailHeader(
            title: '详情标题',
            scrollProgress: 1.0,
            onBack: () {},
          ),
        ),
      ));
      expect(find.byType(BackdropFilter), findsNothing);
      final boxes = tester.widgetList<DecoratedBox>(find.descendant(
        of: find.byType(JournalFloatingDetailHeader),
        matching: find.byType(DecoratedBox),
      ));
      final hasDividerBox = boxes.any((b) {
        final dec = b.decoration;
        return dec is BoxDecoration &&
            dec.color == JournalPalette.light.paper.withValues(alpha: 0.98) &&
            dec.border is Border;
      });
      expect(hasDividerBox, isTrue);
    });

    testWidgets(
        'JournalPickerSheet search input uses inputBorder instead of BorderSide.none',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showJournalPickerSheet<String>(
                  context,
                  title: '选择课程',
                  selectedValue: '',
                  searchable: true,
                  options: const [
                    JournalPickerOption(value: 'a', label: '高等数学'),
                  ],
                );
              },
              child: const Text('open-picker'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open-picker'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      final enabledBorder =
          field.decoration!.enabledBorder! as OutlineInputBorder;
      expect(enabledBorder.borderSide.style, BorderStyle.solid);
      expect(enabledBorder.borderSide.color, JournalPalette.light.inputBorder);
      expect(field.decoration!.fillColor, JournalPalette.light.inputFill);
    });
  });

  for (final theme in [StudyAssistantTheme.light, StudyAssistantTheme.dark]) {
    final label = theme.brightness.name;

    testWidgets('grouped card paints layered optical depth in $label',
        (tester) async {
      await _pumpCards(tester, theme);
      expect(tester.takeException(), isNull);

      final palette = _paletteFor(theme);
      for (final key in [_inkKey, _emphasizedKey]) {
        expect(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(BackdropFilter),
          ),
          findsNothing,
          reason: '$key must not introduce a backdrop blur',
        );
        expect(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(IntrinsicHeight),
          ),
          findsNothing,
          reason: '$key must not introduce intrinsic height passes',
        );

        final shadows = _cardDecoration(tester, key).boxShadow;
        expect(shadows, isNotNull);
        expect(shadows, hasLength(2), reason: '$key needs contact + ambient');
        final contact = shadows![0];
        expect(contact.color, palette.cardShadowContact);
        expect(contact.blurRadius, 3);
        expect(contact.spreadRadius, 0);
        expect(contact.offset, const Offset(0, 1));
        final ambient = shadows[1];
        expect(ambient.color, palette.cardShadowAmbient);
        expect(ambient.blurRadius, 14);
        expect(ambient.spreadRadius, -2);
        expect(ambient.offset, const Offset(0, 5));

        final paint = _cardPaint(tester, key);
        expect(paint.foregroundPainter, isNotNull,
            reason: '$key needs the top highlight / edge painter');
      }

      expect(_cardPaint(tester, _inkKey).painter, isNull);
      expect(_cardPaint(tester, _emphasizedKey).painter, isNotNull);

      final inkSide =
          (_cardMaterial(tester, _inkKey).shape! as RoundedRectangleBorder)
              .side;
      final emphasizedSide = (_cardMaterial(tester, _emphasizedKey).shape!
              as RoundedRectangleBorder)
          .side;
      expect(inkSide.color, palette.cardBorder);
      expect(emphasizedSide.color, palette.sageBorder);
      expect(inkSide.width, 0.8);
      expect(emphasizedSide.width, 0.8);
      expect(_cardMaterial(tester, _inkKey).color, palette.sheet);
      expect(_cardMaterial(tester, _emphasizedKey).color, palette.sheet);
    });

    testWidgets('emphasis keeps card geometry identical in $label',
        (tester) async {
      await _pumpCards(tester, theme);
      expect(tester.takeException(), isNull);
      final inkSize = tester.getSize(find.byKey(_inkKey));
      final emphasizedSize = tester.getSize(find.byKey(_emphasizedKey));
      expect(emphasizedSize.width, inkSize.width);
      expect(emphasizedSize.height, inkSize.height);
      // 2 x 44dp rows + a single 0.6dp divider: no optical layer may add height.
      expect(inkSize.height, closeTo(88.6, 0.01));
    });
  }
}

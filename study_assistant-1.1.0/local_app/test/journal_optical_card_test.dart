import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_grouped_card.dart';

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

void main() {
  group('JournalPalette optical tokens', () {
    test('light palette exposes the documented values', () {
      const palette = JournalPalette.light;
      expect(palette.ambientPrimaryGlow, const Color(0x0E5B749B));
      expect(palette.ambientWarmGlow, const Color(0x00000000));
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
    });

    test('dark palette exposes the documented values', () {
      const palette = JournalPalette.dark;
      expect(palette.ambientPrimaryGlow, const Color(0x0CEEDAC0));
      expect(palette.ambientWarmGlow, const Color(0x00000000));
      expect(palette.cardShadowContact, const Color(0x24000000));
      expect(palette.cardShadowAmbient, const Color(0x38000000));
      expect(palette.cardTopHighlight, const Color(0x18FFF8EB));
      expect(palette.cardEmphasisTintStart, const Color(0x1888A8F8));
      expect(palette.cardEmphasisTintEnd, const Color(0x0488A8F8));
      expect(palette.cardEmphasisBar, const Color(0xCC88A8F8));
      expect(palette.cardEmphasisBarGlow, const Color(0x3688A8F8));
      expect(palette.cardBorder, const Color(0x14FFF8EB));
      expect(palette.sageBorder, const Color(0xFF3D4C6E));
    });

    test('copyWith carries every optical token', () {
      final light = JournalPalette.light;
      const changed = Color(0xFF123456);
      final copy = light.copyWith(
        ambientPrimaryGlow: changed,
        ambientWarmGlow: changed,
        cardShadowContact: changed,
        cardShadowAmbient: changed,
        cardTopHighlight: changed,
        cardEmphasisTintStart: changed,
        cardEmphasisTintEnd: changed,
        cardEmphasisBar: changed,
        cardEmphasisBarGlow: changed,
      );
      expect(copy.ambientPrimaryGlow, changed);
      expect(copy.ambientWarmGlow, changed);
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

    test('equality and hashCode react to each optical token', () {
      final mutations = <String, JournalPalette Function()>{
        'ambientPrimaryGlow': () => JournalPalette.light
            .copyWith(ambientPrimaryGlow: const Color(0xFF000001)),
        'ambientWarmGlow': () => JournalPalette.light
            .copyWith(ambientWarmGlow: const Color(0xFF000002)),
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

    test('lerp interpolates every optical token', () {
      const light = JournalPalette.light;
      const dark = JournalPalette.dark;
      final mid = light.lerp(dark, 0.5);
      expect(mid.isDark, dark.isDark);
      expect(mid.ambientPrimaryGlow,
          Color.lerp(light.ambientPrimaryGlow, dark.ambientPrimaryGlow, 0.5));
      expect(mid.ambientWarmGlow,
          Color.lerp(light.ambientWarmGlow, dark.ambientWarmGlow, 0.5));
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

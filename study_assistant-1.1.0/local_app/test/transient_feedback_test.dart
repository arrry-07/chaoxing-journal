import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/transient_feedback.dart';

void main() {
  for (final replacePage in [false, true]) {
    testWidgets(
        'dispose with inactive scaffold is safe; replacement=$replacePage',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: _FeedbackPage(
              key: ValueKey('first'), message: 'departing page')));
      await tester.pumpAndSettle();
      expect(find.text('departing page'), findsOneWidget);
      await tester.pumpWidget(replacePage
          ? const MaterialApp(
              home: _FeedbackPage(
                  key: ValueKey('second'), message: 'replacement page'))
          : const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (replacePage) {
        expect(find.text('replacement page'), findsOneWidget,
            reason: 'deferred old cleanup cannot close the new owner');
      }
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
  testWidgets(
      'replaced controller dispose before closed microtask cannot close new owner',
      (tester) async {
    final first = TransientFeedbackController();
    final second = TransientFeedbackController();
    late BuildContext page;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) {
        page = context;
        return const SizedBox();
      },
    ))));
    first.show(page, const SnackBar(content: Text('owner A')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    second.show(page, const SnackBar(content: Text('owner B')));
    // Deliberately no pump/await: A.closed has not drained its microtasks.
    first.dispose();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('owner A'), findsNothing);
    expect(find.text('owner B'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('owner B'), findsOneWidget,
        reason: 'A timeout must not affect B');
    second.dispose();
    await tester.pumpAndSettle();
    expect(find.text('owner B'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('ordinary feedback expires at five seconds', (tester) async {
    final feedback = TransientFeedbackController();
    late BuildContext page;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) {
        page = context;
        return const SizedBox();
      },
    ))));
    feedback.show(page, const SnackBar(content: Text('first')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('first'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsNothing);
    feedback.dispose();
  });

  for (final accessible in [false, true]) {
    testWidgets('replacement action timeout and cleanup accessible=$accessible',
        (tester) async {
      final feedback = TransientFeedbackController();
      late BuildContext page;
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
        data: MediaQueryData(accessibleNavigation: accessible),
        child: Scaffold(body: Builder(builder: (context) {
          page = context;
          return const SizedBox();
        })),
      )));
      feedback.show(page, const SnackBar(content: Text('old')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      feedback.show(
          page,
          SnackBar(
              content: const Text('new'),
              action: SnackBarAction(label: '详情', onPressed: () {})));
      await tester.pumpAndSettle();
      expect(find.text('old'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('new'), findsOneWidget,
          reason: 'old timer must not close replacement');
      await tester.pump(Duration(seconds: accessible ? 28 : 10));
      await tester.pumpAndSettle();
      expect(find.text('new'), findsNothing);
      feedback.show(page, const SnackBar(content: Text('disposed')));
      await tester.pump();
      feedback.dispose();
      await tester.pumpAndSettle();
      expect(find.text('disposed'), findsNothing);
      await tester.pump(const Duration(seconds: 40));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('return banner replacement and unmount cancel old timers',
      (tester) async {
    var dismissed = 0;
    Widget banner(String text) => MaterialApp(
        home: Scaffold(
            body: TimedReturnCheck(
                key: ValueKey(text),
                message: text,
                onDismiss: () => dismissed++)));
    await tester.pumpWidget(banner('checking'));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(banner('checked'));
    await tester.pump(const Duration(seconds: 1));
    expect(dismissed, 0);
    await tester.pump(const Duration(seconds: 4));
    expect(dismissed, 1);
    await tester.pumpWidget(banner('leaving'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(dismissed, 1);
  });
}

class _FeedbackPage extends StatefulWidget {
  const _FeedbackPage({super.key, required this.message});
  final String message;
  @override
  State<_FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<_FeedbackPage> {
  final feedback = TransientFeedbackController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        feedback.show(context, SnackBar(content: Text(widget.message)));
      }
    });
  }

  @override
  void dispose() {
    feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('page content'));
}

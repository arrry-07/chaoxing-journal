import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/app/transient_feedback.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/calendar_screen.dart';
import 'package:study_assistant_mobile/src/features/login_screen.dart';
import 'package:study_assistant_mobile/src/features/stats_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_context_menu.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_swipe_tile.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

/// Regression net for the v1.8.25 Batch 1A UI stabilization items
/// (P0-06..P0-11, P1-29). Every case reproduces a defect seen in the
/// 1.8.24 audit and must stay green afterwards.

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

class _Session extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'student-1a';

  @override
  Future<String?> readChaoxingPassword() async => 'secret';

  @override
  Future<String?> readChaoxingDisplayName() async => '手记同学';

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _Store extends AssignmentStore {
  _Store({this.forceLoading = false})
      : super(
          sessionStore: SecureSessionStore(),
          notificationService: _Notifications(),
          widgetSnapshotService: _Snapshot(),
        );

  final bool forceLoading;

  @override
  bool get isLoading => forceLoading || super.isLoading;

  @override
  Future<bool> runDueAutoSync({DateTime? now}) async => false;
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Assignment _work(
  String id, {
  required String status,
  DateTime? due,
  String course = '数据结构与算法分析',
}) =>
    Assignment(
      id: 'cx:work:7:8:$id',
      courseName: course,
      title: '作业$id',
      deadlineAt: due,
      deadlineTrusted: due != null,
      requirementsText: '',
      status: status,
      lastSyncedAt: DateTime(2026, 11, 1),
    );

void _setView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _scaled(Widget child, {double scale = 1, ThemeData? theme}) =>
    MaterialApp(
      theme: theme ?? StudyAssistantTheme.light,
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: inner!,
      ),
      home: child,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('P0-06 login loading indicator', () {
    for (final mode in [
      (name: 'light', theme: StudyAssistantTheme.light),
      (name: 'dark', theme: StudyAssistantTheme.dark),
    ]) {
      testWidgets('spinner stays visible on the disabled fill (${mode.name})',
          (tester) async {
        final store = _Store(forceLoading: true);
        addTearDown(store.dispose);
        await tester.pumpWidget(MaterialApp(
          theme: mode.theme,
          home: LoginScreen(store: store),
        ));
        await tester.pump();

        final spinner = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        );
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.onPressed, isNull);
        final fill =
            button.style!.backgroundColor!.resolve({WidgetState.disabled})!;
        expect(
          _contrast(spinner.color!, fill),
          greaterThanOrEqualTo(3.0),
          reason: 'loading spinner must read against the disabled fill',
        );
      });
    }
  });

  group('P0-07 dark snackbar action contrast', () {
    test('theme action color is readable on the snackbar fill', () {
      for (final theme in [
        StudyAssistantTheme.light,
        StudyAssistantTheme.dark
      ]) {
        final snack = theme.snackBarTheme;
        expect(
          _contrast(snack.actionTextColor!, snack.backgroundColor!),
          greaterThanOrEqualTo(4.5),
          reason: '${theme.brightness} snackbar action contrast',
        );
      }
    });

    testWidgets('home undo action inherits the readable theme color',
        (tester) async {
      SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
      FlutterSecureStorage.setMockInitialValues({});
      final now = DateTime(2026, 11, 22, 10);
      final store = AssignmentStore(
        sessionStore: _Session(),
        notificationService: _Notifications(),
        widgetSnapshotService: _Snapshot(),
      );
      addTearDown(store.dispose);
      await store.restoreSession();
      await store.repository.mergeAndSave([
        _work('hide-me',
                status: 'pending', due: now.add(const Duration(days: 2)))
            .copyWith(
          submitUrl: 'https://mooc1.chaoxing.com/work/view?workid=hide-me',
        ),
      ]);
      await store.restoreSession();

      final theme = StudyAssistantTheme.dark;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          body: AssignmentListScreen(store: store, clock: () => now),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('作业hide-me'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('在本机隐藏'));
      await tester.pumpAndSettle();

      final action = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      final fg = action.textColor ?? theme.snackBarTheme.actionTextColor!;
      final bg = snack.backgroundColor ?? theme.snackBarTheme.backgroundColor!;
      expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5));
    });
  });

  group('P0-09 context menu placement', () {
    Future<void> openMenu(
      WidgetTester tester, {
      required Rect anchor,
      required double previewHeight,
      required double scale,
    }) async {
      final actions = [
        for (final label in ['在学习通打开', '置顶', '加入今日计划', '复制链接', '在本机隐藏'])
          JournalContextMenuAction(
            label: label,
            icon: Icons.circle_outlined,
            onSelected: () {},
          ),
      ];
      await tester.pumpWidget(_scaled(
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showJournalContextMenu(
                  context: context,
                  anchorRect: anchor,
                  previewCard: SizedBox(
                    key: const ValueKey('menu-preview'),
                    height: previewHeight,
                    child: const ColoredBox(color: Colors.white),
                  ),
                  actions: actions,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        scale: scale,
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    void expectMenuFits(WidgetTester tester, Size screen) {
      expect(tester.takeException(), isNull);
      final preview =
          tester.getRect(find.byKey(const ValueKey('menu-preview')));
      for (final label in ['在学习通打开', '置顶', '加入今日计划', '复制链接', '在本机隐藏']) {
        final finder = find.text(label);
        expect(finder, findsOneWidget, reason: label);
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(0), reason: '$label left');
        expect(rect.right, lessThanOrEqualTo(screen.width), reason: label);
        expect(rect.top, greaterThanOrEqualTo(0), reason: '$label top');
        expect(rect.bottom, lessThanOrEqualTo(screen.height), reason: label);
        expect(rect.overlaps(preview), isFalse,
            reason: '$label must not sit on the preview card');
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        expect(
          paragraph.getMaxIntrinsicHeight(paragraph.size.width),
          lessThanOrEqualTo(paragraph.size.height + 0.5),
          reason: '$label must not be vertically clipped',
        );
        final row = tester.getSize(find.ancestor(
          of: finder,
          matching: find.byType(InkWell),
        ));
        expect(row.height, greaterThanOrEqualTo(48), reason: '$label target');
      }
    }

    testWidgets('tall preview near the top does not cover the menu at 2.0x',
        (tester) async {
      const screen = Size(360, 640);
      _setView(tester, screen);
      await openMenu(
        tester,
        anchor: const Rect.fromLTWH(18, 100, 324, 260),
        previewHeight: 260,
        scale: 2.0,
      );
      expectMenuFits(tester, screen);
    });

    testWidgets('bottom anchor keeps every action on screen at 2.0x',
        (tester) async {
      const screen = Size(360, 640);
      _setView(tester, screen);
      await openMenu(
        tester,
        anchor: const Rect.fromLTWH(18, 560, 324, 72),
        previewHeight: 72,
        scale: 2.0,
      );
      expectMenuFits(tester, screen);
    });
  });

  group('P0-10 calendar month swipe', () {
    testWidgets('dragging a 5-row month toward a 6-row month never overflows',
        (tester) async {
      await initializeDateFormatting('zh_CN');
      _setView(tester, const Size(360, 780));
      final store = _Store();
      addTearDown(store.dispose);
      // April 2026 spans 5 week rows; May 2026 spans 6.
      final now = DateTime(2026, 4, 15, 10);
      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(body: CalendarScreen(store: store, clock: () => now)),
      ));
      await tester.pumpAndSettle();
      expect(find.text('2026年4月'), findsOneWidget);

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(PageView)));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(-30, 0));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'mid-drag step $i');
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('2026年5月'), findsOneWidget);

      final viewport = find.byKey(const ValueKey('calendar-grid-viewport'));
      final grid = tester.getRect(viewport);
      final lastDay = tester.getRect(find.descendant(
        of: viewport,
        matching: find.text('31'),
      ));
      expect(lastDay.bottom, lessThanOrEqualTo(grid.bottom + 0.5),
          reason: 'May 31 sits in the sixth row and must be fully visible');
    });
  });

  group('P0-11 stats course row at 360dp', () {
    testWidgets('three status pills never overflow or crush the course name',
        (tester) async {
      _setView(tester, const Size(360, 900));
      final now = DateTime(2026, 11, 22, 10);
      final store = _Store();
      addTearDown(store.dispose);
      store.replaceAssignmentsForTest([
        for (var i = 0; i < 12; i++)
          _work('p$i',
              status: 'pending', due: now.add(const Duration(days: 3))),
        for (var i = 0; i < 12; i++)
          _work('o$i',
              status: 'pending', due: now.subtract(const Duration(days: 3))),
        for (var i = 0; i < 12; i++) _work('u$i', status: 'unknown'),
      ]);
      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(body: StatsScreen(store: store, clock: () => now)),
      ));
      await tester.pumpAndSettle();

      final row = find.byKey(const ValueKey('stats-course-7:8'));
      await tester.scrollUntilVisible(row, 240,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in ['待完成 12', '已逾期 12', '未知 12']) {
        expect(find.descendant(of: row, matching: find.text(label)),
            findsOneWidget);
      }
      final name = tester.getSize(find.descendant(
        of: row,
        matching: find.text('数据结构与算法分析'),
      ));
      expect(name.width, greaterThanOrEqualTo(96),
          reason: 'course name keeps a readable width');
    });
  });

  group('P1-29 swipe tile', () {
    double foregroundOffset(WidgetTester tester) => tester
        .widget<Transform>(
            find.byKey(const ValueKey('journal-swipe-foreground')))
        .transform
        .getTranslation()
        .x;

    Widget tile({required bool withRight}) => MaterialApp(
          theme: StudyAssistantTheme.light,
          home: Scaffold(
            body: Center(
              child: JournalSwipeTile(
                rightAction: withRight
                    ? JournalSwipeAction(
                        label: '今日计划',
                        icon: Icons.add,
                        color: Colors.blue,
                        backgroundColor: Colors.white,
                        onTrigger: () {},
                      )
                    : null,
                leftAction: JournalSwipeAction(
                  label: '置顶',
                  icon: Icons.push_pin_outlined,
                  color: Colors.black,
                  backgroundColor: Colors.white,
                  onTrigger: () {},
                ),
                child: const SizedBox(
                  key: ValueKey('swipe-child'),
                  width: 320,
                  height: 72,
                  child: ColoredBox(color: Colors.white),
                ),
              ),
            ),
          ),
        );

    testWidgets('rubber band never pulls back while the finger moves forward',
        (tester) async {
      await tester.pumpWidget(tile(withRight: true));
      final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('swipe-child'))));
      await gesture.moveBy(const Offset(20, 0)); // win the drag arena
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      var previous = foregroundOffset(tester);
      expect(previous, greaterThan(72), reason: 'past the right threshold');
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(2, 0));
        await tester.pump();
        final current = foregroundOffset(tester);
        expect(current, greaterThanOrEqualTo(previous - 0.001),
            reason: 'step $i moved backwards');
        previous = current;
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(foregroundOffset(tester), closeTo(0, 0.5));
    });

    testWidgets('losing the active action mid-drag snaps the tile closed',
        (tester) async {
      await tester.pumpWidget(tile(withRight: true));
      final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('swipe-child'))));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(foregroundOffset(tester), greaterThan(20));

      // e.g. the assignment became completed and no longer offers "今日计划".
      await tester.pumpWidget(tile(withRight: false));
      await tester.pumpAndSettle();
      expect(foregroundOffset(tester), closeTo(0, 0.5));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Batch 1B.5 S5 & S10: feedback ownership and dark contrast guards', () {
    testWidgets(
        'S5: showJournalMessage revokes a disposing TransientFeedbackController owner',
        (tester) async {
      final controller = TransientFeedbackController();
      late BuildContext hostContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                hostContext = context;
                return const Text('host');
              },
            ),
          ),
        ),
      );

      controller.show(
        hostContext,
        const SnackBar(content: Text('旧页面提示')),
      );
      await tester.pump();
      expect(find.text('旧页面提示'), findsOneWidget);

      // Previous page disposes (scheduling post-frame removal) right before
      // the next page emits a one-off showJournalMessage on the same messenger.
      controller.dispose();
      showJournalMessage(hostContext, '新页面提示');
      await tester.pumpAndSettle();

      expect(find.text('新页面提示'), findsOneWidget,
          reason:
              'disposing controller post-frame cleanup must not kill showJournalMessage');
    });

    testWidgets(
        'S10: LoginScreen unchecked agreement checkbox stays high contrast in light and dark themes',
        (tester) async {
      for (final mode in [
        (name: 'light', theme: StudyAssistantTheme.light),
        (name: 'dark', theme: StudyAssistantTheme.dark),
      ]) {
        final store = _Store();
        addTearDown(store.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: mode.theme,
            home: LoginScreen(store: store),
          ),
        );
        await tester.pumpAndSettle();

        final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
        final journal = mode.theme.extension<JournalPalette>()!;
        final borderColor = checkbox.side?.color ??
            mode.theme.checkboxTheme.side?.color ??
            journal.ruleStrong;
        expect(
          _contrast(borderColor, journal.sheet),
          greaterThanOrEqualTo(3.0),
          reason:
              'unchecked login checkbox outline must remain >= 3:1 in ${mode.name}',
        );
      }
    });

    testWidgets(
        'S10: AssignmentCard overdue title uses isDark rather than identity equality with JournalPalette.dark',
        (tester) async {
      final derivedDark = JournalPalette.dark.copyWith(
        paper: const Color(0xFF1A1917),
      );
      final darkTheme = StudyAssistantTheme.dark.copyWith(
        extensions: [derivedDark],
      );
      final now = DateTime(2026, 11, 22, 10);
      final overdueItem = _work(
        'overdue-card',
        status: 'pending',
        due: now.subtract(const Duration(days: 2)),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: Scaffold(
            body: AssignmentCard(
              assignment: overdueItem,
              now: now,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final titleText = tester.widget<Text>(find.text('作业overdue-card'));
      final color = titleText.style!.color!;
      expect(
        _contrast(color, derivedDark.sheet),
        greaterThanOrEqualTo(4.5),
        reason:
            'overdue card title on interpolated/copied dark palette must stay readable (>= 4.5:1)',
      );
    });
  });
}

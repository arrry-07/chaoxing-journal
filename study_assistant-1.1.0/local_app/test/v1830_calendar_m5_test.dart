import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/calendar_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _TestSession extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'student-cal-m5';

  @override
  Future<String?> readChaoxingPassword() async => 'secret';

  @override
  Future<String?> readChaoxingDisplayName() async => '测试同学';

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _NoopNotifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}

  @override
  Future<void> rescheduleManual(List<ManualEntry> entries) async {}

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}

  @override
  Future<void> rescheduleSummary(
    List<Assignment> items,
    PersonalWorkspace personal,
    DateTime? lastSync,
  ) async {}
}

class _NoopWidgetSnapshot extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

List<Color> _dotColors(WidgetTester tester, int day) {
  final row = find.byKey(ValueKey('calendar-dots-$day'));
  final dots = find.descendant(of: row, matching: find.byType(Container));
  return tester
      .widgetList<Container>(dots)
      .map((c) => (c.decoration! as BoxDecoration).color!)
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('zh_CN'));

  testWidgets(
      'M5: calendar removes red busy cell fill, colors typed dots without berry on overdue, shows + overflow & legend across themes and 320dp@2x',
      (tester) async {
    final now = DateTime.utc(2026, 11, 18, 2, 0); // 10:00 Beijing Nov 18
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    for (final dark in [false, true]) {
      SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
      FlutterSecureStorage.setMockInitialValues({});
      final store = AssignmentStore(
        sessionStore: _TestSession(),
        notificationService: _NoopNotifications(),
        widgetSnapshotService: _NoopWidgetSnapshot(),
        clock: () => now,
      );
      addTearDown(store.dispose);
      await store.restoreSession();
      await store.repository.mergeAndSave([
        // Day 10: overdue homework -> dot MUST remain accent blue, never berry red
        Assignment(
          id: 'cx:work:1:1:overdue',
          courseName: '软件工程',
          title: '逾期作业',
          deadlineAt: DateTime.utc(2026, 11, 10, 6, 0),
          deadlineTrusted: true,
          requirementsText: '',
          status: 'pending',
          lastSyncedAt: now,
        ),
        // Day 20: 1 homework + 1 official exam
        Assignment(
          id: 'cx:work:1:1:d20w',
          courseName: '操作系统',
          title: '实验报告',
          deadlineAt: DateTime.utc(2026, 11, 20, 6, 0),
          deadlineTrusted: true,
          requirementsText: '',
          status: 'pending',
          lastSyncedAt: now,
        ),
        Assignment(
          id: 'cx:exam:1:1:d20e',
          source: AssignmentSource.exam,
          courseName: '操作系统',
          title: '期中考试',
          deadlineAt: null,
          requirementsText: '',
          status: 'unknown',
          exam: ExamInfo(
            examId: 'd20e',
            courseId: '1',
            clazzId: '1',
            startAt: DateTime.utc(2026, 11, 20, 2, 0),
            endAt: DateTime.utc(2026, 11, 20, 4, 0),
            startTrusted: true,
            endTrusted: true,
            lifecycle: 'scheduled',
          ),
          lastSyncedAt: now,
        ),
        // Day 22: 3 homeworks + 1 exam (4 events + 1 manual todo = 5 events -> 3 typed dots + '+')
        for (var i = 1; i <= 3; i++)
          Assignment(
            id: 'cx:work:1:1:d22w$i',
            courseName: '编译原理',
            title: '作业$i',
            deadlineAt: DateTime.utc(2026, 11, 22, 6, 0),
            deadlineTrusted: true,
            requirementsText: '',
            status: 'pending',
            lastSyncedAt: now,
          ),
        Assignment(
          id: 'cx:exam:1:1:d22e',
          source: AssignmentSource.exam,
          courseName: '编译原理',
          title: '随堂考试',
          deadlineAt: null,
          requirementsText: '',
          status: 'unknown',
          exam: ExamInfo(
            examId: 'd22e',
            courseId: '1',
            clazzId: '1',
            startAt: DateTime.utc(2026, 11, 22, 3, 0),
            endAt: DateTime.utc(2026, 11, 22, 4, 0),
            startTrusted: true,
            endTrusted: true,
            lifecycle: 'scheduled',
          ),
          lastSyncedAt: now,
        ),
      ]);
      await store.restoreSession();
      // Add manual todo on Day 20 and Day 22 + manual exam on Day 24
      await store.saveNotebook(
        (_) => StudyNotebook(entries: [
          ManualEntry(
            id: 'm-d20-todo',
            kind: ManualEntry.kindTodo,
            title: '个人复习待办',
            at: DateTime.utc(2026, 11, 20, 10, 0),
          ),
          ManualEntry(
            id: 'm-d22-todo',
            kind: ManualEntry.kindTodo,
            title: '高密日待办',
            at: DateTime.utc(2026, 11, 22, 10, 0),
          ),
          ManualEntry(
            id: 'm-d24-exam',
            kind: ManualEntry.kindExam,
            title: '手动模拟考试',
            at: DateTime.utc(2026, 11, 24, 2, 0),
          ),
        ]),
        store.accountEpoch,
      );

      final palette = dark ? JournalPalette.dark : JournalPalette.light;

      await tester.pumpWidget(MaterialApp(
        theme: dark ? StudyAssistantTheme.dark : StudyAssistantTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: Scaffold(
          body: CalendarScreen(
            key: ValueKey('cal-$dark'),
            store: store,
            clock: () => now,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'dark=$dark');

      // Legend present below grid
      final legend = find.byKey(const ValueKey('calendar-dot-legend'));
      expect(legend, findsOneWidget);
      expect(find.descendant(of: legend, matching: find.text('作业')),
          findsOneWidget);
      expect(find.descendant(of: legend, matching: find.text('考试')),
          findsOneWidget);
      expect(find.descendant(of: legend, matching: find.text('待办')),
          findsOneWidget);

      // Day 10 overdue homework dot is accent, not berry
      expect(_dotColors(tester, 10), [palette.accent]);
      expect(find.byKey(const ValueKey('calendar-dots-overflow-10')),
          findsNothing);

      // Day 20: 1 homework, 1 exam, 1 todo = 3 distinct colors, no '+'
      expect(_dotColors(tester, 20),
          [palette.accent, palette.examOrange, palette.todoGreen]);
      expect(find.byKey(const ValueKey('calendar-dots-overflow-20')),
          findsNothing);

      // Day 22: 3 homeworks + 1 exam + 1 todo -> guarantees 1 dot per active category + '+'
      expect(_dotColors(tester, 22),
          [palette.accent, palette.examOrange, palette.todoGreen]);
      expect(find.byKey(const ValueKey('calendar-dots-overflow-22')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-busy-day-2026-11-22')),
          findsNothing);

      // Day 24: manual exam uses examOrange
      expect(_dotColors(tester, 24), [palette.examOrange]);

      // Today (day 18) selected initially: sage fill + sageBorder + bold accent text
      final todayCell = find.byKey(const ValueKey('calendar-day-2026-11-18'));
      final todayCircle = tester.widget<AnimatedContainer>(find.descendant(
        of: todayCell,
        matching: find.byType(AnimatedContainer),
      ));
      final todayDeco = todayCircle.decoration! as BoxDecoration;
      expect(todayDeco.color, palette.sage);
      expect((todayDeco.border as Border).top.color, palette.sageBorder);
      final todayText = tester.widget<Text>(
          find.descendant(of: todayCell, matching: find.text('18')));
      expect(todayText.style?.color, palette.accent);
      expect(todayText.style?.fontWeight, FontWeight.w700);

      // Tap day 20: today (18) becomes transparent (no border) with accent bold; day 20 becomes sage fill with ink bold
      final day20TextFinder = find.descendant(
        of: find.byKey(const ValueKey('calendar-day-2026-11-20')),
        matching: find.text('20'),
      );
      await tester.tap(day20TextFinder);
      await tester.pumpAndSettle();

      final todayAfter = tester.widget<AnimatedContainer>(find.descendant(
        of: todayCell,
        matching: find.byType(AnimatedContainer),
      ));
      final todayAfterDeco = todayAfter.decoration! as BoxDecoration;
      expect(todayAfterDeco.color, Colors.transparent);
      expect(todayAfterDeco.border, isNull);

      final day20After = tester.widget<AnimatedContainer>(find.descendant(
        of: find.byKey(const ValueKey('calendar-day-2026-11-20')),
        matching: find.byType(AnimatedContainer),
      ));
      final day20Deco = day20After.decoration! as BoxDecoration;
      expect(day20Deco.color, palette.sage);
      expect((day20Deco.border as Border).top.color, palette.sageBorder);
    }
  });
}

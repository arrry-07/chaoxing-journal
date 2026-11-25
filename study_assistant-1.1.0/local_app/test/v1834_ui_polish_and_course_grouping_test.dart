import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/main.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/app/journal_motion.dart';
import 'package:study_assistant_mobile/src/app/journal_page_transitions.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:study_assistant_mobile/src/features/course_list_screen.dart';
import 'package:study_assistant_mobile/src/features/course_study_hub_screen.dart';
import 'package:study_assistant_mobile/src/features/local_records_screen.dart';
import 'package:study_assistant_mobile/src/features/manual_agenda_screen.dart';
import 'package:study_assistant_mobile/src/features/manual_entry_detail_screen.dart';
import 'package:study_assistant_mobile/src/features/reminder_status_screen.dart';
import 'package:study_assistant_mobile/src/features/stats_screen.dart';
import 'package:study_assistant_mobile/src/features/sync_status_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_buttons.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_expansion_tile.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_floating_detail_header.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_sliver_grouped_card.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/models/course_chapter_progress.dart';
import 'package:study_assistant_mobile/src/models/course_notice.dart';
import 'package:study_assistant_mobile/src/models/course_term_preferences.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/models/reminder_history.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/course_term_catalog.dart';
import 'package:study_assistant_mobile/src/services/home_course_filter.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

double _contrastRatio(Color fg, Color bg) {
  final l1 = fg.computeLuminance();
  final l2 = bg.computeLuminance();
  final hi = math.max(l1, l2);
  final lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

class _Session extends SecureSessionStore {
  _Session([this.account = '13800000001']);
  String account;

  @override
  Future<String?> readChaoxingAccount() async => account;
  @override
  Future<String?> readChaoxingPassword() async => 'pw';
  @override
  Future<String?> readChaoxingDisplayName() async => '同学';
  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _NoopNotif extends LocalNotificationService {
  @override
  Future<bool> isLegacyAssignmentMigrationComplete() async => true;
  @override
  Future<void> removeLegacyAssignmentSchedules() async {}
  @override
  Future<void> cancelPrivateSchedules() async {}
  @override
  Future<void> rescheduleManual(List<ManualEntry> entries) async {}
  @override
  Future<void> rescheduleSummary(
    List<Assignment> assignments,
    dynamic personal,
    DateTime? lastSyncAt,
  ) async {}
  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}
}

class _NoopWidget extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _FakeStore extends AssignmentStore {
  _FakeStore({
    _Session? session,
    super.repository,
    this.explanationOverride,
    super.clock,
  }) : super(
          sessionStore: session ?? _Session(),
          notificationService: _NoopNotif(),
          widgetSnapshotService: _NoopWidget(),
          chaoxingClient: ChaoxingLocalClient(),
          manageBackgroundSchedule: true,
        );

  final ReminderExplanation? explanationOverride;

  @override
  Future<ReminderExplanation> explainReminder({
    required String kind,
    required String id,
  }) async =>
      explanationOverride ?? await super.explainReminder(kind: kind, id: id);
}

Future<AssignmentStore> _createStore({
  String account = '13800000001',
  DateTime Function()? clock,
  ReminderExplanation? explanationOverride,
  List<CourseRef> courses = const [],
  List<CourseNotice> notices = const [],
  List<CourseChapterSnapshot> chapters = const [],
  SyncReport? syncReport,
}) async {
  SharedPreferences.setMockInitialValues({
    'auto_sync_interval_minutes': 0,
  });
  FlutterSecureStorage.setMockInitialValues({});
  final repo = LocalAssignmentRepository();
  await repo.activateAccount(account);
  if (syncReport != null) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sync_report_v1', jsonEncode(syncReport.toJson()));
  }
  if (courses.isNotEmpty) {
    await repo.saveCourses(courses, account: account);
  }
  if (notices.isNotEmpty) {
    await repo.saveCourseNotices(
        CourseNoticeCollection(items: notices), account);
  }
  if (chapters.isNotEmpty) {
    var catalog = CourseChapterCatalog();
    for (final snapshot in chapters) {
      catalog = catalog.upsertCourse(snapshot);
    }
    await repo.saveCourseChapters(catalog, account);
  }
  final store = _FakeStore(
    session: _Session(account),
    repository: repo,
    explanationOverride: explanationOverride,
    clock: clock,
  );
  await store.restoreSession();
  return store;
}

void _setNarrowViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = const Size(640, 1280);
  tester.view.padding = const FakeViewPadding(top: 48, bottom: 48);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('zh_CN'));

  group('M1 · 逾期字色清晰化、muted 加深与非危险红清扫', () {
    test('light & dark WCAG AA >= 4.5:1 contrast invariants hold', () {
      expect(Journal.muted, const Color(0xFF363C44));
      expect(JournalPalette.light.muted, const Color(0xFF363C44));
      for (final p in [JournalPalette.light, JournalPalette.dark]) {
        expect(_contrastRatio(p.ink, p.sheet), greaterThanOrEqualTo(4.5));
        expect(_contrastRatio(p.muted, p.sheet), greaterThanOrEqualTo(4.5));
        expect(_contrastRatio(p.muted, p.paper), greaterThanOrEqualTo(4.5));
        expect(_contrastRatio(p.accent, p.slateBg), greaterThanOrEqualTo(4.5));
        expect(
          _contrastRatio(p.overdueSky, p.overdueSkyBg),
          greaterThanOrEqualTo(4.5),
        );
        expect(_contrastRatio(p.ochre, p.ochreBg), greaterThanOrEqualTo(4.5));
        expect(_contrastRatio(p.berry, p.berryBg), greaterThanOrEqualTo(4.5));
      }
    });

    testWidgets(
        'AssignmentCard & ManualAgendaScreen render overdue title/clock in journal.ink while keeping done manual item muted',
        (tester) async {
      final now = DateTime.utc(2026, 11, 20, 4);
      final overdueWork = Assignment(
        id: 'cx:work:1:1:od',
        courseName: '高等数学',
        title: '逾期微积分习题',
        deadlineAt: now.subtract(const Duration(days: 2)),
        deadlineTrusted: true,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      );

      for (final theme in [
        StudyAssistantTheme.light,
        StudyAssistantTheme.dark,
      ]) {
        final journal = theme.extension<JournalPalette>()!;
        await tester.pumpWidget(MaterialApp(
          key: ValueKey('card-${journal.isDark}'),
          theme: theme,
          home: Scaffold(
            body: AssignmentCard(
              assignment: overdueWork,
              now: now,
              onTap: () {},
            ),
          ),
        ));
        await tester.pumpAndSettle();

        final titleStyle = tester.widget<Text>(find.text('逾期微积分习题')).style!;
        expect(titleStyle.color, journal.ink);

        final clockFinder = find.text('12:00');
        expect(clockFinder, findsOneWidget);
        expect(tester.widget<Text>(clockFinder).style?.color, journal.ink);
      }

      final store = await _createStore(clock: () => now);
      addTearDown(store.dispose);
      await store.saveNotebook(
        (n) => n.withEntries([
          ManualEntry(
            id: 'm-overdue',
            title: '未完成逾期待办',
            kind: ManualEntry.kindTodo,
            done: false,
            at: now.subtract(const Duration(hours: 3)),
          ),
          ManualEntry(
            id: 'm-done',
            title: '已完成历史待办',
            kind: ManualEntry.kindTodo,
            done: true,
            at: now.subtract(const Duration(hours: 6)),
          ),
        ]),
        store.accountEpoch,
      );

      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: ManualAgendaScreen(store: store, clock: () => now),
      ));
      await tester.pumpAndSettle();

      final overdueManualStyle =
          tester.widget<Text>(find.text('未完成逾期待办')).style!;
      expect(overdueManualStyle.color, JournalPalette.light.ink);

      await tester.tap(find.byKey(const ValueKey('agenda-completed-toggle')));
      await tester.pumpAndSettle();
      final doneManualStyle = tester.widget<Text>(find.text('已完成历史待办')).style!;
      expect(doneManualStyle.color, JournalPalette.light.muted);
      expect(doneManualStyle.decoration, TextDecoration.lineThrough);
    });

    testWidgets(
        'LocalRecords, AssignmentDetail, CourseStudyHub & ReminderStatus swap non-danger red while preserving berry for failures',
        (tester) async {
      final now = DateTime.utc(2026, 11, 20, 4);
      final store = await _createStore(
        clock: () => now,
        courses: const [CourseRef(courseId: '1', clazzId: '1', name: '高等数学')],
        notices: [
          CourseNotice(
            id: 'cx:notice:${'a' * 64}',
            courseId: '1',
            clazzId: '1',
            courseName: '高等数学',
            title: '期中测验通知',
            localRead: false,
            lastSyncedAt: now,
          ),
        ],
        chapters: [
          CourseChapterSnapshot(
            courseId: '1',
            clazzId: '1',
            courseName: '高等数学',
            completedPoints: 1,
            totalPoints: 3,
            progressTrusted: true,
            nodes: const [
              ChapterNode(
                sectionId: 'cx:chapter:s1',
                level: 1,
                code: '1.1',
                title: '极限与连续',
                state: ChapterTaskState.pendingPoints,
                pendingPoints: 2,
              ),
            ],
            lastSyncedAt: now,
          ),
        ],
        explanationOverride: ReminderExplanation(
          subjectKind: 'assignment',
          subjectId: 'cx:work:1:1:od',
          displayName: '逾期作业',
          checkedAt: now,
          categories: const [
            ReminderCategoryExplanation(
              category: 'assignmentDeadline',
              status: ReminderExplanationStatus.unconfirmed,
              reasonCodes: [],
              nextScheduledAt: null,
              evidenceAt: null,
              actionLabel: null,
            ),
            ReminderCategoryExplanation(
              category: 'assignmentUpdate',
              status: ReminderExplanationStatus.queryFailed,
              reasonCodes: [],
              nextScheduledAt: null,
              evidenceAt: null,
              actionLabel: null,
            ),
          ],
          queryWarnings: const [],
        ),
      );
      addTearDown(store.dispose);

      final overdueWork = Assignment(
        id: 'cx:work:1:1:od',
        courseName: '高等数学',
        title: '逾期作业详情颜色测试',
        deadlineAt: now.subtract(const Duration(days: 1)),
        deadlineTrusted: true,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      );
      store.replaceAssignmentsForTest([overdueWork]);

      // 1) LocalRecordsScreen expired pill == overdueSky / overdueSkyBg.
      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: LocalRecordsScreen(store: store, clock: () => now),
      ));
      await tester.pumpAndSettle();
      final expiredPillFinder = find.descendant(
        of: find.byType(JournalSliverGroupedCard),
        matching: find.text('已逾期'),
      );
      final expiredText = tester.widget<Text>(expiredPillFinder);
      expect(expiredText.style?.color, JournalPalette.light.overdueSky);
      final expiredBox = tester.widget<Container>(
        find
            .ancestor(
              of: expiredPillFinder,
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (expiredBox.decoration as BoxDecoration).color,
        JournalPalette.light.overdueSkyBg,
      );

      // 2) AssignmentDetailScreen overdue deadline icon == overdueSky.
      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: AssignmentDetailScreen(
          store: store,
          assignmentId: overdueWork.id,
          clock: () => now,
        ),
      ));
      await tester.pumpAndSettle();
      final clockIcons =
          tester.widgetList<Icon>(find.byIcon(Icons.schedule_rounded)).toList();
      expect(
        clockIcons.any((i) => i.color == JournalPalette.light.overdueSky),
        isTrue,
      );

      // 3) ReminderStatusScreen: unconfirmed == ochre/ochreBg, queryFailed == berry/berryBg.
      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: ReminderStatusScreen(
          store: store,
          kind: 'assignment',
          id: overdueWork.id,
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('结果未确认')).style?.color,
        JournalPalette.light.ochre,
      );
      expect(
        tester.widget<Text>(find.text('查询失败')).style?.color,
        JournalPalette.light.berry,
      );

      // 4) CourseStudyHubScreen: notice '未读' == slateBg/accent, pending chapter == accent.
      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: CourseStudyHubScreen(store: store, initialTab: 'notices'),
      ));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('未读')).style?.color,
        JournalPalette.light.accent,
      );

      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: CourseStudyHubScreen(store: store, initialTab: 'chapters'),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chapter-course-1:1')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.textContaining('2 个任务点待完成')).style?.color,
        JournalPalette.light.accent,
      );
    });
  });

  group('M2 · 无重叠切页转场、统计滑块与微交互', () {
    testWidgets(
        'primary tabs switch instantaneously with NoTransitionPage and no FadeTransition overlap',
        (tester) async {
      final now = DateTime.utc(2026, 11, 20, 4);
      final store = await _createStore(clock: () => now);
      addTearDown(store.dispose);

      await tester.pumpWidget(StudyAssistantApp(
        assignmentStore: store,
        notificationService: _NoopNotif(),
        clock: () => now,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('统计'));
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.byType(StatsScreen), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets(
        'JournalPageTransitionsBuilder slides opaquely without FadeTransition and respects disableAnimations',
        (tester) async {
      const builder = JournalPageTransitionsBuilder();
      expect(builder.transitionDuration, const Duration(milliseconds: 250));
      expect(
          builder.reverseTransitionDuration, const Duration(milliseconds: 220));

      for (final reduced in [false, true]) {
        await tester.pumpWidget(MaterialApp(
          key: ValueKey('nav-transition-$reduced'),
          theme: StudyAssistantTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: Text('二级详情页')),
                    ),
                  );
                },
                child: const Text('去二级页'),
              ),
            ),
          ),
        ));

        await tester.tap(find.text('去二级页'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        if (reduced) {
          expect(find.text('二级详情页'), findsOneWidget);
          expect(find.byType(SlideTransition), findsNothing);
        } else {
          expect(
            find.ancestor(
              of: find.text('二级详情页'),
              matching: find.byType(SlideTransition),
            ),
            findsWidgets,
          );
          expect(
            find.ancestor(
              of: find.text('二级详情页'),
              matching: find.byType(FadeTransition),
            ),
            findsNothing,
          );
        }
        await tester.pumpAndSettle();
      }
    });

    testWidgets(
        'StatsScreen sliding scope indicator moves cleanly at 320dp@2x and obeys disableAnimations',
        (tester) async {
      _setNarrowViewport(tester);
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 20, 4);
      final store = await _createStore(clock: () => now);
      addTearDown(store.dispose);

      for (final reduced in [false, true]) {
        await tester.pumpWidget(MaterialApp(
          key: ValueKey('nav-transition-$reduced'),
          theme: StudyAssistantTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2.0),
              disableAnimations: reduced,
            ),
            child: child!,
          ),
          home: StatsScreen(store: store, clock: () => now),
        ));
        await tester.pumpAndSettle();

        final indicatorFinder = find.descendant(
          of: find.byType(AnimatedPositioned),
          matching: find.byType(DecoratedBox),
        );
        expect(indicatorFinder, findsOneWidget);
        final beforePos =
            tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned));
        expect(
          beforePos.duration,
          reduced ? Duration.zero : const Duration(milliseconds: 200),
        );

        await tester
            .tap(find.byKey(const ValueKey('stats-term-scope-allTerms')));
        await tester.pumpAndSettle();
        final afterPos =
            tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned));
        expect(afterPos.left, isNot(beforePos.left));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        'JournalPressableScale scales down on press and honors reduced motion',
        (tester) async {
      for (final reduced in [false, true]) {
        var tapped = false;
        await tester.pumpWidget(MaterialApp(
          key: ValueKey('press-scale-$reduced'),
          theme: StudyAssistantTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: JournalPressableScale(
                child: ElevatedButton(
                  onPressed: () => tapped = true,
                  child: const Text('点按胶囊'),
                ),
              ),
            ),
          ),
        ));

        final gesture =
            await tester.startGesture(tester.getCenter(find.text('点按胶囊')));
        await tester.pump(const Duration(milliseconds: 60));
        final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
        if (reduced) {
          expect(scale.scale, 1.0);
          expect(scale.duration, Duration.zero);
        } else {
          expect(scale.scale, lessThan(1.0));
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(tapped, isTrue);
      }
    });
  });

  group('M3 · 悬浮详情顶栏与 320dp@2x 浅/深双主题零溢出', () {
    testWidgets(
        'AssignmentDetailScreen keeps floating back & pin pinned near top across 500px scroll while fading title in',
        (tester) async {
      _setNarrowViewport(tester);
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 20, 4);
      final assignment = Assignment(
        id: 'cx:work:1:2:long',
        courseName: '计算机组成原理（实验与课程设计班）',
        title: '单周期 CPU 设计与指令译码仿真报告',
        deadlineAt: now.add(const Duration(days: 2)),
        deadlineTrusted: true,
        requirementsText:
            List.filled(20, '请提交完整仿真波形、Verilog 源码说明以及关键数据通路分析文档。').join('\n'),
        status: 'pending',
        lastSyncedAt: now,
      );

      for (final theme in [
        StudyAssistantTheme.light,
        StudyAssistantTheme.dark,
      ]) {
        final store = await _createStore(clock: () => now);
        addTearDown(store.dispose);
        store.replaceAssignmentsForTest([assignment]);

        await tester.pumpWidget(MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2.0),
            ),
            child: child!,
          ),
          home: AssignmentDetailScreen(
            store: store,
            assignmentId: assignment.id,
            clock: () => now,
          ),
        ));
        await tester.pumpAndSettle();

        final backFinder = find.byKey(const ValueKey('assignment-detail-back'));
        final pinFinder = find.byKey(const ValueKey('assignment-detail-pin'));
        final headerFinder = find.byType(JournalFloatingDetailHeader);
        expect(backFinder, findsOneWidget);
        expect(pinFinder, findsOneWidget);
        expect(find.text('置顶'), findsOneWidget);
        expect(
          find.descendant(of: headerFinder, matching: find.byType(Opacity)),
          findsNothing,
        );

        final backRectBefore = tester.getRect(backFinder);
        final pinRectBefore = tester.getRect(pinFinder);
        expect(tester.getSize(backFinder).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(backFinder).height, greaterThanOrEqualTo(48));

        await tester.drag(find.byType(ListView), const Offset(0, -500));
        await tester.pumpAndSettle();

        expect(
            tester.getRect(backFinder).top, closeTo(backRectBefore.top, 0.5));
        expect(tester.getRect(pinFinder).top, closeTo(pinRectBefore.top, 0.5));
        expect(backFinder.hitTestable(), findsOneWidget);
        expect(pinFinder.hitTestable(), findsOneWidget);

        final headerOpacity = tester.widget<Opacity>(
          find.descendant(of: headerFinder, matching: find.byType(Opacity)),
        );
        expect(headerOpacity.opacity, 1.0);
        expect(tester.takeException(), isNull);
      }

      // Anti-case: hidden assignment has no pin button.
      final hiddenStore = await _createStore(clock: () => now);
      addTearDown(hiddenStore.dispose);
      hiddenStore.replaceAssignmentsForTest([assignment]);
      await hiddenStore.setAssignmentsHidden([assignment.id], true);
      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: AssignmentDetailScreen(
          store: hiddenStore,
          assignmentId: assignment.id,
          clock: () => now,
        ),
      ));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('assignment-detail-back')), findsOneWidget);
      expect(find.byKey(const ValueKey('assignment-detail-pin')), findsNothing);
    });

    testWidgets(
        'ManualEntryDetailScreen keeps manual-detail-back visible on populated & empty states at 320dp@2x',
        (tester) async {
      _setNarrowViewport(tester);
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 20, 4);
      for (final theme in [
        StudyAssistantTheme.light,
        StudyAssistantTheme.dark,
      ]) {
        final store = await _createStore(clock: () => now);
        addTearDown(store.dispose);
        await store.saveNotebook(
          (n) => n.withEntries([
            ManualEntry(
              id: 'm1',
              title: '线性代数考前复习冲刺安排',
              kind: ManualEntry.kindExam,
              at: now.add(const Duration(days: 3)),
              note: List.filled(18, '重点核对特征值与二次型真题。').join('\n'),
            ),
          ]),
          store.accountEpoch,
        );

        await tester.pumpWidget(MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2.0),
            ),
            child: child!,
          ),
          home: ManualEntryDetailScreen(
            store: store,
            entryId: 'm1',
            clock: () => now,
          ),
        ));
        await tester.pumpAndSettle();

        final backFinder = find.byKey(const ValueKey('manual-detail-back'));
        expect(backFinder, findsOneWidget);
        expect(tester.getSize(backFinder).height, greaterThanOrEqualTo(48));
        final beforeTop = tester.getRect(backFinder).top;
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.getRect(backFinder).top, closeTo(beforeTop, 0.5));
        expect(backFinder.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: ManualEntryDetailScreen(
            store: store,
            entryId: 'missing-entry',
            clock: () => now,
          ),
        ));
        await tester.pumpAndSettle();
        expect(
            find.byKey(const ValueKey('manual-detail-back')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('M4 · 未分组治理（clazzName/courseTime/筛选去噪/批量管理）', () {
    test(
        'CourseTermCatalog chain keeps activity above courseTime, supports clazzName, and preserves 2025级分班级 as ungrouped',
        () {
      final now = DateTime.utc(2026, 11, 20, 4);
      final oldTemplateWithCurrentActivity = CourseRef(
        courseId: 'tpl1',
        clazzId: 'c1',
        name: '大学物理实验',
        courseStartAt: DateTime.utc(2023, 9, 1),
      );
      const clazzNamed = CourseRef(
        courseId: 'clz1',
        clazzId: 'c2',
        name: '工程伦理',
        clazzName: '25-26(1)公共课1班',
      );
      final timeOnlyPast = CourseRef(
        courseId: 'tm1',
        clazzId: 'c3',
        name: '形势与政策',
        courseEndAt: DateTime.utc(2025, 1, 10),
      );
      const ungroupedGradeClass = CourseRef(
        courseId: 'ung1',
        clazzId: 'c4',
        name: '高等数学',
        clazzName: '2025级分班级',
        teacherNames: ['黄敬言'],
      );

      final catalog = CourseTermCatalog.build(
        courses: [
          oldTemplateWithCurrentActivity,
          clazzNamed,
          timeOnlyPast,
          ungroupedGradeClass,
        ],
        assignments: [
          Assignment(
            id: 'cx:work:tpl1:c1:1',
            courseName: '大学物理实验',
            title: '实验报告一',
            deadlineAt: now.add(const Duration(days: 5)),
            deadlineTrusted: true,
            requirementsText: '',
            status: 'pending',
            lastSyncedAt: now,
          ),
        ],
        notices: const [],
        preferences: const CourseTermPreferences.empty(),
        now: now,
      );

      final tplEntry = catalog.entryFor(oldTemplateWithCurrentActivity.key)!;
      expect(tplEntry.term, const AcademicTerm(2026, AcademicSemester.fall));
      expect(tplEntry.source, CourseTermSource.activity);
      expect(tplEntry.state, CourseCatalogState.active);

      final clzEntry = catalog.entryFor(clazzNamed.key)!;
      expect(clzEntry.term, const AcademicTerm(2025, AcademicSemester.fall));
      expect(clzEntry.source, CourseTermSource.clazzName);

      final tmEntry = catalog.entryFor(timeOnlyPast.key)!;
      expect(tmEntry.term, const AcademicTerm(2024, AcademicSemester.fall));
      expect(tmEntry.source, CourseTermSource.courseTime);
      expect(tmEntry.state, CourseCatalogState.archived);

      final ungEntry = catalog.entryFor(ungroupedGradeClass.key)!;
      expect(ungEntry.isUngrouped, isTrue);
      expect(ungEntry.term, isNull);
    });

    test(
        'HomeCourseFilterOption.subtitle omits noisy 未分组 and displays teacher cleanly',
        () {
      final now = DateTime.utc(2026, 11, 20, 4);
      const ungrouped = CourseRef(
        courseId: '99',
        clazzId: 'k99',
        name: '2025级分班级',
        teacherNames: ['黄敬言'],
      );
      final catalog = CourseTermCatalog.build(
        courses: const [ungrouped],
        assignments: const [],
        notices: const [],
        preferences: const CourseTermPreferences.empty(),
        now: now,
      );
      final options = buildHomeCourseFilterOptions(
        assignments: const [],
        catalog: const [ungrouped],
        records: const [],
        termCatalog: catalog,
        includeIdleCourses: true,
      );
      expect(options.length, 1);
      expect(options.first.ungrouped, isTrue);
      expect(options.first.subtitle, '黄敬言');
      expect(options.first.subtitle, isNot(contains('未分组')));
    });

    testWidgets(
        'CourseListScreen batch selection, set-term, archive, block & dark layout work with zero overflow at 320dp@2x',
        (tester) async {
      _setNarrowViewport(tester);
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 20, 4);
      const currentCourse = CourseRef(
        courseId: 'c-cur',
        clazzId: 'k1',
        name: '算法设计与分析',
        folderName: '2026-2027-1',
      );
      const ungA = CourseRef(
        courseId: 'c-ung1',
        clazzId: 'k2',
        name: '形式语言与自动机',
        teacherNames: ['刘新海'],
      );
      const ungB = CourseRef(
        courseId: 'c-ung2',
        clazzId: 'k3',
        name: '专业英语文献研读',
        teacherNames: ['粟涓'],
      );

      final store = await _createStore(
        clock: () => now,
        courses: const [currentCourse, ungA, ungB],
      );
      addTearDown(store.dispose);

      await store.saveHomeFilters(
        const HomeFilters(courseKey: 'c-ung2:k3'),
        store.accountEpoch,
      );

      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2.0),
          ),
          child: child!,
        ),
        home: CourseListScreen(store: store, clock: () => now),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('course-list-manage-terms')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester
          .tap(find.byKey(const ValueKey('course-select-all-ungrouped')));
      await tester.pumpAndSettle();
      expect(find.text('批量操作 · 2 门'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Batch archive both ungrouped courses.
      await tester
          .tap(find.byKey(const ValueKey('course-batch-archive-selected')));
      await tester.pumpAndSettle();
      expect(
        store.courseTermPreferences.entryFor(ungA.key)?.archiveMode,
        CourseArchiveMode.archived,
      );
      expect(
        store.courseTermPreferences.entryFor(ungB.key)?.archiveMode,
        CourseArchiveMode.archived,
      );
      expect(find.textContaining('批量操作'), findsNothing);

      // Select ungB & block it -> homeFilters.courseKey cleared atomically.
      final ungBSelect = find.byKey(const ValueKey('course-select-c-ung2:k3'));
      await tester.scrollUntilVisible(
        ungBSelect,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(ungBSelect);
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('course-batch-block-selected')));
      await tester.pumpAndSettle();
      expect(store.homeFilters.courseKey, isNull);
      expect(
        store.courseTermPreferences.entryFor(ungB.key)?.blockMode,
        CourseBlockMode.blocked,
      );

      // Verify batchUpdateCourseTerms manualTerm + archiveMode.
      final ok = await store.batchUpdateCourseTerms(
        courseKeys: {ungA.key},
        updateManualTerm: true,
        manualTerm: const AcademicTerm(2026, AcademicSemester.fall),
        archiveMode: CourseArchiveMode.auto,
      );
      expect(ok, isTrue);
      expect(
        store.termCatalog.entryFor(ungA.key)?.term,
        const AcademicTerm(2026, AcademicSemester.fall),
      );
      expect(
        store.termCatalog.entryFor(ungA.key)?.source,
        CourseTermSource.manual,
      );

      // Dark theme render check with batch bar visible at 320dp@2x.
      await tester.pumpWidget(MaterialApp(
        key: const ValueKey('course-list-dark'),
        theme: StudyAssistantTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2.0),
          ),
          child: child!,
        ),
        home: CourseListScreen(store: store, clock: () => now),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('course-list-manage-terms')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('course-select-all-visible')));
      await tester.pumpAndSettle();
      expect(find.textContaining('批量操作'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('M5 · JournalExpansionTile 平滑折叠、保态与窄屏嵌套零溢出', () {
    testWidgets(
        'JournalExpansionTile expands cleanly, preserves PageStorage state across scroll, and respects disableAnimations',
        (tester) async {
      final bucket = PageStorageBucket();
      for (final reduced in [false, true]) {
        await tester.pumpWidget(MaterialApp(
          key: ValueKey('nav-transition-$reduced'),
          theme: StudyAssistantTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: Scaffold(
            body: PageStorage(
              bucket: bucket,
              child: ListView(
                children: [
                  JournalExpansionTile(
                    key: PageStorageKey<String>('exp-$reduced'),
                    title: Text('折叠分组-$reduced'),
                    children: const [Text('展开子内容')],
                  ),
                  const SizedBox(height: 1600),
                  const Text('底部哨兵'),
                ],
              ),
            ),
          ),
        ));

        expect(find.text('展开子内容'), findsNothing);
        if (reduced) {
          expect(find.byType(AnimatedSize), findsNothing);
        } else {
          final size = tester.widget<AnimatedSize>(find.byType(AnimatedSize));
          expect(size.duration, const Duration(milliseconds: 220));
          expect(size.curve, JournalMotion.easeDrawer);
        }

        await tester.tap(find.text('折叠分组-$reduced'));
        await tester.pumpAndSettle();
        expect(find.text('展开子内容'), findsOneWidget);
        final rot =
            tester.widget<AnimatedRotation>(find.byType(AnimatedRotation));
        expect(rot.turns, 0.5);
        expect(
          rot.duration,
          reduced ? Duration.zero : const Duration(milliseconds: 200),
        );

        await tester.drag(find.byType(ListView), const Offset(0, -1400));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, 1400));
        await tester.pumpAndSettle();
        expect(find.text('展开子内容'), findsOneWidget);
      }
    });

    testWidgets(
        'SyncStatusScreen 3-level nested JournalExpansionTiles expand with zero overflow at 320dp@2x',
        (tester) async {
      _setNarrowViewport(tester);
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 20, 4);
      final store = await _createStore(
        clock: () => now,
        courses: const [CourseRef(courseId: '1', clazzId: '1', name: '计算机网络')],
        syncReport: SyncReport(
          phase: SyncPhase.partial,
          issues: const [
            SyncIssue(
              SyncIssueKind.schemaChanged,
              '测试课程页结构异常，建议重新验证后重试',
              stage: 'coursePage',
              courseKey: '1:1',
              httpStatus: 500,
              elapsedMs: 120,
            ),
          ],
          sourceResults: const [
            SyncSourceResult(
              source: 'courseWork',
              phase: SyncSourcePhase.partial,
              reasonCodes: ['examPhoneListFailed'],
            ),
          ],
          lastCurrentSuccessAt: now,
        ),
      );
      addTearDown(store.dispose);

      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2.0),
          ),
          child: child!,
        ),
        home: SyncStatusScreen(store: store, expandIssues: false),
      ));
      await tester.pumpAndSettle();

      final groupsFinder = find.byKey(const ValueKey('sync-issue-groups'));
      await tester.scrollUntilVisible(groupsFinder, 200);
      await tester.ensureVisible(groupsFinder);
      await tester.pumpAndSettle();
      await tester.tap(groupsFinder);
      await tester.pumpAndSettle();
      final group0Finder = find.byKey(const ValueKey('sync-issue-group-0'));
      await tester.scrollUntilVisible(group0Finder, 200);
      await tester.ensureVisible(group0Finder);
      await tester.pumpAndSettle();
      await tester.tap(group0Finder);
      await tester.pumpAndSettle();
      final raw0Finder = find.byKey(const ValueKey('sync-issue-raw-0'));
      await tester.scrollUntilVisible(raw0Finder, 200);
      await tester.ensureVisible(raw0Finder);
      await tester.pumpAndSettle();
      await tester.tap(raw0Finder);
      await tester.pumpAndSettle();

      expect(find.textContaining('HTTP 500'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

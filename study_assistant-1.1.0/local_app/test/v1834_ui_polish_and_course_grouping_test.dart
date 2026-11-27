import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
import 'package:study_assistant_mobile/src/services/daily_summary.dart';
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
  String? account;

  @override
  Future<String?> readChaoxingAccount() async => account;
  @override
  Future<String?> readChaoxingPassword() async => account == null ? null : 'pw';
  @override
  Future<String?> readChaoxingDisplayName() async => '同学';
  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
  @override
  Future<void> saveChaoxingAccount({
    required String account,
    required String password,
    String? displayName,
    String? avatarUrl,
  }) async {
    this.account = account;
  }

  @override
  Future<void> clearWebSession() async {}

  @override
  Future<void> clear() async {
    account = null;
  }
}

class _SwitchableClient extends ChaoxingLocalClient {
  @override
  bool get needsSessionInitialization => false;

  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async =>
      ChaoxingLoginResult(success: true, displayName: '用户-$account');

  @override
  Future<List<Assignment>> fetchAssignments() async => const [];
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
  @override
  Future<ReminderHealth> inspectHealth() async => const ReminderHealth(
        notifications: true,
        assignmentChannel: ReminderChannelHealth(ReminderChannelStatus.enabled),
        manualChannel: ReminderChannelHealth(ReminderChannelStatus.enabled),
        summaryChannel: ReminderChannelHealth(ReminderChannelStatus.enabled),
        scheduleRecoveryPending: false,
      );
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
    ChaoxingLocalClient? chaoxingClient,
    super.clock,
  }) : super(
          sessionStore: session ?? _Session(),
          notificationService: _NoopNotif(),
          widgetSnapshotService: _NoopWidget(),
          chaoxingClient: chaoxingClient ?? ChaoxingLocalClient(),
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

class _FailingFollowStore extends _FakeStore {
  _FailingFollowStore({
    super.session,
    super.repository,
    super.chaoxingClient,
    super.clock,
  });

  bool failFollowCourse = false;

  @override
  Future<void> followCourse(String key, bool followed) async {
    if (failFollowCourse) return;
    await super.followCourse(key, followed);
  }
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
        'JournalPageTransitionsBuilder handles Android predictive back commit, cancel, and route guards',
        (tester) async {
      Future<bool> sendStartBackGesture({
        double progress = 0.0,
        int swipeEdge = 0,
        bool isButtonEvent = false,
      }) async {
        bool handled = false;
        final msg = const StandardMethodCodec().encodeMethodCall(
          MethodCall('startBackGesture', <String, dynamic>{
            'touchOffset': <double>[5.0, 300.0],
            'progress': progress,
            'swipeEdge': swipeEdge,
            if (isButtonEvent) 'isButtonEvent': true,
          }),
        );
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          SystemChannels.backGesture.name,
          msg,
          (ByteData? reply) {
            if (reply != null) {
              handled =
                  const StandardMethodCodec().decodeEnvelope(reply) == true;
            }
          },
        );
        return handled;
      }

      Future<void> sendUpdateBackGesture(double progress) async {
        final msg = const StandardMethodCodec().encodeMethodCall(
          MethodCall('updateBackGestureProgress', <String, dynamic>{
            'touchOffset': <double>[120.0, 310.0],
            'progress': progress,
            'swipeEdge': 0,
          }),
        );
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          SystemChannels.backGesture.name,
          msg,
          (_) {},
        );
      }

      Future<void> sendBackAction(String method) async {
        final msg = const StandardMethodCodec().encodeMethodCall(
          MethodCall(method),
        );
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          SystemChannels.backGesture.name,
          msg,
          (_) {},
        );
      }

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        var canPopThird = false;
        var reducedMotion = false;
        late StateSetter setHostState;

        await tester.pumpWidget(StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return MaterialApp(
              theme: StudyAssistantTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(disableAnimations: reducedMotion),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Column(
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const Scaffold(
                                body: Text('预测性返回目标页'),
                              ),
                            ),
                          );
                        },
                        child: const Text('去目标页'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => StatefulBuilder(
                                builder: (ctx, _) => PopScope(
                                  canPop: canPopThird,
                                  child: const Scaffold(
                                    body: Text('禁止手势返回页'),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        child: const Text('去禁返页'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ));
        await tester.pumpAndSettle();

        // 1) Root route cannot be popped via predictive back.
        expect(await sendStartBackGesture(), isFalse);

        // 2) Push second page -> cancel branch keeps route active and restores parallax host.
        await tester.tap(find.text('去目标页'));
        await tester.pumpAndSettle();
        expect(find.text('预测性返回目标页'), findsOneWidget);

        expect(await sendStartBackGesture(), isTrue);
        await tester.pump();
        await sendUpdateBackGesture(0.35);
        await tester.pump();
        expect(
          find.ancestor(
            of: find.text('预测性返回目标页'),
            matching: find.byType(Transform),
          ),
          findsWidgets,
        );
        expect(
          find.ancestor(
            of: find.text('预测性返回目标页'),
            matching: find.byType(FadeTransition),
          ),
          findsNothing,
        );

        await sendBackAction('cancelBackGesture');
        await tester.pumpAndSettle();
        expect(find.text('预测性返回目标页'), findsOneWidget);

        // 3) Commit branch pops route back to root.
        expect(await sendStartBackGesture(), isTrue);
        await tester.pump();
        await sendUpdateBackGesture(0.45);
        await tester.pump();
        await sendBackAction('commitBackGesture');
        await tester.pumpAndSettle();
        expect(find.text('预测性返回目标页'), findsNothing);
        expect(find.text('去目标页'), findsOneWidget);

        // 4) Non-poppable route (PopScope canPop: false) and disableAnimations reject predictive gesture.
        await tester.tap(find.text('去禁返页'));
        await tester.pumpAndSettle();
        expect(await sendStartBackGesture(), isFalse);

        // With disableAnimations: true, even a poppable route declines predictive back.
        canPopThird = true;
        reducedMotion = true;
        setHostState(() {});
        await tester.pumpAndSettle();
        expect(await sendStartBackGesture(), isFalse);

        // Re-enable animations and verify clean pop.
        reducedMotion = false;
        setHostState(() {});
        await tester.pumpAndSettle();
        expect(await sendStartBackGesture(), isTrue);
        await tester.pump();
        await sendUpdateBackGesture(0.5);
        await tester.pump();
        await sendBackAction('commitBackGesture');
        await tester.pumpAndSettle();
        expect(find.text('去目标页'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
        'JournalPageTransitionsBuilder declines predictive back inside nested ShellRoute when root dialog is open, preserves right-edge cancel sign, and recovers vetoed async commit',
        (tester) async {
      Future<bool> sendStartBackGesture({
        double progress = 0.0,
        int swipeEdge = 0,
      }) async {
        var handled = false;
        final msg = const StandardMethodCodec().encodeMethodCall(
          MethodCall('startBackGesture', <String, dynamic>{
            'touchOffset': <double>[swipeEdge == 1 ? 395.0 : 5.0, 300.0],
            'progress': progress,
            'swipeEdge': swipeEdge,
          }),
        );
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          SystemChannels.backGesture.name,
          msg,
          (ByteData? reply) {
            if (reply != null) {
              handled =
                  const StandardMethodCodec().decodeEnvelope(reply) == true;
            }
          },
        );
        return handled;
      }

      Future<void> sendUpdateBackGesture(
        double progress, {
        int swipeEdge = 0,
      }) async {
        final msg = const StandardMethodCodec().encodeMethodCall(
          MethodCall('updateBackGestureProgress', <String, dynamic>{
            'touchOffset': <double>[swipeEdge == 1 ? 260.0 : 120.0, 310.0],
            'progress': progress,
            'swipeEdge': swipeEdge,
          }),
        );
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          SystemChannels.backGesture.name,
          msg,
          (_) {},
        );
      }

      Future<void> sendBackAction(String method) async {
        final msg = const StandardMethodCodec().encodeMethodCall(
          MethodCall(method),
        );
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          SystemChannels.backGesture.name,
          msg,
          (_) {},
        );
      }

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        // 1) Nested Navigator (ShellRoute) + root Dialog: predictive back must decline so root dialog handles pop.
        final nestedKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(MaterialApp(
          theme: StudyAssistantTheme.light,
          home: Navigator(
            key: nestedKey,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (innerCtx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(innerCtx).push(
                      MaterialPageRoute<void>(
                        builder: (secCtx) => Scaffold(
                          body: Column(
                            children: [
                              const Text('嵌套二级页'),
                              ElevatedButton(
                                onPressed: () {
                                  showDialog<void>(
                                    context: secCtx,
                                    useRootNavigator: true,
                                    builder: (_) => const AlertDialog(
                                      title: Text('根导航弹窗'),
                                    ),
                                  );
                                },
                                child: const Text('打开根弹窗'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('进入嵌套二级页'),
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.text('进入嵌套二级页'));
        await tester.pumpAndSettle();
        expect(find.text('嵌套二级页'), findsOneWidget);

        // Without dialog, nested secondary page accepts right-edge predictive back and keeps negative dx on cancel.
        expect(await sendStartBackGesture(swipeEdge: 1), isTrue);
        await tester.pump();
        await sendUpdateBackGesture(0.4, swipeEdge: 1);
        await tester.pump();
        await sendBackAction('cancelBackGesture');
        await tester.pump(const Duration(milliseconds: 16));
        final translates = tester
            .widgetList<Transform>(
              find.ancestor(
                of: find.text('嵌套二级页'),
                matching: find.byType(Transform),
              ),
            )
            .map((t) => t.transform.getTranslation().x)
            .where((dx) => dx != 0.0)
            .toList();
        expect(translates, isNotEmpty);
        expect(translates.every((dx) => dx < 0.0), isTrue);
        await tester.pumpAndSettle();
        expect(find.text('嵌套二级页'), findsOneWidget);

        // Open root-navigator dialog above nested secondary page -> predictive back MUST return false.
        await tester.tap(find.text('打开根弹窗'));
        await tester.pumpAndSettle();
        expect(find.text('根导航弹窗'), findsOneWidget);
        expect(await sendStartBackGesture(), isFalse);
        expect(find.text('根导航弹窗'), findsOneWidget);
        expect(find.text('嵌套二级页'), findsOneWidget);

        // 2) Vetoed commit via real GoRouter async onExit returning false: animation recovers cleanly to 1.0.
        ModalRoute<dynamic>? vetoedRoute;
        final router = GoRouter(
          initialLocation: '/home',
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, _) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => context.push('/veto'),
                  child: const Text('去异步拦截页'),
                ),
              ),
            ),
            GoRoute(
              path: '/veto',
              onExit: (_, __) async => false,
              builder: (context, _) {
                vetoedRoute = ModalRoute.of(context);
                return const Scaffold(body: Text('异步拦截页'));
              },
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(
          theme: StudyAssistantTheme.light,
          routerConfig: router,
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.text('去异步拦截页'));
        await tester.pumpAndSettle();
        expect(find.text('异步拦截页'), findsOneWidget);

        expect(await sendStartBackGesture(), isTrue);
        await tester.pump();
        await sendUpdateBackGesture(0.45);
        await tester.pump();
        expect(vetoedRoute!.animation!.value, lessThan(0.9));

        await sendBackAction('commitBackGesture');
        await tester.pumpAndSettle();
        expect(find.text('异步拦截页'), findsOneWidget);
        expect(vetoedRoute!.animation!.value, closeTo(1.0, 0.001));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test(
        'deadline_channel_v3_auto_migrated_v1 is account-scoped so secondary legacy accounts still migrate to v3',
        () async {
      SharedPreferences.setMockInitialValues({
        'auto_sync_interval_minutes': 0,
      });
      FlutterSecureStorage.setMockInitialValues({});
      final repo = LocalAssignmentRepository();
      final prefs = await SharedPreferences.getInstance();

      // Seed legacy Account B archived with v1 deadline channel, then switch to Account A.
      await repo.activateAccount('student-b');
      await repo.writeDeadlineChannelIdInPrefs(
        prefs,
        LocalNotificationService.assignmentChannel,
      );
      await repo.activateAccount('student-a');

      final session = _Session('student-a');
      final storeA = _FakeStore(session: session, repository: repo);
      addTearDown(storeA.dispose);
      await storeA.restoreSession();
      expect(
        storeA.activeDeadlineChannelId,
        LocalNotificationService.assignmentV3Channel,
      );
      expect(
        prefs.getBool(
            LocalAssignmentRepository.deadlineChannelV3AutoMigratedKey),
        isTrue,
      );

      // Switching back to Account B must isolate the marker and migrate B from v1 -> v3.
      final storeB = _FakeStore(
        session: _Session('student-b'),
        repository: repo,
      );
      addTearDown(storeB.dispose);
      await storeB.restoreSession();
      expect(
        storeB.activeDeadlineChannelId,
        LocalNotificationService.assignmentV3Channel,
      );
      expect(
        await repo.loadDeadlineChannelId('student-b'),
        LocalNotificationService.assignmentV3Channel,
      );
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

        final indicatorFinder =
            find.byKey(const ValueKey('stats-term-scope-indicator'));
        expect(indicatorFinder, findsOneWidget);
        final beforeLeft = tester.getTopLeft(indicatorFinder).dx;

        await tester
            .tap(find.byKey(const ValueKey('stats-term-scope-allTerms')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        final midLeft = tester.getTopLeft(indicatorFinder).dx;
        expect(midLeft, greaterThan(beforeLeft));
        await tester.pumpAndSettle();
        final afterLeft = tester.getTopLeft(indicatorFinder).dx;
        expect(afterLeft, greaterThan(beforeLeft));
        if (reduced) {
          expect(midLeft, closeTo(afterLeft, 0.01));
        } else {
          expect(midLeft, lessThan(afterLeft));
        }
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

        double currentScale() {
          final transform = tester.widget<Transform>(
            find
                .descendant(
                  of: find.byType(JournalPressableScale),
                  matching: find.byType(Transform),
                )
                .first,
          );
          return transform.transform.storage[0];
        }

        expect(currentScale(), 1.0);
        final gesture =
            await tester.startGesture(tester.getCenter(find.text('点按胶囊')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        if (reduced) {
          expect(currentScale(), 1.0);
        } else {
          expect(currentScale(), lessThan(1.0));
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(currentScale(), 1.0);
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
      expect(tmEntry.term, isNull);
      expect(tmEntry.source, CourseTermSource.ungrouped);
      expect(tmEntry.state, CourseCatalogState.active);

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

    testWidgets(
        'CourseListScreen keeps select-all visible on disjoint search subset and aborts batch term write across accountEpoch change',
        (tester) async {
      final now = DateTime.utc(2026, 11, 20, 4);
      const courseA = CourseRef(
        courseId: 'c-a',
        clazzId: 'k1',
        name: '编译原理',
      );
      const courseB = CourseRef(
        courseId: 'c-b',
        clazzId: 'k2',
        name: '操作系统',
      );
      const courseC = CourseRef(
        courseId: 'c-c',
        clazzId: 'k3',
        name: '线性代数',
      );

      final session = _Session('13800000001');
      SharedPreferences.setMockInitialValues({
        'auto_sync_interval_minutes': 0,
      });
      FlutterSecureStorage.setMockInitialValues({});
      final repo = LocalAssignmentRepository();
      await repo.activateAccount('13800000001');
      await repo.saveCourses(
        const [courseA, courseB, courseC],
        account: '13800000001',
      );
      await repo.activateAccount('13800000002');
      await repo.saveCourses(
        const [courseA, courseB, courseC],
        account: '13800000002',
      );
      await repo.activateAccount('13800000001');
      final store = _FakeStore(
        session: session,
        repository: repo,
        chaoxingClient: _SwitchableClient(),
        clock: () => now,
      );
      await store.restoreSession();
      addTearDown(store.dispose);

      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: CourseListScreen(store: store, clock: () => now),
      ));
      await tester.pumpAndSettle();

      // Enter manage mode, select 2 courses (courseA, courseB).
      await tester.tap(find.byKey(const ValueKey('course-list-manage-terms')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('course-select-c-a:k1')));
      await tester.tap(find.byKey(const ValueKey('course-select-c-b:k2')));
      await tester.pumpAndSettle();

      // Search for a smaller disjoint subset (only courseC, 1 unselected item < 2 selected).
      await tester.tap(find.byKey(const ValueKey('course-list-search-toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('course-list-search')),
        '线性代数',
      );
      await tester.pumpAndSettle();

      final selectAllFinder =
          find.byKey(const ValueKey('course-select-all-visible'));
      expect(selectAllFinder, findsOneWidget);
      await tester.tap(selectAllFinder);
      await tester.pumpAndSettle();
      expect(selectAllFinder, findsNothing);

      // Clear search and test accountEpoch guard in _pickBatchManualTerm.
      await tester.tap(find.byKey(const ValueKey('course-list-search-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('course-clear-selection')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('course-select-c-a:k1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('course-batch-set-term')));
      await tester.pumpAndSettle();
      expect(find.text('自动推断（清除手动设置）'), findsOneWidget);

      // Switch account while picker sheet is open -> accountEpoch changes.
      await store.loginChaoxing(
        account: '13800000002',
        password: 'pw',
        agreementAccepted: true,
      );
      await tester.pumpAndSettle();

      // Selecting a term now must NOT mutate the new account's term preferences.
      final fallOption = find.byKey(const ValueKey('term-option-2026-fall'));
      expect(fallOption, findsOneWidget);
      await tester.tap(fallOption);
      await tester.pumpAndSettle();

      expect(store.account, '13800000002');
      expect(store.courseTermPreferences.entryFor(courseA.key), isNull);
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

        Transform chevronTransform() => tester.widget<Transform>(
              find
                  .ancestor(
                    of: find.byIcon(Icons.expand_more_rounded),
                    matching: find.byType(Transform),
                  )
                  .first,
            );

        expect(chevronTransform().transform.storage[0], closeTo(1.0, 1e-3));

        await tester.tap(find.text('折叠分组-$reduced'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        if (reduced) {
          expect(
            chevronTransform().transform.storage[0],
            closeTo(-1.0, 1e-3),
          );
        } else {
          expect(
            chevronTransform().transform.storage[0],
            greaterThan(-1.0),
          );
        }
        await tester.pumpAndSettle();
        expect(find.text('展开子内容'), findsOneWidget);
        expect(chevronTransform().transform.storage[0], closeTo(-1.0, 1e-3));
        expect(chevronTransform().transform.storage[1], closeTo(0.0, 1e-3));

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

    testWidgets(
        'JournalExpansionTile persists PageStorageKey state without leaking plain ValueKey tiles into PageStorageBucket',
        (tester) async {
      final bucket = PageStorageBucket();

      // 1) Mount two tiles: one with ancestor PageStorageKey, one with plain ValueKey only.
      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
          body: PageStorage(
            bucket: bucket,
            child: ListView(
              children: const [
                KeyedSubtree(
                  key: PageStorageKey<String>('persisted-course-1'),
                  child: JournalExpansionTile(
                    key: ValueKey('persisted-row-1'),
                    title: Text('带 PageStorageKey 分组'),
                    children: [Text('保态子内容')],
                  ),
                ),
                JournalExpansionTile(
                  key: ValueKey('plain-detail-row'),
                  title: Text('仅 ValueKey 折叠项'),
                  children: [Text('临时子内容')],
                ),
              ],
            ),
          ),
        ),
      ));

      await tester.tap(find.text('带 PageStorageKey 分组'));
      await tester.tap(find.text('仅 ValueKey 折叠项'));
      await tester.pumpAndSettle();
      expect(find.text('保态子内容'), findsOneWidget);
      expect(find.text('临时子内容'), findsOneWidget);

      // 2) Unmount the page completely (simulating tab switch / object change) and
      // remount fresh widget instances under the same PageStorageBucket:
      // PageStorageKey tile must restore expanded; plain ValueKey tile must start collapsed.
      await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        theme: StudyAssistantTheme.light,
        home: Scaffold(
          body: PageStorage(
            bucket: bucket,
            child: ListView(
              key: UniqueKey(),
              children: const [
                KeyedSubtree(
                  key: PageStorageKey<String>('persisted-course-1'),
                  child: JournalExpansionTile(
                    key: ValueKey('persisted-row-1'),
                    title: Text('带 PageStorageKey 分组'),
                    children: [Text('保态子内容')],
                  ),
                ),
                JournalExpansionTile(
                  key: ValueKey('plain-detail-row'),
                  title: Text('仅 ValueKey 折叠项'),
                  children: [Text('临时子内容')],
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final plainCtx =
          tester.element(find.byKey(const ValueKey('plain-detail-row')));
      expect(bucket.readState(plainCtx), isNull);
      expect(
        bucket.readState(plainCtx,
            identifier: const ValueKey('plain-detail-row')),
        isNull,
      );
      expect(find.text('保态子内容'), findsOneWidget);
      expect(find.text('临时子内容'), findsNothing);
    });

    testWidgets(
        'CourseListScreen search field uses inputBorder and SwitchListTile toggle supports epoch-guarded undo',
        (tester) async {
      final now = DateTime.utc(2026, 11, 20, 4);
      final session = _Session('13800000001');
      SharedPreferences.setMockInitialValues({
        'auto_sync_interval_minutes': 0,
      });
      FlutterSecureStorage.setMockInitialValues({});
      const course = CourseRef(
        courseId: '101',
        clazzId: '10',
        name: '数据结构与算法',
        folderName: '2026年秋',
      );
      final repo = LocalAssignmentRepository();
      await repo.activateAccount('13800000001');
      await repo.saveCourses(const [course], account: '13800000001');
      await repo.activateAccount('13800000002');
      await repo.saveCourses(const [course], account: '13800000002');
      await repo.activateAccount('13800000001');
      final store = _FakeStore(
        session: session,
        repository: repo,
        chaoxingClient: _SwitchableClient(),
        clock: () => now,
      );
      await store.restoreSession();
      addTearDown(store.dispose);

      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: CourseListScreen(store: store, clock: () => now),
      ));
      await tester.pumpAndSettle();

      // Search field uses global inputFill & inputBorder (1.0dp, not BorderSide.none).
      await tester.tap(find.byKey(const ValueKey('course-list-search-toggle')));
      await tester.pumpAndSettle();
      final searchField = tester.widget<TextField>(
        find.byKey(const ValueKey('course-list-search')),
      );
      final deco = searchField.decoration!;
      expect(deco.fillColor, JournalPalette.light.inputFill);
      final enabledBorder = deco.enabledBorder! as OutlineInputBorder;
      expect(enabledBorder.borderSide.color, JournalPalette.light.inputBorder);
      expect(enabledBorder.borderSide.width, 1.0);

      // Toggle follow off -> snackbar shows scope explanation + 撤销.
      expect(store.follows('101:10'), isTrue);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(store.follows('101:10'), isFalse);
      expect(
        find.text('已取消关注《数据结构与算法》，将从首页、日历、提醒、小组件与统计中隐藏'),
        findsOneWidget,
      );
      final undoBtn = find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('撤销'),
      );
      expect(undoBtn, findsOneWidget);

      await tester.tap(undoBtn);
      await tester.pumpAndSettle();
      expect(store.follows('101:10'), isTrue);

      // Toggle off again, verify re-follow copy after manual follow, then verify account switch dismisses stale undo.
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(store.follows('101:10'), isFalse);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(store.follows('101:10'), isTrue);
      expect(
        find.text('已关注《数据结构与算法》，将恢复纳入首页、日历、提醒与统计'),
        findsOneWidget,
      );

      // Account switch while snackbar is visible dismisses stale undo bar cleanly.
      await store.loginChaoxing(
        account: '13800000002',
        password: 'pw',
        agreementAccepted: true,
      );
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets(
        'CourseListScreen shows error without undo when follow toggle or undo persistence fails',
        (tester) async {
      final now = DateTime.utc(2026, 11, 20, 4);
      final session = _Session('13800000001');
      SharedPreferences.setMockInitialValues({
        'auto_sync_interval_minutes': 0,
      });
      FlutterSecureStorage.setMockInitialValues({});
      const course = CourseRef(
        courseId: '101',
        clazzId: '10',
        name: '数据结构与算法',
        folderName: '2026年秋',
      );
      final repo = LocalAssignmentRepository();
      await repo.activateAccount('13800000001');
      await repo.saveCourses(const [course], account: '13800000001');
      final store = _FailingFollowStore(
        session: session,
        repository: repo,
        chaoxingClient: _SwitchableClient(),
        clock: () => now,
      );
      await store.restoreSession();
      addTearDown(store.dispose);

      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: CourseListScreen(store: store, clock: () => now),
      ));
      await tester.pumpAndSettle();

      // 1) Initial toggle persistence fails -> shows failure message and no 撤销 button.
      store.failFollowCourse = true;
      expect(store.follows('101:10'), isTrue);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(store.follows('101:10'), isTrue);
      expect(
        find.text('更新《数据结构与算法》关注状态失败，请重试'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('撤销'),
        ),
        findsNothing,
      );

      // 2) Toggle succeeds, then undo persistence fails -> shows undo failure message.
      store.failFollowCourse = false;
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(store.follows('101:10'), isFalse);
      final undoBtn = find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('撤销'),
      );
      expect(undoBtn, findsOneWidget);

      store.failFollowCourse = true;
      await tester.tap(undoBtn);
      await tester.pumpAndSettle();
      expect(store.follows('101:10'), isFalse);
      expect(
        find.text('撤销《数据结构与算法》关注状态失败，请重试'),
        findsOneWidget,
      );
    });
  });
}

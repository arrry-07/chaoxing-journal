import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/assignment_change.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

import 'review_core_remediation_test.dart' as f;

class _Store extends AssignmentStore {
  _Store()
      : super(
          sessionStore: SecureSessionStore(),
          notificationService: LocalNotificationService(),
          widgetSnapshotService: WidgetSnapshotService(),
        );

  @override
  Future<bool> saveHomeFilters(HomeFilters next, int expectedEpoch) async {
    homeFilters = next;
    notifyListeners();
    return true;
  }

  void changed() => notifyListeners();
}

Assignment _work(
  String id, {
  required String title,
  required String course,
  required DateTime? due,
  bool trusted = true,
  String? submitUrl,
}) =>
    Assignment(
      id: 'cx:work:1:2:$id',
      title: title,
      courseName: course,
      deadlineAt: due,
      deadlineTrusted: trusted,
      requirementsText: '',
      status: 'pending',
      submitUrl: submitUrl,
      lastSyncedAt: DateTime.now(),
    );

DateTime _chinaTime(DateTime now, int dayOffset, int hour) {
  final china = now.toUtc().add(const Duration(hours: 8));
  return DateTime.utc(
    china.year,
    china.month,
    china.day + dayOffset,
    hour - 8,
  );
}

final _dateHeading = RegExp(r'^(?:\d{4}年)?\d+月\d+日 周[一二三四五六日]$');

String _heading(DateTime instant, DateTime now, {bool fullYear = false}) {
  final day = instant.toUtc().add(const Duration(hours: 8));
  final today = now.toUtc().add(const Duration(hours: 8));
  final year = fullYear || day.year != today.year ? '${day.year}年' : '';
  return '$year${day.month}月${day.day}日 周${'一二三四五六日'[day.weekday - 1]}';
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'all home sort modes keep their order and add trusted date headings',
      (tester) async {
    final now = DateTime.now();
    final dayOne = _chinaTime(now, 1, 10);
    final dayTwo = _chinaTime(now, 2, 9);
    final alpha = _work('alpha', title: 'Alpha 作业', course: '物理', due: dayOne);
    final beta = _work('beta',
        title: 'Beta 作业',
        course: '数学',
        due: dayOne.add(const Duration(hours: 2)));
    final gamma = _work('gamma', title: 'Gamma 作业', course: '数学', due: dayTwo);
    final delta = _work('delta', title: 'Delta 作业', course: '语文', due: null);
    final unknown = _work(
      'unknown',
      title: 'Unknown 作业',
      course: '英语',
      due: dayTwo,
      trusted: false,
    );
    final store = _Store()
      ..replaceAssignmentsForTest([unknown, delta, gamma, beta, alpha]);
    addTearDown(store.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 2400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AssignmentListScreen(store: store))),
    );

    final expected = {
      HomeSortOrder.grouped: (
        ['Alpha 作业', 'Beta 作业', 'Gamma 作业', 'Unknown 作业', 'Delta 作业'],
        [_heading(dayOne, now), _heading(dayTwo, now)],
      ),
      HomeSortOrder.deadlineAsc: (
        ['Alpha 作业', 'Beta 作业', 'Gamma 作业', 'Unknown 作业', 'Delta 作业'],
        [_heading(dayOne, now), _heading(dayTwo, now)],
      ),
      HomeSortOrder.deadlineDesc: (
        ['Gamma 作业', 'Beta 作业', 'Alpha 作业', 'Unknown 作业', 'Delta 作业'],
        [_heading(dayTwo, now), _heading(dayOne, now)],
      ),
      HomeSortOrder.courseName: (
        ['Beta 作业', 'Gamma 作业', 'Alpha 作业', 'Unknown 作业', 'Delta 作业'],
        [
          _heading(dayOne, now),
          _heading(dayTwo, now),
          _heading(dayOne, now),
        ],
      ),
      HomeSortOrder.title: (
        ['Alpha 作业', 'Beta 作业', 'Gamma 作业', 'Unknown 作业', 'Delta 作业'],
        [_heading(dayOne, now), _heading(dayTwo, now)],
      ),
    };

    for (final entry in expected.entries) {
      store.homeFilters = HomeFilters(sortOrder: entry.key);
      store.changed();
      await tester.pump();

      final titles = tester
          .widgetList<AssignmentCard>(find.byType(AssignmentCard))
          .map((card) => card.assignment.title)
          .toList();
      expect(titles, entry.value.$1, reason: entry.key.name);
      final headings = tester
          .widgetList<Text>(find.byWidgetPredicate((widget) =>
              widget is Text &&
              _dateHeading.hasMatch(
                  widget.data ?? widget.textSpan?.toPlainText() ?? '')))
          .map((text) => text.data ?? text.textSpan?.toPlainText())
          .toList();
      expect(headings, entry.value.$2, reason: entry.key.name);
    }
  });

  testWidgets('untrusted and absent dates never receive synthetic headings',
      (tester) async {
    final store = _Store()
      ..replaceAssignmentsForTest([
        _work('no-date', title: '无截止日期', course: '语文', due: null),
        _work(
          'untrusted',
          title: '截止待确认',
          course: '英语',
          due: DateTime.now().add(const Duration(days: 2)),
          trusted: false,
        ),
      ]);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AssignmentListScreen(store: store))),
    );

    expect(
      find.byWidgetPredicate((widget) =>
          widget is Text &&
          _dateHeading
              .hasMatch(widget.data ?? widget.textSpan?.toPlainText() ?? '')),
      findsNothing,
    );
    expect(find.text('未设置截止时间'), findsNothing);
    expect(find.byType(AssignmentCard), findsNWidgets(2));
    expect(find.text('无截止日期'), findsWidgets);
    expect(find.text('截止时间待确认'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('无截止日期'), findsWidgets);
    expect(find.text('无日期与待确认'), findsOneWidget);
  });

  testWidgets('home date heading and long title reflow without overlaps',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final now = DateTime.now();
    final due = _chinaTime(now, 1, 14);
    const title = '面向对象程序设计课程综合实验报告与项目复盘总结材料';
    final work = _work(
      'layout',
      title: title,
      course: '计算机课程综合实践与应用专题研讨班',
      due: due,
      submitUrl:
          'https://mooc1.chaoxing.com/work/view?courseid=1&classid=2&workid=layout',
    );

    for (final width in [320.0, 390.0]) {
      for (final scale in [1.0, 2.0]) {
        final store = _Store()..replaceAssignmentsForTest([work]);
        addTearDown(store.dispose);
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(body: AssignmentListScreen(store: store)),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$width/$scale');
        expect(find.text(_heading(due, now)), findsOneWidget);

        final action = find.byTooltip('在学习通内打开作业');
        await tester.scrollUntilVisible(
          action,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull, reason: '$width/$scale');
        expect(
          tester.getRect(find.text(title)).overlaps(tester.getRect(action)),
          isFalse,
          reason: '$width/$scale',
        );
      }
    }
  });

  testWidgets(
      'home date headings keep only cross-year prefixes and mark Beijing today and tomorrow',
      (tester) async {
    final now = DateTime.now();
    final today =
        _chinaTime(now, 1, 0).subtract(const Duration(microseconds: 1));
    final tomorrow = _chinaTime(now, 1, 0).add(const Duration(minutes: 30));
    final nextYear = DateTime.utc(
      now.toUtc().add(const Duration(hours: 8)).year + 1,
      4,
      15,
      4,
    );
    final store = _Store()
      ..replaceAssignmentsForTest([
        _work('today', title: '当天作业', course: '课程', due: today),
        _work('tomorrow', title: '次日作业', course: '课程', due: tomorrow),
        _work('next-year', title: '跨年作业', course: '课程', due: nextYear),
      ]);
    addTearDown(store.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AssignmentListScreen(store: store))),
    );

    final todayHeading = find.text(_heading(today, now));
    final tomorrowHeading = find.text(_heading(tomorrow, now));
    expect(find.text(_heading(today, now, fullYear: true)), findsNothing);
    expect(find.text(_heading(nextYear, now, fullYear: true)), findsOneWidget);
    for (final (label, badge) in [
      (todayHeading, '今天'),
      (tomorrowHeading, '明天'),
    ]) {
      final row = find.ancestor(of: label, matching: find.byType(Row)).first;
      expect(
          find.descendant(of: row, matching: find.text(badge)), findsOneWidget);
    }

    final heading = tester.widget<Text>(todayHeading);
    final spans = (heading.textSpan as TextSpan?)?.children;
    expect(spans, isNotNull);
    expect(
      spans!.whereType<TextSpan>().any((span) =>
          span.text?.contains('月') == true &&
          span.style?.fontWeight == FontWeight.w700),
      isTrue,
    );
  });

  testWidgets('recovery keeps full work headings and the original time order',
      (tester) async {
    final now = DateTime.now();
    final due = _chinaTime(now, 12, 14);
    final later = _work('later', title: '远期截止', course: '课程', due: due)
        .copyWith(status: 'unknown');
    final startOnly = _work(
      'start-only',
      title: '仅有开始时间',
      course: '课程',
      due: null,
      trusted: false,
    ).copyWith(availableFromAt: now);
    final store = _Store()..replaceAssignmentsForTest([later, startOnly]);
    addTearDown(store.dispose);
    final router = await _mountRoutedHome(tester, store);

    List<String> cardIds() => tester
        .widgetList<AssignmentCard>(find.byType(AssignmentCard))
        .map((card) => card.assignment.id)
        .toList();
    expect(cardIds(), [startOnly.id, later.id]);

    router.go('/assignments?scope=deadlinePending');
    await tester.pumpAndSettle();
    expect(cardIds(), [later.id, startOnly.id]);
    expect(find.text(_heading(due, now, fullYear: true)), findsOneWidget);
    expect(find.text('无日期与待确认'), findsNothing);
  });

  testWidgets('same-day exam retains its full heading in home and recovery',
      (tester) async {
    final now = DateTime.now();
    final start = _chinaTime(now, 1, 9);
    final work = _work(
      'same-day',
      title: '同日作业',
      course: '课程',
      due: start.subtract(const Duration(hours: 1)),
    );
    final exam = Assignment(
      id: 'cx:exam:1:2:1',
      source: AssignmentSource.exam,
      title: '同日考试',
      courseName: '课程',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
      exam: ExamInfo(
        examId: '1',
        courseId: '1',
        clazzId: '2',
        lifecycle: 'scheduled',
        startAt: start,
        startTrusted: true,
        endAt: start.add(const Duration(hours: 2)),
        endTrusted: true,
      ),
    );
    final store = _Store()..replaceAssignmentsForTest([work, exam]);
    addTearDown(store.dispose);
    final router = await _mountRoutedHome(tester, store);

    final workHeading = _heading(start, now);
    final examHeading = _heading(start, now, fullYear: true);
    if (workHeading != examHeading) {
      expect(find.text(workHeading), findsOneWidget);
      expect(find.text('明天'), findsNWidgets(2));
    } else {
      expect(find.text('明天'), findsOneWidget);
    }
    expect(find.text(examHeading), findsOneWidget);

    router.go('/assignments?scope=examUnknown');
    await tester.pumpAndSettle();
    expect(find.text(examHeading), findsOneWidget);
    expect(find.text(work.title), findsNothing);
    expect(find.text(exam.title), findsOneWidget);
    expect(find.text('明天'), findsNothing);
    expect(find.text('置顶'), findsNothing);
  });

  group('Phase 2A pinned ordering, drag reorder, context menu & 3-line rail',
      () {
    testWidgets(
        'unmanual pins auto-sort by nearest remaining time with untrusted last, show 3-line rail and vermilion near-due',
        (tester) async {
      final now = DateTime.utc(2026, 11, 20, 4, 0); // Beijing 12:00
      final session = f.Session();
      final store = _PinTimelineStore(sessionStore: session, clock: () => now);
      addTearDown(store.dispose);

      final far = _work(
        'far',
        title: '远期置顶',
        course: '语文',
        due: now.add(const Duration(days: 5)),
      );
      final today = _work(
        'today',
        title: '今天置顶',
        course: '高数',
        due: now.add(const Duration(hours: 3)), // Beijing 15:00 today
      );
      final unknown = _work(
        'unknown',
        title: '无期限置顶',
        course: '英语',
        due: null,
        trusted: false,
      );
      await store.repository.activateAccount('A');
      await store.repository.mergeAndSave([far, unknown, today]);
      await store.restoreSession();

      // Single pin: no drag handle shown, left rail shows 3 lines with berry color.
      await store.togglePin(today);
      await _mountRoutedHomeWithClock(tester, store, () => now);
      expect(find.byIcon(Icons.drag_indicator_rounded), findsNothing);
      expect(find.text('今天'), findsOneWidget);
      expect(find.text('15:00'), findsOneWidget);
      expect(find.text('剩3小时'), findsOneWidget);
      final todayText = tester.widget<Text>(find.text('今天'));
      expect(todayText.style?.color, Journal.berry);

      // Pin two more -> auto order: today, far, unknown; drag handle appears.
      await store.togglePin(unknown);
      await store.togglePin(far);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.drag_indicator_rounded), findsNWidgets(3));

      double topOf(String title) => tester.getTopLeft(find.text(title)).dy;
      expect(topOf(today.title), lessThan(topOf(far.title)));
      expect(topOf(far.title), lessThan(topOf(unknown.title)));
      expect(find.text('待定'), findsOneWidget);

      // Long-press menu offers non-drag '置顶下移' on item 0 and persists manual order.
      await tester.longPress(find.text(today.title));
      await tester.pumpAndSettle();
      expect(find.text('置顶下移'), findsOneWidget);
      expect(find.text('置顶上移'), findsNothing);
      await tester.tap(find.text('置顶下移'));
      await tester.pumpAndSettle();

      expect(store.hasManualPinOrder, isTrue);
      expect(topOf(far.title), lessThan(topOf(today.title)));
      expect(
        store.pinnedKeys,
        [far.courseTaskKey, today.courseTaskKey, unknown.courseTaskKey],
      );

      // Direct drag on drag handle reorders pins and preserves order.
      final lastHandle = find.byIcon(Icons.drag_indicator_rounded).last;
      final dragDistance = tester.getCenter(find.text(far.title)).dy -
          tester.getCenter(find.text(unknown.title)).dy -
          30;
      await tester.timedDrag(
        lastHandle,
        Offset(0, dragDistance),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();
      expect(
        store.pinnedKeys,
        [unknown.courseTaskKey, far.courseTaskKey, today.courseTaskKey],
      );
    });
  });

  testWidgets(
      'Phase 2B home card displays manual label with official pending and keeps manual overdue at bottom',
      (tester) async {
    final now = DateTime.utc(2026, 11, 20, 4); // 12:00 Beijing
    final session = f.Session()..account = 'home-manual-student';
    final futureUntrusted = _work(
      'future-m',
      title: '未确认但设了未来手动截止',
      course: '离散数学',
      due: null,
      trusted: false,
    );
    final pastUntrusted = _work(
      'past-m',
      title: '已过手动截止的作业',
      course: '算法设计',
      due: null,
      trusted: false,
    );
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('home-manual-student');
    await repo
        .mergeAndSave([futureUntrusted, pastUntrusted], completeSync: true);
    final store = _PinTimelineStore(sessionStore: session, clock: () => now);
    addTearDown(store.dispose);
    await store.restoreSession();
    expect(
      await store.setManualDeadline(
        futureUntrusted,
        now.add(const Duration(days: 1)),
      ),
      isTrue,
    );
    expect(
      await store.setManualDeadline(
        pastUntrusted,
        now.subtract(const Duration(hours: 3)),
      ),
      isTrue,
    );

    await _mountRoutedHomeWithClock(tester, store, () => now);
    expect(find.text('手动'), findsNWidgets(2));
    expect(find.textContaining('官方待确认'), findsNWidgets(2));
    expect(find.text('手动截止已过'), findsOneWidget);
    expect(find.text('已逾期置底'), findsOneWidget);

    final cards =
        tester.widgetList<AssignmentCard>(find.byType(AssignmentCard)).toList();
    expect(
      cards.map((c) => c.assignment.title).toList(),
      ['未确认但设了未来手动截止', '已过手动截止的作业'],
    );
  });

  testWidgets(
      'Phase 2D home card shows 时间变更 pill for advance deadline and clears after acknowledgment or local completion',
      (tester) async {
    final now = DateTime.utc(2026, 11, 20, 4);
    final session = f.Session()..account = 'home-alert-student';
    final work = _work(
      'adv',
      title: '教师提前截止的作业',
      course: '编译原理',
      due: now.add(const Duration(days: 1)),
    );
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('home-alert-student');
    await repo.mergeAndSave([work], completeSync: true);
    final store = _PinTimelineStore(sessionStore: session, clock: () => now);
    addTearDown(store.dispose);
    await store.restoreSession();
    final event = AssignmentChange(
      assignmentId: work.id,
      title: work.title,
      courseName: work.courseName,
      kind: AssignmentChangeKind.deadline,
      at: now,
      before: now.add(const Duration(days: 5)).toIso8601String(),
      after: now.add(const Duration(days: 1)).toIso8601String(),
      beforeDeadlineUtc: now.add(const Duration(days: 5)),
      afterDeadlineUtc: now.add(const Duration(days: 1)),
    );
    store.changes = [event];

    await _mountRoutedHomeWithClock(tester, store, () => now);
    expect(find.text('时间变更'), findsOneWidget);

    await store.setLocallyCompleted(work, true);
    await tester.pumpAndSettle();
    expect(find.text('时间变更'), findsNothing);

    await store.setLocallyCompleted(work, false);
    await tester.pumpAndSettle();
    expect(find.text('时间变更'), findsOneWidget);

    expect(
        await store.acknowledgeDeadlineAlert(event.effectiveChangeId), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('时间变更'), findsNothing);
  });

  testWidgets(
      'Phase 5A upcoming exam strip respects selected course scope and restores previous deadline filter at 360dp',
      (tester) async {
    final now = DateTime.utc(2026, 11, 16, 2); // Beijing 10:00
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final session = f.Session();
    final store = _PinTimelineStore(sessionStore: session, clock: () => now);
    addTearDown(store.dispose);
    await store.restoreSession();

    final mathExam = Assignment(
      id: 'cx:exam:1:2:10',
      source: AssignmentSource.exam,
      courseName: '高等数学',
      title: '高数期中考试',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
      exam: ExamInfo(
        examId: '10',
        courseId: '1',
        clazzId: '2',
        startAt: now.add(const Duration(days: 3)),
        endAt: now.add(const Duration(days: 3, hours: 2)),
        startTrusted: true,
        endTrusted: true,
        lifecycle: 'scheduled',
      ),
    );
    final staleNotice = Assignment(
      id: 'cx:examNotice:inbox:n10',
      source: AssignmentSource.exam,
      courseName: '高等数学',
      title: '高数期中考试（通知）',
      deadlineAt: null,
      requirementsText: '考试时间：2026-11-17 09:00 至 2026-11-17 11:00',
      status: 'pending',
      lastSyncedAt: now,
      exam: ExamInfo(
        examId: 'n10',
        relatedExamId: '10',
        courseId: '1',
        clazzId: '2',
        noticeOnly: true,
        startAt: now.add(const Duration(days: 1)),
        endAt: now.add(const Duration(days: 1, hours: 2)),
        startTrusted: true,
        endTrusted: true,
        lifecycle: 'scheduled',
      ),
    );
    final otherCourseWork = _work(
      'other-course',
      title: '大学英语作文',
      course: '大学英语',
      due: now.add(const Duration(days: 2)),
    ).copyWith(id: 'cx:work:9:9:w1');

    store
      ..replaceAssignmentsForTest([mathExam, staleNotice, otherCourseWork])
      ..homeFilters = const HomeFilters(
        courseKey: '1:2',
        deadline: AssignmentDeadlineFilter.notExpired,
      );

    await _mountRoutedHomeWithClock(tester, store, () => now);
    tester.view.physicalSize = const Size(360, 780);
    await tester.pumpAndSettle();

    // Formal exam wins over stale notice at day +1; shows +3 days.
    expect(find.text('近期考试 · 《高数期中考试》3 天后'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-upcoming-exam-strip')));
    await tester.pumpAndSettle();
    expect(store.homeFilters.type, AssignmentTypeFilter.exam);
    expect(store.homeFilters.courseKey, '1:2');

    // Return restores previous deadline filter + clears exam type.
    await tester.tap(find.byKey(const ValueKey('home-upcoming-exam-strip')));
    await tester.pumpAndSettle();
    expect(store.homeFilters.type, AssignmentTypeFilter.all);
    expect(store.homeFilters.courseKey, '1:2');
    expect(store.homeFilters.deadline, AssignmentDeadlineFilter.notExpired);

    // Selecting unrelated course removes the strip with zero placeholder.
    await store.saveHomeFilters(
      const HomeFilters(courseKey: '9:9'),
      store.accountEpoch,
    );
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('home-upcoming-exam-strip')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<GoRouter> _mountRoutedHomeWithClock(
  WidgetTester tester,
  AssignmentStore store,
  DateTime Function() clock,
) async {
  final router = GoRouter(
    initialLocation: '/assignments',
    routes: [
      GoRoute(
        path: '/assignments',
        builder: (_, __) =>
            Scaffold(body: AssignmentListScreen(store: store, clock: clock)),
      ),
    ],
  );
  addTearDown(router.dispose);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp.router(
    theme: StudyAssistantTheme.light,
    routerConfig: router,
  ));
  await tester.pumpAndSettle();
  return router;
}

class _PinTimelineStore extends AssignmentStore {
  _PinTimelineStore({required super.sessionStore, required super.clock})
      : super(
          notificationService: f.Notifications(),
          widgetSnapshotService: f.WidgetService(),
          chaoxingClient: f.Client(),
        );

  @override
  Future<bool> runDueAutoSync({DateTime? now}) async => false;
}

Future<GoRouter> _mountRoutedHome(
  WidgetTester tester,
  AssignmentStore store,
) async {
  final router = GoRouter(
    initialLocation: '/assignments',
    routes: [
      GoRoute(
        path: '/assignments',
        builder: (_, __) => Scaffold(body: AssignmentListScreen(store: store)),
      ),
    ],
  );
  addTearDown(router.dispose);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

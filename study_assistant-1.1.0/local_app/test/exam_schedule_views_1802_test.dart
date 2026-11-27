import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_grouping.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/exam_schedule_presentation.dart';
import 'package:study_assistant_mobile/src/services/home_upcoming_exam.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

final _now = DateTime.utc(2026, 11, 16);
const _body = '试卷名称：合成考试\n考试时间：11-16 07:06:00 至 11-30 07:06:31\n答题时长：60分钟';

Assignment _exam(
        {bool notice = false,
        String clazz = '2',
        bool trusted = false,
        String suffix = ''}) =>
    Assignment(
      id: notice ? 'cx:examNotice:inbox:n$clazz$suffix' : 'cx:exam:1:$clazz:3',
      source: AssignmentSource.exam,
      courseName: '合成课程',
      title: '合成考试',
      deadlineAt: null,
      requirementsText: notice ? _body : '',
      status: 'pending',
      lastSyncedAt: _now,
      exam: ExamInfo(
        examId: notice ? 'n$clazz$suffix' : '3',
        relatedExamId: notice ? '3' : null,
        courseId: '1',
        clazzId: clazz,
        noticeOnly: notice,
        startAt: trusted ? _now : null,
        endAt: trusted ? _now.add(const Duration(hours: 1)) : null,
        startTrusted: trusted,
        endTrusted: trusted,
        durationMinutes: 60,
        location: '',
      ),
    );

class _Store extends AssignmentStore {
  _Store(this.records)
      : super(
          sessionStore: SecureSessionStore(),
          notificationService: LocalNotificationService(),
          widgetSnapshotService: WidgetSnapshotService(),
        );
  final List<Assignment> records;
  final hidden = <String>[];
  final persistedHidden = <String>{};
  final batches = <List<String>>[];
  int reloads = 0;
  bool failBatch = false, throwBatch = false, switchAccount = false;
  int epoch = 0;
  @override
  int get accountEpoch => epoch;
  @override
  CourseworkGroup? courseworkGroupFor(String assignmentId) {
    for (final group in AssignmentGrouping.group(
      records,
      hiddenIds: persistedHidden,
    )) {
      if (group.sources.any((assignment) => assignment.id == assignmentId)) {
        return group;
      }
    }
    return null;
  }

  @override
  List<Assignment> get courseAssignments =>
      records.where((a) => !persistedHidden.contains(a.id)).toList();
  @override
  Assignment? findAssignment(String id) =>
      courseAssignments.where((a) => a.id == id).firstOrNull;
  @override
  Future<bool> setAssignmentsHidden(
    Iterable<String> assignmentIds,
    bool value,
  ) async {
    final ids = List<String>.unmodifiable(assignmentIds);
    batches.add(ids);
    if (switchAccount) {
      epoch++;
      throw StateError('synthetic account change');
    }
    if (throwBatch) throw StateError('synthetic failure');
    if (failBatch) return false;
    if (value) {
      hidden.addAll(ids);
      persistedHidden.addAll(ids);
    } else {
      hidden.removeWhere(ids.contains);
      persistedHidden.removeAll(ids);
    }
    // Simulate one serialized journal write + reload for the whole group.
    reloads++;
    notifyListeners();
    return true;
  }
}

Future<void> _detail(WidgetTester t, _Store store) async {
  await t.pumpWidget(MaterialApp(
      home: Scaffold(
          body: AssignmentDetailScreen(
              store: store, assignmentId: store.records.first.id))));
}

void main() {
  test('static compatibility reads own notice without promoting dates', () {
    final a = _exam(notice: true);
    final before = a.toJson();
    expect(AssignmentCard.examScheduleLines(a),
        ['考试时间：11-16 07:06:00 至 11-30 07:06:31', '时长 60 分钟']);
    expect(a.toJson(), before);
    expect(a.reminderAnchorAt, isNull);
  });

  test('static compatibility keeps trusted absolute schedule and metadata', () {
    expect(AssignmentCard.examScheduleLines(_exam(trusted: true)),
        ['开考 2026年11月16日 08:00', '结束 2026年11月16日 09:00', '时长 60 分钟']);
  });

  testWidgets(
      'card uses linked notice sources with no archive button or placeholders',
      (t) async {
    final a = _exam(), n = _exam(notice: true);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AssignmentCard(
                assignment: a,
                examSources: [a, n],
                now: _now,
                showFullDeadline: false,
                onTap: () {}))));
    expect(find.text('07:06'), findsOneWidget);
    expect(find.text('考试时间：11-16 07:06:00 至 11-30 07:06:31'), findsNothing);
    expect(find.text('时长 60 分钟'), findsOneWidget);
    expect(find.text('归档'), findsNothing);
    expect(find.text('—'), findsNothing);
    expect(find.text('年份待确认'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('card does not borrow same title from another class', (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AssignmentCard(
                assignment: _exam(),
                examSources: [_exam(notice: true, clazz: '9')],
                now: _now,
                onTap: () {}))));
    expect(find.textContaining('07:06'), findsNothing);
  });

  testWidgets('detail uses source time and a single helper verification note',
      (t) async {
    final store = _Store([_exam(), _exam(notice: true)]);
    addTearDown(store.dispose);
    final schedule = ExamSchedulePresentation.build(store.records.first,
        records: store.records);
    expect(schedule.verificationNote, isNotNull);
    await _detail(t, store);
    expect(find.textContaining('考试时间：11-16 07:06:00 至 11-30 07:06:31'),
        findsOneWidget);
    expect(find.text(schedule.verificationNote!), findsOneWidget);
    expect(find.text('部分信息尚未核实'), findsNothing);
    expect(find.textContaining('地点'), findsNothing);
    expect(t.takeException(), isNull);
  });

  for (final mode in ['success', 'false', 'throw', 'account']) {
    testWidgets('detail hides complete identity sources: $mode', (t) async {
      final a = _exam(), n = _exam(notice: true);
      final second = _exam(notice: true, suffix: 'second');
      final other = _exam(notice: true, clazz: '9');
      final store = _Store([a, n, second, other])
        ..failBatch = mode == 'false'
        ..throwBatch = mode == 'throw'
        ..switchAccount = mode == 'account';
      addTearDown(store.dispose);
      final router = GoRouter(initialLocation: '/detail', routes: [
        GoRoute(
            path: '/detail',
            builder: (_, __) => Scaffold(
                body:
                    AssignmentDetailScreen(store: store, assignmentId: a.id))),
        GoRoute(
            path: '/assignments',
            builder: (_, __) => const Scaffold(body: Text('返回列表成功'))),
      ]);
      addTearDown(router.dispose);
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      await t.pumpAndSettle();
      final hide = find.widgetWithText(TextButton, '在本机隐藏此考试（3 条来源）');
      // ListView builds offscreen children lazily. Build the action by scrolling
      // before ensureVisible, which requires an already mounted element.
      await t.scrollUntilVisible(hide, 250,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      await Scrollable.ensureVisible(t.element(hide), alignment: 0.5);
      await t.pumpAndSettle();
      expect(hide.hitTestable(), findsOneWidget);
      expect(t.widget<TextButton>(hide).onPressed, isNotNull);
      await t.tap(hide);
      await t.pumpAndSettle();
      if (mode == 'false' || mode == 'throw') {
        expect(store.findAssignment(a.id), same(a),
            reason:
                'Partial archive must retain the detail representative for retry');
        expect(find.textContaining('尚未在当前账号的本机记录中找到'), findsNothing);
      }
      final expectedSources = [a.id, n.id, second.id];
      expect(store.batches, [expectedSources]);
      expect(store.hidden, mode == 'success' ? expectedSources : isEmpty);
      expect(store.hidden, isNot(contains(other.id)));
      expect(find.text('返回列表成功'),
          mode == 'success' ? findsOneWidget : findsNothing);
      if (mode != 'success') {
        expect(find.textContaining('隐藏失败'), findsOneWidget);
        expect(store.findAssignment(a.id), same(a));
        expect(store.findAssignment(n.id), same(n));
        expect(store.reloads, 0);
        expect(find.textContaining('尚未在当前账号的本机记录中找到'), findsNothing);
        expect(hide.hitTestable(), findsOneWidget);
        expect(t.widget<TextButton>(hide).onPressed, isNotNull);
        if (mode != 'account') {
          // A failed batch commits no source; retry the whole group at once.
          store.failBatch = false;
          store.throwBatch = false;
          await t.tap(hide);
          await t.pumpAndSettle();
          expect(store.batches, [expectedSources, expectedSources]);
          expect(store.hidden, expectedSources);
          expect(store.findAssignment(a.id), isNull);
          expect(store.findAssignment(second.id), isNull);
          expect(store.findAssignment(other.id), same(other));
          expect(store.reloads, 1);
          expect(find.text('返回列表成功'), findsOneWidget);
        }
      } else {
        expect(store.findAssignment(a.id), isNull);
        expect(store.findAssignment(other.id), same(other));
        expect(store.reloads, 1);
      }
      expect(store.records.map((r) => r.status), everyElement('pending'));
      expect(t.takeException(), isNull);
    });
  }

  test(
      'Phase 5A HomeUpcomingExam rejects standalone noticeOnly, yearless notice times, and stale conflicting notices after reschedule',
      () {
    final now = DateTime.utc(2026, 11, 16, 2); // Beijing 10:00
    final standaloneNotice = Assignment(
      id: 'cx:examNotice:inbox:99',
      source: AssignmentSource.exam,
      courseName: '高等数学',
      title: '仅通知考试',
      deadlineAt: null,
      requirementsText: '考试时间：11-18 09:00:00 至 11-18 11:00:00',
      status: 'pending',
      lastSyncedAt: now,
      exam: ExamInfo(
        examId: '99',
        courseId: '1',
        clazzId: '2',
        noticeOnly: true,
        startAt: now.add(const Duration(days: 2)),
        endAt: now.add(const Duration(days: 2, hours: 2)),
        startTrusted: true,
        endTrusted: true,
        lifecycle: 'scheduled',
      ),
    );
    expect(HomeUpcomingExam.select([standaloneNotice], now: now), isNull);

    final unverifiedWithNoticeRange = _exam(notice: false, trusted: false);
    final linkedNotice = _exam(notice: true, trusted: false);
    expect(
      HomeUpcomingExam.select(
        [unverifiedWithNoticeRange, linkedNotice],
        now: now,
      ),
      isNull,
    );

    final formalMovedOut = Assignment(
      id: 'cx:exam:1:2:3',
      source: AssignmentSource.exam,
      courseName: '合成课程',
      title: '改期后的考试',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
      exam: ExamInfo(
        examId: '3',
        courseId: '1',
        clazzId: '2',
        noticeOnly: false,
        startAt: now.add(const Duration(days: 16)),
        endAt: now.add(const Duration(days: 16, hours: 2)),
        startTrusted: true,
        endTrusted: true,
        lifecycle: 'scheduled',
      ),
    );
    final staleNoticeDay3 = Assignment(
      id: 'cx:examNotice:inbox:n2',
      source: AssignmentSource.exam,
      courseName: '合成课程',
      title: '改期后的考试',
      deadlineAt: null,
      requirementsText: '考试时间：2026-11-19 09:00 至 2026-11-19 11:00',
      status: 'pending',
      lastSyncedAt: now,
      exam: ExamInfo(
        examId: 'n2',
        relatedExamId: '3',
        courseId: '1',
        clazzId: '2',
        noticeOnly: true,
        startAt: now.add(const Duration(days: 3)),
        endAt: now.add(const Duration(days: 3, hours: 2)),
        startTrusted: true,
        endTrusted: true,
        lifecycle: 'scheduled',
      ),
    );
    expect(
      HomeUpcomingExam.select([formalMovedOut, staleNoticeDay3], now: now),
      isNull,
    );
  });
}

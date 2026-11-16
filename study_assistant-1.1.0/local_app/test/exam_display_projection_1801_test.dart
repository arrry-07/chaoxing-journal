import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';

final now = DateTime.utc(2026, 11, 16, 2);
Assignment exam(
        {String id = '3',
        String? course = '1',
        String? clazz = '2',
        bool notice = false,
        String? related,
        DateTime? start,
        DateTime? end,
        bool trusted = true,
        String lifecycle = 'unknown',
        String status = 'pending',
        String location = ''}) =>
    Assignment(
        id: notice
            ? 'cx:examNotice:inbox:$id'
            : 'cx:exam:${course ?? 'account'}:${clazz ?? 'account'}:$id',
        source: AssignmentSource.exam,
        courseName: '课程',
        title: '同名考试',
        deadlineAt: null,
        requirementsText: '',
        status: status,
        lastSyncedAt: now,
        exam: ExamInfo(
            examId: id,
            courseId: course,
            clazzId: clazz,
            noticeOnly: notice,
            relatedExamId: related,
            startAt: start,
            endAt: end,
            startTrusted: trusted && start != null,
            endTrusted: trusted && end != null,
            lifecycle: lifecycle,
            location: location));

class _PreviewArchiveStore extends AssignmentStore {
  _PreviewArchiveStore(this.preview)
      : super(
            sessionStore: SecureSessionStore(),
            notificationService: LocalNotificationService(),
            widgetSnapshotService: WidgetSnapshotService());
  final Assignment preview;
  int hiddenCalls = 0;
  @override
  List<Assignment> get homeDisplayAssignments => [preview];
  @override
  List<Assignment> get courseAssignments => [];
  @override
  Future<bool> hideAssignment(String id) async {
    hiddenCalls++;
    return true;
  }
}

void main() {
  testWidgets('unsaved exam preview is visible without a separate archive row',
      (tester) async {
    final store = _PreviewArchiveStore(exam());
    addTearDown(store.dispose);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AssignmentListScreen(store: store))));
    await tester.pumpAndSettle();
    expect(find.text('同名考试'), findsOneWidget);
    expect(find.textContaining('考试时间未知'), findsNothing);
    expect(find.text('归档'), findsNothing);
    expect(store.hiddenCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('conflicting notices never infer publication order from sync time or ID',
      () {
    final old = exam(
            id: 'a',
            notice: true,
            related: '3',
            lifecycle: 'ended',
            start: now.subtract(const Duration(days: 2)),
            end: now.subtract(const Duration(days: 1)))
        .copyWith(lastSyncedAt: now.add(const Duration(seconds: 5)));
    final changed = exam(
        id: 'z',
        notice: true,
        related: '3',
        lifecycle: 'scheduled',
        start: now.add(const Duration(days: 1)),
        end: now.add(const Duration(days: 2)));
    for (final records in [
      [old, changed],
      [changed, old]
    ]) {
      final projected = AssignmentQuery.projectDisplay(records).single;
      expect(projected.id, old.id);
      expect(projected.exam!.lifecycle, 'unknown');
      expect(projected.exam!.startTrusted, isFalse);
      expect(projected.exam!.endTrusted, isFalse);
      expect(AssignmentQuery.isExamEnded(projected, now), isFalse);
      expect(AssignmentQuery.currentDisplay(records, now), hasLength(1));
      expect(AssignmentQuery.calendarDisplay(records, now), isEmpty);
      expect(projected.reminderAnchorAt, isNull);
      expect(
          AssignmentQuery.projectDisplay([projected]).single.exam!.endTrusted,
          isFalse);
      expect(old.exam!.endTrusted, isTrue);
    }
  });
  test('notice lifecycle conflict alone revokes time trust', () {
    final a = exam(
        id: 'a',
        notice: true,
        related: '3',
        lifecycle: 'cancelled',
        start: now,
        end: now.add(const Duration(hours: 1)));
    final b = exam(
        id: 'b',
        notice: true,
        related: '3',
        lifecycle: 'inProgress',
        start: now,
        end: now.add(const Duration(hours: 1)));
    final p = AssignmentQuery.projectDisplay([a, b]).single;
    expect(p.exam!.lifecycle, 'unknown');
    expect(p.timelineTrusted, isFalse);
    expect(AssignmentQuery.currentDisplay([a, b], now), hasLength(1));
  });
  test('formal explicit schedule wins over conflicting notices', () {
    final a = exam(
        lifecycle: 'scheduled',
        start: now.add(const Duration(days: 3)),
        end: now.add(const Duration(days: 4)));
    final old = exam(
        id: 'a',
        notice: true,
        related: '3',
        lifecycle: 'ended',
        start: now.subtract(const Duration(days: 2)),
        end: now.subtract(const Duration(days: 1)));
    final p = AssignmentQuery.currentDisplay([old, a], now).single;
    expect(p.id, a.id);
    expect(p.timelineAt, a.timelineAt);
    expect(p.exam!.endAt, a.exam!.endAt);
    expect(p.exam!.lifecycle, 'scheduled');
  });
  test('conflicting notice evidence cannot fill missing formal dates', () {
    final a = exam();
    final n1 = exam(
        id: 'a',
        notice: true,
        related: '3',
        start: now,
        end: now.add(const Duration(hours: 1)));
    final n2 = exam(
        id: 'b',
        notice: true,
        related: '3',
        start: now.add(const Duration(days: 1)),
        end: now.add(const Duration(days: 2)));
    final p = AssignmentQuery.projectDisplay([n1, a, n2]).single;
    expect(p.timelineAt, isNull);
    expect(p.exam!.endAt, isNull);
    expect(p.exam!.lifecycle, 'unknown');
  });
  test('formal unknown does not inherit notice cancellation without chronology',
      () {
    final a = exam();
    final n = exam(id: 'n', notice: true, related: '3', lifecycle: 'cancelled');
    final p = AssignmentQuery.currentDisplay([a, n], now).single;
    expect(p.exam!.lifecycle, 'unknown');
    expect(p.id, a.id);
  });

  test('end boundary exits current display without inventing submission', () {
    final a = exam(start: now.subtract(const Duration(hours: 1)), end: now);
    expect(
        AssignmentQuery.currentDisplay(
            [a], now.subtract(const Duration(seconds: 1))),
        hasLength(1));
    expect(AssignmentQuery.currentDisplay([a], now), isEmpty);
    expect(a.status, 'pending');
    expect(a.isCompleted, isFalse);
    expect(AssignmentQuery.scope([a], {}), [a]);
  });
  test('official terminal states exit even without dates', () {
    for (final lifecycle in ['ended', 'cancelled']) {
      final a = exam(lifecycle: lifecycle);
      expect(AssignmentQuery.currentDisplay([a], now), isEmpty);
      expect(AssignmentRecoveryScope.examUnknown.matches(a, now), isFalse);
    }
  });
  test('old untrusted end and start-only do not end exam', () {
    expect(AssignmentQuery.isExamEnded(exam(end: now, trusted: false), now),
        isFalse);
    expect(
        AssignmentQuery.isExamEnded(
            exam(start: now.subtract(const Duration(days: 1))), now),
        isFalse);
  });
  test('complete identity deduplicates independent of order and preserves IDs',
      () {
    final a = exam();
    final n = exam(id: 'notice1', notice: true, related: '3', location: '教室');
    for (final records in [
      [a, n],
      [n, a]
    ]) {
      final projected = AssignmentQuery.projectDisplay(records).single;
      expect(projected.id, a.id);
      expect(projected.exam!.location, '教室');
      expect(AssignmentQuery.displaySources(projected, records), hasLength(2));
      expect(records, hasLength(2));
      expect(a.exam!.location, isEmpty);
      expect(n.id, 'cx:examNotice:inbox:notice1');
    }
  });
  test('submitted primary suppresses pending notice', () {
    expect(
        AssignmentQuery.currentDisplay([
          exam(id: 'notice', notice: true, related: '3'),
          exam(status: 'submitted')
        ], now),
        isEmpty);
  });
  test('title equality and incomplete or different identities never merge', () {
    final records = [
      exam(),
      exam(id: '4'),
      exam(clazz: '9'),
      exam(id: 'n', notice: true),
      exam(id: 'm', notice: true, related: '3', clazz: null)
    ];
    expect(AssignmentQuery.projectDisplay(records), hasLength(5));
  });
  test('notice dates supplement missing primary fields without changing state',
      () {
    final a = exam();
    final n = exam(
        id: 'n',
        notice: true,
        related: '3',
        start: now,
        end: now.add(const Duration(hours: 1)));
    final p = AssignmentQuery.projectDisplay([a, n]).single;
    expect(p.timelineAt, now);
    expect(p.timelineTrusted, isTrue);
    expect(p.status, a.status);
    expect(a.timelineAt, isNull);
  });
  test('past calendar retains completed and ended exams but not today/future',
      () {
    for (final state in ['submitted', 'pending']) {
      final past = exam(
          id: '1',
          status: state,
          lifecycle: 'ended',
          start: now.subtract(const Duration(days: 1)));
      final today = exam(status: state, lifecycle: 'ended', start: now);
      final future = exam(
          id: '3',
          status: state,
          lifecycle: 'ended',
          start: now.add(const Duration(days: 1)));
      expect(
          AssignmentQuery.calendarDisplay([past, today, future], now)
              .map((a) => a.timelineAt),
          [past.timelineAt]);
      expect(
          AssignmentQuery.forDay(
              [past], AssignmentQuery.dayKey(past.timelineAt!), {},
              now: now),
          hasLength(1));
    }
  });
  test('unknown exam is separate from unknown homework scope', () {
    final a = exam();
    expect(AssignmentRecoveryScope.examUnknown.matches(a, now), isTrue);
    expect(AssignmentRecoveryScope.deadlinePending.matches(a, now), isFalse);
    expect(AssignmentRecoveryScope.noDeadline.matches(a, now), isFalse);
  });
  test('time sorts keep chronological order with unknown last', () {
    final past = exam(id: '1', start: now.subtract(const Duration(hours: 1)));
    final future = exam(id: '2', start: now.add(const Duration(hours: 1)));
    final unknown = exam(id: '3');
    expect(
        AssignmentQuery.sortHome(
            [unknown, future, past], HomeSortOrder.deadlineAsc,
            now: now),
        [past, future, unknown]);
    expect(
        AssignmentQuery.sortHome(
            [unknown, future, past], HomeSortOrder.deadlineDesc,
            now: now),
        [future, past, unknown]);
  });
  test('legacy preferences migrate and preserve search/course', () {
    for (final order in ['grouped', 'title']) {
      final filters = HomeFilters.decode(
          '{"query":" test ","courseKey":"1:2","deadline":"all","sortOrder":"$order","type":"examNotice"}');
      expect(filters.sortOrder, HomeSortOrder.deadlineAsc);
      expect(filters.type, AssignmentTypeFilter.exam);
      expect(filters.query, 'test');
      expect(filters.courseKey, '1:2');
    }
    expect(homeTypeFilterChoices, hasLength(4));
    expect(homeSortOrderChoices, hasLength(3));
    expect(homeDeadlineFilterChoices, hasLength(3));
  });
}

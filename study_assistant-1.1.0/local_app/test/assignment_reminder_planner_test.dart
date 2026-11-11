import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_reminder_planner.dart';

void main() {
  final now = DateTime(2026, 11, 11, 9);

  test('first complete sync establishes a silent baseline', () {
    final plan = _plan(
      now: now,
      assignments: [_assignment(id: 'cx:work:1:2:old', deadline: null)],
      known: {},
      baseline: false,
      complete: true,
    );

    expect(plan.baselineCompleted, isTrue);
    expect(plan.newEvents, isEmpty);
    expect(plan.knownAssignmentIds, contains('cx:work:1:2:old'));
  });

  test('partial sync never establishes the baseline', () {
    final plan = _plan(
      now: now,
      assignments: [_assignment(id: 'cx:work:1:2:new')],
      known: {},
      baseline: false,
      complete: false,
    );

    expect(plan.baselineCompleted, isFalse);
    expect(plan.newEvents, isEmpty);
  });

  test('reliable new assignment in a later partial sync can be reminded', () {
    final plan = _plan(
      now: now,
      assignments: [_assignment(id: 'cx:work:1:2:partial-new')],
      known: {'cx:work:1:2:old'},
      baseline: true,
      complete: false,
    );

    expect(plan.baselineCompleted, isTrue);
    expect(plan.newEvents.single.assignmentId, 'cx:work:1:2:partial-new');
  });

  test('new unknown-deadline assignment is eligible after baseline', () {
    final plan = _plan(
      now: now,
      assignments: [_assignment(id: 'cx:work:1:2:new', deadline: null)],
      known: {'cx:work:1:2:old'},
      baseline: true,
      complete: true,
    );

    expect(plan.newEvents, hasLength(1));
    expect(plan.newEvents.single.eventId, contains('|new'));
    expect(plan.deadlineEvents, isEmpty);
  });

  test('known, hidden, unfollowed, completed and non-formal are filtered', () {
    final rows = [
      _assignment(id: 'cx:work:1:2:known'),
      _assignment(id: 'cx:work:1:2:hidden'),
      _assignment(id: 'cx:work:3:4:unfollowed'),
      _assignment(id: 'cx:work:1:2:done', status: 'submitted'),
      _assignment(id: 'cx:activity:1:2:a'),
      _assignment(id: 'cx:work:1:2:new'),
    ];
    final plan = _plan(
      now: now,
      assignments: rows,
      known: {'cx:work:1:2:known'},
      hidden: {'cx:work:1:2:hidden'},
      unfollowed: {'3:4'},
      baseline: true,
      complete: true,
    );

    expect(
        plan.newEvents.map((event) => event.assignmentId), ['cx:work:1:2:new']);
  });

  test('a previously sent new event is not recreated after reopening', () {
    final plan = _plan(
      now: now,
      assignments: [_assignment(id: 'cx:work:1:2:old')],
      known: {},
      sentNew: {'cx:work:1:2:old'},
      baseline: true,
      complete: true,
    );
    expect(plan.newEvents, isEmpty);
  });

  test('backup or visibility refresh does not classify records as new', () {
    final plan = _plan(
      now: now,
      assignments: [_assignment(id: 'cx:work:1:2:restored')],
      known: {'cx:work:1:2:old'},
      baseline: true,
      complete: false,
      detectNew: false,
    );
    expect(plan.newEvents, isEmpty);
    expect(plan.knownAssignmentIds, contains('cx:work:1:2:restored'));
  });

  test('early-morning deadlines shift to 08:00 or cancel when already due', () {
    final plan = _plan(
      now: DateTime(2026, 11, 10, 20),
      assignments: [
        _assignment(
            id: 'cx:work:1:2:early-valid', deadline: DateTime(2026, 11, 11, 9)),
        _assignment(
            id: 'cx:work:1:2:early-invalid',
            deadline: DateTime(2026, 11, 11, 7, 30)),
        _assignment(
            id: 'cx:work:1:2:at-eight', deadline: DateTime(2026, 11, 11, 8)),
      ],
      known: {
        'cx:work:1:2:early-valid',
        'cx:work:1:2:early-invalid',
        'cx:work:1:2:at-eight',
      },
      baseline: true,
      complete: true,
      offsets: [180],
    );

    expect(
      plan.deadlineEvents
          .where((event) => event.assignmentId == 'cx:work:1:2:early-valid')
          .single
          .notifyAt,
      DateTime(2026, 11, 11, 8),
    );
    expect(
      plan.deadlineEvents
          .where((event) => event.assignmentId == 'cx:work:1:2:early-invalid'),
      isEmpty,
    );
    expect(
      plan.deadlineEvents
          .where((event) => event.assignmentId == 'cx:work:1:2:at-eight'),
      isEmpty,
    );
  });

  test('multiple rules at the same shifted time merge into one event', () {
    final plan = _plan(
      now: DateTime(2026, 11, 10, 20),
      assignments: [
        _assignment(
            id: 'cx:work:1:2:merge', deadline: DateTime(2026, 11, 12, 9)),
      ],
      known: {'cx:work:1:2:merge'},
      baseline: true,
      complete: true,
      offsets: [240, 180],
    );

    expect(plan.deadlineEvents, hasLength(1));
    final shifted = plan.deadlineEvents
        .singleWhere((event) => event.notifyAt == DateTime(2026, 11, 12, 8));
    expect(shifted.offsetMinutes, [240, 180]);
  });

  test('deadline change creates a new event identity', () {
    final first = _plan(
      now: now,
      assignments: [
        _assignment(
            id: 'cx:work:1:2:changed', deadline: DateTime(2026, 11, 12, 9)),
      ],
      known: {'cx:work:1:2:changed'},
      baseline: true,
      complete: true,
      offsets: [30],
    );
    final second = _plan(
      now: now,
      assignments: [
        _assignment(
            id: 'cx:work:1:2:changed', deadline: DateTime(2026, 11, 12, 10)),
      ],
      known: {'cx:work:1:2:changed'},
      baseline: true,
      complete: true,
      offsets: [30],
    );
    expect(first.deadlineEvents.single.eventId,
        isNot(second.deadlineEvents.single.eventId));
  });

  test('repeating an unchanged sync produces stable event identities', () {
    AssignmentReminderPlan run() => _plan(
          now: now,
          assignments: [
            _assignment(
                id: 'cx:work:1:2:stable', deadline: DateTime(2026, 11, 12, 9)),
          ],
          known: {'cx:work:1:2:stable'},
          baseline: true,
          complete: true,
          offsets: [30],
        );
    expect(run().deadlineEvents.single.eventId,
        run().deadlineEvents.single.eventId);
  });
}

AssignmentReminderPlan _plan({
  required DateTime now,
  required List<Assignment> assignments,
  required Set<String> known,
  required bool baseline,
  required bool complete,
  Set<String> hidden = const {},
  Set<String> unfollowed = const {},
  Set<String> sentNew = const {},
  List<int> offsets = const [1440, 180, 30],
  bool newEnabled = true,
  bool detectNew = true,
}) =>
    AssignmentReminderPlanner.planAfterSync(
      accountHash: 'account-hash',
      sessionEpoch: 1,
      assignments: assignments,
      hiddenAssignmentIds: hidden,
      unfollowedCourseKeys: unfollowed,
      knownAssignmentIds: known,
      sentNewAssignmentIds: sentNew,
      baselineCompleted: baseline,
      completeSync: complete,
      detectNewAssignments: detectNew,
      newAssignmentReminderEnabled: newEnabled,
      reminderOffsetsMinutes: offsets,
      now: now,
    );

Assignment _assignment({
  required String id,
  DateTime? deadline,
  String course = '1:2',
  String status = 'pending',
}) {
  final parts = id.split(':');
  final courseId = parts.length >= 5 ? parts[2] : course.split(':')[0];
  return Assignment(
    id: id,
    courseName: '课程 $courseId',
    title: '作业 ${parts.last}',
    deadlineAt: deadline,
    requirementsText: '',
    status: status,
    lastSyncedAt: DateTime(2026, 11, 11, 9),
    deadlineTrusted: deadline != null,
    deadlineReadFailed: false,
    source: id.startsWith('cx:work:')
        ? AssignmentSource.courseWork
        : AssignmentSource.classroomActivity,
  );
}

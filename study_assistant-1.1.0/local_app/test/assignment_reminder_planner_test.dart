import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/local_coursework_state.dart';
import 'package:study_assistant_mobile/src/services/assignment_reminder_planner.dart';
import 'package:study_assistant_mobile/src/services/coursework_deadline.dart';

void main() {
  final now = DateTime(2026, 11, 11, 9);

  test('first activity baselines are silent alongside a new formal assignment',
      () {
    final plan = _plan(
      now: now,
      assignments: [
        _assignment(id: 'cx:work:1:2:new'),
        _assignment(
            id: 'cx:activity:1:2:task',
            activityType: 35,
            deadline: now.add(const Duration(days: 2))),
        _assignment(id: 'cx:activity:1:2:quiz', activityType: 42),
      ],
      known: {},
      baseline: true,
      complete: false,
      baselinedSources: {'courseWork'},
      completedSourceKeys: {'classroomActivity:35', 'classroomActivity:42'},
    );
    expect(plan.newEvents.map((e) => e.assignmentId), ['cx:work:1:2:new']);
    expect(plan.baselinedSources,
        {'courseWork', 'classroomActivity:35', 'classroomActivity:42'});
    expect(plan.deadlineEvents, isNotEmpty);
    final task = plan.snapshotJson
        .singleWhere((s) => s['assignmentId'] == 'cx:activity:1:2:task');
    expect(task['inAssignmentScope'], isTrue);
    expect(task['formal'], isFalse);
  });

  test('activity baseline allows later new records during a partial sync', () {
    final plan = _plan(
      now: now,
      assignments: [_assignment(id: 'cx:activity:1:2:new', activityType: 42)],
      known: {},
      baseline: false,
      complete: false,
      baselinedSources: {'classroomActivity:42'},
    );
    expect(plan.newEvents.single.assignmentId, 'cx:activity:1:2:new');
    expect(plan.baselineCompleted, isFalse);
  });

  test('explicit empty sources suppress legacy baseline fallback', () {
    final plan = _plan(
      now: now,
      assignments: [_assignment(id: 'cx:work:1:2:new')],
      known: {},
      baseline: true,
      complete: true,
      baselinedSources: {},
    );
    expect(plan.newEvents, isEmpty);
    expect(plan.baselinedSources, isEmpty);
    expect(plan.baselineCompleted, isFalse);
  });

  test('source success establishes its baseline even with no assignments', () {
    final plan = _plan(
      now: now,
      assignments: [],
      known: {},
      baseline: false,
      complete: false,
      baselinedSources: {},
      completedSourceKeys: {'classroomActivity:35'},
    );
    expect(plan.baselinedSources, {'classroomActivity:35'});
  });

  test('incomplete activity source stays silent until its first success', () {
    final existing = _assignment(
      id: 'cx:activity:1:2:existing',
      activityType: 35,
    );
    final partial = _plan(
      now: now,
      assignments: [existing],
      known: {},
      baseline: true,
      complete: false,
      baselinedSources: {'courseWork'},
    );
    expect(partial.baselinedSources, {'courseWork'});
    expect(partial.newEvents, isEmpty);

    final firstSuccess = _plan(
      now: now,
      assignments: [
        existing,
        _assignment(id: 'cx:activity:1:2:backlog', activityType: 35),
        _assignment(id: 'cx:activity:1:2:quiz', activityType: 42),
      ],
      known: partial.knownAssignmentIds,
      baseline: partial.baselineCompleted,
      complete: false,
      baselinedSources: partial.baselinedSources,
      completedSourceKeys: {'classroomActivity:35'},
    );
    expect(
        firstSuccess.baselinedSources, {'courseWork', 'classroomActivity:35'});
    expect(firstSuccess.newEvents, isEmpty);

    final later = _plan(
      now: now,
      assignments: [
        _assignment(id: 'cx:activity:1:2:new-task', activityType: 35),
        _assignment(id: 'cx:activity:1:2:new-quiz', activityType: 42),
      ],
      known: firstSuccess.knownAssignmentIds,
      baseline: firstSuccess.baselineCompleted,
      complete: false,
      baselinedSources: firstSuccess.baselinedSources,
    );
    expect(later.newEvents.map((event) => event.assignmentId),
        ['cx:activity:1:2:new-task']);
  });

  test('legacy completion maps only to course work without source statistics',
      () {
    final legacy = _plan(
        now: now, assignments: [], known: {}, baseline: false, complete: true);
    expect(legacy.baselinedSources, {'courseWork'});
    final withStatistics = _plan(
        now: now,
        assignments: [],
        known: {},
        baseline: false,
        complete: true,
        completedSourceKeys: {'classroomActivity:42'});
    expect(withStatistics.baselinedSources, {'classroomActivity:42'});
    expect(withStatistics.baselineCompleted, isFalse);
  });

  test('unsupported and unavailable identities never emit events', () {
    final plan = _plan(
      now: now,
      assignments: [
        _assignment(id: 'cx:activity:1:2:ai', activityType: 77),
        _assignment(
            id: 'cx:activity:1:2:missing',
            activityType: 35,
            availability: AssignmentAvailability.unavailable),
        _assignment(
            id: 'cx:activity:1:2:unknown',
            activityType: 42,
            status: 'unknown',
            deadline: now.add(const Duration(days: 2))),
        _assignment(
            id: 'cx:activity:1:2:failed',
            activityType: 35,
            deadlineReadFailed: true,
            deadline: now.add(const Duration(days: 2))),
      ],
      known: {},
      baseline: true,
      complete: true,
      baselinedSources: {
        'courseWork',
        'classroomActivity:35',
        'classroomActivity:42'
      },
    );
    expect(plan.newEvents, isEmpty);
    expect(plan.deadlineEvents, isEmpty);
    expect(
        plan.snapshotJson.singleWhere((s) =>
            s['assignmentId'] ==
            'cx:activity:1:2:missing')['inAssignmentScope'],
        isFalse);
  });

  test('unconfirmed availability encodes unknown status for native snapshots',
      () {
    final plan = _plan(
        now: now,
        assignments: [
          _assignment(
              id: 'cx:activity:1:2:unknown-availability',
              activityType: 35,
              availability: AssignmentAvailability.unknown,
              deadline: now.add(const Duration(days: 2))),
          _assignment(
              id: 'cx:work:1:2:unavailable',
              availability: AssignmentAvailability.unavailable),
        ],
        known: {},
        baseline: true,
        complete: false,
        baselinedSources: {'courseWork', 'classroomActivity:35'});
    expect(plan.snapshotJson.map((s) => s['status']), ['unknown', 'unknown']);
    expect(plan.newEvents, isEmpty);
    expect(plan.deadlineEvents, isEmpty);
  });

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

  test('conflicting overdue status never schedules a deadline reminder', () {
    final plan = _plan(
      now: now,
      assignments: [
        _assignment(
          id: 'cx:work:1:2:conflict',
          deadline: DateTime(2026, 11, 12, 9),
          status: 'overdue',
        ),
      ],
      known: const {},
      baseline: true,
      complete: true,
      offsets: [30],
    );

    expect(plan.newEvents, isEmpty);
    expect(plan.deadlineEvents, isEmpty);
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

  test(
      'Phase 2B planner uses manual deadline, skips manual past, and rebuilds cleanly on official takeover without resurrection',
      () {
    final now = DateTime.utc(2026, 11, 20, 4); // 12:00 Beijing
    final untrusted = Assignment(
      id: 'cx:work:1:2:m1',
      courseName: '计算机网络',
      title: '手工时间作业',
      deadlineAt: null,
      deadlineTrusted: false,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
    );
    final pastWork = Assignment(
      id: 'cx:work:1:2:m-past',
      courseName: '计算机网络',
      title: '手动已过作业',
      deadlineAt: null,
      deadlineTrusted: false,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
    );
    final manualAt = now.add(const Duration(days: 2));
    final pastAt = now.subtract(const Duration(hours: 2));
    final coursework = LocalCourseworkState()
        .withManualDeadline(
            CourseworkDeadline.keyFor(untrusted), const [], manualAt)
        .withManualDeadline(
            CourseworkDeadline.keyFor(pastWork), const [], pastAt);

    final manualPlan = _plan(
      now: now,
      assignments: [untrusted, pastWork],
      known: {untrusted.id, pastWork.id},
      baseline: true,
      complete: true,
      offsets: [60],
      coursework: coursework,
    );
    expect(
      manualPlan.deadlineEvents.map((e) => e.assignmentId).toList(),
      [untrusted.id],
    );
    expect(manualPlan.deadlineEvents.single.deadlineAt!.toUtc(), manualAt);
    expect(
      manualPlan.snapshots
          .singleWhere((s) => s.assignment.id == untrusted.id)
          .toJson(),
      containsPair('deadlineTrusted', true),
    );
    expect(
      manualPlan.snapshots
          .singleWhere((s) => s.assignment.id == untrusted.id)
          .toJson(),
      containsPair('deadlineReadFailed', false),
    );

    // Trusted official deadline takes over with a different timestamp -> new eventId replaces old alarm.
    final officialAt = now.add(const Duration(days: 4));
    final officialWork = untrusted.copyWith(
      deadlineAt: officialAt,
      deadlineTrusted: true,
      deadlineReadFailed: false,
    );
    final reconciled = CourseworkDeadline.reconcileWithAssignments(
      coursework,
      [officialWork, pastWork],
    );
    expect(
      reconciled
          .entryForAliases(CourseworkDeadline.aliasesFor(officialWork))!
          .officialTakenOver,
      isTrue,
    );
    final officialPlan = _plan(
      now: now,
      assignments: [officialWork],
      known: {untrusted.id},
      baseline: true,
      complete: true,
      offsets: [60],
      coursework: reconciled,
    );
    expect(officialPlan.deadlineEvents.single.deadlineAt!.toUtc(), officialAt);
    expect(
      officialPlan.deadlineEvents.single.eventId,
      isNot(manualPlan.deadlineEvents.single.eventId),
    );

    // Subsequent temporary detail failure must NOT resurrect stale manual deadline alarms.
    final failedAfterTakeover = officialWork.copyWith(deadlineReadFailed: true);
    final failedPlan = _plan(
      now: now,
      assignments: [failedAfterTakeover],
      known: {untrusted.id},
      baseline: true,
      complete: true,
      offsets: [60],
      coursework: reconciled,
    );
    expect(failedPlan.deadlineEvents, isEmpty);
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
  Set<String>? baselinedSources,
  Set<String> completedSourceKeys = const {},
  LocalCourseworkState coursework = const LocalCourseworkState.empty(),
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
      baselinedSources: baselinedSources,
      completedSourceKeys: completedSourceKeys,
      completeSync: complete,
      detectNewAssignments: detectNew,
      newAssignmentReminderEnabled: newEnabled,
      reminderOffsetsMinutes: offsets,
      now: now,
      courseworkState: coursework,
    );

Assignment _assignment({
  required String id,
  DateTime? deadline,
  String course = '1:2',
  String status = 'pending',
  int? activityType,
  AssignmentAvailability availability = AssignmentAvailability.available,
  bool deadlineReadFailed = false,
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
    deadlineTrusted: true,
    deadlineReadFailed: deadlineReadFailed,
    activityType: activityType,
    availability: availability,
    source: id.startsWith('cx:work:')
        ? AssignmentSource.courseWork
        : AssignmentSource.classroomActivity,
  );
}

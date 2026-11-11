import '../models/assignment.dart';
import 'daytime_check_policy.dart';

enum AssignmentReminderEventType { newAssignment, deadline }

class AssignmentReminderSnapshot {
  const AssignmentReminderSnapshot({
    required this.assignment,
    required this.hidden,
    required this.followed,
  });

  final Assignment assignment;
  final bool hidden;
  final bool followed;

  bool get eligible =>
      assignment.isFormal &&
      assignment.isPendingConfirmed &&
      !assignment.isCompleted &&
      !hidden &&
      followed;

  Map<String, dynamic> toJson() => {
        'assignmentId': assignment.id,
        'courseName': assignment.courseName,
        'title': assignment.title,
        'deadlineAt': assignment.deadlineAt?.toUtc().toIso8601String(),
        'deadlineTrusted': assignment.deadlineTrusted,
        'deadlineReadFailed': assignment.deadlineReadFailed,
        'status': assignment.status,
        'completed': assignment.isCompleted,
        'hidden': hidden,
        'followed': followed,
        'formal': assignment.isFormal,
      };
}

class AssignmentReminderEvent {
  const AssignmentReminderEvent({
    required this.eventId,
    required this.type,
    required this.assignmentId,
    required this.courseName,
    required this.title,
    required this.notifyAt,
    this.deadlineAt,
    this.offsetMinutes = const [],
    this.batchId,
  });

  final String eventId;
  final AssignmentReminderEventType type;
  final String assignmentId;
  final String courseName;
  final String title;
  final DateTime notifyAt;
  final DateTime? deadlineAt;
  final List<int> offsetMinutes;
  final String? batchId;

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'type': type.name,
        'assignmentId': assignmentId,
        'courseName': courseName,
        'title': title,
        'notifyAt': notifyAt.toUtc().toIso8601String(),
        'deadlineAt': deadlineAt?.toUtc().toIso8601String(),
        'offsets': offsetMinutes,
        if (batchId != null) 'batchId': batchId,
      };
}

class AssignmentReminderPlan {
  const AssignmentReminderPlan({
    required this.snapshots,
    required this.newEvents,
    required this.deadlineEvents,
    required this.knownAssignmentIds,
    required this.baselineCompleted,
  });

  final List<AssignmentReminderSnapshot> snapshots;
  final List<AssignmentReminderEvent> newEvents;
  final List<AssignmentReminderEvent> deadlineEvents;
  final Set<String> knownAssignmentIds;
  final bool baselineCompleted;

  List<Map<String, dynamic>> get snapshotJson =>
      snapshots.map((snapshot) => snapshot.toJson()).toList();

  List<Map<String, dynamic>> get eventJson => [
        ...newEvents.map((event) => event.toJson()),
        ...deadlineEvents.map((event) => event.toJson()),
      ];
}

class AssignmentReminderPlanner {
  const AssignmentReminderPlanner._();

  static AssignmentReminderPlan planAfterSync({
    required String accountHash,
    required int sessionEpoch,
    required List<Assignment> assignments,
    required Set<String> hiddenAssignmentIds,
    required Set<String> unfollowedCourseKeys,
    required Set<String> knownAssignmentIds,
    required Set<String> sentNewAssignmentIds,
    required bool baselineCompleted,
    required bool completeSync,
    required bool detectNewAssignments,
    required bool newAssignmentReminderEnabled,
    required List<int> reminderOffsetsMinutes,
    required DateTime now,
  }) {
    final snapshots = assignments
        .where((assignment) => assignment.isFormal)
        .map((assignment) => AssignmentReminderSnapshot(
              assignment: assignment,
              hidden: hiddenAssignmentIds.contains(assignment.id),
              followed: !unfollowedCourseKeys.contains(assignment.courseKey),
            ))
        .toList()
      ..sort(
          (a, b) => Assignment.compareByDeadline(a.assignment, b.assignment));

    final currentFormalIds =
        snapshots.map((snapshot) => snapshot.assignment.id).toSet();
    final previousKnown = knownAssignmentIds;
    final nextKnown = {...previousKnown, ...currentFormalIds};
    final nextBaseline = baselineCompleted || completeSync;

    final newEvents = <AssignmentReminderEvent>[];
    if (baselineCompleted &&
        detectNewAssignments &&
        newAssignmentReminderEnabled &&
        nextBaseline) {
      final batchId = now.toUtc().microsecondsSinceEpoch.toString();
      for (final snapshot in snapshots) {
        final assignment = snapshot.assignment;
        if (previousKnown.contains(assignment.id) ||
            sentNewAssignmentIds.contains(assignment.id) ||
            !snapshot.eligible ||
            _deadlinePassed(assignment, now)) {
          continue;
        }
        newEvents.add(AssignmentReminderEvent(
          eventId: '$accountHash|${assignment.id}|new',
          type: AssignmentReminderEventType.newAssignment,
          assignmentId: assignment.id,
          courseName: assignment.courseName,
          title: assignment.title,
          notifyAt: now,
          deadlineAt: _trustedDeadline(assignment),
          batchId: batchId,
        ));
      }
    }

    final rawDeadlineEvents = <AssignmentReminderEvent>[];
    for (final snapshot in snapshots) {
      final assignment = snapshot.assignment;
      if (!snapshot.eligible) continue;
      final deadline = _trustedDeadline(assignment);
      if (deadline == null || !deadline.isAfter(now)) continue;
      final byTime = <DateTime, List<int>>{};
      for (final offset in reminderOffsetsMinutes.where((value) => value > 0)) {
        final original = deadline.subtract(Duration(minutes: offset));
        final shifted = original.hour < DaytimeCheckPolicy.startHour
            ? DateTime(
                original.year,
                original.month,
                original.day,
                DaytimeCheckPolicy.startHour,
              )
            : original;
        if (!shifted.isAfter(now) || !shifted.isBefore(deadline)) continue;
        byTime.putIfAbsent(shifted, () => []).add(offset);
      }
      for (final entry in byTime.entries) {
        final offsets = entry.value..sort((a, b) => b.compareTo(a));
        rawDeadlineEvents.add(AssignmentReminderEvent(
          eventId:
              _deadlineEventId(accountHash, assignment.id, deadline, offsets),
          type: AssignmentReminderEventType.deadline,
          assignmentId: assignment.id,
          courseName: assignment.courseName,
          title: assignment.title,
          notifyAt: entry.key,
          deadlineAt: deadline,
          offsetMinutes: List.unmodifiable(offsets),
        ));
      }
    }
    rawDeadlineEvents.sort((a, b) => a.notifyAt.compareTo(b.notifyAt));

    return AssignmentReminderPlan(
      snapshots: snapshots,
      newEvents: newEvents,
      deadlineEvents: rawDeadlineEvents,
      knownAssignmentIds: nextKnown,
      baselineCompleted: nextBaseline,
    );
  }

  static bool _deadlinePassed(Assignment assignment, DateTime now) {
    final deadline = _trustedDeadline(assignment);
    return deadline != null && !deadline.isAfter(now);
  }

  static DateTime? _trustedDeadline(Assignment assignment) =>
      assignment.deadlineTrusted && !assignment.deadlineReadFailed
          ? assignment.deadlineAt
          : null;

  static String _deadlineEventId(
    String accountHash,
    String assignmentId,
    DateTime deadline,
    List<int> offsets,
  ) {
    final offsetKey = offsets.join('-');
    return '$accountHash|$assignmentId|deadline:'
        '${deadline.toUtc().millisecondsSinceEpoch}|$offsetKey';
  }
}

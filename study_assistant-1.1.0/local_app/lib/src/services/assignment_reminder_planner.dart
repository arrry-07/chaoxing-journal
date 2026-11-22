import '../models/assignment.dart';
import '../models/local_coursework_state.dart';
import 'coursework_deadline.dart';
import 'daytime_check_policy.dart';
import 'assignment_query.dart';

enum AssignmentReminderEventType { newAssignment, deadline }

class AssignmentReminderSnapshot {
  const AssignmentReminderSnapshot({
    required this.assignment,
    required this.hidden,
    required this.followed,
    this.courseworkEntry,
  });

  final Assignment assignment;
  final bool hidden;
  final bool followed;
  final LocalCourseworkEntry? courseworkEntry;

  String get eventKind => assignment.isExam ? 'examStart' : 'deadline';

  CourseworkDeadline? get _resolvedDeadline => assignment.isExam
      ? null
      : CourseworkDeadline.resolveEntry(assignment, courseworkEntry);

  // The reminder DTO's historical deadlineAt field carries the event anchor.
  // Assignment.deadlineAt continues to mean the exam's end time.
  DateTime? get anchorAt =>
      assignment.isExam ? assignment.reminderAnchorAt : _resolvedDeadline?.at;

  bool get anchorTrusted => assignment.isExam
      ? assignment.exam!.startTrusted
      : (assignment.deadlineTrusted && !assignment.deadlineReadFailed) ||
          _resolvedDeadline?.isManual == true;

  bool get _anchorReadFailed =>
      !assignment.isExam &&
      assignment.deadlineReadFailed &&
      _resolvedDeadline == null;

  bool get _examCanRemind =>
      !assignment.isExam ||
      (assignment.hasExamIdentity &&
          !assignment.exam!.noticeOnly &&
          assignment.exam!.lifecycle == 'scheduled' &&
          assignment.submitUrl?.isNotEmpty == true);

  bool get _effectivelyCompleted =>
      CourseworkDeadline.isEffectivelyCompletedEntry(
        assignment,
        courseworkEntry,
      );

  bool eligibleAt(DateTime now) {
    if (!assignment.isInAssignmentScope ||
        AssignmentQuery.isArchivedPastTerm(assignment, now) ||
        !assignment.isPendingConfirmed ||
        _effectivelyCompleted ||
        hidden ||
        !followed ||
        !_examCanRemind) {
      return false;
    }
    if (assignment.isExam) {
      return !AssignmentQuery.isExamEnded(assignment, now) &&
          anchorTrusted &&
          anchorAt != null &&
          anchorAt!.isAfter(now);
    }
    final bucket =
        CourseworkDeadline.bucketAt(assignment, now, entry: courseworkEntry);
    return bucket == AssignmentDeadlineBucket.notExpiredWithDeadline ||
        bucket == AssignmentDeadlineBucket.confirmedNoDeadline;
  }

  Map<String, dynamic> toJson() => {
        'assignmentId': assignment.id,
        'courseName': assignment.courseName,
        'title': assignment.title,
        'eventKind': eventKind,
        'deadlineAt': anchorAt?.toUtc().toIso8601String(),
        'deadlineTrusted': anchorTrusted,
        'deadlineReadFailed': _anchorReadFailed,
        'status': assignment.availability == AssignmentAvailability.available &&
                _examCanRemind
            ? assignment.status
            : 'unknown',
        'completed': _effectivelyCompleted,
        'hidden': hidden,
        'followed': followed,
        'formal': assignment.isFormal,
        'inAssignmentScope': assignment.isInAssignmentScope,
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
    this.eventKind = 'deadline',
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
  final String eventKind;

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'type': type.name,
        'eventKind': eventKind,
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
    Set<String>? baselinedSources,
  }) : baselinedSources = baselinedSources ??
            (baselineCompleted ? const {'courseWork'} : const {});

  final List<AssignmentReminderSnapshot> snapshots;
  final List<AssignmentReminderEvent> newEvents;
  final List<AssignmentReminderEvent> deadlineEvents;
  final Set<String> knownAssignmentIds;
  final bool baselineCompleted;
  final Set<String> baselinedSources;

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
    Set<String>? baselinedSources,
    Set<String> completedSourceKeys = const {},
    LocalCourseworkState courseworkState = const LocalCourseworkState.empty(),
  }) {
    final snapshots = assignments
        .where((assignment) => assignment.hasCourseTaskIdentity)
        .map((assignment) => AssignmentReminderSnapshot(
              assignment: assignment,
              hidden: hiddenAssignmentIds.contains(assignment.id),
              followed: !unfollowedCourseKeys.contains(assignment.courseKey),
              courseworkEntry:
                  CourseworkDeadline.entryFor(assignment, courseworkState),
            ))
        .toList()
      ..sort(
          (a, b) => Assignment.compareByDeadline(a.assignment, b.assignment));

    final currentAssignmentIds =
        snapshots.map((snapshot) => snapshot.assignment.id).toSet();
    final previousKnown = knownAssignmentIds;
    final nextKnown = {...previousKnown, ...currentAssignmentIds};
    final previousSources = baselinedSources ??
        (baselineCompleted ? const {'courseWork'} : const <String>{});
    final nextSources = {
      ...previousSources,
      ...completedSourceKeys,
      // Calls predating per-source statistics can complete only the original
      // course-work baseline. An explicit source set opts into source tracking.
      if (baselinedSources == null &&
          completedSourceKeys.isEmpty &&
          completeSync)
        'courseWork',
    };
    final nextBaseline = nextSources.contains('courseWork');

    final newEvents = <AssignmentReminderEvent>[];
    if (detectNewAssignments && newAssignmentReminderEnabled) {
      final batchId = now.toUtc().microsecondsSinceEpoch.toString();
      for (final snapshot in snapshots) {
        final assignment = snapshot.assignment;
        if (!previousSources.contains(assignment.reminderSourceKey) ||
            previousKnown.contains(assignment.id) ||
            sentNewAssignmentIds.contains(assignment.id) ||
            !snapshot.eligibleAt(now) ||
            _deadlinePassed(snapshot, now)) {
          continue;
        }
        newEvents.add(AssignmentReminderEvent(
          eventId: '$accountHash|${assignment.id}|new',
          type: AssignmentReminderEventType.newAssignment,
          assignmentId: assignment.id,
          courseName: assignment.courseName,
          title: assignment.title,
          notifyAt: now,
          deadlineAt: _trustedDeadline(snapshot),
          eventKind: snapshot.eventKind,
          batchId: batchId,
        ));
      }
    }

    final rawDeadlineEvents = <AssignmentReminderEvent>[];
    for (final snapshot in snapshots) {
      final assignment = snapshot.assignment;
      if (!snapshot.eligibleAt(now) ||
          (!assignment.isExam &&
              CourseworkDeadline.bucketAt(
                    assignment,
                    now,
                    entry: snapshot.courseworkEntry,
                  ) !=
                  AssignmentDeadlineBucket.notExpiredWithDeadline)) {
        continue;
      }
      final deadline = _trustedDeadline(snapshot);
      if (deadline == null || !deadline.isAfter(now)) continue;
      final localDeadline = deadline.toLocal();
      final byTime = <DateTime, List<int>>{};
      for (final offset in reminderOffsetsMinutes.where((value) => value > 0)) {
        final original = localDeadline.subtract(Duration(minutes: offset));
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
          eventId: _deadlineEventId(accountHash, assignment.id, deadline,
              offsets, snapshot.eventKind),
          type: AssignmentReminderEventType.deadline,
          assignmentId: assignment.id,
          courseName: assignment.courseName,
          title: assignment.title,
          notifyAt: entry.key,
          deadlineAt: deadline,
          eventKind: snapshot.eventKind,
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
      baselinedSources: Set.unmodifiable(nextSources),
    );
  }

  static bool _deadlinePassed(
      AssignmentReminderSnapshot snapshot, DateTime now) {
    final deadline = _trustedDeadline(snapshot);
    return deadline != null && !deadline.isAfter(now);
  }

  static DateTime? _trustedDeadline(AssignmentReminderSnapshot snapshot) {
    final assignment = snapshot.assignment;
    if (assignment.isExam) return assignment.reminderAnchorAt;
    return CourseworkDeadline.resolveEntry(
      assignment,
      snapshot.courseworkEntry,
    )?.at;
  }

  static String _deadlineEventId(
    String accountHash,
    String assignmentId,
    DateTime deadline,
    List<int> offsets,
    String eventKind,
  ) {
    final offsetKey = offsets.join('-');
    return '$accountHash|$assignmentId|$eventKind:'
        '${deadline.toUtc().millisecondsSinceEpoch}|$offsetKey';
  }
}

import 'assignment.dart';

enum AssignmentChangeKind { published, deadline, status }

class AssignmentChange {
  const AssignmentChange(
      {required this.assignmentId,
      required this.title,
      required this.courseName,
      required this.kind,
      required this.at,
      required this.before,
      required this.after});
  final String assignmentId, title, courseName, before, after;
  final AssignmentChangeKind kind;
  final DateTime at;
  Map<String, dynamic> toJson() => {
        'id': assignmentId,
        'title': title,
        'course': courseName,
        'kind': kind.name,
        'at': at.toUtc().toIso8601String(),
        'before': before,
        'after': after
      };
  factory AssignmentChange.fromJson(Map<String, dynamic> j) => AssignmentChange(
      assignmentId: j['id'] as String,
      title: j['title'] as String,
      courseName: j['course'] as String,
      kind: AssignmentChangeKind.values.byName(j['kind'] as String),
      at: DateTime.parse(j['at'] as String),
      before: j['before'] as String,
      after: j['after'] as String);

  static List<AssignmentChange> compare(List<Assignment> previous,
      List<Assignment> current, Set<String> observedIds, DateTime at) {
    final old = {for (final a in previous) a.id: a};
    final changes = <AssignmentChange>[];
    for (final a in current.where((a) => observedIds.contains(a.id))) {
      final prior = old[a.id];
      void add(AssignmentChangeKind kind, String before, String after) =>
          changes.add(AssignmentChange(
              assignmentId: a.id,
              title: a.title,
              courseName: a.courseName,
              kind: kind,
              at: at,
              before: before,
              after: after));
      if (prior == null) {
        add(AssignmentChangeKind.published, '', '新读取到作业');
        continue;
      }
      if (prior.deadlineTrusted &&
          !prior.deadlineReadFailed &&
          a.deadlineTrusted &&
          !a.deadlineReadFailed &&
          prior.deadlineAt != a.deadlineAt) {
        add(
            AssignmentChangeKind.deadline,
            prior.deadlineAt?.toUtc().toIso8601String() ?? '',
            a.deadlineAt?.toUtc().toIso8601String() ?? '');
      }
      if (prior.statusLabel != a.statusLabel && a.statusLabel != '提交状态未知') {
        add(AssignmentChangeKind.status, prior.statusLabel, a.statusLabel);
      }
    }
    return changes;
  }
}

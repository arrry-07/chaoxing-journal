import '../models/assignment.dart';

/// One read-only coursework identity assembled from original source records.
///
/// Only exams with a fully validated identity are grouped. Every other record
/// remains its own group, so equal titles, dates or incomplete notice metadata
/// can never merge unrelated coursework.
class CourseworkGroup {
  CourseworkGroup({
    required this.key,
    required this.primary,
    required List<Assignment> sources,
    required this.hidden,
  }) : sources = List.unmodifiable(sources);

  final String key;
  final Assignment primary;
  final List<Assignment> sources;
  final bool hidden;

  bool get isExam => primary.isExam;
  int get sourceCount => sources.length;

  String get sourceLabel {
    if (isExam) {
      if (sourceCount > 1) return '考试 · $sourceCount 条来源';
      return primary.exam?.noticeOnly == true ? '考试通知' : '考试';
    }
    return switch (primary.source) {
      AssignmentSource.courseWork => '作业',
      AssignmentSource.classroomActivity => '任务',
      AssignmentSource.exam => '考试',
      AssignmentSource.manual => '个人',
      AssignmentSource.legacyUnknown => '其他来源',
    };
  }
}

class AssignmentGrouping {
  const AssignmentGrouping._();

  /// Validated exam identity shared by display and read-only statistics.
  /// Notices must carry a numeric related exam ID; missing metadata stays
  /// independent.
  static String? examKey(Assignment assignment) {
    if (!assignment.hasExamIdentity) return null;
    final exam = assignment.exam!;
    final course = exam.courseId;
    final clazz = exam.clazzId;
    final examId = exam.noticeOnly ? exam.relatedExamId : exam.examId;
    bool numeric(String? value) =>
        value != null && RegExp(r'^[0-9]+$').hasMatch(value);
    if (!numeric(course) || !numeric(clazz) || !numeric(examId)) return null;
    return 'exam:$course:$clazz:$examId';
  }

  static List<CourseworkGroup> group(
    Iterable<Assignment> records, {
    Set<String> hiddenIds = const {},
  }) {
    final order = <String>[];
    final sourcesByKey = <String, List<Assignment>>{};
    final seenIds = <String>{};
    for (final assignment in records) {
      if (!seenIds.add(assignment.id)) continue;
      final key = examKey(assignment) ?? 'record:${assignment.id}';
      if (!sourcesByKey.containsKey(key)) order.add(key);
      (sourcesByKey[key] ??= <Assignment>[]).add(assignment);
    }
    return [
      for (final key in order)
        CourseworkGroup(
          key: key,
          primary: _primary(sourcesByKey[key]!),
          sources: sourcesByKey[key]!,
          hidden: sourcesByKey[key]!.any(
            (assignment) => hiddenIds.contains(assignment.id),
          ),
        ),
    ];
  }

  static Assignment _primary(List<Assignment> sources) {
    final formal = sources
        .where((assignment) =>
            assignment.isExam && assignment.exam?.noticeOnly != true)
        .toList();
    final candidates = formal.isEmpty ? sources : formal;
    return candidates.reduce(
      (left, right) => left.id.compareTo(right.id) <= 0 ? left : right,
    );
  }
}

import '../models/assignment.dart';
import '../models/course.dart';

/// A course filter entry resolved from the account's full course catalog.
///
/// The home list only offers courses with current unfinished work plus the
/// already selected placeholder, but names and class identifiers come from the
/// full catalog so a remaining same-name class is still identifiable.
class HomeCourseFilterOption {
  const HomeCourseFilterOption({
    required this.courseKey,
    required this.courseId,
    required this.clazzId,
    required this.name,
    required this.showClass,
    required this.showCourseId,
  });

  final String courseKey;
  final String courseId;
  final String clazzId;
  final String name;
  final bool showClass;
  final bool showCourseId;

  String get classLabel =>
      showCourseId ? '班级 $clazzId · 课程 $courseId' : '班级 $clazzId';

  String get label => showClass ? '$name · $classLabel' : name;
}

List<HomeCourseFilterOption> buildHomeCourseFilterOptions({
  required Iterable<Assignment> assignments,
  required Iterable<CourseRef> catalog,
  required Iterable<Assignment> records,
  String? selectedCourseKey,
}) {
  final known = <String, _KnownCourse>{};

  void learn(String? key, String? name, {String? courseId, String? clazzId}) {
    if (key == null || key.isEmpty) return;
    final cleanName = (name ?? '').trim();
    final existing = known[key];
    if (existing != null) {
      if (existing.name.isEmpty && cleanName.isNotEmpty) {
        known[key] = existing.copyWith(name: cleanName);
      }
      return;
    }
    final parts = key.split(':');
    known[key] = _KnownCourse(
      courseId: courseId ?? (parts.isNotEmpty ? parts.first : key),
      clazzId:
          clazzId ?? (parts.length > 1 && parts[1].isNotEmpty ? parts[1] : '—'),
      name: cleanName,
    );
  }

  for (final course in catalog) {
    learn(
      course.key,
      course.name,
      courseId: course.courseId,
      clazzId: course.clazzId,
    );
  }
  for (final record in records) {
    learn(
      record.courseKey,
      record.courseName,
      courseId: record.courseId,
      clazzId: record.clazzId,
    );
  }
  for (final assignment in assignments) {
    learn(
      assignment.courseKey,
      assignment.courseName,
      courseId: assignment.courseId,
      clazzId: assignment.clazzId,
    );
  }

  final nameCounts = <String, int>{};
  final nameClassCounts = <String, int>{};
  for (final course in known.values) {
    final name = _normalized(course.name);
    if (name.isEmpty) continue;
    nameCounts[name] = (nameCounts[name] ?? 0) + 1;
    final nameClass = '$name\u0000${course.clazzId}';
    nameClassCounts[nameClass] = (nameClassCounts[nameClass] ?? 0) + 1;
  }

  final candidateKeys = <String>{
    for (final assignment in assignments)
      if (assignment.courseKey case final key?) key,
  };
  if (selectedCourseKey != null && selectedCourseKey.isNotEmpty) {
    candidateKeys.add(selectedCourseKey);
  }

  final options = <HomeCourseFilterOption>[];
  for (final key in candidateKeys) {
    final course = known[key];
    final name =
        (course?.name.isNotEmpty ?? false) ? course!.name : '已选课程（当前无可显示作业）';
    final clazzId = course?.clazzId ?? '—';
    final courseId = course?.courseId ?? key;
    final normalized = _normalized(name);
    options.add(
      HomeCourseFilterOption(
        courseKey: key,
        courseId: courseId,
        clazzId: clazzId,
        name: name,
        showClass: normalized.isNotEmpty && (nameCounts[normalized] ?? 0) > 1,
        showCourseId: normalized.isNotEmpty &&
            (nameClassCounts['$normalized\u0000$clazzId'] ?? 0) > 1,
      ),
    );
  }
  options.sort((a, b) {
    final byName = _normalized(a.name).compareTo(_normalized(b.name));
    if (byName != 0) return byName;
    final byClass = a.clazzId.compareTo(b.clazzId);
    if (byClass != 0) return byClass;
    final byCourse = a.courseId.compareTo(b.courseId);
    if (byCourse != 0) return byCourse;
    return a.courseKey.compareTo(b.courseKey);
  });
  return List.unmodifiable(options);
}

String _normalized(String value) => value.trim().toLowerCase();

class _KnownCourse {
  const _KnownCourse({
    required this.courseId,
    required this.clazzId,
    required this.name,
  });

  final String courseId;
  final String clazzId;
  final String name;

  _KnownCourse copyWith({String? name}) => _KnownCourse(
        courseId: courseId,
        clazzId: clazzId,
        name: name ?? this.name,
      );
}

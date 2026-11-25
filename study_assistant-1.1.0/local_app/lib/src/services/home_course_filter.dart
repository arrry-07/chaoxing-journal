import '../models/assignment.dart';
import '../models/course.dart';
import '../models/study_notebook.dart';
import 'assignment_query.dart';
import 'course_term_catalog.dart';

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
    this.teacherNames = const [],
    this.termLabel,
    this.archived = false,
    this.recalled = false,
    this.ungrouped = false,
  });

  final String courseKey;
  final String courseId;
  final String clazzId;
  final String name;
  final bool showClass;
  final bool showCourseId;
  final List<String> teacherNames;
  final String? termLabel;
  final bool archived;
  final bool recalled;
  final bool ungrouped;

  String get classLabel =>
      showCourseId ? '班级 $clazzId · 课程 $courseId' : '班级 $clazzId';

  String get teacherLabel => teacherNames.join('、');

  String? get subtitle {
    final statusSuffix = recalled
        ? (termLabel != null && termLabel!.isNotEmpty
            ? '$termLabel · 补修/近期活跃'
            : '补修/近期活跃')
        : archived
            ? (termLabel != null && termLabel!.isNotEmpty
                ? '$termLabel · 已归档'
                : '已归档')
            : (termLabel == null || termLabel!.isEmpty) && ungrouped
                ? '未分组'
                : null;
    final parts = <String>[
      if (showClass) classLabel,
      if (teacherNames.isNotEmpty) teacherLabel,
      if (statusSuffix != null) statusSuffix,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String? get searchKeywords =>
      teacherNames.isEmpty ? null : teacherNames.join(' ');

  String get label => showClass ? '$name · $classLabel' : name;
}

List<HomeCourseFilterOption> buildHomeCourseFilterOptions({
  required Iterable<Assignment> assignments,
  required Iterable<CourseRef> catalog,
  required Iterable<Assignment> records,
  String? selectedCourseKey,
  CourseTermCatalog? termCatalog,
  bool includeIdleCourses = false,
}) {
  final known = <String, _KnownCourse>{};

  void learn(
    String? key,
    String? name, {
    String? courseId,
    String? clazzId,
    List<String> teacherNames = const [],
  }) {
    if (key == null || key.isEmpty) return;
    final cleanName = (name ?? '').trim();
    final existing = known[key];
    if (existing != null) {
      if ((existing.name.isEmpty && cleanName.isNotEmpty) ||
          (existing.teacherNames.isEmpty && teacherNames.isNotEmpty)) {
        known[key] = existing.copyWith(
          name:
              existing.name.isEmpty && cleanName.isNotEmpty ? cleanName : null,
          teacherNames: existing.teacherNames.isEmpty && teacherNames.isNotEmpty
              ? teacherNames
              : null,
        );
      }
      return;
    }
    final parts = key.split(':');
    known[key] = _KnownCourse(
      courseId: courseId ?? (parts.isNotEmpty ? parts.first : key),
      clazzId:
          clazzId ?? (parts.length > 1 && parts[1].isNotEmpty ? parts[1] : '—'),
      name: cleanName,
      teacherNames: teacherNames,
    );
  }

  for (final course in catalog) {
    learn(
      course.key,
      course.name,
      courseId: course.courseId,
      clazzId: course.clazzId,
      teacherNames: course.teacherNames,
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
    if (includeIdleCourses)
      for (final course in catalog)
        if (course.key.isNotEmpty) course.key,
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
    final termEntry = termCatalog?.entryFor(key);
    options.add(
      HomeCourseFilterOption(
        courseKey: key,
        courseId: courseId,
        clazzId: clazzId,
        name: name,
        showClass: normalized.isNotEmpty && (nameCounts[normalized] ?? 0) > 1,
        showCourseId: normalized.isNotEmpty &&
            (nameClassCounts['$normalized\u0000$clazzId'] ?? 0) > 1,
        teacherNames: course?.teacherNames ?? const [],
        termLabel: termEntry?.term?.label,
        archived: termEntry?.state == CourseCatalogState.archived,
        recalled: termEntry?.state == CourseCatalogState.recalled,
        ungrouped: termEntry?.isUngrouped ?? false,
      ),
    );
  }
  options.sort((a, b) {
    final byName = compareNaturalPinyin(a.name, b.name);
    if (byName != 0) return byName;
    final byTeacher = compareNaturalPinyin(a.teacherLabel, b.teacherLabel);
    if (byTeacher != 0) return byTeacher;
    final byClass = a.clazzId.compareTo(b.clazzId);
    if (byClass != 0) return byClass;
    final byCourse = a.courseId.compareTo(b.courseId);
    if (byCourse != 0) return byCourse;
    return a.courseKey.compareTo(b.courseKey);
  });
  return List.unmodifiable(options);
}

/// Counts the items each course would show on Home under the given filters.
///
/// Coursework is matched by course key; manual entries only carry a course
/// name, so they count toward every option with the same normalized name.
Map<String, int> countHomeCourseItems({
  required Iterable<HomeCourseFilterOption> options,
  required Iterable<Assignment> filteredAssignments,
  required Iterable<ManualEntry> filteredManualEntries,
}) {
  final counts = <String, int>{};
  final keys = {for (final option in options) option.courseKey};
  for (final assignment in filteredAssignments) {
    final key = assignment.courseKey;
    if (key == null || !keys.contains(key)) continue;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final manualByName = <String, int>{};
  for (final entry in filteredManualEntries) {
    final name = _normalized(entry.course);
    if (name.isEmpty) continue;
    manualByName[name] = (manualByName[name] ?? 0) + 1;
  }
  for (final option in options) {
    final manual = manualByName[_normalized(option.name)];
    if (manual == null) continue;
    counts[option.courseKey] = (counts[option.courseKey] ?? 0) + manual;
  }
  return counts;
}

/// Courses with items come first (most items first); idle courses follow in
/// the stable name order produced by [buildHomeCourseFilterOptions].
List<HomeCourseFilterOption> sortHomeCourseOptionsByCount(
  List<HomeCourseFilterOption> options,
  Map<String, int> counts,
) {
  final indexed = [
    for (var index = 0; index < options.length; index++)
      (index: index, option: options[index]),
  ];
  indexed.sort((left, right) {
    final leftCount = counts[left.option.courseKey] ?? 0;
    final rightCount = counts[right.option.courseKey] ?? 0;
    final byCount = rightCount.compareTo(leftCount);
    if (byCount != 0) return byCount;
    if (leftCount == 0) {
      final byGrouped = (left.option.ungrouped ? 1 : 0)
          .compareTo(right.option.ungrouped ? 1 : 0);
      if (byGrouped != 0) return byGrouped;
    }
    return left.index.compareTo(right.index);
  });
  return List.unmodifiable([for (final item in indexed) item.option]);
}

String homeCourseCountLabel(int count) => count > 0 ? '$count 项' : '暂无';

String _normalized(String value) => value.trim().toLowerCase();

class _KnownCourse {
  const _KnownCourse({
    required this.courseId,
    required this.clazzId,
    required this.name,
    this.teacherNames = const [],
  });

  final String courseId;
  final String clazzId;
  final String name;
  final List<String> teacherNames;

  _KnownCourse copyWith({String? name, List<String>? teacherNames}) =>
      _KnownCourse(
        courseId: courseId,
        clazzId: clazzId,
        name: name ?? this.name,
        teacherNames: teacherNames ?? this.teacherNames,
      );
}

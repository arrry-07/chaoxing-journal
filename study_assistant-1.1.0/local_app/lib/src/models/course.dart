class CourseRef {
  const CourseRef({
    required this.courseId,
    required this.clazzId,
    required this.name,
    this.teacherNames = const [],
    this.folderName,
    this.clazzName,
    this.courseStartAt,
    this.courseEndAt,
  });

  final String courseId, clazzId, name;
  final List<String> teacherNames;
  final String? folderName;
  final String? clazzName;
  final DateTime? courseStartAt;
  final DateTime? courseEndAt;

  String get key => '$courseId:$clazzId';

  String get teacherLabel => teacherNames.join('、');

  String? get normalizedFolderName {
    final trimmed = folderName?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  String? get normalizedClazzName {
    final trimmed = clazzName?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  bool get hasMetadata =>
      teacherNames.isNotEmpty ||
      normalizedFolderName != null ||
      normalizedClazzName != null ||
      courseStartAt != null ||
      courseEndAt != null;

  CourseRef copyWith({
    String? courseId,
    String? clazzId,
    String? name,
    List<String>? teacherNames,
    String? folderName,
    bool clearFolderName = false,
    String? clazzName,
    bool clearClazzName = false,
    DateTime? courseStartAt,
    bool clearCourseStartAt = false,
    DateTime? courseEndAt,
    bool clearCourseEndAt = false,
  }) =>
      CourseRef(
        courseId: courseId ?? this.courseId,
        clazzId: clazzId ?? this.clazzId,
        name: name ?? this.name,
        teacherNames: teacherNames ?? this.teacherNames,
        folderName: clearFolderName ? null : (folderName ?? this.folderName),
        clazzName: clearClazzName ? null : (clazzName ?? this.clazzName),
        courseStartAt:
            clearCourseStartAt ? null : (courseStartAt ?? this.courseStartAt),
        courseEndAt:
            clearCourseEndAt ? null : (courseEndAt ?? this.courseEndAt),
      );

  CourseRef mergeMissingMetadata(CourseRef fallback) {
    final nextTeachers =
        teacherNames.isNotEmpty ? teacherNames : fallback.teacherNames;
    final nextFolder = normalizedFolderName ?? fallback.normalizedFolderName;
    final nextClazzName = normalizedClazzName ?? fallback.normalizedClazzName;
    final nextStartAt = courseStartAt ?? fallback.courseStartAt;
    final nextEndAt = courseEndAt ?? fallback.courseEndAt;
    if (nextTeachers == teacherNames &&
        nextFolder == normalizedFolderName &&
        nextClazzName == normalizedClazzName &&
        nextStartAt == courseStartAt &&
        nextEndAt == courseEndAt) {
      return this;
    }
    return CourseRef(
      courseId: courseId,
      clazzId: clazzId,
      name: name,
      teacherNames: List.unmodifiable(nextTeachers),
      folderName: nextFolder,
      clazzName: nextClazzName,
      courseStartAt: nextStartAt,
      courseEndAt: nextEndAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'courseId': courseId,
        'clazzId': clazzId,
        'name': name,
        if (teacherNames.isNotEmpty) 'teacherNames': teacherNames,
        if (normalizedFolderName != null) 'folderName': normalizedFolderName,
        if (normalizedClazzName != null) 'clazzName': normalizedClazzName,
        if (courseStartAt != null)
          'courseStartAt': courseStartAt!.toUtc().toIso8601String(),
        if (courseEndAt != null)
          'courseEndAt': courseEndAt!.toUtc().toIso8601String(),
      };

  static List<String> _decodeTeacherNames(dynamic raw) {
    if (raw == null) return const [];
    if (raw is! List) {
      throw const FormatException('课程教师名单格式无效');
    }
    final unique = <String>[];
    final seen = <String>{};
    for (final entry in raw) {
      if (entry is! String) throw const FormatException('课程教师名称格式无效');
      final trimmed = entry.trim();
      if (trimmed.isEmpty || trimmed.length > 80) continue;
      if (seen.add(trimmed)) {
        unique.add(trimmed);
        if (unique.length >= 10) break;
      }
    }
    return List.unmodifiable(unique);
  }

  static String? _decodeBoundedText(dynamic raw, {required String error}) {
    if (raw == null) return null;
    if (raw is! String) throw FormatException(error);
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length > 120 ? trimmed.substring(0, 120) : trimmed;
  }

  static DateTime? _decodeUtcDate(dynamic raw, {required String error}) {
    if (raw == null) return null;
    if (raw is! String) throw FormatException(error);
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed == null || parsed.year < 2000 || parsed.year > 2100) {
      throw FormatException(error);
    }
    return parsed.toUtc();
  }

  factory CourseRef.fromJson(Map<String, dynamic> j) => CourseRef(
        courseId: j['courseId'] as String,
        clazzId: j['clazzId'] as String,
        name: j['name'] as String,
        teacherNames: _decodeTeacherNames(j['teacherNames']),
        folderName: _decodeBoundedText(j['folderName'], error: '课程目录名称格式无效'),
        clazzName: _decodeBoundedText(j['clazzName'], error: '课程班级名称格式无效'),
        courseStartAt: _decodeUtcDate(j['courseStartAt'], error: '课程开始时间格式无效'),
        courseEndAt: _decodeUtcDate(j['courseEndAt'], error: '课程结束时间格式无效'),
      );
}

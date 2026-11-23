class CourseRef {
  const CourseRef({
    required this.courseId,
    required this.clazzId,
    required this.name,
    this.teacherNames = const [],
    this.folderName,
  });

  final String courseId, clazzId, name;
  final List<String> teacherNames;
  final String? folderName;

  String get key => '$courseId:$clazzId';

  String get teacherLabel => teacherNames.join('、');

  String? get normalizedFolderName {
    final trimmed = folderName?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  bool get hasMetadata =>
      teacherNames.isNotEmpty || normalizedFolderName != null;

  CourseRef copyWith({
    String? courseId,
    String? clazzId,
    String? name,
    List<String>? teacherNames,
    String? folderName,
    bool clearFolderName = false,
  }) =>
      CourseRef(
        courseId: courseId ?? this.courseId,
        clazzId: clazzId ?? this.clazzId,
        name: name ?? this.name,
        teacherNames: teacherNames ?? this.teacherNames,
        folderName: clearFolderName ? null : (folderName ?? this.folderName),
      );

  CourseRef mergeMissingMetadata(CourseRef fallback) {
    final nextTeachers =
        teacherNames.isNotEmpty ? teacherNames : fallback.teacherNames;
    final nextFolder = normalizedFolderName ?? fallback.normalizedFolderName;
    if (nextTeachers == teacherNames && nextFolder == normalizedFolderName) {
      return this;
    }
    return CourseRef(
      courseId: courseId,
      clazzId: clazzId,
      name: name,
      teacherNames: List.unmodifiable(nextTeachers),
      folderName: nextFolder,
    );
  }

  Map<String, dynamic> toJson() => {
        'courseId': courseId,
        'clazzId': clazzId,
        'name': name,
        if (teacherNames.isNotEmpty) 'teacherNames': teacherNames,
        if (normalizedFolderName != null) 'folderName': normalizedFolderName,
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

  static String? _decodeFolderName(dynamic raw) {
    if (raw == null) return null;
    if (raw is! String) throw const FormatException('课程目录名称格式无效');
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length > 120 ? trimmed.substring(0, 120) : trimmed;
  }

  factory CourseRef.fromJson(Map<String, dynamic> j) => CourseRef(
        courseId: j['courseId'] as String,
        clazzId: j['clazzId'] as String,
        name: j['name'] as String,
        teacherNames: _decodeTeacherNames(j['teacherNames']),
        folderName: _decodeFolderName(j['folderName']),
      );
}

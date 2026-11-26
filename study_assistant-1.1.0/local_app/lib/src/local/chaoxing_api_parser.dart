import '../models/assignment.dart';
import 'chaoxing_classroom_parser.dart';
import 'chaoxing_param_helper.dart';

class ChaoxingCourseRef {
  const ChaoxingCourseRef({
    required this.courseId,
    required this.clazzId,
    required this.courseName,
    this.cpi,
    this.teacherNames = const [],
    this.folderName,
    this.clazzName,
    this.courseStartAt,
    this.courseEndAt,
  });

  final String courseId;
  final String clazzId;
  final String courseName;
  final String? cpi;
  final List<String> teacherNames;
  final String? folderName;
  final String? clazzName;
  final DateTime? courseStartAt;
  final DateTime? courseEndAt;
}

class ChaoxingApiParser {
  static List<ChaoxingCourseRef> parseCourseRefs(dynamic payload) {
    return parseCourseRefsDetailed(payload).refs;
  }

  static final Set<String> _placeholderTeachers = {
    '-',
    '—',
    '--',
    '无',
    '暂无',
    '未知',
    '待定',
    'null',
    'nil',
    'n/a',
    'na',
  };

  static List<String> _parseTeacherNames(dynamic raw) {
    final tokens = <String>[];
    void addFromString(String text) {
      for (final piece in text.split(RegExp(r'[,，、;；/\r\n]+'))) {
        final trimmed = piece.trim();
        if (trimmed.isEmpty ||
            trimmed.length > 80 ||
            _placeholderTeachers.contains(trimmed.toLowerCase()) ||
            RegExp(r'^\d+$').hasMatch(trimmed)) {
          continue;
        }
        tokens.add(trimmed);
      }
    }

    if (raw is String) {
      addFromString(raw);
    } else if (raw is List) {
      for (final entry in raw) {
        if (entry is String) {
          addFromString(entry);
        }
      }
    }
    if (tokens.isEmpty) return const [];
    final unique = <String>[];
    final seen = <String>{};
    for (final name in tokens) {
      if (seen.add(name)) {
        unique.add(name);
        if (unique.length >= 10) break;
      }
    }
    return List.unmodifiable(unique);
  }

  static ({List<String> names, bool conflicted}) _extractTeachers(
    Map<String, dynamic>? courseData,
    Map<String, dynamic> content,
  ) {
    final target = courseData ?? content;
    final tfNames = _parseTeacherNames(target['teacherfactor']);
    final tnNames = _parseTeacherNames(target['teacherName']);
    if (tfNames.isNotEmpty && tnNames.isNotEmpty) {
      final tfSet = tfNames.toSet();
      final tnSet = tnNames.toSet();
      if (tfSet.length != tnSet.length || !tfSet.containsAll(tnSet)) {
        return (names: const <String>[], conflicted: true);
      }
    }
    return (names: tfNames, conflicted: false);
  }

  static final int _minCourseBoundaryMs =
      DateTime.utc(2000, 1, 1).millisecondsSinceEpoch;
  static final int _maxCourseBoundaryMs =
      DateTime.utc(2100, 12, 31, 23, 59, 59, 999).millisecondsSinceEpoch;

  static DateTime? _parseCourseBoundaryUtc(dynamic raw) {
    if (raw == null) return null;
    DateTime? dt;
    if (raw is num) {
      if (!raw.isFinite || raw <= 0) return null;
      final num msNum = raw < 100000000000 ? raw * 1000 : raw;
      if (!msNum.isFinite ||
          msNum < _minCourseBoundaryMs ||
          msNum > _maxCourseBoundaryMs) {
        return null;
      }
      dt = DateTime.fromMillisecondsSinceEpoch(msNum.truncate(), isUtc: true);
    } else if (raw is String) {
      final text = raw.trim();
      if (text.isEmpty) return null;
      final numeric = num.tryParse(text);
      if (numeric != null) {
        return _parseCourseBoundaryUtc(numeric);
      }
      final dateOnly =
          RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(text);
      if (dateOnly != null) {
        final y = int.parse(dateOnly.group(1)!);
        final m = int.parse(dateOnly.group(2)!);
        final d = int.parse(dateOnly.group(3)!);
        dt = DateTime.utc(y, m, d);
        if (dt.year != y || dt.month != m || dt.day != d) return null;
      } else {
        dt = DateTime.tryParse(text)?.toUtc();
      }
    }
    if (dt == null || dt.year < 2000 || dt.year > 2100) return null;
    return dt.toUtc();
  }

  static DateTime? _firstCourseBoundaryUtc(List<dynamic> candidates) {
    for (final raw in candidates) {
      final parsed = _parseCourseBoundaryUtc(raw);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static ({
    List<ChaoxingCourseRef> refs,
    int rejected,
    int duplicates,
  }) parseCourseRefsDetailed(dynamic payload) {
    final roots = _asMap(payload);
    if (roots == null) {
      return (refs: const <ChaoxingCourseRef>[], rejected: 0, duplicates: 0);
    }

    final channels = _asList(roots['channelList']) ??
        _asList(roots['data']) ??
        _asList(roots['courses']) ??
        const [];
    Iterable<({dynamic item, String? folderName})> flattenChannels(
      List<dynamic> items, {
      String? parentFolder,
    }) sync* {
      const childKeys = ['channelList', 'children', 'childList', 'courseList'];
      for (final item in items) {
        final channel = _asMap(item);
        final content = _asMap(channel?['content']) ?? channel;
        final children = [
          for (final key in childKeys) ...?_asList(channel?[key]),
          if (content != channel)
            for (final key in childKeys) ...?_asList(content?[key]),
        ];
        final markedFolder = content?['folderName'] != null ||
            content?['datatype']?.toString() == '1' ||
            channel?['cataName'] == '文件夹';
        final hasCourse = content?['course'] != null ||
            ChaoxingParamHelper.hasAnyKey(
                content, ChaoxingParamHelper.courseIdKeys) ||
            (!markedFolder &&
                content?['id'] != null &&
                (content?['clazz'] != null ||
                    ChaoxingParamHelper.hasAnyKey(
                        content, ChaoxingParamHelper.clazzIdKeys) ||
                    channel?['key'] != null));
        final isFolder = markedFolder ||
            childKeys.any((key) =>
                _asList(channel?[key]) != null ||
                _asList(content?[key]) != null);
        final ownFolder =
            _stringValue(content?['folderName'] ?? channel?['folderName']) ??
                ((markedFolder || (isFolder && !hasCourse))
                    ? _stringValue(content?['name'] ?? channel?['name'])
                    : null);
        final nextFolder = ownFolder ?? parentFolder;
        if (hasCourse || !isFolder) {
          yield (item: item, folderName: isFolder ? nextFolder : parentFolder);
        }
        if (children.isNotEmpty) {
          yield* flattenChannels(children, parentFolder: nextFolder);
        }
      }
    }

    final courses = <ChaoxingCourseRef>[];
    final indexByKey = <String, int>{};
    final foldersByKey = <String, Set<String>>{};
    final clazzNamesByKey = <String, Set<String>>{};
    final startAtsByKey = <String, Set<int>>{};
    final endAtsByKey = <String, Set<int>>{};
    final teacherSignaturesByKey = <String, Set<String>>{};
    final teacherConflictKeys = <String>{};
    var rejected = 0;
    var duplicates = 0;
    for (final entry in flattenChannels(channels)) {
      final channel = _asMap(entry.item);
      if (channel == null) {
        rejected++;
        continue;
      }
      final content = _asMap(channel['content']) ?? channel;
      final courseData =
          _firstMapFrom(content['course']) ?? _asMap(content['course']);
      final clazzData =
          _firstMapFrom(content['clazz']) ?? _asMap(content['clazz']);
      final courseAlias = ChaoxingParamHelper.singleMapValue(
          content, ChaoxingParamHelper.courseIdKeys);
      final clazzAlias = ChaoxingParamHelper.singleMapValue(
          content, ChaoxingParamHelper.clazzIdKeys);
      if ((courseAlias == null &&
              ChaoxingParamHelper.hasAnyKey(
                  content, ChaoxingParamHelper.courseIdKeys)) ||
          (clazzAlias == null &&
              ChaoxingParamHelper.hasAnyKey(
                  content, ChaoxingParamHelper.clazzIdKeys))) {
        rejected++;
        continue;
      }

      final courseId = _stringValue(courseData?['id'] ??
          courseAlias ??
          (courseData == null ? content['id'] : null));
      final clazzId =
          _stringValue(clazzData?['id'] ?? channel['key'] ?? clazzAlias);
      final courseName = _stringValue(
        courseData?['name'] ??
            courseData?['courseName'] ??
            content['name'] ??
            content['courseName'] ??
            channel['name'],
      );
      if (courseId == null ||
          clazzId == null ||
          courseName == null ||
          courseName.isEmpty) {
        rejected++;
        continue;
      }

      final rawClazzCandidate = courseData != null
          ? _stringValue(
              clazzData?['name'] ??
                  clazzData?['clazzName'] ??
                  content['clazzName'] ??
                  content['name'],
            )
          : _stringValue(
              clazzData?['name'] ??
                  clazzData?['clazzName'] ??
                  content['clazzName'],
            );
      final String? rawClazzName =
          (rawClazzCandidate == null || rawClazzCandidate == courseName)
              ? null
              : (rawClazzCandidate.length > 120
                  ? rawClazzCandidate.substring(0, 120)
                  : rawClazzCandidate);
      final courseStartAt = _firstCourseBoundaryUtc([
        clazzData?['begindate'],
        clazzData?['startTime'],
        clazzData?['startdate'],
        courseData?['begindate'],
        courseData?['startTime'],
        courseData?['startdate'],
        content['begindate'],
        content['startTime'],
        content['startdate'],
        clazzData?['createtime'],
        clazzData?['createTime'],
        content['createtime'],
        content['createTime'],
        channel['createtime'],
        channel['createTime'],
      ]);
      final courseEndAt = _firstCourseBoundaryUtc([
        courseData?['enddate'],
        courseData?['endTime'],
        content['enddate'],
        content['endTime'],
      ]);

      final key = '$courseId:$clazzId';
      final teacherInfo = _extractTeachers(courseData, content);
      final folders = foldersByKey.putIfAbsent(key, () => <String>{});
      if (entry.folderName != null && entry.folderName!.isNotEmpty) {
        folders.add(entry.folderName!);
      }
      final clazzNames = clazzNamesByKey.putIfAbsent(key, () => <String>{});
      if (rawClazzName != null) {
        clazzNames.add(rawClazzName);
      }
      final startAts = startAtsByKey.putIfAbsent(key, () => <int>{});
      if (courseStartAt != null) {
        startAts.add(courseStartAt.millisecondsSinceEpoch);
      }
      final endAts = endAtsByKey.putIfAbsent(key, () => <int>{});
      if (courseEndAt != null) {
        endAts.add(courseEndAt.millisecondsSinceEpoch);
      }
      if (teacherInfo.conflicted) {
        teacherConflictKeys.add(key);
      } else if (teacherInfo.names.isNotEmpty) {
        final sig = (teacherInfo.names.toList()..sort()).join('\u0000');
        teacherSignaturesByKey.putIfAbsent(key, () => <String>{}).add(sig);
      }

      final existingIdx = indexByKey[key];
      if (existingIdx != null) {
        duplicates++;
        final existing = courses[existingIdx];
        final resolvedFolder = folders.length == 1 ? folders.single : null;
        final resolvedClazzName =
            clazzNames.length == 1 ? clazzNames.single : null;
        final resolvedStartAt = startAts.length == 1
            ? DateTime.fromMillisecondsSinceEpoch(startAts.single, isUtc: true)
            : null;
        final resolvedEndAt = endAts.length == 1
            ? DateTime.fromMillisecondsSinceEpoch(endAts.single, isUtc: true)
            : null;
        final teacherConflict = teacherConflictKeys.contains(key) ||
            (teacherSignaturesByKey[key]?.length ?? 0) > 1;
        final resolvedTeachers = teacherConflict
            ? const <String>[]
            : existing.teacherNames.isNotEmpty
                ? existing.teacherNames
                : teacherInfo.names;
        courses[existingIdx] = ChaoxingCourseRef(
          courseId: existing.courseId,
          clazzId: existing.clazzId,
          courseName: existing.courseName,
          cpi: existing.cpi,
          teacherNames: resolvedTeachers,
          folderName: resolvedFolder,
          clazzName: resolvedClazzName,
          courseStartAt: resolvedStartAt,
          courseEndAt: resolvedEndAt,
        );
        continue;
      }

      indexByKey[key] = courses.length;
      courses.add(
        ChaoxingCourseRef(
          courseId: courseId,
          clazzId: clazzId,
          courseName: courseName,
          cpi: _stringValue(content['cpi'] ?? channel['cpi']),
          teacherNames:
              teacherInfo.conflicted ? const <String>[] : teacherInfo.names,
          folderName: entry.folderName,
          clazzName: rawClazzName,
          courseStartAt: courseStartAt,
          courseEndAt: courseEndAt,
        ),
      );
    }
    return (refs: courses, rejected: rejected, duplicates: duplicates);
  }

  static List<Assignment> parseActivityAssignments(
    dynamic payload,
    ChaoxingCourseRef course, {
    DateTime? now,
  }) {
    final root = _asMap(payload);
    final data = _asMap(root?['data']) ?? root;
    final rows = _asList(data?['activeList']) ?? const [];
    return [
      for (final type in [35, 42, 77])
        ...ChaoxingClassroomParser.parseActivities(rows,
            courseId: course.courseId,
            clazzId: course.clazzId,
            courseName: course.courseName,
            activityType: type,
            now: now),
    ];
  }
  // ---------- Exam parsing ----------

  static List<Assignment> parseActivityExamAssignments(
    dynamic payload,
    ChaoxingCourseRef course, {
    DateTime? now,
  }) {
    final parsedAt = now ?? DateTime.now();
    final root = _asMap(payload);
    if (root == null) {
      return [];
    }

    final data = _asMap(root['data']) ?? root;
    final activities = _asList(data['activeList']) ??
        _asList(data['list']) ??
        _asList(data['activities']) ??
        const [];
    final assignments = <Assignment>[];
    for (final item in activities) {
      final activity = _asMap(item);
      if (activity == null || !_looksLikeExam(activity)) {
        continue;
      }
      final id = _stringValue(
        activity['id'] ?? activity['activeId'] ?? activity['aid'],
      );
      final title = _stringValue(
        activity['nameOne'] ??
            activity['name'] ??
            activity['title'] ??
            activity['activeName'],
      );
      final examDate = _examTimeFrom(activity);
      if (id == null || title == null || title.isEmpty || examDate == null) {
        continue;
      }
      // Skip exams that are more than 30 days in the past
      if (examDate.isBefore(parsedAt.subtract(const Duration(days: 30)))) {
        continue;
      }

      final location = _stringValue(
        activity['location'] ??
            activity['address'] ??
            activity['place'] ??
            activity['examPlace'],
      );

      final durationStr = _stringValue(
        activity['duration'] ??
            activity['examDuration'] ??
            activity['timeLong'],
      );
      final durationMinutes =
          durationStr != null ? int.tryParse(durationStr) : null;

      assignments.add(
        Assignment(
          id: 'cx:exam:${course.courseId}:${course.clazzId}:$id',
          courseName: course.courseName,
          title: title,
          deadlineAt: examDate,
          requirementsText: _examRequirementsText(
            title: title,
            location: location,
            durationMinutes: durationMinutes,
            notes: _stringValue(activity['remark'] ?? activity['description']),
          ),
          status: _personalStatus(activity),
          submitUrl: _activityUrl(course, id),
          lastSyncedAt: parsedAt,
        ),
      );
    }
    return assignments;
  }

  static String _personalStatus(Map<String, dynamic> activity) {
    final personal = _stringValue(
        activity['submitStatusName'] ?? activity['answerStatusName']);
    if (personal != null) return Assignment.statusFromChaoxing(personal, null);
    final label = _stringValue(activity['statusName'] ??
        activity['stateName'] ??
        activity['statusText']);
    // Lifecycle labels such as 已结束 and 已完成 may describe the activity itself.
    // A generic status field must explicitly describe submitting or grading.
    if (label == null ||
        !RegExp(r'提交|批阅|批改|退回|打回|重做|已交|未交|互评|submitted|graded|reviewing|returned',
                caseSensitive: false)
            .hasMatch(label)) {
      return 'unknown';
    }
    return Assignment.statusFromChaoxing(label, null);
  }

  static bool _looksLikeExam(Map<String, dynamic> activity) {
    final type = _stringValue(
      activity['activeType'] ?? activity['type'] ?? activity['activeTypeName'],
    );
    final name = _stringValue(
          activity['nameOne'] ??
              activity['name'] ??
              activity['title'] ??
              activity['activeName'],
        ) ??
        '';
    // Exam activity types in Chaoxing: 49 is typically exam
    if (name.contains('考试') ||
        name.contains('考核') ||
        name.contains('期末') ||
        name.contains('期中') ||
        name.toLowerCase().contains('exam')) {
      return true;
    }
    // Activity type 49 is exam, 50 is some variants
    return const {'49', '50'}.contains(type);
  }

  // ---------- Shared ----------

  static DateTime? _deadlineFrom(Map<String, dynamic> activity) {
    final raw = _stringValue(
      activity['endTime'] ??
          activity['deadline'] ??
          activity['deadlineAt'] ??
          activity['endtime'] ??
          activity['endTimeStr'] ??
          activity['endDate'],
    );
    if (raw == null || raw.isEmpty || raw == '0') {
      return null;
    }

    final iso = DateTime.tryParse(raw);
    if (iso != null) {
      return iso.toLocal();
    }

    final millis = int.tryParse(raw);
    if (millis != null) {
      final value = millis > 100000000000 ? millis : millis * 1000;
      return DateTime.fromMillisecondsSinceEpoch(value);
    }

    final normalized = raw
        .replaceAll('年', '-')
        .replaceAll('月', '-')
        .replaceAll('日', '')
        .replaceAll('/', '-')
        .trim();
    final match = RegExp(
      r'(20\d{2})-(\d{1,2})-(\d{1,2})(?:\s+|T)(\d{1,2}):(\d{2})(?::(\d{2}))?',
    ).firstMatch(normalized);
    if (match == null) {
      return null;
    }
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6) ?? '0'),
    );
  }

  static DateTime? _examTimeFrom(Map<String, dynamic> activity) {
    final examSpecific = _stringValue(
      activity['examTime'] ??
          activity['examStartTime'] ??
          activity['startTime'] ??
          activity['beginTime'] ??
          activity['startDate'],
    );
    if (examSpecific != null &&
        examSpecific.isNotEmpty &&
        examSpecific != '0') {
      return _parseDateTime(examSpecific);
    }
    return _deadlineFrom(activity);
  }

  static DateTime? _parseDateTime(String raw) {
    final iso = DateTime.tryParse(raw);
    if (iso != null) {
      return iso.toLocal();
    }
    final millis = int.tryParse(raw);
    if (millis != null) {
      final value = millis > 100000000000 ? millis : millis * 1000;
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    final normalized = raw
        .replaceAll('年', '-')
        .replaceAll('月', '-')
        .replaceAll('日', '')
        .replaceAll('/', '-')
        .trim();
    final match = RegExp(
      r'(20\d{2})-(\d{1,2})-(\d{1,2})(?:\s+|T)(\d{1,2}):(\d{2})(?::(\d{2}))?',
    ).firstMatch(normalized);
    if (match == null) {
      return null;
    }
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6) ?? '0'),
    );
  }

  static String _activityUrl(ChaoxingCourseRef course, String activeId) {
    return Uri.https('mobilelearn.chaoxing.com', '/widget/pcpick/stu/index', {
      'courseid': course.courseId,
      'jclassId': course.clazzId,
      'activeId': activeId,
      if (course.cpi != null) 'cpi': course.cpi!,
    }).toString();
  }

  static String _examRequirementsText({
    required String title,
    String? location,
    int? durationMinutes,
    String? notes,
  }) {
    final parts = <String>[
      '考试：$title',
      if (location != null && location.isNotEmpty) '地点：$location',
      if (durationMinutes != null) '时长：$durationMinutes 分钟',
      if (notes != null && notes.isNotEmpty) notes,
    ];
    return parts.join('\n');
  }

  static Map<String, dynamic>? _firstMapFrom(dynamic value) {
    final map = _asMap(value);
    if (map != null) {
      final data = _asList(map['data']);
      if (data != null && data.isNotEmpty) {
        return _asMap(data.first);
      }
      return map;
    }
    final list = _asList(value);
    if (list != null && list.isNotEmpty) {
      return _asMap(list.first);
    }
    return null;
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  static List<dynamic>? _asList(dynamic value) => value is List ? value : null;

  static String? _stringValue(dynamic value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}

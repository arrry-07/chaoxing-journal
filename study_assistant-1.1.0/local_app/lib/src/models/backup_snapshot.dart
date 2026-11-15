import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'assignment.dart';
import 'course.dart';
import 'personal_workspace.dart';
import 'reminder_rule_limits.dart';
import 'study_notebook.dart';

/// Portable, explicitly validated data only. Session and signed links never enter
/// this format; decoded records are still historical observations, not a sync.
class BackupSnapshot {
  BackupSnapshot._(
      this.owner,
      this.createdAt,
      List<Assignment> records,
      Set<String> hidden,
      List<CourseRef> courses,
      Set<String> unfollowed,
      List<int> reminderOffsets,
      this.autoSyncIntervalMinutes,
      this.personal,
      this.notebook,
      Map<String, String> courseTaskKeys)
      : records = List.unmodifiable(records),
        hidden = Set.unmodifiable(hidden),
        courses = List.unmodifiable(courses),
        unfollowed = Set.unmodifiable(unfollowed),
        reminderOffsets = List.unmodifiable(reminderOffsets),
        courseTaskKeys = Map.unmodifiable(courseTaskKeys);

  static const maxPlaintextBytes = 8 * 1024 * 1024;
  final String owner;
  final DateTime createdAt;
  final List<Assignment> records;
  final Set<String> hidden;
  final List<CourseRef> courses;
  final Set<String> unfollowed;
  final List<int> reminderOffsets;
  final int autoSyncIntervalMinutes;
  final PersonalWorkspace personal;
  final StudyNotebook notebook;
  final Map<String, String> courseTaskKeys;
  static String ownerFor(String account) =>
      sha256.convert(utf8.encode(account.trim())).toString();

  static Map<String, dynamic> _record(Assignment a, String? retainedKey) {
    return {
      'id': a.id,
      'source': a.source.name,
      'activityType': a.activityType,
      'availability': a.availability.name,
      'exam': a.exam?.toJson(),
      'courseTaskKey': a.source == AssignmentSource.classroomActivity
          ? a.courseTaskKey ?? retainedKey
          : null,
      'courseName': a.courseName,
      'title': a.title,
      // Server descriptions may embed signed links as plain text or HTML.
      // Re-fetch the source body after restore instead of exporting access data.
      'requirementsText': '',
      'status': a.status,
      'deadlineAt': a.deadlineAt?.toUtc().toIso8601String(),
      'completedAt': a.completedAt?.toUtc().toIso8601String(),
      'lastSyncedAt': a.lastSyncedAt.toUtc().toIso8601String(),
    };
  }

  /// Validate a portable activity identity without inferring it from a title.
  static bool isValidCourseTaskKey(Assignment record, Object? key) =>
      record.source == AssignmentSource.classroomActivity &&
      key is String &&
      record.copyWith(id: key, clearSubmitUrl: true).courseTaskKey == key &&
      (record.courseTaskKey == null || record.courseTaskKey == key);

  factory BackupSnapshot.create(
          {required String owner,
          required DateTime createdAt,
          required List<Assignment> records,
          required Set<String> hidden,
          required List<CourseRef> courses,
          required Set<String> unfollowed,
          required List<int> reminderOffsets,
          required int autoSyncIntervalMinutes,
          Map<String, String> courseTaskKeys = const {},
          PersonalWorkspace? personal,
          StudyNotebook? notebook}) =>
      BackupSnapshot.decode(jsonEncode({
        'schema': 5,
        'notebook': (notebook ?? StudyNotebook()).toJson(),
        'personal': (personal ?? PersonalWorkspace()).toJson(portable: true),
        'owner': owner,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'records':
            records.map((a) => _record(a, courseTaskKeys[a.id])).toList(),
        'hidden': hidden.toList(),
        'courses': courses.map((c) => c.toJson()).toList(),
        'unfollowed': unfollowed.toList(),
        'reminderOffsets': reminderOffsets,
        'autoSyncIntervalMinutes': autoSyncIntervalMinutes,
      }));

  String encode() => jsonEncode({
        'schema': 5,
        'notebook': notebook.toJson(),
        'personal': personal.toJson(portable: true),
        'owner': owner,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'records':
            records.map((a) => _record(a, courseTaskKeys[a.id])).toList(),
        'hidden': hidden.toList(),
        'courses': courses.map((c) => c.toJson()).toList(),
        'unfollowed': unfollowed.toList(),
        'reminderOffsets': reminderOffsets,
        'autoSyncIntervalMinutes': autoSyncIntervalMinutes,
      });

  static Never _bad() => throw const FormatException('备份文件格式不受支持或数据损坏');
  static Map<String, dynamic> _map(dynamic v, Set<String> keys) {
    if (v is! Map<String, dynamic> ||
        v.length != keys.length ||
        !keys.every(v.containsKey)) {
      _bad();
    }
    return v;
  }

  static String _text(dynamic v, {int max = 500, bool empty = false}) {
    if (v is! String || v.length > max || (!empty && v.trim().isEmpty)) _bad();
    return v;
  }

  static List<dynamic> _list(dynamic v, {int max = 20000}) {
    if (v is! List || v.length > max) _bad();
    return v;
  }

  static DateTime _date(dynamic v) {
    final s = _text(v, max: 40);
    final d = DateTime.tryParse(s);
    if (!Assignment.hasExplicitTimeZone(s) ||
        d == null ||
        d.year < 1970 ||
        d.year > 2200 ||
        d.toUtc().toIso8601String() != s) {
      _bad();
    }
    return d.toLocal();
  }

  static Set<String> _strings(dynamic v) {
    final list = _list(v).map((s) => _text(s)).toList();
    if (list.toSet().length != list.length) _bad();
    return list.toSet();
  }

  static BackupSnapshot decode(String plaintext) {
    if (plaintext.length > maxPlaintextBytes ||
        utf8.encode(plaintext).length > maxPlaintextBytes) {
      _bad();
    }
    final decoded = jsonDecode(plaintext);
    final version = decoded is Map ? decoded['schema'] : null;
    if (version is! int || !{1, 2, 3, 4, 5}.contains(version)) _bad();
    final j = _map(decoded, {
      if (version >= 2) 'personal',
      if (version >= 3) 'notebook',
      'schema',
      'owner',
      'createdAt',
      'records',
      'hidden',
      'courses',
      'unfollowed',
      'reminderOffsets',
      'autoSyncIntervalMinutes'
    });
    final owner = _text(j['owner'], max: 64);
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(owner)) _bad();
    final records = <Assignment>[];
    final courseTaskKeys = <String, String>{};
    for (final value in _list(j['records'])) {
      final r = _map(value, {
        if (version >= 4) 'activityType',
        if (version >= 4) 'availability',
        if (version >= 4) 'courseTaskKey',
        if (version >= 5) 'exam',
        'id',
        'source',
        'courseName',
        'title',
        'requirementsText',
        'status',
        'deadlineAt',
        'completedAt',
        'lastSyncedAt'
      });
      final source = AssignmentSource.values
          .where((s) => s.name == r['source'])
          .firstOrNull;
      final activityType = version >= 4 ? r['activityType'] : null;
      final availability = version >= 4
          ? AssignmentAvailability.values
              .where((v) => v.name == r['availability'])
              .firstOrNull
          : AssignmentAvailability.available;
      if ((activityType != null && activityType is! int) ||
          availability == null) {
        _bad();
      }
      if (source == null ||
          !{
            'pending',
            'overdue',
            'returned',
            'unknown',
            'submitted',
            'completed',
            'reviewing',
            'graded'
          }.contains(r['status'])) {
        _bad();
      }
      var record = Assignment(
          id: _text(r['id']),
          source: source,
          exam: version >= 5 ? _exam(r['exam']) : null,
          activityType: activityType,
          availability: availability,
          courseName: _text(r['courseName']),
          title: _text(r['title'], max: 2000),
          requirementsText:
              _text(r['requirementsText'], max: 20000, empty: true),
          status: r['status'] as String,
          deadlineAt: r['deadlineAt'] == null ? null : _date(r['deadlineAt']),
          completedAt:
              r['completedAt'] == null ? null : _date(r['completedAt']),
          lastSyncedAt: _date(r['lastSyncedAt']),
          deadlineTrusted: false);
      if (record.exam != null &&
          (source != AssignmentSource.exam || !record.hasExamIdentity)) {
        _bad();
      }
      final taskKey = version >= 4 ? r['courseTaskKey'] : null;
      if (taskKey != null) {
        if (!isValidCourseTaskKey(record, taskKey)) _bad();
        courseTaskKeys[record.id] = _text(taskKey);
        record = record.copyWith(persistedCourseTaskKey: _text(taskKey));
      }
      records.add(record);
    }
    final ids = records.map((r) => r.id).toSet();
    if (ids.length != records.length) _bad();
    final hidden = _strings(j['hidden']);
    if (!hidden.every(ids.contains)) _bad();
    final courses = <CourseRef>[];
    for (final value in _list(j['courses'], max: 2000)) {
      final c = _map(value, {'courseId', 'clazzId', 'name'});
      courses.add(CourseRef(
          courseId: _text(c['courseId']),
          clazzId: _text(c['clazzId']),
          name: _text(c['name'])));
    }
    if (courses.map((c) => c.key).toSet().length != courses.length) _bad();
    final offsets =
        _list(j['reminderOffsets'], max: ReminderRuleLimits.maxLegacyRuleCount);
    if (offsets.any((v) =>
            v is! int ||
            v <= 0 ||
            v > ReminderRuleLimits.maxLegacyOffsetMinutes) ||
        offsets.toSet().length != offsets.length) {
      _bad();
    }
    final interval = j['autoSyncIntervalMinutes'];
    if (interval is! int || interval < 0 || interval > 1440) _bad();
    return BackupSnapshot._(
        owner,
        _date(j['createdAt']),
        records,
        hidden,
        courses,
        _strings(j['unfollowed']),
        offsets.cast<int>(),
        interval,
        version == 1
            ? PersonalWorkspace()
            : PersonalWorkspace.fromJson(j['personal']),
        version < 3
            ? StudyNotebook()
            : StudyNotebook.decode(jsonEncode(j['notebook'])),
        courseTaskKeys);
  }

  static ExamInfo? _exam(dynamic value) {
    if (value == null) return null;
    final e = _map(value, {
      'examId',
      'courseId',
      'clazzId',
      'startAt',
      'endAt',
      'startTrusted',
      'endTrusted',
      'durationMinutes',
      'location',
      'lifecycle',
      'noticeOnly',
    });
    String? identity(dynamic v) {
      if (v == null) return null;
      final text = _text(v);
      if (text.contains(':') ||
          text != text.trim() ||
          RegExp(r'[\s\x00-\x1f]').hasMatch(text)) {
        _bad();
      }
      return text;
    }

    final examId = identity(e['examId']);
    if (examId == null ||
        e['startTrusted'] is! bool ||
        e['endTrusted'] is! bool ||
        e['noticeOnly'] is! bool ||
        !const {'scheduled', 'inProgress', 'ended', 'cancelled', 'unknown'}
            .contains(e['lifecycle'])) {
      _bad();
    }
    final start = e['startAt'] == null ? null : _date(e['startAt']);
    final end = e['endAt'] == null ? null : _date(e['endAt']);
    final duration = e['durationMinutes'];
    if ((start != null && end != null && end.isBefore(start)) ||
        (e['startTrusted'] == true && start == null) ||
        (e['endTrusted'] == true && end == null) ||
        (duration != null && (duration is! int || duration <= 0))) {
      _bad();
    }
    return ExamInfo(
      examId: examId,
      courseId: identity(e['courseId']),
      clazzId: identity(e['clazzId']),
      startAt: start,
      endAt: end,
      // A portable observation has no live personal state or safe entry.
      startTrusted: false,
      endTrusted: false,
      durationMinutes: duration as int?,
      location: _text(e['location'], max: 2000, empty: true),
      lifecycle: e['lifecycle'] as String,
      noticeOnly: e['noticeOnly'] as bool,
    );
  }
}

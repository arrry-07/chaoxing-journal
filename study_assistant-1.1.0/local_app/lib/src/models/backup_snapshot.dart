import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'assignment.dart';
import 'course.dart';
import 'course_chapter_progress.dart';
import 'course_notice.dart';
import 'course_term_preferences.dart';
import 'local_coursework_state.dart';
import 'personal_workspace.dart';
import 'pinned_assignments.dart';
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
      Map<String, String> courseTaskKeys,
      this.notices,
      this.chapters,
      this.pinned,
      this.courseworkState,
      this.courseTermPreferences)
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
  final CourseNoticeCollection notices;
  final CourseChapterCatalog chapters;
  final PinnedAssignments pinned;
  final LocalCourseworkState courseworkState;
  final CourseTermPreferences courseTermPreferences;
  static String ownerFor(String account) =>
      sha256.convert(utf8.encode(account.trim())).toString();

  static final RegExp _portableStartTextPattern = RegExp(
      r'^(?:20\d{2}[-/年])?\d{1,2}[-/月]\d{1,2}日?\s+\d{1,2}[:：]\d{2}(?:[:：]\d{2})?$');
  static const _maxStartTextLength = 40;

  static bool _isPortableStartText(String value) =>
      value.length <= _maxStartTextLength &&
      value == value.trim() &&
      _portableStartTextPattern.hasMatch(value);

  static String? _portableStartText(String? value) =>
      value != null && _isPortableStartText(value) ? value : null;

  static bool _hasPortableTimeEvidence(Assignment record) =>
      record.publishedAt != null ||
      record.availableFromAt != null ||
      _portableStartText(record.availableFromText) != null;

  static int _schemaVersion(
    List<Assignment> records,
    CourseNoticeCollection notices,
    CourseChapterCatalog chapters,
    PinnedAssignments pinned,
    LocalCourseworkState courseworkState,
    List<CourseRef> courses,
    CourseTermPreferences courseTermPreferences,
  ) {
    if (courses.any((c) => c.hasMetadata) || courseTermPreferences.isNotEmpty) {
      return 9;
    }
    if (pinned.isNotEmpty ||
        pinned.manuallyOrdered ||
        courseworkState.isNotEmpty) {
      return 8;
    }
    if (records.any(_hasPortableTimeEvidence)) return 7;
    if (notices.items.isNotEmpty || chapters.byCourse.isNotEmpty) return 6;
    return 5;
  }

  static Map<String, dynamic> _record(
    Assignment a,
    String? retainedKey, {
    required bool includeTimeEvidence,
  }) {
    // Portable backups keep strict schema 5/6/7 exam keys and re-derive
    // yearless notice anchors on live re-sync without promoting restored trust.
    final examJson = a.exam?.toJson();
    examJson?.remove('noticeStartAt');
    examJson?.remove('noticeEndAt');
    return {
      'id': a.id,
      'source': a.source.name,
      'activityType': a.activityType,
      'availability': a.availability.name,
      'exam': examJson,
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
      if (includeTimeEvidence)
        'publishedAt': a.publishedAt?.toUtc().toIso8601String(),
      if (includeTimeEvidence)
        'availableFromAt': a.availableFromAt?.toUtc().toIso8601String(),
      if (includeTimeEvidence)
        'availableFromText': _portableStartText(a.availableFromText),
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
      StudyNotebook? notebook,
      CourseNoticeCollection? notices,
      CourseChapterCatalog? chapters,
      PinnedAssignments? pinned,
      LocalCourseworkState? courseworkState,
      CourseTermPreferences? courseTermPreferences}) {
    final effectiveNotices = notices ?? CourseNoticeCollection();
    final effectiveChapters = chapters ?? CourseChapterCatalog();
    final effectivePinned = pinned ?? const PinnedAssignments.empty();
    final effectiveCoursework =
        courseworkState ?? const LocalCourseworkState.empty();
    final effectiveTermPrefs =
        courseTermPreferences ?? const CourseTermPreferences.empty();
    final version = _schemaVersion(
      records,
      effectiveNotices,
      effectiveChapters,
      effectivePinned,
      effectiveCoursework,
      courses,
      effectiveTermPrefs,
    );
    return BackupSnapshot.decode(jsonEncode({
      'schema': version,
      'notebook': (notebook ?? StudyNotebook()).toJson(portable: true),
      'personal': (personal ?? PersonalWorkspace()).toJson(portable: true),
      if (version >= 6) 'notices': effectiveNotices.toJson(portable: true),
      if (version >= 6) 'chapters': effectiveChapters.toJson(portable: true),
      if (version >= 8) 'pinned': effectivePinned.toJson(),
      if (version >= 8 && effectiveCoursework.isNotEmpty)
        'courseworkState': effectiveCoursework.toJson(),
      if (version >= 9 && effectiveTermPrefs.isNotEmpty)
        'courseTermPreferences': effectiveTermPrefs.toJson(),
      'owner': owner,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'records': records
          .map((a) => _record(a, courseTaskKeys[a.id],
              includeTimeEvidence: version >= 7))
          .toList(),
      'hidden': hidden.toList(),
      'courses': courses.map((c) => c.toJson()).toList(),
      'unfollowed': unfollowed.toList(),
      'reminderOffsets': reminderOffsets,
      'autoSyncIntervalMinutes': autoSyncIntervalMinutes,
    }));
  }

  String encode() {
    final version = _schemaVersion(
      records,
      notices,
      chapters,
      pinned,
      courseworkState,
      courses,
      courseTermPreferences,
    );
    return jsonEncode({
      'schema': version,
      'notebook': notebook.toJson(portable: true),
      'personal': personal.toJson(portable: true),
      if (version >= 6) 'notices': notices.toJson(portable: true),
      if (version >= 6) 'chapters': chapters.toJson(portable: true),
      if (version >= 8) 'pinned': pinned.toJson(),
      if (version >= 8 && courseworkState.isNotEmpty)
        'courseworkState': courseworkState.toJson(),
      if (version >= 9 && courseTermPreferences.isNotEmpty)
        'courseTermPreferences': courseTermPreferences.toJson(),
      'owner': owner,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'records': records
          .map((a) => _record(a, courseTaskKeys[a.id],
              includeTimeEvidence: version >= 7))
          .toList(),
      'hidden': hidden.toList(),
      'courses': version >= 9
          ? courses.map((c) => c.toJson()).toList()
          : courses
              .map((c) => {
                    'courseId': c.courseId,
                    'clazzId': c.clazzId,
                    'name': c.name,
                  })
              .toList(),
      'unfollowed': unfollowed.toList(),
      'reminderOffsets': reminderOffsets,
      'autoSyncIntervalMinutes': autoSyncIntervalMinutes,
    });
  }

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
    if (version is! int || !{1, 2, 3, 4, 5, 6, 7, 8, 9}.contains(version)) {
      _bad();
    }
    final hasCourseworkState = version >= 8 &&
        decoded is Map &&
        decoded.containsKey('courseworkState');
    final hasCourseTermPreferences = version >= 9 &&
        decoded is Map &&
        decoded.containsKey('courseTermPreferences');
    final j = _map(decoded, {
      if (version >= 2) 'personal',
      if (version >= 3) 'notebook',
      if (version >= 6) 'notices',
      if (version >= 6) 'chapters',
      if (version >= 8) 'pinned',
      if (hasCourseworkState) 'courseworkState',
      if (hasCourseTermPreferences) 'courseTermPreferences',
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
        if (version >= 7) 'publishedAt',
        if (version >= 7) 'availableFromAt',
        if (version >= 7) 'availableFromText',
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
          publishedAt: version >= 7 && r['publishedAt'] != null
              ? _date(r['publishedAt'])
              : null,
          availableFromAt: version >= 7 && r['availableFromAt'] != null
              ? _date(r['availableFromAt'])
              : null,
          availableFromText: version >= 7 && r['availableFromText'] != null
              ? _startText(r['availableFromText'])
              : null,
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
      if (version < 9) {
        final c = _map(value, {'courseId', 'clazzId', 'name'});
        courses.add(CourseRef(
            courseId: _text(c['courseId']),
            clazzId: _text(c['clazzId']),
            name: _text(c['name'])));
      } else {
        if (value is! Map<String, dynamic>) _bad();
        final c = _map(value, {
          'courseId',
          'clazzId',
          'name',
          if (value.containsKey('teacherNames')) 'teacherNames',
          if (value.containsKey('folderName')) 'folderName',
        });
        final teacherRaw = c['teacherNames'];
        final teacherList = <String>[];
        if (c.containsKey('teacherNames')) {
          final items = _list(teacherRaw, max: 10);
          if (items.isEmpty) _bad();
          final seenTeachers = <String>{};
          for (final item in items) {
            final name = _text(item, max: 80);
            if (!seenTeachers.add(name)) _bad();
            teacherList.add(name);
          }
        }
        final folderName = c.containsKey('folderName')
            ? _text(c['folderName'], max: 120)
            : null;
        courses.add(CourseRef(
          courseId: _text(c['courseId']),
          clazzId: _text(c['clazzId']),
          name: _text(c['name']),
          teacherNames: List.unmodifiable(teacherList),
          folderName: folderName,
        ));
      }
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
    final decodedNotebook = version < 3
        ? StudyNotebook()
        : StudyNotebook.decodePortable(jsonEncode(j['notebook']));
    final validEntryIds = {for (final e in decodedNotebook.entries) e.id};
    final decodedNotices = version < 6
        ? CourseNoticeCollection()
        : CourseNoticeCollection.fromJson(j['notices']);
    final cleanNotices = CourseNoticeCollection(items: [
      for (final n in decodedNotices.items)
        n.linkedManualEntryId != null &&
                !validEntryIds.contains(n.linkedManualEntryId)
            ? n.copyWith(clearLinkedManualEntryId: true)
            : n,
    ]);
    final decodedChapters = version < 6
        ? CourseChapterCatalog()
        : CourseChapterCatalog.fromJson(j['chapters']);
    final cleanChapters = CourseChapterCatalog(byCourse: {
      for (final e in decodedChapters.byCourse.entries)
        e.key: e.value.copyWith(nodes: [
          for (final node in e.value.nodes)
            node.linkedManualEntryId != null &&
                    !validEntryIds.contains(node.linkedManualEntryId)
                ? node.copyWith(clearLinkedManualEntryId: true)
                : node,
        ]),
    });
    final decodedPinned = version < 8
        ? const PinnedAssignments.empty()
        : PinnedAssignments.fromJson(j['pinned'], strict: true);
    final decodedCoursework = !hasCourseworkState
        ? const LocalCourseworkState.empty()
        : LocalCourseworkState.fromJson(j['courseworkState'], strict: true);
    final decodedTermPrefs = !hasCourseTermPreferences
        ? const CourseTermPreferences.empty()
        : CourseTermPreferences.fromJson(
            j['courseTermPreferences'],
            strict: true,
          );
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
            : PersonalWorkspace.fromJson(j['personal'], portable: true),
        decodedNotebook,
        courseTaskKeys,
        cleanNotices,
        cleanChapters,
        decodedPinned,
        decodedCoursework,
        decodedTermPrefs);
  }

  static ExamInfo? _exam(dynamic value) {
    if (value == null) return null;
    final e = _map(value, {
      if (value is Map && value.containsKey('relatedExamId')) 'relatedExamId',
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
    final courseId = identity(e['courseId']), clazzId = identity(e['clazzId']);
    final relatedExamId = e['relatedExamId'];
    if (relatedExamId != null &&
        (relatedExamId is! String ||
            relatedExamId.length > 500 ||
            RegExp(r'[0-9]+').matchAsPrefix(relatedExamId)?.end !=
                relatedExamId.length ||
            e['noticeOnly'] != true ||
            courseId == null ||
            clazzId == null)) {
      _bad();
    }
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
      relatedExamId: relatedExamId as String?,
      courseId: courseId,
      clazzId: clazzId,
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

  static String _startText(dynamic value) {
    final text = _text(value, max: _maxStartTextLength);
    if (!_isPortableStartText(text)) _bad();
    return text;
  }
}

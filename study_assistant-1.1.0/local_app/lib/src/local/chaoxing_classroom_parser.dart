import '../models/assignment.dart';

/// Read-only classroom metadata. Lifecycle status never proves submission.
class ChaoxingClassroomParser {
  static List<dynamic> readActivityList(dynamic payload) {
    final data = responseData(payload);
    final rows = data['activeList'];
    if (rows is! List || rows.any((row) => row is! Map)) {
      throw const FormatException('activityListSchema');
    }
    final identities = <String>{};
    for (final row in rows) {
      final type = _integer(row['activeType']);
      if (type == null) throw const FormatException('activityTypeSchema');
      if (const {35, 42}.contains(type)) {
        final id = _text(row['id'] ?? row['activeId']);
        if (id == null || !identities.add(id)) {
          throw const FormatException('activityIdentity');
        }
      }
    }
    return rows;
  }

  static List<Assignment> parseActivities(List<dynamic> rows,
      {required String courseId,
      required String clazzId,
      required String courseName,
      required int activityType,
      DateTime? now}) {
    final result = <Assignment>[];
    final seen = <String>{};
    for (final value in rows) {
      final row = _map(value);
      if (_integer(row['activeType']) != activityType) continue;
      final id = _text(row['id'] ?? row['activeId']);
      final title = _text(row['nameOne'] ?? row['name'] ?? row['title']);
      if (id == null || id.contains(':') || title == null || !seen.add(id)) {
        throw const FormatException('activityIdentity');
      }
      final seed = Assignment(
        id: 'cx:activity:$courseId:$clazzId:$id',
        source: AssignmentSource.classroomActivity,
        activityType: activityType,
        availability: AssignmentAvailability.unknown,
        courseName: courseName,
        title: title,
        deadlineAt: null,
        deadlineTrusted: false,
        requirementsText: '',
        status: 'unknown',
        lastSyncedAt: now ?? DateTime.now(),
      );
      checkIdentity(row, seed);
      result.add(seed);
    }
    return result;
  }

  static Map<String, dynamic> responseData(dynamic payload) {
    final root = _map(payload);
    if (root['result'] != true && _integer(root['result']) != 1) {
      throw const FormatException('classroomResponseSchema');
    }
    if (root['data'] is! Map) {
      throw const FormatException('classroomResponseSchema');
    }
    return _map(root['data']);
  }

  static Map<String, dynamic> taskMetadata(dynamic payload, Assignment seed) {
    final root = _map(payload);
    final data = _map(root['data']);
    // A not-in-class rejection is explicit availability evidence.
    if (!_unavailable(data)) responseData(payload);
    checkIdentity(data, seed);
    return data;
  }

  static bool isUnavailable(Map<String, dynamic> data) => _unavailable(data);

  static Assignment unavailable(Assignment seed) => seed.copyWith(
        availability: AssignmentAvailability.unavailable,
        clearSubmitUrl: true,
        clearCompletedAt: true,
        status: 'unknown',
      );

  static Assignment parseTask(Assignment seed,
      {required Map<String, dynamic> metadata,
      required dynamic detailPayload,
      required dynamic personalPayload,
      required String? currentUid}) {
    if (_unavailable(metadata)) return unavailable(seed);
    final active = responseData(detailPayload);
    checkIdentity(active, seed, requireActivity: true, requireCourse: true);
    final personal = responseData(personalPayload);
    checkIdentity(personal, seed);
    final attend = _map(personal['pptUserAttend']);
    final hasPersonalIdentity = _personalIdentity(attend, seed, currentUid);
    final group = _map(personal['taskGroupInfo']);
    checkIdentity(group, seed);
    final groupIds = [
      personal['groupId'],
      attend['groupId'],
      group['id'],
    ].map(_text).whereType<String>().where((id) => id != '0').toSet();
    if (groupIds.length > 1) {
      throw const FormatException('classroomGroupIdentity');
    }
    final groupStatus = _submission(group);
    final ownStatus = _submission(attend);
    final statuses = [
      if (hasPersonalIdentity && groupIds.isNotEmpty) groupStatus,
      if (hasPersonalIdentity) ownStatus,
    ].where((status) => status != 'unknown').toSet();
    final status = statuses.length == 1 ? statuses.single : 'unknown';
    final completedAt = status == 'submitted'
        ? absoluteTime(group['submitTime'] ?? attend['submitTime'])
        : null;
    final available = _integer(metadata['isDelete']) == 0
        ? AssignmentAvailability.available
        : AssignmentAvailability.unknown;
    return _withDeadline(seed, active).copyWith(
      availability: available,
      status: status,
      completedAt: completedAt,
      clearCompletedAt: completedAt == null,
      submitUrl: taskUrl(seed, metadata),
    );
  }

  static Assignment parseQuiz(Assignment seed,
      {required dynamic detailPayload,
      required dynamic answerPayload,
      required String? currentUid}) {
    final detail = responseData(detailPayload);
    final active = _map(detail['pptActive']);
    checkIdentity(active, seed, requireActivity: true, requireCourse: true);
    final answer = responseData(answerPayload);
    checkIdentity(answer, seed);
    for (final key in ['active', 'pptActive']) {
      if (answer[key] != null) {
        checkIdentity(_map(answer[key]), seed,
            requireActivity: true, requireCourse: true);
      }
    }
    final hasPersonalIdentity =
        _personalIdentity(_map(detail['pptUserAttend']), seed, currentUid);
    _personalIdentity(_map(answer['pptUserAttend']), seed, currentUid);
    _checkUid(answer, currentUid);
    final answered = answer['isAnswered'];
    final status = hasPersonalIdentity && answered is bool
        ? (answered ? 'submitted' : 'pending')
        : 'unknown';
    if (_integer(detail['hasAnswerPermission']) == 0 || _unavailable(active)) {
      return unavailable(seed);
    }
    final completedAt = status == 'submitted'
        ? absoluteTime(
            answer['submitTime'] ?? _map(detail['pptUserAttend'])['submitTime'])
        : null;
    return _withDeadline(seed, active).copyWith(
      availability: AssignmentAvailability.available,
      status: status,
      completedAt: completedAt,
      clearCompletedAt: completedAt == null,
      submitUrl: Uri.https('mobilelearn.chaoxing.com',
              '/page/quiz/stu/answerQuestion2', _linkParameters(seed))
          .toString(),
    );
  }

  /// The eight routes are the official course activity page's task branches.
  static String? taskUrl(Assignment seed, Map<String, dynamic> metadata) {
    final grouped = _integer(metadata['isNorm']);
    final editor = _integer(metadata['useNoteEditor']);
    final answer = _integer(metadata['toAnswerPage']);
    if (![grouped, editor, answer].every((flag) => flag == 0 || flag == 1) ||
        _unavailable(metadata)) {
      return null;
    }
    final engine = editor == 1 ? 'renwuNew' : 'renwu';
    final suffix = editor == 1 ? '_new' : '';
    final audience = grouped == 1 ? 'stu' : 'notGroup';
    final page =
        answer == 1 ? 'taskDetailStuForAnswer' : 'taskDetailStuAndAnsDetail';
    final personal = grouped == 1 ? '' : 'NotGroup';
    return Uri.https(
            'mobilelearn.chaoxing.com',
            '/page/$engine/$audience/$page$personal$suffix',
            _linkParameters(seed))
        .toString();
  }

  static Map<String, String> _linkParameters(Assignment seed) => {
        'courseId': seed.courseId!,
        'classId': seed.clazzId!,
        'activeId': seed.activityId!,
        'fid': '0',
      };

  static void checkIdentity(Map<String, dynamic> data, Assignment seed,
      {bool requireActivity = false, bool requireCourse = false}) {
    void check(List<String> keys, String expected, bool required) {
      final values = keys.map((key) => _text(data[key])).whereType<String>();
      if ((required && values.isEmpty) || values.any((v) => v != expected)) {
        throw const FormatException('classroomIdentity');
      }
    }

    // Official quiz metadata currently omits courseId. Its activity and class
    // must match the independently enumerated course; any supplied courseId
    // must still match it.
    check(['courseId', 'courseid'], seed.courseId!, false);
    check(['classId', 'classid', 'clazzId', 'clazzid'], seed.clazzId!,
        requireCourse);
    check([
      'activeId', 'activeid',
      // id on attendance and group rows identifies the row itself.
      if (requireActivity) 'id',
    ], seed.activityId!, requireActivity);
    if (data['activeType'] != null &&
        _integer(data['activeType']) != seed.activityType) {
      throw const FormatException('classroomType');
    }
  }

  static bool _personalIdentity(
      Map<String, dynamic> attend, Assignment seed, String? uid) {
    checkIdentity(attend, seed);
    _checkUid(attend, uid);
    return uid != null &&
        _text(attend['uid'] ?? attend['puid'] ?? attend['userId']) == uid &&
        _text(attend['activeId'] ?? attend['activeid']) == seed.activityId;
  }

  static void _checkUid(Map<String, dynamic> data, String? uid) {
    if (uid == null) return;
    for (final key in ['uid', 'puid', 'userId']) {
      final actual = _text(data[key]);
      if (actual != null && actual != uid) {
        throw const FormatException('classroomPersonalIdentity');
      }
    }
  }

  static String _submission(Map<String, dynamic> row) {
    final status = _integer(row['submitStatus']);
    final time = absoluteTime(row['submitTime']);
    if (status == 0 && time == null) return 'pending';
    if (status == 1 && time != null) return 'submitted';
    return 'unknown';
  }

  static bool _unavailable(Map<String, dynamic> data) =>
      _integer(data['isDelete'] ?? data['isdelete']) == 1 ||
      const {1, 2}.contains(_integer(data['notInClass']));

  static Assignment _withDeadline(
      Assignment seed, Map<String, dynamic> active) {
    final raw = active['endtime'] ?? active['endTime'] ?? active['deadline'];
    final time = absoluteTime(raw);
    final noLimit = const {'不限', '无截止时间', '不限制', 'no limit'}
        .contains(_text(raw)?.toLowerCase());
    return seed.copyWith(
      deadlineAt: time,
      clearDeadlineAt: time == null,
      deadlineTrusted: time != null || noLimit,
      deadlineReadFailed: false,
      // Never retain arbitrary response text in persisted diagnostics.
      deadlineRawText: noLimit ? '不限' : null,
      clearDeadlineRawText: !noLimit,
    );
  }

  static DateTime? absoluteTime(dynamic value) {
    final raw = _text(value);
    if (raw == null) return null;
    final epoch = int.tryParse(raw);
    if (epoch != null) {
      final millis = epoch < 100000000000 ? epoch * 1000 : epoch;
      if (millis < 946684800000 || millis > 4102444800000) return null;
      return DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    }
    final match = RegExp(
            r'^(20\d{2})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?(Z|[+-]\d{2}:?\d{2})?$')
        .firstMatch(raw);
    if (match == null) return null;
    final parts = [for (var i = 1; i <= 6; i++) int.parse(match[i] ?? '0')];
    final check = DateTime.utc(
        parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
    if (check.year != parts[0] ||
        check.month != parts[1] ||
        check.day != parts[2] ||
        check.hour != parts[3] ||
        check.minute != parts[4] ||
        check.second != parts[5]) {
      return null;
    }
    // Platform wall times are Beijing time, independent of the device zone.
    return DateTime.tryParse(
            '${raw.replaceFirst(' ', 'T')}${match[8] == null ? '+08:00' : ''}')
        ?.toLocal();
  }

  static int? _integer(dynamic value) => int.tryParse('$value');

  static String? _text(dynamic value) {
    if (value is! String && value is! num) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static Map<String, dynamic> _map(dynamic value) => value is Map
      ? value.map((key, value) => MapEntry(key.toString(), value))
      : const {};
}

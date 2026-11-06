enum AssignmentSource {
  courseWork,
  classroomActivity,
  exam,
  manual,
  legacyUnknown
}

class Assignment {
  Assignment({
    required this.id,
    required this.courseName,
    required this.title,
    required this.deadlineAt,
    required this.requirementsText,
    required this.status,
    required this.lastSyncedAt,
    this.submitUrl,
    this.completedAt,
    this.deadlineReadFailed = false,
    this.deadlineTrusted = true,
    this.deadlineRawText,
    AssignmentSource? source,
  }) : source = source ?? inferSource(id, submitUrl);

  final AssignmentSource source;
  String? get courseId => _identity?[0];
  String? get clazzId => _identity?[1];
  String? get workId => _identity?[2];
  String? get courseKey => courseId == null ? null : '$courseId:$clazzId';
  bool get isFormal =>
      source == AssignmentSource.courseWork && _identity != null;
  bool get isPendingConfirmed =>
      const {'pending', 'returned', 'overdue'}.contains(status);
  List<String>? get _identity {
    final parts = id.split(':');
    if (parts.length == 5 &&
        parts[0] == 'cx' &&
        parts[1] == 'work' &&
        parts.sublist(2).every((v) => v.isNotEmpty)) {
      return parts.sublist(2);
    }
    final uri = Uri.tryParse(submitUrl ?? '');
    if (uri == null ||
        !uri.host.endsWith('.chaoxing.com') ||
        !uri.path.contains('work')) {
      return null;
    }
    final q = uri.queryParameters.map((k, v) => MapEntry(k.toLowerCase(), v));
    final c = q['courseid'],
        cl = q['classid'] ?? q['clazzid'] ?? q['jclassid'],
        w = q['workid'] ?? q['taskrefid'];
    return c == null || cl == null || w == null ? null : [c, cl, w];
  }

  static AssignmentSource inferSource(String id, String? url) {
    if (id.startsWith('cx:work:')) return AssignmentSource.courseWork;
    if (id.startsWith('cx:activity:')) {
      return AssignmentSource.classroomActivity;
    }
    if (id.startsWith('cx:exam:')) return AssignmentSource.exam;
    if (id.startsWith('cx:manual:')) return AssignmentSource.manual;
    final u = Uri.tryParse(url ?? '');
    if (u != null &&
        u.host.endsWith('.chaoxing.com') &&
        u.path.contains('work') &&
        u.queryParameters.keys.any((k) =>
            k.toLowerCase() == 'workid' || k.toLowerCase() == 'taskrefid')) {
      return AssignmentSource.courseWork;
    }
    return AssignmentSource.legacyUnknown;
  }

  final bool deadlineReadFailed;
  final bool deadlineTrusted;
  final String? deadlineRawText;
  final String id;
  final String courseName;
  final String title;
  final DateTime? deadlineAt;
  final String requirementsText;
  final String status;
  final String? submitUrl;
  final DateTime? completedAt;
  final DateTime lastSyncedAt;

  factory Assignment.fromJson(Map<String, dynamic> json) {
    final rawDeadline = json['deadlineAt'] as String?;
    return Assignment(
      source: AssignmentSource.values
          .where((s) => s.name == json['source'])
          .firstOrNull,
      deadlineReadFailed: json['deadlineReadFailed'] == true,
      // Versions 32–33 incorrectly interpreted list endTime=0 as no deadline.
      deadlineTrusted: json['deadlineTrusted'] == true &&
          (rawDeadline == null || hasExplicitTimeZone(rawDeadline)) &&
          !(json['deadlineAt'] == null && json['deadlineRawText'] == '0'),
      deadlineRawText: json['deadlineRawText'] as String?,
      id: json['id'] as String,
      courseName: json['courseName'] as String,
      title: json['title'] as String,
      deadlineAt: json['deadlineAt'] == null
          ? null
          : DateTime.parse(json['deadlineAt'] as String).toLocal(),
      requirementsText: json['requirementsText'] as String,
      status: json['status'] as String,
      submitUrl: json['submitUrl'] as String?,
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.parse(json['completedAt'] as String).toLocal(),
      // Old wall times have no recoverable offset. They must not prevent a
      // fresh server result from replacing a cache after a timezone change.
      lastSyncedAt: hasExplicitTimeZone(json['lastSyncedAt'] as String)
          ? DateTime.parse(json['lastSyncedAt'] as String).toLocal()
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.name,
        'deadlineTrusted': deadlineTrusted,
        if (deadlineRawText != null) 'deadlineRawText': deadlineRawText,
        if (deadlineReadFailed) 'deadlineReadFailed': true,
        'courseName': courseName,
        'title': title,
        'deadlineAt': deadlineAt?.toUtc().toIso8601String(),
        'requirementsText': requirementsText,
        'status': status,
        'submitUrl': submitUrl,
        'completedAt': completedAt?.toUtc().toIso8601String(),
        'lastSyncedAt': lastSyncedAt.toUtc().toIso8601String(),
      };

  static bool hasExplicitTimeZone(String value) =>
      RegExp(r'(?:[zZ]|[+-]\d{2}:?\d{2})$').hasMatch(value);

  Assignment copyWith({
    String? id,
    String? courseName,
    String? title,
    DateTime? deadlineAt,
    String? requirementsText,
    String? status,
    String? submitUrl,
    DateTime? completedAt,
    DateTime? lastSyncedAt,
    bool? deadlineReadFailed,
    bool? deadlineTrusted,
    String? deadlineRawText,
    bool clearDeadlineRawText = false,
    bool clearSubmitUrl = false,
    bool clearCompletedAt = false,
    bool clearDeadlineAt = false,
  }) {
    return Assignment(
      id: id ?? this.id,
      source: source,
      deadlineTrusted: deadlineTrusted ?? this.deadlineTrusted,
      deadlineRawText:
          clearDeadlineRawText ? null : deadlineRawText ?? this.deadlineRawText,
      deadlineReadFailed: deadlineReadFailed ?? this.deadlineReadFailed,
      courseName: courseName ?? this.courseName,
      title: title ?? this.title,
      deadlineAt: clearDeadlineAt ? null : deadlineAt ?? this.deadlineAt,
      requirementsText: requirementsText ?? this.requirementsText,
      status: status ?? this.status,
      submitUrl: clearSubmitUrl ? null : submitUrl ?? this.submitUrl,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  /// 已提交、待批阅、已完成都视为完成状态
  bool get isCompleted =>
      status == 'completed' ||
      status == 'submitted' ||
      status == 'reviewing' ||
      status == 'graded';

  bool get isOverdue =>
      deadlineTrusted &&
      isPendingConfirmed &&
      !isCompleted &&
      (deadlineAt?.isBefore(DateTime.now()) ?? false);

  String get deadlineLabel {
    if (deadlineAt == null && deadlineRawText == '尚未开放') {
      return '尚未开放，截止时间待确认';
    }
    if (deadlineAt == null && deadlineRawText?.endsWith('（年份待确认）') == true) {
      return '截止 $deadlineRawText';
    }
    if (deadlineReadFailed) {
      return deadlineAt == null ? '截止时间读取失败，请查看同步详情' : '截止时间为上次读取记录';
    }
    return deadlineTrusted ? '未设置截止时间' : '截止时间待确认';
  }

  String get statusLabel => switch (status) {
        'returned' => '已退回',
        'submitted' => '已提交',
        'reviewing' => '待批阅',
        'graded' => '已批阅',
        'completed' => '已完成',
        'unknown' => '提交状态未知',
        'overdue' => '已逾期',
        'pending' => '待提交',
        _ => '提交状态未知',
      };

  static int compareByDeadline(Assignment a, Assignment b) {
    final left = a.deadlineAt;
    final right = b.deadlineAt;
    if (left == null && right != null) return 1;
    if (right == null && left != null) return -1;
    final time = left == null ? 0 : left.compareTo(right!);
    if (time != 0) return time;
    final title = a.title.compareTo(b.title);
    return title == 0 ? a.id.compareTo(b.id) : title;
  }

  /// 从学习通返回的状态文本推断内部状态
  static String statusFromChaoxing(String? statusName, String? stateText) {
    final text = [statusName, stateText]
        .whereType<String>()
        .join(' ')
        .trim()
        .toLowerCase();
    if (RegExp(r'退回|打回|重做|重新提交|returned|resubmit').hasMatch(text)) {
      return 'returned';
    }
    if (RegExp(
            r'未完成|未提交|待提交|待完成|未交|未做|待做|not[_ -]?submitted|incomplete|pending')
        .hasMatch(text)) {
      return 'pending';
    }
    if (RegExp(r'待批阅|待批改|评阅中|待评分|reviewing').hasMatch(text)) return 'reviewing';
    if (RegExp(
            r'已提交|已批阅|已批改|已完成|已做完|已交|已互评|submitted|graded|reviewed|completed')
        .hasMatch(text)) {
      return 'submitted';
    }
    return 'unknown';
  }
}

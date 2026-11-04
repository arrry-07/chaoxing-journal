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
  });

  final bool deadlineReadFailed;
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
    return Assignment(
      deadlineReadFailed: json['deadlineReadFailed'] == true,
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
      lastSyncedAt: DateTime.parse(json['lastSyncedAt'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (deadlineReadFailed) 'deadlineReadFailed': true,
        'courseName': courseName,
        'title': title,
        'deadlineAt': deadlineAt?.toIso8601String(),
        'requirementsText': requirementsText,
        'status': status,
        'submitUrl': submitUrl,
        'completedAt': completedAt?.toIso8601String(),
        'lastSyncedAt': lastSyncedAt.toIso8601String(),
      };

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
    bool clearCompletedAt = false,
    bool clearDeadlineAt = false,
  }) {
    return Assignment(
      id: id ?? this.id,
      deadlineReadFailed: deadlineReadFailed ?? this.deadlineReadFailed,
      courseName: courseName ?? this.courseName,
      title: title ?? this.title,
      deadlineAt: clearDeadlineAt ? null : deadlineAt ?? this.deadlineAt,
      requirementsText: requirementsText ?? this.requirementsText,
      status: status ?? this.status,
      submitUrl: submitUrl ?? this.submitUrl,
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
      !isCompleted && (deadlineAt?.isBefore(DateTime.now()) ?? false);

  String get deadlineLabel => deadlineReadFailed
      ? (deadlineAt == null ? '截止时间读取失败' : '截止时间为上次读取记录')
      : '未设置截止时间';

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

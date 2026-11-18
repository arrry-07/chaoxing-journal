import 'dart:convert';
import 'personal_workspace.dart';

enum ChapterTaskState {
  completed,
  pendingPoints,
  locked,
  noTaskPoints,
  unknown,
}

class ChapterNode {
  const ChapterNode({
    required this.sectionId,
    required this.level,
    required this.code,
    required this.title,
    required this.state,
    this.pendingPoints = 0,
    this.linkedManualEntryId,
  });

  final String sectionId;
  final int level;
  final String code;
  final String title;
  final ChapterTaskState state;
  final int pendingPoints;
  final String? linkedManualEntryId;

  ChapterNode copyWith({
    ChapterTaskState? state,
    int? pendingPoints,
    String? linkedManualEntryId,
    bool clearLinkedManualEntryId = false,
  }) =>
      ChapterNode(
        sectionId: sectionId,
        level: level,
        code: code,
        title: title,
        state: state ?? this.state,
        pendingPoints: pendingPoints ?? this.pendingPoints,
        linkedManualEntryId: clearLinkedManualEntryId
            ? null
            : (linkedManualEntryId ?? this.linkedManualEntryId),
      );

  Map<String, dynamic> toJson() => {
        'sectionId': sectionId,
        'level': level,
        'code': code,
        'title': title,
        'state': state.name,
        'pendingPoints': pendingPoints,
        'linkedManualEntryId': linkedManualEntryId,
      };

  factory ChapterNode.fromJson(dynamic value) {
    final j = PersonalWorkspace.map(value, {
      'sectionId',
      'level',
      'code',
      'title',
      'state',
      'pendingPoints',
      'linkedManualEntryId',
    });
    final level = j['level'];
    if (level is! int || (level != 0 && level != 1)) PersonalWorkspace.bad();
    final state =
        ChapterTaskState.values.where((v) => v.name == j['state']).firstOrNull;
    final pendingPoints = j['pendingPoints'];
    if (state == null ||
        pendingPoints is! int ||
        pendingPoints < 0 ||
        pendingPoints > 999 ||
        (state == ChapterTaskState.pendingPoints && pendingPoints < 1) ||
        (state != ChapterTaskState.pendingPoints && pendingPoints != 0)) {
      PersonalWorkspace.bad();
    }
    final sectionId = PersonalWorkspace.text(j['sectionId'], 300);
    if (!sectionId.startsWith('cx:chapter:')) PersonalWorkspace.bad();
    final rawEntryId = j['linkedManualEntryId'];
    return ChapterNode(
      sectionId: sectionId,
      level: level,
      code: PersonalWorkspace.text(j['code'], 60),
      title: PersonalWorkspace.text(j['title'], 500),
      state: state,
      pendingPoints: pendingPoints,
      linkedManualEntryId:
          rawEntryId == null ? null : PersonalWorkspace.text(rawEntryId, 100),
    );
  }
}

class CourseChapterSnapshot {
  CourseChapterSnapshot({
    required this.courseId,
    required this.clazzId,
    required this.courseName,
    this.completedPoints,
    this.totalPoints,
    this.progressTrusted = false,
    List<ChapterNode> nodes = const [],
    required this.lastSyncedAt,
  }) : nodes = List.unmodifiable(nodes);

  static const int maxNodes = 600;

  final String courseId;
  final String clazzId;
  final String courseName;
  final int? completedPoints;
  final int? totalPoints;
  final bool progressTrusted;
  final List<ChapterNode> nodes;
  final DateTime lastSyncedAt;

  String get courseKey => '$courseId:$clazzId';

  int get pendingSectionCount => nodes
      .where((n) => n.level == 1 && n.state == ChapterTaskState.pendingPoints)
      .length;

  int get pendingPointTotal => nodes
      .where((n) => n.level == 1 && n.state == ChapterTaskState.pendingPoints)
      .fold<int>(0, (sum, n) => sum + n.pendingPoints);

  CourseChapterSnapshot copyWith({
    String? courseName,
    int? completedPoints,
    int? totalPoints,
    bool? progressTrusted,
    List<ChapterNode>? nodes,
    DateTime? lastSyncedAt,
  }) =>
      CourseChapterSnapshot(
        courseId: courseId,
        clazzId: clazzId,
        courseName: courseName ?? this.courseName,
        completedPoints: completedPoints ?? this.completedPoints,
        totalPoints: totalPoints ?? this.totalPoints,
        progressTrusted: progressTrusted ?? this.progressTrusted,
        nodes: nodes ?? this.nodes,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      );

  Map<String, dynamic> toJson({bool portable = false}) => {
        'courseId': courseId,
        'clazzId': clazzId,
        'courseName': courseName,
        'completedPoints': completedPoints,
        'totalPoints': totalPoints,
        'progressTrusted': portable ? false : progressTrusted,
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'lastSyncedAt': lastSyncedAt.toUtc().toIso8601String(),
      };

  static final RegExp _identityTokenBad = RegExp(r'[:\s\x00-\x1f\x7f]');

  factory CourseChapterSnapshot.fromJson(dynamic value) {
    final j = PersonalWorkspace.map(value, {
      'courseId',
      'clazzId',
      'courseName',
      'completedPoints',
      'totalPoints',
      'progressTrusted',
      'nodes',
      'lastSyncedAt',
    });
    final courseId = PersonalWorkspace.text(j['courseId'], 120);
    final clazzId = PersonalWorkspace.text(j['clazzId'], 120);
    if (_identityTokenBad.hasMatch(courseId) ||
        _identityTokenBad.hasMatch(clazzId)) {
      PersonalWorkspace.bad();
    }
    final completed = j['completedPoints'];
    final total = j['totalPoints'];
    final trusted = j['progressTrusted'];
    if (trusted is! bool) PersonalWorkspace.bad();
    if (completed != null && (completed is! int || completed < 0)) {
      PersonalWorkspace.bad();
    }
    if (total != null && (total is! int || total < 0)) {
      PersonalWorkspace.bad();
    }
    if ((completed == null) != (total == null)) PersonalWorkspace.bad();
    if (completed != null && total != null && completed > total) {
      PersonalWorkspace.bad();
    }
    if (trusted && (completed == null || total == null)) {
      PersonalWorkspace.bad();
    }
    final lastRaw = PersonalWorkspace.text(j['lastSyncedAt'], 40);
    if (!RegExp(r'(?:[zZ]|[+-]\d{2}:?\d{2})$').hasMatch(lastRaw)) {
      PersonalWorkspace.bad();
    }
    final lastSyncedAt = DateTime.tryParse(lastRaw);
    if (lastSyncedAt == null ||
        lastSyncedAt.year < 1970 ||
        lastSyncedAt.year > 2200 ||
        lastSyncedAt.toUtc().toIso8601String() != lastRaw) {
      PersonalWorkspace.bad();
    }
    final nodes = PersonalWorkspace.list(j['nodes'], maxNodes)
        .map(ChapterNode.fromJson)
        .toList();
    if (nodes.map((n) => n.sectionId).toSet().length != nodes.length) {
      PersonalWorkspace.bad();
    }
    return CourseChapterSnapshot(
      courseId: courseId,
      clazzId: clazzId,
      courseName: PersonalWorkspace.text(j['courseName'], 200),
      completedPoints: completed as int?,
      totalPoints: total as int?,
      progressTrusted: trusted,
      nodes: nodes,
      lastSyncedAt: lastSyncedAt.toLocal(),
    );
  }
}

class CourseChapterCatalog {
  CourseChapterCatalog({Map<String, CourseChapterSnapshot> byCourse = const {}})
      : byCourse = Map.unmodifiable(byCourse);

  static const int maxCourses = 200;
  static const int maxBytes = 4 * 1024 * 1024;

  final Map<String, CourseChapterSnapshot> byCourse;

  int get totalPendingSections =>
      byCourse.values.fold<int>(0, (sum, c) => sum + c.pendingSectionCount);

  CourseChapterCatalog upsertCourse(CourseChapterSnapshot incoming) {
    final prior = byCourse[incoming.courseKey];
    final priorLinks = {
      if (prior != null)
        for (final node in prior.nodes)
          if (node.linkedManualEntryId != null)
            node.sectionId: node.linkedManualEntryId!,
    };
    final mergedNodes = [
      for (final node in incoming.nodes)
        priorLinks.containsKey(node.sectionId) &&
                node.linkedManualEntryId == null
            ? node.copyWith(linkedManualEntryId: priorLinks[node.sectionId])
            : node,
    ];
    final next = {...byCourse};
    if (!next.containsKey(incoming.courseKey) && next.length >= maxCourses) {
      final oldest = next.entries.reduce((a, b) =>
          a.value.lastSyncedAt.isBefore(b.value.lastSyncedAt) ? a : b);
      next.remove(oldest.key);
    }
    next[incoming.courseKey] = incoming.copyWith(nodes: mergedNodes);
    return CourseChapterCatalog(byCourse: next);
  }

  CourseChapterCatalog bindManualEntry(
    String courseKey,
    String sectionId,
    String entryId,
  ) {
    final current = byCourse[courseKey];
    if (current == null) return this;
    final nextNodes = [
      for (final node in current.nodes)
        if (node.sectionId == sectionId)
          node.copyWith(linkedManualEntryId: entryId)
        else
          node,
    ];
    return CourseChapterCatalog(
      byCourse: {...byCourse, courseKey: current.copyWith(nodes: nextNodes)},
    );
  }

  CourseChapterCatalog mergeImported(
    CourseChapterCatalog imported, {
    Set<String> validEntryIds = const {},
  }) {
    final next = {...byCourse};
    for (final entry in imported.byCourse.entries) {
      if (next.containsKey(entry.key) || next.length >= maxCourses) continue;
      final cleanNodes = [
        for (final node in entry.value.nodes)
          node.linkedManualEntryId != null &&
                  !validEntryIds.contains(node.linkedManualEntryId)
              ? node.copyWith(clearLinkedManualEntryId: true)
              : node,
      ];
      next[entry.key] = entry.value.copyWith(nodes: cleanNodes);
    }
    return CourseChapterCatalog(byCourse: next);
  }

  Map<String, dynamic> toJson({bool portable = false}) => {
        'version': 1,
        'courses': [
          for (final snapshot in byCourse.values)
            snapshot.toJson(portable: portable),
        ],
      };

  String encode({bool portable = false}) =>
      jsonEncode(toJson(portable: portable));

  factory CourseChapterCatalog.decode(String raw) {
    if (raw.length > maxBytes || utf8.encode(raw).length > maxBytes) {
      PersonalWorkspace.bad();
    }
    return CourseChapterCatalog.fromJson(jsonDecode(raw));
  }

  factory CourseChapterCatalog.fromJson(dynamic value) {
    final j = PersonalWorkspace.map(value, {'version', 'courses'});
    if (j['version'] is! int || j['version'] != 1) PersonalWorkspace.bad();
    final snapshots = PersonalWorkspace.list(j['courses'], maxCourses)
        .map(CourseChapterSnapshot.fromJson)
        .toList();
    final map = <String, CourseChapterSnapshot>{};
    for (final s in snapshots) {
      if (map.containsKey(s.courseKey)) PersonalWorkspace.bad();
      map[s.courseKey] = s;
    }
    return CourseChapterCatalog(byCourse: map);
  }
}

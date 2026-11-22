import 'dart:convert';

import '../local/chaoxing_api_parser.dart';
import '../services/course_term_catalog.dart';

enum AssignmentSyncScope {
  current('本学期优先'),
  all('全部学期'),
  targeted('定向课程'),
  historicalSweep('往期巡检');

  const AssignmentSyncScope(this.label);

  final String label;

  static AssignmentSyncScope? tryParse(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    for (final value in AssignmentSyncScope.values) {
      if (value.name == trimmed) return value;
    }
    return null;
  }
}

typedef SyncCourseSelector = SyncScopeSelection Function(
  List<ChaoxingCourseRef> catalog,
);

/// Result of projecting the full Chaoxing course catalog against a requested
/// [AssignmentSyncScope].
class SyncScopeSelection {
  SyncScopeSelection({
    required this.scope,
    required List<ChaoxingCourseRef> targetCourses,
    required Set<String> skippedCourseKeys,
    required this.includeAccountExams,
  })  : targetCourses = List.unmodifiable(targetCourses),
        skippedCourseKeys = Set.unmodifiable(skippedCourseKeys);

  final AssignmentSyncScope scope;
  final List<ChaoxingCourseRef> targetCourses;
  final Set<String> skippedCourseKeys;
  final bool includeAccountExams;

  static String courseKeyOf(ChaoxingCourseRef ref) =>
      '${ref.courseId}:${ref.clazzId}';

  factory SyncScopeSelection.all(List<ChaoxingCourseRef> catalog) =>
      SyncScopeSelection(
        scope: AssignmentSyncScope.all,
        targetCourses: catalog,
        skippedCourseKeys: const {},
        includeAccountExams: true,
      );

  /// Filters the full fetched catalog according to [scope] without mutating
  /// the underlying catalog list.
  static SyncScopeSelection select({
    required List<ChaoxingCourseRef> catalog,
    required AssignmentSyncScope scope,
    required CourseTermCatalog termCatalog,
    Set<String> targetedCourseKeys = const {},
  }) {
    if (scope == AssignmentSyncScope.all) {
      return SyncScopeSelection.all(catalog);
    }

    final targets = <ChaoxingCourseRef>[];
    final skipped = <String>{};
    for (final ref in catalog) {
      final key = courseKeyOf(ref);
      final include = switch (scope) {
        AssignmentSyncScope.all => true,
        AssignmentSyncScope.current => termCatalog.isActiveOrRecalled(key),
        AssignmentSyncScope.targeted ||
        AssignmentSyncScope.historicalSweep =>
          targetedCourseKeys.contains(key),
      };
      if (include) {
        targets.add(ref);
      } else {
        skipped.add(key);
      }
    }

    return SyncScopeSelection(
      scope: scope,
      targetCourses: targets,
      skippedCourseKeys: skipped,
      includeAccountExams: scope == AssignmentSyncScope.current,
    );
  }
}

/// Account-scoped rotation cursor and 24-hour cooldown state for bounded
/// background polling of archived/past courses.
class HistoricalSweepState {
  const HistoricalSweepState({
    this.lastBatchAtUtc,
    this.cursorIndex = 0,
    this.pendingRetryKeys = const [],
  });

  const HistoricalSweepState.empty()
      : lastBatchAtUtc = null,
        cursorIndex = 0,
        pendingRetryKeys = const [];

  static const int maxBatchSize = 3;
  static const Duration defaultCooldown = Duration(hours: 24);

  final DateTime? lastBatchAtUtc;
  final int cursorIndex;
  final List<String> pendingRetryKeys;

  bool isDueAt(
    DateTime now, {
    Duration cooldown = defaultCooldown,
  }) {
    final last = lastBatchAtUtc;
    if (last == null) return true;
    final elapsed = now.toUtc().difference(last.toUtc());
    return !elapsed.isNegative && elapsed >= cooldown;
  }

  /// Picks up to [maxBatchSize] followed archived course keys for this daytime
  /// rotation, prioritizing [pendingRetryKeys] before advancing [cursorIndex].
  List<String> selectNextBatch(
    Iterable<String> eligiblePastCourseKeys, {
    required DateTime now,
    Duration cooldown = defaultCooldown,
    int batchLimit = maxBatchSize,
  }) {
    if (batchLimit <= 0 || !isDueAt(now, cooldown: cooldown)) {
      return const [];
    }
    final sorted = _normalizedSortedKeys(eligiblePastCourseKeys);
    if (sorted.isEmpty) return const [];
    final eligibleSet = sorted.toSet();

    final picked = <String>[];
    final seen = <String>{};
    for (final raw in pendingRetryKeys) {
      final key = raw.trim();
      if (key.isNotEmpty && eligibleSet.contains(key) && seen.add(key)) {
        picked.add(key);
        if (picked.length >= batchLimit) return List.unmodifiable(picked);
      }
    }

    final start = cursorIndex <= 0 ? 0 : cursorIndex % sorted.length;
    for (var offset = 0; offset < sorted.length; offset++) {
      final candidate = sorted[(start + offset) % sorted.length];
      if (seen.add(candidate)) {
        picked.add(candidate);
        if (picked.length >= batchLimit) break;
      }
    }
    return List.unmodifiable(picked);
  }

  /// Advances the cursor past newly walked courses and retains [failedKeys]
  /// for priority retry in the next due window.
  HistoricalSweepState recordBatchResult({
    required List<String> plannedKeys,
    required Set<String> failedKeys,
    required Iterable<String> eligiblePastCourseKeys,
    required DateTime at,
  }) {
    final sorted = _normalizedSortedKeys(eligiblePastCourseKeys);
    final eligibleSet = sorted.toSet();
    final priorPendingSet = pendingRetryKeys.toSet();
    final plannedSet = plannedKeys.toSet();

    final nextPending = <String>[
      for (final key in plannedKeys)
        if (failedKeys.contains(key) && eligibleSet.contains(key)) key,
      for (final key in pendingRetryKeys)
        if (!plannedSet.contains(key) && eligibleSet.contains(key)) key,
    ];

    var nextCursor = 0;
    if (sorted.isNotEmpty) {
      final normalizedStart =
          cursorIndex <= 0 ? 0 : cursorIndex % sorted.length;
      var walkedSteps = 0;
      for (var offset = 0; offset < sorted.length; offset++) {
        final candidate = sorted[(normalizedStart + offset) % sorted.length];
        if (plannedSet.contains(candidate) &&
            !priorPendingSet.contains(candidate)) {
          walkedSteps = offset + 1;
        }
      }
      nextCursor = (normalizedStart + walkedSteps) % sorted.length;
    }

    return HistoricalSweepState(
      lastBatchAtUtc: at.toUtc(),
      cursorIndex: nextCursor,
      pendingRetryKeys: List.unmodifiable(nextPending),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'lastBatchAtUtc': lastBatchAtUtc?.toUtc().toIso8601String(),
        'cursorIndex': cursorIndex,
        'pendingRetryKeys': pendingRetryKeys,
      };

  String encode() => jsonEncode(toJson());

  static HistoricalSweepState decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['version'] != 1) {
      throw const FormatException('往期巡检状态格式无效');
    }
    DateTime? lastBatchAtUtc;
    final rawLast = decoded['lastBatchAtUtc'];
    if (rawLast != null) {
      if (rawLast is! String) {
        throw const FormatException('往期巡检时间无效');
      }
      final parsed = DateTime.tryParse(rawLast);
      if (parsed == null) {
        throw const FormatException('往期巡检时间无法解析');
      }
      lastBatchAtUtc = parsed.toUtc();
    }
    final rawCursor = decoded['cursorIndex'];
    if (rawCursor is! int || rawCursor < 0) {
      throw const FormatException('往期巡检游标无效');
    }
    final rawPending = decoded['pendingRetryKeys'];
    if (rawPending is! List) {
      throw const FormatException('往期巡检待重试列表无效');
    }
    final pending = <String>[];
    final seen = <String>{};
    for (final item in rawPending) {
      if (item is! String || item.trim().isEmpty) {
        throw const FormatException('往期巡检待重试课程键无效');
      }
      final trimmed = item.trim();
      if (seen.add(trimmed)) {
        pending.add(trimmed);
      }
    }
    return HistoricalSweepState(
      lastBatchAtUtc: lastBatchAtUtc,
      cursorIndex: rawCursor,
      pendingRetryKeys: List.unmodifiable(pending),
    );
  }

  static List<String> _normalizedSortedKeys(Iterable<String> keys) {
    final unique = <String>{
      for (final raw in keys)
        if (raw.trim().isNotEmpty) raw.trim(),
    }.toList()
      ..sort();
    return unique;
  }
}

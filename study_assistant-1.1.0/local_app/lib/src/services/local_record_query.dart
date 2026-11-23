import '../models/assignment.dart';
import '../models/local_coursework_state.dart';
import 'assignment_grouping.dart';
import 'assignment_query.dart';
import 'assignment_statistics.dart';
import 'assignment_store.dart';
import 'course_term_catalog.dart';

enum StatsTimeRange {
  all,
  next7Days,
  next30Days;

  String get label => switch (this) {
        StatsTimeRange.all => '全部',
        StatsTimeRange.next7Days => '未来 7 天',
        StatsTimeRange.next30Days => '未来 30 天',
      };
}

enum LocalRecordCategory {
  coursework,
  otherSources,
  hidden;

  String get label => switch (this) {
        LocalRecordCategory.coursework => '作业与任务',
        LocalRecordCategory.otherSources => '历史与其他来源',
        LocalRecordCategory.hidden => '已隐藏',
      };
}

enum LocalRecordStatusFilter {
  all,
  unfinished,
  pending,
  completed,
  overdue,
  unknown;

  String get label => switch (this) {
        LocalRecordStatusFilter.all => '全部状态',
        LocalRecordStatusFilter.unfinished => '待处理',
        LocalRecordStatusFilter.pending => '待完成',
        LocalRecordStatusFilter.completed => '已完成',
        LocalRecordStatusFilter.overdue => '已逾期',
        LocalRecordStatusFilter.unknown => '提交未知',
      };
}

enum LocalRecordScopeFilter {
  allLocal,
  followedStats,
  accountExam,
  otherUnkeyed;

  String get label => switch (this) {
        LocalRecordScopeFilter.allLocal => '本机全部课程',
        LocalRecordScopeFilter.followedStats => '已关注课程',
        LocalRecordScopeFilter.accountExam => '账号考试',
        LocalRecordScopeFilter.otherUnkeyed => '其他课业',
      };
}

enum LocalRecordSortOrder {
  timeAsc,
  timeDesc,
  courseName,
  lastSyncedDesc;

  String get label => switch (this) {
        LocalRecordSortOrder.timeAsc => '业务时间近到远',
        LocalRecordSortOrder.timeDesc => '业务时间远到近',
        LocalRecordSortOrder.courseName => '课程名称',
        LocalRecordSortOrder.lastSyncedDesc => '最近读取优先',
      };
}

class LocalRecordCourseOption {
  const LocalRecordCourseOption({
    required this.courseKey,
    required this.label,
  });

  final String courseKey;
  final String label;
}

class LocalRecordFilterSpec {
  const LocalRecordFilterSpec({
    this.from,
    this.category = LocalRecordCategory.coursework,
    this.status = LocalRecordStatusFilter.all,
    this.scope = LocalRecordScopeFilter.allLocal,
    this.courseKey,
    this.timeRange = StatsTimeRange.all,
    this.termScope = CourseTermScope.allTerms,
    this.query = '',
    this.sort = LocalRecordSortOrder.timeAsc,
  });

  final String? from;
  final LocalRecordCategory category;
  final LocalRecordStatusFilter status;
  final LocalRecordScopeFilter scope;
  final String? courseKey;
  final StatsTimeRange timeRange;
  final CourseTermScope termScope;
  final String query;
  final LocalRecordSortOrder sort;

  factory LocalRecordFilterSpec.fromQueryParameters(
      Map<String, String> params) {
    final sourceRaw = params['source'];
    final statusRaw = params['status'];
    final scopeRaw = params['scope'];
    final rangeRaw = params['range'];
    final termRaw = params['term'];
    final sortRaw = params['sort'];
    final fromRaw = params['from'];
    final courseKeyRaw = params['courseKey']?.trim();

    final isHiddenShortcut = sourceRaw == 'hidden' || statusRaw == 'hidden';
    final category = isHiddenShortcut
        ? LocalRecordCategory.hidden
        : LocalRecordCategory.values
                .where((value) => value.name == sourceRaw)
                .firstOrNull ??
            LocalRecordCategory.coursework;

    final status = isHiddenShortcut
        ? LocalRecordStatusFilter.all
        : LocalRecordStatusFilter.values
                .where((value) => value.name == statusRaw)
                .firstOrNull ??
            LocalRecordStatusFilter.all;

    final scope = LocalRecordScopeFilter.values
            .where((value) => value.name == scopeRaw)
            .firstOrNull ??
        LocalRecordScopeFilter.allLocal;

    final timeRange = StatsTimeRange.values
            .where((value) => value.name == rangeRaw)
            .firstOrNull ??
        StatsTimeRange.all;

    final termScope = CourseTermScope.values
            .where((value) => value.name == termRaw)
            .firstOrNull ??
        CourseTermScope.allTerms;

    final sort = LocalRecordSortOrder.values
            .where((value) => value.name == sortRaw)
            .firstOrNull ??
        LocalRecordSortOrder.timeAsc;

    return LocalRecordFilterSpec(
      from: fromRaw?.isEmpty == true ? null : fromRaw,
      category: category,
      status: status,
      scope: scope,
      courseKey:
          courseKeyRaw == null || courseKeyRaw.isEmpty ? null : courseKeyRaw,
      timeRange: timeRange,
      termScope: termScope,
      query: params['q'] ?? '',
      sort: sort,
    );
  }

  bool get isStatsScoped =>
      scope != LocalRecordScopeFilter.allLocal ||
      courseKey != null ||
      timeRange != StatsTimeRange.all ||
      status != LocalRecordStatusFilter.all ||
      from == 'stats';

  LocalRecordFilterSpec copyWith({
    String? from,
    bool clearFrom = false,
    LocalRecordCategory? category,
    LocalRecordStatusFilter? status,
    LocalRecordScopeFilter? scope,
    String? courseKey,
    bool clearCourseKey = false,
    StatsTimeRange? timeRange,
    String? query,
    LocalRecordSortOrder? sort,
  }) {
    return LocalRecordFilterSpec(
      from: clearFrom ? null : from ?? this.from,
      category: category ?? this.category,
      status: status ?? this.status,
      scope: scope ?? this.scope,
      courseKey: clearCourseKey ? null : courseKey ?? this.courseKey,
      timeRange: timeRange ?? this.timeRange,
      query: query ?? this.query,
      sort: sort ?? this.sort,
    );
  }

  LocalRecordFilterSpec resetToAllLocal() => LocalRecordFilterSpec(
        from: from,
        category: LocalRecordCategory.coursework,
        status: LocalRecordStatusFilter.all,
        scope: LocalRecordScopeFilter.allLocal,
        courseKey: null,
        timeRange: StatsTimeRange.all,
        query: '',
        sort: sort,
      );
}

class StatsRangeResult {
  const StatsRangeResult({
    required this.records,
    required this.excludedUnscheduledCount,
  });

  final List<Assignment> records;
  final int excludedUnscheduledCount;
}

class LocalRecordQueryResult {
  const LocalRecordQueryResult({
    this.groups = const [],
    this.otherSources = const [],
    this.courseOptions = const [],
  });

  final List<CourseworkGroup> groups;
  final List<Assignment> otherSources;
  final List<LocalRecordCourseOption> courseOptions;

  int get count => groups.isNotEmpty ? groups.length : otherSources.length;
}

class LocalRecordQuery {
  const LocalRecordQuery._();

  static bool hasDeterministicTime(Assignment a) =>
      a.timelineTrusted &&
      (a.isExam || !a.deadlineReadFailed) &&
      a.timelineAt != null;

  static bool matchesStatsTimeRange(
    Assignment a,
    StatsTimeRange range,
    DateTime now,
  ) {
    if (range == StatsTimeRange.all) return true;
    if (!a.timelineTrusted || (!a.isExam && a.deadlineReadFailed)) return false;
    final target = a.timelineAt;
    if (target == null) return false;
    final today = AssignmentQuery.dayKey(now);
    final days = range == StatsTimeRange.next7Days ? 7 : 30;
    final end = DateTime(today.year, today.month, today.day + days);
    final targetDay = AssignmentQuery.dayKey(target);
    return !targetDay.isBefore(today) && targetDay.isBefore(end);
  }

  static StatsRangeResult filterStatsRecords(
    List<Assignment> statsAssignments,
    StatsTimeRange range,
    DateTime now,
  ) {
    if (range == StatsTimeRange.all) {
      return StatsRangeResult(
        records: List<Assignment>.unmodifiable(statsAssignments),
        excludedUnscheduledCount: 0,
      );
    }
    var excludedUnscheduled = 0;
    final selected = <Assignment>[];
    for (final a in statsAssignments) {
      if (!hasDeterministicTime(a)) {
        excludedUnscheduled++;
        continue;
      }
      if (matchesStatsTimeRange(a, range, now)) {
        selected.add(a);
      }
    }
    return StatsRangeResult(
      records: List<Assignment>.unmodifiable(selected),
      excludedUnscheduledCount: excludedUnscheduled,
    );
  }

  static bool matchesStatusFilter(
    Assignment a,
    LocalRecordStatusFilter status,
    DateTime now, {
    LocalCourseworkState coursework = const LocalCourseworkState.empty(),
  }) {
    if (status == LocalRecordStatusFilter.all) return true;
    final bucket =
        AssignmentStatistics.classify(a, now, coursework: coursework);
    return switch (status) {
      LocalRecordStatusFilter.all => true,
      LocalRecordStatusFilter.unfinished =>
        bucket != AssignmentStatBucket.completed,
      LocalRecordStatusFilter.pending => bucket == AssignmentStatBucket.pending,
      LocalRecordStatusFilter.completed =>
        bucket == AssignmentStatBucket.completed,
      LocalRecordStatusFilter.overdue => bucket == AssignmentStatBucket.expired,
      LocalRecordStatusFilter.unknown => bucket == AssignmentStatBucket.unknown,
    };
  }

  static LocalRecordQueryResult query(
    AssignmentStore store,
    LocalRecordFilterSpec spec,
    DateTime now,
  ) {
    final needle = spec.query.trim().toLowerCase();

    if (spec.category == LocalRecordCategory.otherSources) {
      final filtered = store.assignments.where((a) {
        if (a.hasCourseTaskIdentity) return false;
        if (needle.isEmpty) return true;
        return a.title.toLowerCase().contains(needle) ||
            a.courseName.toLowerCase().contains(needle) ||
            a.source.name.toLowerCase().contains(needle);
      }).toList();
      final sorted = _sortAssignments(filtered, spec.sort, now, filtered);
      return LocalRecordQueryResult(otherSources: sorted);
    }

    if (spec.category == LocalRecordCategory.hidden) {
      final filtered = store.hiddenCourseworkGroups.where((group) {
        if (needle.isEmpty) return true;
        return group.primary.title.toLowerCase().contains(needle) ||
            group.primary.courseName.toLowerCase().contains(needle) ||
            group.sourceLabel.toLowerCase().contains(needle);
      }).toList();
      final sorted = _sortGroups(filtered, spec.sort, now);
      return LocalRecordQueryResult(groups: sorted);
    }

    // Coursework category: align base collection with the same term-scoped
    // statistics source used by StatsScreen, including archived courses.
    final statsScoped =
        spec.from == 'stats' || spec.scope != LocalRecordScopeFilter.allLocal;
    final baseGroups = statsScoped
        ? _statsScopedGroups(store, spec, now)
        : store.localCourseTaskGroups;

    final courseOptions = _buildCourseOptions(
      baseGroups,
      ensureCourseKey: spec.courseKey,
    );

    final filtered = baseGroups.where((group) {
      final primary = group.primary;
      if (spec.scope == LocalRecordScopeFilter.accountExam &&
          !(primary.courseKey == null && primary.isExam)) {
        return false;
      }
      if (spec.scope == LocalRecordScopeFilter.otherUnkeyed &&
          !(primary.courseKey == null && !primary.isExam)) {
        return false;
      }
      if (spec.courseKey != null && primary.courseKey != spec.courseKey) {
        return false;
      }
      if (!matchesStatsTimeRange(primary, spec.timeRange, now)) {
        return false;
      }
      if (!matchesStatusFilter(
        primary,
        spec.status,
        now,
        coursework: store.courseworkState,
      )) {
        return false;
      }
      if (needle.isNotEmpty) {
        final match = primary.title.toLowerCase().contains(needle) ||
            primary.courseName.toLowerCase().contains(needle) ||
            group.sourceLabel.toLowerCase().contains(needle) ||
            (primary.courseKey?.toLowerCase().contains(needle) ?? false);
        if (!match) return false;
      }
      return true;
    }).toList();

    final sorted = _sortGroups(filtered, spec.sort, now);
    return LocalRecordQueryResult(
      groups: sorted,
      courseOptions: courseOptions,
    );
  }

  static List<CourseworkGroup> _statsScopedGroups(
    AssignmentStore store,
    LocalRecordFilterSpec spec,
    DateTime now,
  ) {
    final allowed = {
      for (final assignment
          in store.statsAssignmentsForScope(spec.termScope, now: now))
        assignment.id,
    };
    return [
      for (final group in store.localRecordGroups)
        if (!group.hidden && allowed.contains(group.primary.id)) group,
    ];
  }

  static List<LocalRecordCourseOption> _buildCourseOptions(
    List<CourseworkGroup> groups, {
    String? ensureCourseKey,
  }) {
    final byKey = <String, ({String name, String? clazzId})>{};
    for (final group in groups) {
      final key = group.primary.courseKey;
      if (key == null || key.isEmpty) continue;
      byKey.putIfAbsent(
        key,
        () => (
          name: group.primary.courseName.trim().isEmpty
              ? '未命名课程'
              : group.primary.courseName.trim(),
          clazzId: group.primary.clazzId,
        ),
      );
    }
    final nameCounts = <String, int>{};
    for (final entry in byKey.values) {
      nameCounts[entry.name] = (nameCounts[entry.name] ?? 0) + 1;
    }
    final keys = byKey.keys.toList()
      ..sort((left, right) {
        final a = byKey[left]!;
        final b = byKey[right]!;
        final byName = a.name.compareTo(b.name);
        return byName != 0 ? byName : left.compareTo(right);
      });
    final options = <LocalRecordCourseOption>[
      for (final key in keys)
        LocalRecordCourseOption(
          courseKey: key,
          label: (nameCounts[byKey[key]!.name] ?? 0) > 1
              ? '${byKey[key]!.name} · 班级 ${byKey[key]!.clazzId ?? key}'
              : byKey[key]!.name,
        ),
    ];
    if (ensureCourseKey != null &&
        ensureCourseKey.isNotEmpty &&
        !byKey.containsKey(ensureCourseKey)) {
      options.insert(
        0,
        LocalRecordCourseOption(
          courseKey: ensureCourseKey,
          label: '指定课程（$ensureCourseKey）',
        ),
      );
    }
    return options;
  }

  static List<CourseworkGroup> _sortGroups(
    List<CourseworkGroup> groups,
    LocalRecordSortOrder sort,
    DateTime now,
  ) {
    if (groups.length <= 1) return List<CourseworkGroup>.of(groups);
    if (sort == LocalRecordSortOrder.lastSyncedDesc) {
      final copy = List<CourseworkGroup>.of(groups);
      copy.sort((left, right) {
        final time =
            right.primary.lastSyncedAt.compareTo(left.primary.lastSyncedAt);
        if (time != 0) return time;
        final title = left.primary.title.compareTo(right.primary.title);
        return title != 0 ? title : left.key.compareTo(right.key);
      });
      return copy;
    }
    final byPrimaryId = <String, CourseworkGroup>{
      for (final group in groups) group.primary.id: group,
    };
    final primaries = [for (final group in groups) group.primary];
    final sources = [for (final group in groups) ...group.sources];
    final homeSort = switch (sort) {
      LocalRecordSortOrder.timeAsc => HomeSortOrder.deadlineAsc,
      LocalRecordSortOrder.timeDesc => HomeSortOrder.deadlineDesc,
      LocalRecordSortOrder.courseName => HomeSortOrder.courseName,
      LocalRecordSortOrder.lastSyncedDesc => HomeSortOrder.deadlineAsc,
    };
    final sortedPrimaries = AssignmentQuery.sortHome(
      primaries,
      homeSort,
      now: now,
      sourceRecords: sources,
      prioritizeStartOnly: false,
    );
    return [for (final primary in sortedPrimaries) byPrimaryId[primary.id]!];
  }

  static List<Assignment> _sortAssignments(
    List<Assignment> records,
    LocalRecordSortOrder sort,
    DateTime now,
    List<Assignment> sources,
  ) {
    if (records.length <= 1) return List<Assignment>.of(records);
    if (sort == LocalRecordSortOrder.lastSyncedDesc) {
      final copy = List<Assignment>.of(records);
      copy.sort((left, right) {
        final time = right.lastSyncedAt.compareTo(left.lastSyncedAt);
        if (time != 0) return time;
        final title = left.title.compareTo(right.title);
        return title != 0 ? title : left.id.compareTo(right.id);
      });
      return copy;
    }
    final homeSort = switch (sort) {
      LocalRecordSortOrder.timeAsc => HomeSortOrder.deadlineAsc,
      LocalRecordSortOrder.timeDesc => HomeSortOrder.deadlineDesc,
      LocalRecordSortOrder.courseName => HomeSortOrder.courseName,
      LocalRecordSortOrder.lastSyncedDesc => HomeSortOrder.deadlineAsc,
    };
    return AssignmentQuery.sortHome(
      records,
      homeSort,
      now: now,
      sourceRecords: sources,
      prioritizeStartOnly: false,
    );
  }
}

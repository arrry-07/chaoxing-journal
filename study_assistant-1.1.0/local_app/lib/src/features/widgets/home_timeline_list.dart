import 'dart:async';

import 'package:flutter/foundation.dart'
    show listEquals, setEquals, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/journal.dart';
import '../../app/journal_motion.dart';
import '../../models/assignment.dart';
import '../../models/assignment_sync_progress.dart';
import '../../models/course.dart';
import '../../models/local_coursework_state.dart';
import '../../models/personal_workspace.dart';
import '../../models/pinned_assignments.dart';
import '../../models/study_notebook.dart';
import '../../models/sync_report.dart';
import '../../services/assignment_query.dart';
import '../../services/assignment_store.dart';
import '../../services/assignment_web_link.dart';
import '../../services/clawd_companion_controller.dart';
import '../../services/home_course_filter.dart';
import '../../services/home_manual_timeline.dart';
import '../../services/home_sync_presentation.dart';
import '../../services/home_upcoming_exam.dart';
import '../../services/interaction_feedback_service.dart';
import 'assignment_card.dart';
import 'home_list_sections.dart';
import 'home_manual_actions.dart';
import 'home_manual_sections.dart';
import 'journal_buttons.dart';
import 'journal_grouped_card.dart';
import 'journal_swipe_tile.dart';

class HomeViewData {
  const HomeViewData({
    required this.filtersActive,
    required this.coursework,
    required this.catalogAssignments,
    required this.displayIndex,
    required this.displayAssignments,
    required this.options,
    required this.items,
    required this.sortOrder,
    required this.selectedCourseIdle,
    required this.sortedTimelineItems,
    required this.plans,
    required this.plannedIds,
    required this.sync,
    required this.dueSummary,
    required this.showDueSummary,
    required this.statusText,
    required this.upcomingExam,
    required this.buddyMood,
    required this.homeSnapshot,
  });

  final bool filtersActive;
  final LocalCourseworkState coursework;
  final List<Assignment> catalogAssignments;
  final AssignmentDisplayIndex displayIndex;
  final List<Assignment> displayAssignments;
  final List<HomeCourseFilterOption> options;
  final List<Assignment> items;
  final HomeSortOrder sortOrder;
  final bool selectedCourseIdle;
  final List<HomeTimelineItem> sortedTimelineItems;
  final List<DailyPlanItem> plans;
  final Set<String> plannedIds;
  final HomeSyncPresentation sync;
  final HomeDueSummary dueSummary;
  final bool showDueSummary;
  final String statusText;
  final HomeUpcomingExam? upcomingExam;
  final JournalPixelBuddyMood buddyMood;
  final ClawdPageContextSnapshot homeSnapshot;
}

typedef HomeCoursePickerProjection = ({
  List<HomeCourseFilterOption> options,
  Map<String, int> Function(
    String query,
    AssignmentTypeFilter type,
    AssignmentDeadlineFilter deadline,
  ) countsFor,
});

/// Shared projection for followed courses and live item counts across home and
/// the filter sheet's course picker.
HomeCoursePickerProjection computeHomeCoursePickerProjection({
  required AssignmentStore store,
  required DateTime now,
  required String? selectedCourseKey,
  AssignmentDisplayIndex? fallbackDisplayIndex,
}) {
  final coursework = store.courseworkState;
  final termCatalog = store.termCatalog;
  final allFollowedSources = [
    for (final group in store.localRecordGroups)
      if (!group.hidden &&
          (group.primary.courseKey == null ||
              (store.follows(group.primary.courseKey!) &&
                  !termCatalog.isBlocked(group.primary.courseKey!))))
        ...group.sources,
  ];
  final pickerIndex = allFollowedSources.isEmpty && fallbackDisplayIndex != null
      ? fallbackDisplayIndex
      : AssignmentDisplayIndex.from(allFollowedSources);
  final pickerAssignments = AssignmentQuery.currentDisplay(
    AssignmentQuery.scope(allFollowedSources, {}),
    now,
    index: pickerIndex,
    coursework: coursework,
  );
  final options = buildHomeCourseFilterOptions(
    assignments: pickerAssignments,
    catalog: [
      for (final course in store.courses)
        if (store.follows(course.key) && !termCatalog.isBlocked(course.key))
          course,
    ],
    records: allFollowedSources,
    selectedCourseKey: selectedCourseKey,
    termCatalog: termCatalog,
    includeIdleCourses: true,
  );
  return (
    options: options,
    countsFor: (query, type, deadline) => countHomeCourseItems(
          options: options,
          filteredAssignments: AssignmentQuery.filterHome(
            allFollowedSources,
            query: query,
            deadline: deadline,
            type: type,
            includeHistorical: false,
            index: pickerIndex,
            now: now,
            coursework: coursework,
          ),
          filteredManualEntries: HomeManualTimeline.filterManualEntries(
            store.isAuthenticated
                ? store.notebook.entries
                : const <ManualEntry>[],
            query: query,
            deadline: deadline,
            type: type,
            now: now,
          ),
        ),
  );
}

class _HomeProjectionCacheEntry {
  const _HomeProjectionCacheEntry({
    required this.store,
    required this.accountEpoch,
    required this.isAuthenticated,
    required this.homeCatalog,
    required this.localRecordGroups,
    required this.termCatalog,
    required this.coursework,
    required this.notebook,
    required this.personal,
    required this.courses,
    required this.unfollowedCourseKeys,
    required this.query,
    required this.typeFilter,
    required this.deadlineFilter,
    required this.courseKey,
    required this.sortOrder,
    required this.completingManualIds,
    required this.nowMinute,
    required this.filtersActive,
    required this.catalogAssignments,
    required this.displayIndex,
    required this.displayAssignments,
    required this.options,
    required this.items,
    required this.selectedCourseIdle,
    required this.sortedTimelineItems,
    required this.plans,
    required this.plannedIds,
    required this.dueSummary,
    required this.upcomingExam,
    required this.hasManualItems,
    required this.followedCourses,
    required this.activeAgenda,
  });

  final AssignmentStore store;
  final int accountEpoch;
  final bool isAuthenticated;
  final List<Assignment> homeCatalog;
  final Object localRecordGroups;
  final Object termCatalog;
  final LocalCourseworkState coursework;
  final StudyNotebook notebook;
  final PersonalWorkspace personal;
  final List<CourseRef> courses;
  final Set<String> unfollowedCourseKeys;
  final String query;
  final AssignmentTypeFilter typeFilter;
  final AssignmentDeadlineFilter deadlineFilter;
  final String? courseKey;
  final HomeSortOrder sortOrder;
  final Set<String> completingManualIds;
  final int nowMinute;

  final bool filtersActive;
  final List<Assignment> catalogAssignments;
  final AssignmentDisplayIndex displayIndex;
  final List<Assignment> displayAssignments;
  final List<HomeCourseFilterOption> options;
  final List<Assignment> items;
  final bool selectedCourseIdle;
  final List<HomeTimelineItem> sortedTimelineItems;
  final List<DailyPlanItem> plans;
  final Set<String> plannedIds;
  final HomeDueSummary dueSummary;
  final HomeUpcomingExam? upcomingExam;
  final bool hasManualItems;
  final int followedCourses;
  final int activeAgenda;

  bool matches({
    required AssignmentStore store,
    required List<Assignment> homeCatalog,
    required Object localRecordGroups,
    required Object termCatalog,
    required List<CourseRef> courses,
    required Set<String> unfollowedCourseKeys,
    required String query,
    required AssignmentTypeFilter typeFilter,
    required AssignmentDeadlineFilter deadlineFilter,
    required String? courseKey,
    required HomeSortOrder sortOrder,
    required Set<String> completingManualIds,
    required int nowMinute,
  }) =>
      identical(this.store, store) &&
      accountEpoch == store.accountEpoch &&
      isAuthenticated == store.isAuthenticated &&
      identical(this.homeCatalog, homeCatalog) &&
      identical(this.localRecordGroups, localRecordGroups) &&
      identical(this.termCatalog, termCatalog) &&
      identical(coursework, store.courseworkState) &&
      identical(notebook, store.notebook) &&
      identical(personal, store.personal) &&
      this.query == query &&
      this.typeFilter == typeFilter &&
      this.deadlineFilter == deadlineFilter &&
      this.courseKey == courseKey &&
      this.sortOrder == sortOrder &&
      this.nowMinute == nowMinute &&
      setEquals(this.completingManualIds, completingManualIds) &&
      listEquals(this.courses, courses) &&
      setEquals(this.unfollowedCourseKeys, unfollowedCourseKeys);
}

_HomeProjectionCacheEntry? _homeProjectionCache;

@visibleForTesting
void clearHomeProjectionCacheForTesting() {
  _homeProjectionCache = null;
}

HomeViewData prepareHomeViewData({
  required AssignmentStore store,
  required DateTime now,
  required bool busy,
  required bool recoveryActive,
  bool Function(Assignment assignment)? recoveryMatches,
  required String? courseKey,
  required String query,
  required AssignmentDeadlineFilter deadlineFilter,
  required AssignmentTypeFilter typeFilter,
  required HomeSortOrder sortOrder,
  required Set<String> completingManualIds,
}) {
  final bool filtersActive;
  final LocalCourseworkState coursework;
  final List<Assignment> catalogAssignments;
  final AssignmentDisplayIndex displayIndex;
  final List<Assignment> displayAssignments;
  final List<HomeCourseFilterOption> options;
  final List<Assignment> items;
  final bool selectedCourseIdle;
  final List<HomeTimelineItem> sortedTimelineItems;
  final List<DailyPlanItem> plans;
  final Set<String> plannedIds;
  final HomeDueSummary dueSummary;
  final HomeUpcomingExam? upcomingExam;
  final bool hasManualItems;
  final int followedCourses;
  final int activeAgenda;

  final homeCatalog = store.homeCatalogAssignments;
  final localRecordGroups = store.localRecordGroups;
  final termCatalog = store.termCatalog;
  final courses = store.courses;
  final unfollowedCourseKeys = <String>{
    for (final course in courses)
      if (!store.follows(course.key)) course.key,
  };
  final nowMinute = now.millisecondsSinceEpoch ~/ 60000;
  final cached = _homeProjectionCache;
  if (!recoveryActive &&
      cached != null &&
      cached.matches(
        store: store,
        homeCatalog: homeCatalog,
        localRecordGroups: localRecordGroups,
        termCatalog: termCatalog,
        courses: courses,
        unfollowedCourseKeys: unfollowedCourseKeys,
        query: query,
        typeFilter: typeFilter,
        deadlineFilter: deadlineFilter,
        courseKey: courseKey,
        sortOrder: sortOrder,
        completingManualIds: completingManualIds,
        nowMinute: nowMinute,
      )) {
    filtersActive = cached.filtersActive;
    coursework = cached.coursework;
    catalogAssignments = cached.catalogAssignments;
    displayIndex = cached.displayIndex;
    displayAssignments = cached.displayAssignments;
    options = cached.options;
    items = cached.items;
    selectedCourseIdle = cached.selectedCourseIdle;
    sortedTimelineItems = cached.sortedTimelineItems;
    plans = cached.plans;
    plannedIds = cached.plannedIds;
    dueSummary = cached.dueSummary;
    upcomingExam = cached.upcomingExam;
    hasManualItems = cached.hasManualItems;
    followedCourses = cached.followedCourses;
    activeAgenda = cached.activeAgenda;
  } else {
    filtersActive = query.trim().isNotEmpty ||
        typeFilter != AssignmentTypeFilter.all ||
        courseKey != null ||
        deadlineFilter != AssignmentDeadlineFilter.all;
    coursework = store.courseworkState;
    catalogAssignments = courseKey == null
        ? homeCatalog
        : store.homeCatalogAssignmentsWithSelectedCourse(courseKey);
    displayIndex = courseKey == null
        ? store.homeDisplayIndex
        : AssignmentDisplayIndex.from(catalogAssignments);
    displayAssignments = AssignmentQuery.currentDisplay(
      catalogAssignments,
      now,
      index: displayIndex,
      coursework: coursework,
    );
    options = computeHomeCoursePickerProjection(
      store: store,
      now: now,
      selectedCourseKey: courseKey,
      fallbackDisplayIndex: displayIndex,
    ).options;
    items = !recoveryActive
        ? AssignmentQuery.filterHome(
            catalogAssignments,
            query: query,
            courseKey: courseKey,
            deadline: deadlineFilter,
            type: typeFilter,
            includeHistorical: false,
            index: displayIndex,
            now: now,
            coursework: coursework,
          )
        : displayAssignments
            .where((assignment) => recoveryMatches?.call(assignment) ?? false)
            .toList();
    final selectedCourseName = courseKey == null
        ? null
        : options
            .where((option) => option.courseKey == courseKey)
            .firstOrNull
            ?.name;
    final manualItems = !recoveryActive
        ? HomeManualTimeline.filterManualEntries(
            store.isAuthenticated
                ? store.notebook.entries
                : const <ManualEntry>[],
            query: query,
            selectedCourseName: selectedCourseName,
            deadline: deadlineFilter,
            type: typeFilter,
            keepVisibleIds: completingManualIds,
            now: now,
          )
        : const <ManualEntry>[];
    hasManualItems = manualItems.isNotEmpty;
    selectedCourseIdle = !recoveryActive &&
        courseKey != null &&
        query.trim().isEmpty &&
        deadlineFilter == AssignmentDeadlineFilter.all &&
        typeFilter == AssignmentTypeFilter.all &&
        manualItems.isEmpty &&
        !displayAssignments.any((a) => a.courseKey == courseKey);
    sortedTimelineItems = HomeManualTimeline.mergeAndSort(
      assignments: items,
      manualEntries: manualItems,
      order: sortOrder,
      now: now,
      sourceRecords: catalogAssignments,
      displayIndex: displayIndex,
      prioritizeStartOnly: !recoveryActive,
      coursework: coursework,
      keepVisibleIds: completingManualIds,
    );
    final today = PersonalWorkspace.dayKey(now);
    plans = store.personal.plans.where((p) => p.day == today).toList();
    plannedIds = plans.map((p) => p.assignmentId).toSet();
    dueSummary = HomeDueSummary.from(
      catalogAssignments,
      now: now,
      index: displayIndex,
      coursework: coursework,
      manualEntries: store.isAuthenticated ? store.notebook.entries : const [],
    );
    upcomingExam = !recoveryActive
        ? HomeUpcomingExam.select(
            catalogAssignments,
            now: now,
            index: displayIndex,
            coursework: coursework,
            courseKey: courseKey,
          )
        : null;
    followedCourses = courses.length - unfollowedCourseKeys.length;
    activeAgenda = store.notebook.entries.where((e) => !e.done).length;
    if (!recoveryActive) {
      _homeProjectionCache = _HomeProjectionCacheEntry(
        store: store,
        accountEpoch: store.accountEpoch,
        isAuthenticated: store.isAuthenticated,
        homeCatalog: homeCatalog,
        localRecordGroups: localRecordGroups,
        termCatalog: termCatalog,
        coursework: coursework,
        notebook: store.notebook,
        personal: store.personal,
        courses: List<CourseRef>.of(courses),
        unfollowedCourseKeys: unfollowedCourseKeys,
        query: query,
        typeFilter: typeFilter,
        deadlineFilter: deadlineFilter,
        courseKey: courseKey,
        sortOrder: sortOrder,
        completingManualIds: Set<String>.of(completingManualIds),
        nowMinute: nowMinute,
        filtersActive: filtersActive,
        catalogAssignments: catalogAssignments,
        displayIndex: displayIndex,
        displayAssignments: displayAssignments,
        options: options,
        items: items,
        selectedCourseIdle: selectedCourseIdle,
        sortedTimelineItems: sortedTimelineItems,
        plans: plans,
        plannedIds: plannedIds,
        dueSummary: dueSummary,
        upcomingExam: upcomingExam,
        hasManualItems: hasManualItems,
        followedCourses: followedCourses,
        activeAgenda: activeAgenda,
      );
    }
  }
  final sync = HomeSyncPresentation.from(
    store.syncReport,
    loading: store.isLoading,
    hasCache: catalogAssignments.isNotEmpty || displayAssignments.isNotEmpty,
    hasPreviousData: store.hadCacheBeforeLastSync,
    now: now,
    successAt: store.lastSyncAt,
    serviceWarning: (store.hasNonQuietServiceWarning ||
            store.recoveryWarning != null ||
            store.operationError != null) &&
        store.syncReport.phase == SyncPhase.success,
    widgetWarning: store.serviceWarnings.any((w) => w.contains('小组件')) &&
        store.syncReport.phase == SyncPhase.success,
  );
  final showDueSummary = !recoveryActive &&
      (catalogAssignments.isNotEmpty ||
          displayAssignments.isNotEmpty ||
          hasManualItems ||
          store.syncReport.phase == SyncPhase.success ||
          store.syncReport.lastDataSuccessAt != null ||
          store.lastSyncAt != null);
  final statusText = sync.gentle && sync.action == HomeSyncAction.retry
      ? '${sync.summary} · 重试'
      : sync.showCached
          ? '${sync.summary} · 显示上次记录'
          : sync.summary;
  final buddyMood = busy
      ? JournalPixelBuddyMood.syncing
      : dueSummary.dueToday > 0
          ? JournalPixelBuddyMood.dueToday
          : (showDueSummary &&
                  dueSummary.dueToday == 0 &&
                  (dueSummary.completedToday > 0 ||
                      sortedTimelineItems.isEmpty))
              ? JournalPixelBuddyMood.allClear
              : JournalPixelBuddyMood.idle;
  final homeSnapshot = ClawdPageContextSnapshot(
    tab: ClawdPrimaryTab.home,
    dueToday: dueSummary.dueToday,
    dueIn3Days: dueSummary.dueIn3Days,
    completedToday: dueSummary.completedToday,
    followedCourseCount: followedCourses,
    activeAgendaCount: activeAgenda,
  );
  return HomeViewData(
    filtersActive: filtersActive,
    coursework: coursework,
    catalogAssignments: catalogAssignments,
    displayIndex: displayIndex,
    displayAssignments: displayAssignments,
    options: options,
    items: items,
    sortOrder: sortOrder,
    selectedCourseIdle: selectedCourseIdle,
    sortedTimelineItems: sortedTimelineItems,
    plans: plans,
    plannedIds: plannedIds,
    sync: sync,
    dueSummary: dueSummary,
    showDueSummary: showDueSummary,
    statusText: statusText,
    upcomingExam: upcomingExam,
    buddyMood: buddyMood,
    homeSnapshot: homeSnapshot,
  );
}

({JournalPixelBuddyMood mood, ClawdPageContextSnapshot snapshot})
    prepareHomeClawdState({
  required AssignmentStore store,
  required DateTime now,
  required bool isBusy,
  required String? courseKey,
  required String query,
  required AssignmentDeadlineFilter deadlineFilter,
  required AssignmentTypeFilter typeFilter,
  required Set<String> completingManualIds,
}) {
  final coursework = store.courseworkState;
  final catalogAssignments = courseKey == null
      ? store.homeCatalogAssignments
      : store.homeCatalogAssignmentsWithSelectedCourse(courseKey);
  final displayIndex = courseKey == null
      ? store.homeDisplayIndex
      : AssignmentDisplayIndex.from(catalogAssignments);
  final dueSummary = HomeDueSummary.from(
    catalogAssignments,
    now: now,
    index: displayIndex,
    coursework: coursework,
    manualEntries: store.isAuthenticated ? store.notebook.entries : const [],
  );
  final displayAssignments = AssignmentQuery.currentDisplay(
    catalogAssignments,
    now,
    index: displayIndex,
    coursework: coursework,
  );
  final items = AssignmentQuery.filterHome(
    catalogAssignments,
    query: query,
    courseKey: courseKey,
    deadline: deadlineFilter,
    type: typeFilter,
    includeHistorical: false,
    index: displayIndex,
    now: now,
    coursework: coursework,
  );
  final selectedCourseName = courseKey == null
      ? null
      : store.courses
              .where((course) => course.key == courseKey)
              .firstOrNull
              ?.name ??
          catalogAssignments
              .where((assignment) => assignment.courseKey == courseKey)
              .firstOrNull
              ?.courseName;
  final manualItems = HomeManualTimeline.filterManualEntries(
    store.isAuthenticated ? store.notebook.entries : const <ManualEntry>[],
    query: query,
    selectedCourseName: selectedCourseName,
    deadline: deadlineFilter,
    type: typeFilter,
    keepVisibleIds: completingManualIds,
    now: now,
  );
  final showDueSummary = catalogAssignments.isNotEmpty ||
      displayAssignments.isNotEmpty ||
      manualItems.isNotEmpty ||
      store.syncReport.phase == SyncPhase.success ||
      store.syncReport.lastDataSuccessAt != null ||
      store.lastSyncAt != null;
  final mood = isBusy
      ? JournalPixelBuddyMood.syncing
      : dueSummary.dueToday > 0
          ? JournalPixelBuddyMood.dueToday
          : (showDueSummary &&
                  dueSummary.dueToday == 0 &&
                  (dueSummary.completedToday > 0 ||
                      (items.isEmpty && manualItems.isEmpty)))
              ? JournalPixelBuddyMood.allClear
              : JournalPixelBuddyMood.idle;
  final followedCourses =
      store.courses.where((c) => store.follows(c.key)).length;
  final activeAgenda = store.notebook.entries.where((e) => !e.done).length;
  final snapshot = ClawdPageContextSnapshot(
    tab: ClawdPrimaryTab.home,
    dueToday: dueSummary.dueToday,
    dueIn3Days: dueSummary.dueIn3Days,
    completedToday: dueSummary.completedToday,
    followedCourseCount: followedCourses,
    activeAgendaCount: activeAgenda,
  );
  return (mood: mood, snapshot: snapshot);
}

class HomeTimelineList extends StatelessWidget {
  const HomeTimelineList({
    super.key,
    required this.scrollController,
    required this.store,
    required this.now,
    required this.recoveryQueryParameter,
    required this.recoveryQueryValue,
    required this.headerBlock,
    this.topPadding = 14.0,
    required this.catalogAssignments,
    required this.displayAssignments,
    required this.displayIndex,
    required this.coursework,
    required this.courseOptions,
    required this.sortedTimelineItems,
    required this.plannedIds,
    required this.openingAssignments,
    required this.pinPulseByKey,
    required this.completingPinnedKeyById,
    required this.completingPinnedSnapshot,
    required this.manualActions,
    required this.courseKey,
    required this.typeFilter,
    this.sortOrder = HomeSortOrder.deadlineAsc,
    required this.filtersActive,
    required this.selectedCourseIdle,
    required this.busy,
    required this.onClearCourseFilter,
    required this.onClearAllFilters,
    required this.onOpenAssignment,
    required this.onToggleTodayPlan,
    required this.onTogglePin,
    required this.onOpenContextMenu,
  });

  final ScrollController scrollController;
  final AssignmentStore store;
  final DateTime now;
  final String recoveryQueryParameter;
  final String? recoveryQueryValue;
  final Widget headerBlock;
  final double topPadding;
  final List<Assignment> catalogAssignments;
  final List<Assignment> displayAssignments;
  final AssignmentDisplayIndex displayIndex;
  final LocalCourseworkState coursework;
  final List<HomeCourseFilterOption> courseOptions;
  final List<HomeTimelineItem> sortedTimelineItems;
  final Set<String> plannedIds;
  final Set<String> openingAssignments;
  final Map<String, int> pinPulseByKey;
  final Map<String, String> completingPinnedKeyById;
  final PinnedAssignments? completingPinnedSnapshot;
  final HomeManualActions manualActions;
  final String? courseKey;
  final AssignmentTypeFilter typeFilter;
  final HomeSortOrder sortOrder;
  final bool filtersActive;
  final bool selectedCourseIdle;
  final bool busy;
  final VoidCallback onClearCourseFilter;
  final VoidCallback onClearAllFilters;
  final ValueChanged<String> onOpenAssignment;
  final Future<void> Function(Assignment) onToggleTodayPlan;
  final Future<void> Function(Assignment) onTogglePin;
  final Future<void> Function(
    BuildContext itemContext,
    Assignment assignment,
    Widget previewCard, {
    required bool inTodayPlan,
    bool pinned,
    List<String> pinnedVisibleKeys,
  }) onOpenContextMenu;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final isRecovery = recoveryQueryValue != null;
    final compactDensity = store.display.compact;

    Widget buildCard(
      Assignment a, {
      bool pinned = false,
      bool preview = false,
      bool previewOnly = false,
      Widget? dragHandle,
      VoidCallback? onLongPress,
    }) =>
        AssignmentCard(
          key: preview ? null : ValueKey('assignment-${a.id}'),
          assignment: a,
          examSources: catalogAssignments,
          displayIndex: displayIndex,
          courseworkEntry: store.courseworkEntryFor(a),
          now: now,
          showFullDeadline:
              pinned || isRecovery || sortOrder == HomeSortOrder.courseName,
          showDivider: false,
          enableTapFeedback: false,
          inPinnedSection: pinned,
          dragHandle: preview ? null : dragHandle,
          compact: compactDensity,
          countdown: store.display.countdown,
          deadlinePending: preview ? false : store.isHomeDeadlinePending(a.id),
          hasDeadlineAlert:
              preview ? false : store.activeDeadlineAlertFor(a) != null,
          previewOnly: preview ? false : previewOnly,
          previewSaving: !preview &&
              store.homeSyncProgress?.stage == AssignmentSyncStage.saving,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          onOpenAssignment: preview || AssignmentWebLink.validatedUrl(a) == null
              ? null
              : () => onOpenAssignment(a.id),
          opening: !preview && openingAssignments.contains(a.id),
          onLongPress: preview ? null : onLongPress,
          onTap: preview
              ? () {}
              : () {
                  InteractionFeedback.trigger(store.display);
                  final path = '/assignments/${Uri.encodeComponent(a.id)}';
                  final scope = !isRecovery
                      ? ''
                      : '?$recoveryQueryParameter=$recoveryQueryValue';
                  context.push('$path$scope');
                },
        );

    Widget card(
      Assignment a, {
      bool pinned = false,
      Widget? dragHandle,
      List<String> pinnedVisibleKeys = const [],
    }) {
      final previewOnly = store.isHomeAssignmentPreviewOnly(a.id);
      if (previewOnly) {
        return buildCard(a, pinned: pinned, previewOnly: true);
      }
      final inTodayPlan = plannedIds.contains(a.id);
      final canPin = store.canTogglePin(a);
      final isPinned = store.isPinned(a);
      final pinKey = AssignmentStore.pinKeyOf(a);
      return Builder(
        key: ValueKey('home-timeline-item-$pinKey'),
        builder: (itemContext) {
          final interactiveCard = buildCard(
            a,
            pinned: pinned,
            dragHandle: dragHandle,
            onLongPress: () => onOpenContextMenu(
              itemContext,
              a,
              buildCard(a, pinned: pinned, preview: true),
              inTodayPlan: inTodayPlan,
              pinned: pinned,
              pinnedVisibleKeys: pinnedVisibleKeys,
            ),
          );

          return JournalMicroBounce(
            key: ValueKey('home-micro-bounce-$pinKey'),
            pulse: pinPulseByKey[pinKey] ?? 0,
            child: JournalSwipeTile(
              key: ValueKey('swipe-${a.id}'),
              displayPrefs: store.display,
              rightAction: a.isCompleted
                  ? null
                  : JournalSwipeAction(
                      label: inTodayPlan ? '移出计划' : '今日计划',
                      icon: inTodayPlan
                          ? Icons.playlist_remove_rounded
                          : Icons.playlist_add_check_rounded,
                      color: journal.accent,
                      backgroundColor: journal.sage,
                      onTrigger: () => unawaited(onToggleTodayPlan(a)),
                    ),
              leftAction: !canPin
                  ? null
                  : JournalSwipeAction(
                      label: isPinned ? '取消置顶' : '置顶',
                      icon: isPinned
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                      color: journal.ink,
                      backgroundColor: journal.parchment,
                      onTrigger: () => unawaited(onTogglePin(a)),
                    ),
              child: interactiveCard,
            ),
          );
        },
      );
    }

    Widget timelineCard(
      HomeTimelineItem item, {
      bool pinned = false,
      Widget? dragHandle,
      List<String> pinnedVisibleKeys = const [],
    }) {
      if (item.isManual) {
        return buildHomeManualTile(
          store: store,
          now: now,
          entry: item.manual!,
          actions: manualActions,
          pinned: pinned,
          showFullDeadline:
              pinned || isRecovery || sortOrder == HomeSortOrder.courseName,
          dragHandle: dragHandle,
          pinnedVisibleKeys: pinnedVisibleKeys,
          bouncePulse: pinPulseByKey[item.pinKey] ?? 0,
        );
      }
      return card(
        item.assignment!,
        pinned: pinned,
        dragHandle: dragHandle,
        pinnedVisibleKeys: pinnedVisibleKeys,
      );
    }

    Widget buildEmptyState() {
      if (isRecovery) {
        return const HomeEmptyStateCard(
          icon: Icons.event_available_outlined,
          message: '当前范围没有课业',
        );
      }
      if (selectedCourseIdle) {
        final courseName = store.courses
                .where((course) => course.key == courseKey)
                .firstOrNull
                ?.name ??
            courseOptions
                .where((option) => option.courseKey == courseKey)
                .firstOrNull
                ?.name;
        return HomeEmptyStateCard(
          icon: Icons.event_note_outlined,
          message: '这门课暂无作业和考试',
          actions: [
            JournalPrimaryButton(
              key: const ValueKey('home-course-empty-add'),
              expanded: false,
              label: '为这门课添加待办',
              onPressed: () => manualActions.openEditor(
                context,
                initialCourse: courseName,
              ),
            ),
            JournalSecondaryButton(
              expanded: false,
              label: '查看全部课程',
              onPressed: onClearCourseFilter,
            ),
          ],
        );
      }
      if (filtersActive &&
          (displayAssignments.isNotEmpty ||
              store.assignments.isNotEmpty ||
              (store.isAuthenticated &&
                  store.notebook.entries.any((entry) => !entry.done)))) {
        return HomeEmptyStateCard(
          icon: Icons.filter_alt_off_outlined,
          message: '没有符合搜索、类型或期限条件的记录',
          actions: [
            JournalPrimaryButton(
              expanded: false,
              label: '清除搜索与筛选条件',
              onPressed: onClearAllFilters,
            ),
          ],
        );
      }
      if (store.assignments.isNotEmpty) {
        return HomeEmptyStateCard(
          icon: Icons.inventory_2_outlined,
          message: '本机有已完成、已结束、已隐藏、未关注、历史课堂练习或非课业来源的记录，可在本地记录查看。',
          actions: [
            JournalPrimaryButton(
              expanded: false,
              label: '查看全部本地记录',
              onPressed: () => context.push('/records'),
            ),
            JournalSecondaryButton(
              expanded: false,
              label: '管理课程',
              onPressed: () => context.push('/courses'),
            ),
            JournalSecondaryButton(
              expanded: false,
              label: '添加课业或待办',
              onPressed: () => manualActions.openEditor(
                context,
                initialKind: typeFilter == AssignmentTypeFilter.exam
                    ? ManualEntry.kindExam
                    : ManualEntry.kindTodo,
              ),
            ),
          ],
        );
      }
      return HomeEmptyStateCard(
        icon: busy
            ? Icons.hourglass_top_rounded
            : store.syncReport.phase == SyncPhase.success
                ? Icons.task_alt_rounded
                : Icons.menu_book_rounded,
        message: store.isLoading || store.syncReport.phase == SyncPhase.running
            ? '正在读取课程与作业，请稍候。'
            : store.syncReport.phase == SyncPhase.success
                ? '暂无待办，已读取的作业、任务与考试会显示在这里。'
                : store.syncReport.phase == SyncPhase.failed
                    ? '本次尚未取得作业，请点击右上角刷新继续。'
                    : '点击右上角刷新，开始整理这本课业手记。',
        actions: [
          JournalSecondaryButton(
            expanded: false,
            label: '添加课业或待办',
            onPressed: () => manualActions.openEditor(
              context,
              initialKind: typeFilter == AssignmentTypeFilter.exam
                  ? ManualEntry.kindExam
                  : ManualEntry.kindTodo,
            ),
          ),
        ],
      );
    }

    final completingPinnedKeys = completingPinnedKeyById.values.toSet();
    final timelineSections = sortedTimelineItems.isEmpty
        ? const <HomeTimelineSection>[]
        : buildHomeTimelineSections(
            list: sortedTimelineItems,
            now: now,
            store: store,
            recovery: isRecovery,
            coursework: coursework,
            examSources: catalogAssignments,
            displayIndex: displayIndex,
            keepPinnedKeys: completingPinnedKeys,
            completingPinnedSnapshot: completingPinnedSnapshot,
          );

    return ListView.builder(
      controller: scrollController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      key: PageStorageKey(
        !isRecovery ? 'home-list' : 'home-recovery-$recoveryQueryValue',
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        topPadding,
        16,
        JournalLayout.floatingNavClearance(context),
      ),
      itemCount: 1 + (timelineSections.isEmpty ? 1 : timelineSections.length),
      itemBuilder: (context, index) {
        if (index == 0) return headerBlock;
        if (timelineSections.isEmpty) return buildEmptyState();
        final sectionIndex = index - 1;
        final section = timelineSections[sectionIndex];
        final isEmphasizedSection = section.pinned || section.badge == '今天';
        final useReorderablePinned = section.pinned &&
            (section.items.length >= 2 ||
                (completingPinnedKeys.isNotEmpty &&
                    (completingPinnedSnapshot?.keys.length ?? 0) >= 2));
        final groupCard = useReorderablePinned
            ? JournalGroupedCard(
                emphasized: isEmphasizedSection,
                children: [
                  Builder(
                    builder: (context) {
                      final visualKeys = [
                        for (final item in section.items) item.pinKey,
                      ];
                      final activePinnedKeys = [
                        for (final key in visualKeys)
                          if (!completingPinnedKeys.contains(key)) key,
                      ];
                      return ReorderableListView.builder(
                        shrinkWrap: true,
                        primary: false,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        proxyDecorator: (child, index, animation) => Material(
                          color: journal.sheetElevated,
                          elevation: 4,
                          shadowColor: Colors.black.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: child,
                        ),
                        onReorderStart: (_) =>
                            JournalMotion.selectionTick(store.display),
                        onReorderItem: (oldIndex, newIndex) {
                          if (oldIndex == newIndex) return;
                          final nextVisualKeys = List<String>.of(visualKeys);
                          final moved = nextVisualKeys.removeAt(oldIndex);
                          nextVisualKeys.insert(newIndex, moved);
                          final nextActiveKeys = [
                            for (final key in nextVisualKeys)
                              if (!completingPinnedKeys.contains(key)) key,
                          ];
                          if (nextActiveKeys.length >= 2) {
                            unawaited(store.reorderPinned(nextActiveKeys));
                          }
                        },
                        itemCount: section.items.length,
                        itemBuilder: (context, itemIndex) {
                          final item = section.items[itemIndex];
                          final isCompletingItem =
                              completingPinnedKeys.contains(item.pinKey);
                          final dragHandle =
                              isCompletingItem || activePinnedKeys.length < 2
                                  ? null
                                  : ReorderableDragStartListener(
                                      index: itemIndex,
                                      child: Tooltip(
                                        message: '拖动调整置顶顺序',
                                        child: SizedBox(
                                          width: 34,
                                          height: 48,
                                          child: Center(
                                            child: Icon(
                                              Icons.drag_indicator_rounded,
                                              size: 18,
                                              color: journal.muted,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                          return Column(
                            key: ValueKey('pinned-reorder-${item.pinKey}'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              timelineCard(
                                item,
                                pinned: true,
                                dragHandle: dragHandle,
                                pinnedVisibleKeys: activePinnedKeys,
                              ),
                              if (itemIndex < section.items.length - 1)
                                Padding(
                                  padding: const EdgeInsets.only(left: 70),
                                  child: Divider(
                                    height: 1,
                                    thickness: 0.8,
                                    color: journal.rule,
                                  ),
                                ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ],
              )
            : JournalGroupedCard(
                emphasized: isEmphasizedSection,
                dividerIndent: 70.0,
                children: [
                  for (final item in section.items)
                    timelineCard(item, pinned: section.pinned),
                ],
              );
        if (section.heading == null) return groupCard;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomeDayHeading(
              label: section.heading!,
              top: compactDensity
                  ? (sectionIndex == 0 ? 4 : 10)
                  : (sectionIndex == 0 ? 8 : 18),
              bottom: compactDensity ? 4 : 8,
              tone: section.tone,
              badge: section.badge,
            ),
            groupCard,
          ],
        );
      },
    );
  }
}

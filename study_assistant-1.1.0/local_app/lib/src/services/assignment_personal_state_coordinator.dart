import '../models/assignment.dart';
import '../models/course_term_preferences.dart';
import '../models/home_filters.dart';
import '../models/local_coursework_state.dart';
import '../models/personal_workspace.dart';
import '../models/pinned_assignments.dart';
import '../models/study_notebook.dart';
import 'assignment_grouping.dart';
import 'assignment_query.dart';
import 'course_term_catalog.dart';
import 'coursework_deadline.dart';

/// Pure domain rules for personal plans, pin keys/pruning/reordering,
/// local coursework state mutations, and course term preference updates.
class AssignmentPersonalStateCoordinator {
  const AssignmentPersonalStateCoordinator._();

  /// Returns `true` when two daily plan lists differ in length or fields.
  static bool dailyPlansChanged(
    List<DailyPlanItem> a,
    List<DailyPlanItem> b,
  ) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i].assignmentId != b[i].assignmentId ||
          a[i].day != b[i].day ||
          a[i].minutes != b[i].minutes ||
          a[i].done != b[i].done) {
        return true;
      }
    }
    return false;
  }

  /// Canonical pin key for an assignment or grouped exam.
  static String pinKeyOf(Assignment assignment) =>
      AssignmentGrouping.examKey(assignment) ??
      assignment.courseTaskKey ??
      assignment.id;

  /// Builds all pin aliases associated with [assignment], expanding grouped
  /// exam source aliases when [courseworkGroups] contains the matching group.
  static Set<String> pinAliases(
    Assignment assignment, {
    Iterable<CourseworkGroup> courseworkGroups = const [],
  }) {
    final key = pinKeyOf(assignment);
    final aliases = <String>{
      key,
      assignment.id,
      if (assignment.courseTaskKey != null) assignment.courseTaskKey!,
    };
    if (AssignmentGrouping.examKey(assignment) != null) {
      final group =
          courseworkGroups.where((item) => item.key == key).firstOrNull;
      if (group != null) {
        for (final source in group.sources) {
          aliases.add(source.id);
          if (source.courseTaskKey != null) {
            aliases.add(source.courseTaskKey!);
          }
        }
      }
    }
    return aliases;
  }

  /// Computes the migrated and pruned [PinnedAssignments] snapshot given all
  /// local coursework groups, active manual notebook entries, and [now].
  static PinnedAssignments computePrunedPins({
    required PinnedAssignments current,
    required Iterable<CourseworkGroup> localRecordGroups,
    required StudyNotebook notebook,
    required DateTime now,
    required bool Function(Assignment assignment) isLocallyCompleted,
  }) {
    final aliasToCanonical = <String, String>{};
    final explicitlyCompletedOrHiddenKeys = <String>{};
    for (final group in localRecordGroups) {
      final canonical = pinKeyOf(group.primary);
      for (final alias in pinAliases(group.primary)) {
        aliasToCanonical[alias] = canonical;
      }
      for (final source in group.sources) {
        for (final alias in pinAliases(source)) {
          aliasToCanonical[alias] = canonical;
        }
      }
      if (group.hidden ||
          group.primary.isCompleted ||
          isLocallyCompleted(group.primary) ||
          AssignmentQuery.isExamEnded(group.primary, now)) {
        explicitlyCompletedOrHiddenKeys.add(canonical);
        explicitlyCompletedOrHiddenKeys.addAll(pinAliases(group.primary));
        for (final source in group.sources) {
          explicitlyCompletedOrHiddenKeys.addAll(pinAliases(source));
        }
      }
    }
    for (final key in current.keys.where(ManualEntry.isManualKey)) {
      final id = key.substring(ManualEntry.pinPrefix.length);
      if (!notebook.hasActiveEntry(id)) {
        explicitlyCompletedOrHiddenKeys.add(key);
      }
    }
    return current.migrateAndPrune(
      aliasToCanonical: aliasToCanonical,
      explicitlyCompletedOrHiddenKeys: explicitlyCompletedOrHiddenKeys,
    );
  }

  /// Validates and reorders only the visible pinned subset while keeping
  /// filtered-out pinned keys anchored in their existing slots.
  ///
  /// Returns `null` when [visibleOrderedKeys] is empty, contains duplicates,
  /// references non-pinnable/unpinned keys, or fails slot validation.
  static PinnedAssignments? validateAndReorderVisiblePins({
    required PinnedAssignments current,
    required List<String> visibleOrderedKeys,
    required Set<String> pinnableKeys,
  }) {
    final cleanOrdered = [
      for (final raw in visibleOrderedKeys)
        if (raw.trim().isNotEmpty) raw.trim(),
    ];
    if (cleanOrdered.isEmpty ||
        cleanOrdered.toSet().length != cleanOrdered.length ||
        cleanOrdered.any(
          (key) => !pinnableKeys.contains(key) || !current.keys.contains(key),
        )) {
      return null;
    }
    return current.reorderVisible(cleanOrdered, cleanOrdered.toSet());
  }

  /// Computes the target [LocalCourseworkState] for a manual deadline change,
  /// returning `null` if the target is an exam or cannot accept a manual date.
  static LocalCourseworkState? computeManualDeadlineState({
    required LocalCourseworkState currentState,
    required Assignment target,
    required DateTime? at,
  }) {
    if (target.isExam) return null;
    if (at != null &&
        !CourseworkDeadline.canSetManualDeadline(
          target,
          entry: CourseworkDeadline.entryFor(target, currentState),
        )) {
      return null;
    }
    return currentState.withManualDeadline(
      CourseworkDeadline.keyFor(target),
      CourseworkDeadline.aliasesFor(target),
      at,
    );
  }

  /// Computes the target [LocalCourseworkState] for toggling local completion.
  static LocalCourseworkState computeLocallyCompletedState({
    required LocalCourseworkState currentState,
    required Assignment target,
    required bool completed,
  }) =>
      currentState.withLocallyCompleted(
        CourseworkDeadline.keyFor(target),
        CourseworkDeadline.aliasesFor(target),
        completed,
      );

  /// Normalizes and deduplicates non-empty course keys.
  static Set<String> normalizeCourseKeys(Iterable<String> courseKeys) =>
      courseKeys.where((k) => k.trim().isNotEmpty).toSet();

  /// Returns `true` when a batch course term update carries any actual mutation.
  static bool hasBatchCourseTermChanges({
    required Set<String> courseKeys,
    bool updateManualTerm = false,
    CourseArchiveMode? archiveMode,
    CourseBlockMode? blockMode,
  }) =>
      courseKeys.isNotEmpty &&
      (updateManualTerm || archiveMode != null || blockMode != null);

  /// Applies a batch of manual term, archive mode, and block mode updates.
  static CourseTermPreferences applyBatchCourseTermUpdates({
    required CourseTermPreferences current,
    required Set<String> courseKeys,
    AcademicTerm? manualTerm,
    bool updateManualTerm = false,
    CourseArchiveMode? archiveMode,
    CourseBlockMode? blockMode,
  }) {
    var next = current;
    if (updateManualTerm) {
      next = next.withBatchManualTerm(courseKeys, manualTerm?.key);
    }
    if (archiveMode != null) {
      for (final key in courseKeys) {
        next = next.withArchiveMode(key, archiveMode);
      }
    }
    if (blockMode != null) {
      next = next.withBatchBlockMode(courseKeys, blockMode);
    }
    return next;
  }

  /// Returns a [HomeFilters] copy with `courseKey` cleared when the currently
  /// selected course was part of [updatedCourseKeys] and is now blocked;
  /// returns `null` when no filter change is required.
  static HomeFilters? clearedCourseFilterIfBlocked({
    required HomeFilters currentFilters,
    required Set<String> updatedCourseKeys,
    required bool Function(String courseKey) isCourseBlocked,
  }) {
    final selectedCourseKey = currentFilters.courseKey;
    if (selectedCourseKey == null ||
        !updatedCourseKeys.contains(selectedCourseKey) ||
        !isCourseBlocked(selectedCourseKey)) {
      return null;
    }
    return HomeFilters(
      query: currentFilters.query,
      courseKey: null,
      deadline: currentFilters.deadline,
      sortOrder: currentFilters.sortOrder,
      type: currentFilters.type,
    );
  }

  /// Dismisses recall for [courseKey] and resets its archive mode to auto.
  static CourseTermPreferences applyDismissCourseRecall({
    required CourseTermPreferences current,
    required String courseKey,
    required DateTime? latestRecallEventUtc,
    required DateTime now,
  }) {
    final cursor = latestRecallEventUtc ?? now.toUtc();
    return current
        .withArchiveMode(courseKey, CourseArchiveMode.auto)
        .withDismissedRecallCursor(courseKey, cursor);
  }
}

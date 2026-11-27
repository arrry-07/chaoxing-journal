import '../models/display_preferences.dart';
import '../models/home_filters.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_version.dart';
import '../local/chaoxing_api_parser.dart';
import '../local/chaoxing_assignment_parser.dart';
import '../local/chaoxing_local_client.dart';
import '../local/chaoxing_sync_diagnostics_exporter.dart';
import '../local/local_assignment_repository.dart';
import '../models/assignment.dart';
import '../models/assignment_sync_progress.dart';
import '../models/course_chapter_progress.dart';
import '../models/course_notice.dart';
import '../models/sync_report.dart';
import '../models/sync_scope.dart';
import '../models/course.dart';
import 'assignment_query.dart';
import 'assignment_grouping.dart';
import 'local_notification_service.dart';
import 'manual_attachment_service.dart';
import 'personal_file_service.dart';
import 'reminder_rule_store.dart';
import 'secure_session_store.dart';
import 'widget_snapshot_service.dart';
import 'assignment_change_log.dart';
import 'account_identity.dart';
import 'assignment_reminder_planner.dart';
import 'background_check_settings.dart';
import 'background_reminder_gateway.dart';
import 'daytime_check_policy.dart';
import '../models/assignment_change.dart';
import '../models/backup_snapshot.dart';
import '../models/course_term_preferences.dart';
import '../models/local_coursework_state.dart';
import '../models/personal_workspace.dart';
import '../models/pinned_assignments.dart';
import '../models/reminder_history.dart';
import '../models/study_notebook.dart';
import 'assignment_personal_state_coordinator.dart';
import 'assignment_reminder_coordinator.dart';
import 'assignment_session_coordinator.dart';
import 'assignment_sync_coordinator.dart';
import 'course_term_catalog.dart';
import 'coursework_deadline.dart';

part 'assignment_store_personal.dart';
part 'assignment_store_session.dart';
part 'assignment_store_sync.dart';
part 'assignment_store_reminders.dart';

class ReturnCheckConfirmation {
  const ReturnCheckConfirmation({
    required this.id,
    required this.accountEpoch,
    required this.assignmentId,
    required this.title,
    required this.message,
    required this.confirmedAt,
  });

  final int id;
  final int accountEpoch;
  final String assignmentId;
  final String title;
  final String message;
  final DateTime confirmedAt;
}

class BackgroundCheckResult {
  const BackgroundCheckResult({
    required this.success,
    required this.skipped,
    required this.nextTargetAt,
    this.message,
    this.skipReason,
    this.remoteReadInvoked = false,
  });

  static const outsideWindowSkipReason = 'outsideWindow';

  final bool success;
  final bool skipped;
  final DateTime? nextTargetAt;
  final String? message;
  final String? skipReason;
  final bool remoteReadInvoked;
}

class AssignmentStore extends ChangeNotifier {
  static const defaultAutoSyncIntervalMinutes =
      DaytimeCheckPolicy.defaultIntervalMinutes;
  static const _serverBackoffKey = 'background_server_backoff_until_v1';
  static const _notificationClickMissingKey = 'notification_click_missing_v1';
  static const _privacyCleanupPendingKey =
      'notification_privacy_cleanup_pending_v1';
  static const _privacyVerifiedHiddenKey =
      'notification_privacy_verified_hidden_v1';
  static const _nativeCleanupAccountsKey = 'native_account_cleanup_pending_v1';
  static const _legacyScheduleCleanupKey =
      'legacy_assignment_schedule_cleanup_v2';
  static const _historyPurgeRequestKey = 'reminder_history_purge_request_v1';
  static const _historyPurgeGenerationKey =
      'reminder_history_purge_generation_v1';

  AssignmentStore({
    required this.sessionStore,
    required this.notificationService,
    required this.widgetSnapshotService,
    this.personalFileService = const PersonalFileService(),
    ManualAttachmentService? manualAttachmentService,
    LocalAssignmentRepository? repository,
    ChaoxingLocalClient? chaoxingClient,
    ReminderRuleStore? reminderRuleStore,
    BackgroundReminderGateway backgroundReminderGateway =
        const BackgroundReminderGateway(),
    this.backgroundCheckSettingsStore = const BackgroundCheckSettingsStore(),
    bool manageBackgroundSchedule = true,
    this.nativeLeaseOwner,
    this.notificationRemoteStart,
    this.backgroundSignalVersion,
    this.reminderHistoryEnabled = false,
    this.nativeReminderDeliveryEnabled = false,
    DateTime Function()? clock,
  })  : manualAttachmentService =
            manualAttachmentService ?? ManualAttachmentService(),
        repository = repository ??
            LocalAssignmentRepository(
              backgroundReminderGateway: backgroundReminderGateway,
              writeLeaseOwner: nativeLeaseOwner,
            ),
        chaoxingClient = chaoxingClient ?? ChaoxingLocalClient(),
        reminderRuleStore = reminderRuleStore ?? ReminderRuleStore(),
        backgroundReminderGateway = backgroundReminderGateway,
        _manageBackgroundSchedule = manageBackgroundSchedule,
        _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  final SecureSessionStore sessionStore;
  final LocalNotificationService notificationService;
  final WidgetSnapshotService widgetSnapshotService;
  final PersonalFileService personalFileService;
  final ManualAttachmentService manualAttachmentService;
  final LocalAssignmentRepository repository;
  final ChaoxingLocalClient chaoxingClient;
  final ReminderRuleStore reminderRuleStore;
  final BackgroundReminderGateway backgroundReminderGateway;
  final BackgroundCheckSettingsStore backgroundCheckSettingsStore;
  final bool _manageBackgroundSchedule;
  final String? nativeLeaseOwner;
  final NotificationRemoteStartContext? notificationRemoteStart;
  final int? backgroundSignalVersion;
  final bool reminderHistoryEnabled;
  final bool nativeReminderDeliveryEnabled;
  final changeLog = AssignmentChangeLog();
  PersonalWorkspace personal = PersonalWorkspace();
  StudyNotebook notebook = StudyNotebook();
  HomeFilters homeFilters = const HomeFilters();
  CourseNoticeCollection _courseNotices = CourseNoticeCollection();
  CourseChapterCatalog _courseChapters = CourseChapterCatalog();
  bool _isChapterSyncing = false;
  String? _chapterSyncProgressText;

  CourseNoticeCollection get courseNotices => _courseNotices;
  int get unreadCourseNoticeCount => _courseNotices.primaryUnreadCount;
  CourseChapterCatalog get courseChapters => _courseChapters;
  int get pendingChapterSectionCount => _courseChapters.totalPendingSections;
  bool get isChapterSyncing => _isChapterSyncing;
  String? get chapterSyncProgressText => _chapterSyncProgressText;

  String exportSanitizedSyncDiagnostics() => _exportSanitizedSyncDiagnostics();

  Future<void>? _filterWrites;

  Future<bool> saveHomeFilters(HomeFilters next, int expectedEpoch) =>
      _saveHomeFilters(next, expectedEpoch);

  Future<bool> saveNotebook(
          StudyNotebook Function(StudyNotebook) update, int expectedEpoch) =>
      _saveNotebook(update, expectedEpoch);

  int get accountEpoch => _generation;
  int get reminderHistoryGeneration => _reminderHistoryGeneration;

  Future<bool> savePersonal(
          PersonalWorkspace Function(PersonalWorkspace) update,
          int expectedEpoch) =>
      _savePersonal(update, expectedEpoch);

  Future<bool> markNoticeLocalRead(
    String noticeId, {
    bool read = true,
    int expectedEpoch = -1,
  }) =>
      _markNoticeLocalRead(noticeId, read: read, expectedEpoch: expectedEpoch);

  Future<bool> markAllNoticesLocalRead({Iterable<String>? noticeIds}) =>
      _markAllNoticesLocalRead(noticeIds: noticeIds);

  Future<bool> syncCourseChapters({String? courseKey}) =>
      _syncCourseChapters(courseKey: courseKey);

  Future<ManualEntry?> createReminderFromNotice(
    CourseNotice notice, {
    required DateTime remindAt,
    int expectedEpoch = -1,
  }) =>
      _createReminderFromNotice(
        notice,
        remindAt: remindAt,
        expectedEpoch: expectedEpoch,
      );

  Future<ManualEntry?> createTodoFromChapterNode(
    CourseChapterSnapshot snapshot,
    ChapterNode node, {
    DateTime? remindAt,
    int minutes = 30,
    int expectedEpoch = -1,
  }) =>
      _createTodoFromChapterNode(
        snapshot,
        node,
        remindAt: remindAt,
        minutes: minutes,
        expectedEpoch: expectedEpoch,
      );

  List<AssignmentChange> changes = [];
  Set<String> _acknowledgedDeadlineChangeIds = <String>{};
  String? returnCheckMessage;
  String? _visitedAssignment;
  int? _visitGeneration;
  int _nextVisitTicket = 0;
  int? _activeVisitTicket;
  bool _visitLeftApp = false;
  int _nextConfirmationId = 0;
  ReturnCheckConfirmation? _pendingReturnConfirmation;

  ReturnCheckConfirmation? get pendingReturnConfirmation =>
      _pendingReturnConfirmation;

  ReturnCheckConfirmation? consumeReturnCheckConfirmation() =>
      _consumeReturnCheckConfirmation();

  void beginAssignmentVisit(String id) => _beginAssignmentVisit(id);

  void cancelAssignmentVisit(String id) => _cancelAssignmentVisit(id);

  void markAssignmentVisitLeftApp() => _markAssignmentVisitLeftApp();

  void dismissReturnCheck() => _dismissReturnCheck();

  Future<void> checkReturnedAssignment() => _checkReturnedAssignment();

  SyncReport syncReport = const SyncReport();
  HistoricalSweepState _historicalSweepState =
      const HistoricalSweepState.empty();
  HistoricalSweepState get historicalSweepState => _historicalSweepState;
  AssignmentSyncScope _lastRequestedSyncScope = AssignmentSyncScope.current;
  Set<String> _lastTargetedCourseKeys = const {};
  List<SyncSourceResult> _lastSyncSourceResults = const [];
  int _generation = 0;
  bool _disposed = false, _loginRunning = false;
  String get syncSummary => _syncSummary;

  bool get hasWidgetWarningOnly => _warningBuckets.hasWidgetWarningOnly(
        hasRecoveryWarnings: _recoveryWarnings.isNotEmpty,
        hasOperationError: _error != null,
        hasRepositoryRecoveryWarning: repository.recoveryWarning != null,
      );

  bool get hasNonQuietServiceWarning =>
      _warningBuckets.isNotEmpty && !hasWidgetWarningOnly;
  bool _authenticated = false;
  bool _loading = false;
  bool _agreementAccepted = false;
  String? _error;
  String? _account;
  String? _chaoxingDisplayName;
  String? _chaoxingAvatarUrl;
  DateTime? _lastSyncAt;
  List<int> _reminderOffsetsMinutes = ReminderRuleStore.defaultOffsetsMinutes;
  bool _allowUrgentDeadlineNightBreakthrough = false;
  static const _deadlineChannelV3AutoMigratedKey =
      LocalAssignmentRepository.deadlineChannelV3AutoMigratedKey;
  String _deadlineChannelId = LocalNotificationService.assignmentV3Channel;
  bool _migratedDeadlineChannelToV3ThisRestore = false;
  BackgroundCheckSettings _backgroundCheckSettings =
      const BackgroundCheckSettings(
    enabled: true,
    intervalMinutes: defaultAutoSyncIntervalMinutes,
    notificationListenerEnabled: false,
    newAssignmentReminderEnabled: true,
    migratedFromLegacy: false,
  );
  final List<Assignment> _assignments = [];
  bool _autoSyncRunning = false;
  bool _nativeReminderAvailable = false;
  bool _reminderHistoryReady = false;
  int _reminderHistoryGeneration = 0;
  String? _accountHash;
  int _nativeSessionEpoch = 0;
  DateTime? _serverBackoffUntil;
  String? _backgroundWarning;

  bool get isAuthenticated => _authenticated;
  bool get isLoading => _loading;
  bool get agreementAccepted => _agreementAccepted;
  final ReminderWarningBuckets _warningBuckets = ReminderWarningBuckets();
  final List<String> _recoveryWarnings = [];
  List<String> get serviceWarnings => _warningBuckets.serviceWarnings;
  List<String> get manualSaveWarnings => _warningBuckets.manualSaveWarnings;
  String? get recoveryWarning => repository.recoveryWarning;
  String? get operationError => _error;
  String? get error => _combinedError;

  String saveFeedback(
    bool saved, {
    required String successMessage,
    required String failureMessage,
    Iterable<String>? warnings,
  }) =>
      _saveFeedback(
        saved,
        successMessage: successMessage,
        failureMessage: failureMessage,
        warnings: warnings,
      );

  List<Assignment> _hiddenAssignments = [];
  List<Assignment> get hiddenAssignments =>
      List.unmodifiable(_hiddenAssignments);
  DateTime? _lastSyncAttemptAt;
  String? get account => _account;
  String? get accountHash => _accountHash;
  int get nativeSessionEpoch => _nativeSessionEpoch;
  String? get profileAvatarUrl => _chaoxingAvatarUrl;

  String get profileDisplayName => _profileDisplayName;

  DateTime? get lastSyncAt => _effectiveLastSyncAt;
  int get autoSyncIntervalMinutes => _backgroundCheckSettings.enabled
      ? _backgroundCheckSettings.intervalMinutes
      : 0;
  int get backgroundCheckIntervalMinutes =>
      _backgroundCheckSettings.intervalMinutes;
  bool get backgroundCheckEnabled => _backgroundCheckSettings.enabled;
  bool get notificationListenerEnabled =>
      _backgroundCheckSettings.notificationListenerEnabled;
  bool get newAssignmentReminderEnabled =>
      _backgroundCheckSettings.newAssignmentReminderEnabled;
  bool get allowUrgentDeadlineNightBreakthrough =>
      _allowUrgentDeadlineNightBreakthrough;
  String get activeDeadlineChannelId => _deadlineChannelId;
  bool get isUsingV3DeadlineChannel =>
      _deadlineChannelId == LocalNotificationService.assignmentV3Channel;
  bool get isUsingV2DeadlineChannel =>
      _deadlineChannelId == LocalNotificationService.assignmentV2Channel;
  String? get backgroundWarning => _backgroundWarning;
  DateTime? get nextBackgroundCheckAt => _nextBackgroundCheckAt;

  Future<BackgroundReminderHealth?> inspectBackgroundReminderHealth() =>
      _inspectBackgroundReminderHealth();

  List<int> get reminderOffsetsMinutes =>
      List.unmodifiable(_reminderOffsetsMinutes);
  List<Assignment> get assignments => List.unmodifiable(_assignments);
  final Set<String> _unfollowed = {};
  PinnedAssignments _pinned = const PinnedAssignments.empty();
  LocalCourseworkState _courseworkState = const LocalCourseworkState.empty();
  CourseTermPreferences _courseTermPreferences =
      const CourseTermPreferences.empty();
  CourseTermCatalog? _termCatalogCache;
  bool _pinsNeedSave = false;
  bool _journalRestoreFailed = false;

  static String _pinKey(Assignment assignment) =>
      AssignmentGrouping.examKey(assignment) ??
      assignment.courseTaskKey ??
      assignment.id;

  static String pinKeyOf(Assignment assignment) => _pinKey(assignment);

  static String manualPinKeyOf(ManualEntry entry) => entry.pinKey;

  PinnedAssignments get pinnedAssignments => _pinned;
  List<String> get pinnedKeys => _pinned.keys;
  bool get hasManualPinOrder => _pinned.manuallyOrdered;
  LocalCourseworkState get courseworkState => _courseworkState;
  LocalCourseworkEntry? courseworkEntryFor(Assignment assignment) =>
      _courseworkEntryFor(assignment);
  CourseworkDeadline? effectiveDeadlineFor(Assignment assignment) =>
      _effectiveDeadlineFor(assignment);
  DateTime? manualDeadlineFor(Assignment assignment) =>
      _manualDeadlineFor(assignment);
  bool isLocallyCompleted(Assignment assignment) =>
      _isLocallyCompleted(assignment);
  bool isEffectivelyCompleted(Assignment assignment) =>
      _isEffectivelyCompleted(assignment);

  AssignmentChange? latestDeadlineChangeFor(Assignment assignment) =>
      _latestDeadlineChangeFor(assignment);

  AssignmentChange? activeDeadlineAlertFor(Assignment assignment) =>
      _activeDeadlineAlertFor(assignment);

  Future<bool> acknowledgeDeadlineAlert(String changeId) =>
      _acknowledgeDeadlineAlert(changeId);

  Future<bool> setManualDeadline(Assignment assignment, DateTime? at) =>
      _setManualDeadline(assignment, at);

  Future<bool> setLocallyCompleted(
    Assignment assignment,
    bool completed,
  ) =>
      _setLocallyCompleted(assignment, completed);

  final _authNotifier = ValueNotifier<int>(0);
  bool _lastNotifiedAuth = false;
  int _lastNotifiedEpoch = 0;
  String? _lastNotifiedHash;

  /// Fires only when authentication status, account epoch, or account hash
  /// changes, so GoRouter does not re-evaluate redirects on filter/plan/sync
  /// ticks.
  Listenable get authListenable => _authNotifier;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
    if (_authenticated != _lastNotifiedAuth ||
        _generation != _lastNotifiedEpoch ||
        _accountHash != _lastNotifiedHash) {
      _lastNotifiedAuth = _authenticated;
      _lastNotifiedEpoch = _generation;
      _lastNotifiedHash = _accountHash;
      _authNotifier.value++;
    }
  }

  void _notify() => notifyListeners();

  bool isPinned(Assignment assignment) => _isPinned(assignment);

  Set<String>? _pinnableKeysCache;
  int? _pinnableKeysCacheMinute;

  bool canTogglePin(Assignment assignment) => _canTogglePin(assignment);

  Future<bool> togglePin(Assignment assignment) => _togglePin(assignment);

  bool isManualPinned(ManualEntry entry) => _isManualPinned(entry);

  bool canToggleManualPin(ManualEntry entry) => _canToggleManualPin(entry);

  Future<bool> toggleManualPin(ManualEntry entry) => _toggleManualPin(entry);

  Future<bool> reorderPinned(List<String> visibleOrderedKeys) =>
      _reorderPinned(visibleOrderedKeys);

  List<CourseRef> _courses = [];
  List<CourseRef> get courses => List.unmodifiable(_courses);
  bool follows(String key) => !_unfollowed.contains(key);
  CourseTermPreferences get courseTermPreferences => _courseTermPreferences;

  CourseTermCatalog get termCatalog => _termCatalog;

  bool isCourseActive(String key) => _isCourseActive(key);

  Future<bool> setCourseManualTerm(String courseKey, AcademicTerm? term) =>
      _setCourseManualTerm(courseKey, term);

  Future<bool> setCourseArchiveMode(
    String courseKey,
    CourseArchiveMode mode,
  ) =>
      _setCourseArchiveMode(courseKey, mode);

  Future<bool> batchUpdateCourseTerms({
    required Iterable<String> courseKeys,
    AcademicTerm? manualTerm,
    bool updateManualTerm = false,
    CourseArchiveMode? archiveMode,
    CourseBlockMode? blockMode,
  }) =>
      _batchUpdateCourseTerms(
        courseKeys: courseKeys,
        manualTerm: manualTerm,
        updateManualTerm: updateManualTerm,
        archiveMode: archiveMode,
        blockMode: blockMode,
      );

  Future<bool> setCourseBlockMode(
    String courseKey,
    CourseBlockMode mode,
  ) =>
      _setCourseBlockMode(courseKey, mode);

  Future<bool> dismissCourseRecall(String courseKey) =>
      _dismissCourseRecall(courseKey);

  Future<bool> archivePastCourses() => _archivePastCourses();

  List<Assignment> get formalAssignments => _formalAssignments;
  List<CourseworkGroup>? _courseworkGroupsCache;
  List<CourseworkGroup>? _localRecordGroupsCache;
  List<Assignment>? _courseworkSourcesCache;
  List<Assignment>? _statsAssignmentsCache;

  List<CourseworkGroup> get localRecordGroups => _localRecordGroups;

  List<CourseworkGroup> get courseworkGroups => _courseworkGroups;

  List<Assignment> get courseAssignments => _courseAssignments;

  /// Original primary records for statistics across followed courses.
  ///
  /// Uses all non-hidden followed records so past/archived terms remain
  /// inspectable via [statsAssignmentsForScope].
  List<Assignment> get statsAssignments => _statsAssignments;

  List<Assignment> statsAssignmentsForScope(
    CourseTermScope scope, {
    DateTime? now,
  }) =>
      _statsAssignmentsForScope(scope, now: now);

  List<Assignment> homeCatalogAssignmentsWithSelectedCourse(
    String? selectedCourseKey,
  ) =>
      _homeCatalogAssignmentsWithSelectedCourse(selectedCourseKey);

  List<CourseworkGroup> get hiddenCourseworkGroups => _hiddenCourseworkGroups;

  List<CourseworkGroup> get localCourseTaskGroups => _localCourseTaskGroups;

  CourseworkGroup? courseworkGroupFor(String assignmentId) =>
      _courseworkGroupFor(assignmentId);
  bool _privacyCleanupPending = false;
  final Set<String> _pendingNativeCleanupAccounts = <String>{};
  bool get notificationPrivacyPending => _privacyCleanupPending;
  bool get notificationDetails => notificationService.showDetails;
  Future<void> saveNotificationDetails(bool value) =>
      _saveNotificationDetails(value);

  DisplayPreferences display = const DisplayPreferences();
  Future<void>? _displayWrites;

  Future<String?> saveDisplay(DisplayPreferences next) => _saveDisplay(next);

  List<Assignment> get visibleAssignments => _visibleAssignments;
  AssignmentSyncProgress? _homeSyncProgress;
  List<Assignment> _homePreviewAssignments = [];
  Set<String> _homePendingDeadlineIds = {};
  AssignmentSyncProgress? _queuedHomeProgress;
  Timer? _homeProgressTimer;
  bool _hadCacheBeforeLastSync = false;

  bool get hadCacheBeforeLastSync => _hadCacheBeforeLastSync;

  AssignmentSyncProgress? get homeSyncProgress => _homeSyncProgress;

  List<Assignment> get homeDisplayAssignments => _homeDisplayAssignments;

  /// Complete scoped source catalog for the home list, including submitted
  /// homework and ended exams. It retains notice sources for display-time
  /// ordering and stays consistent while a sync preview is published;
  /// current-todo callers continue to use [homeDisplayAssignments].
  List<Assignment> get homeCatalogAssignments => _homeCatalogAssignments;

  List<Assignment>? _homeCatalogCache;
  AssignmentDisplayIndex? _homeDisplayIndex;
  Set<String>? _persistedIdsCache;
  Set<String>? _previewIdsCache;

  AssignmentDisplayIndex get homeDisplayIndex => _resolveHomeDisplayIndex;

  void _invalidateHomeDisplayIndex() {
    _termCatalogCache = null;
    _homeCatalogCache = null;
    _homeDisplayIndex = null;
    _courseworkGroupsCache = null;
    _localRecordGroupsCache = null;
    _courseworkSourcesCache = null;
    _statsAssignmentsCache = null;
    _pinnableKeysCache = null;
    _pinnableKeysCacheMinute = null;
    _persistedIdsCache = null;
    _previewIdsCache = null;
  }

  bool isHomeDeadlinePending(String assignmentId) =>
      _homePendingDeadlineIds.contains(assignmentId);

  bool isHomeAssignmentPreviewOnly(String assignmentId) =>
      _isHomeAssignmentPreviewOnly(assignmentId);

  Future<void> followCourse(String key, bool followed) =>
      _followCourse(key, followed);

  Map<String, dynamic>? get syncStatus => _syncStatus;

  Assignment? findAssignment(String assignmentId) =>
      _findAssignment(assignmentId);

  /// Resolves either visible or hidden assignments on the current account,
  /// allowing read-only detail inspection and restore without exposing hidden
  /// records to [findAssignment] notification or visit callers.
  Assignment? findAnyAssignment(String assignmentId) =>
      _findAnyAssignment(assignmentId);

  Future<void> restoreSession() => _restoreSession();

  Future<void> loginChaoxing({
    required String account,
    required String password,
    required bool agreementAccepted,
  }) =>
      _loginChaoxing(
          account: account,
          password: password,
          agreementAccepted: agreementAccepted);

  Future<String?>? _syncInFlight;
  int _syncOperation = 0;
  bool _syncCancelled = false;
  bool _remoteReadInvoked = false;
  String? _syncSkipReason;
  int? _syncSkipReasonOperation;
  int? _syncSkipReasonGeneration;

  /// Stopping is explicit: it invalidates the current operation and cancels
  /// transport before the serial cleanup queue, so a cancelled fetch can never
  /// be committed as a successful empty sync.
  void cancelSynchronization() => _cancelSynchronization();

  Future<void> syncAssignments() =>
      syncAssignmentsForTrigger(BackgroundSyncTrigger.manual);

  Future<void> syncAllTerms() => syncAssignmentsForTrigger(
        BackgroundSyncTrigger.manual,
        scope: AssignmentSyncScope.all,
      );

  Future<void> syncTargetedCourses(Set<String> courseKeys) =>
      syncAssignmentsForTrigger(
        BackgroundSyncTrigger.manual,
        scope: AssignmentSyncScope.targeted,
        targetedCourseKeys: courseKeys,
      );

  Future<void> retryLastSyncAfterVerification() => syncAssignmentsForTrigger(
        BackgroundSyncTrigger.manual,
        scope: _lastRequestedSyncScope,
        targetedCourseKeys: _lastTargetedCourseKeys,
      );

  Future<void> syncAssignmentsForTrigger(
    BackgroundSyncTrigger trigger, {
    bool skipTaskEngineProbe = false,
    AssignmentSyncScope? scope,
    Set<String>? targetedCourseKeys,
  }) =>
      _syncAssignmentsForTrigger(trigger,
          skipTaskEngineProbe: skipTaskEngineProbe,
          scope: scope,
          targetedCourseKeys: targetedCourseKeys);

  Future<void> importAssignmentsFromHtml(String html) =>
      _importAssignmentsFromHtml(html);

  Future<void> refreshAssignments() => _run(_reloadJournal);

  Future<bool> restoreLocalBackup(BackupSnapshot snapshot) =>
      _restoreLocalBackup(snapshot);

  Future<void> updateCompletion(String assignmentId, bool completed) =>
      setAssignmentsHidden([assignmentId], completed);

  Future<bool> hideAssignment(String assignmentId) =>
      setAssignmentsHidden([assignmentId], true);

  Future<bool> setAssignmentsHidden(
    Iterable<String> assignmentIds,
    bool hidden,
  ) =>
      _setAssignmentsHidden(assignmentIds, hidden);

  Future<bool> setCourseworkGroupHidden(
    CourseworkGroup group,
    bool hidden,
  ) =>
      setAssignmentsHidden(
        group.sources.map((assignment) => assignment.id),
        hidden,
      );

  Future<bool> saveReminderRule(List<int> offsetsMinutes) =>
      _saveReminderRule(offsetsMinutes);

  Future<bool> saveAutoSyncIntervalMinutes(int minutes) =>
      _saveAutoSyncIntervalMinutes(minutes);

  Future<bool> saveBackgroundCheckEnabled(bool enabled) =>
      _saveBackgroundCheckEnabled(enabled);

  Future<bool> saveBackgroundCheckIntervalMinutes(int minutes) =>
      _saveBackgroundCheckIntervalMinutes(minutes);

  Future<bool> saveNotificationListenerEnabled(bool enabled) =>
      _saveNotificationListenerEnabled(enabled);

  Future<bool> saveNewAssignmentReminderEnabled(bool enabled) =>
      _saveNewAssignmentReminderEnabled(enabled);

  Future<bool> saveAllowUrgentDeadlineNightBreakthrough(bool enabled) =>
      _saveAllowUrgentDeadlineNightBreakthrough(enabled);

  Future<bool> saveDeadlineChannelId(String channelId) =>
      _saveDeadlineChannelId(channelId);

  Future<TestDeadlineNotificationOutcome> sendTestDeadlineNotification({
    int delayMillis = 3000,
  }) =>
      _sendTestDeadlineNotification(delayMillis: delayMillis);

  /// Reloads durable sync timestamps and journal records if a headless
  /// background check persisted newer state while this foreground store was idle.
  Future<bool> reconcileExternalSyncState() => _reconcileExternalSyncState();

  Future<bool> runDueAutoSync({DateTime? now}) => _runDueAutoSync(now: now);

  Future<BackgroundCheckResult> runBackgroundAutomaticCheck(
    BackgroundSyncTrigger trigger,
  ) =>
      _runBackgroundAutomaticCheckAndRecord(trigger);

  Future<void> logout() => _logout();

  @visibleForTesting
  void replaceAssignmentsForTest(List<Assignment> assignments) =>
      _replaceAssignmentsForTest(assignments);

  bool get reminderHistoryAvailable => _reminderHistoryReady;

  Future<ReminderHistoryPage> loadReminderHistory({
    int? snapshotMaxId,
    int? beforeId,
    String? category,
    List<ReminderSubjectRef> subjectRefs = const [],
  }) =>
      _loadReminderHistory(
        snapshotMaxId: snapshotMaxId,
        beforeId: beforeId,
        category: category,
        subjectRefs: subjectRefs,
      );

  Future<ReminderSubjectEvidence> inspectReminderSubjects(
    List<ReminderSubjectRef> refs,
  ) =>
      _inspectReminderSubjects(refs);

  Future<ReminderExplanation> explainReminder({
    required String kind,
    required String id,
  }) =>
      _explainReminder(kind: kind, id: id);

  Future<void> retryReminderRecovery() => _retryReminderRecovery();

  bool _needsProfileRecovery = false;

  static int normalizeAutoSyncIntervalMinutes(int minutes) =>
      minutes <= 0 ? 0 : DaytimeCheckPolicy.normalizeIntervalMinutes(minutes);

  Future<void>? _operations;
  _SessionSnapshot? _activeSyncSession;

  Future<void> _run(Future<void> Function() action) {
    // Seed lazily in the caller's zone, including WidgetTester's fake clock.
    // Swallow tail errors on the chain pointer so one unexpected failure never
    // permanently poisons subsequent queued operations.
    final previous = _operations ?? Future<void>.value();
    final result = previous.then((_) => _execute(action));
    _operations =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _execute(Future<void> Function() action) async {
    if (_disposed) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      if (error is _LoginInterruptedException ||
          error is StaleSessionWriteException) {
        return;
      }
      final failedSyncSession = _activeSyncSession;
      if (error is SyncCancelledException) {
        // A stopped operation never advances full-success time and is not
        // merged as an empty snapshot. Already committed data stays committed.
        if (failedSyncSession != null &&
            (failedSyncSession.generation != _generation ||
                failedSyncSession.account != _account ||
                _disposed)) {
          return;
        }
        _error = AssignmentSyncCoordinator.cancelledMessage;
        syncReport = AssignmentSyncCoordinator.cancelledReport(
          syncReport,
          lastFullSuccessAt: _lastSyncAt,
          succeededCourses: chaoxingClient.succeededCourses,
          failedCourses: chaoxingClient.failedCourses,
        );
        try {
          await _persistSyncReport(
            session: failedSyncSession?.withoutSyncOperation(),
          );
        } catch (_) {
          // The in-memory cancelled phase still prevents a success claim.
        }
        return;
      }
      if (failedSyncSession != null &&
          (failedSyncSession.generation != _generation ||
              failedSyncSession.account != _account ||
              _disposed)) {
        return;
      }
      _error = _friendlyError(error);
      if (syncReport.phase == SyncPhase.running) {
        syncReport = AssignmentSyncCoordinator.failedReport(
          syncReport,
          lastAttemptAt: _lastSyncAttemptAt,
          lastFullSuccessAt: _lastSyncAt,
          readIssues: chaoxingClient.issues,
          error: error,
          message: _error!,
        );
        try {
          await _updateServerBackoff(
            syncReport.issues,
            session: failedSyncSession,
          );
        } catch (_) {
          // Backoff mirror failure must not abort failure-report persistence or
          // poison the serial operation queue.
        }
        await _recordBackgroundAttempt(
          attemptedAt: syncReport.attemptedAt ?? DateTime.now(),
          dataSucceeded: syncReport.lastDataSuccessAt?.isAfter(
                syncReport.attemptedAt ??
                    DateTime.fromMillisecondsSinceEpoch(0),
              ) ??
              false,
          fullSucceeded: false,
          failure: _error,
        );
        try {
          await _persistSyncReport(session: failedSyncSession);
        } catch (_) {
          _error = '$_error；同步结果未能保存，请重试';
        }
      }
    } finally {
      _activeSyncSession = null;
      _loading = false;
      _clearHomePreview();
      if (!_disposed) notifyListeners();
    }
  }

  _SessionSnapshot _captureSession({int? syncOperation}) => _SessionSnapshot(
        generation: _generation,
        account: _account,
        authenticated: _authenticated,
        accountHash: _accountHash,
        sessionEpoch: _nativeSessionEpoch,
        syncOperation: syncOperation,
      );

  bool _isSessionStateCurrent({
    required int epoch,
    String? account,
    bool checkAccount = false,
    String? accountHash,
    bool checkAccountHash = false,
    bool? expectedAuthenticated = true,
    bool requireNotDisposed = true,
    int? syncOperation,
  }) {
    if (requireNotDisposed && _disposed) return false;
    if (epoch != _generation) return false;
    if (expectedAuthenticated != null &&
        _authenticated != expectedAuthenticated) {
      return false;
    }
    if (checkAccount && account != _account) return false;
    if (checkAccountHash && accountHash != _accountHash) return false;
    if (syncOperation != null &&
        (_syncCancelled || syncOperation != _syncOperation)) {
      return false;
    }
    return true;
  }

  bool _isSessionCurrent(_SessionSnapshot snap) => _isSessionStateCurrent(
        epoch: snap.generation,
        account: snap.account,
        checkAccount: true,
        expectedAuthenticated: snap.authenticated,
        syncOperation: snap.syncOperation,
      );

  Future<bool> Function() _scopedWriteGateFor(_SessionSnapshot snap) {
    return () async {
      if (!_isSessionCurrent(snap)) return false;
      if (_nativeReminderAvailable &&
          snap.authenticated &&
          snap.accountHash != null &&
          snap.sessionEpoch > 0) {
        final current = await backgroundReminderGateway.isSessionCurrent(
          snap.accountHash!,
          snap.sessionEpoch,
        );
        if (!current || !_isSessionCurrent(snap)) {
          return false;
        }
      }
      return true;
    };
  }

  Future<T> _runScopedWrite<T>(
    _SessionSnapshot snap,
    Future<T> Function(SharedPreferences prefs) action, {
    String rejectedMessage = '账号会话已变化，旧写入已拒绝提交',
  }) =>
      repository.runScopedWrite(
        action,
        account: snap.authenticated ? snap.account : null,
        canCommit: _scopedWriteGateFor(snap),
        rejectedMessage: rejectedMessage,
      );

  Future<bool> _writeScopedPreferenceAndVerify(
    String key,
    String value, {
    _SessionSnapshot? session,
  }) =>
      _runScopedWrite(
        session ?? _captureSession(),
        (prefs) => _writePreferenceAndVerify(prefs, key, value),
      );

  Future<void> _persistSyncReport({_SessionSnapshot? session}) async {
    final encoded = jsonEncode(syncReport.toJson());
    if (!await _writeScopedPreferenceAndVerify(
      'sync_report_v1',
      encoded,
      session: session,
    )) {
      throw StateError('同步结果未能保存');
    }
  }

  Future<bool> _writePreferenceAndVerify(
      SharedPreferences prefs, String key, String value) async {
    try {
      if (await prefs.setString(key, value)) return true;
    } catch (_) {
      // Verify below: a platform write can fail after the durable value changed.
    }
    try {
      await prefs.reload();
      return prefs.getString(key) == value;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _writeBoolPreferenceAndVerify(
      SharedPreferences prefs, String key, bool value) async {
    try {
      if (await prefs.setBool(key, value)) return true;
    } catch (_) {
      // Verify the durable value; the plugin can fail after updating memory.
    }
    try {
      await prefs.reload();
      return prefs.getBool(key) == value;
    } catch (_) {
      return false;
    }
  }

  String _friendlyError(Object error) {
    if (error is LocalStorageWriteException) {
      // Never reclassify a local write failure as a network problem just
      // because the platform error mentions a timeout or connection.
      return error.message;
    }
    final raw = error.toString().replaceFirst('Bad state: ', '');
    if (raw.contains('SocketException') ||
        raw.contains('Failed host lookup') ||
        raw.contains('Connection') ||
        raw.contains('timeout')) {
      return '作业刷新失败，请检查网络后再试。';
    }
    if (raw.contains('没有获取到作业')) {
      return '暂时没有刷新到作业。如果你确认学习通里有未完成作业，请稍后再试。';
    }
    if (raw.contains('同步失败')) {
      return '学习通作业同步失败，请稍后再试。';
    }
    return raw.isEmpty ? '操作没有完成，请稍后再试。' : raw;
  }

  @override
  void dispose() {
    _disposed = true;
    _syncCancelled = true;
    _syncOperation++;
    repository.dispose();
    chaoxingClient.cancelActiveRequests();
    _clearHomePreview();
    _generation++;
    _authNotifier.dispose();
    super.dispose();
  }
}

class _SessionSnapshot {
  const _SessionSnapshot({
    required this.generation,
    required this.account,
    required this.authenticated,
    required this.accountHash,
    required this.sessionEpoch,
    this.syncOperation,
  });

  final int generation;
  final String? account;
  final bool authenticated;
  final String? accountHash;
  final int sessionEpoch;
  final int? syncOperation;

  _SessionSnapshot withoutSyncOperation() => _SessionSnapshot(
        generation: generation,
        account: account,
        authenticated: authenticated,
        accountHash: accountHash,
        sessionEpoch: sessionEpoch,
      );
}

class _LoginInterruptedException implements Exception {
  const _LoginInterruptedException();
}

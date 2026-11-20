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
import '../models/course.dart';
import 'assignment_query.dart';
import 'assignment_grouping.dart';
import 'local_notification_service.dart';
import 'reminder_rule_store.dart';
import 'secure_session_store.dart';
import 'widget_snapshot_service.dart';
import 'assignment_change_log.dart';
import 'account_identity.dart';
import 'assignment_reminder_planner.dart';
import 'background_check_settings.dart';
import 'background_reminder_gateway.dart';
import 'daily_summary.dart';
import 'daytime_check_policy.dart';
import '../models/assignment_change.dart';
import '../models/backup_snapshot.dart';
import '../models/personal_workspace.dart';
import '../models/reminder_history.dart';
import '../models/study_notebook.dart';
import 'reminder_explanation.dart';

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
  })  : repository = repository ??
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
  int get unreadCourseNoticeCount => _courseNotices.unreadCount;
  CourseChapterCatalog get courseChapters => _courseChapters;
  int get pendingChapterSectionCount => _courseChapters.totalPendingSections;
  bool get isChapterSyncing => _isChapterSyncing;
  String? get chapterSyncProgressText => _chapterSyncProgressText;

  String exportSanitizedSyncDiagnostics() =>
      ChaoxingSyncDiagnosticsExporter.exportJson(
        appVersion: AppVersion.display,
        report: syncReport,
        phaseElapsedMs: chaoxingClient.diagnostics.phaseElapsedMs,
        requestTimings: chaoxingClient.requestTimings,
      );

  Future<bool> saveHomeFilters(HomeFilters next, int expectedEpoch) async {
    final account = _account;
    var saved = false;
    await _run(() async {
      if (account == null ||
          !_authenticated ||
          _generation != expectedEpoch ||
          account != _account) {
        return;
      }
      await repository.saveHomeFilters(next, account);
      if (_generation != expectedEpoch || !_authenticated) return;
      homeFilters = HomeFilters.decode(next.encode());
      saved = true;
    });
    return saved;
  }

  Future<bool> saveNotebook(
      StudyNotebook Function(StudyNotebook) update, int expectedEpoch) async {
    final account = _account;
    var saved = false;
    await _run(() async {
      if (account == null ||
          !_authenticated ||
          _generation != expectedEpoch ||
          account != _account) {
        return;
      }
      final next = update(notebook);
      await repository.saveNotebook(next, account);
      if (_generation != expectedEpoch || !_authenticated) return;
      final previous = notebook;
      notebook = StudyNotebook.decode(next.encode());
      saved = true;
      final manualSucceeded = await _afterAssignmentsChanged();
      await _recordManualCancellationOutcomes(
        previous,
        notebook,
        rescheduleSucceeded: manualSucceeded,
      );
    });
    return saved;
  }

  int get accountEpoch => _generation;
  int get reminderHistoryGeneration => _reminderHistoryGeneration;
  Future<bool> savePersonal(
      PersonalWorkspace Function(PersonalWorkspace) update,
      int expectedEpoch) async {
    final account = _account;
    var saved = false;
    await _run(() async {
      if (account == null ||
          !_authenticated ||
          _generation != expectedEpoch ||
          account != _account) {
        return;
      }
      final next = update(personal);
      await repository.savePersonalWorkspace(next, account);
      if (_generation != expectedEpoch || !_authenticated) return;
      personal = PersonalWorkspace.decode(next.encode());
      saved = true;
      await _afterAssignmentsChanged();
    });
    return saved;
  }

  Future<bool> markNoticeLocalRead(String noticeId, {bool read = true}) async {
    final account = _account;
    final epoch = _generation;
    var saved = false;
    await _run(() async {
      if (account == null ||
          !_authenticated ||
          _generation != epoch ||
          account != _account) {
        return;
      }
      final next = _courseNotices.markLocalRead(noticeId, read: read);
      await repository.saveCourseNotices(next, account);
      if (_generation != epoch || !_authenticated || account != _account) {
        return;
      }
      _courseNotices = next;
      saved = true;
    });
    return saved;
  }

  Future<bool> markAllNoticesLocalRead({Iterable<String>? noticeIds}) async {
    final account = _account;
    final epoch = _generation;
    var saved = false;
    await _run(() async {
      if (account == null ||
          !_authenticated ||
          _generation != epoch ||
          account != _account) {
        return;
      }
      final next =
          _courseNotices.markAllLocalRead(noticeIds: noticeIds?.toSet());
      await repository.saveCourseNotices(next, account);
      if (_generation != epoch || !_authenticated || account != _account) {
        return;
      }
      _courseNotices = next;
      saved = true;
    });
    return saved;
  }

  Future<bool> syncCourseChapters({String? courseKey}) async {
    final account = _account;
    final epoch = _generation;
    if (account == null || !_authenticated) return false;
    var succeeded = false;
    await _run(() async {
      if (_generation != epoch ||
          !_authenticated ||
          account != _account ||
          _disposed) {
        return;
      }
      _syncCancelled = false;
      _isChapterSyncing = true;
      _chapterSyncProgressText = '正在准备读取章节进度…';
      notifyListeners();
      try {
        final targets = <ChaoxingCourseRef>[];
        final clientByKey = {
          for (final c in chaoxingClient.courses)
            '${c.courseId}:${c.clazzId}': c,
        };
        if (courseKey != null) {
          final match = clientByKey[courseKey] ??
              _courses
                  .where((c) => c.key == courseKey)
                  .map((c) => ChaoxingCourseRef(
                      courseId: c.courseId,
                      clazzId: c.clazzId,
                      courseName: c.name))
                  .firstOrNull;
          if (match != null) targets.add(match);
        } else {
          final followed =
              _courses.where((c) => follows(c.key)).toList(growable: false);
          for (final c in followed) {
            targets.add(clientByKey[c.key] ??
                ChaoxingCourseRef(
                    courseId: c.courseId,
                    clazzId: c.clazzId,
                    courseName: c.name));
          }
        }
        if (targets.isEmpty) {
          _error = courseKey != null ? '未找到目标课程，请先同步课程列表' : '当前没有已关注的课程';
          return;
        }
        if (chaoxingClient.needsSessionInitialization) {
          await _refreshChaoxingSession();
        }
        var updatedCount = 0;
        String? firstIssue;
        for (var i = 0; i < targets.length; i++) {
          if (_syncCancelled ||
              _generation != epoch ||
              !_authenticated ||
              account != _account ||
              _disposed) {
            break;
          }
          final target = targets[i];
          _chapterSyncProgressText =
              '正在读取 ${target.courseName}（${i + 1}/${targets.length}）';
          notifyListeners();
          try {
            CourseChapterSnapshot snapshot;
            try {
              snapshot = await chaoxingClient.fetchCourseChapters(target);
            } on ChaoxingAuthenticationException {
              if (_syncCancelled ||
                  _generation != epoch ||
                  !_authenticated ||
                  _disposed) {
                break;
              }
              await _refreshChaoxingSession();
              if (_syncCancelled ||
                  _generation != epoch ||
                  !_authenticated ||
                  _disposed) {
                break;
              }
              snapshot = await chaoxingClient.fetchCourseChapters(target);
            }
            if (_syncCancelled ||
                _generation != epoch ||
                account != _account ||
                _disposed) {
              break;
            }
            final merged = _courseChapters.upsertCourse(snapshot);
            await repository.saveCourseChapters(merged, account);
            if (_generation != epoch || _disposed) break;
            _courseChapters = merged;
            updatedCount++;
            notifyListeners();
          } on SyncReadException catch (e) {
            if (e.issue.kind == SyncIssueKind.cancelled) {
              _error = '已取消读取章节进度';
              break;
            }
            firstIssue ??= e.issue.message;
          } catch (e) {
            firstIssue ??= '${target.courseName} 章节进度读取失败：$e';
          }
        }
        succeeded = updatedCount > 0 && firstIssue == null && !_syncCancelled;
        if (_syncCancelled) {
          _error = updatedCount > 0
              ? '已取消读取，已保存前 $updatedCount 门课的章节进度'
              : '已取消读取章节进度';
        } else if (firstIssue != null) {
          _error = updatedCount > 0
              ? '已更新 $updatedCount 门课章节进度；$firstIssue'
              : firstIssue;
        }
      } finally {
        _isChapterSyncing = false;
        _chapterSyncProgressText = null;
      }
    });
    return succeeded;
  }

  Future<ManualEntry?> createReminderFromNotice(
    CourseNotice notice, {
    required DateTime remindAt,
    int expectedEpoch = -1,
  }) async {
    final epoch = expectedEpoch >= 0 ? expectedEpoch : _generation;
    final account = _account;
    ManualEntry? created;
    await _run(() async {
      if (account == null ||
          !_authenticated ||
          _generation != epoch ||
          account != _account) {
        return;
      }
      final existing = notice.linkedManualEntryId == null
          ? null
          : notebook.entries
              .where((e) => e.id == notice.linkedManualEntryId)
              .firstOrNull;
      if (existing != null) {
        created = existing;
        return;
      }
      if (notebook.entries.length >= 500) {
        _error = '个人待办已达 500 条上限，请清理后再添加到日程';
        return;
      }
      final baseId = 'notice-${notice.id.substring(10, 24)}';
      var candidateId = baseId;
      var suffix = 1;
      while (notebook.entries.any((e) => e.id == candidateId)) {
        candidateId = '$baseId-${suffix++}';
      }
      final rawTitle = '[课程通知] ${notice.title}';
      final entryTitle =
          rawTitle.length > 200 ? rawTitle.substring(0, 200) : rawTitle;
      final entryCourse = notice.courseName == '通知中心' ? '' : notice.courseName;
      final entryNote = notice.summary.length > 500
          ? notice.summary.substring(0, 500)
          : notice.summary;
      final entry = ManualEntry(
        id: candidateId,
        title: entryTitle,
        kind: 'todo',
        course: entryCourse.length > 200
            ? entryCourse.substring(0, 200)
            : entryCourse,
        note: entryNote,
        at: remindAt.toUtc(),
        remind: true,
      );
      final nextNotebook = notebook.withEntries([...notebook.entries, entry]);
      await repository.saveNotebook(nextNotebook, account);
      if (_generation != epoch || !_authenticated) return;
      final previous = notebook;
      notebook = StudyNotebook.decode(nextNotebook.encode());
      final manualSucceeded = await _afterAssignmentsChanged();
      await _recordManualCancellationOutcomes(
        previous,
        notebook,
        rescheduleSucceeded: manualSucceeded,
      );
      final nextNotices = _courseNotices.bindManualEntry(notice.id, entry.id);
      await repository.saveCourseNotices(nextNotices, account);
      if (_generation == epoch && _authenticated) {
        _courseNotices = nextNotices;
      }
      created = entry;
    });
    return created;
  }

  Future<ManualEntry?> createTodoFromChapterNode(
    CourseChapterSnapshot snapshot,
    ChapterNode node, {
    DateTime? remindAt,
    int minutes = 30,
    int expectedEpoch = -1,
  }) async {
    final epoch = expectedEpoch >= 0 ? expectedEpoch : _generation;
    final account = _account;
    ManualEntry? created;
    await _run(() async {
      if (account == null ||
          !_authenticated ||
          _generation != epoch ||
          account != _account) {
        return;
      }
      final existing = node.linkedManualEntryId == null
          ? null
          : notebook.entries
              .where((e) => e.id == node.linkedManualEntryId)
              .firstOrNull;
      if (existing != null) {
        created = existing;
        return;
      }
      if (notebook.entries.length >= 500) {
        _error = '个人待办已达 500 条上限，请清理后再添加';
        return;
      }
      final digest = sha256
          .convert(utf8.encode(node.sectionId))
          .toString()
          .substring(0, 14);
      var candidateId = 'chap-$digest';
      var suffix = 1;
      while (notebook.entries.any((e) => e.id == candidateId)) {
        candidateId = 'chap-$digest-${suffix++}';
      }
      final rawTitle = '[章节任务点] ${node.code} ${node.title}';
      final entryTitle =
          rawTitle.length > 200 ? rawTitle.substring(0, 200) : rawTitle;
      final entryNote = node.state == ChapterTaskState.pendingPoints
          ? '待完成任务点：${node.pendingPoints} 个'
          : '';
      final entry = ManualEntry(
        id: candidateId,
        title: entryTitle,
        kind: 'todo',
        course: snapshot.courseName.length > 200
            ? snapshot.courseName.substring(0, 200)
            : snapshot.courseName,
        note: entryNote,
        at: remindAt?.toUtc(),
        remind: remindAt != null,
        minutes: minutes.clamp(0, 1440),
      );
      final nextNotebook = notebook.withEntries([...notebook.entries, entry]);
      await repository.saveNotebook(nextNotebook, account);
      if (_generation != epoch || !_authenticated) return;
      final previous = notebook;
      notebook = StudyNotebook.decode(nextNotebook.encode());
      final manualSucceeded = await _afterAssignmentsChanged();
      await _recordManualCancellationOutcomes(
        previous,
        notebook,
        rescheduleSucceeded: manualSucceeded,
      );
      final nextCatalog = _courseChapters.bindManualEntry(
        snapshot.courseKey,
        node.sectionId,
        entry.id,
      );
      await repository.saveCourseChapters(nextCatalog, account);
      if (_generation == epoch && _authenticated) {
        _courseChapters = nextCatalog;
      }
      created = entry;
    });
    return created;
  }

  List<AssignmentChange> changes = [];
  String? returnCheckMessage;
  String? _visitedAssignment;
  int? _visitGeneration;
  bool _visitLeftApp = false;

  void beginAssignmentVisit(String id) {
    if (!_authenticated || findAssignment(id) == null) return;
    _visitedAssignment = id;
    _visitGeneration = _generation;
    _visitLeftApp = false;
    returnCheckMessage = null;
  }

  void cancelAssignmentVisit(String id) {
    if (_visitedAssignment == id) {
      _visitedAssignment = null;
      _visitLeftApp = false;
    }
  }

  void markAssignmentVisitLeftApp() {
    if (_visitedAssignment != null) _visitLeftApp = true;
  }

  void dismissReturnCheck() {
    returnCheckMessage = null;
    notifyListeners();
  }

  Future<void> checkReturnedAssignment() async {
    final id = _visitedAssignment, generation = _visitGeneration;
    if (id == null || !_visitLeftApp) return;
    _visitedAssignment = null;
    _visitLeftApp = false;
    if (generation != _generation || !_authenticated || _disposed) return;
    final target = findAssignment(id);
    if (target == null ||
        (!target.isExam &&
            (target.courseId == null || target.clazzId == null))) {
      return;
    }
    returnCheckMessage = target.isExam ? '正在核对刚才考试的作答状态…' : '正在核对刚才作业的提交状态…';
    notifyListeners();
    var confirmed = false;
    await _run(() async {
      if (generation != _generation || !_authenticated || _disposed) return;
      if (chaoxingClient.needsSessionInitialization) {
        await _refreshChaoxingSession();
      }
      chaoxingClient.previousAssignments = {
        for (final a in [..._assignments, ..._hiddenAssignments]) a.id: a
      };
      late List<Assignment> incoming;
      try {
        incoming = target.courseId == null
            ? await chaoxingClient.fetchAssignments()
            : await chaoxingClient.fetchAssignmentsForCourse(
                courseId: target.courseId!, clazzId: target.clazzId!);
      } on ChaoxingAuthenticationException {
        await _refreshChaoxingSession();
        incoming = target.courseId == null
            ? await chaoxingClient.fetchAssignments()
            : await chaoxingClient.fetchAssignmentsForCourse(
                courseId: target.courseId!, clazzId: target.clazzId!);
      }
      if (generation != _generation || !_authenticated || _disposed) return;
      final observed = incoming
          .where((a) =>
              a.id == id ||
              (target.courseTaskKey != null &&
                  a.courseTaskKey == target.courseTaskKey))
          .firstOrNull;
      final before = [..._assignments, ..._hiddenAssignments];
      final accepted = incoming
          .where((a) =>
              a.isExam ||
              a.isSupportedClassroomTask ||
              a.id != id ||
              a.statusLabel != '提交状态未知')
          .toList();
      await _markReminderMutationPending();
      await repository.mergeAndSave(accepted,
          completeSync: false,
          canCommit: () async =>
              generation == _generation && _authenticated && !_disposed);
      if (generation != _generation || !_authenticated || _disposed) return;
      await _reloadJournal();
      if (generation != _generation || !_authenticated || _disposed) return;
      await _recordChanges(before, accepted);
      if (generation != _generation || !_authenticated || _disposed) return;
      if (repository.identityConflictCount > 0) {
        returnCheckMessage = '已读取最新状态，部分旧记录存在重复关联，已暂停其提醒；请查看本地记录。';
        confirmed = true;
        return;
      }
      final latestBefore =
          before.where((a) => a.id == id).firstOrNull ?? target;
      final conflictsWithConfirmation = latestBefore.isCompleted &&
          !latestBefore.isExam &&
          !latestBefore.isSupportedClassroomTask &&
          observed != null &&
          !observed.isCompleted &&
          observed.status != 'returned';
      returnCheckMessage = observed == null ||
              observed.status == 'unknown' ||
              observed.statusLabel == '提交状态未知' ||
              conflictsWithConfirmation
          ? (observed?.isSupportedClassroomTask == true
              ? '本次未能确认提交状态，已更新为待确认；确认前暂停提醒。'
              : '本次未能确认提交状态，已保留原记录；请稍后刷新核对。')
          : observed.isCompleted
              ? '已确认提交：${observed.title}（${observed.statusLabel}）'
              : '刚才的作业仍为${observed.statusLabel}，提醒继续保留。';
      confirmed = true;
    });
    if (generation != _generation || !_authenticated || _disposed) return;
    if (!confirmed) returnCheckMessage = '本次未能确认提交状态，已保留原记录和提醒；请稍后重试。';
    notifyListeners();
  }

  Future<void> _recordChanges(
      List<Assignment> before, List<Assignment> incoming,
      {bool completeSync = false}) async {
    final generation = _generation;
    try {
      final after = [..._assignments, ..._hiddenAssignments];
      final observedIds = incoming.expand<String>((a) {
        final ids = after
            .where((saved) =>
                saved.id == a.id ||
                (a.courseTaskKey != null &&
                    saved.courseTaskKey == a.courseTaskKey))
            .map((saved) => saved.id)
            .toSet();
        return ids.isEmpty ? [a.id] : ids;
      }).toSet();
      await changeLog.record(before, after, observedIds,
          completeSync: completeSync);
      if (generation != _generation || _disposed) return;
      final loaded = await changeLog.load();
      if (generation != _generation || _disposed) return;
      changes = loaded;
    } catch (_) {
      _recoveryWarnings.add('部分作业变化记录未能保存或读取，请稍后重试');
    }
  }

  SyncReport syncReport = const SyncReport();
  int _generation = 0;
  bool _disposed = false, _loginRunning = false;
  String get syncSummary =>
      _serviceWarnings.isNotEmpty && syncReport.phase == SyncPhase.success
          ? '作业已更新，提醒或小组件需要处理'
          : syncReport.summary;
  bool _authenticated = false;
  bool _loading = false;
  bool _agreementAccepted = false;
  String? _error;
  String? _account;
  String? _chaoxingDisplayName;
  String? _chaoxingAvatarUrl;
  DateTime? _lastSyncAt;
  List<int> _reminderOffsetsMinutes = ReminderRuleStore.defaultOffsetsMinutes;
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
  final List<String> _serviceWarnings = [];
  final List<String> _recoveryWarnings = [];
  List<String> get serviceWarnings => List.unmodifiable(_serviceWarnings);
  String? get recoveryWarning => repository.recoveryWarning;
  String? get operationError => _error;
  String? get error {
    final messages = [
      _error,
      repository.recoveryWarning,
      ..._serviceWarnings,
      ..._recoveryWarnings
    ].whereType<String>().where((s) => s.isNotEmpty).toSet();
    return messages.isEmpty ? null : messages.join('；');
  }

  String saveFeedback(
    bool saved, {
    required String successMessage,
    required String failureMessage,
  }) {
    final warnings = {
      if (repository.recoveryWarning != null) repository.recoveryWarning!,
      ..._serviceWarnings,
    };
    return [
      saved ? successMessage : failureMessage,
      ...warnings,
    ].join('；');
  }

  List<Assignment> _hiddenAssignments = [];
  List<Assignment> get hiddenAssignments =>
      List.unmodifiable(_hiddenAssignments);
  DateTime? _lastSyncAttemptAt;
  String? get account => _account;
  String? get accountHash => _accountHash;
  int get nativeSessionEpoch => _nativeSessionEpoch;
  String? get profileAvatarUrl => _chaoxingAvatarUrl;

  String get profileDisplayName {
    final name = _chaoxingDisplayName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    final account = _account?.trim();
    if (account != null && account.isNotEmpty) {
      return account;
    }
    return '同学';
  }

  DateTime? get lastSyncAt =>
      _lastSyncAt ??
      (syncReport.phase == SyncPhase.success
          ? syncReport.lastFullSuccessAt
          : null);
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
  String? get backgroundWarning => _backgroundWarning;
  DateTime? get nextBackgroundCheckAt {
    if (!_authenticated || !_backgroundCheckSettings.enabled) return null;
    return _nextBackgroundTarget(DateTime.now());
  }

  Future<BackgroundReminderHealth?> inspectBackgroundReminderHealth() async {
    final accountHash = _accountHash;
    if (!_nativeReminderAvailable || !_authenticated || accountHash == null) {
      return null;
    }
    // Once the bridge is expected, a failed read is not "zero reminders"; let
    // the caller surface the failure instead of fabricating a healthy state.
    return backgroundReminderGateway.inspectHealth(
      accountHash: accountHash,
      sessionEpoch: _nativeSessionEpoch,
    );
  }

  List<int> get reminderOffsetsMinutes =>
      List.unmodifiable(_reminderOffsetsMinutes);
  List<Assignment> get assignments => List.unmodifiable(_assignments);
  final Set<String> _unfollowed = {};
  List<CourseRef> _courses = [];
  List<CourseRef> get courses => List.unmodifiable(_courses);
  bool follows(String key) => !_unfollowed.contains(key);
  List<Assignment> get formalAssignments =>
      courseAssignments.where((a) => a.isFormal).toList();
  List<CourseworkGroup>? _courseworkGroupsCache;
  List<CourseworkGroup>? _localRecordGroupsCache;
  List<Assignment>? _courseworkSourcesCache;
  List<Assignment>? _statsAssignmentsCache;

  List<CourseworkGroup> get localRecordGroups =>
      _localRecordGroupsCache ??= List.unmodifiable(AssignmentGrouping.group(
        [..._assignments, ..._hiddenAssignments],
        hiddenIds:
            _hiddenAssignments.map((assignment) => assignment.id).toSet(),
      ));

  List<CourseworkGroup> get courseworkGroups =>
      _courseworkGroupsCache ??= List.unmodifiable(AssignmentGrouping.group(
        AssignmentQuery.scope([..._assignments, ..._hiddenAssignments], {})
            .where((assignment) =>
                assignment.courseKey == null || follows(assignment.courseKey!))
            .toList(),
        hiddenIds:
            _hiddenAssignments.map((assignment) => assignment.id).toSet(),
      ));

  List<Assignment> get courseAssignments =>
      _courseworkSourcesCache ??= List.unmodifiable([
        for (final group in courseworkGroups)
          if (!group.hidden) ...group.sources,
      ]);

  /// Original primary records for statistics. Notice supplementation is a
  /// display-only projection and must never resolve submission state.
  List<Assignment> get statsAssignments =>
      _statsAssignmentsCache ??= List.unmodifiable([
        for (final group in courseworkGroups)
          if (!group.hidden) group.primary,
      ]);

  List<CourseworkGroup> get hiddenCourseworkGroups => List.unmodifiable(
        localRecordGroups.where((group) => group.hidden),
      );

  List<CourseworkGroup> get localCourseTaskGroups => List.unmodifiable(
        localRecordGroups.where(
          (group) => !group.hidden && group.primary.hasCourseTaskIdentity,
        ),
      );

  CourseworkGroup? courseworkGroupFor(String assignmentId) => localRecordGroups
      .where((group) =>
          group.sources.any((assignment) => assignment.id == assignmentId))
      .firstOrNull;
  bool _privacyCleanupPending = false;
  final Set<String> _pendingNativeCleanupAccounts = <String>{};
  bool get notificationPrivacyPending => _privacyCleanupPending;
  bool get notificationDetails => notificationService.showDetails;
  Future<void> saveNotificationDetails(bool value) => _run(() async {
        await _markReminderMutationPending();
        final prefs = await SharedPreferences.getInstance();
        if (value) {
          await prefs.remove(_privacyVerifiedHiddenKey);
        } else {
          try {
            await _cancelPrivateNotifications();
          } catch (_) {
            throw StateError('旧提醒未能清理，通知详情尚未关闭，请在提醒体检重试');
          }
        }
        if (!await prefs.setBool('notification_details_v1', value)) {
          throw StateError('通知隐私设置未能保存');
        }
        if (!value) {
          await _writeBoolPreferenceAndVerify(
              prefs, _privacyVerifiedHiddenKey, true);
        }
        notificationService.showDetails = value;
        _privacyCleanupPending = false;
        await _reconcileBackgroundControls();
        await _afterAssignmentsChanged();
        if (_serviceWarnings.isNotEmpty) {
          throw StateError('隐私设置已保存，部分旧提醒未更新，请在提醒体检重试');
        }
      });
  DisplayPreferences display = const DisplayPreferences();
  Future<void> saveDisplay(DisplayPreferences next) => _run(() async {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setString('display_preferences_v1', next.encode())) {
          throw StateError('显示设置未能保存，请重试');
        }
        display = next;
        try {
          await widgetSnapshotService.saveAssignmentsForContext(
            display.forWidget(
                _authenticated ? courseAssignments : <Assignment>[],
                DateTime.now()),
            authenticated: _authenticated,
            range: next.widgetRange,
          );
        } catch (_) {
          throw StateError('显示设置已保存，小组件更新失败，请稍后刷新');
        }
      });
  List<Assignment> get visibleAssignments =>
      AssignmentQuery.currentDisplay(courseAssignments, DateTime.now());
  AssignmentSyncProgress? _homeSyncProgress;
  List<Assignment> _homePreviewAssignments = [];
  Set<String> _homePendingDeadlineIds = {};
  AssignmentSyncProgress? _queuedHomeProgress;
  Timer? _homeProgressTimer;
  bool _hadCacheBeforeLastSync = false;

  bool get hadCacheBeforeLastSync => _hadCacheBeforeLastSync;

  AssignmentSyncProgress? get homeSyncProgress => _homeSyncProgress;

  List<Assignment> get homeDisplayAssignments {
    return AssignmentQuery.currentDisplay(
        homeCatalogAssignments, DateTime.now(),
        index: homeDisplayIndex);
  }

  /// Complete scoped source catalog for the home list, including submitted
  /// homework and ended exams. It retains notice sources for display-time
  /// ordering and stays consistent while a sync preview is published;
  /// current-todo callers continue to use [homeDisplayAssignments].
  List<Assignment> get homeCatalogAssignments {
    if (_homeCatalogCache != null) return _homeCatalogCache!;
    if (_homePreviewAssignments.isEmpty) {
      final next = List<Assignment>.unmodifiable(
          AssignmentQuery.scope(courseAssignments, {}));
      _homeCatalogCache = next;
      return next;
    }
    final merged = LocalAssignmentRepository.mergeAssignments(
      [..._assignments, ..._hiddenAssignments],
      _homePreviewAssignments,
      hiddenCompletedIds:
          _hiddenAssignments.map((assignment) => assignment.id).toSet(),
      includeCompleted: true,
    );
    final hiddenIds =
        _hiddenAssignments.map((assignment) => assignment.id).toSet();
    final next = List<Assignment>.unmodifiable([
      for (final group in AssignmentGrouping.group(
        _catalogAssignmentsFrom(merged),
        hiddenIds: hiddenIds,
      ))
        if (!group.hidden) ...group.sources,
    ]);
    _homeCatalogCache = next;
    return next;
  }

  List<Assignment>? _homeCatalogCache;
  AssignmentDisplayIndex? _homeDisplayIndex;

  AssignmentDisplayIndex get homeDisplayIndex =>
      _homeDisplayIndex ??= AssignmentDisplayIndex.from(homeCatalogAssignments);

  void _invalidateHomeDisplayIndex() {
    _homeCatalogCache = null;
    _homeDisplayIndex = null;
    _courseworkGroupsCache = null;
    _localRecordGroupsCache = null;
    _courseworkSourcesCache = null;
    _statsAssignmentsCache = null;
  }

  bool isHomeDeadlinePending(String assignmentId) =>
      _homePendingDeadlineIds.contains(assignmentId);

  bool isHomeAssignmentPreviewOnly(String assignmentId) =>
      _homePreviewAssignments.any((a) => a.id == assignmentId) &&
      !_assignments.any((a) => a.id == assignmentId);

  List<Assignment> _catalogAssignmentsFrom(Iterable<Assignment> records) =>
      AssignmentQuery.scope(records.toList(), {})
          .where((assignment) =>
              assignment.courseKey == null || follows(assignment.courseKey!))
          .toList();

  void _handleHomeProgress(int generation, AssignmentSyncProgress progress) {
    if (generation != _generation || !_authenticated || _disposed) return;
    _queuedHomeProgress = progress;
    final firstBatch =
        _homePreviewAssignments.isEmpty && progress.assignments.isNotEmpty;
    final finalDetails = progress.stage == AssignmentSyncStage.details &&
        progress.pendingDetailIds.isEmpty &&
        progress.resolvedCount >= progress.attemptedCount;
    final firstState = _homeSyncProgress == null;
    final stageChanged = _homeSyncProgress?.stage != progress.stage;
    if (firstBatch || finalDetails || firstState || stageChanged) {
      _publishHomeProgress(progress);
      return;
    }
    _homeProgressTimer ??= Timer(const Duration(milliseconds: 100), () {
      _homeProgressTimer = null;
      final latest = _queuedHomeProgress;
      if (latest != null) _publishHomeProgress(latest);
    });
  }

  void _publishHomeProgress(AssignmentSyncProgress progress) {
    if (_disposed || !_authenticated) return;
    _homeProgressTimer?.cancel();
    _homeProgressTimer = null;
    _queuedHomeProgress = null;
    _homeSyncProgress = progress;
    _homePreviewAssignments = List.of(progress.assignments);
    _homePendingDeadlineIds = Set.of(progress.pendingDetailIds);
    _invalidateHomeDisplayIndex();
    notifyListeners();
  }

  void _markHomePreviewSaving() {
    // A retraction may still be waiting in the 100ms merge queue. Saving must
    // publish the newest snapshot, otherwise the failed course's temporary
    // rows reappear until the whole sync clears the preview.
    final progress = _queuedHomeProgress ?? _homeSyncProgress;
    if (progress == null) return;
    _publishHomeProgress(AssignmentSyncProgress(
      stage: AssignmentSyncStage.saving,
      assignments: progress.assignments,
      pendingDetailIds: const {},
      resolvedCount: progress.resolvedCount,
      attemptedCount: progress.attemptedCount,
      unconfirmedCount: progress.unconfirmedCount,
      workListFailureCount: progress.workListFailureCount,
    ));
  }

  void _clearHomePreview({bool notify = false}) {
    final hadPreview =
        _homePreviewAssignments.isNotEmpty || _homeSyncProgress != null;
    _homeProgressTimer?.cancel();
    _homeProgressTimer = null;
    _queuedHomeProgress = null;
    _homeSyncProgress = null;
    _homePreviewAssignments = [];
    _homePendingDeadlineIds = {};
    _invalidateHomeDisplayIndex();
    if (notify && hadPreview && !_disposed) notifyListeners();
  }

  Future<void> followCourse(String key, bool followed) => _run(() async {
        await _markReminderMutationPending();
        final prefs = await SharedPreferences.getInstance();
        final next = {..._unfollowed};
        if (followed) {
          next.remove(key);
        } else {
          next.add(key);
        }
        if (!await prefs.setStringList('unfollowed_courses', next.toList())) {
          throw StateError('课程关注设置未能保存，请重试');
        }
        _unfollowed
          ..clear()
          ..addAll(next);
        _invalidateHomeDisplayIndex();
        await _afterAssignmentsChanged();
      });

  Map<String, dynamic>? get syncStatus => {
        'localOnly': true,
        'lastSyncedAt': _lastSyncAt?.toIso8601String(),
        'stale': _lastSyncAt == null ||
            DateTime.now().difference(_lastSyncAt!).inHours >= 24,
      };

  Assignment? findAssignment(String assignmentId) {
    for (final assignment in _assignments) {
      if (assignment.id == assignmentId) {
        return assignment;
      }
    }
    return null;
  }

  /// Resolves either visible or hidden assignments on the current account,
  /// allowing read-only detail inspection and restore without exposing hidden
  /// records to [findAssignment] notification or visit callers.
  Assignment? findAnyAssignment(String assignmentId) {
    final visible = findAssignment(assignmentId);
    if (visible != null) return visible;
    for (final assignment in _hiddenAssignments) {
      if (assignment.id == assignmentId) {
        return assignment;
      }
    }
    return null;
  }

  Future<void> restoreSession() async {
    _recoveryWarnings.clear();
    _nativeReminderAvailable = nativeReminderDeliveryEnabled &&
        await backgroundReminderGateway.isAvailable();
    repository.crossEngineLockEnabled = _nativeReminderAvailable;
    try {
      _account = await sessionStore.readChaoxingAccount();
      _authenticated = _account?.trim().isNotEmpty == true;
      _accountHash = _authenticated ? AccountIdentity.hash(_account!) : null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final notificationClickMessage =
          prefs.getString(_notificationClickMissingKey);
      if (notificationClickMessage != null) {
        _error = notificationClickMessage;
        await prefs.remove(_notificationClickMissingKey);
      }
    } catch (error) {
      _recoveryWarnings.add('本机数据恢复未完成：登录信息暂时无法读取，请重新登录');
    }
    try {
      if (_authenticated) {
        if (_nativeReminderAvailable) {
          _nativeSessionEpoch =
              await backgroundReminderGateway.ensureActiveAccount(
            _accountHash!,
          );
          await _prepareReminderHistorySession();
        }
        await repository.activateAccount(_account!, previousAccount: _account);
      }
      await _restoreAccountData();
    } catch (error) {
      _authenticated = false;
      _assignments.clear();
      _hiddenAssignments = [];
      _recoveryWarnings.add('账号本机记录暂时无法恢复，请重新登录后重试');
    }
    try {
      _chaoxingDisplayName = await sessionStore.readChaoxingDisplayName();
      _chaoxingAvatarUrl = await sessionStore.readChaoxingAvatarUrl();
      _needsProfileRecovery = _authenticated &&
          (_chaoxingDisplayName == null || _chaoxingAvatarUrl == null);
    } catch (_) {
      _recoveryWarnings.add('个人资料暂时无法恢复，不影响重新登录和读取作业');
    }
    await _reconcileBackgroundControls();
    await _maybeMigrateLegacyAssignmentSchedules();
    notifyListeners();
  }

  Future<void> _restoreAccountData() async {
    _clearHomePreview();
    homeFilters = const HomeFilters();
    notebook = StudyNotebook();
    personal = PersonalWorkspace();
    _courseNotices = CourseNoticeCollection();
    _courseChapters = CourseChapterCatalog();
    _isChapterSyncing = false;
    _chapterSyncProgressText = null;
    changes = [];
    _assignments.clear();
    _hiddenAssignments = [];
    _courses = [];
    _unfollowed.clear();
    _reminderOffsetsMinutes = ReminderRuleStore.defaultOffsetsMinutes;
    _lastSyncAt = null;
    _lastSyncAttemptAt = null;
    _serverBackoffUntil = null;
    syncReport = const SyncReport();
    Future<void> stage(String name, Future<void> Function() action) async {
      try {
        await action();
      } catch (_) {
        _recoveryWarnings.add('$name恢复未完成，请重新同步或保存设置');
      }
    }

    await stage('通知隐私', () async {
      final prefs = await SharedPreferences.getInstance();
      final details = prefs.getBool('notification_details_v1') ?? false;
      final cleanupPending = prefs.getBool(_privacyCleanupPendingKey) ?? false;
      final verifiedHidden = prefs.getBool(_privacyVerifiedHiddenKey) ?? false;
      _pendingNativeCleanupAccounts
        ..clear()
        ..addAll(prefs.getStringList(_nativeCleanupAccountsKey) ?? const []);
      notificationService.showDetails = details;
      _privacyCleanupPending =
          (_manageBackgroundSchedule && !details && !verifiedHidden) ||
              cleanupPending ||
              _pendingNativeCleanupAccounts.isNotEmpty;
      if (_privacyCleanupPending) {
        try {
          await _cancelPrivateNotifications();
        } catch (error) {
          _recoveryWarnings.add(_privacyCleanupMessage(error));
        }
      }
    });
    await stage('显示设置', () async {
      final prefs = await SharedPreferences.getInstance();
      display =
          DisplayPreferences.decode(prefs.getString('display_preferences_v1'));
    });
    await stage('首页筛选', () async {
      if (_authenticated) homeFilters = await repository.loadHomeFilters();
    });
    await stage('提醒设置', () async {
      _reminderOffsetsMinutes = await reminderRuleStore.loadOffsetsMinutes();
    });
    await stage('自动同步设置', () async {
      _backgroundCheckSettings =
          await backgroundCheckSettingsStore.loadAndMigrate();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      _serverBackoffUntil =
          DateTime.tryParse(prefs.getString(_serverBackoffKey) ?? '')
              ?.toLocal();
    });
    await stage('同步记录', () async {
      final prefs = await SharedPreferences.getInstance();
      _lastSyncAttemptAt =
          DateTime.tryParse(prefs.getString('sync_attempt_at') ?? '')
              ?.toLocal();
      final dataAt = DateTime.tryParse(prefs.getString('sync_data_at') ?? '');
      final report = prefs.getString('sync_report_v1');
      Map<String, dynamic>? reportJson;
      var reportDamaged = false;
      if (report != null) {
        try {
          final decoded = jsonDecode(report);
          if (decoded is Map<String, dynamic>) {
            reportJson = decoded;
          } else {
            reportDamaged = true;
          }
        } catch (_) {
          reportDamaged = true;
        }
      }
      if (reportJson != null) {
        try {
          SyncReport.fromJson(reportJson);
        } catch (_) {
          reportJson = null;
          reportDamaged = true;
        }
      }
      if (reportDamaged) {
        _recoveryWarnings.add('同步记录恢复未完成：原同步报告损坏，已依据可验证的本机时间重建部分状态');
      }
      var reportNeedsRepair = reportDamaged;
      if (reportJson != null) {
        final rawPhase = reportJson['phase'];
        syncReport = SyncReport.fromJson(reportJson);
        final reportAttempt = syncReport.attemptedAt;
        if (reportAttempt != null &&
            (_lastSyncAttemptAt == null ||
                reportAttempt.isAfter(_lastSyncAttemptAt!))) {
          // The v1 report is the canonical attempt timestamp. The legacy
          // mirror may be missing if its SharedPreferences write failed.
          _lastSyncAttemptAt = reportAttempt;
        }
        if (dataAt != null &&
            (syncReport.lastDataSuccessAt == null ||
                dataAt.isAfter(syncReport.lastDataSuccessAt!))) {
          // sync_data_at is written only after mergeAndSave has completed.
          // If it is newer than the report, the report is stale even when its
          // old phase says success/failed; do not present that attempt as a
          // fully successful sync whose final status was never persisted.
          final interruptedAfterDataSave = rawPhase == 'running' ||
              syncReport.attemptedAt == null ||
              dataAt.isAfter(syncReport.attemptedAt!);
          syncReport = syncReport.copyWith(
            phase: interruptedAfterDataSave ? SyncPhase.partial : null,
            lastDataSuccessAt: dataAt.toLocal(),
            issues: interruptedAfterDataSave
                ? [
                    ...syncReport.issues,
                    const SyncIssue(SyncIssueKind.storage,
                        '上次同步已写入作业数据，但在保存最终同步报告前中断；请重新同步核对',
                        stage: 'persistence')
                  ]
                : null,
          );
          // Persist the mirror reconciliation even when the existing phase
          // remains failed (for example, a newer failed attempt after older
          // durable data). The timestamps are still independently useful.
          reportNeedsRepair = true;
        }
      } else {
        DateTime? durableFullAt;
        try {
          durableFullAt = await repository.lastSyncAt();
        } catch (error) {
          // The independent data timestamp is still useful if the journal
          // cannot currently be read. Do not let a damaged repository hide
          // evidence that a partial sync had already saved records.
          _recoveryWarnings.add('完整同步时间暂时无法从作业仓库读取：$error');
        }
        final recoveredDataAt = dataAt?.toLocal();
        final lastDataAt = recoveredDataAt == null ||
                (durableFullAt != null &&
                    durableFullAt.isAfter(recoveredDataAt))
            ? durableFullAt
            : recoveredDataAt;
        final hasDurableData = lastDataAt != null;
        final hasAttempt = _lastSyncAttemptAt != null;
        syncReport = SyncReport(
            // sync_data_at advances after any data merge, including partial
            // course reads. Repository.lastSyncAt advances only after a full
            // sync, so never promote the mirror to a full-success timestamp.
            phase: hasDurableData
                ? SyncPhase.partial
                : hasAttempt || reportDamaged
                    ? SyncPhase.failed
                    : SyncPhase.idle,
            attemptedAt: _lastSyncAttemptAt,
            lastDataSuccessAt: lastDataAt,
            lastFullSuccessAt: durableFullAt,
            issues: !hasDurableData && !hasAttempt && !reportDamaged
                ? const []
                : [
                    SyncIssue(
                        SyncIssueKind.storage,
                        reportDamaged
                            ? '上次同步结果记录损坏；已依据本机数据时间恢复可确认部分，请重新同步核对'
                            : hasDurableData
                                ? '上次同步结果记录缺失；已依据本机数据时间恢复可确认部分，请重新同步核对'
                                : '上次同步尝试记录存在，但结果报告缺失且没有可确认的数据写入，请重新同步',
                        stage: 'persistence')
                  ]);
        reportNeedsRepair = reportNeedsRepair || hasDurableData || hasAttempt;
      }
      if (reportNeedsRepair) {
        await _persistSyncReport();
      }
    });
    await stage('课程关注', () async {
      final prefs = await SharedPreferences.getInstance();
      _unfollowed.addAll(prefs.getStringList('unfollowed_courses') ?? []);
    });
    await stage('课程资料', () async {
      _courses = await repository.loadCourses(account: _account);
    });
    await stage('个人计划与记录', () async {
      personal = await repository.loadPersonalWorkspace();
    });
    await stage('个人待办与学期归档', () async {
      notebook = await repository.loadNotebook();
    });
    await stage('课程通知', () async {
      _courseNotices = await repository.loadCourseNotices();
    });
    await stage('章节进度', () async {
      _courseChapters = await repository.loadCourseChapters();
    });
    await stage('作业记录', () async {
      await _reloadJournal();
      _hadCacheBeforeLastSync =
          _assignments.isNotEmpty || _hiddenAssignments.isNotEmpty;
    });
    await stage('作业变化', () async {
      changes = await changeLog.load();
    });
  }

  Future<void> loginChaoxing({
    required String account,
    required String password,
    required bool agreementAccepted,
  }) async {
    if (_loginRunning) return;
    if (!agreementAccepted) {
      _error = '请先阅读并同意服务协议和隐私协议';
      notifyListeners();
      return;
    }
    _loginRunning = true;
    final generation = ++_generation;
    _clearHomePreview(notify: true);
    _visitedAssignment = null;
    returnCheckMessage = null;
    var loginSucceeded = false;
    chaoxingClient.deferProfile = true;
    await _run(() async {
      final result = await chaoxingClient.login(
        account: account,
        password: password,
      );
      if (generation != _generation) return;
      if (!result.success) {
        chaoxingClient.clearSession();
        throw StateError(result.message ?? '登录失败');
      }
      final normalizedAccount = account.trim();
      final oldAccount = _account;
      final oldAccountHash = _accountHash;
      final oldNativeEpoch = _nativeSessionEpoch;
      final newAccountHash = AccountIdentity.hash(normalizedAccount);
      final sameAccount =
          oldAccountHash != null && oldAccountHash == newAccountHash;
      var nativeSwitched = false;
      if (_nativeReminderAvailable) {
        try {
          final nativeEpoch = sameAccount
              ? await backgroundReminderGateway
                  .rotateSessionEpoch(newAccountHash)
              : await backgroundReminderGateway.switchAccount(
                  previousAccountHash: oldAccountHash ??
                      (oldAccount == null
                          ? null
                          : AccountIdentity.hash(oldAccount)),
                  accountHash: newAccountHash,
                );
          if (nativeEpoch <= 0) {
            throw StateError('原生会话代次无效');
          }
          _nativeSessionEpoch = nativeEpoch;
          _accountHash = newAccountHash;
          nativeSwitched = true;
        } catch (error) {
          // The server accepted the login, but native reminder state did not
          // follow. Do not commit the new local identity with split ownership.
          chaoxingClient.clearSession();
          throw StateError('原生提醒账号切换失败，登录未完成：$error');
        }
      }
      String? oldPassword;
      if (oldAccount != null) {
        try {
          oldPassword = await sessionStore.readChaoxingPassword();
        } catch (_) {
          /* A damaged old credential must not block reauthentication. */
        }
      }
      final oldName = _chaoxingDisplayName, oldAvatar = _chaoxingAvatarUrl;
      try {
        if (oldAccount?.trim() != normalizedAccount) {
          // Full privacy cleanup also removes delivered notifications that
          // are no longer pending and have no v2 active-ID manifest.
          await _cancelPrivateNotifications();
          await widgetSnapshotService.saveAssignmentsForContext(
            const [],
            authenticated: false,
            range: display.widgetRange,
          );
        }
        await repository.activateAccount(normalizedAccount,
            previousAccount: oldAccount);
        await sessionStore.saveChaoxingAccount(
          account: normalizedAccount,
          password: password,
          displayName: result.displayName,
          avatarUrl: result.avatarUrl,
        );
      } catch (_) {
        // The server has already authenticated the new account. A local
        // rollback must also invalidate those cookies before any old-account sync.
        chaoxingClient.clearSession();
        try {
          if (_nativeReminderAvailable && nativeSwitched) {
            if (oldAccount != null && oldAccountHash != null) {
              if (!sameAccount) {
                _nativeSessionEpoch =
                    await backgroundReminderGateway.switchAccount(
                  previousAccountHash: newAccountHash,
                  accountHash: oldAccountHash,
                );
              }
              _accountHash = oldAccountHash;
            } else {
              await backgroundReminderGateway
                  .clearActiveAccount(newAccountHash);
              _accountHash = null;
              _nativeSessionEpoch = 0;
            }
          }
          if (oldAccount != null) {
            await repository.activateAccount(oldAccount);
          }
          if (oldAccount != null && oldPassword != null) {
            await sessionStore.saveChaoxingAccount(
                account: oldAccount,
                password: oldPassword,
                displayName: oldName,
                avatarUrl: oldAvatar);
          } else {
            await sessionStore.clear();
          }
          if (_nativeReminderAvailable &&
              nativeSwitched &&
              _authenticated &&
              _accountHash != null &&
              _nativeSessionEpoch > 0) {
            await _prepareReminderHistorySession();
          } else if (_nativeReminderAvailable && nativeSwitched) {
            _reminderHistoryReady = false;
            _reminderHistoryGeneration = 0;
          }
        } catch (_) {
          _authenticated = false;
          _account = null;
          _reminderHistoryReady = false;
          _reminderHistoryGeneration = 0;
          _assignments.clear();
          _hiddenAssignments = [];
          _courses = [];
          _unfollowed.clear();
          _courseNotices = CourseNoticeCollection();
          _courseChapters = CourseChapterCatalog();
          _invalidateHomeDisplayIndex();
          try {
            await sessionStore.clear();
          } catch (_) {/* Already failed closed. */}
          await _afterAssignmentsChanged();
        }
        rethrow;
      }
      if (generation != _generation || _disposed) return;
      if (oldAccount?.trim() != normalizedAccount) {
        await sessionStore.clearWebSession();
        chaoxingClient.previousAssignments = {};
        chaoxingClient.trackedActivityIds = {};
      }
      _recoveryWarnings.clear();
      _account = normalizedAccount;
      _accountHash = newAccountHash;
      _authenticated = true;
      String? historyRetireWarning;
      if (_nativeReminderAvailable) {
        if (oldAccountHash != null && !sameAccount && oldNativeEpoch > 0) {
          historyRetireWarning = await _retireReminderHistoryBeforeLogout(
            oldAccountHash,
            oldNativeEpoch,
          );
        }
        await _prepareReminderHistorySession();
      }
      await _restoreAccountData();
      if (historyRetireWarning != null) {
        _recoveryWarnings.add(historyRetireWarning);
      }
      _chaoxingDisplayName = result.displayName;
      _chaoxingAvatarUrl = result.avatarUrl;
      _agreementAccepted = true;
      _authenticated = true;
      loginSucceeded = true;
      await _reconcileBackgroundControls();
    });
    _loginRunning = false;
    if (loginSucceeded && _authenticated && generation == _generation) {
      unawaited(syncAssignmentsForTrigger(
        BackgroundSyncTrigger.manual,
        skipTaskEngineProbe: true,
      ));
      unawaited(_hydrateProfile(generation));
    }
  }

  Future<void> _hydrateProfile(int generation) async {
    if (!chaoxingClient.canHydrateProfile) return;
    try {
      final profile = await chaoxingClient.loadProfile();
      if (generation != _generation || _disposed || !_authenticated) return;
      final pending = (_operations ?? Future<void>.value()).then((_) async {
        if (generation != _generation || _disposed || !_authenticated) return;
        final password = await sessionStore.readChaoxingPassword();
        if (password == null || generation != _generation) return;
        final name = profile.displayName ?? _chaoxingDisplayName;
        final avatar = profile.avatarUrl ?? _chaoxingAvatarUrl;
        await sessionStore.saveChaoxingAccount(
            account: _account!,
            password: password,
            displayName: name,
            avatarUrl: avatar);
        _chaoxingDisplayName = name;
        _chaoxingAvatarUrl = avatar;
        if (!_disposed) notifyListeners();
      });
      _operations =
          pending.then<void>((_) {}, onError: (Object _, StackTrace __) {});
      await pending;
    } catch (_) {
      /* Optional profile loading must not prevent homework access. */
    }
  }

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
  void cancelSynchronization() {
    _syncCancelled = true;
    _syncOperation++;
    chaoxingClient.cancelActiveRequests();
    _clearHomePreview(notify: true);
  }

  void _ensureSyncActive(int operation) {
    if (_disposed || _syncCancelled || operation != _syncOperation) {
      throw const SyncCancelledException();
    }
  }

  Future<void> syncAssignments() =>
      syncAssignmentsForTrigger(BackgroundSyncTrigger.manual);

  Future<void> syncAssignmentsForTrigger(
    BackgroundSyncTrigger trigger, {
    bool skipTaskEngineProbe = false,
  }) async {
    await _syncForTrigger(trigger, skipTaskEngineProbe: skipTaskEngineProbe);
  }

  Future<String?> _syncForTrigger(
    BackgroundSyncTrigger trigger, {
    bool skipTaskEngineProbe = false,
  }) {
    if (!_authenticated) return Future.value();
    return _syncInFlight ??= _performCoordinatedSync(
      trigger,
      skipTaskEngineProbe: skipTaskEngineProbe,
    ).whenComplete(() {
      _syncInFlight = null;
    });
  }

  Future<String?> _performCoordinatedSync(
    BackgroundSyncTrigger trigger, {
    bool skipTaskEngineProbe = false,
  }) async {
    final operation = ++_syncOperation;
    final generation = _generation;
    _syncCancelled = false;
    _syncSkipReason = null;
    _syncSkipReasonOperation = null;
    _syncSkipReasonGeneration = null;
    final accountHash = _accountHash;
    final sessionEpoch = _nativeSessionEpoch;
    String? leaseRequest;
    DateTime? leaseRequestedAt;
    SyncLeaseResult? lease;
    if (_nativeReminderAvailable && accountHash != null) {
      leaseRequestedAt = DateTime.now();
      // The Worker's owner is stable for write leases and engine cleanup, but
      // every sync acquisition needs its own request id: native terminal ids
      // are tombstones and must never be reused by a later acquisition.
      final prefix = nativeLeaseOwner ??
          accountHash.substring(0, min(8, accountHash.length));
      leaseRequest = '$prefix-${leaseRequestedAt.microsecondsSinceEpoch}-'
          '${Random().nextInt(1 << 31)}';
      lease = await backgroundReminderGateway.acquireSyncLease(
        accountHash: accountHash,
        requestId: leaseRequest,
        requestedAt: leaseRequestedAt,
      );
      if (!lease.acquired) {
        _backgroundWarning = '另一轮作业检查仍在进行，本次已合并等待';
        notifyListeners();
        return null;
      }
    }
    try {
      if (lease != null &&
          lease.waited &&
          leaseRequestedAt != null &&
          (lease.lastAttemptAt?.isAfter(leaseRequestedAt) ?? false)) {
        if (lease.lastFullSuccessAt?.isAfter(leaseRequestedAt) ?? false) {
          await _run(_reloadJournal);
          return null;
        }
        _error = '另一轮作业检查未成功，本次合并到现有节奏，不立即重试';
        notifyListeners();
        return null;
      }
      if (trigger != BackgroundSyncTrigger.manual &&
          !DaytimeCheckPolicy.isInWindow(_clock())) {
        return BackgroundCheckResult.outsideWindowSkipReason;
      }
      await _run(() async {
        if (!_authenticated) return;
        if (_nativeReminderAvailable &&
            accountHash != null &&
            !await backgroundReminderGateway.isSessionCurrent(
              accountHash,
              sessionEpoch,
            )) {
          return;
        }
        await _syncAssignmentsBody(
          trigger,
          operation: operation,
          skipTaskEngineProbe: skipTaskEngineProbe,
        );
      });
      if (_syncSkipReasonOperation == operation &&
          _syncSkipReasonGeneration == generation) {
        return _syncSkipReason;
      }
      return null;
    } finally {
      if (_nativeReminderAvailable &&
          accountHash != null &&
          leaseRequest != null &&
          lease != null &&
          lease.acquired) {
        try {
          await backgroundReminderGateway.releaseSyncLease(
            accountHash: accountHash,
            requestId: leaseRequest,
          );
        } catch (error) {
          // Keep the sync result intact; an unconfirmed release is visible and
          // the native engine-destroy path remains the safety net.
          _backgroundWarning = '同步租约释放未确认：$error';
          _serviceWarnings.add(_backgroundWarning!);
        }
      }
    }
  }

  Future<void> importAssignmentsFromHtml(String html) async {
    await _run(() async {
      final incoming = ChaoxingAssignmentParser.parseWorkHtml(
        html,
        fallbackCourseName: '学习通课程',
        sourcePrefix: 'manual',
        baseUri: Uri.parse('https://mooc1.chaoxing.com'),
      );
      await _markReminderMutationPending();
      await repository.mergeAndSave(incoming, completeSync: false);
      await _reloadJournal();
    });
  }

  Future<void> _reloadJournal({
    bool completeSync = false,
    bool detectNewAssignments = false,
    bool syncCompleted = false,
    String? syncFailure,
    DateTime? completedAt,
  }) async {
    final generation = _generation;
    final journal = await repository.loadJournal();
    if (generation != _generation || _disposed) return;
    _assignments
      ..clear()
      ..addAll(journal);
    _hiddenAssignments = await repository.loadHiddenAssignments();
    if (generation != _generation || _disposed) return;
    _invalidateHomeDisplayIndex();
    final durableSyncAt = await repository.lastSyncAt();
    if (generation != _generation || _disposed) return;
    _lastSyncAt = durableSyncAt;
    var reportReconciled = false;
    if (durableSyncAt != null) {
      final fullTimestampMissingOrStale =
          syncReport.lastFullSuccessAt == null ||
              durableSyncAt.isAfter(syncReport.lastFullSuccessAt!);
      final dataTimestampMissingOrStale =
          syncReport.lastDataSuccessAt == null ||
              durableSyncAt.isAfter(syncReport.lastDataSuccessAt!);
      final interruptedAfterFullSave = fullTimestampMissingOrStale &&
          (syncReport.attemptedAt == null ||
              durableSyncAt.isAfter(syncReport.attemptedAt!));
      final reportMissingForDurableData = syncReport.phase == SyncPhase.idle;
      if (fullTimestampMissingOrStale ||
          dataTimestampMissingOrStale ||
          interruptedAfterFullSave ||
          reportMissingForDurableData) {
        syncReport = syncReport.copyWith(
          phase: interruptedAfterFullSave || reportMissingForDurableData
              ? SyncPhase.partial
              : null,
          lastDataSuccessAt: dataTimestampMissingOrStale ? durableSyncAt : null,
          lastFullSuccessAt: fullTimestampMissingOrStale ? durableSyncAt : null,
          issues: interruptedAfterFullSave
              ? [
                  ...syncReport.issues,
                  const SyncIssue(SyncIssueKind.storage,
                      '本机作业数据已完成保存，但最终同步报告中断；已从数据仓库恢复时间记录',
                      stage: 'persistence')
                ]
              : reportMissingForDurableData
                  ? [
                      ...syncReport.issues,
                      const SyncIssue(SyncIssueKind.storage,
                          '本机作业数据存在，但同步结果报告缺失或损坏；已从数据仓库恢复时间记录',
                          stage: 'persistence')
                    ]
                  : null,
        );
        reportReconciled = true;
      }
    }
    if (reportReconciled) {
      try {
        await _persistSyncReport();
      } catch (error) {
        _recoveryWarnings.add('已从作业仓库恢复同步时间，但同步报告未能重新保存：$error');
      }
    }
    if (generation != _generation || _disposed) return;
    await _afterAssignmentsChanged(
      completeSync: completeSync,
      detectNewAssignments: detectNewAssignments,
      syncCompleted: syncCompleted,
      syncFailure: syncFailure,
      completedAt: completedAt,
    );
  }

  Future<void> refreshAssignments() => _run(_reloadJournal);

  Future<bool> restoreLocalBackup(BackupSnapshot snapshot) async {
    final account = _account, generation = _generation;
    if (account == null || !_authenticated) return false;
    var restored = false;
    await _run(() async {
      if (generation != _generation || account != _account || !_authenticated) {
        return;
      }
      await _markReminderMutationPending();
      restored = await repository.restoreBackupSnapshot(snapshot, account);
      if (generation != _generation || account != _account || !_authenticated) {
        restored = false;
        return;
      }
      if (restored) {
        _visitedAssignment = null;
        returnCheckMessage = null;
        await _restoreAccountData();
      }
    });
    return restored;
  }

  Future<void> updateCompletion(String assignmentId, bool completed) async {
    await setAssignmentsHidden([assignmentId], completed);
  }

  Future<bool> hideAssignment(String assignmentId) async {
    return setAssignmentsHidden([assignmentId], true);
  }

  Future<bool> setAssignmentsHidden(
    Iterable<String> assignmentIds,
    bool hidden,
  ) async {
    final ids = assignmentIds.toSet();
    if (ids.isEmpty) return true;
    final epoch = accountEpoch;
    final accountHash = _accountHash;
    if (accountHash == null) return false;
    var saved = false;
    await _run(() async {
      await _markReminderMutationPending();
      await repository.updateCompletionMany(
        ids,
        hidden,
        canCommit: () async {
          if (accountEpoch != epoch) return false;
          if (!_nativeReminderAvailable) return true;
          return backgroundReminderGateway.isSessionCurrent(
            accountHash,
            _nativeSessionEpoch,
          );
        },
      );
      if (accountEpoch != epoch) {
        throw StateError('账号会话已变化，隐藏结果未应用到当前账号');
      }
      await _reloadJournal();
      saved = true;
    });
    return saved;
  }

  Future<bool> setCourseworkGroupHidden(
    CourseworkGroup group,
    bool hidden,
  ) =>
      setAssignmentsHidden(
        group.sources.map((assignment) => assignment.id),
        hidden,
      );

  Future<bool> saveReminderRule(List<int> offsetsMinutes) async {
    var saved = false;
    await _run(() async {
      await _markReminderMutationPending();
      final normalized = await reminderRuleStore.saveOffsetsMinutes(
        offsetsMinutes,
      );
      _reminderOffsetsMinutes = normalized;
      saved = true;
      await _afterAssignmentsChanged();
    });
    return saved;
  }

  Future<bool> saveAutoSyncIntervalMinutes(int minutes) async {
    if (minutes == 0) {
      return saveBackgroundCheckEnabled(false);
    }
    return saveBackgroundCheckIntervalMinutes(minutes);
  }

  Future<bool> saveBackgroundCheckEnabled(bool enabled) async {
    var saved = false;
    await _run(() async {
      final next = _backgroundCheckSettings.copyWith(enabled: enabled);
      await backgroundCheckSettingsStore.save(next);
      _backgroundCheckSettings = next;
      if (!await _reconcileBackgroundControls()) {
        throw StateError('设置已保存，但后台提醒设置未确认，请重试');
      }
      saved = true;
    });
    return saved;
  }

  Future<bool> saveBackgroundCheckIntervalMinutes(int minutes) async {
    var saved = false;
    await _run(() async {
      final normalized = DaytimeCheckPolicy.normalizeIntervalMinutes(minutes);
      final next = _backgroundCheckSettings.copyWith(
        enabled: true,
        intervalMinutes: normalized,
      );
      await backgroundCheckSettingsStore.save(next);
      _backgroundCheckSettings = next;
      if (!await _reconcileBackgroundControls()) {
        throw StateError('设置已保存，但后台提醒设置未确认，请重试');
      }
      saved = true;
    });
    return saved;
  }

  Future<bool> saveNotificationListenerEnabled(bool enabled) async {
    var saved = false;
    await _run(() async {
      final next = _backgroundCheckSettings.copyWith(
        notificationListenerEnabled: enabled,
      );
      await backgroundCheckSettingsStore.save(next);
      _backgroundCheckSettings = next;
      if (!await _reconcileBackgroundControls()) {
        throw StateError('设置已保存，但后台提醒设置未确认，请重试');
      }
      saved = true;
    });
    return saved;
  }

  Future<bool> saveNewAssignmentReminderEnabled(bool enabled) async {
    var saved = false;
    await _run(() async {
      final next = _backgroundCheckSettings.copyWith(
        newAssignmentReminderEnabled: enabled,
      );
      await backgroundCheckSettingsStore.save(next);
      _backgroundCheckSettings = next;
      if (!await _reconcileBackgroundControls()) {
        throw StateError('设置已保存，但后台提醒设置未确认，请重试');
      }
      saved = true;
    });
    return saved;
  }

  Future<bool> runDueAutoSync({DateTime? now}) async {
    if (!_authenticated ||
        !_backgroundCheckSettings.enabled ||
        _loading ||
        _autoSyncRunning) {
      return false;
    }
    final currentNow = now ?? DateTime.now();
    if (!DaytimeCheckPolicy.isDue(
          localNow: currentNow,
          lastAttemptAt: _latestAttemptAt,
          intervalMinutes: _backgroundCheckSettings.intervalMinutes,
        ) ||
        (_serverBackoffUntil?.isAfter(currentNow) ?? false)) {
      return false;
    }

    _lastSyncAttemptAt = currentNow;
    _autoSyncRunning = true;
    try {
      await syncAssignmentsForTrigger(BackgroundSyncTrigger.foregroundDue);
      await _reconcileBackgroundControls(now: currentNow);
      return _error == null;
    } finally {
      _autoSyncRunning = false;
    }
  }

  Future<BackgroundCheckResult> runBackgroundAutomaticCheck(
    BackgroundSyncTrigger trigger,
  ) async {
    final result = await _runBackgroundAutomaticCheck(trigger);
    await _recordBackgroundCheckObservation(trigger, result);
    return result;
  }

  Future<BackgroundCheckResult> _runBackgroundAutomaticCheck(
    BackgroundSyncTrigger trigger,
  ) async {
    _remoteReadInvoked = false;
    final now = _clock();
    if (!_authenticated) {
      return const BackgroundCheckResult(
        success: false,
        skipped: true,
        nextTargetAt: null,
        message: '未登录',
      );
    }
    if (trigger == BackgroundSyncTrigger.daytime &&
        !_backgroundCheckSettings.enabled) {
      return const BackgroundCheckResult(
        success: false,
        skipped: true,
        nextTargetAt: null,
        message: '白天后台检查已关闭',
      );
    }
    if (trigger == BackgroundSyncTrigger.notificationSignal &&
        !_backgroundCheckSettings.notificationListenerEnabled) {
      return BackgroundCheckResult(
        success: false,
        skipped: true,
        nextTargetAt: null,
        message: '通知监听已关闭',
      );
    }
    if (!DaytimeCheckPolicy.isInWindow(now)) {
      return BackgroundCheckResult(
        success: false,
        skipped: true,
        nextTargetAt: trigger == BackgroundSyncTrigger.notificationSignal
            ? _nextNotificationWindowTarget(now)
            : _nextBackgroundTarget(now),
        message: '当前不在白天检查窗口',
        skipReason: BackgroundCheckResult.outsideWindowSkipReason,
        remoteReadInvoked: _remoteReadInvoked,
      );
    }
    if (trigger == BackgroundSyncTrigger.daytime &&
        !DaytimeCheckPolicy.isDue(
          localNow: now,
          lastAttemptAt: _latestAttemptAt,
          intervalMinutes: _backgroundCheckSettings.intervalMinutes,
        )) {
      return BackgroundCheckResult(
        success: true,
        skipped: true,
        nextTargetAt: _nextBackgroundTarget(now),
        message: '合并到已有检查节奏',
      );
    }
    final syncSkipReason = await _syncForTrigger(trigger);
    if (syncSkipReason == BackgroundCheckResult.outsideWindowSkipReason) {
      return BackgroundCheckResult(
        success: false,
        skipped: true,
        nextTargetAt: trigger == BackgroundSyncTrigger.notificationSignal
            ? _nextNotificationWindowTarget(_clock())
            : _nextBackgroundTarget(_clock()),
        message: '当前不在白天检查窗口',
        skipReason: BackgroundCheckResult.outsideWindowSkipReason,
        remoteReadInvoked: _remoteReadInvoked,
      );
    }
    final success = _error == null ||
        syncReport.phase == SyncPhase.success ||
        syncReport.phase == SyncPhase.partial;
    return BackgroundCheckResult(
      success: success && !_loading,
      skipped: false,
      nextTargetAt: trigger == BackgroundSyncTrigger.notificationSignal
          ? _nextNotificationWindowTarget(_clock())
          : _nextBackgroundTarget(_clock()),
      message: _error,
      remoteReadInvoked: _remoteReadInvoked,
    );
  }

  Future<void> _recordBackgroundCheckObservation(
    BackgroundSyncTrigger trigger,
    BackgroundCheckResult result,
  ) async {
    if (!_nativeReminderAvailable || !_reminderHistoryReady) return;
    if (trigger == BackgroundSyncTrigger.daytime &&
        result.skipped &&
        result.success &&
        result.skipReason == null) {
      return;
    }
    final accountHash = _accountHash;
    final epoch = _nativeSessionEpoch;
    if (accountHash == null || epoch <= 0) return;
    final isOutsideWindow =
        result.skipReason == BackgroundCheckResult.outsideWindowSkipReason;
    final stage = isOutsideWindow
        ? 'deferred'
        : result.skipped
            ? 'blocked'
            : result.success
                ? 'scheduled'
                : 'unconfirmed';
    final reasonCode =
        result.skipReason ?? (result.success ? null : 'backgroundCheckFailed');
    final logicalKey = trigger == BackgroundSyncTrigger.notificationSignal
        ? 'background:notificationSignal:${backgroundSignalVersion ?? 0}'
        : 'background:${trigger.name}';
    final owner = notificationRemoteStart?.workerId ?? nativeLeaseOwner;
    final observationId = (owner != null && owner.isNotEmpty)
        ? 'bg:${trigger.name}:${backgroundSignalVersion ?? 0}:$owner:$stage:${reasonCode ?? ''}'
        : null;
    try {
      final context =
          await backgroundReminderGateway.acquireReminderObservationContext(
        accountHash: accountHash,
        sessionEpoch: epoch,
      );
      await backgroundReminderGateway.appendReminderObservation(
        context: context,
        observation: ReminderObservation(
          observationId: observationId,
          subjectKind: 'account',
          logicalKey: logicalKey,
          category: 'backgroundCheck',
          stage: stage,
          reasonCode: reasonCode,
          observedAt: _clock(),
          scheduledAt: result.nextTargetAt,
        ),
      );
    } on ReminderHistoryException catch (error) {
      _serviceWarnings.add('提醒记录未能写入：${error.message}');
    } catch (error) {
      _serviceWarnings.add('提醒记录未能写入：$error');
    }
  }

  Future<void> _prepareReminderHistorySession() async {
    if (!reminderHistoryEnabled) return;
    final accountHash = _accountHash;
    final epoch = _nativeSessionEpoch;
    if (!_nativeReminderAvailable ||
        !_authenticated ||
        accountHash == null ||
        epoch <= 0) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    try {
      final control = await backgroundReminderGateway.getReminderHistoryControl(
        accountHash: accountHash,
        sessionEpoch: epoch,
      );
      var generation = control.historyGeneration;
      if (control.purgePending) {
        final token = control.purgeToken;
        if (token == null) {
          _reminderHistoryReady = false;
          _serviceWarnings.add('提醒记录仍在清理，当前记录功能暂不可用');
          return;
        }
        final finished =
            await backgroundReminderGateway.finishReminderHistoryLogout(token);
        generation = finished.historyGeneration;
      }
      final pendingRequest = prefs.getString(_historyPurgeRequestKey);
      final pendingGeneration = prefs.getInt(_historyPurgeGenerationKey);
      if (pendingRequest != null && pendingRequest.isNotEmpty) {
        final expected = pendingGeneration == null || pendingGeneration <= 0
            ? generation
            : pendingGeneration;
        try {
          final started =
              await backgroundReminderGateway.beginReminderHistoryLogout(
            expectedHistoryGeneration: expected,
            requestId: pendingRequest,
            accountHash: accountHash,
            sessionEpoch: epoch,
          );
          final finished = await backgroundReminderGateway
              .finishReminderHistoryLogout(started.purgeToken);
          generation = finished.historyGeneration;
        } on ReminderHistoryException catch (error) {
          if (error.code != 'stale_history_generation') rethrow;
          generation =
              (await backgroundReminderGateway.getReminderHistoryControl(
            accountHash: accountHash,
            sessionEpoch: epoch,
          ))
                  .historyGeneration;
        }
        await prefs.remove(_historyPurgeRequestKey);
        await prefs.remove(_historyPurgeGenerationKey);
      }
      generation = await backgroundReminderGateway.enableReminderHistorySession(
        accountHash: accountHash,
        sessionEpoch: epoch,
        expectedHistoryGeneration: generation,
      );
      _reminderHistoryGeneration = generation;
      _reminderHistoryReady = true;
    } on ReminderHistoryException catch (error) {
      _reminderHistoryReady = false;
      _serviceWarnings.add('提醒记录暂不可用：${error.message}');
    } catch (error) {
      _reminderHistoryReady = false;
      _serviceWarnings.add('提醒记录暂不可用：$error');
    }
  }

  Future<String?> _retireReminderHistoryBeforeLogout(
    String accountHash,
    int sessionEpoch,
  ) async {
    if (!reminderHistoryEnabled) return null;
    if (!_nativeReminderAvailable) {
      await _persistHistoryPurgeIntent();
      return null;
    }
    final requestId =
        'logout-${DateTime.now().microsecondsSinceEpoch}-$_generation';
    final prefs = await SharedPreferences.getInstance();
    try {
      final control = await backgroundReminderGateway.getReminderHistoryControl(
        accountHash: accountHash,
        sessionEpoch: sessionEpoch,
      );
      var generation = control.historyGeneration;
      if (control.purgePending && control.purgeToken != null) {
        final finished = await backgroundReminderGateway
            .finishReminderHistoryLogout(control.purgeToken!);
        generation = finished.historyGeneration;
      } else if (control.purgePending) {
        await prefs.setString(_historyPurgeRequestKey, requestId);
        await prefs.setInt(_historyPurgeGenerationKey, generation);
        return null;
      }
      final started =
          await backgroundReminderGateway.beginReminderHistoryLogout(
        expectedHistoryGeneration: generation,
        requestId: requestId,
        accountHash: accountHash,
        sessionEpoch: sessionEpoch,
      );
      await backgroundReminderGateway
          .finishReminderHistoryLogout(started.purgeToken);
      _reminderHistoryReady = false;
      _reminderHistoryGeneration = 0;
      return null;
    } catch (error) {
      await _persistHistoryPurgeIntent(
        requestId: requestId,
        generation: _reminderHistoryGeneration,
      );
      _reminderHistoryReady = false;
      final warning = '退出时提醒记录清理未确认：$error';
      _serviceWarnings.add(warning);
      return warning;
    }
  }

  Future<void> _persistHistoryPurgeIntent({
    String? requestId,
    int? generation,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _historyPurgeRequestKey,
        requestId ??
            'logout-${DateTime.now().microsecondsSinceEpoch}-$_generation',
      );
      await prefs.setInt(
        _historyPurgeGenerationKey,
        generation ?? _reminderHistoryGeneration,
      );
    } catch (_) {
      // The logout path already reports the unconfirmed native cleanup.
    }
  }

  Future<void> logout() async {
    _generation++;
    cancelSynchronization();
    chaoxingClient.clearSession();
    _clearHomePreview(notify: true);
    _visitedAssignment = null;
    returnCheckMessage = null;
    changes = [];
    final accountHash = _accountHash;
    String? historyLogoutWarning;
    if (_nativeReminderAvailable && accountHash != null) {
      historyLogoutWarning = await _retireReminderHistoryBeforeLogout(
        accountHash,
        _nativeSessionEpoch,
      );
      try {
        await backgroundReminderGateway.clearActiveAccount(accountHash);
      } catch (error) {
        // Local identity removal must still complete. Keep the old account
        // hash so the native cleanup can be retried without account identity.
        _pendingNativeCleanupAccounts.add(accountHash);
        try {
          await _persistNativeCleanupAccounts();
        } catch (persistError) {
          _error = '退出后原生提醒清理未确认，且清理目标未能保存：$persistError';
        }
        _privacyCleanupPending = true;
      }
    }
    _accountHash = null;
    _nativeSessionEpoch = 0;
    await _run(() async {
      try {
        await _cancelPrivateNotifications();
      } catch (_) {
        // Logout must still remove the local identity. Keep cleanup pending so
        // a later refresh or app start can retry cancellable notifications.
        _privacyCleanupPending = true;
      }
      chaoxingClient.clearSession();
      chaoxingClient.previousAssignments = {};
      chaoxingClient.trackedActivityIds = {};
      await sessionStore.clear();
      await repository.clear();
      await reminderRuleStore.clear();
      _authenticated = false;
      _account = null;
      homeFilters = const HomeFilters();
      personal = PersonalWorkspace();
      notebook = StudyNotebook();
      _courseNotices = CourseNoticeCollection();
      _courseChapters = CourseChapterCatalog();
      _isChapterSyncing = false;
      _chapterSyncProgressText = null;
      _agreementAccepted = false;
      _needsProfileRecovery = false;
      _reminderOffsetsMinutes = ReminderRuleStore.defaultOffsetsMinutes;
      _chaoxingDisplayName = null;
      _chaoxingAvatarUrl = null;
      _error = null;
      _recoveryWarnings.clear();
      _assignments.clear();
      _lastSyncAt = null;
      _lastSyncAttemptAt = null;
      _serverBackoffUntil = null;
      _hiddenAssignments = [];
      _courses = [];
      _unfollowed.clear();
      _invalidateHomeDisplayIndex();
      syncReport = const SyncReport();
      _visitedAssignment = null;
      returnCheckMessage = null;
      changes = [];
      repository.recoveryWarning = null;
      await _reconcileBackgroundControls();
      await _afterAssignmentsChanged();
      if (historyLogoutWarning != null) {
        _serviceWarnings.add(historyLogoutWarning);
      }
      if (_serviceWarnings.isNotEmpty) {
        final hasOtherWarnings = _serviceWarnings.any(
          (warning) => warning != historyLogoutWarning,
        );
        _error = hasOtherWarnings
            ? (historyLogoutWarning == null
                ? '账号已退出，但部分提醒或桌面内容可能仍保留。请在系统中清除本应用通知并移除小组件。'
                : '账号已退出，但部分提醒或桌面内容可能仍保留（$historyLogoutWarning）。请在系统中清除本应用通知并移除小组件。')
            : historyLogoutWarning;
      }
    });
    if (_pendingNativeCleanupAccounts.isNotEmpty) {
      _error ??= '账号已退出，但旧账号的原生提醒清理尚未确认；应用会在下次启动或刷新时重试。';
      notifyListeners();
    }
  }

  @visibleForTesting
  void replaceAssignmentsForTest(List<Assignment> assignments) {
    _assignments
      ..clear()
      ..addAll(assignments);
    _invalidateHomeDisplayIndex();
  }

  Future<bool> _afterAssignmentsChanged({
    bool completeSync = false,
    bool detectNewAssignments = false,
    bool syncCompleted = false,
    String? syncFailure,
    DateTime? completedAt,
  }) async {
    var manualRescheduleSucceeded = false;
    _serviceWarnings.clear();
    // Restored app preferences can outlive excluded/nonportable credentials.
    // Do not publish their private content to lockscreen or widget before login.
    final scoped = _authenticated ? courseAssignments : <Assignment>[];
    if (_privacyCleanupPending) {
      try {
        await _cancelPrivateNotifications();
      } catch (error) {
        _serviceWarnings.add(_privacyCleanupMessage(error));
      }
    }
    if (!_privacyCleanupPending) {
      if (_nativeReminderAvailable && _authenticated) {
        final controlsApplied = await _reconcileBackgroundControls();
        if (!controlsApplied) {
          // Fail closed: publishing a plan while showDetails/schedule settings
          // were not applied would activate the previous native settings.
          _serviceWarnings.add(_backgroundWarning ?? '后台提醒设置未能应用，本次未更新提醒计划');
        } else {
          try {
            if (await _ensureLegacyAssignmentVerified()) {
              await _applyNativeReminderPlan(
                completeSync: completeSync,
                detectNewAssignments: detectNewAssignments,
                syncCompleted: syncCompleted,
                failure: syncFailure,
                completedAt: completedAt,
              );
            }
          } catch (error) {
            _serviceWarnings.add('后台作业提醒状态未能更新：$error');
          }
        }
      } else {
        try {
          await notificationService.rescheduleAssignments(scoped,
              offsetsMinutes: _reminderOffsetsMinutes);
        } catch (_) {
          _serviceWarnings.add('提醒安排失败，请检查通知权限后重试');
        }
        if (notificationService.lastWarning != null) {
          _serviceWarnings.add(notificationService.lastWarning!);
        }
      }
      if (_manageBackgroundSchedule) {
        try {
          await notificationService.rescheduleSummary(scoped,
              _authenticated ? personal : PersonalWorkspace(), _lastSyncAt);
          if (notificationService.lastWarning != null) {
            _serviceWarnings.add(notificationService.lastWarning!);
          }
        } catch (error) {
          final detail = notificationService.lastWarning ?? error.toString();
          _serviceWarnings.add(_authenticated && personal.summaryEnabled
              ? '每日摘要未能更新：$detail'
              : '旧摘要未能清理：$detail');
        }
        await _recordPluginScheduleOutcomes(
          notificationService.lastScheduleOutcomes,
        );
        try {
          await notificationService
              .rescheduleManual(_authenticated ? notebook.entries : []);
          manualRescheduleSucceeded = !notificationService.lastScheduleOutcomes
              .any((item) => item.stage == 'scheduleFailed');
          if (notificationService.lastWarning != null) {
            _serviceWarnings.add('个人日程：${notificationService.lastWarning!}');
          }
        } catch (error) {
          manualRescheduleSucceeded = false;
          final detail = notificationService.lastWarning ?? error.toString();
          _serviceWarnings.add('个人日程提醒未能更新或清理：$detail');
        }
        await _recordPluginScheduleOutcomes(
          notificationService.lastScheduleOutcomes,
        );
      }
    }
    final widgetItems = display.forWidget(scoped, DateTime.now());
    if (_manageBackgroundSchedule) {
      try {
        await widgetSnapshotService.saveAssignmentsForContext(
          widgetItems,
          authenticated: _authenticated,
          range: display.widgetRange,
        );
      } catch (_) {
        _serviceWarnings.add('作业已保存在本机，小组件更新失败，请稍后刷新');
      }
    } else if (_authenticated && !_privacyCleanupPending) {
      try {
        await widgetSnapshotService.saveAssignmentsForContext(
          widgetItems,
          authenticated: true,
          range: display.widgetRange,
        );
      } catch (error) {
        debugPrint('[WidgetSnapshot] background_refresh_skipped: $error');
      }
    }
    return manualRescheduleSucceeded;
  }

  Future<void> _markReminderMutationPending() async {
    final accountHash = _accountHash;
    if (!_nativeReminderAvailable || !_authenticated || accountHash == null) {
      return;
    }
    await backgroundReminderGateway.markPendingUpdate(
      accountHash: accountHash,
      sessionEpoch: _nativeSessionEpoch,
    );
  }

  Future<void> _recordPluginScheduleOutcomes(
    List<ReminderScheduleOutcome> outcomes,
  ) async {
    if (!_nativeReminderAvailable ||
        !_reminderHistoryReady ||
        outcomes.isEmpty) {
      return;
    }
    final accountHash = _accountHash;
    final epoch = _nativeSessionEpoch;
    if (accountHash == null || epoch <= 0) return;
    try {
      final context =
          await backgroundReminderGateway.acquireReminderObservationContext(
        accountHash: accountHash,
        sessionEpoch: epoch,
      );
      final result =
          await backgroundReminderGateway.recordReminderScheduleOutcome(
        context: context,
        outcomes: outcomes,
      );
      if (result.warning != null) {
        _serviceWarnings.add(result.warning!);
      }
    } on ReminderHistoryException catch (error) {
      _serviceWarnings.add('提醒记录未能写入：${error.message}');
    } catch (error) {
      _serviceWarnings.add('提醒记录未能写入：$error');
    }
  }

  Future<void> _recordManualCancellationOutcomes(
    StudyNotebook previous,
    StudyNotebook current, {
    required bool rescheduleSucceeded,
  }) async {
    if (!_nativeReminderAvailable ||
        !_reminderHistoryReady ||
        !_authenticated) {
      return;
    }
    final now = DateTime.now();
    final outcomes = <ReminderScheduleOutcome>[];
    for (final entry in previous.entries) {
      if (entry.done || !entry.remind || entry.at == null) continue;
      final next =
          current.entries.where((item) => item.id == entry.id).firstOrNull;
      final stillScheduled = next != null &&
          !next.done &&
          next.remind &&
          next.at != null &&
          next.at == entry.at &&
          next.at!.subtract(const Duration(minutes: 30)).isAfter(now);
      if (stillScheduled) continue;
      final at = entry.at!.subtract(const Duration(minutes: 30));
      if (!rescheduleSucceeded) {
        outcomes.add(ReminderScheduleOutcome(
          subjectKind: 'manual',
          subjectId: entry.id,
          logicalKey: 'manual:${entry.id}:${at.millisecondsSinceEpoch}',
          category: 'personal',
          stage: 'cancelFailed',
          reasonCode: 'scheduleBatchFailed',
          observedAt: now,
          scheduledAt: at,
          expectedPayload: 'p:${entry.id}',
          evidenceState: 'recoveryPending',
        ));
        continue;
      }
      final String reasonCode;
      if (next == null) {
        reasonCode = 'removed';
      } else if (next.done) {
        reasonCode = 'completed';
      } else if (!next.remind) {
        reasonCode = 'reminderDisabled';
      } else if (next.at == null) {
        reasonCode = 'noDeadline';
      } else if (!next.at!.subtract(const Duration(minutes: 30)).isAfter(now)) {
        reasonCode = 'offsetWindowPassed';
      } else {
        reasonCode = 'scheduleReplaced';
      }
      outcomes.add(ReminderScheduleOutcome(
        subjectKind: 'manual',
        subjectId: entry.id,
        logicalKey: 'manual:${entry.id}:${at.millisecondsSinceEpoch}',
        category: 'personal',
        stage: 'cancelled',
        reasonCode: reasonCode,
        observedAt: now,
        scheduledAt: at,
        expectedPayload: 'p:${entry.id}',
        evidenceState: 'removed',
      ));
    }
    await _recordPluginScheduleOutcomes(outcomes);
  }

  bool get reminderHistoryAvailable => _reminderHistoryReady;

  ReminderObservationContext _historyReadContext() {
    final accountHash = _accountHash;
    if (!_nativeReminderAvailable ||
        !_reminderHistoryReady ||
        accountHash == null ||
        _nativeSessionEpoch <= 0 ||
        _reminderHistoryGeneration <= 0) {
      throw const ReminderHistoryException(
        'history_unavailable',
        '提醒记录当前不可用',
      );
    }
    return ReminderObservationContext(
      accountHash: accountHash,
      sessionEpoch: _nativeSessionEpoch,
      historyGeneration: _reminderHistoryGeneration,
      operationSequence: 0,
    );
  }

  Future<ReminderHistoryPage> loadReminderHistory({
    int? snapshotMaxId,
    int? beforeId,
    String? category,
    List<ReminderSubjectRef> subjectRefs = const [],
  }) =>
      backgroundReminderGateway.listReminderHistory(
        context: _historyReadContext(),
        snapshotMaxId: snapshotMaxId,
        beforeId: beforeId,
        category: category,
        subjectRefs: subjectRefs,
      );

  Future<ReminderSubjectEvidence> inspectReminderSubjects(
    List<ReminderSubjectRef> refs,
  ) async {
    final context = _historyReadContext();
    if (refs.length <= 50) {
      return backgroundReminderGateway.inspectReminderSubjects(
        context: context,
        subjectRefs: refs,
      );
    }
    final nativeEvents = <ReminderNativeSubjectEvidence>[];
    final pluginEvidence = <ReminderPluginSubjectEvidence>[];
    final warnings = <String>[];
    var checkedAt = DateTime.now();
    var generation = context.historyGeneration;
    for (var start = 0; start < refs.length; start += 50) {
      final end = (start + 50).clamp(0, refs.length);
      final page = await backgroundReminderGateway.inspectReminderSubjects(
        context: context,
        subjectRefs: refs.sublist(start, end),
      );
      checkedAt = page.checkedAt;
      generation = page.historyGeneration;
      nativeEvents.addAll(page.nativeEvents);
      pluginEvidence.addAll(page.pluginEvidence);
      warnings.addAll(page.queryWarnings);
    }
    return ReminderSubjectEvidence(
      checkedAt: checkedAt,
      nativeEvents: nativeEvents,
      pluginEvidence: pluginEvidence,
      queryWarnings: warnings,
      historyGeneration: generation,
    );
  }

  Future<ReminderExplanation> explainReminder({
    required String kind,
    required String id,
  }) async {
    final now = DateTime.now();
    final warnings = <String>[];
    ReminderHealth? health;
    var healthQueryFailed = false;
    try {
      health = await notificationService.inspectHealth();
    } catch (error) {
      healthQueryFailed = true;
      warnings.add('系统通知状态暂时无法读取：$error');
    }
    PluginScheduleEvidenceSnapshot? plugin;
    var pluginQueryFailed = false;
    try {
      plugin = await notificationService.readScheduleEvidence();
    } catch (error) {
      pluginQueryFailed = true;
      warnings.add('系统待投递排期暂时无法读取：$error');
    }
    ReminderSubjectEvidence? evidence;
    var subjectQueryFailed = false;
    try {
      final refs = switch (kind) {
        'assignment' => [
            for (final source in courseworkGroupFor(id)?.sources ??
                [if (findAssignment(id) != null) findAssignment(id)!])
              ReminderSubjectRef('assignment', source.id),
          ],
        'manual' => [ReminderSubjectRef('manual', id)],
        'summary' => const [ReminderSubjectRef('summary', null)],
        _ => <ReminderSubjectRef>[],
      };
      if (refs.isNotEmpty) {
        evidence = await inspectReminderSubjects(refs);
      }
    } on ReminderHistoryException catch (error) {
      subjectQueryFailed = true;
      warnings.add(error.message);
    } catch (error) {
      subjectQueryFailed = true;
      warnings.add('提醒证据暂时无法读取：$error');
    }
    if (kind == 'assignment') {
      final group = courseworkGroupFor(id);
      final primary = group?.primary ?? findAssignment(id);
      if (primary == null) {
        return ReminderExplanation(
          checkedAt: now,
          subjectKind: kind,
          subjectId: id,
          displayName: '事项已不在当前账号的本机记录中',
          categories: const [
            ReminderCategoryExplanation(
              category: 'deadline',
              status: ReminderExplanationStatus.ineligible,
              reasonCodes: ['removed'],
              nextScheduledAt: null,
              evidenceAt: null,
              actionLabel: null,
            ),
          ],
          queryWarnings: warnings,
        );
      }
      ReminderPlanState? plan;
      if (_nativeReminderAvailable && _nativeSessionEpoch > 0) {
        try {
          plan = await backgroundReminderGateway.loadPlanState(
            accountHash: _accountHash!,
            sessionEpoch: _nativeSessionEpoch,
          );
        } catch (error) {
          subjectQueryFailed = true;
          warnings.add('提醒规则状态暂时无法读取：$error');
        }
      }
      return ReminderExplanationService.forAssignment(
        primary: primary,
        sources: group?.sources ?? [primary],
        groupHidden: group?.hidden ?? false,
        hiddenAssignmentIds: _hiddenAssignments.map((item) => item.id).toSet(),
        unfollowedCourseKeys: _unfollowed,
        plan: plan,
        offsets: _reminderOffsetsMinutes,
        newReminderEnabled:
            _backgroundCheckSettings.newAssignmentReminderEnabled,
        now: now,
        evidence: evidence,
        health: health,
        pluginEvidence: plugin,
        queryWarnings: warnings,
        healthQueryFailed: healthQueryFailed,
        pluginQueryFailed: pluginQueryFailed,
        subjectQueryFailed: subjectQueryFailed,
      );
    }
    if (kind == 'manual') {
      final entry = notebook.entries.where((item) => item.id == id).firstOrNull;
      return ReminderExplanationService.forManual(
        entry: entry,
        entryId: id,
        now: now,
        evidence: evidence,
        health: health,
        pluginEvidence: plugin,
        queryWarnings: warnings,
        healthQueryFailed: healthQueryFailed,
        pluginQueryFailed: pluginQueryFailed,
        subjectQueryFailed: subjectQueryFailed,
      );
    }
    if (kind == 'summary') {
      final summaryId = int.tryParse(id);
      final notices = DailySummary.build(
        courseAssignments,
        _authenticated ? personal : PersonalWorkspace(),
        now,
        _lastSyncAt,
      );
      return ReminderExplanationService.forSummary(
        personal: _authenticated ? personal : PersonalWorkspace(),
        summaryId: summaryId,
        now: now,
        evidence: evidence,
        health: health,
        pluginEvidence: plugin,
        queryWarnings: warnings,
        notices: notices,
        healthQueryFailed: healthQueryFailed,
        pluginQueryFailed: pluginQueryFailed,
        subjectQueryFailed: subjectQueryFailed,
      );
    }
    throw const ReminderHistoryException(
      'invalid_history_argument',
      '未知提醒事项类型',
    );
  }

  Future<void> retryReminderRecovery() async {
    await notificationService.recoverPendingSchedules();
    await _afterAssignmentsChanged();
  }

  Future<void> _maybeMigrateLegacyAssignmentSchedules() async {
    await _ensureLegacyAssignmentVerified();
  }

  /// The native migration revision is the only activation fact. The Flutter
  /// boolean is mirrored for diagnostics/tests but never authorizes delivery.
  Future<bool> _ensureLegacyAssignmentVerified() async {
    if (!_nativeReminderAvailable) return true;
    try {
      if (await notificationService.isLegacyAssignmentMigrationComplete()) {
        await _mirrorLegacyCleanupMarker();
        return true;
      }
      await notificationService.removeLegacyAssignmentSchedules();
      if (!await notificationService.isLegacyAssignmentMigrationComplete()) {
        _serviceWarnings.add('旧作业提醒迁移未完成，已暂缓原生提醒计划');
        return false;
      }
      await _mirrorLegacyCleanupMarker();
      return true;
    } catch (error) {
      _serviceWarnings.add('旧作业提醒迁移尚未完成：$error');
      return false;
    }
  }

  Future<void> _mirrorLegacyCleanupMarker() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_legacyScheduleCleanupKey) == true) return;
    if (!await _writeBoolPreferenceAndVerify(
        prefs, _legacyScheduleCleanupKey, true)) {
      _serviceWarnings.add('旧作业提醒已清理，但本机完成标记未能保存；不影响原生迁移状态');
    }
  }

  Future<void> _applyNativeReminderPlan({
    required bool completeSync,
    required bool detectNewAssignments,
    required bool syncCompleted,
    String? failure,
    DateTime? completedAt,
  }) async {
    final accountHash = _accountHash;
    if (!_authenticated || accountHash == null) return;
    final sessionEpoch = _nativeSessionEpoch;
    final state = await backgroundReminderGateway.loadPlanState(
      accountHash: accountHash,
      sessionEpoch: sessionEpoch,
    );
    final now = completedAt ?? DateTime.now();
    final plan = AssignmentReminderPlanner.planAfterSync(
      accountHash: accountHash,
      sessionEpoch: sessionEpoch,
      assignments: [..._assignments, ..._hiddenAssignments],
      hiddenAssignmentIds: _hiddenAssignments.map((item) => item.id).toSet(),
      unfollowedCourseKeys: _unfollowed,
      knownAssignmentIds: state.knownAssignmentIds,
      sentNewAssignmentIds: state.sentNewAssignmentIds,
      baselineCompleted: state.baselineCompleted,
      baselinedSources: state.baselinedSources,
      completedSourceKeys: syncCompleted
          ? {
              for (final source in chaoxingClient.sourceResults)
                if (source.phase == SyncSourcePhase.success) source.source,
            }
          : const {},
      completeSync: completeSync,
      detectNewAssignments: detectNewAssignments,
      newAssignmentReminderEnabled:
          _backgroundCheckSettings.newAssignmentReminderEnabled,
      reminderOffsetsMinutes: _reminderOffsetsMinutes,
      now: now,
    );
    final result = await backgroundReminderGateway.applyPlan(
      accountHash: accountHash,
      sessionEpoch: sessionEpoch,
      plan: plan,
      completedAt: now,
      failure: failure,
      syncCompleted: syncCompleted,
      expectedMutationVersion: state.mutationVersion,
    );
    _backgroundWarning = result.warning;
    if (result.warning != null) {
      _serviceWarnings.add(result.warning!);
    }
  }

  bool _needsProfileRecovery = false;

  Future<void> _syncAssignmentsBody(BackgroundSyncTrigger trigger,
      {required int operation, bool skipTaskEngineProbe = false}) async {
    final generation = _generation;
    final startedAt = _autoSyncRunning && _lastSyncAttemptAt != null
        ? _lastSyncAttemptAt!
        : _clock();
    final automatic = trigger != BackgroundSyncTrigger.manual;
    if (automatic && !DaytimeCheckPolicy.isInWindow(startedAt)) {
      _syncSkipReason = BackgroundCheckResult.outsideWindowSkipReason;
      _syncSkipReasonOperation = operation;
      _syncSkipReasonGeneration = generation;
      await _reconcileBackgroundControls(now: startedAt);
      return;
    }
    if (automatic && (_serverBackoffUntil?.isAfter(startedAt) ?? false)) {
      await _reconcileBackgroundControls(now: startedAt);
      return;
    }
    if (trigger == BackgroundSyncTrigger.notificationSignal &&
        notificationRemoteStart != null) {
      final authorization =
          await backgroundReminderGateway.authorizeNotificationRemoteStart(
        notificationRemoteStart!,
      );
      if (authorization == NotificationRemoteAuthorization.outsideWindow) {
        _syncSkipReason = BackgroundCheckResult.outsideWindowSkipReason;
        _syncSkipReasonOperation = operation;
        _syncSkipReasonGeneration = generation;
        await _reconcileBackgroundControls(now: startedAt);
        return;
      }
      if (authorization != NotificationRemoteAuthorization.granted) {
        _error = '提醒任务的会话已变化，已跳过本次后台读取';
        return;
      }
      if (!DaytimeCheckPolicy.isInWindow(_clock())) {
        _syncSkipReason = BackgroundCheckResult.outsideWindowSkipReason;
        _syncSkipReasonOperation = operation;
        _syncSkipReasonGeneration = generation;
        await _reconcileBackgroundControls(now: _clock());
        return;
      }
      _remoteReadInvoked = true;
    }
    final attempted = startedAt;
    _hadCacheBeforeLastSync =
        _assignments.isNotEmpty || _hiddenAssignments.isNotEmpty;
    _lastSyncAttemptAt = attempted;
    syncReport = SyncReport(
        phase: SyncPhase.running,
        attemptedAt: attempted,
        lastDataSuccessAt: syncReport.lastDataSuccessAt,
        lastFullSuccessAt: _lastSyncAt);
    await _persistSyncReport();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final attemptMirrorSaved = await _writePreferenceAndVerify(
        prefs, 'sync_attempt_at', attempted.toUtc().toIso8601String());
    if (chaoxingClient.needsSessionInitialization) {
      await _refreshChaoxingSession();
      _needsProfileRecovery = false;
    }
    final previous = [..._assignments, ..._hiddenAssignments];
    chaoxingClient.previousAssignments = {for (final a in previous) a.id: a};
    chaoxingClient.trackedActivityIds = _assignments
        .followedBy(_hiddenAssignments)
        .where((a) => a.id.startsWith('cx:activity:'))
        .map((a) => a.id)
        .toSet();
    List<Assignment> incoming;
    final stopCheck =
        automatic ? () => !DaytimeCheckPolicy.isInWindow(_clock()) : null;
    chaoxingClient.shouldStop = stopCheck;
    final manualSync = trigger == BackgroundSyncTrigger.manual;
    final showPreview = manualSync;
    void attachProgress() {
      chaoxingClient.onProgress = showPreview
          ? (progress) => _handleHomeProgress(generation, progress)
          : null;
    }

    attachProgress();
    var savingStageMarked = false;
    // Persistence begins with the course cache; mark that stage before the
    // first write can suspend, not only before the journal merge.
    void markSavingStage() {
      if (savingStageMarked) return;
      savingStageMarked = true;
      _markHomePreviewSaving();
    }

    try {
      incoming = await chaoxingClient.fetchAssignmentsWithOptions(
        collectCourseNotices: manualSync,
        enableTaskEngineProbe: manualSync && !skipTaskEngineProbe,
      );
    } on ChaoxingAuthenticationException {
      _needsProfileRecovery = false;
      chaoxingClient.onProgress = null;
      _clearHomePreview(notify: true);
      await _refreshChaoxingSession();
      attachProgress();
      incoming = await chaoxingClient.fetchAssignmentsWithOptions(
        collectCourseNotices: manualSync,
        enableTaskEngineProbe: manualSync && !skipTaskEngineProbe,
      );
    } on SyncReadException catch (error) {
      if (error.issue.kind == SyncIssueKind.cancelled) {
        throw const SyncCancelledException();
      }
      rethrow;
    } finally {
      chaoxingClient.onProgress = null;
      chaoxingClient.shouldStop = null;
      if (generation == _generation &&
          !_disposed &&
          !_syncCancelled &&
          operation == _syncOperation &&
          chaoxingClient.hasCourseResponse) {
        final nextCourses = chaoxingClient.courses
            .map((c) => CourseRef(
                courseId: c.courseId, clazzId: c.clazzId, name: c.courseName))
            .toList();
        final account = _account;
        if (account == null) {
          throw StateError('当前学习通账号已变化，课程资料未保存');
        }
        markSavingStage();
        await repository.saveCourses(nextCourses, account: account);
        if (generation == _generation && !_disposed) _courses = nextCourses;
      }
    }
    if (generation != _generation || _disposed) return;
    _ensureSyncActive(operation);
    var warning = chaoxingClient.lastSyncWarning;
    if (_needsProfileRecovery && !chaoxingClient.deferProfile) {
      _needsProfileRecovery = false;
      try {
        await _refreshChaoxingSession();
      } catch (_) {
        // Profile recovery is optional after a successful homework fetch.
      }
    }
    if (generation != _generation || _disposed) return;
    _ensureSyncActive(operation);
    final before = [..._assignments, ..._hiddenAssignments];
    await _markReminderMutationPending();
    markSavingStage();
    await repository.mergeAndSave(
      incoming,
      completeSync: warning == null,
      canCommit: _nativeReminderAvailable
          ? () async {
              _ensureSyncActive(operation);
              if (generation != _generation || _disposed) {
                throw const SyncCancelledException();
              }
              final current = await backgroundReminderGateway.isSessionCurrent(
                  _accountHash!, _nativeSessionEpoch);
              _ensureSyncActive(operation);
              if (generation != _generation || _disposed) {
                throw const SyncCancelledException();
              }
              return current;
            }
          : () async {
              _ensureSyncActive(operation);
              return generation == _generation && !_disposed;
            },
    );
    if (generation != _generation || _disposed) return;
    if (repository.identityConflictCount > 0) {
      warning ??= '部分旧记录存在重复关联，已暂停其提醒，请查看本地记录';
      final sources = repository.identityConflictSources;
      chaoxingClient.sourceResults = [
        for (final source in chaoxingClient.sourceResults)
          sources.contains(source.source)
              ? source.withIdentityConflict()
              : source,
      ];
    }
    final dataSuccessAt = DateTime.now();
    final dataMirrorSaved = await _writePreferenceAndVerify(
        prefs, 'sync_data_at', dataSuccessAt.toUtc().toIso8601String());
    final timestampMirrorFailed = !attemptMirrorSaved || !dataMirrorSaved;
    final reportIssues = List<SyncIssue>.of(chaoxingClient.issues);
    var courseNoticeReadFailed = false;
    var courseNoticeSaveFailed = false;
    final courseNoticeResults = chaoxingClient.sourceResults
        .where((source) => source.source == 'courseNotice')
        .toList();
    if (courseNoticeResults.isNotEmpty &&
        courseNoticeResults.first.phase != SyncSourcePhase.success) {
      courseNoticeReadFailed = true;
      reportIssues.add(const SyncIssue(
        SyncIssueKind.partial,
        '部分课程通知未更新',
        stage: 'courseNotice',
      ));
    }
    if (manualSync &&
        chaoxingClient.sourceResults.any((s) =>
            s.source == 'courseNotice' && s.phase != SyncSourcePhase.failed)) {
      final account = _account;
      if (account != null && generation == _generation && !_disposed) {
        try {
          final mergedNotices =
              _courseNotices.mergeIncoming(chaoxingClient.lastFetchedNotices);
          await repository.saveCourseNotices(mergedNotices, account);
          if (generation == _generation && !_disposed) {
            _courseNotices = mergedNotices;
          }
        } catch (error) {
          courseNoticeSaveFailed = true;
          reportIssues.add(SyncIssue(
              SyncIssueKind.storage, '作业已保存，但课程通知缓存未能更新：$error',
              stage: 'persistence'));
        }
      }
    }
    if (repository.identityConflictCount > 0) {
      reportIssues.add(const SyncIssue(
          SyncIssueKind.partial, '部分旧记录存在重复关联，已暂停其提醒，请查看本地记录',
          stage: 'identity'));
    }
    if (timestampMirrorFailed) {
      reportIssues.add(const SyncIssue(SyncIssueKind.storage,
          '作业数据已保存，但兼容同步时间记录未能完整更新；当前同步报告保留了准确时间，请重试以修复记录',
          stage: 'persistence'));
    }
    syncReport = SyncReport(
        phase: warning == null &&
                !timestampMirrorFailed &&
                !courseNoticeReadFailed &&
                !courseNoticeSaveFailed
            ? SyncPhase.success
            : SyncPhase.partial,
        attemptedAt: attempted,
        lastDataSuccessAt: dataSuccessAt,
        lastFullSuccessAt: warning == null ? dataSuccessAt : _lastSyncAt,
        succeededCourses: chaoxingClient.succeededCourses,
        failedCourses: chaoxingClient.failedCourses,
        sourceResults: chaoxingClient.sourceResults,
        issues: reportIssues);
    await _updateServerBackoff(reportIssues);
    final timestampWarning =
        timestampMirrorFailed ? '作业数据已保存，但同步时间记录未能完整保存；请重新同步核对' : null;
    final courseNoticeWarning = courseNoticeReadFailed ? '部分课程通知未更新' : null;
    _error = [warning, timestampWarning, courseNoticeWarning]
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .join('；');
    if (_error!.isEmpty) _error = null;
    try {
      await _persistSyncReport();
    } catch (_) {
      // The journal already contains the data and last-full-sync timestamp.
      // Keep the in-memory result non-successful and let the next launch
      // recover the previous running report as failed rather than claiming
      // that the status record was saved.
      syncReport = SyncReport(
          phase: SyncPhase.partial,
          attemptedAt: attempted,
          lastDataSuccessAt: dataSuccessAt,
          lastFullSuccessAt: warning == null ? dataSuccessAt : _lastSyncAt,
          succeededCourses: chaoxingClient.succeededCourses,
          failedCourses: chaoxingClient.failedCourses,
          sourceResults: chaoxingClient.sourceResults,
          issues: [
            ...reportIssues,
            const SyncIssue(
                SyncIssueKind.storage, '作业数据已保存，但同步结果记录未能保存；请重新同步核对',
                stage: 'persistence')
          ]);
      _error = '作业数据已保存，但同步结果记录未能保存；请重新同步核对';
    }
    try {
      await _reloadJournal(
        completeSync: warning == null,
        detectNewAssignments: true,
        syncCompleted: true,
        syncFailure: warning,
        completedAt: dataSuccessAt,
      );
      if (generation != _generation || _disposed) return;
      _clearHomePreview(notify: true);
      await _recordChanges(before, incoming, completeSync: warning == null);
      _error ??= warning;
    } catch (error) {
      syncReport = syncReport.copyWith(
        phase: SyncPhase.partial,
        issues: [
          ...syncReport.issues,
          SyncIssue(SyncIssueKind.storage, '作业数据已保存，但同步后的本机状态刷新未完成：$error',
              stage: 'persistence')
        ],
      );
      _error = '作业数据已保存，但同步后的本机状态刷新未完成；请重新打开或重新同步核对';
      try {
        await _persistSyncReport();
      } catch (_) {
        _error = '$_error；同步状态记录也未能保存';
      }
    }
  }

  Future<void> _refreshChaoxingSession() async {
    final generation = _generation;
    final account = _account ?? await sessionStore.readChaoxingAccount();
    final password = await sessionStore.readChaoxingPassword();
    if (account == null ||
        account.trim().isEmpty ||
        password == null ||
        password.isEmpty) {
      return;
    }
    // Restored sessions also skip optional profile/avatar requests. A profile
    // challenge must not prevent the authenticated course request from running.
    chaoxingClient.deferProfile = true;
    final result = await chaoxingClient.login(
      account: account,
      password: password,
    );
    if (!result.success) {
      throw StateError(result.message ?? '登录失败');
    }
    if (generation != _generation || _disposed) return;
    _account = account;
    if (result.displayName != null || result.avatarUrl != null) {
      final displayName = result.displayName ??
          _chaoxingDisplayName ??
          await sessionStore.readChaoxingDisplayName();
      final avatarUrl = result.avatarUrl ??
          _chaoxingAvatarUrl ??
          await sessionStore.readChaoxingAvatarUrl();
      await sessionStore.saveChaoxingAccount(
        account: account,
        password: password,
        displayName: displayName,
        avatarUrl: avatarUrl,
      );
      _chaoxingDisplayName = displayName;
      _chaoxingAvatarUrl = avatarUrl;
    }
  }

  static int normalizeAutoSyncIntervalMinutes(int minutes) {
    if (minutes <= 0) {
      return 0;
    }
    return DaytimeCheckPolicy.normalizeIntervalMinutes(minutes);
  }

  DateTime? get _latestAttemptAt {
    final attempt = _lastSyncAttemptAt;
    final success = _lastSyncAt;
    if (attempt == null) return success;
    if (success == null || attempt.isAfter(success)) return attempt;
    return success;
  }

  DateTime? _nextBackgroundTarget(DateTime now) {
    if (!_backgroundCheckSettings.enabled) return null;
    var target = DaytimeCheckPolicy.nextTarget(
      localNow: now,
      lastAttemptAt: _latestAttemptAt,
      intervalMinutes: _backgroundCheckSettings.intervalMinutes,
    );
    final backoff = _serverBackoffUntil;
    if (backoff != null && backoff.isAfter(target)) {
      target = backoff;
    }
    return target;
  }

  DateTime? _nextNotificationWindowTarget(DateTime now) {
    if (!_backgroundCheckSettings.notificationListenerEnabled) return null;
    var target = DaytimeCheckPolicy.isInWindow(now)
        ? now
        : DaytimeCheckPolicy.nextWindowStart(now);
    final backoff = _serverBackoffUntil;
    if (backoff != null && backoff.isAfter(target)) {
      target = backoff;
    }
    return target;
  }

  /// Applies settings/schedule to the native side. Returns false only when a
  /// control write was not confirmed, so callers can refuse to activate a plan
  /// under stale settings. Health is diagnostic and never blocks that result.
  Future<bool> _reconcileBackgroundControls({DateTime? now}) async {
    if (!_nativeReminderAvailable) return true;
    final current = now ?? DateTime.now();
    final accountHash = _accountHash;
    try {
      if (_authenticated && accountHash != null) {
        await backgroundReminderGateway.updateSettings(
          accountHash,
          _nativeSessionEpoch,
          _backgroundCheckSettings,
          showDetails: notificationService.showDetails,
          reconcileSchedules: _manageBackgroundSchedule,
        );
      }
      if (_manageBackgroundSchedule) {
        await backgroundReminderGateway.reconcileDaytimeSchedule(
          targetAt: _authenticated ? _nextBackgroundTarget(current) : null,
          enabled: _authenticated && _backgroundCheckSettings.enabled,
          intervalMinutes: _backgroundCheckSettings.intervalMinutes,
        );
      }
    } catch (error) {
      _backgroundWarning =
          '后台提醒设置未确认：${error.toString().replaceFirst('PlatformException', '后台提醒')}';
      return false;
    }
    try {
      if (accountHash != null) {
        final health = await backgroundReminderGateway.inspectHealth(
          accountHash: accountHash,
          sessionEpoch: _nativeSessionEpoch,
        );
        _backgroundWarning = health.lastFailure;
      }
    } catch (error) {
      _backgroundWarning = '后台提醒体检读取失败：$error';
    }
    return true;
  }

  Future<void> _updateServerBackoff(Iterable<SyncIssue> issues) async {
    final seconds = issues
        .map((issue) => issue.retryAfterSeconds ?? 0)
        .where((value) => value > 0)
        .fold<int>(0, max);
    final prefs = await SharedPreferences.getInstance();
    if (seconds == 0) {
      if (syncReport.phase == SyncPhase.success) {
        _serverBackoffUntil = null;
        await prefs.remove(_serverBackoffKey);
      }
      return;
    }
    final until = DateTime.now().add(Duration(seconds: seconds));
    _serverBackoffUntil = until;
    await prefs.setString(
      _serverBackoffKey,
      until.toUtc().toIso8601String(),
    );
  }

  Future<void> _recordBackgroundAttempt({
    required DateTime attemptedAt,
    required bool dataSucceeded,
    required bool fullSucceeded,
    required String? failure,
  }) async {
    final accountHash = _accountHash;
    if (!_nativeReminderAvailable || !_authenticated || accountHash == null) {
      return;
    }
    try {
      await backgroundReminderGateway.recordAttempt(
        accountHash: accountHash,
        sessionEpoch: _nativeSessionEpoch,
        attemptedAt: attemptedAt,
        dataSucceeded: dataSucceeded,
        fullSucceeded: fullSucceeded,
        failure: failure,
      );
      await _reconcileBackgroundControls(now: attemptedAt);
    } catch (error) {
      _backgroundWarning = error.toString();
    }
  }

  Future<void>? _operations;

  Future<void> _run(Future<void> Function() action) {
    // Seed lazily in the caller's zone, including WidgetTester's fake clock.
    final previous = _operations ?? Future<void>.value();
    return _operations = previous.then((_) => _execute(action));
  }

  Future<void> _execute(Future<void> Function() action) async {
    if (_disposed) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      if (error is SyncCancelledException) {
        // A stopped operation never advances full-success time and is not
        // merged as an empty snapshot. Already committed data stays committed.
        _error = '本次同步已取消';
        syncReport = SyncReport(
          phase: SyncPhase.cancelled,
          attemptedAt: syncReport.attemptedAt,
          lastDataSuccessAt: syncReport.lastDataSuccessAt,
          lastFullSuccessAt: _lastSyncAt,
          succeededCourses: chaoxingClient.succeededCourses,
          failedCourses: chaoxingClient.failedCourses,
          issues: const [
            SyncIssue(SyncIssueKind.cancelled, '本次同步已取消', stage: 'request')
          ],
        );
        try {
          await _persistSyncReport();
        } catch (_) {
          // The in-memory cancelled phase still prevents a success claim.
        }
        return;
      }
      _error = _friendlyError(error);
      if (syncReport.phase == SyncPhase.running) {
        final storageFailure = error is LocalStorageWriteException;
        syncReport = SyncReport(
            phase: SyncPhase.failed,
            attemptedAt: syncReport.attemptedAt ?? _lastSyncAttemptAt,
            lastDataSuccessAt: syncReport.lastDataSuccessAt,
            lastFullSuccessAt: _lastSyncAt,
            issues: [
              ...chaoxingClient.issues,
              if (storageFailure)
                SyncIssue(SyncIssueKind.storage, _error!, stage: 'persistence')
              else if (chaoxingClient.issues.isEmpty)
                error is SyncReadException
                    ? error.issue
                    : SyncIssue(
                        error is ChaoxingAuthenticationException
                            ? SyncIssueKind.authExpired
                            : SyncIssueKind.network,
                        _error!)
            ]);
        await _updateServerBackoff(syncReport.issues);
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
          await _persistSyncReport();
        } catch (_) {
          _error = '$_error；同步结果未能保存，请重试';
        }
      }
    } finally {
      _loading = false;
      _clearHomePreview();
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _persistSyncReport() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(syncReport.toJson());
    if (!await _writePreferenceAndVerify(prefs, 'sync_report_v1', encoded)) {
      throw StateError('同步结果未能保存');
    }
  }

  Future<void> _cancelPrivateNotifications() async {
    _privacyCleanupPending = true;
    try {
      await _persistPrivacyCleanupPending(true);
      if (_manageBackgroundSchedule) {
        await notificationService.cancelPrivateSchedules();
      }
      final nativeTargets = <String>{
        ..._pendingNativeCleanupAccounts,
        if (_nativeReminderAvailable && _accountHash != null) _accountHash!,
      };
      var pendingChanged = false;
      for (final target in nativeTargets) {
        final pendingAccount = _pendingNativeCleanupAccounts.contains(target);
        if (!_nativeReminderAvailable) {
          // No bridge means no proof the old account was cleaned. Keep the
          // durable target; deleting it here would silently lose retry state.
          continue;
        }
        if (pendingAccount) {
          // Account-level cleanup also cancels background work and alarms;
          // delivery cleanup alone is not enough to retry a failed logout.
          await backgroundReminderGateway.clearActiveAccount(target);
        }
        await backgroundReminderGateway
            .cancelAssignmentDeliveryKeepEvents(target);
        if (pendingAccount && _pendingNativeCleanupAccounts.remove(target)) {
          pendingChanged = true;
        }
      }
      if (pendingChanged) {
        // Retry evidence is only cleared after the native side confirmed the
        // delivery cleanup for that old identity.
        await _persistNativeCleanupAccounts();
      }
      if (_pendingNativeCleanupAccounts.isEmpty) {
        await _persistPrivacyCleanupPending(false);
        final prefs = await SharedPreferences.getInstance();
        if (_manageBackgroundSchedule &&
            prefs.getBool('notification_details_v1') == false) {
          await _writeBoolPreferenceAndVerify(
              prefs, _privacyVerifiedHiddenKey, true);
        }
        _privacyCleanupPending = false;
      } else {
        // A failed account-level cleanup is still pending even when delivery
        // cancellation succeeded. Keep the durable marker for the next retry.
        await _persistPrivacyCleanupPending(true);
        _privacyCleanupPending = true;
        throw StateError('原生提醒通道不可用，旧账号清理状态未确认');
      }
    } catch (error) {
      _privacyCleanupPending = true;
      try {
        await _persistPrivacyCleanupPending(true);
      } catch (_) {
        // The in-memory state remains fail-closed even if persistence fails.
      }
      throw StateError(_privacyCleanupMessage(error));
    }
  }

  Future<void> _persistPrivacyCleanupPending(bool pending) async {
    final prefs = await SharedPreferences.getInstance();
    if (pending) {
      if (prefs.getBool(_privacyCleanupPendingKey) != true) {
        final saved = await prefs.setBool(_privacyCleanupPendingKey, true);
        if (!saved) {
          await prefs.reload();
          if (prefs.getBool(_privacyCleanupPendingKey) != true) {
            throw StateError('通知隐私待清理状态未能保存');
          }
        }
      }
      return;
    }
    final removed = await prefs.remove(_privacyCleanupPendingKey);
    if (!removed) {
      await prefs.reload();
      if (prefs.getBool(_privacyCleanupPendingKey) == true) {
        throw StateError('通知隐私待清理状态未能清除');
      }
    }
  }

  Future<void> _persistNativeCleanupAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    if (_pendingNativeCleanupAccounts.isEmpty) {
      final removed = await prefs.remove(_nativeCleanupAccountsKey);
      if (!removed) {
        await prefs.reload();
        if (prefs.getStringList(_nativeCleanupAccountsKey) != null) {
          throw StateError('旧账号原生提醒清理目标未能清除');
        }
      }
      return;
    }
    final values = _pendingNativeCleanupAccounts.toList()..sort();
    if (!await prefs.setStringList(_nativeCleanupAccountsKey, values)) {
      await prefs.reload();
      if (!listEquals(prefs.getStringList(_nativeCleanupAccountsKey), values)) {
        throw StateError('旧账号原生提醒清理目标未能保存');
      }
    }
  }

  String _privacyCleanupMessage(Object error) =>
      notificationService.lastWarning ??
      error
          .toString()
          .replaceFirst('Bad state: ', '')
          .replaceFirst('旧账号私人通知未能完整清理：', '');

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
    chaoxingClient.cancelActiveRequests();
    _clearHomePreview();
    _generation++;
    super.dispose();
  }
}

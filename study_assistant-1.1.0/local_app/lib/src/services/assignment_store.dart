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
import 'daily_summary.dart';
import 'daytime_check_policy.dart';
import '../models/assignment_change.dart';
import '../models/backup_snapshot.dart';
import '../models/course_term_preferences.dart';
import '../models/local_coursework_state.dart';
import '../models/personal_workspace.dart';
import '../models/pinned_assignments.dart';
import '../models/reminder_history.dart';
import '../models/study_notebook.dart';
import 'course_term_catalog.dart';
import 'coursework_deadline.dart';
import 'deadline_quiet_hours_policy.dart';
import 'reminder_explanation.dart';

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

  String exportSanitizedSyncDiagnostics() =>
      ChaoxingSyncDiagnosticsExporter.exportJson(
        appVersion: AppVersion.display,
        report: syncReport,
        phaseElapsedMs: chaoxingClient.diagnostics.phaseElapsedMs,
        requestTimings: chaoxingClient.requestTimings,
      );

  Future<void>? _filterWrites;

  Future<bool> saveHomeFilters(HomeFilters next, int expectedEpoch) {
    final account = _account;
    if (account == null ||
        !_authenticated ||
        _disposed ||
        _generation != expectedEpoch) {
      return Future<bool>.value(false);
    }
    final encoded = next.encode();
    final write = (_filterWrites ?? Future<void>.value()).then((_) async {
      if (_disposed ||
          !_authenticated ||
          _generation != expectedEpoch ||
          _account != account) {
        return false;
      }
      try {
        await repository.saveHomeFilters(next, account);
      } on StaleSessionWriteException {
        return false;
      } catch (error) {
        if (!_disposed &&
            _authenticated &&
            _generation == expectedEpoch &&
            _account == account) {
          _error = _friendlyError(error);
          notifyListeners();
        }
        return false;
      }
      if (_disposed ||
          !_authenticated ||
          _generation != expectedEpoch ||
          _account != account) {
        return false;
      }
      _error = null;
      homeFilters = HomeFilters.decode(encoded);
      notifyListeners();
      return true;
    });
    _filterWrites = write.then<void>((_) {}, onError: (Object _) {});
    return write;
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
      _invalidatePinnableKeys();
      saved = true;
      await _cleanupRemovedManualAttachments(previous, notebook);
      if (_pinsNeedSave || _pinned.keys.any(ManualEntry.isManualKey)) {
        await _prunePins();
      }
      if (!_ownsAuthenticatedSession(expectedEpoch, account)) {
        return;
      }
      final manualSucceeded = await _afterAssignmentsChanged(
        updateAssignmentReminders: false,
        updateSummary: false,
        updateManual: true,
        updateWidget: false,
      );
      await _recordManualCancellationOutcomes(
        previous,
        notebook,
        rescheduleSucceeded: manualSucceeded,
      );
    });
    return saved;
  }

  static bool _dailyPlansChanged(
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
      final previous = personal;
      final next = update(previous);
      await repository.savePersonalWorkspace(next, account);
      if (_generation != expectedEpoch || !_authenticated) return;
      personal = PersonalWorkspace.decode(next.encode());
      saved = true;
      final summarySettingsChanged =
          previous.summaryEnabled != personal.summaryEnabled ||
              previous.summaryHour != personal.summaryHour ||
              previous.summaryMinute != personal.summaryMinute;
      final plansChanged = _dailyPlansChanged(previous.plans, personal.plans);
      final needSummary = summarySettingsChanged ||
          ((previous.summaryEnabled || personal.summaryEnabled) &&
              plansChanged);
      if (needSummary) {
        await _afterAssignmentsChanged(
          updateAssignmentReminders: false,
          updateSummary: true,
          updateManual: false,
          updateWidget: false,
        );
      }
    });
    return saved;
  }

  Future<bool> markNoticeLocalRead(
    String noticeId, {
    bool read = true,
    int expectedEpoch = -1,
  }) async {
    final epoch = expectedEpoch >= 0 ? expectedEpoch : _generation;
    if (expectedEpoch >= 0 && expectedEpoch != _generation) return false;
    final account = _account;
    var saved = false;
    await _run(() async {
      if (account == null ||
          !_authenticated ||
          _disposed ||
          _generation != epoch ||
          account != _account) {
        return;
      }
      final next = _courseNotices.markLocalRead(noticeId, read: read);
      await repository.saveCourseNotices(next, account);
      if (_disposed ||
          _generation != epoch ||
          !_authenticated ||
          account != _account) {
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
      final chapterOperation = ++_syncOperation;
      bool chapterCancelled() =>
          _syncCancelled || chapterOperation != _syncOperation;
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
                        courseName: c.name,
                        teacherNames: c.teacherNames,
                        folderName: c.folderName,
                      ))
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
                  courseName: c.name,
                  teacherNames: c.teacherNames,
                  folderName: c.folderName,
                ));
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
          if (chapterCancelled() ||
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
              if (chapterCancelled() ||
                  _generation != epoch ||
                  !_authenticated ||
                  _disposed) {
                break;
              }
              await _refreshChaoxingSession();
              if (chapterCancelled() ||
                  _generation != epoch ||
                  !_authenticated ||
                  _disposed) {
                break;
              }
              snapshot = await chaoxingClient.fetchCourseChapters(target);
            }
            if (chapterCancelled() ||
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
          } on StaleSessionWriteException {
            break;
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
        succeeded =
            updatedCount > 0 && firstIssue == null && !chapterCancelled();
        if (chapterCancelled()) {
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
    if (expectedEpoch >= 0 && expectedEpoch != _generation) return null;
    final account = _account;
    ManualEntry? created;
    await _run(() async {
      if (account == null ||
          !_authenticated ||
          _disposed ||
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
        _error = '待办已达 500 条上限，请清理后再添加';
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
      if (_disposed ||
          _generation != epoch ||
          !_authenticated ||
          account != _account) {
        return;
      }
      final previous = notebook;
      notebook = StudyNotebook.decode(nextNotebook.encode());
      _invalidatePinnableKeys();
      final manualSucceeded = await _afterAssignmentsChanged();
      await _recordManualCancellationOutcomes(
        previous,
        notebook,
        rescheduleSucceeded: manualSucceeded,
      );
      if (_disposed ||
          _generation != epoch ||
          !_authenticated ||
          account != _account) {
        return;
      }
      final nextNotices = _courseNotices.bindManualEntry(notice.id, entry.id);
      await repository.saveCourseNotices(nextNotices, account);
      if (_disposed ||
          _generation != epoch ||
          !_authenticated ||
          account != _account) {
        return;
      }
      _courseNotices = nextNotices;
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
    if (expectedEpoch >= 0 && expectedEpoch != _generation) return null;
    final account = _account;
    ManualEntry? created;
    await _run(() async {
      if (account == null ||
          !_authenticated ||
          _disposed ||
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
        _error = '待办已达 500 条上限，请清理后再添加';
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
      if (_disposed ||
          _generation != epoch ||
          !_authenticated ||
          account != _account) {
        return;
      }
      final previous = notebook;
      notebook = StudyNotebook.decode(nextNotebook.encode());
      _invalidatePinnableKeys();
      final manualSucceeded = await _afterAssignmentsChanged();
      await _recordManualCancellationOutcomes(
        previous,
        notebook,
        rescheduleSucceeded: manualSucceeded,
      );
      if (_disposed ||
          _generation != epoch ||
          !_authenticated ||
          account != _account) {
        return;
      }
      final nextCatalog = _courseChapters.bindManualEntry(
        snapshot.courseKey,
        node.sectionId,
        entry.id,
      );
      await repository.saveCourseChapters(nextCatalog, account);
      if (_disposed ||
          _generation != epoch ||
          !_authenticated ||
          account != _account) {
        return;
      }
      _courseChapters = nextCatalog;
      created = entry;
    });
    return created;
  }

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

  ReturnCheckConfirmation? consumeReturnCheckConfirmation() {
    final current = _pendingReturnConfirmation;
    _pendingReturnConfirmation = null;
    return current;
  }

  void beginAssignmentVisit(String id) {
    if (!_authenticated || findAssignment(id) == null) return;
    _visitedAssignment = id;
    _visitGeneration = _generation;
    _activeVisitTicket = ++_nextVisitTicket;
    _visitLeftApp = false;
    _pendingReturnConfirmation = null;
    returnCheckMessage = null;
  }

  void cancelAssignmentVisit(String id) {
    if (_visitedAssignment == id) {
      _visitedAssignment = null;
      _activeVisitTicket = null;
      _visitLeftApp = false;
    }
  }

  void markAssignmentVisitLeftApp() {
    if (_visitedAssignment != null && _activeVisitTicket != null) {
      _visitLeftApp = true;
    }
  }

  void dismissReturnCheck() {
    returnCheckMessage = null;
    notifyListeners();
  }

  Future<void> checkReturnedAssignment() async {
    final id = _visitedAssignment;
    final generation = _visitGeneration;
    final ticket = _activeVisitTicket;
    if (id == null || ticket == null || !_visitLeftApp) return;
    _visitedAssignment = null;
    _activeVisitTicket = null;
    _visitLeftApp = false;
    _pendingReturnConfirmation = null;
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
      if (target.isExam) {
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
      } else {
        Assignment? single;
        try {
          single = await chaoxingClient.fetchReturnedWork(target);
        } on ChaoxingAuthenticationException {
          await _refreshChaoxingSession();
          single = await chaoxingClient.fetchReturnedWork(target);
        }
        incoming = single == null ? const <Assignment>[] : [single];
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
      final unconfirmed = observed == null ||
          observed.status == 'unknown' ||
          observed.statusLabel == '提交状态未知' ||
          conflictsWithConfirmation;
      if (unconfirmed) {
        returnCheckMessage = observed?.isSupportedClassroomTask == true
            ? '本次未能确认提交状态，已更新为待确认；确认前暂停提醒。'
            : '本次未能确认提交状态，已保留原记录；请稍后刷新核对。';
      } else if (observed.isCompleted) {
        if (!latestBefore.isCompleted) {
          final event = ReturnCheckConfirmation(
            id: ++_nextConfirmationId,
            accountEpoch: accountEpoch,
            assignmentId: observed.id,
            title: observed.title,
            message: '《${observed.title}》已确认提交',
            confirmedAt: _clock(),
          );
          _pendingReturnConfirmation = event;
          returnCheckMessage = event.message;
        } else {
          returnCheckMessage =
              '已确认提交：${observed.title}（${observed.statusLabel}）';
        }
      } else {
        returnCheckMessage = '刚才的作业仍为${observed.statusLabel}，提醒继续保留。';
      }
      confirmed = true;
    });
    if (generation != _generation || !_authenticated || _disposed) return;
    if (!confirmed) returnCheckMessage = '本次未能确认提交状态，已保留原记录和提醒；请稍后重试。';
    notifyListeners();
  }

  Future<void> _recordChanges(
    List<Assignment> before,
    List<Assignment> incoming, {
    bool completeSync = false,
    _SessionSnapshot? session,
  }) async {
    final snap = session ?? _captureSession();
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
      final loaded = await _runScopedWrite(snap, (prefs) async {
        await changeLog.record(
          before,
          after,
          observedIds,
          completeSync: completeSync,
          prefs: prefs,
          at: _clock(),
        );
        return changeLog.load(prefs: prefs);
      });
      if (!_isSessionCurrent(snap)) return;
      changes = loaded;
      _termCatalogCache = null;
    } on StaleSessionWriteException {
      return;
    } catch (_) {
      if (snap.generation == _generation && !_disposed) {
        _recoveryWarnings.add('部分作业变化记录未能保存或读取，请稍后重试');
      }
    }
  }

  SyncReport syncReport = const SyncReport();
  HistoricalSweepState _historicalSweepState =
      const HistoricalSweepState.empty();
  HistoricalSweepState get historicalSweepState => _historicalSweepState;
  AssignmentSyncScope _lastRequestedSyncScope = AssignmentSyncScope.current;
  Set<String> _lastTargetedCourseKeys = const {};
  List<SyncSourceResult> _lastSyncSourceResults = const [];
  int _generation = 0;
  bool _disposed = false, _loginRunning = false;
  String get syncSummary {
    if (_serviceWarnings.isNotEmpty && syncReport.phase == SyncPhase.success) {
      return hasWidgetWarningOnly ? '作业已更新，小组件需要处理' : '作业已更新，提醒或小组件需要处理';
    }
    return syncReport.summary;
  }

  bool get hasWidgetWarningOnly =>
      _widgetWarnings.isNotEmpty &&
      _serviceWarnings.length == _widgetWarnings.length &&
      _recoveryWarnings.isEmpty &&
      _error == null &&
      repository.recoveryWarning == null;

  bool get hasNonQuietServiceWarning =>
      _serviceWarnings.isNotEmpty && !hasWidgetWarningOnly;
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
  static const _deadlineChannelV2AutoMigratedKey =
      'deadline_channel_v2_auto_migrated_v1';
  String _deadlineChannelId = LocalNotificationService.assignmentV2Channel;
  bool _migratedDeadlineChannelToV2ThisRestore = false;
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
  final List<String> _privacyWarnings = [];
  final List<String> _deadlineWarnings = [];
  final List<String> _summaryWarnings = [];
  final List<String> _manualWarnings = [];
  final List<String> _widgetWarnings = [];
  final List<String> _recoveryWarnings = [];
  List<String> get serviceWarnings => List.unmodifiable(_serviceWarnings);
  List<String> get manualSaveWarnings =>
      List.unmodifiable([..._privacyWarnings, ..._manualWarnings]);
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
    Iterable<String>? warnings,
  }) {
    final mergedWarnings = {
      if (repository.recoveryWarning != null) repository.recoveryWarning!,
      ...(warnings ?? _serviceWarnings),
    };
    return [
      saved ? successMessage : failureMessage,
      ...mergedWarnings,
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
  bool get allowUrgentDeadlineNightBreakthrough =>
      _allowUrgentDeadlineNightBreakthrough;
  String get activeDeadlineChannelId => _deadlineChannelId;
  bool get isUsingV2DeadlineChannel =>
      _deadlineChannelId == LocalNotificationService.assignmentV2Channel;
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
      CourseworkDeadline.entryFor(assignment, _courseworkState);
  CourseworkDeadline? effectiveDeadlineFor(Assignment assignment) =>
      CourseworkDeadline.resolveEntry(
          assignment, courseworkEntryFor(assignment));
  DateTime? manualDeadlineFor(Assignment assignment) =>
      courseworkEntryFor(assignment)?.manualDeadlineAt;
  bool isLocallyCompleted(Assignment assignment) =>
      _authenticated &&
      CourseworkDeadline.isLocallyCompleted(assignment, _courseworkState);
  bool isEffectivelyCompleted(Assignment assignment) =>
      assignment.isCompleted || isLocallyCompleted(assignment);

  AssignmentChange? latestDeadlineChangeFor(Assignment assignment) {
    for (final event in changes) {
      if (event.assignmentId == assignment.id &&
          event.kind == AssignmentChangeKind.deadline) {
        return event;
      }
    }
    return null;
  }

  AssignmentChange? activeDeadlineAlertFor(Assignment assignment) {
    if (_journalRestoreFailed ||
        changes.isEmpty ||
        isEffectivelyCompleted(assignment)) {
      return null;
    }
    final latest = latestDeadlineChangeFor(assignment);
    if (latest == null || !latest.isAdvanceDeadlineAlert) return null;
    if (_acknowledgedDeadlineChangeIds.contains(latest.effectiveChangeId)) {
      return null;
    }
    return latest;
  }

  Future<bool> acknowledgeDeadlineAlert(String changeId) async {
    final normalized = changeId.trim();
    if (normalized.isEmpty) return false;
    if (_acknowledgedDeadlineChangeIds.contains(normalized)) return true;
    final snap = _captureSession();
    if (!snap.authenticated || snap.account == null) return false;
    var nextSet = <String>{..._acknowledgedDeadlineChangeIds, normalized};
    try {
      await _runScopedWrite(snap, (prefs) async {
        final durable =
            await repository.readAcknowledgedDeadlineChangeIdsInPrefs(prefs);
        final merged = <String>{
          ..._acknowledgedDeadlineChangeIds,
          ...durable,
        };
        final nextOrdered = <String>[
          normalized,
          for (final c in changes)
            if (merged.contains(c.effectiveChangeId) &&
                c.effectiveChangeId != normalized)
              c.effectiveChangeId,
          for (final id in merged)
            if (id != normalized) id,
        ];
        nextSet = nextOrdered.take(300).toSet();
        await repository.writeAcknowledgedDeadlineChangeIdsInPrefs(
          prefs,
          nextOrdered,
        );
      });
    } on StaleSessionWriteException {
      return false;
    } on LocalStorageLeaseReleaseException {
      const warning = '时间变更提醒确认状态已保存，本机写入通道释放未确认，请稍后重试其他写入';
      if (snap.generation == _generation &&
          !_recoveryWarnings.contains(warning)) {
        _recoveryWarnings.add(warning);
      }
    } catch (_) {
      return false;
    }
    if (!_isSessionCurrent(snap)) return false;
    _acknowledgedDeadlineChangeIds = nextSet;
    notifyListeners();
    return true;
  }

  Future<bool> _mutateCourseworkState(
    _SessionSnapshot snap,
    LocalCourseworkState Function(Assignment current) transform, {
    required String leaseWarning,
  }) async {
    var saved = false;
    await _run(() async {
      if (!_isSessionCurrent(snap)) return;
      final next = transform(Assignment(
        id: '_',
        courseName: '',
        title: '',
        deadlineAt: null,
        requirementsText: '',
        status: 'unknown',
        lastSyncedAt: _clock(),
      ));
      if (next == _courseworkState) {
        saved = true;
        return;
      }
      await _markReminderMutationPending();
      if (!_isSessionCurrent(snap)) return;
      try {
        await _runScopedWrite(
          snap,
          (prefs) => repository.writeCourseworkStateInPrefs(prefs, next),
        );
      } on StaleSessionWriteException {
        return;
      } on LocalStorageLeaseReleaseException {
        if (snap.generation == _generation &&
            !_recoveryWarnings.contains(leaseWarning)) {
          _recoveryWarnings.add(leaseWarning);
        }
      } catch (_) {
        return;
      }
      if (!_isSessionCurrent(snap)) return;
      _courseworkState = next;
      _invalidateHomeDisplayIndex();
      saved = true;
      await _afterAssignmentsChanged(
        updateSummary: true,
        updateManual: false,
        updateWidget: true,
      );
      if (_isSessionCurrent(snap)) notifyListeners();
    });
    return saved;
  }

  Future<bool> setManualDeadline(Assignment assignment, DateTime? at) async {
    final snap = _captureSession();
    if (!snap.authenticated || snap.account == null || assignment.isExam) {
      return false;
    }
    if (at != null &&
        !CourseworkDeadline.canSetManualDeadline(
          assignment,
          entry: courseworkEntryFor(assignment),
        )) {
      return false;
    }
    return _mutateCourseworkState(
      snap,
      (_) {
        final current = findAnyAssignment(assignment.id) ?? assignment;
        if (at != null &&
            !CourseworkDeadline.canSetManualDeadline(
              current,
              entry: courseworkEntryFor(current),
            )) {
          return _courseworkState;
        }
        return _courseworkState.withManualDeadline(
          CourseworkDeadline.keyFor(current),
          CourseworkDeadline.aliasesFor(current),
          at,
        );
      },
      leaseWarning: '手动截止状态已保存，本机写入通道释放未确认，请稍后重试其他写入',
    );
  }

  Future<bool> setLocallyCompleted(
    Assignment assignment,
    bool completed,
  ) async {
    final snap = _captureSession();
    if (!snap.authenticated || snap.account == null) return false;
    return _mutateCourseworkState(
      snap,
      (_) {
        final current = findAnyAssignment(assignment.id) ?? assignment;
        return _courseworkState.withLocallyCompleted(
          CourseworkDeadline.keyFor(current),
          CourseworkDeadline.aliasesFor(current),
          completed,
        );
      },
      leaseWarning: '本机完成状态已保存，本机写入通道释放未确认，请稍后重试其他写入',
    );
  }

  Future<void> _reconcileCourseworkState() async {
    final snap = _captureSession();
    if (!snap.authenticated ||
        snap.account == null ||
        _journalRestoreFailed ||
        repository.recoveryWarning != null ||
        _courseworkState.isEmpty) {
      return;
    }
    final reconciled = CourseworkDeadline.reconcileWithAssignments(
      _courseworkState,
      [..._assignments, ..._hiddenAssignments],
    );
    if (reconciled == _courseworkState) return;
    try {
      await _runScopedWrite(
        snap,
        (prefs) => repository.writeCourseworkStateInPrefs(prefs, reconciled),
      );
    } on StaleSessionWriteException {
      return;
    } on LocalStorageLeaseReleaseException {
      const warning = '个人截止状态已同步清理，本机写入通道释放未确认，请稍后重试其他写入';
      if (snap.generation == _generation &&
          !_recoveryWarnings.contains(warning)) {
        _recoveryWarnings.add(warning);
      }
    } catch (_) {
      const warning = '部分个人截止状态同步整理未能保存，请稍后重试';
      if (snap.generation == _generation &&
          !_recoveryWarnings.contains(warning)) {
        _recoveryWarnings.add(warning);
      }
      return;
    }
    if (!_isSessionCurrent(snap)) return;
    _courseworkState = reconciled;
    _invalidateHomeDisplayIndex();
  }

  Set<String> _pinAliases(Assignment assignment) {
    final key = _pinKey(assignment);
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

  bool isPinned(Assignment assignment) =>
      _authenticated && _pinned.containsAny(_pinAliases(assignment));

  Set<String>? _pinnableKeysCache;
  int? _pinnableKeysCacheMinute;

  void _invalidatePinnableKeys() =>
      _pinnableKeysCache = _pinnableKeysCacheMinute = null;

  Set<String> _pinnableKeys() {
    final now = _clock();
    final minute = now.millisecondsSinceEpoch ~/ 60000;
    if (_pinnableKeysCache != null && _pinnableKeysCacheMinute == minute) {
      return _pinnableKeysCache!;
    }
    _pinnableKeysCacheMinute = minute;
    return _pinnableKeysCache = {
      for (final item in visibleAssignments) _pinKey(item),
      for (final entry in notebook.entries)
        if (!entry.done) manualPinKeyOf(entry),
    };
  }

  bool canTogglePin(Assignment assignment) =>
      _manageBackgroundSchedule &&
      _authenticated &&
      _account != null &&
      _pinnableKeys().contains(_pinKey(assignment));

  Future<bool> togglePin(Assignment assignment) => _togglePinKey(
        _pinKey(assignment),
        _pinAliases(assignment),
        () => canTogglePin(assignment),
      );

  bool isManualPinned(ManualEntry entry) =>
      _authenticated && _pinned.containsAny([manualPinKeyOf(entry)]);

  bool canToggleManualPin(ManualEntry entry) =>
      _manageBackgroundSchedule &&
      _authenticated &&
      _account != null &&
      !entry.done &&
      _pinnableKeys().contains(manualPinKeyOf(entry));

  Future<bool> toggleManualPin(ManualEntry entry) {
    final key = manualPinKeyOf(entry);
    return _togglePinKey(key, [key], () => canToggleManualPin(entry));
  }

  Future<bool> _togglePinKey(
    String key,
    Iterable<String> aliases,
    bool Function() canToggle,
  ) async {
    final account = _account;
    final generation = _generation;
    if (account == null || !canToggle()) return false;
    var saved = false;
    await _run(() async {
      bool stillOwned() => _ownsAuthenticatedSession(generation, account);
      bool valid() => stillOwned() && canToggle();
      if (!valid()) return;
      final next = _pinned.toggle(key, aliases);
      final persisted = await _savePins(next, account, generation);
      if (!persisted || !stillOwned()) return;
      _pinned = next;
      _pinsNeedSave = false;
      saved = true;
    });
    return saved;
  }

  Future<bool> reorderPinned(List<String> visibleOrderedKeys) async {
    final account = _account;
    final generation = _generation;
    if (account == null || !_authenticated || !_manageBackgroundSchedule) {
      return false;
    }
    final cleanOrdered = [
      for (final raw in visibleOrderedKeys)
        if (raw.trim().isNotEmpty) raw.trim(),
    ];
    // Filters may hide pinned slots; only the visible subset is reordered.
    final pinnable = _pinnableKeys();
    if (cleanOrdered.isEmpty ||
        cleanOrdered.toSet().length != cleanOrdered.length ||
        cleanOrdered.any(
            (key) => !pinnable.contains(key) || !_pinned.keys.contains(key))) {
      return false;
    }
    final visibleKeySet = cleanOrdered.toSet();
    var saved = false;
    await _run(() async {
      if (!_manageBackgroundSchedule ||
          !_ownsAuthenticatedSession(generation, account)) {
        return;
      }
      final next = _pinned.reorderVisible(cleanOrdered, visibleKeySet);
      if (next == null) return;
      if (!await _savePins(next, account, generation) ||
          !_ownsAuthenticatedSession(generation, account)) {
        return;
      }
      _pinned = next;
      _pinsNeedSave = false;
      saved = true;
    });
    return saved;
  }

  bool _ownsAuthenticatedSession(int generation, String? account) =>
      !_disposed &&
      _authenticated &&
      account != null &&
      generation == _generation &&
      account == _account;

  Future<bool> _savePins(
      PinnedAssignments pins, String account, int generation) async {
    try {
      await repository.savePinnedAssignments(pins, account);
      return true;
    } on StaleSessionWriteException {
      return false;
    } on LocalStorageLeaseReleaseException {
      const warning = '置顶状态已保存，本机写入通道释放未确认，请稍后重试其他写入';
      if (_ownsAuthenticatedSession(generation, account) &&
          !_recoveryWarnings.contains(warning)) {
        _recoveryWarnings.add(warning);
      }
      return true;
    }
  }

  Future<void> _prunePins() async {
    final account = _account;
    // Only the foreground store manages pins, and never prune after a
    // failed/damaged journal read. Keys absent merely due to unfollowed
    // courses, partial sync frames, or filters must remain pinned on disk.
    if (!_manageBackgroundSchedule ||
        !_authenticated ||
        account == null ||
        (_pinned.isEmpty && !_pinsNeedSave) ||
        _journalRestoreFailed ||
        repository.recoveryWarning != null) {
      return;
    }
    final aliasToCanonical = <String, String>{};
    final explicitlyCompletedOrHiddenKeys = <String>{};
    for (final group in localRecordGroups) {
      final canonical = _pinKey(group.primary);
      for (final alias in _pinAliases(group.primary)) {
        aliasToCanonical[alias] = canonical;
      }
      for (final source in group.sources) {
        for (final alias in _pinAliases(source)) {
          aliasToCanonical[alias] = canonical;
        }
      }
      if (group.hidden ||
          group.primary.isCompleted ||
          isLocallyCompleted(group.primary) ||
          AssignmentQuery.isExamEnded(group.primary, _clock())) {
        explicitlyCompletedOrHiddenKeys.add(canonical);
        explicitlyCompletedOrHiddenKeys.addAll(_pinAliases(group.primary));
        for (final source in group.sources) {
          explicitlyCompletedOrHiddenKeys.addAll(_pinAliases(source));
        }
      }
    }
    for (final key in _pinned.keys.where(ManualEntry.isManualKey)) {
      final id = key.substring(ManualEntry.pinPrefix.length);
      if (!notebook.hasActiveEntry(id)) {
        explicitlyCompletedOrHiddenKeys.add(key);
      }
    }
    final retained = _pinned.migrateAndPrune(
      aliasToCanonical: aliasToCanonical,
      explicitlyCompletedOrHiddenKeys: explicitlyCompletedOrHiddenKeys,
    );
    if (retained == _pinned && !_pinsNeedSave) return;
    _pinned = retained;
    _pinsNeedSave = true;
    final generation = _generation;
    try {
      final persisted = await _savePins(_pinned, account, generation);
      if (persisted && _ownsAuthenticatedSession(generation, account)) {
        _pinsNeedSave = false;
      }
    } catch (_) {
      // The next successful journal update can retry without restoring pins
      // for entries already removed during this session.
    }
  }

  List<CourseRef> _courses = [];
  List<CourseRef> get courses => List.unmodifiable(_courses);
  bool follows(String key) => !_unfollowed.contains(key);
  CourseTermPreferences get courseTermPreferences => _courseTermPreferences;

  CourseTermCatalog get termCatalog {
    final currentNow = _clock();
    final currentTerm = AcademicTerm.fromInstant(currentNow);
    final cached = _termCatalogCache;
    if (cached != null && cached.currentTerm == currentTerm) {
      return cached;
    }
    return _termCatalogCache = CourseTermCatalog.build(
      courses: courses,
      assignments: [..._assignments, ..._hiddenAssignments],
      notices: _courseNotices.items,
      preferences: _courseTermPreferences,
      now: currentNow,
      coursework: _courseworkState,
      unfollowedCourseKeys: _unfollowed,
      hiddenAssignmentIds: {for (final a in _hiddenAssignments) a.id},
      changes: changes,
    );
  }

  bool isCourseActive(String key) =>
      follows(key) && termCatalog.isActiveOrRecalled(key);

  Future<bool> _mutateCourseTermPreferences(
    _SessionSnapshot snap,
    CourseTermPreferences Function(CourseTermPreferences current) transform, {
    required String leaseWarning,
  }) async {
    var saved = false;
    await _run(() async {
      if (!_isSessionCurrent(snap)) return;
      final next = transform(_courseTermPreferences);
      if (next == _courseTermPreferences) {
        saved = true;
        return;
      }
      await _markReminderMutationPending();
      if (!_isSessionCurrent(snap)) return;
      try {
        await _runScopedWrite(
          snap,
          (prefs) => repository.writeCourseTermPreferencesInPrefs(prefs, next),
        );
      } on StaleSessionWriteException {
        return;
      } on LocalStorageLeaseReleaseException {
        if (snap.generation == _generation &&
            !_recoveryWarnings.contains(leaseWarning)) {
          _recoveryWarnings.add(leaseWarning);
        }
      } catch (_) {
        return;
      }
      if (!_isSessionCurrent(snap)) return;
      _courseTermPreferences = next;
      _invalidateHomeDisplayIndex();
      saved = true;
      await _afterAssignmentsChanged(
        updateSummary: true,
        updateManual: false,
        updateWidget: true,
      );
      if (_isSessionCurrent(snap)) notifyListeners();
    });
    return saved;
  }

  Future<bool> setCourseManualTerm(String courseKey, AcademicTerm? term) async {
    final snap = _captureSession();
    if (!snap.authenticated || snap.account == null) return false;
    return _mutateCourseTermPreferences(
      snap,
      (current) => current.withManualTerm(courseKey, term?.key),
      leaseWarning: '学期归属已保存，本机写入通道释放未确认，请稍后重试其他写入',
    );
  }

  Future<bool> setCourseArchiveMode(
    String courseKey,
    CourseArchiveMode mode,
  ) async {
    final snap = _captureSession();
    if (!snap.authenticated || snap.account == null) return false;
    return _mutateCourseTermPreferences(
      snap,
      (current) => current.withArchiveMode(courseKey, mode),
      leaseWarning: '课程归档状态已保存，本机写入通道释放未确认，请稍后重试其他写入',
    );
  }

  Future<bool> setCourseBlockMode(
    String courseKey,
    CourseBlockMode mode,
  ) async {
    final snap = _captureSession();
    if (!snap.authenticated || snap.account == null) return false;
    final saved = await _mutateCourseTermPreferences(
      snap,
      (current) => current.withBlockMode(courseKey, mode),
      leaseWarning: '课程屏蔽状态已保存，本机写入通道释放未确认，请稍后重试其他写入',
    );
    if (saved &&
        _isSessionCurrent(snap) &&
        homeFilters.courseKey == courseKey &&
        termCatalog.isBlocked(courseKey)) {
      final cleared = HomeFilters(
        query: homeFilters.query,
        courseKey: null,
        deadline: homeFilters.deadline,
        sortOrder: homeFilters.sortOrder,
        type: homeFilters.type,
      );
      await saveHomeFilters(cleared, snap.generation);
    }
    return saved;
  }

  Future<bool> dismissCourseRecall(String courseKey) async {
    final snap = _captureSession();
    if (!snap.authenticated || snap.account == null) return false;
    return _mutateCourseTermPreferences(
      snap,
      (current) {
        final cursor = termCatalog.entryFor(courseKey)?.latestRecallEventUtc ??
            _clock().toUtc();
        return current
            .withArchiveMode(courseKey, CourseArchiveMode.auto)
            .withDismissedRecallCursor(courseKey, cursor);
      },
      leaseWarning: '召回忽略状态已保存，本机写入通道释放未确认，请稍后重试其他写入',
    );
  }

  Future<bool> archivePastCourses() async {
    final snap = _captureSession();
    if (!snap.authenticated || snap.account == null) return false;
    return _mutateCourseTermPreferences(
      snap,
      (current) =>
          current.withBatchArchive(termCatalog.archivablePastCourseKeys),
      leaseWarning: '往期课程已批量归档，本机写入通道释放未确认，请稍后重试其他写入',
    );
  }

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
                assignment.courseKey == null ||
                isCourseActive(assignment.courseKey!))
            .toList(),
        hiddenIds:
            _hiddenAssignments.map((assignment) => assignment.id).toSet(),
      ));

  List<Assignment> get courseAssignments =>
      _courseworkSourcesCache ??= List.unmodifiable([
        for (final group in courseworkGroups)
          if (!group.hidden) ...group.sources,
      ]);

  /// Original primary records for statistics across followed courses.
  ///
  /// Uses all non-hidden followed records so past/archived terms remain
  /// inspectable via [statsAssignmentsForScope].
  List<Assignment> get statsAssignments =>
      _statsAssignmentsCache ??= List.unmodifiable([
        for (final group in localRecordGroups)
          if (!group.hidden &&
              group.primary.isInAssignmentScope &&
              (group.primary.courseKey == null ||
                  (follows(group.primary.courseKey!) &&
                      !termCatalog.isBlocked(group.primary.courseKey!))))
            group.primary,
      ]);

  List<Assignment> statsAssignmentsForScope(
    CourseTermScope scope, {
    DateTime? now,
  }) {
    final catalog = now == null
        ? termCatalog
        : CourseTermCatalog.build(
            courses: courses,
            assignments: [..._assignments, ..._hiddenAssignments],
            notices: _courseNotices.items,
            preferences: _courseTermPreferences,
            now: now,
            coursework: _courseworkState,
            unfollowedCourseKeys: _unfollowed,
            hiddenAssignmentIds: {for (final a in _hiddenAssignments) a.id},
            changes: changes,
          );
    return List.unmodifiable([
      for (final a in statsAssignments)
        if (catalog.matchesAssignmentInStatsScope(a, scope)) a,
    ]);
  }

  List<Assignment> homeCatalogAssignmentsWithSelectedCourse(
    String? selectedCourseKey,
  ) {
    final activeCatalog = homeCatalogAssignments;
    if (selectedCourseKey == null ||
        !follows(selectedCourseKey) ||
        termCatalog.isBlocked(selectedCourseKey) ||
        termCatalog.isActiveOrRecalled(selectedCourseKey)) {
      return activeCatalog;
    }
    final activeIds = {for (final a in activeCatalog) a.id};
    final extra = <Assignment>[];
    for (final group in localRecordGroups) {
      if (group.hidden) continue;
      if (group.primary.courseKey != selectedCourseKey) continue;
      for (final source in group.sources) {
        if (!activeIds.contains(source.id)) {
          extra.add(source);
        }
      }
    }
    if (extra.isEmpty) return activeCatalog;
    return List<Assignment>.unmodifiable([...activeCatalog, ...extra]);
  }

  Set<String> _effectiveHiddenAssignmentIds() => {
        for (final item in _hiddenAssignments) item.id,
        for (final group in hiddenCourseworkGroups)
          for (final source in group.sources) source.id,
      };

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
  Future<void> saveNotificationDetails(bool value) {
    final snap = _captureSession();
    return _run(() async {
      if (!_isSessionCurrent(snap)) return;
      await _markReminderMutationPending();
      if (!_isSessionCurrent(snap)) return;
      if (!value) {
        try {
          await _cancelPrivateNotifications();
        } catch (_) {
          throw StateError('旧提醒未能清理，通知详情尚未关闭，请在提醒体检重试');
        }
        if (!_isSessionCurrent(snap)) return;
      }
      try {
        await _runScopedWrite(snap, (prefs) async {
          if (value) {
            await prefs.remove(_privacyVerifiedHiddenKey);
          }
          if (!await prefs.setBool('notification_details_v1', value)) {
            throw StateError('通知隐私设置未能保存');
          }
          if (!value) {
            await _writeBoolPreferenceAndVerify(
                prefs, _privacyVerifiedHiddenKey, true);
          }
        });
      } on StaleSessionWriteException {
        return;
      }
      if (!_isSessionCurrent(snap)) return;
      notificationService.showDetails = value;
      _privacyCleanupPending = false;
      await _reconcileBackgroundControls();
      if (!_isSessionCurrent(snap)) return;
      await _afterAssignmentsChanged();
      if (!_isSessionCurrent(snap)) return;
      if (_serviceWarnings.isNotEmpty) {
        throw StateError('隐私设置已保存，部分旧提醒未更新，请在提醒体检重试');
      }
    });
  }

  DisplayPreferences display = const DisplayPreferences();
  Future<void>? _displayWrites;

  Future<String?> saveDisplay(DisplayPreferences next) {
    final snap = _captureSession();
    display = next;
    // Serialize preference writes independently of coursework operations.
    final write = (_displayWrites ?? Future<void>.value()).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final previous =
          DisplayPreferences.decode(prefs.getString('display_preferences_v1'));
      if (!await prefs.setString('display_preferences_v1', next.encode())) {
        throw StateError('显示设置未能保存');
      }
      return previous.widgetRange != next.widgetRange;
    });
    _displayWrites = write.then<void>((_) {}, onError: (Object _) {});
    notifyListeners();
    return _finishDisplaySave(next, write, snap);
  }

  Future<String?> _finishDisplaySave(
    DisplayPreferences next,
    Future<bool> write,
    _SessionSnapshot snap,
  ) async {
    final bool rangeChanged;
    try {
      rangeChanged = await write;
    } catch (_) {
      return '显示设置未能保存，当前调整仅在本次使用时生效';
    }
    if (!rangeChanged ||
        !_isSessionCurrent(snap) ||
        display.widgetRange != next.widgetRange) {
      return null;
    }
    final effectiveCoursework = snap.authenticated
        ? _courseworkState
        : const LocalCourseworkState.empty();
    final now = _clock();
    final activeCatalog = snap.authenticated ? termCatalog : null;
    final items = next.forWidget(
      snap.authenticated ? courseAssignments : <Assignment>[],
      now,
      coursework: effectiveCoursework,
    );
    try {
      await _runScopedWrite(
        snap,
        (_) {
          widgetSnapshotService.clock = _clock;
          widgetSnapshotService.courseworkState = effectiveCoursework;
          widgetSnapshotService.termCatalog = activeCatalog;
          return widgetSnapshotService.saveAssignmentsForContext(
            items,
            authenticated: snap.authenticated,
            range: next.widgetRange,
          );
        },
      );
      return null;
    } on StaleSessionWriteException {
      return null;
    } catch (_) {
      return '显示设置已保存，小组件更新失败，请稍后刷新';
    }
  }

  List<Assignment> get visibleAssignments => AssignmentQuery.currentDisplay(
        courseAssignments,
        _clock(),
        coursework: _authenticated
            ? _courseworkState
            : const LocalCourseworkState.empty(),
      );
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
      homeCatalogAssignments,
      DateTime.now(),
      index: homeDisplayIndex,
      coursework: _authenticated
          ? _courseworkState
          : const LocalCourseworkState.empty(),
    );
  }

  /// Complete scoped source catalog for the home list, including submitted
  /// homework and ended exams. It retains notice sources for display-time
  /// ordering and stays consistent while a sync preview is published;
  /// current-todo callers continue to use [homeDisplayAssignments].
  List<Assignment> get homeCatalogAssignments {
    if (_homeCatalogCache != null) return _homeCatalogCache!;
    if (_homePreviewAssignments.isEmpty) {
      final sources = courseAssignments;
      // The store's own snapshot is already scoped and immutable. Overrides
      // keep the same filtering and snapshot semantics as before.
      final next = identical(sources, _courseworkSourcesCache)
          ? sources
          : List<Assignment>.unmodifiable(AssignmentQuery.scope(sources, {}));
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
  Set<String>? _persistedIdsCache;
  Set<String>? _previewIdsCache;

  AssignmentDisplayIndex get homeDisplayIndex =>
      _homeDisplayIndex ??= AssignmentDisplayIndex.from(homeCatalogAssignments);

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

  bool isHomeAssignmentPreviewOnly(String assignmentId) {
    if (_homePreviewAssignments.isEmpty) return false;
    final previewIds =
        _previewIdsCache ??= {for (final a in _homePreviewAssignments) a.id};
    if (!previewIds.contains(assignmentId)) return false;
    final persistedIds =
        _persistedIdsCache ??= {for (final a in _assignments) a.id};
    return !persistedIds.contains(assignmentId);
  }

  List<Assignment> _catalogAssignmentsFrom(Iterable<Assignment> records) =>
      AssignmentQuery.scope(records.toList(), {})
          .where((assignment) =>
              assignment.courseKey == null ||
              isCourseActive(assignment.courseKey!))
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
      _publishHomeProgress(generation, progress);
      return;
    }
    _homeProgressTimer ??= Timer(const Duration(milliseconds: 100), () {
      _homeProgressTimer = null;
      if (generation != _generation || !_authenticated || _disposed) return;
      final latest = _queuedHomeProgress;
      if (latest != null) _publishHomeProgress(generation, latest);
    });
  }

  void _publishHomeProgress(int generation, AssignmentSyncProgress progress) {
    if (_disposed || !_authenticated || generation != _generation) return;
    _homeProgressTimer?.cancel();
    _homeProgressTimer = null;
    _queuedHomeProgress = null;
    _homeSyncProgress = progress;
    _homePreviewAssignments = List.of(progress.assignments);
    _homePendingDeadlineIds = Set.of(progress.pendingDetailIds);
    _invalidateHomeDisplayIndex();
    notifyListeners();
  }

  void _markHomePreviewSaving(int generation) {
    if (_disposed || !_authenticated || generation != _generation) return;
    // A retraction may still be waiting in the 100ms merge queue. Saving must
    // publish the newest snapshot, otherwise the failed course's temporary
    // rows reappear until the whole sync clears the preview.
    final progress = _queuedHomeProgress ?? _homeSyncProgress;
    if (progress == null) return;
    _publishHomeProgress(
      generation,
      AssignmentSyncProgress(
        stage: AssignmentSyncStage.saving,
        assignments: progress.assignments,
        pendingDetailIds: const {},
        resolvedCount: progress.resolvedCount,
        attemptedCount: progress.attemptedCount,
        unconfirmedCount: progress.unconfirmedCount,
        workListFailureCount: progress.workListFailureCount,
      ),
    );
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

  Future<void> followCourse(String key, bool followed) {
    final snap = _captureSession();
    return _run(() async {
      if (!_isSessionCurrent(snap)) return;
      await _markReminderMutationPending();
      if (!_isSessionCurrent(snap)) return;
      final next = {..._unfollowed};
      if (followed) {
        next.remove(key);
      } else {
        next.add(key);
      }
      try {
        await _runScopedWrite(snap, (prefs) async {
          if (!await prefs.setStringList('unfollowed_courses', next.toList())) {
            throw StateError('课程关注设置未能保存，请重试');
          }
        });
      } on StaleSessionWriteException {
        return;
      }
      if (!_isSessionCurrent(snap)) return;
      _unfollowed
        ..clear()
        ..addAll(next);
      _invalidateHomeDisplayIndex();
      await _afterAssignmentsChanged();
    });
  }

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
    _serviceWarnings.clear();
    _privacyWarnings.clear();
    _deadlineWarnings.clear();
    _summaryWarnings.clear();
    _manualWarnings.clear();
    _widgetWarnings.clear();
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
      debugPrint('[AssignmentStore] restoreIdentity: ${error.runtimeType}');
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
      debugPrint('[AssignmentStore] restoreAccount: ${error.runtimeType}');
      _authenticated = false;
      _assignments.clear();
      _hiddenAssignments = [];
      _recoveryWarnings.add('账号本机记录暂时无法恢复，请重新登录后重试');
      widgetSnapshotService.clock = _clock;
      widgetSnapshotService.courseworkState =
          const LocalCourseworkState.empty();
      widgetSnapshotService.termCatalog = null;
      if (_manageBackgroundSchedule) {
        try {
          await widgetSnapshotService.saveAssignmentsForContext(
            const [],
            authenticated: false,
            range: display.widgetRange,
          );
        } catch (widgetError) {
          debugPrint(
              '[WidgetSnapshot] restore_clear: ${widgetError.runtimeType}');
        }
      }
    }
    try {
      _chaoxingDisplayName = await sessionStore.readChaoxingDisplayName();
      _chaoxingAvatarUrl = await sessionStore.readChaoxingAvatarUrl();
      _needsProfileRecovery = _authenticated &&
          (_chaoxingDisplayName == null || _chaoxingAvatarUrl == null);
    } catch (error) {
      debugPrint('[AssignmentStore] restoreProfile: ${error.runtimeType}');
      _recoveryWarnings.add('个人资料暂时无法恢复，不影响重新登录和读取作业');
    }
    await _reconcileBackgroundControls();
    await _maybeMigrateLegacyAssignmentSchedules();
    await _maybeMigrateLegacyManualSchedules();
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
    _acknowledgedDeadlineChangeIds = <String>{};
    _assignments.clear();
    _hiddenAssignments = [];
    _courses = [];
    _unfollowed.clear();
    _pinned = const PinnedAssignments.empty();
    _courseworkState = const LocalCourseworkState.empty();
    _courseTermPreferences = const CourseTermPreferences.empty();
    _historicalSweepState = const HistoricalSweepState.empty();
    _lastRequestedSyncScope = AssignmentSyncScope.current;
    _lastTargetedCourseKeys = const {};
    _lastSyncSourceResults = const [];
    _termCatalogCache = null;
    _visitedAssignment = null;
    _activeVisitTicket = null;
    _visitLeftApp = false;
    _pendingReturnConfirmation = null;
    _pinsNeedSave = false;
    _journalRestoreFailed = false;
    _reminderOffsetsMinutes = ReminderRuleStore.defaultOffsetsMinutes;
    _allowUrgentDeadlineNightBreakthrough = false;
    _deadlineChannelId = LocalNotificationService.assignmentV2Channel;
    _migratedDeadlineChannelToV2ThisRestore = false;
    notificationService.activeDeadlineChannelId =
        LocalNotificationService.assignmentV2Channel;
    _lastSyncAt = null;
    _lastSyncAttemptAt = null;
    _serverBackoffUntil = null;
    syncReport = const SyncReport();
    var stageNumber = 0;
    Future<void> stage(String name, Future<void> Function() action) async {
      stageNumber++;
      try {
        await action();
      } catch (error) {
        debugPrint(
            '[AssignmentStore] restoreStage$stageNumber: ${error.runtimeType}');
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
    await stage('置顶课业', () async {
      final account = _account;
      if (_manageBackgroundSchedule && _authenticated && account != null) {
        _pinned = await repository.loadPinnedAssignments(account);
      }
    });
    await stage('个人课业状态', () async {
      final account = _account;
      if (_authenticated && account != null) {
        _courseworkState = await repository.loadCourseworkState(account);
      }
    });
    await stage('课程学期设置', () async {
      final account = _account;
      if (_authenticated && account != null) {
        _courseTermPreferences =
            await repository.loadCourseTermPreferences(account);
      }
    });
    await stage('往期巡检状态', () async {
      final account = _account;
      if (_authenticated && account != null) {
        _historicalSweepState =
            await repository.loadHistoricalSweepState(account);
      }
    });
    await stage('提醒设置', () async {
      _reminderOffsetsMinutes = await reminderRuleStore.loadOffsetsMinutes();
      final account = _account;
      _allowUrgentDeadlineNightBreakthrough =
          (_authenticated && account != null)
              ? await repository.loadAllowUrgentNightBreakthrough(account)
              : false;
      final savedDeadlineChannel = (_authenticated && account != null)
          ? await repository.loadDeadlineChannelId(account)
          : null;
      if (_authenticated && account != null) {
        final prefs = await SharedPreferences.getInstance();
        final alreadyAutoMigrated =
            prefs.getBool(_deadlineChannelV2AutoMigratedKey) ?? false;
        if (savedDeadlineChannel ==
                LocalNotificationService.assignmentChannel &&
            !alreadyAutoMigrated) {
          final snap = _captureSession();
          try {
            await _runScopedWrite(
              snap,
              (scopedPrefs) async {
                await repository.writeDeadlineChannelIdInPrefs(
                  scopedPrefs,
                  LocalNotificationService.assignmentV2Channel,
                );
                await scopedPrefs.setBool(
                  _deadlineChannelV2AutoMigratedKey,
                  true,
                );
              },
            );
            _migratedDeadlineChannelToV2ThisRestore = true;
          } on StaleSessionWriteException {
            // Session changed mid-restore; leave persisted state untouched.
          } catch (_) {
            // Keep running restore using the upgraded in-memory default below.
          }
          _deadlineChannelId = LocalNotificationService.assignmentV2Channel;
        } else {
          _deadlineChannelId =
              await notificationService.resolveDefaultDeadlineChannel(
            storedChannelId: savedDeadlineChannel,
          );
          if (_deadlineChannelId ==
                  LocalNotificationService.assignmentV2Channel &&
              !alreadyAutoMigrated) {
            await prefs.setBool(_deadlineChannelV2AutoMigratedKey, true);
          }
        }
      } else {
        _deadlineChannelId = LocalNotificationService.assignmentV2Channel;
      }
      notificationService.activeDeadlineChannelId = _authenticated
          ? _deadlineChannelId
          : LocalNotificationService.assignmentV2Channel;
    });
    await stage('自动同步设置', () async {
      final snap = _captureSession();
      _backgroundCheckSettings = await _runScopedWrite(
        snap,
        (prefs) => backgroundCheckSettingsStore.loadAndMigrate(prefs: prefs),
      );
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
        } on FormatException catch (error) {
          debugPrint(
              '[AssignmentStore] restoreSyncReportJson: ${error.runtimeType}');
          reportDamaged = true;
        }
      }
      if (reportJson != null) {
        try {
          SyncReport.fromJson(reportJson);
        } on FormatException catch (error) {
          debugPrint(
              '[AssignmentStore] restoreSyncReport: ${error.runtimeType}');
          reportJson = null;
          reportDamaged = true;
        } on TypeError catch (error) {
          debugPrint(
              '[AssignmentStore] restoreSyncReport: ${error.runtimeType}');
          reportJson = null;
          reportDamaged = true;
        } on ArgumentError catch (error) {
          debugPrint(
              '[AssignmentStore] restoreSyncReport: ${error.runtimeType}');
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
      _invalidatePinnableKeys();
    });
    await stage('课程通知', () async {
      _courseNotices = await repository.loadCourseNotices();
    });
    await stage('章节进度', () async {
      _courseChapters = await repository.loadCourseChapters();
    });
    await stage('作业记录', () async {
      try {
        await _reloadJournal();
        _journalRestoreFailed = false;
      } catch (_) {
        _journalRestoreFailed = true;
        rethrow;
      }
      _hadCacheBeforeLastSync =
          _assignments.isNotEmpty || _hiddenAssignments.isNotEmpty;
    });
    await stage('作业变化', () async {
      changes = await changeLog.load();
      _termCatalogCache = null;
    });
    await stage('时间变更确认状态', () async {
      final account = _account;
      if (_authenticated && account != null) {
        _acknowledgedDeadlineChangeIds =
            await repository.loadAcknowledgedDeadlineChangeIds(account);
      }
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
    cancelSynchronization();
    _visitedAssignment = null;
    _activeVisitTicket = null;
    _visitLeftApp = false;
    _pendingReturnConfirmation = null;
    returnCheckMessage = null;
    var loginSucceeded = false;
    chaoxingClient.deferProfile = true;
    try {
      await _run(() async {
        if (generation != _generation || _disposed) return;
        final result = await chaoxingClient.login(
          account: account,
          password: password,
        );
        if (generation != _generation || _disposed) {
          chaoxingClient.clearSession();
          return;
        }
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
        String? oldPassword;
        if (oldAccount != null) {
          try {
            oldPassword = await sessionStore.readChaoxingPassword();
          } catch (_) {
            /* A damaged old credential must not block reauthentication. */
          }
          if (generation != _generation || _disposed) {
            chaoxingClient.clearSession();
            return;
          }
        }
        final oldName = _chaoxingDisplayName, oldAvatar = _chaoxingAvatarUrl;
        var nativeSwitched = false;
        var repositoryActivated = false;
        try {
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
            if (generation != _generation || _disposed) {
              throw const _LoginInterruptedException();
            }
          }
          if (oldAccount?.trim() != normalizedAccount) {
            // Full privacy cleanup also removes delivered notifications that
            // are no longer pending and have no v2 active-ID manifest.
            await _cancelPrivateNotifications();
            if (generation != _generation || _disposed) {
              throw const _LoginInterruptedException();
            }
            widgetSnapshotService.clock = _clock;
            widgetSnapshotService.courseworkState =
                const LocalCourseworkState.empty();
            widgetSnapshotService.termCatalog = null;
            await widgetSnapshotService.saveAssignmentsForContext(
              const [],
              authenticated: false,
              range: display.widgetRange,
            );
            if (generation != _generation || _disposed) {
              throw const _LoginInterruptedException();
            }
          }
          await repository.activateAccount(normalizedAccount,
              previousAccount: oldAccount);
          repositoryActivated = true;
          if (generation != _generation || _disposed) {
            throw const _LoginInterruptedException();
          }
          await sessionStore.saveChaoxingAccount(
            account: normalizedAccount,
            password: password,
            displayName: result.displayName,
            avatarUrl: result.avatarUrl,
          );
        } catch (error) {
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
            if (repositoryActivated) {
              if (oldAccount != null) {
                await repository.activateAccount(oldAccount);
              } else {
                await repository.clear();
              }
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
            if (!_disposed &&
                _nativeReminderAvailable &&
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
            _pinned = const PinnedAssignments.empty();
            _courseworkState = const LocalCourseworkState.empty();
            _courseTermPreferences = const CourseTermPreferences.empty();
            _historicalSweepState = const HistoricalSweepState.empty();
            _termCatalogCache = null;
            _acknowledgedDeadlineChangeIds = <String>{};
            _pinsNeedSave = false;
            _courseNotices = CourseNoticeCollection();
            _courseChapters = CourseChapterCatalog();
            _invalidateHomeDisplayIndex();
            try {
              await sessionStore.clear();
            } catch (_) {/* Already failed closed. */}
            if (!_disposed) await _afterAssignmentsChanged();
          }
          if (error is _LoginInterruptedException) return;
          rethrow;
        }
        // The account and credentials are committed at this point.
        if (oldAccount != null && oldAccount.trim() != normalizedAccount) {
          await personalFileService.releaseAll();
          try {
            await manualAttachmentService.deleteAllAttachments();
          } catch (error) {
            debugPrint(
                '[ManualAttachment] switch_cleanup: ${error.runtimeType}');
          }
        }
        if (generation != _generation || _disposed) {
          chaoxingClient.clearSession();
          return;
        }
        if (oldAccount?.trim() != normalizedAccount) {
          await sessionStore.clearWebSession();
          if (generation != _generation || _disposed) {
            chaoxingClient.clearSession();
            return;
          }
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
            if (generation != _generation || _disposed) {
              chaoxingClient.clearSession();
              return;
            }
          }
          await _prepareReminderHistorySession();
          if (generation != _generation || _disposed) {
            chaoxingClient.clearSession();
            return;
          }
        }
        await _restoreAccountData();
        if (generation != _generation || _disposed) {
          chaoxingClient.clearSession();
          return;
        }
        if (historyRetireWarning != null) {
          _recoveryWarnings.add(historyRetireWarning);
        }
        _chaoxingDisplayName = result.displayName;
        _chaoxingAvatarUrl = result.avatarUrl;
        _agreementAccepted = true;
        _authenticated = true;
        loginSucceeded = true;
        await _reconcileBackgroundControls();
        await _maybeMigrateLegacyManualSchedules();
      });
    } finally {
      _loginRunning = false;
    }
    if (loginSucceeded &&
        _authenticated &&
        !_disposed &&
        generation == _generation) {
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
    _syncInFlight = null;
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
  }) async {
    await _syncForTrigger(
      trigger,
      skipTaskEngineProbe: skipTaskEngineProbe,
      scope: scope,
      targetedCourseKeys: targetedCourseKeys,
    );
  }

  Future<String?> _syncForTrigger(
    BackgroundSyncTrigger trigger, {
    bool skipTaskEngineProbe = false,
    AssignmentSyncScope? scope,
    Set<String>? targetedCourseKeys,
  }) {
    if (!_authenticated) return Future.value();
    final existing = _syncInFlight;
    if (existing != null) return existing;
    late final Future<String?> currentFuture;
    currentFuture = _performCoordinatedSync(
      trigger,
      skipTaskEngineProbe: skipTaskEngineProbe,
      scope: scope,
      targetedCourseKeys: targetedCourseKeys,
    ).whenComplete(() {
      if (identical(_syncInFlight, currentFuture)) {
        _syncInFlight = null;
      }
    });
    _syncInFlight = currentFuture;
    return currentFuture;
  }

  Future<String?> _performCoordinatedSync(
    BackgroundSyncTrigger trigger, {
    bool skipTaskEngineProbe = false,
    AssignmentSyncScope? scope,
    Set<String>? targetedCourseKeys,
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
      if (generation != _generation ||
          _disposed ||
          _syncCancelled ||
          operation != _syncOperation) {
        return null;
      }
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
        if (!_authenticated ||
            generation != _generation ||
            _disposed ||
            _syncCancelled ||
            operation != _syncOperation) {
          return;
        }
        if (_nativeReminderAvailable &&
            accountHash != null &&
            !await backgroundReminderGateway.isSessionCurrent(
              accountHash,
              sessionEpoch,
            )) {
          return;
        }
        if (!_authenticated ||
            generation != _generation ||
            _disposed ||
            _syncCancelled ||
            operation != _syncOperation) {
          return;
        }
        await _syncAssignmentsBody(
          trigger,
          operation: operation,
          skipTaskEngineProbe: skipTaskEngineProbe,
          scope: scope,
          targetedCourseKeys: targetedCourseKeys,
        );
        if (trigger == BackgroundSyncTrigger.daytime) {
          await _maybeRunHistoricalSweepAfterDaytimeSync(
            session: _captureSession(syncOperation: operation),
          );
        }
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
    bool allowSourceBaselineUpdate = true,
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
    _journalRestoreFailed = false;
    _invalidateHomeDisplayIndex();
    await _reconcileCourseworkState();
    if (generation != _generation || _disposed) return;
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
      } on StaleSessionWriteException {
        return;
      } catch (error) {
        _recoveryWarnings.add('已从作业仓库恢复同步时间，但同步报告未能重新保存：$error');
      }
    }
    if (generation != _generation || _disposed) return;
    await _afterAssignmentsChanged(
      completeSync: completeSync,
      detectNewAssignments: detectNewAssignments,
      syncCompleted: syncCompleted,
      allowSourceBaselineUpdate: allowSourceBaselineUpdate,
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
    final account = _account;
    final accountHash = _accountHash;
    if (!_authenticated || account == null || accountHash == null) {
      return false;
    }
    var saved = false;
    await _run(() async {
      if (accountEpoch != epoch ||
          _account != account ||
          _accountHash != accountHash ||
          !_authenticated) {
        return;
      }
      await _markReminderMutationPending();
      if (accountEpoch != epoch ||
          _account != account ||
          _accountHash != accountHash ||
          !_authenticated) {
        return;
      }
      try {
        await repository.updateCompletionMany(
          ids,
          hidden,
          canCommit: () async {
            if (accountEpoch != epoch ||
                _account != account ||
                !_authenticated) {
              return false;
            }
            if (!_nativeReminderAvailable) return true;
            return backgroundReminderGateway.isSessionCurrent(
              accountHash,
              _nativeSessionEpoch,
            );
          },
        );
      } on StateError {
        if (accountEpoch != epoch) return;
        rethrow;
      }
      if (accountEpoch != epoch ||
          _account != account ||
          _accountHash != accountHash ||
          !_authenticated) {
        return;
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
    final snap = _captureSession();
    var saved = false;
    await _run(() async {
      if (!_isSessionCurrent(snap)) return;
      await _markReminderMutationPending();
      if (!_isSessionCurrent(snap)) return;
      final List<int> normalized;
      try {
        normalized = await _runScopedWrite(
          snap,
          (_) => reminderRuleStore.saveOffsetsMinutes(offsetsMinutes),
        );
      } on StaleSessionWriteException {
        return;
      }
      if (!_isSessionCurrent(snap)) return;
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

  Future<bool> _saveBackgroundCheckSettings(
    BackgroundCheckSettings Function(BackgroundCheckSettings current) transform,
  ) async {
    final snap = _captureSession();
    var saved = false;
    await _run(() async {
      if (!_isSessionCurrent(snap)) return;
      final next = transform(_backgroundCheckSettings);
      try {
        await _runScopedWrite(
          snap,
          (prefs) => backgroundCheckSettingsStore.save(next, prefs: prefs),
        );
      } on StaleSessionWriteException {
        return;
      }
      if (!_isSessionCurrent(snap)) return;
      _backgroundCheckSettings = next;
      if (!await _reconcileBackgroundControls()) {
        throw StateError('设置已保存，但后台提醒设置未确认，请重试');
      }
      if (!_isSessionCurrent(snap)) return;
      saved = true;
    });
    return saved;
  }

  Future<bool> saveBackgroundCheckEnabled(bool enabled) =>
      _saveBackgroundCheckSettings(
        (current) => current.copyWith(enabled: enabled),
      );

  Future<bool> saveBackgroundCheckIntervalMinutes(int minutes) =>
      _saveBackgroundCheckSettings(
        (current) => current.copyWith(
          enabled: true,
          intervalMinutes: DaytimeCheckPolicy.normalizeIntervalMinutes(minutes),
        ),
      );

  Future<bool> saveNotificationListenerEnabled(bool enabled) =>
      _saveBackgroundCheckSettings(
        (current) => current.copyWith(notificationListenerEnabled: enabled),
      );

  Future<bool> saveNewAssignmentReminderEnabled(bool enabled) =>
      _saveBackgroundCheckSettings(
        (current) => current.copyWith(newAssignmentReminderEnabled: enabled),
      );

  Future<bool> saveAllowUrgentDeadlineNightBreakthrough(bool enabled) async {
    final snap = _captureSession();
    var saved = false;
    await _run(() async {
      if (!_isSessionCurrent(snap)) return;
      await _markReminderMutationPending();
      if (!_isSessionCurrent(snap)) return;
      try {
        await _runScopedWrite(
          snap,
          (prefs) => repository.writeAllowUrgentNightBreakthroughInPrefs(
            prefs,
            enabled,
          ),
        );
      } on StaleSessionWriteException {
        return;
      }
      if (!_isSessionCurrent(snap)) return;
      _allowUrgentDeadlineNightBreakthrough = enabled;
      notificationService.allowUrgentNightBreakthrough =
          snap.authenticated && enabled;
      saved = true;
      await _afterAssignmentsChanged(updateSummary: false);
    });
    return saved;
  }

  Future<bool> saveDeadlineChannelId(String channelId) async {
    final normalized =
        LocalAssignmentRepository.normalizeDeadlineChannelId(channelId);
    if (normalized == null) {
      _error = '未知的截止提醒通知渠道';
      notifyListeners();
      return false;
    }
    final snap = _captureSession();
    var saved = false;
    await _run(() async {
      if (!_isSessionCurrent(snap)) return;
      await _markReminderMutationPending();
      if (!_isSessionCurrent(snap)) return;
      try {
        await _runScopedWrite(
          snap,
          (prefs) async {
            await repository.writeDeadlineChannelIdInPrefs(
              prefs,
              normalized,
            );
            await prefs.setBool(_deadlineChannelV2AutoMigratedKey, true);
          },
        );
      } on StaleSessionWriteException {
        return;
      }
      if (!_isSessionCurrent(snap)) return;
      _deadlineChannelId = normalized;
      notificationService.activeDeadlineChannelId = snap.authenticated
          ? normalized
          : LocalNotificationService.assignmentV2Channel;
      saved = true;
      await _afterAssignmentsChanged(updateSummary: false);
    });
    return saved;
  }

  Future<TestDeadlineNotificationOutcome> sendTestDeadlineNotification({
    int delayMillis = 3000,
  }) async {
    final now = _clock();
    if (DeadlineQuietHoursPolicy.isQuiet(now)) {
      final retryAt = DeadlineQuietHoursPolicy.nextQuietEnd(now);
      final hm =
          '${retryAt.hour.toString().padLeft(2, '0')}:${retryAt.minute.toString().padLeft(2, '0')}';
      return TestDeadlineNotificationOutcome(
        status: TestDeadlineNotificationStatus.quietHours,
        channelId: activeDeadlineChannelId,
        warning: '当前处于夜间静音时段（23:30–07:30），测试提醒不会穿透静音；请在 $hm 后重试。',
        retryAfterAt: retryAt,
      );
    }
    final targetChannel = _authenticated
        ? _deadlineChannelId
        : LocalNotificationService.assignmentV2Channel;
    notificationService.activeDeadlineChannelId = targetChannel;
    if (_nativeReminderAvailable) {
      try {
        return await backgroundReminderGateway.sendTestDeadlineNotification(
          accountHash: _authenticated ? _accountHash : null,
          channelId: targetChannel,
          delayMillis: delayMillis,
        );
      } catch (error) {
        return TestDeadlineNotificationOutcome(
          status: TestDeadlineNotificationStatus.blocked,
          channelId: targetChannel,
          warning: '发送测试提醒失败：$error',
        );
      }
    }
    try {
      final ok = await notificationService.showTestNotification();
      return ok
          ? TestDeadlineNotificationOutcome(
              status: TestDeadlineNotificationStatus.posted,
              channelId: targetChannel,
            )
          : TestDeadlineNotificationOutcome(
              status: TestDeadlineNotificationStatus.blocked,
              channelId: targetChannel,
              warning:
                  notificationService.lastWarning ?? '未能请求测试通知，请检查通知权限与渠道。',
            );
    } catch (error) {
      return TestDeadlineNotificationOutcome(
        status: TestDeadlineNotificationStatus.blocked,
        channelId: targetChannel,
        warning: '发送测试提醒失败：$error',
      );
    }
  }

  /// Reloads durable sync timestamps and journal records if a headless
  /// background check persisted newer state while this foreground store was idle.
  Future<bool> reconcileExternalSyncState() async {
    final account = _account;
    final generation = _generation;
    if (!_authenticated ||
        account == null ||
        _loading ||
        _autoSyncRunning ||
        _disposed) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (!_authenticated ||
        _account != account ||
        _generation != generation ||
        _loading ||
        _disposed) {
      return false;
    }
    if (prefs.containsKey('journal_account_switch')) return false;
    final owner = prefs.getString('journal_account_owner');
    if (owner != null && owner != AccountIdentity.hash(account)) {
      return false;
    }
    final durableAttempt =
        DateTime.tryParse(prefs.getString('sync_attempt_at') ?? '')?.toLocal();
    final durableData =
        DateTime.tryParse(prefs.getString('sync_data_at') ?? '')?.toLocal();
    final attemptAdvanced = durableAttempt != null &&
        (_lastSyncAttemptAt == null ||
            durableAttempt.isAfter(_lastSyncAttemptAt!));
    final dataAdvanced = durableData != null &&
        (syncReport.lastDataSuccessAt == null ||
            durableData.isAfter(syncReport.lastDataSuccessAt!));
    if (!attemptAdvanced && !dataAdvanced) return false;

    var reconciled = false;
    await _run(() async {
      if (!_authenticated ||
          _account != account ||
          _generation != generation ||
          _disposed) {
        return;
      }
      final refreshed = await SharedPreferences.getInstance();
      await refreshed.reload();
      if (refreshed.containsKey('journal_account_switch')) return;
      final currentOwner = refreshed.getString('journal_account_owner');
      if (currentOwner != null &&
          currentOwner != AccountIdentity.hash(account)) {
        return;
      }
      final nextAttempt =
          DateTime.tryParse(refreshed.getString('sync_attempt_at') ?? '')
              ?.toLocal();
      if (nextAttempt != null &&
          (_lastSyncAttemptAt == null ||
              nextAttempt.isAfter(_lastSyncAttemptAt!))) {
        _lastSyncAttemptAt = nextAttempt;
      }
      _serverBackoffUntil =
          DateTime.tryParse(refreshed.getString(_serverBackoffKey) ?? '')
              ?.toLocal();
      final rawReport = refreshed.getString('sync_report_v1');
      if (rawReport != null) {
        try {
          final decoded = jsonDecode(rawReport);
          if (decoded is Map<String, dynamic>) {
            syncReport = SyncReport.fromJson(decoded);
          }
        } on FormatException catch (error) {
          debugPrint(
              '[AssignmentStore] reconcileSyncReport: ${error.runtimeType}');
        } on TypeError catch (error) {
          debugPrint(
              '[AssignmentStore] reconcileSyncReport: ${error.runtimeType}');
        } on ArgumentError catch (error) {
          debugPrint(
              '[AssignmentStore] reconcileSyncReport: ${error.runtimeType}');
        }
      }
      _courseworkState = await repository.loadCourseworkState(account);
      await _reloadJournal();
      reconciled = true;
    });
    return reconciled;
  }

  Future<bool> runDueAutoSync({DateTime? now}) async {
    if (!_authenticated || _loading || _autoSyncRunning || _disposed) {
      return false;
    }
    await reconcileExternalSyncState();
    if (!_authenticated ||
        !_backgroundCheckSettings.enabled ||
        _loading ||
        _autoSyncRunning ||
        _disposed) {
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
    final logoutGen = ++_generation;
    cancelSynchronization();
    chaoxingClient.clearSession();
    _clearHomePreview(notify: true);
    _visitedAssignment = null;
    _activeVisitTicket = null;
    _visitLeftApp = false;
    _pendingReturnConfirmation = null;
    returnCheckMessage = null;
    changes = [];
    _termCatalogCache = null;
    _acknowledgedDeadlineChangeIds = <String>{};
    await _run(() async {
      if (logoutGen != _generation || _disposed) return;
      final accountHash = _accountHash;
      final sessionEpoch = _nativeSessionEpoch;
      String? historyLogoutWarning;
      String? widgetLogoutWarning;
      if (_nativeReminderAvailable && accountHash != null) {
        historyLogoutWarning = await _retireReminderHistoryBeforeLogout(
          accountHash,
          sessionEpoch,
        );
        if (logoutGen != _generation || _disposed) return;
        try {
          await backgroundReminderGateway.clearActiveAccount(accountHash);
        } catch (error) {
          if (logoutGen != _generation || _disposed) return;
          // Local identity removal must still complete. Keep the old account
          // hash so the native cleanup can be retried without account identity.
          _pendingNativeCleanupAccounts.add(accountHash);
          try {
            await _persistNativeCleanupAccounts();
          } catch (persistError) {
            if (logoutGen == _generation && !_disposed) {
              _error = '退出后原生提醒清理未确认，且清理目标未能保存：$persistError';
            }
          }
          if (logoutGen != _generation || _disposed) return;
          _privacyCleanupPending = true;
        }
        if (logoutGen != _generation || _disposed) return;
      }
      _accountHash = null;
      _nativeSessionEpoch = 0;
      widgetSnapshotService.clock = _clock;
      widgetSnapshotService.courseworkState =
          const LocalCourseworkState.empty();
      widgetSnapshotService.termCatalog = null;
      try {
        await repository.runScopedWrite(
          (_) => widgetSnapshotService.saveAssignmentsForContext(
            const [],
            authenticated: false,
            range: display.widgetRange,
          ),
          canCommit: () async => logoutGen == _generation && !_disposed,
        );
      } on StaleSessionWriteException {
        if (logoutGen != _generation || _disposed) return;
        widgetLogoutWarning = '退出时未能确认小组件内容已清除';
      } catch (error) {
        debugPrint('[WidgetSnapshot] logout: ${error.runtimeType}');
        widgetLogoutWarning = '退出时未能确认小组件内容已清除';
      }
      if (logoutGen != _generation || _disposed) return;
      try {
        await _cancelPrivateNotifications();
      } catch (_) {
        if (logoutGen != _generation || _disposed) return;
        // Logout must still remove the local identity. Keep cleanup pending so
        // a later refresh or app start can retry cancellable notifications.
        _privacyCleanupPending = true;
      }
      if (logoutGen != _generation || _disposed) return;
      await personalFileService.releaseAll();
      if (logoutGen != _generation || _disposed) return;
      try {
        await manualAttachmentService.deleteAllAttachments();
      } catch (error) {
        debugPrint('[ManualAttachment] logout_cleanup: ${error.runtimeType}');
      }
      if (logoutGen != _generation || _disposed) return;
      chaoxingClient.clearSession();
      chaoxingClient.previousAssignments = {};
      chaoxingClient.trackedActivityIds = {};
      await sessionStore.clear();
      if (logoutGen != _generation || _disposed) return;
      await repository.clear();
      if (logoutGen != _generation || _disposed) return;
      try {
        await repository.runScopedWrite(
          (prefs) => reminderRuleStore.clear(prefs: prefs),
          canCommit: () async => logoutGen == _generation && !_disposed,
        );
      } on StaleSessionWriteException {
        return;
      }
      if (logoutGen != _generation || _disposed) return;
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
      _allowUrgentDeadlineNightBreakthrough = false;
      _deadlineChannelId = LocalNotificationService.assignmentV2Channel;
      notificationService.activeDeadlineChannelId =
          LocalNotificationService.assignmentV2Channel;
      _chaoxingDisplayName = null;
      _chaoxingAvatarUrl = null;
      _error = null;
      _serviceWarnings.clear();
      _privacyWarnings.clear();
      _deadlineWarnings.clear();
      _summaryWarnings.clear();
      _manualWarnings.clear();
      _widgetWarnings.clear();
      _recoveryWarnings.clear();
      _assignments.clear();
      _lastSyncAt = null;
      _lastSyncAttemptAt = null;
      _serverBackoffUntil = null;
      _hiddenAssignments = [];
      _courses = [];
      _unfollowed.clear();
      _pinned = const PinnedAssignments.empty();
      _courseworkState = const LocalCourseworkState.empty();
      _courseTermPreferences = const CourseTermPreferences.empty();
      _historicalSweepState = const HistoricalSweepState.empty();
      _lastRequestedSyncScope = AssignmentSyncScope.current;
      _lastTargetedCourseKeys = const {};
      _lastSyncSourceResults = const [];
      _termCatalogCache = null;
      _pinsNeedSave = false;
      _invalidateHomeDisplayIndex();
      syncReport = const SyncReport();
      _visitedAssignment = null;
      _activeVisitTicket = null;
      _visitLeftApp = false;
      _pendingReturnConfirmation = null;
      returnCheckMessage = null;
      changes = [];
      _acknowledgedDeadlineChangeIds = <String>{};
      repository.recoveryWarning = null;
      await _reconcileBackgroundControls();
      if (logoutGen != _generation || _disposed) return;
      await _afterAssignmentsChanged(updateWidget: false);
      if (logoutGen != _generation || _disposed) return;
      if (widgetLogoutWarning != null) {
        _serviceWarnings.add(widgetLogoutWarning);
      }
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
      if (_pendingNativeCleanupAccounts.isNotEmpty) {
        _error ??= '账号已退出，但旧账号的原生提醒清理尚未确认；应用会在下次启动或刷新时重试。';
      }
    });
  }

  @visibleForTesting
  void replaceAssignmentsForTest(List<Assignment> assignments) {
    _assignments
      ..clear()
      ..addAll(assignments);
    _invalidateHomeDisplayIndex();
  }

  Future<void> _cleanupRemovedManualAttachments(
    StudyNotebook previous,
    StudyNotebook current,
  ) async {
    final retained = <String>{
      for (final entry in current.entries)
        for (final item in entry.attachments) item.relativePath,
    };
    final removed = <String>[
      for (final entry in previous.entries)
        for (final item in entry.attachments)
          if (!retained.contains(item.relativePath)) item.relativePath,
    ];
    if (removed.isEmpty) return;
    try {
      await manualAttachmentService.deleteFiles(removed);
    } catch (error) {
      debugPrint('[ManualAttachment] cleanup: ${error.runtimeType}');
    }
  }

  Future<bool> _afterAssignmentsChanged({
    bool completeSync = false,
    bool detectNewAssignments = false,
    bool syncCompleted = false,
    bool allowSourceBaselineUpdate = true,
    String? syncFailure,
    DateTime? completedAt,
    bool updateAssignmentReminders = true,
    bool updateSummary = true,
    bool updateManual = true,
    bool updateWidget = true,
  }) async {
    final snap = _captureSession();
    if (updateAssignmentReminders) {
      await _prunePins();
      if (!_isSessionCurrent(snap)) {
        return false;
      }
    }
    var manualRescheduleSucceeded = false;
    final fullRefresh = updateAssignmentReminders &&
        updateSummary &&
        updateManual &&
        updateWidget;
    void clearWarningBucket(List<String> bucket) {
      for (final msg in bucket) {
        _serviceWarnings.remove(msg);
      }
      bucket.clear();
    }

    void addSubsystemWarning(List<String> bucket, String message) {
      bucket.add(message);
      _serviceWarnings.add(message);
    }

    if (fullRefresh) {
      _serviceWarnings.clear();
      _privacyWarnings.clear();
      _deadlineWarnings.clear();
      _summaryWarnings.clear();
      _manualWarnings.clear();
      _widgetWarnings.clear();
    } else {
      clearWarningBucket(_privacyWarnings);
      if (updateAssignmentReminders) clearWarningBucket(_deadlineWarnings);
      if (updateSummary) clearWarningBucket(_summaryWarnings);
      if (updateManual) clearWarningBucket(_manualWarnings);
      if (updateWidget) clearWarningBucket(_widgetWarnings);
    }
    // Restored app preferences can outlive excluded/nonportable credentials.
    // Do not publish their private content to lockscreen or widget before login.
    final scoped = snap.authenticated ? courseAssignments : <Assignment>[];
    if (_privacyCleanupPending) {
      try {
        await _cancelPrivateNotifications();
      } catch (error) {
        addSubsystemWarning(_privacyWarnings, _privacyCleanupMessage(error));
      }
    }
    final effectiveCoursework = snap.authenticated
        ? _courseworkState
        : const LocalCourseworkState.empty();
    notificationService.courseworkState = effectiveCoursework;
    notificationService.allowUrgentNightBreakthrough =
        snap.authenticated && _allowUrgentDeadlineNightBreakthrough;
    notificationService.activeDeadlineChannelId = snap.authenticated
        ? _deadlineChannelId
        : LocalNotificationService.assignmentV2Channel;
    if (!_privacyCleanupPending) {
      if (updateAssignmentReminders) {
        if (_nativeReminderAvailable && _authenticated) {
          final controlsApplied = await _reconcileBackgroundControls();
          if (!controlsApplied) {
            // Fail closed: publishing a plan while showDetails/schedule settings
            // were not applied would activate the previous native settings.
            addSubsystemWarning(
              _deadlineWarnings,
              _backgroundWarning ?? '后台提醒设置未能应用，本次未更新提醒计划',
            );
          } else {
            try {
              if (await _ensureLegacyAssignmentVerified()) {
                await _applyNativeReminderPlan(
                  completeSync: completeSync,
                  detectNewAssignments: detectNewAssignments,
                  syncCompleted: syncCompleted,
                  allowSourceBaselineUpdate: allowSourceBaselineUpdate,
                  failure: syncFailure,
                  completedAt: completedAt,
                );
              }
            } catch (error) {
              addSubsystemWarning(_deadlineWarnings, '后台作业提醒状态未能更新：$error');
            }
          }
        } else {
          try {
            await notificationService.rescheduleAssignments(scoped,
                offsetsMinutes: _reminderOffsetsMinutes);
          } catch (_) {
            addSubsystemWarning(_deadlineWarnings, '提醒安排失败，请检查通知权限后重试');
          }
          if (notificationService.lastWarning != null) {
            addSubsystemWarning(
                _deadlineWarnings, notificationService.lastWarning!);
          }
        }
      }
      if (_manageBackgroundSchedule && updateSummary) {
        try {
          await notificationService.rescheduleSummary(scoped,
              _authenticated ? personal : PersonalWorkspace(), _lastSyncAt);
          if (notificationService.lastWarning != null) {
            addSubsystemWarning(
                _summaryWarnings, notificationService.lastWarning!);
          }
        } catch (error) {
          final detail = notificationService.lastWarning ?? error.toString();
          addSubsystemWarning(
            _summaryWarnings,
            _authenticated && personal.summaryEnabled
                ? '每日摘要未能更新：$detail'
                : '旧摘要未能清理：$detail',
          );
        }
        await _recordPluginScheduleOutcomes(
          notificationService.lastScheduleOutcomes,
        );
      }
      if (_manageBackgroundSchedule && updateManual) {
        try {
          await notificationService
              .rescheduleManual(_authenticated ? notebook.entries : []);
          manualRescheduleSucceeded = !notificationService.lastScheduleOutcomes
              .any((item) => item.stage == 'scheduleFailed');
          if (notificationService.lastWarning != null) {
            addSubsystemWarning(
                _manualWarnings, '个人日程：${notificationService.lastWarning!}');
          }
        } catch (error) {
          manualRescheduleSucceeded = false;
          final detail = notificationService.lastWarning ?? error.toString();
          addSubsystemWarning(_manualWarnings, '个人日程提醒未能更新或清理：$detail');
        }
        await _recordPluginScheduleOutcomes(
          notificationService.lastScheduleOutcomes,
        );
      }
    }
    if (!_isSessionCurrent(snap) || !updateWidget) {
      return manualRescheduleSucceeded;
    }
    final now = _clock();
    final activeCatalog = snap.authenticated ? termCatalog : null;
    final widgetItems = display.forWidget(
      scoped,
      now,
      coursework: effectiveCoursework,
    );
    if (_manageBackgroundSchedule) {
      try {
        await _runScopedWrite(
          snap,
          (_) {
            widgetSnapshotService.clock = _clock;
            widgetSnapshotService.courseworkState = effectiveCoursework;
            widgetSnapshotService.termCatalog = activeCatalog;
            return widgetSnapshotService.saveAssignmentsForContext(
              widgetItems,
              authenticated: snap.authenticated,
              range: display.widgetRange,
            );
          },
        );
      } on StaleSessionWriteException {
        return manualRescheduleSucceeded;
      } catch (_) {
        if (snap.generation == _generation && !_disposed) {
          addSubsystemWarning(_widgetWarnings, '作业已保存在本机，小组件更新失败，请稍后刷新');
        }
      }
    } else if (snap.authenticated && !_privacyCleanupPending) {
      try {
        await _runScopedWrite(
          snap,
          (_) {
            widgetSnapshotService.clock = _clock;
            widgetSnapshotService.courseworkState = effectiveCoursework;
            widgetSnapshotService.termCatalog = activeCatalog;
            return widgetSnapshotService.saveAssignmentsForContext(
              widgetItems,
              authenticated: true,
              range: display.widgetRange,
            );
          },
        );
      } on StaleSessionWriteException {
        return manualRescheduleSucceeded;
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
      if (health.queryErrors.isNotEmpty) {
        healthQueryFailed = true;
        warnings.addAll(health.queryErrors);
      }
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
        hiddenAssignmentIds: _effectiveHiddenAssignmentIds(),
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
        coursework: _courseworkState,
        allowUrgentNightBreakthrough: _allowUrgentDeadlineNightBreakthrough,
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
        allowUrgentNightBreakthrough: _allowUrgentDeadlineNightBreakthrough,
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
        coursework: _authenticated
            ? _courseworkState
            : const LocalCourseworkState.empty(),
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

  Future<void> retryReminderRecovery() {
    final generation = _generation;
    return _run(() async {
      if (_disposed || generation != _generation) return;
      await notificationService.recoverPendingSchedules();
      if (_disposed || generation != _generation) return;
      await _afterAssignmentsChanged();
    });
  }

  Future<void> _maybeMigrateLegacyAssignmentSchedules() async {
    await _ensureLegacyAssignmentVerified();
  }

  Future<void> _maybeMigrateLegacyManualSchedules() async {
    if (!_authenticated ||
        !_manageBackgroundSchedule ||
        _privacyCleanupPending) {
      return;
    }
    notificationService.allowUrgentNightBreakthrough =
        _allowUrgentDeadlineNightBreakthrough;
    notificationService.courseworkState = _courseworkState;
    try {
      await notificationService
          .migrateLegacyManualChannelIfNeeded(notebook.entries);
    } catch (error) {
      _manualWarnings.add('个人日程提醒渠道迁移未完成：$error');
      _serviceWarnings.add('个人日程提醒渠道迁移未完成：$error');
    }
    try {
      await notificationService.migrateLegacySummaryChannelIfNeeded(
        courseAssignments,
        personal,
        _lastSyncAt,
      );
    } catch (error) {
      _summaryWarnings.add('每日摘要提醒渠道迁移未完成：$error');
      _serviceWarnings.add('每日摘要提醒渠道迁移未完成：$error');
    }
    var deadlineRescheduledForV2 = false;
    try {
      await notificationService.retireLegacyUpdatesAndDeadlineChannelsIfNeeded(
        retireDeadlineV1:
            _deadlineChannelId == LocalNotificationService.assignmentV2Channel,
        beforeRetireDeadlineV1: !_nativeReminderAvailable
            ? () async {
                deadlineRescheduledForV2 = true;
                await notificationService.rescheduleAssignments(
                  courseAssignments,
                  offsetsMinutes: _reminderOffsetsMinutes,
                );
                if (notificationService.lastDeadlineScheduleFailed) {
                  final reason = notificationService.lastWarning ?? '截止提醒重排未完成';
                  _deadlineWarnings.add('截止提醒渠道升级重排未完成：$reason');
                  _serviceWarnings.add('截止提醒渠道升级重排未完成：$reason');
                  return false;
                }
                return true;
              }
            : null,
      );
    } catch (error) {
      if (deadlineRescheduledForV2) {
        _deadlineWarnings.add('截止提醒渠道升级重排未完成：$error');
        _serviceWarnings.add('截止提醒渠道升级重排未完成：$error');
      }
      // Best-effort legacy v1 channel cleanup.
    }
    if (_migratedDeadlineChannelToV2ThisRestore && !_nativeReminderAvailable) {
      _migratedDeadlineChannelToV2ThisRestore = false;
      if (!deadlineRescheduledForV2) {
        try {
          await notificationService.rescheduleAssignments(
            courseAssignments,
            offsetsMinutes: _reminderOffsetsMinutes,
          );
        } catch (error) {
          _deadlineWarnings.add('截止提醒渠道升级重排未完成：$error');
          _serviceWarnings.add('截止提醒渠道升级重排未完成：$error');
        }
      }
    }
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
    bool allowSourceBaselineUpdate = true,
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
    final now = completedAt ?? _clock();
    final plan = AssignmentReminderPlanner.planAfterSync(
      accountHash: accountHash,
      sessionEpoch: sessionEpoch,
      assignments: [..._assignments, ..._hiddenAssignments],
      hiddenAssignmentIds: _effectiveHiddenAssignmentIds(),
      unfollowedCourseKeys: _unfollowed,
      knownAssignmentIds: state.knownAssignmentIds,
      sentNewAssignmentIds: state.sentNewAssignmentIds,
      baselineCompleted: state.baselineCompleted,
      baselinedSources: state.baselinedSources,
      completedSourceKeys: (syncCompleted && allowSourceBaselineUpdate)
          ? {
              for (final source in (_lastSyncSourceResults.isNotEmpty
                  ? _lastSyncSourceResults
                  : chaoxingClient.sourceResults))
                if (source.phase == SyncSourcePhase.success) source.source,
            }
          : const {},
      completeSync: completeSync,
      detectNewAssignments: detectNewAssignments,
      newAssignmentReminderEnabled:
          _backgroundCheckSettings.newAssignmentReminderEnabled,
      reminderOffsetsMinutes: _reminderOffsetsMinutes,
      now: now,
      courseworkState: _courseworkState,
      archivedCourseKeys: _archivedReminderCourseKeys(),
      allowUrgentNightBreakthrough: _allowUrgentDeadlineNightBreakthrough,
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

  SyncCourseSelector _buildSyncCourseSelector(
    AssignmentSyncScope requestedScope,
    Set<String> targetedCourseKeys,
  ) {
    return (catalog) {
      final mappedCourses = [
        for (final ref in catalog)
          CourseRef(
            courseId: ref.courseId,
            clazzId: ref.clazzId,
            name: ref.courseName,
            teacherNames: ref.teacherNames,
            folderName: ref.folderName,
          ),
      ];
      final liveCatalog = CourseTermCatalog.build(
        courses: mappedCourses,
        assignments: [..._assignments, ..._hiddenAssignments],
        notices: _courseNotices.items,
        preferences: _courseTermPreferences,
        now: _clock(),
        coursework: _courseworkState,
        unfollowedCourseKeys: _unfollowed,
        hiddenAssignmentIds: {for (final a in _hiddenAssignments) a.id},
        changes: changes,
      );
      return SyncScopeSelection.select(
        catalog: catalog,
        scope: requestedScope,
        termCatalog: liveCatalog,
        targetedCourseKeys: targetedCourseKeys,
      );
    };
  }

  Future<void> _maybeRunHistoricalSweepAfterDaytimeSync({
    required _SessionSnapshot session,
  }) async {
    if (!_isSessionCurrent(session) || _disposed || _syncCancelled) return;
    if (syncReport.phase != SyncPhase.success || _error != null) return;
    final hasBlockingIssue = chaoxingClient.issues.any(
      (issue) => const {
        SyncIssueKind.verificationRequired,
        SyncIssueKind.rateLimited,
        SyncIssueKind.authExpired,
      }.contains(issue.kind),
    );
    if (hasBlockingIssue) return;
    final sweepNow = _clock();
    if (!DaytimeCheckPolicy.isInWindow(sweepNow)) return;
    if (_serverBackoffUntil?.isAfter(sweepNow) ?? false) return;

    final catalog = termCatalog;
    final eligibleKeys = [
      for (final entry in catalog.entries)
        if (entry.isFollowed &&
            !entry.isBlocked &&
            entry.state == CourseCatalogState.archived)
          entry.courseKey,
    ];
    final batch = _historicalSweepState.selectNextBatch(
      eligibleKeys,
      now: sweepNow,
    );
    if (batch.isEmpty) return;

    final account = session.account;
    if (account == null) return;

    final savedReport = syncReport;
    final savedError = _error;
    final batchSet = batch.toSet();
    final priorRecords = [..._assignments, ..._hiddenAssignments];
    var swept = const <Assignment>[];
    var abortedMidBatch = false;
    try {
      chaoxingClient.nextSyncCourseSelector = _buildSyncCourseSelector(
        AssignmentSyncScope.historicalSweep,
        batchSet,
      );
      chaoxingClient.shouldStop =
          () => !DaytimeCheckPolicy.isInWindow(_clock());
      chaoxingClient.previousAssignments = {
        for (final a in priorRecords) a.id: a,
      };
      swept = await chaoxingClient.fetchAssignmentsWithOptions(
        collectCourseNotices: false,
        enableTaskEngineProbe: false,
      );
    } on SyncReadException catch (error) {
      if (error.issue.kind == SyncIssueKind.cancelled) {
        throw const SyncCancelledException();
      }
      abortedMidBatch = true;
    } on ChaoxingAuthenticationException {
      abortedMidBatch = true;
    } catch (_) {
      abortedMidBatch = true;
    } finally {
      chaoxingClient.onProgress = null;
      chaoxingClient.shouldStop = null;
      chaoxingClient.nextSyncCourseSelector = null;
    }

    if (!_isSessionCurrent(session) || _disposed || _syncCancelled) return;
    if (chaoxingClient.issues.isNotEmpty) {
      try {
        await _updateServerBackoff(chaoxingClient.issues, session: session);
      } catch (_) {/* Keep sweep non-blocking for daytime sync state. */}
    }

    final failedKeys = {
      ...chaoxingClient.lastFailedCourseKeys.where(batchSet.contains),
      if (abortedMidBatch && chaoxingClient.lastFailedCourseKeys.isEmpty)
        ...batchSet,
    };
    final nextState = _historicalSweepState.recordBatchResult(
      plannedKeys: batch,
      failedKeys: failedKeys,
      eligiblePastCourseKeys: eligibleKeys,
      at: sweepNow,
    );
    try {
      await repository.saveHistoricalSweepState(nextState, account);
      if (_isSessionCurrent(session)) {
        _historicalSweepState = nextState;
      }
    } catch (_) {
      // Cursor persistence failure leaves old cursor intact without failing
      // the primary daytime sync.
    }

    if (swept.isNotEmpty && _isSessionCurrent(session) && !_disposed) {
      try {
        await _markReminderMutationPending();
        await repository.mergeAndSave(
          swept,
          completeSync: false,
          canCommit: _nativeReminderAvailable
              ? () async {
                  if (!_isSessionCurrent(session) || _disposed) return false;
                  return backgroundReminderGateway.isSessionCurrent(
                    session.accountHash!,
                    session.sessionEpoch,
                  );
                }
              : () async => _isSessionCurrent(session) && !_disposed,
        );
        if (_isSessionCurrent(session) && !_disposed) {
          await _reloadJournal(
            completeSync: false,
            detectNewAssignments: false,
            syncCompleted: true,
            allowSourceBaselineUpdate: false,
          );
        }
      } on StaleSessionWriteException {
        return;
      } catch (_) {
        // Keep primary daytime sync state intact when best-effort historical merge fails.
      }
    }
    if (_isSessionCurrent(session) && !_disposed) {
      syncReport = savedReport;
      _error = savedError;
    }
  }

  Future<void> _syncAssignmentsBody(
    BackgroundSyncTrigger trigger, {
    required int operation,
    bool skipTaskEngineProbe = false,
    AssignmentSyncScope? scope,
    Set<String>? targetedCourseKeys,
  }) async {
    final requestedScope = scope ?? AssignmentSyncScope.current;
    final targetedKeys =
        Set<String>.unmodifiable(targetedCourseKeys ?? const {});
    if (trigger == BackgroundSyncTrigger.manual) {
      _lastRequestedSyncScope = requestedScope;
      _lastTargetedCourseKeys = targetedKeys;
    }
    final priorCurrentSuccessAt = syncReport.lastCurrentSuccessAt;
    final priorFullSuccessAt = _lastSyncAt ?? syncReport.lastFullSuccessAt;
    _lastSyncSourceResults = const [];
    final syncSession = _captureSession(syncOperation: operation);
    final generation = syncSession.generation;
    final syncAccount = syncSession.account;
    _activeSyncSession = syncSession;
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
        lastCurrentSuccessAt: priorCurrentSuccessAt,
        lastFullSuccessAt: priorFullSuccessAt,
        syncScope: requestedScope);
    try {
      await _persistSyncReport(session: syncSession);
    } on StaleSessionWriteException {
      return;
    }
    notifyListeners();
    final bool attemptMirrorSaved;
    try {
      attemptMirrorSaved = await _writeScopedPreferenceAndVerify(
        'sync_attempt_at',
        attempted.toUtc().toIso8601String(),
        session: syncSession,
      );
    } on StaleSessionWriteException {
      return;
    }
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
      _markHomePreviewSaving(generation);
    }

    try {
      chaoxingClient.nextSyncCourseSelector = _buildSyncCourseSelector(
        requestedScope,
        targetedKeys,
      );
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
      chaoxingClient.nextSyncCourseSelector = _buildSyncCourseSelector(
        requestedScope,
        targetedKeys,
      );
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
      chaoxingClient.nextSyncCourseSelector = null;
      if (generation == _generation &&
          !_disposed &&
          !_syncCancelled &&
          operation == _syncOperation &&
          chaoxingClient.hasCourseResponse) {
        final nextCourses = chaoxingClient.courses
            .map((c) => CourseRef(
                  courseId: c.courseId,
                  clazzId: c.clazzId,
                  name: c.courseName,
                  teacherNames: c.teacherNames,
                  folderName: c.folderName,
                ))
            .toList();
        final account = _account;
        if (account == null) {
          throw StateError('当前学习通账号已变化，课程资料未保存');
        }
        markSavingStage();
        try {
          await repository.saveCourses(nextCourses, account: account);
          if (generation == _generation && !_disposed) {
            _courses = nextCourses;
            _invalidateHomeDisplayIndex();
          }
        } on StaleSessionWriteException {
          // Account changed before the finally block could commit courses.
        }
      }
    }
    if (generation != _generation || _disposed) return;
    _ensureSyncActive(operation);
    var warning = chaoxingClient.lastSyncWarning;
    // Snapshot scope, issues, sources, and counts before optional profile
    // recovery, because _refreshChaoxingSession() calls login()->clearSession()
    // and would otherwise wipe this round's sync telemetry.
    final usedSelector = chaoxingClient.hasCourseResponse;
    final effectiveScope = usedSelector
        ? chaoxingClient.lastSyncScope
        : (requestedScope == AssignmentSyncScope.targeted ||
                requestedScope == AssignmentSyncScope.historicalSweep
            ? requestedScope
            : AssignmentSyncScope.all);
    final plannedCount = usedSelector
        ? chaoxingClient.plannedCourses
        : (requestedScope == AssignmentSyncScope.targeted ||
                requestedScope == AssignmentSyncScope.historicalSweep
            ? targetedKeys.length
            : 0);
    final skippedCount = usedSelector ? chaoxingClient.skippedCourses : 0;
    final clientSucceededCourses = chaoxingClient.succeededCourses;
    final clientFailedCourses = chaoxingClient.failedCourses;
    final capturedIssues = List<SyncIssue>.of(chaoxingClient.issues);
    var capturedSourceResults =
        List<SyncSourceResult>.of(chaoxingClient.sourceResults);
    _lastSyncSourceResults = capturedSourceResults;
    final capturedNotices =
        List<CourseNotice>.of(chaoxingClient.lastFetchedNotices);
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
    final isCurrentCoverage = effectiveScope == AssignmentSyncScope.current ||
        effectiveScope == AssignmentSyncScope.all;
    final isFullCoverage = effectiveScope == AssignmentSyncScope.all ||
        (effectiveScope == AssignmentSyncScope.current && skippedCount == 0);
    final cleanSuccess = warning == null;

    final before = [..._assignments, ..._hiddenAssignments];
    await _markReminderMutationPending();
    markSavingStage();
    await repository.mergeAndSave(
      incoming,
      completeSync: cleanSuccess && isFullCoverage,
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
      capturedSourceResults = [
        for (final source in capturedSourceResults)
          sources.contains(source.source)
              ? source.withIdentityConflict()
              : source,
      ];
      _lastSyncSourceResults = capturedSourceResults;
      chaoxingClient.sourceResults = capturedSourceResults;
    }
    final dataSuccessAt = DateTime.now();
    final bool dataMirrorSaved;
    try {
      dataMirrorSaved = await _writeScopedPreferenceAndVerify(
        'sync_data_at',
        dataSuccessAt.toUtc().toIso8601String(),
        session: syncSession,
      );
    } on StaleSessionWriteException {
      return;
    }
    final timestampMirrorFailed = !attemptMirrorSaved || !dataMirrorSaved;
    final reportIssues = List<SyncIssue>.of(capturedIssues);
    var courseNoticeReadFailed = false;
    var courseNoticeSaveFailed = false;
    final courseNoticeResults = capturedSourceResults
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
        capturedSourceResults.any((s) =>
            s.source == 'courseNotice' && s.phase != SyncSourcePhase.failed)) {
      final account = syncAccount;
      if (account != null &&
          generation == _generation &&
          _account == account &&
          !_disposed) {
        try {
          final mergedNotices = _courseNotices.mergeIncoming(capturedNotices);
          await repository.saveCourseNotices(mergedNotices, account);
          if (generation == _generation && _account == account && !_disposed) {
            _courseNotices = mergedNotices;
            _invalidateHomeDisplayIndex();
          }
        } on StaleSessionWriteException {
          return;
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
    final nextCurrentSuccessAt = (cleanSuccess && isCurrentCoverage)
        ? dataSuccessAt
        : priorCurrentSuccessAt;
    final nextFullSuccessAt =
        (cleanSuccess && isFullCoverage) ? dataSuccessAt : priorFullSuccessAt;
    syncReport = SyncReport(
        phase: warning == null &&
                !timestampMirrorFailed &&
                !courseNoticeReadFailed &&
                !courseNoticeSaveFailed
            ? SyncPhase.success
            : SyncPhase.partial,
        attemptedAt: attempted,
        lastDataSuccessAt: dataSuccessAt,
        lastCurrentSuccessAt: nextCurrentSuccessAt,
        lastFullSuccessAt: nextFullSuccessAt,
        syncScope: effectiveScope,
        plannedCourses: plannedCount,
        skippedCourses: skippedCount,
        succeededCourses: clientSucceededCourses,
        failedCourses: clientFailedCourses,
        sourceResults: capturedSourceResults,
        issues: reportIssues);
    try {
      await _updateServerBackoff(reportIssues, session: syncSession);
    } on StaleSessionWriteException {
      return;
    }
    final timestampWarning =
        timestampMirrorFailed ? '作业数据已保存，但同步时间记录未能完整保存；请重新同步核对' : null;
    final courseNoticeWarning = courseNoticeReadFailed ? '部分课程通知未更新' : null;
    _error = [warning, timestampWarning, courseNoticeWarning]
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .join('；');
    if (_error!.isEmpty) _error = null;
    try {
      await _persistSyncReport(session: syncSession);
    } on StaleSessionWriteException {
      return;
    } catch (_) {
      // The journal already contains the data and last-full-sync timestamp.
      // Keep the in-memory result non-successful and let the next launch
      // recover the previous running report as failed rather than claiming
      // that the status record was saved.
      syncReport = SyncReport(
          phase: SyncPhase.partial,
          attemptedAt: attempted,
          lastDataSuccessAt: dataSuccessAt,
          lastCurrentSuccessAt: nextCurrentSuccessAt,
          lastFullSuccessAt: nextFullSuccessAt,
          syncScope: effectiveScope,
          plannedCourses: plannedCount,
          skippedCourses: skippedCount,
          succeededCourses: clientSucceededCourses,
          failedCourses: clientFailedCourses,
          sourceResults: capturedSourceResults,
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
        completeSync: cleanSuccess && isCurrentCoverage,
        detectNewAssignments:
            effectiveScope != AssignmentSyncScope.historicalSweep,
        syncCompleted: true,
        allowSourceBaselineUpdate: isCurrentCoverage,
        syncFailure: warning,
        completedAt: dataSuccessAt,
      );
      if (generation != _generation || _disposed) return;
      _clearHomePreview(notify: true);
      await _recordChanges(
        before,
        incoming,
        completeSync: cleanSuccess && isCurrentCoverage,
        session: syncSession,
      );
      _error ??= warning;
    } on StaleSessionWriteException {
      return;
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
        await _persistSyncReport(session: syncSession);
      } on StaleSessionWriteException {
        return;
      } catch (_) {
        _error = '$_error；同步状态记录也未能保存';
      }
    }
  }

  Future<void> _refreshChaoxingSession() async {
    final generation = _generation;
    final account = _account ?? await sessionStore.readChaoxingAccount();
    if (generation != _generation || _disposed) return;
    final password = await sessionStore.readChaoxingPassword();
    if (generation != _generation || _disposed) return;
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
    if (generation != _generation || _disposed) {
      chaoxingClient.clearSession();
      return;
    }
    if (!result.success) {
      throw StateError(result.message ?? '登录失败');
    }
    _account = account;
    if (result.displayName != null || result.avatarUrl != null) {
      final displayName = result.displayName ??
          _chaoxingDisplayName ??
          await sessionStore.readChaoxingDisplayName();
      if (generation != _generation || _disposed || _account != account) return;
      final avatarUrl = result.avatarUrl ??
          _chaoxingAvatarUrl ??
          await sessionStore.readChaoxingAvatarUrl();
      if (generation != _generation || _disposed || _account != account) return;
      await sessionStore.saveChaoxingAccount(
        account: account,
        password: password,
        displayName: displayName,
        avatarUrl: avatarUrl,
      );
      if (generation != _generation || _disposed || _account != account) return;
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

  Set<String> _archivedReminderCourseKeys() {
    return {
      for (final entry in termCatalog.entries)
        if (entry.state == CourseCatalogState.archived || entry.isBlocked)
          entry.courseKey,
    };
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
          allowUrgentNightBreakthrough: _allowUrgentDeadlineNightBreakthrough,
          deadlineChannelId: _deadlineChannelId,
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

  Future<void> _updateServerBackoff(
    Iterable<SyncIssue> issues, {
    _SessionSnapshot? session,
  }) async {
    final snap = session ?? _captureSession();
    final seconds = issues
        .map((issue) => issue.retryAfterSeconds ?? 0)
        .where((value) => value > 0)
        .fold<int>(0, max);
    if (seconds == 0 && syncReport.phase != SyncPhase.success) {
      return;
    }
    final until =
        seconds == 0 ? null : DateTime.now().add(Duration(seconds: seconds));
    await _runScopedWrite(snap, (prefs) async {
      if (until == null) {
        await prefs.remove(_serverBackoffKey);
      } else {
        await prefs.setString(
          _serverBackoffKey,
          until.toUtc().toIso8601String(),
        );
      }
    });
    if (_isSessionCurrent(snap)) {
      _serverBackoffUntil = until;
    }
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
        _error = '本次同步已取消';
        syncReport = SyncReport(
          phase: SyncPhase.cancelled,
          attemptedAt: syncReport.attemptedAt,
          lastDataSuccessAt: syncReport.lastDataSuccessAt,
          lastCurrentSuccessAt: syncReport.lastCurrentSuccessAt,
          lastFullSuccessAt: _lastSyncAt ?? syncReport.lastFullSuccessAt,
          syncScope: syncReport.syncScope,
          plannedCourses: syncReport.plannedCourses,
          skippedCourses: syncReport.skippedCourses,
          succeededCourses: chaoxingClient.succeededCourses,
          failedCourses: chaoxingClient.failedCourses,
          issues: const [
            SyncIssue(SyncIssueKind.cancelled, '本次同步已取消', stage: 'request')
          ],
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
        final storageFailure = error is LocalStorageWriteException;
        syncReport = SyncReport(
            phase: SyncPhase.failed,
            attemptedAt: syncReport.attemptedAt ?? _lastSyncAttemptAt,
            lastDataSuccessAt: syncReport.lastDataSuccessAt,
            lastCurrentSuccessAt: syncReport.lastCurrentSuccessAt,
            lastFullSuccessAt: _lastSyncAt ?? syncReport.lastFullSuccessAt,
            syncScope: syncReport.syncScope,
            plannedCourses: syncReport.plannedCourses,
            skippedCourses: syncReport.skippedCourses,
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

  bool _isSessionCurrent(_SessionSnapshot snap) {
    if (_disposed ||
        snap.generation != _generation ||
        snap.authenticated != _authenticated ||
        snap.account != _account) {
      return false;
    }
    if (snap.syncOperation != null &&
        (_syncCancelled || snap.syncOperation != _syncOperation)) {
      return false;
    }
    return true;
  }

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

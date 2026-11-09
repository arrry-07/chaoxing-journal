import '../models/display_preferences.dart';
import '../models/home_filters.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../local/chaoxing_assignment_parser.dart';
import '../local/chaoxing_local_client.dart';
import '../local/local_assignment_repository.dart';
import '../models/assignment.dart';
import '../models/sync_report.dart';
import '../models/course.dart';
import 'assignment_query.dart';
import 'local_notification_service.dart';
import 'reminder_rule_store.dart';
import 'secure_session_store.dart';
import 'widget_snapshot_service.dart';
import 'assignment_change_log.dart';
import '../models/assignment_change.dart';
import '../models/backup_snapshot.dart';
import '../models/personal_workspace.dart';
import '../models/study_notebook.dart';

class AssignmentStore extends ChangeNotifier {
  static const defaultAutoSyncIntervalMinutes = 30;
  static const _autoSyncIntervalKey = 'auto_sync_interval_minutes';
  static const _privacyCleanupPendingKey =
      'notification_privacy_cleanup_pending_v1';

  AssignmentStore({
    required this.sessionStore,
    required this.notificationService,
    required this.widgetSnapshotService,
    LocalAssignmentRepository? repository,
    ChaoxingLocalClient? chaoxingClient,
    ReminderRuleStore? reminderRuleStore,
  })  : repository = repository ?? LocalAssignmentRepository(),
        chaoxingClient = chaoxingClient ?? ChaoxingLocalClient(),
        reminderRuleStore = reminderRuleStore ?? ReminderRuleStore();

  final SecureSessionStore sessionStore;
  final LocalNotificationService notificationService;
  final WidgetSnapshotService widgetSnapshotService;
  final LocalAssignmentRepository repository;
  final ChaoxingLocalClient chaoxingClient;
  final ReminderRuleStore reminderRuleStore;
  final changeLog = AssignmentChangeLog();
  PersonalWorkspace personal = PersonalWorkspace();
  StudyNotebook notebook = StudyNotebook();
  HomeFilters homeFilters = const HomeFilters();

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
      notebook = StudyNotebook.decode(next.encode());
      saved = true;
      await _afterAssignmentsChanged();
    });
    return saved;
  }

  int get accountEpoch => _generation;
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
    if (target == null || target.courseId == null || target.clazzId == null) {
      return;
    }
    returnCheckMessage = '正在核对刚才作业的提交状态…';
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
        incoming = await chaoxingClient.fetchAssignmentsForCourse(
            courseId: target.courseId!, clazzId: target.clazzId!);
      } on ChaoxingAuthenticationException {
        await _refreshChaoxingSession();
        incoming = await chaoxingClient.fetchAssignmentsForCourse(
            courseId: target.courseId!, clazzId: target.clazzId!);
      }
      if (generation != _generation || !_authenticated || _disposed) return;
      final observed = incoming.where((a) => a.id == id).firstOrNull;
      final before = [..._assignments, ..._hiddenAssignments];
      final accepted = incoming
          .where((a) => a.id != id || a.statusLabel != '提交状态未知')
          .toList();
      await repository.mergeAndSave(accepted, completeSync: false);
      if (generation != _generation || !_authenticated || _disposed) return;
      await _reloadJournal();
      if (generation != _generation || !_authenticated || _disposed) return;
      await _recordChanges(before, accepted);
      if (generation != _generation || !_authenticated || _disposed) return;
      final latestBefore =
          before.where((a) => a.id == id).firstOrNull ?? target;
      final conflictsWithConfirmation = latestBefore.isCompleted &&
          observed != null &&
          !observed.isCompleted &&
          observed.status != 'returned';
      returnCheckMessage = observed == null ||
              observed.statusLabel == '提交状态未知' ||
              conflictsWithConfirmation
          ? '本次未能确认提交状态，已保留原记录；请稍后刷新核对。'
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
      await changeLog.record(before, [..._assignments, ..._hiddenAssignments],
          incoming.map((a) => a.id).toSet(),
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
  int _autoSyncIntervalMinutes = defaultAutoSyncIntervalMinutes;
  final List<Assignment> _assignments = [];
  Timer? _autoSyncTimer;
  bool _autoSyncRunning = false;

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

  DateTime? get lastSyncAt => _lastSyncAt;
  int get autoSyncIntervalMinutes => _autoSyncIntervalMinutes;
  List<int> get reminderOffsetsMinutes =>
      List.unmodifiable(_reminderOffsetsMinutes);
  List<Assignment> get assignments => List.unmodifiable(_assignments);
  final Set<String> _unfollowed = {};
  List<CourseRef> _courses = [];
  List<CourseRef> get courses => List.unmodifiable(_courses);
  bool follows(String key) => !_unfollowed.contains(key);
  List<Assignment> get formalAssignments =>
      AssignmentQuery.scope(_assignments, {})
          .where((a) => follows(a.courseKey!))
          .toList();
  bool _privacyCleanupPending = false;
  bool get notificationPrivacyPending => _privacyCleanupPending;
  bool get notificationDetails => notificationService.showDetails;
  Future<void> saveNotificationDetails(bool value) => _run(() async {
        final prefs = await SharedPreferences.getInstance();
        if (!value) {
          try {
            await _cancelPrivateNotifications();
          } catch (_) {
            throw StateError('旧提醒未能清理，通知详情尚未关闭，请在提醒体检重试');
          }
        }
        if (!await prefs.setBool('notification_details_v1', value)) {
          throw StateError('通知隐私设置未能保存');
        }
        notificationService.showDetails = value;
        _privacyCleanupPending = false;
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
          await widgetSnapshotService.saveAssignments(display.forWidget(
              _authenticated ? formalAssignments : <Assignment>[],
              DateTime.now()));
        } catch (_) {
          throw StateError('显示设置已保存，小组件更新失败，请稍后刷新');
        }
      });
  List<Assignment> get visibleAssignments =>
      formalAssignments.where((a) => !a.isCompleted).toList();
  Future<void> followCourse(String key, bool followed) => _run(() async {
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

  Future<void> restoreSession() async {
    _recoveryWarnings.clear();
    try {
      _account = await sessionStore.readChaoxingAccount();
      _authenticated = _account?.trim().isNotEmpty == true;
    } catch (error) {
      _recoveryWarnings.add('本机数据恢复未完成：登录信息暂时无法读取，请重新登录');
    }
    try {
      if (_authenticated) {
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
    _restartAutoSyncTimer();
    notifyListeners();
  }

  Future<void> _restoreAccountData() async {
    homeFilters = const HomeFilters();
    notebook = StudyNotebook();
    personal = PersonalWorkspace();
    changes = [];
    _assignments.clear();
    _hiddenAssignments = [];
    _courses = [];
    _unfollowed.clear();
    _reminderOffsetsMinutes = ReminderRuleStore.defaultOffsetsMinutes;
    _lastSyncAt = null;
    _lastSyncAttemptAt = null;
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
      notificationService.showDetails = details;
      _privacyCleanupPending = !details || cleanupPending;
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
      _autoSyncIntervalMinutes = await _loadAutoSyncIntervalMinutes();
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
    await stage('作业记录', () async {
      await _reloadJournal();
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
          await widgetSnapshotService.saveAssignments([]);
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
        } catch (_) {
          _authenticated = false;
          _account = null;
          _assignments.clear();
          _hiddenAssignments = [];
          _courses = [];
          _unfollowed.clear();
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
      _authenticated = true;
      await _restoreAccountData();
      _chaoxingDisplayName = result.displayName;
      _chaoxingAvatarUrl = result.avatarUrl;
      _agreementAccepted = true;
      _authenticated = true;
      loginSucceeded = true;
      _restartAutoSyncTimer();
    });
    _loginRunning = false;
    if (loginSucceeded && _authenticated && generation == _generation) {
      unawaited(syncAssignments());
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

  Future<void>? _syncInFlight;

  Future<void> syncAssignments() {
    if (!_authenticated) return Future.value();
    return _syncInFlight ??= _run(() async {
      if (_authenticated) await _syncAssignmentsBody();
    }).whenComplete(() {
      _syncInFlight = null;
    });
  }

  Future<void> importAssignmentsFromHtml(String html) async {
    await _run(() async {
      final incoming = ChaoxingAssignmentParser.parseWorkHtml(
        html,
        fallbackCourseName: '学习通课程',
        sourcePrefix: 'manual',
        baseUri: Uri.parse('https://mooc1.chaoxing.com'),
      );
      await repository.mergeAndSave(incoming, completeSync: false);
      await _reloadJournal();
    });
  }

  Future<void> _reloadJournal() async {
    final generation = _generation;
    final journal = await repository.loadJournal();
    if (generation != _generation || _disposed) return;
    _assignments
      ..clear()
      ..addAll(journal);
    _hiddenAssignments = await repository.loadHiddenAssignments();
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
      } catch (error) {
        _recoveryWarnings.add('已从作业仓库恢复同步时间，但同步报告未能重新保存：$error');
      }
    }
    if (generation != _generation || _disposed) return;
    await _afterAssignmentsChanged();
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
    await _run(() async {
      await repository.updateCompletion(
        assignmentId,
        completed,
      );
      await _reloadJournal();
    });
  }

  Future<bool> hideAssignment(String assignmentId) async {
    var saved = false;
    await _run(() async {
      await repository.updateCompletion(assignmentId, true);
      await _reloadJournal();
      saved = true;
    });
    return saved;
  }

  Future<bool> saveReminderRule(List<int> offsetsMinutes) async {
    var saved = false;
    await _run(() async {
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
    var saved = false;
    await _run(() async {
      final normalized = normalizeAutoSyncIntervalMinutes(minutes);
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setInt(_autoSyncIntervalKey, normalized)) {
        await prefs.reload();
        throw StateError('自动同步设置未能保存，请重试');
      }
      _autoSyncIntervalMinutes = normalized;
      _restartAutoSyncTimer();
      saved = true;
    });
    return saved;
  }

  Future<bool> runDueAutoSync({DateTime? now}) async {
    if (!_authenticated ||
        _autoSyncIntervalMinutes <= 0 ||
        _loading ||
        _autoSyncRunning) {
      return false;
    }
    final currentNow = now ?? DateTime.now();
    final lastSyncAt = _lastSyncAttemptAt != null &&
            (_lastSyncAt == null || _lastSyncAttemptAt!.isAfter(_lastSyncAt!))
        ? _lastSyncAttemptAt
        : _lastSyncAt;
    if (lastSyncAt != null &&
        currentNow.difference(lastSyncAt).inMinutes <
            _autoSyncIntervalMinutes) {
      return false;
    }

    _lastSyncAttemptAt = currentNow;
    _autoSyncRunning = true;
    try {
      await syncAssignments();
      return _error == null;
    } finally {
      _autoSyncRunning = false;
    }
  }

  Future<void> logout() {
    _generation++;
    _visitedAssignment = null;
    returnCheckMessage = null;
    changes = [];
    return _run(() async {
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
      _hiddenAssignments = [];
      _courses = [];
      _unfollowed.clear();
      syncReport = const SyncReport();
      _visitedAssignment = null;
      returnCheckMessage = null;
      changes = [];
      repository.recoveryWarning = null;
      _restartAutoSyncTimer();
      await _afterAssignmentsChanged();
      if (_serviceWarnings.isNotEmpty) {
        _error = '账号已退出，但部分提醒或桌面内容可能仍保留。请在系统中清除本应用通知并移除小组件。';
      }
    });
  }

  @visibleForTesting
  void replaceAssignmentsForTest(List<Assignment> assignments) {
    _assignments
      ..clear()
      ..addAll(assignments);
  }

  Future<void> _afterAssignmentsChanged() async {
    _serviceWarnings.clear();
    // Restored app preferences can outlive excluded/nonportable credentials.
    // Do not publish their private content to lockscreen or widget before login.
    final scoped = _authenticated ? formalAssignments : <Assignment>[];
    if (_privacyCleanupPending) {
      try {
        await _cancelPrivateNotifications();
      } catch (error) {
        _serviceWarnings.add(_privacyCleanupMessage(error));
      }
    }
    if (!_privacyCleanupPending) {
      try {
        await notificationService.rescheduleAssignments(
            scoped.where((a) => a.deadlineTrusted).toList(),
            offsetsMinutes: _reminderOffsetsMinutes);
      } catch (_) {
        _serviceWarnings.add('提醒安排失败，请检查通知权限后重试');
      }
      if (notificationService.lastWarning != null) {
        _serviceWarnings.add(notificationService.lastWarning!);
      }
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
      try {
        await notificationService
            .rescheduleManual(_authenticated ? notebook.entries : []);
        if (notificationService.lastWarning != null) {
          _serviceWarnings.add('个人日程：${notificationService.lastWarning!}');
        }
      } catch (error) {
        final detail = notificationService.lastWarning ?? error.toString();
        _serviceWarnings.add('个人日程提醒未能更新或清理：$detail');
      }
    }
    try {
      await widgetSnapshotService
          .saveAssignments(display.forWidget(scoped, DateTime.now()));
    } catch (_) {
      _serviceWarnings.add('作业已保存在本机，小组件更新失败，请稍后刷新');
    }
  }

  bool _needsProfileRecovery = false;

  Future<void> _syncAssignmentsBody() async {
    final generation = _generation;
    final attempted = _autoSyncRunning && _lastSyncAttemptAt != null
        ? _lastSyncAttemptAt!
        : DateTime.now();
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
    try {
      incoming = await chaoxingClient.fetchAssignments();
    } on ChaoxingAuthenticationException {
      _needsProfileRecovery = false;
      await _refreshChaoxingSession();
      incoming = await chaoxingClient.fetchAssignments();
    } finally {
      if (generation == _generation &&
          !_disposed &&
          chaoxingClient.hasCourseResponse) {
        _courses = chaoxingClient.courses
            .map((c) => CourseRef(
                courseId: c.courseId, clazzId: c.clazzId, name: c.courseName))
            .toList();
        final account = _account;
        if (account == null) {
          throw StateError('当前学习通账号已变化，课程资料未保存');
        }
        await repository.saveCourses(_courses, account: account);
      }
    }
    if (generation != _generation || _disposed) return;
    final warning = chaoxingClient.lastSyncWarning;
    if (_needsProfileRecovery && !chaoxingClient.deferProfile) {
      _needsProfileRecovery = false;
      try {
        await _refreshChaoxingSession();
      } catch (_) {
        // Profile recovery is optional after a successful homework fetch.
      }
    }
    if (generation != _generation || _disposed) return;
    final before = [..._assignments, ..._hiddenAssignments];
    await repository.mergeAndSave(incoming, completeSync: warning == null);
    if (generation != _generation || _disposed) return;
    final dataSuccessAt = DateTime.now();
    final dataMirrorSaved = await _writePreferenceAndVerify(
        prefs, 'sync_data_at', dataSuccessAt.toUtc().toIso8601String());
    final timestampMirrorFailed = !attemptMirrorSaved || !dataMirrorSaved;
    final reportIssues = List<SyncIssue>.of(chaoxingClient.issues);
    if (timestampMirrorFailed) {
      reportIssues.add(const SyncIssue(SyncIssueKind.storage,
          '作业数据已保存，但兼容同步时间记录未能完整更新；当前同步报告保留了准确时间，请重试以修复记录',
          stage: 'persistence'));
    }
    syncReport = SyncReport(
        phase: warning == null && !timestampMirrorFailed
            ? SyncPhase.success
            : SyncPhase.partial,
        attemptedAt: attempted,
        lastDataSuccessAt: dataSuccessAt,
        lastFullSuccessAt: warning == null ? dataSuccessAt : _lastSyncAt,
        succeededCourses: chaoxingClient.succeededCourses,
        failedCourses: chaoxingClient.failedCourses,
        issues: reportIssues);
    final timestampWarning =
        timestampMirrorFailed ? '作业数据已保存，但同步时间记录未能完整保存；请重新同步核对' : null;
    _error = [warning, timestampWarning]
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
          issues: [
            ...reportIssues,
            const SyncIssue(
                SyncIssueKind.storage, '作业数据已保存，但同步结果记录未能保存；请重新同步核对',
                stage: 'persistence')
          ]);
      _error = '作业数据已保存，但同步结果记录未能保存；请重新同步核对';
    }
    try {
      await _reloadJournal();
      if (generation != _generation || _disposed) return;
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

  Future<int> _loadAutoSyncIntervalMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return normalizeAutoSyncIntervalMinutes(
      prefs.getInt(_autoSyncIntervalKey) ?? defaultAutoSyncIntervalMinutes,
    );
  }

  void _restartAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    if (!_authenticated || _autoSyncIntervalMinutes <= 0) {
      return;
    }
    _autoSyncTimer = Timer.periodic(
      Duration(minutes: _autoSyncIntervalMinutes),
      (_) => unawaited(runDueAutoSync()),
    );
  }

  static int normalizeAutoSyncIntervalMinutes(int minutes) {
    if (minutes <= 0) {
      return 0;
    }
    if (minutes < 1) {
      return 1;
    }
    if (minutes > 1440) {
      return 1440;
    }
    return minutes;
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
      _error = _friendlyError(error);
      if (syncReport.phase == SyncPhase.running) {
        syncReport = SyncReport(
            phase: SyncPhase.failed,
            attemptedAt: syncReport.attemptedAt ?? _lastSyncAttemptAt,
            lastDataSuccessAt: syncReport.lastDataSuccessAt,
            lastFullSuccessAt: _lastSyncAt,
            issues: chaoxingClient.issues.isNotEmpty
                ? List.of(chaoxingClient.issues)
                : [
                    error is SyncReadException
                        ? error.issue
                        : SyncIssue(
                            error is ChaoxingAuthenticationException
                                ? SyncIssueKind.authExpired
                                : SyncIssueKind.network,
                            _error!)
                  ]);
        try {
          await _persistSyncReport();
        } catch (_) {
          _error = '$_error；同步结果未能保存，请重试';
        }
      }
    } finally {
      _loading = false;
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
      await notificationService.cancelPrivateSchedules();
      await _persistPrivacyCleanupPending(false);
      _privacyCleanupPending = false;
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

  String _friendlyError(Object error) {
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
    if (raw.contains('登录失败')) {
      return '登录失败，请检查账号和密码。';
    }
    if (raw.contains('同步失败')) {
      return '学习通作业同步失败，请稍后再试。';
    }
    return raw.isEmpty ? '操作没有完成，请稍后再试。' : raw;
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

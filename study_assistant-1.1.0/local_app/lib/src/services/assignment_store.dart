import 'dart:async';

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

class AssignmentStore extends ChangeNotifier {
  static const defaultAutoSyncIntervalMinutes = 30;
  static const _autoSyncIntervalKey = 'auto_sync_interval_minutes';

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
  String? get error {
    final messages = [_error, repository.recoveryWarning, ..._serviceWarnings]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet();
    return messages.isEmpty ? null : messages.join('；');
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
  List<Assignment> get visibleAssignments =>
      formalAssignments.where((a) => !a.isCompleted).toList();
  Future<void> followCourse(String key, bool followed) async {
    final prefs = await SharedPreferences.getInstance();
    if (followed) {
      _unfollowed.remove(key);
    } else {
      _unfollowed.add(key);
    }
    await prefs.setStringList('unfollowed_courses', _unfollowed.toList());
    await _afterAssignmentsChanged();
    notifyListeners();
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

  Future<void> restoreSession() async {
    try {
      _account = await sessionStore.readChaoxingAccount();
      _chaoxingDisplayName = await sessionStore.readChaoxingDisplayName();
      _chaoxingAvatarUrl = await sessionStore.readChaoxingAvatarUrl();
      _authenticated = _account?.trim().isNotEmpty == true;
      _needsProfileRecovery = _authenticated &&
          (_chaoxingDisplayName == null || _chaoxingAvatarUrl == null);
      _reminderOffsetsMinutes = await reminderRuleStore.loadOffsetsMinutes();
      _autoSyncIntervalMinutes = await _loadAutoSyncIntervalMinutes();
      final prefs = await SharedPreferences.getInstance();
      _lastSyncAttemptAt =
          DateTime.tryParse(prefs.getString('sync_attempt_at') ?? '');
      final dataAt = DateTime.tryParse(prefs.getString('sync_data_at') ?? '');
      syncReport = SyncReport(
          phase: dataAt == null ? SyncPhase.idle : SyncPhase.success,
          attemptedAt: _lastSyncAttemptAt,
          lastDataSuccessAt: dataAt);
      _unfollowed.addAll(prefs.getStringList('unfollowed_courses') ?? []);
      _courses = await repository.loadCourses();
      await _reloadJournal();
    } catch (error) {
      _error = '本机数据恢复未完成：${_friendlyError(error)}';
    }
    _restartAutoSyncTimer();
    notifyListeners();
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
    chaoxingClient.deferProfile = true;
    await _run(() async {
      final result = await chaoxingClient.login(
        account: account,
        password: password,
      );
      if (generation != _generation) return;
      if (!result.success) {
        throw StateError(result.message ?? '登录失败');
      }
      await sessionStore.saveChaoxingAccount(
        account: account,
        password: password,
        displayName: result.displayName,
        avatarUrl: result.avatarUrl,
      );
      _account = account;
      _chaoxingDisplayName = result.displayName;
      _chaoxingAvatarUrl = result.avatarUrl;
      _agreementAccepted = true;
      _authenticated = true;
      _restartAutoSyncTimer();
    });
    _loginRunning = false;
    if (_authenticated && generation == _generation) {
      unawaited(syncAssignments());
      unawaited(_hydrateProfile(generation));
    }
  }

  Future<void> _hydrateProfile(int generation) async {
    if (!chaoxingClient.canHydrateProfile) return;
    try {
      final profile = await chaoxingClient.loadProfile();
      if (generation != _generation || _disposed || !_authenticated) return;
      final pending = _operations.then((_) async {
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
    final journal = await repository.loadJournal();
    _assignments
      ..clear()
      ..addAll(journal);
    _hiddenAssignments = await repository.loadHiddenAssignments();
    _lastSyncAt = await repository.lastSyncAt();
    await _afterAssignmentsChanged();
  }

  Future<void> refreshAssignments() => _run(_reloadJournal);

  Future<void> updateCompletion(String assignmentId, bool completed) async {
    await _run(() async {
      await repository.updateCompletion(
        assignmentId,
        completed,
      );
      await _reloadJournal();
    });
  }

  Future<void> saveReminderRule(List<int> offsetsMinutes) async {
    final normalized = await reminderRuleStore.saveOffsetsMinutes(
      offsetsMinutes,
    );
    _reminderOffsetsMinutes = normalized;
    await _afterAssignmentsChanged();
    notifyListeners();
  }

  Future<void> saveAutoSyncIntervalMinutes(int minutes) async {
    final normalized = normalizeAutoSyncIntervalMinutes(minutes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_autoSyncIntervalKey, normalized);
    _autoSyncIntervalMinutes = normalized;
    _restartAutoSyncTimer();
    notifyListeners();
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
    return _run(() async {
      chaoxingClient.clearSession();
      chaoxingClient.previousAssignments = {};
      chaoxingClient.trackedActivityIds = {};
      await sessionStore.clear();
      await repository.clear();
      await reminderRuleStore.clear();
      _authenticated = false;
      _account = null;
      _agreementAccepted = false;
      _needsProfileRecovery = false;
      _reminderOffsetsMinutes = ReminderRuleStore.defaultOffsetsMinutes;
      _chaoxingDisplayName = null;
      _chaoxingAvatarUrl = null;
      _error = null;
      _assignments.clear();
      _lastSyncAt = null;
      _lastSyncAttemptAt = null;
      _hiddenAssignments = [];
      _courses = [];
      _unfollowed.clear();
      syncReport = const SyncReport();
      repository.recoveryWarning = null;
      _restartAutoSyncTimer();
      await _afterAssignmentsChanged();
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
    try {
      await notificationService.rescheduleAssignments(
          formalAssignments.where((a) => a.deadlineTrusted).toList(),
          offsetsMinutes: _reminderOffsetsMinutes);
    } catch (_) {
      _serviceWarnings.add('提醒安排失败，请检查通知权限后重试');
    }
    if (notificationService.lastWarning != null) {
      _serviceWarnings.add(notificationService.lastWarning!);
    }
    try {
      await widgetSnapshotService.saveAssignments(formalAssignments);
    } catch (_) {
      _serviceWarnings.add('作业已保存在本机，小组件更新失败，请稍后刷新');
    }
  }

  bool _needsProfileRecovery = false;

  Future<void> _syncAssignmentsBody() async {
    final generation = _generation;
    final attempted = DateTime.now();
    syncReport = SyncReport(
        phase: SyncPhase.running,
        attemptedAt: attempted,
        lastDataSuccessAt: syncReport.lastDataSuccessAt,
        lastFullSuccessAt: _lastSyncAt);
    notifyListeners();
    if (!_autoSyncRunning) _lastSyncAttemptAt = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'sync_attempt_at', _lastSyncAttemptAt!.toIso8601String());
    if (chaoxingClient.needsSessionInitialization) {
      await _refreshChaoxingSession();
      _needsProfileRecovery = false;
    }
    chaoxingClient.previousAssignments = {
      for (final a in _assignments) a.id: a
    };
    chaoxingClient.trackedActivityIds = _assignments
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
        await repository.saveCourses(_courses);
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
    await repository.mergeAndSave(incoming, completeSync: warning == null);
    syncReport = SyncReport(
        phase: warning == null ? SyncPhase.success : SyncPhase.partial,
        attemptedAt: attempted,
        lastDataSuccessAt: DateTime.now(),
        lastFullSuccessAt: warning == null ? DateTime.now() : _lastSyncAt,
        succeededCourses: chaoxingClient.succeededCourses,
        failedCourses: chaoxingClient.failedCourses,
        issues: List.of(chaoxingClient.issues));
    await prefs.setString('sync_data_at', DateTime.now().toIso8601String());
    await _reloadJournal();
    _error = warning;
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

  Future<void> _operations = Future.value();

  Future<void> _run(Future<void> Function() action) {
    return _operations = _operations.then((_) => _execute(action));
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
            attemptedAt: _lastSyncAttemptAt,
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
      }
    } finally {
      _loading = false;
      if (!_disposed) notifyListeners();
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

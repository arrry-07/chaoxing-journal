import 'chaoxing_ai_practice_parser.dart';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/assignment.dart';
import '../models/assignment_sync_progress.dart';
import '../models/course_chapter_progress.dart';
import '../models/course_notice.dart';
import '../models/sync_report.dart';
import 'chaoxing_api_parser.dart';
import 'chaoxing_assignment_parser.dart';
import 'chaoxing_chapter_parser.dart';
import 'chaoxing_classroom_parser.dart';
import 'chaoxing_exam_parser.dart';
import 'chaoxing_exam_visibility.dart';
import 'chaoxing_notice_parser.dart';

part 'chaoxing_exam_client.dart';

class VerificationTargetUnavailable implements Exception {
  const VerificationTargetUnavailable();
}

class ChaoxingAuthenticationException implements Exception {
  const ChaoxingAuthenticationException([this.httpStatus]);

  final int? httpStatus;

  @override
  String toString() => '学习通登录已失效，请重新登录';
}

class ChaoxingLoginResult {
  const ChaoxingLoginResult({
    required this.success,
    this.message,
    this.displayName,
    this.avatarUrl,
  });

  final bool success;
  final String? message;
  final String? displayName;
  final String? avatarUrl;
}

class ChaoxingLocalClient {
  // The signed work list is the desktop course surface, as in the reference CLI.
  static const courseUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  ChaoxingLocalClient(
      {Dio? dio,
      Future<void> Function(Duration)? wait,
      this.enableClassroomTasks = true,
      this.enableExams = true})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 20),
                followRedirects: false,
                validateStatus: (status) => status != null && status < 500,
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36 SuperStarStudyHelper/0.1',
                  'Accept':
                      'application/json,text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                  'Referer': 'https://i.chaoxing.com/',
                },
              ),
            ),
        _wait = wait ?? _defaultWait;

  static const _maxAttemptsPerRequest = 2;
  static const _maxRetriesPerSync = 2;
  static const _normalRetryDelay = Duration(milliseconds: 500);
  static const _maxRetryDelay = Duration(seconds: 2);

  final Dio _dio;
  final bool enableClassroomTasks;
  final bool enableExams;
  List<SyncSourceResult> sourceResults = const [];
  List<CourseNotice> _lastFetchedNotices = const [];
  List<CourseNotice> get lastFetchedNotices =>
      List.unmodifiable(_lastFetchedNotices);
  bool _collectCourseNoticesInNextSync = false;
  bool _enableTaskEngineProbeInNextSync = false;
  final Future<void> Function(Duration) _wait;
  CancelToken? _activeRequestToken;
  bool _stopRequested = false;
  static Future<void> _defaultWait(Duration delay) =>
      Future<void>.delayed(delay);

  final _requestStats = <String, _RequestStats>{};
  final _phaseElapsedMs = <String, int>{};
  Map<String, Response<dynamic>>? _syncCourseEntries;
  final _openCircuits = <String, SyncIssue>{};
  final _consecutiveTransientFailures = <String, int>{};
  int _syncRetryCount = 0;
  int? _fullSyncElapsedMs;
  bool Function()? shouldStop;
  void Function(AssignmentSyncProgress)? onProgress;

  void cancelActiveRequests({bool reportCancelled = true}) {
    _syncCourseEntries = null;
    _stopRequested = reportCancelled;
    _activeRequestToken?.cancel('主动停止后台学习通请求');
    _activeRequestToken = null;
    _sessionGeneration++;
  }

  CancelToken _startRequestToken() {
    _syncCourseEntries = null;
    _activeRequestToken?.cancel('开始新的学习通请求');
    _stopRequested = false;
    return _activeRequestToken = CancelToken();
  }

  /// Backoff must not delay an explicit stop for the full retry delay.
  Future<void> _waitOrCancel(Duration delay) async {
    final token = _activeRequestToken;
    if (token == null) {
      await _wait(delay);
    } else {
      await Future.any<Object?>([
        _wait(delay),
        token.whenCancel,
      ]);
    }
    if (_stopRequested) {
      throw const SyncReadException(SyncIssue(
        SyncIssueKind.cancelled,
        '本次同步已取消',
        stage: 'request',
      ));
    }
  }

  Map<String, ({int count, int elapsedMs, int httpFailures})>
      get requestTimings => Map.unmodifiable({
            for (final entry in _requestStats.entries)
              entry.key: (
                count: entry.value.count,
                elapsedMs: entry.value.totalHttpMs + entry.value.totalParseMs,
                httpFailures: entry.value.failures,
              ),
          });

  SyncDiagnostics get diagnostics => SyncDiagnostics(
        fullSyncElapsedMs: _fullSyncElapsedMs,
        phaseElapsedMs: Map.unmodifiable(_phaseElapsedMs),
        requests: Map.unmodifiable({
          for (final entry in _requestStats.entries)
            entry.key: SyncRequestDiagnostics(
              count: entry.value.count,
              failures: entry.value.failures,
              parseFailures: entry.value.parseFailures,
              httpSamples: entry.value.httpSamples,
              parseSamples: entry.value.parseSamples,
            ),
        }),
      );

  static String _requestKind(String path) {
    if (path == '/mycourse/backclazzdata') return '课程列表';
    if (path.contains('stucoursemiddle') || path == '/mooc2-ans/mycourse/stu') {
      return '课程入口';
    }
    if (path.contains('stu-base-info')) return '课程导航';
    if (path.endsWith('/work/list') || path.endsWith('/work/api/task')) {
      return '作业列表';
    }
    if (path.contains('/work/')) return '作业详情';
    if (path.contains('/examcode/examlist')) return '账号考试';
    if (path == '/exam/test' || path == '/exam-ans/exam/test') {
      return '课程考试补充';
    }
    if (path.contains('/exam/') ||
        path.contains('/exam-ans/') ||
        path.endsWith('/examList')) {
      return '课程考试';
    }
    if (path.contains('/mycourse/studentcourse')) return '章节进度';
    if (path.contains('/v2/apis/active/getData')) return '任务引擎探测';
    return '其他';
  }

  void _resetSyncTracking({required bool clearRequestStats}) {
    if (clearRequestStats) _requestStats.clear();
    _phaseElapsedMs.clear();
    _openCircuits.clear();
    _consecutiveTransientFailures.clear();
    _syncRetryCount = 0;
    _fullSyncElapsedMs = null;
  }

  void _recordPhase(String phase, Stopwatch watch) {
    _phaseElapsedMs[phase] = watch.elapsedMilliseconds;
  }

  void _recordHttp(
    String kind,
    int elapsedMs, {
    required bool failed,
    int? parseElapsedMs,
    bool parseFailed = false,
  }) {
    final stats = _requestStats.putIfAbsent(kind, _RequestStats.new);
    stats.count++;
    stats.httpSamples.add(elapsedMs);
    if (failed) stats.failures++;
    if (parseElapsedMs != null) {
      stats.parseSamples.add(parseElapsedMs);
      if (parseFailed) stats.parseFailures++;
    }
  }

  void _recordParse(String kind, int elapsedMs, {bool failed = false}) {
    final stats = _requestStats.putIfAbsent(kind, _RequestStats.new);
    stats.parseSamples.add(elapsedMs);
    if (failed) stats.parseFailures++;
  }

  void _noteParseFailure(String kind) {
    _requestStats.putIfAbsent(kind, _RequestStats.new).parseFailures++;
  }

  T _measureParse<T>(String kind, T Function() action) {
    final watch = Stopwatch()..start();
    try {
      final result = action();
      _recordParse(kind, watch.elapsedMilliseconds);
      return result;
    } catch (_) {
      _recordParse(kind, watch.elapsedMilliseconds, failed: true);
      rethrow;
    }
  }

  bool _registerTransientFailure(String kind, _AttemptFailure failure) {
    if (!failure.transient) {
      _consecutiveTransientFailures.remove(kind);
      return false;
    }
    final count = (_consecutiveTransientFailures[kind] ?? 0) + 1;
    _consecutiveTransientFailures[kind] = count;
    if (count >= 2) {
      _openCircuits[kind] = failure.issue;
      return true;
    }
    return false;
  }

  Duration? _retryDelay(
    String kind,
    int attempt,
    _AttemptFailure failure, {
    required bool circuitOpened,
  }) {
    if (!failure.transient ||
        circuitOpened ||
        attempt >= _maxAttemptsPerRequest ||
        _syncRetryCount >= _maxRetriesPerSync) {
      return null;
    }
    if (failure.issue.kind == SyncIssueKind.rateLimited ||
        failure.retryAfter != null) {
      final retryAfter = failure.retryAfter;
      if (retryAfter == null || retryAfter > _maxRetryDelay) return null;
      return retryAfter;
    }
    return _normalRetryDelay;
  }

  final List<_SessionCookie> _cookies = [];
  Uri? _verificationTarget;
  Uri? _courseVerificationProbe;
  bool _v3FormalApiConfirmed = false;
  SyncIssueKind? _deadlineReadsBlockedBy;

  bool get _verificationRequiredThisSync =>
      _deadlineReadsBlockedBy == SyncIssueKind.verificationRequired ||
      issues.any((issue) => issue.kind == SyncIssueKind.verificationRequired);

  SyncSourceResult _verificationPausedSource(String source, int unread) =>
      SyncSourceResult(
        source: source,
        phase: SyncSourcePhase.failed,
        failedCourses: unread,
        reasonCodes: const ['verificationPaused'],
      );

  Future<bool> verifyInBrowser({bool courseInspection = false}) async {
    final generation = _sessionGeneration;
    final target = _verificationTarget ??
        (courseInspection ? _courseVerificationProbe : null);
    if (target == null) throw const VerificationTargetUnavailable();
    if (target.scheme != 'https' ||
        target.userInfo.isNotEmpty ||
        !(target.host == 'chaoxing.com' ||
            target.host.endsWith('.chaoxing.com'))) {
      throw const VerificationTargetUnavailable();
    }
    final rows = await const MethodChannel('study_assistant/external_links')
        .invokeListMethod<dynamic>('verifySession', {
      'url': target.toString(),
      'userAgent': courseUserAgent,
      'cookies': [
        for (final entry in _cookies.where((e) => !e.expired))
          {
            'url': 'https://${entry.domain}${entry.path}',
            'value': entry.cookie.toString()
          }
      ],
    });
    if (generation != _sessionGeneration || rows == null) return false;
    for (final row in rows.whereType<Map>()) {
      final agent = row['userAgent'];
      if (agent is String &&
          agent.length < 512 &&
          !agent.contains(RegExp(r'[\r\n]'))) {
        _dio.options.headers['User-Agent'] = agent;
      }
      final uri = Uri.tryParse(row['url']?.toString() ?? '');
      if (uri == null ||
          uri.scheme != 'https' ||
          !(uri.host == 'chaoxing.com' || uri.host.endsWith('.chaoxing.com'))) {
        continue;
      }
      for (final pair in (row['cookies']?.toString() ?? '').split(';')) {
        final split = pair.indexOf('=');
        if (split < 1) continue;
        final name = pair.substring(0, split).trim(),
            value = pair.substring(split + 1).trim();
        final matches = _cookies
            .where((e) => e.cookie.name == name && e.matches(uri))
            .toList();
        if (matches.any((e) => e.cookie.value == value)) continue;
        if (matches.isNotEmpty && (uri.path.isEmpty || uri.path == '/')) {
          for (final e in matches) {
            e.cookie.value = value;
          }
        } else {
          final path = uri.path.isEmpty ? '/' : uri.path;
          final cookie = Cookie(name, value)
            ..path = path
            ..secure = true;
          _cookies.add(_SessionCookie(cookie, uri.host, path, true));
        }
      }
    }
    // Returning closes the browser; only the subsequent signed request can prove success.
    return true;
  }

  int _sessionGeneration = 0;
  bool hasCourseResponse = false;

  bool get needsSessionInitialization =>
      _cookies.every((cookie) => cookie.expired);

  String? lastSyncWarning;
  bool deferProfile = false;
  dynamic _loginPayload;
  bool get canHydrateProfile => _loginPayload != null;
  List<SyncIssue> issues = [];
  int succeededCourses = 0, failedCourses = 0;
  int detailUnconfirmedCount = 0;
  final Set<String> _detailUnconfirmedCourseKeys = <String>{};
  Future<ChaoxingLoginResult> loadProfile() async {
    final generation = _sessionGeneration;
    final p = await _fetchProfile(_loginPayload, const _ChaoxingProfile());
    if (generation != _sessionGeneration) {
      return const ChaoxingLoginResult(success: false, message: '会话已切换，请重试');
    }
    final avatarUrl = await _resolveAvatarUrl(p.avatarUrl);
    if (generation != _sessionGeneration) {
      return const ChaoxingLoginResult(success: false, message: '会话已切换，请重试');
    }
    return ChaoxingLoginResult(
        success: true, displayName: p.displayName, avatarUrl: avatarUrl);
  }

  List<ChaoxingCourseRef> courses = [];
  Set<String> trackedActivityIds = {};
  Map<String, Assignment> previousAssignments = {};
  void clearSession() {
    // Stop any transport that still belongs to the previous identity before
    // clearing cookies and generation. A session replacement is a stale-result
    // case, not an explicit user/Worker cancellation, so old callers keep the
    // existing empty-result contract; Store cancellation uses the default.
    cancelActiveRequests(reportCancelled: false);
    _resetSyncTracking(clearRequestStats: true);
    _sessionGeneration++;
    _cookies.clear();
    _loginPayload = null;
    courses = [];
    hasCourseResponse = false;
    issues = [];
    sourceResults = const [];
    succeededCourses = 0;
    failedCourses = 0;
    detailUnconfirmedCount = 0;
    _detailUnconfirmedCourseKeys.clear();
    _verificationTarget = null;
    _courseVerificationProbe = null;
    _v3FormalApiConfirmed = false;
    _deadlineReadsBlockedBy = null;
    lastSyncWarning = null;
  }

  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async {
    clearSession();
    final cancelToken = _startRequestToken();
    final generation = _sessionGeneration;
    if (account.trim().isEmpty || password.isEmpty) {
      return const ChaoxingLoginResult(success: false, message: '请输入账号和密码');
    }

    final response = await _dio.post<dynamic>(
      'https://passport2-api.chaoxing.com/v11/loginregister',
      data: FormData.fromMap({
        'uname': account.trim(),
        'code': password,
        'loginType': '1',
        'roleSelect': 'true',
      }),
      cancelToken: cancelToken,
    );
    if (generation != _sessionGeneration) {
      return const ChaoxingLoginResult(success: false, message: '会话已切换，请重试');
    }
    _rememberCookies(response);
    final payload = _decodeJsonPayload(response.data);
    if (const bool.fromEnvironment('AUTH_DIAGNOSTICS')) {
      // Local diagnostic builds record shape only, never response values,
      // credentials, cookies, redirect URLs or personal identifiers.
      final map = payload is Map ? payload : const {};
      debugPrint('[AuthShape] ${jsonEncode({
            'http': response.statusCode,
            'contentType':
                response.headers.value('content-type')?.split(';').first,
            'map': payload is Map,
            'string': payload is String,
            'statusType': map['status']?.runtimeType.toString(),
            'statusTrue': map['status'] == true,
            'resultType': map['result']?.runtimeType.toString(),
            'resultTrue': map['result'] == true,
            'messageFields': [
              for (final key in ['mes', 'msg', 'msg2', 'message', 'errorMsg'])
                if (map[key] is String) key,
            ],
            'html': payload is String && payload.contains('<html'),
            'length': response.data.toString().length,
          })}');
    }
    final success = payload is Map &&
        (payload['status'] == true || payload['result'] == true);
    if (!success) {
      return ChaoxingLoginResult(
        success: false,
        message: _extractMessage(payload) ?? '学习通未确认登录，请稍后重试',
      );
    }
    final sessionProfile = await _completeLoginSession(response.data);
    if (generation != _sessionGeneration) {
      return const ChaoxingLoginResult(success: false, message: '会话已切换，请重试');
    }
    _loginPayload = response.data;
    if (deferProfile) {
      return ChaoxingLoginResult(
          success: true,
          displayName: sessionProfile.displayName,
          avatarUrl: sessionProfile.avatarUrl);
    }
    final profile = await _fetchProfile(response.data, sessionProfile);
    if (generation != _sessionGeneration) {
      return const ChaoxingLoginResult(success: false, message: '会话已切换，请重试');
    }
    final avatarUrl = await _resolveAvatarUrl(profile.avatarUrl);
    if (generation != _sessionGeneration) {
      return const ChaoxingLoginResult(success: false, message: '会话已切换，请重试');
    }
    return ChaoxingLoginResult(
      success: true,
      displayName: profile.displayName,
      avatarUrl: avatarUrl,
    );
  }

  /// Refresh just the selected course; fetching the lightweight course index
  /// supplies its current cpi/signatures without reading every homework list.
  Future<List<Assignment>> fetchAssignmentsForCourse(
      {required String courseId, required String clazzId}) async {
    _startRequestToken();
    final generation = _sessionGeneration;
    final syncWatch = Stopwatch()..start();
    _resetSyncTracking(clearRequestStats: false);
    _verificationTarget = null;
    _courseVerificationProbe = null;
    final entryCache = _syncCourseEntries = <String, Response<dynamic>>{};
    issues = [];
    sourceResults = const [];
    _deadlineReadsBlockedBy = null;
    try {
      final courseListWatch = Stopwatch()..start();
      final mcode =
          _readCookie('UID') ?? _readCookie('uid') ?? _readCookie('_uid');
      final response = await _safeGet<dynamic>(
          'https://mooc1-api.chaoxing.com/mycourse/backclazzdata',
          queryParameters: {'view': 'json', if (mcode != null) 'mcode': mcode});
      if (generation != _sessionGeneration) return const [];
      final refs = _measureParse(
          '课程列表',
          () => ChaoxingApiParser.parseCourseRefs(
              _decodeJsonPayload(response?.data)));
      _recordPhase('courseList', courseListWatch);
      final course = refs
          .where((c) => c.courseId == courseId && c.clazzId == clazzId)
          .firstOrNull;
      if (course == null) {
        _noteParseFailure('课程列表');
        throw const SyncReadException(SyncIssue(
            SyncIssueKind.notFound, '目标课程暂时无法读取，请刷新作业后重试',
            stage: 'courses'));
      }
      List<Assignment>? rows;
      final formalWatch = Stopwatch()..start();
      try {
        rows = await _fetchCourseWork(course, generation: generation);
      } on ChaoxingAuthenticationException {
        rethrow;
      } on SyncReadException catch (e) {
        if (e.issue.kind == SyncIssueKind.cancelled) rethrow;
        if (generation != _sessionGeneration) return const [];
        issues.add(e.issue);
      }
      if (generation != _sessionGeneration) return const [];
      if (rows == null) _syncCourseEntries?.clear();
      _recordPhase('formalWork', formalWatch);
      sourceResults = [
        _formalSourceResult(
            rows ?? const [], rows == null ? 0 : 1, rows == null ? 1 : 0)
      ];
      final classroomWatch = Stopwatch()..start();
      final classroom =
          await _fetchClassroomTasks([course], generation: generation);
      _recordPhase('classroomTasks', classroomWatch);
      if (generation != _sessionGeneration) return const [];
      final examWatch = Stopwatch()..start();
      final exams = await _fetchExams([course],
          generation: generation, includeAccount: false);
      _recordPhase('exams', examWatch);
      if (generation != _sessionGeneration) return const [];
      if (rows == null && !classroom.recognized && !_hasExamObservation) {
        final issue = issues.isNotEmpty
            ? issues.first
            : const SyncIssue(SyncIssueKind.schemaChanged, '本次未能读取目标课程作业',
                stage: 'work');
        throw SyncReadException(issue);
      }
      return _dedupeAssignments([...?rows, ...classroom.rows, ...exams]);
    } finally {
      if (identical(_syncCourseEntries, entryCache)) _syncCourseEntries = null;
      if (generation == _sessionGeneration) {
        _fullSyncElapsedMs = syncWatch.elapsedMilliseconds;
      }
    }
  }

  Future<List<Assignment>> fetchAssignmentsWithOptions({
    bool collectCourseNotices = false,
    bool enableTaskEngineProbe = false,
  }) async {
    _collectCourseNoticesInNextSync = collectCourseNotices;
    _enableTaskEngineProbeInNextSync = enableTaskEngineProbe;
    try {
      return await fetchAssignments();
    } finally {
      _collectCourseNoticesInNextSync = false;
      _enableTaskEngineProbeInNextSync = false;
    }
  }

  Future<List<Assignment>> fetchAssignments() async {
    final collectNotices = _collectCourseNoticesInNextSync;
    final enableProbe = _enableTaskEngineProbeInNextSync;
    _collectCourseNoticesInNextSync = false;
    _enableTaskEngineProbeInNextSync = false;
    _lastFetchedNotices = const [];
    _startRequestToken();
    final generation = _sessionGeneration;
    final syncWatch = Stopwatch()..start();
    _resetSyncTracking(clearRequestStats: true);
    _verificationTarget = null;
    _courseVerificationProbe = null;
    final entryCache = _syncCourseEntries = <String, Response<dynamic>>{};
    final progress =
        onProgress == null ? null : _SyncProgressTracker(onProgress!);
    progress?.setStage(AssignmentSyncStage.courses);
    lastSyncWarning = null;
    _deadlineReadsBlockedBy = null;
    issues = [];
    sourceResults = const [];
    hasCourseResponse = false;
    succeededCourses = 0;
    failedCourses = 0;
    detailUnconfirmedCount = 0;
    _detailUnconfirmedCourseKeys.clear();
    try {
      final courseListWatch = Stopwatch()..start();
      final mcode =
          _readCookie('UID') ?? _readCookie('uid') ?? _readCookie('_uid');
      final response = await _safeGet<dynamic>(
        'https://mooc1-api.chaoxing.com/mycourse/backclazzdata',
        queryParameters: {'view': 'json', if (mcode != null) 'mcode': mcode},
      );
      if (generation != _sessionGeneration) return const [];
      final parsedCourses = _measureParse('课程列表', () {
        final payload = _decodeJsonPayload(response?.data);
        final raw = payload is Map
            ? payload['channelList'] ?? payload['courses'] ?? payload['data']
            : null;
        final parsed = ChaoxingApiParser.parseCourseRefsDetailed(payload);
        return (
          payload: payload,
          raw: raw,
          refs: parsed.refs,
          rejected: parsed.rejected,
          duplicates: parsed.duplicates,
        );
      });
      _recordPhase('courseList', courseListWatch);
      final payload = parsedCourses.payload;
      final raw = parsedCourses.raw;
      final invalidCourseCount = parsedCourses.rejected;
      courses = parsedCourses.refs;
      if (raw is! List ||
          (raw.isNotEmpty && courses.isEmpty) ||
          (payload is Map &&
              (payload['result'] == false || payload['status'] == false))) {
        _noteParseFailure('课程列表');
        throw const SyncReadException(
            SyncIssue(SyncIssueKind.schemaChanged, '课程列表结构无法识别，请查看详情并重试'));
      }
      final problems = <String>{};
      hasCourseResponse = true;
      progress?.setStage(AssignmentSyncStage.workLists);
      if (invalidCourseCount > 0) {
        failedCourses = invalidCourseCount;
        issues.add(const SyncIssue(SyncIssueKind.schemaChanged, '部分课程结构无法识别'));
        problems.add('部分课程无法识别');
      }
      final assignments = <Assignment>[];
      final formalFailedCourseKeys = <String>{};
      var recognized = courses.isEmpty;
      final formalWatch = Stopwatch()..start();
      for (final course in courses) {
        if (shouldStop?.call() == true) {
          formalFailedCourseKeys.addAll(courses
              .skip(courses.indexOf(course))
              .map((c) => '${c.courseId}:${c.clazzId}'));
          const issue = SyncIssue(
            SyncIssueKind.partial,
            '检查窗口已结束，已停止后续课程请求',
            stage: 'workList',
          );
          issues.add(issue);
          lastSyncWarning = '白天检查窗口已结束，已保存已取得的作业数据';
          break;
        }
        List<Assignment>? work;
        final watch = Stopwatch()..start();
        SyncIssue? failure;
        try {
          work = await _fetchCourseWork(course,
              generation: generation, progress: progress);
          if (generation != _sessionGeneration) return const [];
        } on ChaoxingAuthenticationException {
          rethrow;
        } on SyncReadException catch (e) {
          if (e.issue.kind == SyncIssueKind.cancelled) rethrow;
          if (generation != _sessionGeneration) return const [];
          failure = e.issue;
        } catch (_) {
          if (generation != _sessionGeneration) return const [];
          failure = const SyncIssue(SyncIssueKind.schemaChanged, '作业响应无法识别');
        }
        final label = '${course.courseName}（班级 ${course.clazzId}）';
        if (work == null) {
          _syncCourseEntries?.clear();
          formalFailedCourseKeys.add('${course.courseId}:${course.clazzId}');
          final issue = SyncIssue(failure?.kind ?? SyncIssueKind.schemaChanged,
              '$label ${failure?.message ?? '作业页签名或列表无法识别'}',
              elapsedMs: watch.elapsedMilliseconds,
              httpStatus: failure?.httpStatus,
              retryAfter: failure?.retryAfter,
              retryAfterSeconds: failure?.retryAfterSeconds,
              circuitOpen: failure?.circuitOpen ?? false,
              courseKey: '${course.courseId}:${course.clazzId}',
              stage: failure?.stage ?? 'work');
          issues.add(issue);
          problems.add(issue.message);
          if (issue.kind == SyncIssueKind.verificationRequired) {
            formalFailedCourseKeys.addAll(courses
                .skip(courses.indexOf(course))
                .map((c) => '${c.courseId}:${c.clazzId}'));
            break;
          }
        } else {
          recognized = true;
          succeededCourses++;
          assignments.addAll(work);
          if (work.any((a) => a.deadlineReadFailed)) {
            problems.add('$label 部分截止时间未读取');
          }
        }
        if (_deadlineReadsBlockedBy != null) {
          final unread = courses.length - courses.indexOf(course) - 1;
          if (unread > 0) {
            issues.add(SyncIssue(
                _deadlineReadsBlockedBy!, '本次读取已暂停，另有 $unread 门课程尚未更新',
                stage: 'workList'));
            for (final remaining in courses.skip(courses.indexOf(course) + 1)) {
              formalFailedCourseKeys
                  .add('${remaining.courseId}:${remaining.clazzId}');
            }
          }
          break;
        }
      }
      _recordPhase('formalWork', formalWatch);
      final formalFailureCount =
          invalidCourseCount + formalFailedCourseKeys.length;
      failedCourses = formalFailureCount;
      progress?.setWorkListFailureCount(formalFailureCount);
      sourceResults = [
        _formalSourceResult(assignments, succeededCourses, failedCourses)
      ];
      final classroomWatch = Stopwatch()..start();
      if (enableClassroomTasks) {
        progress?.setStage(AssignmentSyncStage.classroomTasks);
      }
      final classroom = await _fetchClassroomTasks(courses,
          generation: generation,
          unreadCourses: invalidCourseCount,
          progress: progress);
      _recordPhase('classroomTasks', classroomWatch);
      if (generation != _sessionGeneration) return const [];
      assignments.addAll(classroom.rows);
      recognized = recognized || classroom.recognized;
      final failedCourseKeys = {
        ...formalFailedCourseKeys,
        if (enableClassroomTasks) ...classroom.failedCourseKeys,
      };
      failedCourses = invalidCourseCount + failedCourseKeys.length;
      if (classroom.failedCourses > 0) {
        problems.add('部分课堂任务信息尚未读取');
      }
      if (enableExams) {
        progress?.setStage(AssignmentSyncStage.exams);
      }
      final examWatch = Stopwatch()..start();
      final exams = await _fetchExams(
        courses,
        generation: generation,
        collectCourseNotices: collectNotices,
      );
      _recordPhase('exams', examWatch);
      if (generation != _sessionGeneration) return const [];
      assignments.addAll(exams);
      recognized = recognized || _hasExamObservation;
      if (enableProbe && enableClassroomTasks && courses.isNotEmpty) {
        final probeWatch = Stopwatch()..start();
        if (_verificationRequiredThisSync) {
          sourceResults = [
            ...sourceResults,
            _verificationPausedSource('taskEnginePlan', courses.length),
          ];
        } else {
          await _probeTaskEnginePlans(courses, generation: generation);
          _recordPhase('taskEnginePlan', probeWatch);
        }
        if (generation != _sessionGeneration) return const [];
      }
      if (sourceResults.any((s) =>
          const {'exam', 'examAccount', 'examNotice'}.contains(s.source) &&
          s.phase != SyncSourcePhase.success)) {
        problems.add('部分考试或通知来源尚未读取');
      }
      if (_verificationRequiredThisSync) {
        lastSyncWarning = '学习通要求人工验证，已暂停剩余读取';
      } else if (problems.isNotEmpty) {
        final examProblem = sourceResults.any((source) =>
            const {'exam', 'examAccount', 'examNotice'}
                .contains(source.source) &&
            source.phase != SyncSourcePhase.success);
        lastSyncWarning = failedCourses > 0
            ? '已更新 $succeededCourses 门课程，$failedCourses 门待重试'
            : detailUnconfirmedCount > 0 && examProblem
                ? '作业列表已更新，部分截止时间待确认；部分考试信息未更新'
                : detailUnconfirmedCount > 0
                    ? '作业列表已更新，部分截止时间待确认'
                    : '作业记录已更新，部分考试或通知信息尚未确认，请查看读取来源后重试';
      }
      if (!recognized) {
        final issue = issues.isNotEmpty
            ? issues.first
            : const SyncIssue(SyncIssueKind.schemaChanged, '无法读取学习通作业',
                stage: 'work');
        throw SyncReadException(issue,
            relatedIssues: List.unmodifiable(issues.skip(1)));
      }
      return _dedupeAssignments(assignments);
    } finally {
      if (identical(_syncCourseEntries, entryCache)) _syncCourseEntries = null;
      if (generation == _sessionGeneration) {
        _fullSyncElapsedMs = syncWatch.elapsedMilliseconds;
      }
    }
  }

  Future<void> _probeTaskEnginePlans(
    List<ChaoxingCourseRef> refs, {
    required int generation,
  }) async {
    var succeeded = 0;
    var failed = 0;
    var planCountTotal = 0;
    var unfinishedCount = 0;
    final reasons = <String>{};
    for (final course in refs) {
      if (_stopRequested) {
        throw const SyncReadException(
            SyncIssue(SyncIssueKind.cancelled, '本次同步已取消', stage: 'request'));
      }
      if (generation != _sessionGeneration) return;
      try {
        final response = await _safeGet<dynamic>(
          'https://mobilelearn.chaoxing.com/v2/apis/active/getData',
          queryParameters: {
            'courseId': course.courseId,
            'classId': course.clazzId,
            'DB_STRATEGY': 'DEFAULT',
          },
          requestKind: '任务引擎探测',
          verificationProbe: _courseVerificationEntry(course),
        );
        if (generation != _sessionGeneration) return;
        final decoded = _decodeJsonPayload(response?.data);
        final data = decoded is Map ? decoded['data'] : null;
        if (decoded is! Map || (decoded['result'] != 1 && data == null)) {
          failed++;
          reasons.add('probeSchemaUnavailable');
          continue;
        }
        var coursePlans = 0;
        var courseFinished = 0;
        if (data is List) {
          for (final entry in data) {
            if (entry is! Map) continue;
            final total = int.tryParse('${entry['planCount'] ?? 0}') ?? 0;
            final done = int.tryParse('${entry['planFinishCount'] ?? 0}') ?? 0;
            if (total > 0) {
              coursePlans += total;
              courseFinished += done.clamp(0, total);
            }
          }
        } else if (data is Map) {
          final total = int.tryParse('${data['planCount'] ?? 0}') ?? 0;
          final done = int.tryParse('${data['planFinishCount'] ?? 0}') ?? 0;
          if (total > 0) {
            coursePlans += total;
            courseFinished += done.clamp(0, total);
          }
        }
        planCountTotal += coursePlans;
        unfinishedCount += (coursePlans - courseFinished).clamp(0, coursePlans);
        succeeded++;
      } on ChaoxingAuthenticationException {
        rethrow;
      } on SyncReadException catch (e) {
        if (e.issue.kind == SyncIssueKind.cancelled) rethrow;
        failed++;
        reasons.add(e.issue.kind.name);
        if (e.issue.kind == SyncIssueKind.verificationRequired) {
          issues.add(e.issue);
          reasons.add('verificationPaused');
          failed = refs.length - succeeded;
          break;
        }
        if (const {
          SyncIssueKind.authExpired,
          SyncIssueKind.rateLimited,
        }.contains(e.issue.kind)) {
          break;
        }
      } catch (_) {
        failed++;
        reasons.add('probeUnexpectedError');
      }
    }
    if (generation != _sessionGeneration) return;
    if (unfinishedCount > 0) {
      reasons.add('unfinishedPlanDetected');
    }
    sourceResults = [
      ...sourceResults,
      SyncSourceResult(
        source: 'taskEnginePlan',
        phase: failed == 0
            ? SyncSourcePhase.success
            : succeeded > 0
                ? SyncSourcePhase.partial
                : SyncSourcePhase.failed,
        succeededCourses: succeeded,
        failedCourses: failed,
        recordCount: planCountTotal,
        unconfirmedCount: unfinishedCount,
        reasonCodes: reasons.toList(),
      ),
    ];
  }

  Future<CourseChapterSnapshot> fetchCourseChapters(
    ChaoxingCourseRef course,
  ) async {
    _startRequestToken();
    final generation = _sessionGeneration;
    final courseKey = '${course.courseId}:${course.clazzId}';
    final middleUri = Uri.https(
      'mooc1.chaoxing.com',
      '/visit/stucoursemiddle',
      {
        'courseid': course.courseId,
        'clazzid': course.clazzId,
        'ismooc2': '1',
        'v': '2',
        if (course.cpi != null && course.cpi!.isNotEmpty) 'cpi': course.cpi!,
      },
    );
    final middleResp = await _courseGet(
      middleUri,
      generation: generation,
      requestKind: '课程入口',
    );
    if (generation != _sessionGeneration || _stopRequested) {
      throw const SyncReadException(
        SyncIssue(SyncIssueKind.cancelled, '已取消读取章节进度', stage: 'chapters'),
      );
    }
    final middleHtml = middleResp?.data?.toString() ?? '';
    final enc = ChaoxingAssignmentParser.hiddenValue(middleHtml, 'enc');
    final openc = ChaoxingAssignmentParser.hiddenValue(middleHtml, 'openc');
    final pageCpi = ChaoxingAssignmentParser.hiddenValue(middleHtml, 'cpi');
    if (enc == null || enc.isEmpty) {
      throw SyncReadException(SyncIssue(
        SyncIssueKind.schemaChanged,
        '${course.courseName} 未提供章节读取凭证',
        stage: 'chapters',
        courseKey: courseKey,
      ));
    }
    final cpi =
        (pageCpi != null && pageCpi.isNotEmpty) ? pageCpi : (course.cpi ?? '');
    final chapterUri = Uri.https(
      'mooc2-ans.chaoxing.com',
      '/mooc2-ans/mycourse/studentcourse',
      {
        'courseid': course.courseId,
        'clazzid': course.clazzId,
        if (cpi.isNotEmpty) 'cpi': cpi,
        'enc': enc,
        if (openc != null && openc.isNotEmpty) 'openc': openc,
        'fromMiddle': '1',
        'ut': 's',
        't': '${DateTime.now().millisecondsSinceEpoch}',
      },
    );
    final response = await _safeGet<dynamic>(
      chapterUri.toString(),
      headers: {'User-Agent': courseUserAgent},
      requestKind: '章节进度',
    );
    if (generation != _sessionGeneration || _stopRequested) {
      throw const SyncReadException(
        SyncIssue(SyncIssueKind.cancelled, '已取消读取章节进度', stage: 'chapters'),
      );
    }
    try {
      final snapshot = ChaoxingChapterParser.parse(
        response?.data?.toString() ?? '',
        course,
      );
      if (snapshot == null) {
        throw SyncReadException(SyncIssue(
          SyncIssueKind.schemaChanged,
          '${course.courseName} 章节目录结构无法识别',
          stage: 'chapters',
          courseKey: courseKey,
        ));
      }
      return snapshot;
    } on StateError catch (e) {
      if (e.message == 'chapterAccessDenied') {
        throw SyncReadException(SyncIssue(
          SyncIssueKind.forbidden,
          '${course.courseName} 章节页暂不允许访问（签名校验未通过）',
          stage: 'chapters',
          courseKey: courseKey,
        ));
      }
      rethrow;
    }
  }

  SyncSourceResult _formalSourceResult(
          List<Assignment> rows, int succeeded, int failed) =>
      SyncSourceResult(
          source: 'courseWork',
          phase: failed == 0
              ? SyncSourcePhase.success
              : succeeded > 0
                  ? SyncSourcePhase.partial
                  : SyncSourcePhase.failed,
          succeededCourses: succeeded,
          failedCourses: failed,
          recordCount: rows.length,
          unconfirmedCount: rows
              .where((a) =>
                  a.status == 'unknown' ||
                  !a.deadlineTrusted ||
                  a.deadlineReadFailed)
              .length,
          detailUnconfirmedCount: detailUnconfirmedCount);

  /// Enumerate the server course activity list independently of formal work.
  /// A task detail failure remains unknown, cancelling stale pending reminders.
  Future<
          ({
            List<Assignment> rows,
            bool recognized,
            int failedCourses,
            Set<String> failedCourseKeys
          })>
      _fetchClassroomTasks(List<ChaoxingCourseRef> refs,
          {required int generation,
          int unreadCourses = 0,
          _SyncProgressTracker? progress}) async {
    const stale = (
      rows: <Assignment>[],
      recognized: false,
      failedCourses: 0,
      failedCourseKeys: <String>{}
    );
    if (!enableClassroomTasks) return stale;
    if (_verificationRequiredThisSync) {
      final unread = refs.length + unreadCourses;
      sourceResults = [
        ...sourceResults,
        for (final type in [35, 42, 77])
          _verificationPausedSource('classroomActivity:$type', unread),
        const SyncSourceResult(
            source: 'groupHistory', phase: SyncSourcePhase.notEnabled),
      ];
      return (
        rows: const <Assignment>[],
        recognized: false,
        failedCourses: unread,
        failedCourseKeys: {
          for (final ref in refs) '${ref.courseId}:${ref.clazzId}',
        },
      );
    }
    bool isCurrent() {
      if (_stopRequested) {
        throw const SyncReadException(
            SyncIssue(SyncIssueKind.cancelled, '本次同步已取消'));
      }
      return generation == _sessionGeneration;
    }

    bool blocks(SyncIssueKind kind) => const {
          SyncIssueKind.authExpired,
          SyncIssueKind.verificationRequired,
          SyncIssueKind.rateLimited,
        }.contains(kind);
    final rows = <Assignment>[];
    final success = {35: 0, 42: 0, 77: 0},
        failure = {35: unreadCourses, 42: unreadCourses, 77: unreadCourses};
    final reasons = {35: <String>{}, 42: <String>{}, 77: <String>{}};
    if (unreadCourses > 0) {
      for (final type in [35, 42, 77]) {
        reasons[type]!.add('courseIdentityFailed');
      }
    }
    final blockedTypes = <int>{};
    SyncIssueKind? listBlockedBy;
    final failedCourseKeys = <String>{};
    var recognized = refs.isEmpty && unreadCourses == 0;
    final uid = _readCookie('UID') ?? _readCookie('uid') ?? _readCookie('_uid');
    for (final course in refs) {
      if (!isCurrent()) return stale;
      final courseProbe = _courseVerificationEntry(course);
      if (shouldStop?.call() == true || listBlockedBy != null) {
        final remaining = refs.length - refs.indexOf(course);
        for (final type in [35, 42, 77]) {
          failure[type] = failure[type]! + remaining;
          reasons[type]!.add(listBlockedBy == SyncIssueKind.verificationRequired
              ? 'verificationPaused'
              : 'readStopped');
        }
        failedCourseKeys.addAll(refs
            .skip(refs.indexOf(course))
            .map((c) => '${c.courseId}:${c.clazzId}'));
        issues.add(const SyncIssue(SyncIssueKind.partial, '部分课堂任务尚未读取，请稍后刷新',
            stage: 'classroom'));
        break;
      }
      List<dynamic> activities;
      try {
        final response = await _safeGet<dynamic>(
            'https://mobilelearn.chaoxing.com/v2/apis/active/student/activelist',
            queryParameters: {
              'fid': 0,
              'courseId': course.courseId,
              'classId': course.clazzId,
              'showNotStartedActive': 0
            },
            requestKind: '课堂活动列表',
            verificationProbe: courseProbe);
        if (!isCurrent()) return stale;
        activities = _measureParse(
            '课堂活动列表',
            () => ChaoxingClassroomParser.readActivityList(
                _decodeJsonPayload(response?.data)));
        recognized = true;
      } catch (e) {
        if (e is SyncReadException && e.issue.kind == SyncIssueKind.cancelled) {
          rethrow;
        }
        if (!isCurrent()) return stale;
        final issue = _classroomIssue(e);
        issues.add(issue);
        if (blocks(issue.kind)) listBlockedBy = issue.kind;
        for (final type in [35, 42, 77]) {
          failure[type] = failure[type]! + 1;
          reasons[type]!.add('activityListFailed');
          if (issue.kind == SyncIssueKind.verificationRequired) {
            reasons[type]!.add('verificationPaused');
          }
        }
        failedCourseKeys.add('${course.courseId}:${course.clazzId}');
        continue;
      }
      for (final type in [35, 42, 77]) {
        var complete = true;
        try {
          final seeds = ChaoxingClassroomParser.parseActivities(activities,
              courseId: course.courseId,
              clazzId: course.clazzId,
              courseName: course.courseName,
              activityType: type);
          progress?.addRows(seeds,
              courseKey:
                  '${course.courseId}:${course.clazzId}:classroomActivity:$type');
          if (!isCurrent()) return stale;
          for (final seed in seeds) {
            Assignment task = seed;
            progress?.attempt(seed.id);
            if (!isCurrent()) return stale;
            if (blockedTypes.contains(type) || shouldStop?.call() == true) {
              complete = false;
              reasons[type]!.add(
                  listBlockedBy == SyncIssueKind.verificationRequired
                      ? 'verificationPaused'
                      : 'sourceReadStopped');
            } else {
              try {
                task = await _hydrateClassroomTask(seed,
                    uid: uid,
                    generation: generation,
                    expectedCpi: course.cpi,
                    verificationProbe: courseProbe);
              } catch (e) {
                if (e is SyncReadException &&
                    e.issue.kind == SyncIssueKind.cancelled) {
                  rethrow;
                }
                if (!isCurrent()) return stale;
                complete = false;
                reasons[type]!.add('personalDetailFailed');
                final issue = _classroomIssue(e);
                issues.add(issue);
                if (issue.kind == SyncIssueKind.verificationRequired) {
                  listBlockedBy = issue.kind;
                  blockedTypes.addAll([35, 42, 77]);
                  reasons[type]!.add('verificationPaused');
                } else if (issue.kind == SyncIssueKind.authExpired) {
                  // Same login, while already read formal results remain valid.
                  blockedTypes.addAll([35, 42, 77]);
                } else if (blocks(issue.kind)) {
                  blockedTypes.add(type);
                }
              }
            }
            if (!isCurrent()) return stale;
            rows.add(task);
            progress?.resolve(seed.id, task);
            if (!isCurrent()) return stale;
          }
        } catch (e) {
          if (e is SyncReadException &&
              e.issue.kind == SyncIssueKind.cancelled) {
            rethrow;
          }
          if (!isCurrent()) return stale;
          complete = false;
          reasons[type]!.add('activityIdentityFailed');
          issues.add(_classroomIssue(e));
          progress?.retractCourse(
              '${course.courseId}:${course.clazzId}:classroomActivity:$type');
          if (!isCurrent()) return stale;
        }
        if (complete) {
          success[type] = success[type]! + 1;
        } else {
          failure[type] = failure[type]! + 1;
          failedCourseKeys.add('${course.courseId}:${course.clazzId}');
        }
      }
    }
    if (!isCurrent()) return stale;
    sourceResults = [
      ...sourceResults,
      for (final type in [35, 42, 77])
        SyncSourceResult(
            source: 'classroomActivity:$type',
            phase: failure[type] == 0
                ? SyncSourcePhase.success
                : success[type]! > 0 || rows.any((a) => a.activityType == type)
                    ? SyncSourcePhase.partial
                    : SyncSourcePhase.failed,
            succeededCourses: success[type]!,
            failedCourses: failure[type]!,
            recordCount: rows.where((a) => a.activityType == type).length,
            unconfirmedCount: rows
                .where((a) =>
                    a.activityType == type &&
                    (a.status == 'unknown' ||
                        !a.deadlineTrusted ||
                        a.availability == AssignmentAvailability.unknown))
                .length,
            reasonCodes: reasons[type]!.toList()),
      const SyncSourceResult(
          source: 'groupHistory', phase: SyncSourcePhase.notEnabled)
    ];
    return (
      rows: rows,
      recognized: recognized,
      failedCourses: failedCourseKeys.length + unreadCourses,
      failedCourseKeys: failedCourseKeys
    );
  }

  SyncIssue _classroomIssue(Object error) {
    final issue = error is SyncReadException ? error.issue : null;
    return SyncIssue(
        issue?.kind ??
            (error is ChaoxingAuthenticationException
                ? SyncIssueKind.authExpired
                : SyncIssueKind.schemaChanged),
        '部分课堂任务信息未能确认，请稍后刷新',
        stage: 'classroom',
        httpStatus: issue?.httpStatus ??
            (error is ChaoxingAuthenticationException
                ? error.httpStatus
                : null),
        retryAfter: issue?.retryAfter,
        retryAfterSeconds: issue?.retryAfterSeconds,
        circuitOpen: issue?.circuitOpen ?? false);
  }

  Future<Assignment> _hydrateClassroomTask(Assignment seed,
      {required String? uid,
      required int generation,
      String? expectedCpi,
      Uri? verificationProbe}) async {
    if (seed.activityType == 77) {
      if (seed.submitUrl == null) {
        throw const FormatException('aiPracticeEntryMissing');
      }
      final page = await _courseGet(Uri.parse(seed.submitUrl!),
          generation: generation,
          requestKind: 'AI实践',
          verificationProbe: verificationProbe);
      if (generation != _sessionGeneration) return seed;
      final context = ChaoxingAiPracticeParser.pageContext(
          seed, page?.data?.toString() ?? '',
          uid: uid, expectedCpi: expectedCpi);
      final response = await _safeGet<dynamic>(
          'https://mooc2-ans.chaoxing.com/mooc2-ans/ai-evaluate/v2/answer/load-data',
          queryParameters: context,
          requestKind: 'AI实践',
          verificationProbe: verificationProbe);
      if (generation != _sessionGeneration) return seed;
      return ChaoxingAiPracticeParser.personal(
          seed, _decodeJsonPayload(response?.data), context);
    }
    final kind = seed.activityType == 35 ? '个人分组任务' : '随堂练习';
    Future<dynamic> read(String path, Map<String, dynamic> parameters) async {
      final response = await _safeGet<dynamic>(
          'https://mobilelearn.chaoxing.com$path',
          queryParameters: parameters,
          requestKind: kind,
          verificationProbe: verificationProbe);
      if (generation != _sessionGeneration) return null;
      return _decodeJsonPayload(response?.data);
    }

    final q = {'activeId': seed.activityId!};
    if (seed.activityType == 35) {
      final metadataPayload = await read('/v2/apis/taskStu/getActiveInfoForMe',
          {...q, 'fid': 0, 'courseId': seed.courseId!});
      if (generation != _sessionGeneration) return seed;
      final metadata =
          ChaoxingClassroomParser.taskMetadata(metadataPayload, seed);
      if (ChaoxingClassroomParser.isUnavailable(metadata)) {
        return ChaoxingClassroomParser.unavailable(seed);
      }
      final detail = await read('/v2/apis/task/getTaskActiveInfo', q);
      if (generation != _sessionGeneration) return seed;
      final personal = uid == null
          ? {'result': 1, 'data': <String, dynamic>{}}
          : await read('/v2/apis/taskStu/getMyGroupInfo', {...q, 'puid': uid});
      if (generation != _sessionGeneration) return seed;
      return _measureParse(
          kind,
          () => ChaoxingClassroomParser.parseTask(seed,
              metadata: metadata,
              detailPayload: detail,
              personalPayload: personal,
              currentUid: uid));
    }
    final detail = await read('/v2/apis/quiz/quizDetail2', {
      ...q,
      'moreClassAttendEnc': '',
      'DB_STRATEGY': 'PRIMARY_KEY',
      'STRATEGY_PARA': 'activeId'
    });
    if (generation != _sessionGeneration) return seed;
    final answer = await read('/v2/apis/studentQuestion/getAnswerResult', q);
    if (generation != _sessionGeneration) return seed;
    return _measureParse(
        kind,
        () => ChaoxingClassroomParser.parseQuiz(seed,
            detailPayload: detail, answerPayload: answer, currentUid: uid));
  }

  Uri _courseVerificationEntry(ChaoxingCourseRef course) =>
      Uri.https('mooc1.chaoxing.com', '/visit/stucoursemiddle', {
        'courseid': course.courseId,
        'clazzid': course.clazzId,
        if (course.cpi != null) 'cpi': course.cpi!,
        'ismooc2': '1',
        'v': '2',
      });

  Future<List<Assignment>?> _fetchCourseWork(ChaoxingCourseRef course,
      {required int generation, _SyncProgressTracker? progress}) async {
    final courseUri = _courseVerificationEntry(course);
    _courseVerificationProbe = courseUri;
    if (_v3FormalApiConfirmed) {
      return _fetchV3FormalHomework(course,
          generation: generation,
          progress: progress,
          verificationProbe: courseUri);
    }
    final middle = await _courseGet(courseUri,
        generation: generation, verificationProbe: courseUri);
    if (generation != _sessionGeneration) return null;
    final middlePage = _measureParse('课程入口', () {
      final html = middle?.data?.toString() ?? '';
      return (
        html: html,
        workEnc: ChaoxingAssignmentParser.hiddenValue(html, 'workEnc'),
        openc: ChaoxingAssignmentParser.hiddenValue(html, 'openc'),
        stuenc: ChaoxingAssignmentParser.hiddenValue(html, 'enc'),
      );
    });
    final html = middlePage.html;
    if (html.contains('没有此页面访问权限')) {
      throw SyncReadException(SyncIssue(SyncIssueKind.forbidden, '学习通未允许访问此课程',
          stage: 'coursePage', httpStatus: middle?.statusCode));
    }
    final workEnc = middlePage.workEnc;
    if (kDebugMode) {
      debugPrint(
          '[SyncCourse] status=${middle?.statusCode} signed=${workEnc?.isNotEmpty == true} vue=${html.contains('/mooc2-ans-vue/')}');
    }
    final navigationUri =
        (workEnc == null || workEnc.isEmpty) && html.contains('/mooc2-ans-vue/')
            ? await _fetchNavigationWorkUri(course,
                generation: generation, verificationProbe: courseUri)
            : null;
    if (generation != _sessionGeneration) return null;
    if ((workEnc == null || workEnc.isEmpty) && navigationUri == null) {
      final isVue = html.contains('/mooc2-ans-vue/');
      if (isVue || middle?.statusCode == 200) {
        try {
          final work = await _fetchV3FormalHomework(course,
              generation: generation,
              progress: progress,
              verificationProbe: courseUri);
          if (generation != _sessionGeneration) return null;
          if (isVue) _v3FormalApiConfirmed = true;
          return work;
        } on SyncReadException catch (error) {
          if (isVue || error.issue.kind != SyncIssueKind.schemaChanged) {
            rethrow;
          }
        }
      }
      throw SyncReadException(SyncIssue(
          SyncIssueKind.schemaChanged, '课程页未生成作业读取凭证，可在应用内检查访问',
          stage: 'coursePage', httpStatus: middle?.statusCode));
    }
    final uri = navigationUri ??
        Uri.https('mooc1.chaoxing.com', '/mooc2/work/list', {
          'courseId': course.courseId,
          'classId': course.clazzId,
          if (course.cpi != null) 'cpi': course.cpi!,
          'ut': 's',
          'enc': workEnc!,
          'openc': middlePage.openc ?? '',
          'stuenc': middlePage.stuenc ?? '',
          'isdisplaytable': '2',
          't': DateTime.now().millisecondsSinceEpoch.toString(),
        });
    final list = await _courseGet(uri,
        generation: generation, verificationProbe: courseUri);
    if (generation != _sessionGeneration) return null;
    final parsed = _measureParse(
        '作业列表',
        () => ChaoxingAssignmentParser.parseSignedWorkList(
            list?.data?.toString() ?? '',
            courseId: course.courseId,
            clazzId: course.clazzId,
            courseName: course.courseName,
            baseUri: uri));
    if (parsed == null) {
      _noteParseFailure('作业列表');
      return null;
    }
    progress?.addRows(parsed);
    return _hydrateWorkDeadlines(parsed,
        generation: generation,
        progress: progress,
        verificationProbe: courseUri,
        readStartTimes: () async => (await _readV3FormalHomework(course,
                generation: generation,
                requestKind: '截止时间佐证',
                verificationProbe: courseUri))
            .starts);
  }

  Future<List<Assignment>> _hydrateWorkDeadlines(List<Assignment> rows,
      {required int generation,
      _SyncProgressTracker? progress,
      Uri? verificationProbe,
      Map<String, DateTime> starts = const {},
      Future<Map<String, DateTime>> Function()? readStartTimes}) async {
    final result = <Assignment>[];
    var startTimes = starts;
    var startTimesRequested = false;
    progress?.beginDetails(rows);
    for (var item in rows) {
      final anchoredStart = startTimes[item.id];
      if (item.availableFromAt == null && anchoredStart != null) {
        item = item.copyWith(availableFromAt: anchoredStart);
      }
      final prior = previousAssignments[item.id];
      final completedDeadlineKnown =
          item.deadlineAt != null && item.deadlineTrusted;
      final priorDeadlineKnown = prior?.deadlineTrusted == true;
      if (item.isCompleted && (completedDeadlineKnown || priorDeadlineKnown)) {
        final completed = item.copyWith(
            deadlineAt: item.deadlineAt ?? prior?.deadlineAt,
            deadlineTrusted:
                item.deadlineAt != null || prior?.deadlineTrusted == true,
            deadlineReadFailed: false,
            deadlineRawText: item.deadlineAt != null
                ? item.deadlineRawText
                : prior?.deadlineRawText);
        result.add(completed);
        progress?.replace(completed);
        continue;
      }
      if (item.deadlineTrusted && item.deadlineAt != null) {
        result.add(item);
        progress?.replace(item);
        continue;
      }
      DeadlineEvidence evidence = const DeadlineEvidence();
      SyncIssue? failure;
      bool isUnconfirmedDeadline() =>
          evidence.deadlineAt == null &&
          !evidence.noLimit &&
          !evidence.notOpen &&
          !evidence.startOnly;
      if (_deadlineReadsBlockedBy == null) {
        progress?.attempt(item.id);
        final watch = Stopwatch()..start();
        try {
          final response = await _courseGet(Uri.parse(item.submitUrl!),
              generation: generation, verificationProbe: verificationProbe);
          if (generation != _sessionGeneration) {
            progress?.clearPending();
            return const [];
          }
          final detail = _measureParse('作业详情', () {
            final body = response?.data?.toString() ?? '';
            if (body.contains('没有此页面访问权限')) {
              throw SyncReadException(SyncIssue(
                  SyncIssueKind.forbidden, '学习通未允许访问此作业详情',
                  httpStatus: response?.statusCode, stage: 'detail'));
            }
            return (
              body: body,
              evidence: ChaoxingAssignmentParser.readDetailDeadline(body,
                  startedAt: startTimes[item.id]),
            );
          });
          evidence = detail.evidence;
          if ((evidence.missingYear ||
                  (evidence.availableFromAt == null &&
                      evidence.availableFromText != null)) &&
              startTimes[item.id] == null &&
              readStartTimes != null) {
            // Signed HTML lists omit absolute starts. Read the formal API only
            // when needed; its validated course/class/work identity supplies an
            // anchor, never a replacement list or status. The detail parser
            // still requires the displayed start to match to the minute.
            if (!startTimesRequested) {
              startTimesRequested = true;
              startTimes = await readStartTimes();
              if (generation != _sessionGeneration) {
                progress?.clearPending();
                return const [];
              }
            }
            if (startTimes[item.id] != null) {
              item = item.copyWith(
                  availableFromAt: item.availableFromAt ?? startTimes[item.id]);
              evidence = _measureParse(
                  '作业详情',
                  () => ChaoxingAssignmentParser.readDetailDeadline(detail.body,
                      startedAt: startTimes[item.id]));
            }
          }
          if (kDebugMode) {
            debugPrint(
                '[DeadlineRead] status=${response?.statusCode} bytes=${detail.body.length} startAnchor=${startTimes.containsKey(item.id)} exact=${evidence.deadlineAt != null} noLimit=${evidence.noLimit} missingYear=${evidence.missingYear} notOpen=${evidence.notOpen} startOnly=${evidence.startOnly}');
          }
          if (isUnconfirmedDeadline()) {
            _noteParseFailure('作业详情');
            failure = SyncIssue(SyncIssueKind.schemaChanged,
                evidence.missingYear ? '作业详情只提供月日，截止年份待确认' : '作业详情未提供可识别的截止信息',
                stage: 'detail',
                courseKey: item.courseKey,
                assignmentId: item.id,
                httpStatus: response?.statusCode,
                elapsedMs: watch.elapsedMilliseconds);
          }
        } on ChaoxingAuthenticationException {
          // The list has already been read successfully. Save those rows and
          // ask for reauthentication instead of discarding this sync's data.
          _deadlineReadsBlockedBy = SyncIssueKind.authExpired;
          failure = SyncIssue(SyncIssueKind.authExpired, '作业详情登录已失效，请重新登录',
              stage: 'detail',
              courseKey: item.courseKey,
              assignmentId: item.id,
              elapsedMs: watch.elapsedMilliseconds);
        } on SyncReadException catch (e) {
          if (e.issue.kind == SyncIssueKind.cancelled) rethrow;
          if (generation != _sessionGeneration) {
            progress?.clearPending();
            return const [];
          }
          failure = SyncIssue(e.issue.kind, e.issue.message,
              stage: 'detail',
              courseKey: item.courseKey,
              assignmentId: item.id,
              httpStatus: e.issue.httpStatus,
              retryAfter: e.issue.retryAfter,
              retryAfterSeconds: e.issue.retryAfterSeconds,
              circuitOpen: e.issue.circuitOpen,
              elapsedMs: watch.elapsedMilliseconds);
          if (e.issue.kind == SyncIssueKind.verificationRequired) {
            _deadlineReadsBlockedBy = e.issue.kind;
          }
        }
      }
      final readFailed = failure != null || isUnconfirmedDeadline();
      if (readFailed) {
        detailUnconfirmedCount++;
        if (item.courseKey != null) {
          _detailUnconfirmedCourseKeys.add(item.courseKey!);
        }
      }
      if (failure != null) issues.add(failure);
      final startEvidenceConflict = evidence.startEvidenceConflict;
      final retainedDeadline = !readFailed &&
              !evidence.noLimit &&
              evidence.deadlineAt == null &&
              prior?.deadlineTrusted == true
          ? prior?.deadlineAt
          : null;
      final resolved = item.copyWith(
          deadlineAt: evidence.deadlineAt ?? retainedDeadline,
          clearDeadlineAt: evidence.noLimit,
          deadlineTrusted: evidence.deadlineAt != null ||
              retainedDeadline != null ||
              evidence.noLimit,
          deadlineReadFailed: readFailed,
          deadlineRawText: evidence.missingYear
              ? '${evidence.rawText}（年份待确认）'
              : retainedDeadline != null
                  ? prior?.deadlineRawText
                  : evidence.rawText,
          availableFromAt: startEvidenceConflict
              ? null
              : evidence.availableFromAt ?? startTimes[item.id],
          clearAvailableFromAt: startEvidenceConflict,
          availableFromText: evidence.availableFromText);
      result.add(resolved);
      progress?.resolve(item.id, resolved);
    }
    return result;
  }

  // fanyav3 obtains its signed navigation from this first-party endpoint.
  // Only follow the formal homework page, with the same course/class identity.
  Future<Uri?> _fetchNavigationWorkUri(ChaoxingCourseRef course,
      {required int generation, Uri? verificationProbe}) async {
    final response = await _safeGet<dynamic>(
        'https://mooc2-ans.chaoxing.com/mooc2-ans/coursemanagev3/stu-base-info',
        queryParameters: {
          'courseId': course.courseId,
          'clazzId': course.clazzId,
          if (course.cpi != null) 'cpi': course.cpi!
        },
        headers: {'User-Agent': courseUserAgent},
        verificationProbe: verificationProbe);
    if (generation != _sessionGeneration) return null;
    final payload =
        _measureParse('课程导航', () => _decodeJsonPayload(response?.data));
    Uri? findWork(dynamic node) {
      if (node is List) {
        for (final child in node) {
          final found = findWork(child);
          if (found != null) return found;
        }
      } else if (node is Map) {
        final link = node['linkUrl'];
        if (link is String) {
          var target = Uri.tryParse(link.replaceAll('&amp;', '&'));
          if (target != null) {
            target =
                Uri.https('mooc2-ans.chaoxing.com', '/').resolveUri(target);
            if (target.scheme == 'http' &&
                target.host.endsWith('.chaoxing.com')) {
              target = target.replace(scheme: 'https', port: 443);
            }
            final q = target.queryParameters;
            if (target.scheme == 'https' &&
                target.host.endsWith('.chaoxing.com') &&
                const ['/mooc2/work/list', '/mooc-ans/work/list']
                    .contains(target.path) &&
                (q['courseId'] ?? q['courseid']) == course.courseId &&
                (q['classId'] ?? q['clazzId'] ?? q['clazzid']) ==
                    course.clazzId &&
                q['enc']?.isNotEmpty == true) {
              return target;
            }
          }
        }
        for (final key in [
          'navigationList',
          'courseNavigationListV3',
          'children'
        ]) {
          final found = findWork(node[key]);
          if (found != null) return found;
        }
      }
      return null;
    }

    final uri = _measureParse(
        '课程导航',
        () => payload is Map && payload['status'] == true
            ? findWork(payload)
            : null);
    if (kDebugMode) {
      debugPrint(
          '[SyncNavigation] status=${response?.statusCode} formalWorkLink=${uri != null}');
      final paths = <String>[];
      void shape(dynamic n) {
        if (n is List) {
          for (final child in n) {
            shape(child);
          }
        }
        if (n is Map) {
          if (n['linkUrl'] is String) {
            final u = Uri.tryParse(n['linkUrl']);
            if (u != null) {
              paths.add(u.path
                  .split('/')
                  .map((s) =>
                      RegExp(r'^[a-zA-Z][a-zA-Z0-9._-]{0,32}$').hasMatch(s)
                          ? s
                          : '*')
                  .join('/'));
            }
          }
          for (final key in [
            'navigationList',
            'courseNavigationListV3',
            'children',
            'data'
          ]) {
            shape(n[key]);
          }
        }
      }

      shape(payload);
      debugPrint(
          '[SyncNavShape] ok=${payload is Map ? payload['status'] : null} paths=${paths.join(',')}');
    }
    return uri;
  }

  // fanyav3 fetches homework separately from its exam and activity APIs.
  Future<List<Assignment>> _fetchV3FormalHomework(ChaoxingCourseRef course,
      {required int generation,
      _SyncProgressTracker? progress,
      Uri? verificationProbe}) async {
    final list = await _readV3FormalHomework(course,
        generation: generation,
        progress: progress,
        verificationProbe: verificationProbe);
    if (generation != _sessionGeneration) return const [];
    return _hydrateWorkDeadlines(list.rows,
        generation: generation,
        starts: list.starts,
        progress: progress,
        verificationProbe: verificationProbe);
  }

  Future<({List<Assignment> rows, Map<String, DateTime> starts})>
      _readV3FormalHomework(ChaoxingCourseRef course,
          {required int generation,
          _SyncProgressTracker? progress,
          String requestKind = '作业列表',
          Uri? verificationProbe}) async {
    final result = <Assignment>[];
    final starts = <String, DateTime>{};
    final seen = <String>{};
    final courseKey = '${course.courseId}:${course.clazzId}';
    try {
      for (var page = 1; page <= 100; page++) {
        final response = await _safeGet<dynamic>(
            'https://mooc1.chaoxing.com/mooc-ans/work/api/task',
            queryParameters: {
              'courseId': course.courseId,
              'classId': course.clazzId,
              'pageNum': page,
              'pageSize': 100
            },
            requestKind: requestKind,
            verificationProbe: verificationProbe,
            headers: {'User-Agent': courseUserAgent});
        if (generation != _sessionGeneration) {
          progress?.retractCourse(courseKey);
          return (
            rows: const <Assignment>[],
            starts: const <String, DateTime>{}
          );
        }
        final pageRows = <Assignment>[];
        final pageResult = _measureParse('作业列表', () {
          final payload = _decodeJsonPayload(response?.data);
          if (payload is! Map ||
              payload['status'] != true ||
              payload['data'] is! List) {
            throw SyncReadException(SyncIssue(
                SyncIssueKind.schemaChanged, '正式作业接口响应无法识别',
                stage: 'workList', httpStatus: response?.statusCode));
          }
          final rows = payload['data'] as List;
          final total = int.tryParse('${payload['total']}');
          if (total == null ||
              total < 0 ||
              result.length + rows.length > total) {
            throw const SyncReadException(SyncIssue(
                SyncIssueKind.schemaChanged, '正式作业总数与分页不匹配',
                stage: 'workList'));
          }
          if (kDebugMode) {
            debugPrint(
                '[SyncFormal] status=${response?.statusCode} page=$page rows=${rows.length} total=$total');
          }
          for (final row in rows) {
            if (row is! Map ||
                row['title'] is! String ||
                (row['title'] as String).trim().isEmpty) {
              throw const SyncReadException(SyncIssue(
                  SyncIssueKind.schemaChanged, '正式作业条目不完整',
                  stage: 'workList'));
            }
            var url = Uri.tryParse(
                '${row['taskUrl'] ?? ''}'.replaceAll('&amp;', '&'));
            if (url != null &&
                url.scheme == 'http' &&
                url.host.endsWith('.chaoxing.com')) {
              url = url.replace(scheme: 'https', port: 443);
            }
            final id = url?.queryParameters['workId'] ??
                url?.queryParameters['taskrefId'];
            final linkedCourse = url?.queryParameters['courseId'] ??
                url?.queryParameters['courseid'];
            final linkedClass = url?.queryParameters['classId'] ??
                url?.queryParameters['clazzId'] ??
                url?.queryParameters['clazzid'];
            if (url == null ||
                url.scheme != 'https' ||
                !url.host.endsWith('.chaoxing.com') ||
                id == null ||
                id.isEmpty ||
                !url.path.contains('/work/') ||
                (linkedCourse != null && linkedCourse != course.courseId) ||
                (linkedClass != null && linkedClass != course.clazzId)) {
              throw const SyncReadException(SyncIssue(
                  SyncIssueKind.schemaChanged, '正式作业详情身份无法确认',
                  stage: 'workList'));
            }
            if (!seen.add(id)) {
              throw const SyncReadException(SyncIssue(
                  SyncIssueKind.schemaChanged, '正式作业分页重复，请稍后重试',
                  stage: 'workList'));
            }
            final status = int.tryParse('${row['stuStatus']}');
            final evaluation = int.tryParse('${row['evaluation'] ?? 0}') ?? 0;
            // An explicit returned status is actionable even when the teacher
            // has already evaluated the previous submission. The evaluation
            // flag must not hide the student's need to resubmit.
            final state = status == 5
                ? 'returned'
                : evaluation != 0
                    ? (status == 4 ? 'completed' : 'unknown')
                    : switch (status) {
                        0 || 1 || 2 => 'pending',
                        3 => 'reviewing',
                        4 => 'completed',
                        5 => 'returned',
                        _ => 'unknown'
                      };
            final end = int.tryParse('${row['endTime']}');
            final start = int.tryParse('${row['startTime']}');
            if (start != null &&
                start >= 946684800000 &&
                start <= 4102444800000) {
              starts['cx:work:${course.courseId}:${course.clazzId}:$id'] =
                  DateTime.fromMillisecondsSinceEpoch(start, isUtc: true);
            }
            final trusted =
                end != null && (end >= 946684800000 && end <= 4102444800000);
            pageRows.add(Assignment(
                id: 'cx:work:${course.courseId}:${course.clazzId}:$id',
                courseName: course.courseName,
                title: (row['title'] as String).trim(),
                deadlineAt: trusted && end > 0
                    ? DateTime.fromMillisecondsSinceEpoch(end)
                    : null,
                deadlineTrusted: trusted,
                deadlineRawText: trusted ? end.toString() : null,
                // endTime=0 is not a confirmed no-deadline value. Keep the
                // observation untrusted so the same work's detail page can
                // resolve it, including for already-submitted rows.
                deadlineReadFailed: !trusted,
                requirementsText: '',
                status: state,
                submitUrl: url.toString(),
                lastSyncedAt: DateTime.now()));
          }
          return (rowCount: rows.length, total: total);
        });
        result.addAll(pageRows);
        // Identity, shape, duplicate, and cumulative total checks for this
        // page have passed. Publish only after them so a later failed page can
        // retract this course's rows without touching other courses or the
        // formal repository.
        if (pageRows.isNotEmpty) {
          progress?.addRows(pageRows, courseKey: courseKey);
        }
        if (result.length == pageResult.total) {
          return (rows: result, starts: starts);
        }
        if (pageResult.rowCount == 0) {
          _noteParseFailure('作业列表');
          throw const SyncReadException(SyncIssue(
              SyncIssueKind.schemaChanged, '正式作业总数与分页不匹配',
              stage: 'workList'));
        }
      }
      _noteParseFailure('作业列表');
      throw const SyncReadException(SyncIssue(
          SyncIssueKind.schemaChanged, '正式作业分页超出读取范围',
          stage: 'workList'));
    } catch (_) {
      // The course is still reported as partially failed by the caller, but
      // its unverified preview must not linger over the old formal cache.
      progress?.retractCourse(courseKey);
      rethrow;
    }
  }

  // Only forward the authenticated session within Chaoxing when the course
  // middle page redirects to the current deployment.
  Future<Response<dynamic>?> _courseGet(Uri uri,
      {int? generation, String? requestKind, Uri? verificationProbe}) async {
    final expectedGeneration = generation ?? _sessionGeneration;
    for (var i = 0; i < 5; i++) {
      // Some deployments still advertise HTTP in Location. Upgrade locally;
      // cookies and signed parameters must never travel over plaintext HTTP.
      if (uri.scheme == 'http' && uri.host.endsWith('.chaoxing.com')) {
        uri = uri.replace(scheme: 'https', port: 443);
      }
      if (uri.scheme != 'https' || !uri.host.endsWith('.chaoxing.com')) {
        return null;
      }
      final response = await _readCourseEntryOrGet(uri,
          generation: expectedGeneration,
          requestKind: requestKind,
          verificationProbe: verificationProbe);
      if (expectedGeneration != _sessionGeneration) return null;
      if (response == null || (response.statusCode ?? 0) < 300) {
        if (kDebugMode) {
          final route = uri.path
              .split('/')
              .map((s) => RegExp(r'^[a-zA-Z][a-zA-Z0-9._-]{0,32}$').hasMatch(s)
                  ? s
                  : '*')
              .join('/');
          debugPrint(
              '[SyncTerminal] host=${uri.host} route=$route status=${response?.statusCode}');
        }
        return response;
      }
      final location = response.headers.value('location');
      if (location == null || location.isEmpty) return null;
      if (kDebugMode) {
        final target = uri.resolve(location);
        debugPrint(
            '[SyncRedirect] legacyHttp=${target.scheme == 'http'} trusted=${target.host.endsWith('.chaoxing.com')}');
      }
      uri = uri.resolve(location);
    }
    return null;
  }

  // ---------- Shared ----------

  /// Share only a successful terminal credential page within one refresh. The
  /// callers still validate redirects independently; never cache a redirect,
  /// failed/missing credential response, or a page from a replaced session.
  static String _courseEntryCacheKey(Uri uri) {
    final keys = uri.queryParametersAll.keys.toList()..sort();
    return uri.replace(queryParameters: {
      for (final key in keys) key: uri.queryParametersAll[key]!,
    }).toString();
  }

  Future<Response<dynamic>?> _readCourseEntryOrGet(Uri uri,
      {required int generation,
      String? requestKind,
      Uri? verificationProbe}) async {
    final cache = _syncCourseEntries;
    final token = _activeRequestToken;
    final eligible = cache != null &&
        uri.scheme == 'https' &&
        ((uri.host == 'mooc1.chaoxing.com' &&
                uri.path == '/visit/stucoursemiddle') ||
            (uri.host == 'mooc2-ans.chaoxing.com' &&
                uri.path == '/mooc2-ans/mycourse/stu')) &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment &&
        uri.port == 443;
    // Canonicalize only parameter order, not identities or signature values.
    final key = _courseEntryCacheKey(uri);
    if (generation != _sessionGeneration ||
        _stopRequested ||
        token?.isCancelled == true) {
      return null;
    }
    if (eligible && cache.containsKey(key)) return cache[key];
    final response = await _safeGet<dynamic>(uri.toString(),
        headers: {'User-Agent': courseUserAgent},
        requestKind: requestKind,
        verificationProbe: verificationProbe);
    if (eligible &&
        identical(cache, _syncCourseEntries) &&
        identical(token, _activeRequestToken) &&
        !_stopRequested &&
        generation == _sessionGeneration &&
        response?.statusCode == 200) {
      final html = response?.data?.toString() ?? '';
      if (ChaoxingAssignmentParser.hiddenValue(html, 'workEnc')?.isNotEmpty ==
              true &&
          ChaoxingAssignmentParser.hiddenValue(html, 'examEnc')?.isNotEmpty ==
              true) {
        cache[key] = response!;
      }
    }
    return response;
  }

  SyncIssue _pausedRequestIssue(String kind, SyncIssue issue) => SyncIssue(
        issue.kind,
        '连续请求失败，已暂停本次刷新中的$kind请求',
        stage: issue.stage,
        elapsedMs: issue.elapsedMs,
        httpStatus: issue.httpStatus,
        retryAfter: issue.retryAfter,
        retryAfterSeconds: issue.retryAfterSeconds,
        circuitOpen: true,
      );

  Future<Response<T>?> _safeGet<T>(
    String uri, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    String? requestKind,
    String method = 'GET',
    Map<String, dynamic>? form,
    Uri? verificationProbe,
  }) async {
    final parsedUri = Uri.parse(uri);
    final kind = requestKind ?? _requestKind(parsedUri.path);
    final generation = _sessionGeneration;
    var attempt = 0;
    while (true) {
      if (_stopRequested) {
        throw const SyncReadException(SyncIssue(
          SyncIssueKind.cancelled,
          '本次同步已取消',
          stage: 'request',
        ));
      }
      if (generation != _sessionGeneration) return null;
      // The exam collector stops the group immediately once its circuit opens.
      final reportExamCircuit = kind == '课程考试' || kind == '课程考试补充';
      final circuit = _openCircuits[kind];
      if (circuit != null) {
        throw SyncReadException(_pausedRequestIssue(kind, circuit));
      }
      attempt++;
      final watch = Stopwatch()..start();
      Response<T>? response;
      DioException? transportError;
      try {
        // ResponseType.plain keeps Dio's JSON transformer out of the measured
        // network window; JSON/HTML parsing is measured separately below.
        response = await _dio.request<T>(
          uri,
          queryParameters: queryParameters,
          data: form,
          options: Options(
            method: method,
            contentType:
                form == null ? null : Headers.formUrlEncodedContentType,
            responseType: ResponseType.plain,
            validateStatus: (status) => status != null,
            headers: _headers(parsedUri, headers),
          ),
          cancelToken: _activeRequestToken,
        );
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) {
          if (_stopRequested) {
            throw const SyncReadException(SyncIssue(
              SyncIssueKind.cancelled,
              '本次同步已取消',
              stage: 'request',
            ));
          }
          if (generation != _sessionGeneration) return null;
          throw const SyncReadException(
            SyncIssue(
              SyncIssueKind.network,
              '后台作业检查已取消',
              stage: 'request',
            ),
          );
        }
        transportError = error;
      }
      final httpElapsedMs = watch.elapsedMilliseconds;
      if (generation != _sessionGeneration) return null;
      if (transportError != null) {
        final failure = _networkFailure(transportError, kind);
        _recordHttp(kind, httpElapsedMs, failed: true);
        final opened = _registerTransientFailure(kind, failure);
        final delay =
            _retryDelay(kind, attempt, failure, circuitOpened: opened);
        if (delay != null) {
          _syncRetryCount++;
          await _waitOrCancel(delay);
          continue;
        }
        throw SyncReadException(opened && reportExamCircuit
            ? _pausedRequestIssue(kind, failure.issue)
            : failure.issue);
      }
      final received = response!;
      _rememberCookies(received);
      final parseWatch = Stopwatch()..start();
      _ResponseOutcome outcome;
      try {
        outcome = _evaluateResponse(received, parsedUri, kind,
            verificationProbe: verificationProbe);
      } catch (_) {
        outcome = _ResponseOutcome.issue(SyncIssue(
            SyncIssueKind.schemaChanged, '学习通响应无法解析，请稍后重试',
            stage: _stageForKind(kind), httpStatus: received.statusCode));
      }
      final parseElapsedMs = parseWatch.elapsedMilliseconds;
      final status = received.statusCode ?? 0;
      final httpFailed = status < 200 || status >= 400;
      _recordHttp(
        kind,
        httpElapsedMs,
        failed: httpFailed,
        parseElapsedMs: parseElapsedMs,
        parseFailed:
            !httpFailed && (outcome.auth != null || outcome.issue != null),
      );
      if (outcome.auth != null) {
        _consecutiveTransientFailures.remove(kind);
        throw outcome.auth!;
      }
      final issue = outcome.issue;
      if (issue != null) {
        final failure = _AttemptFailure(
          issue,
          transient: _isTransient(issue),
          retryAfter: outcome.retryAfter,
        );
        final opened = _registerTransientFailure(kind, failure);
        final delay =
            _retryDelay(kind, attempt, failure, circuitOpened: opened);
        if (delay != null) {
          _syncRetryCount++;
          await _waitOrCancel(delay);
          continue;
        }
        throw SyncReadException(opened && reportExamCircuit
            ? _pausedRequestIssue(kind, issue)
            : issue);
      }
      _consecutiveTransientFailures.remove(kind);
      return received;
    }
  }

  _ResponseOutcome _evaluateResponse(
      Response<dynamic> response, Uri uri, String kind,
      {Uri? verificationProbe}) {
    final status = response.statusCode ?? 0;
    final stage = _stageForKind(kind);
    final location = response.headers.value('location') ?? '';
    final body = response.data is String ? response.data as String : '';
    final payload = _decodeJsonPayload(response.data);
    final message = payload is Map
        ? (payload['msg'] ?? payload['message'] ?? '').toString()
        : '';
    if (payload is Map &&
        (payload['result'] == false || payload['status'] == false) &&
        RegExp(r'未登录|请先登录|登录已失效|登录失效|登录超时|login required|unauthorized',
                caseSensitive: false)
            .hasMatch(message)) {
      return _ResponseOutcome.auth(ChaoxingAuthenticationException(status));
    }
    if (status == 401 ||
        (status >= 300 &&
            status < 400 &&
            (location.contains('passport2') || location.contains('/login'))) ||
        (body.contains('<html') &&
            (body.contains('请登录') ||
                body.contains('passport2.chaoxing.com/login')))) {
      return _ResponseOutcome.auth(ChaoxingAuthenticationException(status));
    }
    if (status == 403 || status == 404 || status == 429 || status >= 500) {
      final retryAfterRaw = response.headers.value('retry-after');
      final retryAfter = _parseRetryAfter(retryAfterRaw);
      return _ResponseOutcome.issue(
          _httpIssue(status, kind,
              retryAfterRaw: retryAfterRaw, retryAfter: retryAfter),
          retryAfter: retryAfter);
    }
    // Shared course scripts include captcha libraries even without a challenge.
    // Inspect visible text, never library names or hidden script configuration.
    final visible = examListChallengeBody(
        body.replaceAll(
            RegExp(r'<(script|style)\b[^>]*>[\s\S]*?</\1>',
                caseSensitive: false),
            ''),
        uri: uri,
        requestKind: kind == '课程考试补充' ? '课程考试' : kind);
    final challenge = RegExp(
                r'请输入验证码|请完成.{0,12}(?:验证|校验)|安全验证|访问异常|人机验证|verify\.chaoxing',
                caseSensitive: false)
            .hasMatch(_stripTags(visible)) ||
        location.contains('antispider');
    if (kDebugMode && uri.path.contains('stucoursemiddle')) {
      debugPrint(
          '[SyncShape] stage=coursePage status=$status workEnc=${ChaoxingAssignmentParser.hiddenValue(body, 'workEnc') != null} captchaLibrary=${body.toLowerCase().contains('captcha')} challenge=$challenge');
    }
    if (challenge) {
      _verificationTarget ??= verificationProbe ?? uri;
      return _ResponseOutcome.issue(SyncIssue(
          SyncIssueKind.verificationRequired, '学习通要求人工验证，请点击完成安全验证',
          stage: stage, httpStatus: status));
    }
    if (status >= 200 && status < 400) {
      return const _ResponseOutcome.success();
    }
    return _ResponseOutcome.issue(SyncIssue(
        SyncIssueKind.network, '接口返回 HTTP $status，请稍后重试',
        stage: stage, httpStatus: status));
  }

  SyncIssue _httpIssue(int status, String kind,
      {String? retryAfterRaw, Duration? retryAfter}) {
    final stage = _stageForKind(kind);
    if (status == 403) {
      return SyncIssue(SyncIssueKind.forbidden, '接口拒绝访问，请稍后重试',
          stage: stage, httpStatus: status);
    }
    if (status == 404) {
      return SyncIssue(SyncIssueKind.notFound, '请求的学习通内容不存在（HTTP 404）',
          stage: stage, httpStatus: status);
    }
    if (status == 429) {
      return SyncIssue(SyncIssueKind.rateLimited, '学习通请求过于频繁，请稍后重试',
          stage: stage,
          httpStatus: status,
          retryAfter: retryAfterRaw,
          retryAfterSeconds: retryAfter?.inSeconds);
    }
    if (status >= 500) {
      return SyncIssue(
          SyncIssueKind.serverError, '学习通服务暂时不可用（HTTP $status），请稍后重试',
          stage: stage,
          httpStatus: status,
          retryAfter: retryAfterRaw,
          retryAfterSeconds: retryAfter?.inSeconds);
    }
    if (status == 408 || status == 425) {
      return SyncIssue(SyncIssueKind.network, '学习通请求超时（HTTP $status），请稍后重试',
          stage: stage, httpStatus: status);
    }
    return SyncIssue(SyncIssueKind.network, '接口返回 HTTP $status，请稍后重试',
        stage: stage, httpStatus: status);
  }

  _AttemptFailure _networkFailure(DioException error, String kind) {
    final response = error.response;
    if (response != null && response.statusCode != null) {
      final status = response.statusCode!;
      final retryAfterRaw = response.headers.value('retry-after');
      final retryAfter = _parseRetryAfter(retryAfterRaw);
      final issue = _httpIssue(status, kind,
          retryAfterRaw: retryAfterRaw, retryAfter: retryAfter);
      return _AttemptFailure(issue,
          transient: _isTransient(issue), retryAfter: retryAfter);
    }
    final transient = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError ||
      DioExceptionType.unknown =>
        true,
      _ => false,
    };
    return _AttemptFailure(
      SyncIssue(
        SyncIssueKind.network,
        transient ? '连接学习通失败，请稍后重试' : '学习通网络请求未能完成',
        stage: _stageForKind(kind),
      ),
      transient: transient,
    );
  }

  bool _isTransient(SyncIssue issue) {
    if (issue.kind == SyncIssueKind.serverError ||
        issue.kind == SyncIssueKind.rateLimited) {
      return true;
    }
    if (issue.kind == SyncIssueKind.network) {
      final status = issue.httpStatus;
      return status == null || status == 408 || status == 425;
    }
    return false;
  }

  Duration? _parseRetryAfter(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final seconds = int.tryParse(value);
    if (seconds != null) {
      return seconds < 0 ? null : Duration(seconds: seconds);
    }
    try {
      final target = HttpDate.parse(value).toUtc();
      final wait = target.difference(DateTime.now().toUtc());
      return wait.isNegative ? Duration.zero : wait;
    } catch (_) {
      return null;
    }
  }

  String _stageForKind(String kind) => switch (kind) {
        '课程列表' => 'courses',
        '课程入口' => 'coursePage',
        '课程导航' || '作业列表' => 'workList',
        '作业详情' || '截止时间佐证' => 'detail',
        '课程考试' || '课程考试补充' => 'exam',
        '账号考试' => 'examAccount',
        '考试通知' => 'examNotice',
        '课程通知' => 'courseNotice',
        '章节进度' => 'chapters',
        '任务引擎探测' => 'taskEnginePlan',
        '课堂活动列表' || '个人分组任务' || '随堂练习' || 'AI实践' => 'classroom',
        _ => 'courses',
      };

  Map<String, String> _headers(Uri uri, [Map<String, String>? extra]) {
    _cookies.removeWhere((c) => c.expired);
    final matching = _cookies.where((c) => c.matches(uri)).toList()
      ..sort((a, b) => b.path.length.compareTo(a.path.length));
    return {
      if (matching.isNotEmpty)
        'Cookie': matching
            .map((c) => '${c.cookie.name}=${c.cookie.value}')
            .join('; '),
      if (extra != null) ...extra,
    };
  }

  void _rememberCookies(Response<dynamic> response) {
    final origin = response.requestOptions.uri;
    for (final raw in response.headers['set-cookie'] ?? const <String>[]) {
      try {
        final cookie = Cookie.fromSetCookieValue(raw);
        final domain = (cookie.domain ?? origin.host)
            .replaceFirst(RegExp(r'^\.'), '')
            .toLowerCase();
        if (domain != origin.host && !origin.host.endsWith('.$domain')) {
          continue;
        }
        if (domain != 'chaoxing.com' && !domain.endsWith('.chaoxing.com')) {
          continue;
        }
        final defaultPath =
            origin.path.substring(0, origin.path.lastIndexOf('/') + 1);
        final path = cookie.path?.startsWith('/') == true
            ? cookie.path!
            : (defaultPath.length > 1
                ? defaultPath.substring(0, defaultPath.length - 1)
                : '/');
        final entry =
            _SessionCookie(cookie, domain, path, cookie.domain == null);
        _cookies.removeWhere((c) =>
            c.cookie.name == cookie.name &&
            c.domain == domain &&
            c.path == path);
        if (!entry.expired) _cookies.add(entry);
      } on FormatException {
        // A malformed Set-Cookie must not invalidate the entire login response.
      }
    }
  }

  String? _readCookie(String name) {
    for (final entry in _cookies.reversed) {
      if (!entry.expired && entry.cookie.name == name) {
        return entry.cookie.value;
      }
    }
    return null;
  }

  List<Assignment> _dedupeAssignments(List<Assignment> assignments) {
    final byId = <String, Assignment>{};
    for (final assignment in assignments) {
      byId[assignment.id] = assignment;
    }
    return byId.values.toList()..sort(Assignment.compareByDeadline);
  }

  String? _extractMessage(dynamic payload) {
    if (payload is! Map) return null;
    for (final key in const ['mes', 'msg', 'msg2', 'message', 'errorMsg']) {
      final value = payload[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  Future<_ChaoxingProfile> _completeLoginSession(dynamic payload) async {
    final redirectUrl = _extractLoginRedirectUrl(payload);
    final uri = Uri.tryParse(redirectUrl ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        !(uri.host == 'chaoxing.com' || uri.host.endsWith('.chaoxing.com'))) {
      return const _ChaoxingProfile();
    }
    final response = await _courseGet(uri);
    return _extractProfile(response?.data, useCookieAvatar: false);
  }

  Future<_ChaoxingProfile> _fetchProfile(
    dynamic loginPayload,
    _ChaoxingProfile sessionProfile,
  ) async {
    final fromLogin = _extractProfile(loginPayload);
    final fallback = _ChaoxingProfile(
      displayName: sessionProfile.displayName ?? fromLogin.displayName,
      avatarUrl: sessionProfile.avatarUrl ?? fromLogin.avatarUrl,
    );
    final candidates = ['https://i.chaoxing.com/base'];
    for (final uri in candidates) {
      final response = await _safeGet<dynamic>(
        uri,
        headers: {'Accept': 'application/json,text/html,*/*'},
      );
      final status = response?.statusCode ?? 0;
      final fromResponse = response == null || status < 200 || status >= 300
          ? const _ChaoxingProfile()
          : _extractProfile(response.data, useCookieAvatar: false);
      final merged = _ChaoxingProfile(
        displayName: fromResponse.displayName ?? fallback.displayName,
        avatarUrl: fromResponse.avatarUrl ?? fallback.avatarUrl,
      );
      if (merged.displayName != null || merged.avatarUrl != null) {
        return merged;
      }
    }
    return fallback;
  }

  _ChaoxingProfile _extractProfile(
    dynamic payload, {
    bool useCookieAvatar = true,
  }) {
    final decoded = _decodeJsonPayload(payload);
    final displayName = _extractDisplayName(decoded);
    final avatarFromPayload = _extractAvatarUrl(decoded);
    return _ChaoxingProfile(
      displayName: displayName,
      avatarUrl: avatarFromPayload ??
          (useCookieAvatar ? _avatarUrlFromCookie() : null),
    );
  }

  dynamic _decodeJsonPayload(dynamic payload) {
    if (payload is! String) {
      return payload;
    }
    final trimmed = payload.trim();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
      return payload;
    }
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return payload;
    }
  }

  String? _extractLoginRedirectUrl(dynamic payload) {
    final decoded = _decodeJsonPayload(payload);
    if (decoded is Map) {
      for (final key in ['url', 'loginUrl', 'redirectUrl', 'location']) {
        final normalized = _normalizeUrl(decoded[key]?.toString());
        if (normalized != null) {
          return normalized;
        }
      }
    }
    final body = payload?.toString() ?? '';
    final match = RegExp(
      r'"(?:url|loginUrl|redirectUrl|location)"\s*:\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(body);
    return _normalizeUrl(match?.group(1));
  }

  String? _extractDisplayName(dynamic payload) {
    final direct = _extractDisplayNameFromJson(payload);
    if (direct != null) {
      return direct;
    }
    final body = payload?.toString() ?? '';
    if (body.isEmpty) {
      return null;
    }
    final userNameElement = RegExp(
      r'''class=["'][^"']*user-name[^"']*["'][^>]*>(.*?)</[^>]+>''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(body);
    final fromElement =
        _normalizeDisplayName(_stripTags(userNameElement?.group(1)));
    if (fromElement != null) {
      return fromElement;
    }
    final jsonLike = RegExp(
      r'"(?:realName|realname|name|nickName|nickname|uname|userName|username)"\s*:\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(body);
    return _normalizeDisplayName(jsonLike?.group(1));
  }

  String? _extractDisplayNameFromJson(dynamic payload) {
    if (payload is Map) {
      final candidates = [
        payload['realName'],
        payload['realname'],
        payload['name'],
        payload['nickName'],
        payload['nickname'],
        payload['uname'],
        payload['userName'],
        payload['username'],
      ];
      for (final candidate in candidates) {
        final normalized = _normalizeDisplayName(candidate?.toString());
        if (normalized != null) {
          return normalized;
        }
      }
      for (final key in ['msg', 'data', 'user', 'userInfo', 'accountInfo']) {
        final nested = _extractDisplayNameFromJson(payload[key]);
        if (nested != null) {
          return nested;
        }
      }
    }
    if (payload is List) {
      for (final item in payload) {
        final nested = _extractDisplayNameFromJson(item);
        if (nested != null) {
          return nested;
        }
      }
    }
    return null;
  }

  String? _extractAvatarUrl(dynamic payload) {
    final direct = _extractAvatarUrlFromJson(payload);
    if (direct != null) {
      return direct;
    }
    final body = payload?.toString() ?? '';
    if (body.isEmpty) {
      return null;
    }
    final imageLike = RegExp(
      r'''(?:avatar|avatarUrl|avatarurl|photo|photoUrl|pic|picUrl|headPic|headimgurl)["']?\s*[:=]\s*["']?([^"',}\s]+)''',
      caseSensitive: false,
    ).firstMatch(body);
    return _normalizeUrl(imageLike?.group(1));
  }

  String? _extractAvatarUrlFromJson(dynamic payload) {
    if (payload is Map) {
      final candidates = [
        payload['avatar'],
        payload['avatarUrl'],
        payload['avatarurl'],
        payload['photo'],
        payload['photoUrl'],
        payload['pic'],
        payload['picUrl'],
        payload['headPic'],
        payload['headimgurl'],
      ];
      for (final candidate in candidates) {
        final normalized = _normalizeUrl(candidate?.toString());
        if (normalized != null) {
          return normalized;
        }
      }
      final puidAvatar = _avatarUrlFromId(payload['puid']);
      if (puidAvatar != null) {
        return puidAvatar;
      }
      final uidAvatar = _avatarUrlFromId(
        payload['uid'] ?? payload['UID'] ?? payload['_uid'],
      );
      if (uidAvatar != null) {
        return uidAvatar;
      }
      for (final key in ['msg', 'data', 'user', 'userInfo', 'accountInfo']) {
        final nested = _extractAvatarUrlFromJson(payload[key]);
        if (nested != null) {
          return nested;
        }
      }
    }
    if (payload is List) {
      for (final item in payload) {
        final nested = _extractAvatarUrlFromJson(item);
        if (nested != null) {
          return nested;
        }
      }
    }
    return null;
  }

  String? _normalizeDisplayName(String? value) {
    final normalized = _decodeHtmlEntities(value ?? '').trim();
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized.contains('@') || normalized.length > 24) {
      return null;
    }
    return normalized;
  }

  String? _avatarUrlFromCookie() {
    final id = _readCookie('puid') ??
        _readCookie('PUID') ??
        _readCookie('sso_puid') ??
        _readCookie('UID') ??
        _readCookie('uid') ??
        _readCookie('_uid');
    return _avatarUrlFromId(id);
  }

  String? _avatarUrlFromId(Object? id) {
    final raw = id?.toString().trim();
    if (raw == null || raw.isEmpty || !RegExp(r'^\d+$').hasMatch(raw)) {
      return null;
    }
    return 'https://photo.chaoxing.com/p/${Uri.encodeComponent(raw)}_160?ts=$raw';
  }

  Future<String?> _resolveAvatarUrl(String? avatarUrl) async {
    final normalized = _normalizeChaoxingAvatarUrl(avatarUrl);
    if (normalized == null ||
        !normalized.startsWith('https://photo.chaoxing.com/')) {
      return normalized;
    }
    try {
      final response = await _dio.get<dynamic>(
        normalized,
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && status < 400,
          headers: _headers(Uri.parse(normalized),
              {'Accept': 'image/avif,image/webp,image/apng,image/*,*/*'}),
        ),
        cancelToken: _activeRequestToken,
      );
      final location = response.headers.value('location');
      return _normalizeUrl(location) ?? normalized;
    } catch (_) {
      return normalized;
    }
  }

  String? _normalizeChaoxingAvatarUrl(String? avatarUrl) {
    final normalized = _normalizeUrl(avatarUrl);
    if (normalized == null ||
        !normalized.startsWith('https://photo.chaoxing.com/')) {
      return normalized;
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      return normalized;
    }
    final query = Map<String, String>.from(uri.queryParameters)
      ..['psize'] = '160_160c'
      ..['ext'] = 'png';
    return uri.replace(queryParameters: query).toString();
  }

  String? _normalizeUrl(String? value) {
    var normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    normalized = normalized.replaceAll(r'\/', '/');
    if (normalized.startsWith('//')) {
      return 'https:$normalized';
    }
    if (normalized.startsWith('http://')) {
      return normalized.replaceFirst('http://', 'https://');
    }
    if (!normalized.startsWith('https://')) {
      return null;
    }
    return normalized;
  }

  String _stripTags(String? html) {
    if (html == null || html.isEmpty) {
      return '';
    }
    return html.replaceAll(RegExp(r'<[^>]+>'), ' ');
  }

  String _decodeHtmlEntities(String value) {
    return value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }
}

class _SyncProgressTracker {
  _SyncProgressTracker(this.onProgress);

  final void Function(AssignmentSyncProgress) onProgress;
  final Map<String, Assignment> assignments = {};
  final Set<String> pendingDetailIds = {};
  final Set<String> _unconfirmedIds = {};
  final Map<String, Set<String>> _courseRowIds = {};
  AssignmentSyncStage stage = AssignmentSyncStage.courses;
  int resolvedCount = 0;
  int attemptedCount = 0;
  int workListFailureCount = 0;

  void setStage(AssignmentSyncStage value) {
    stage = value;
    _emit();
  }

  void setWorkListFailureCount(int value) {
    workListFailureCount = value;
  }

  void addRows(List<Assignment> rows, {String? courseKey}) {
    for (final assignment in rows) {
      assignments[assignment.id] = assignment;
      if (courseKey != null) {
        (_courseRowIds[courseKey] ??= <String>{}).add(assignment.id);
      }
    }
    if (stage == AssignmentSyncStage.courses) {
      stage = AssignmentSyncStage.workLists;
    }
    _emit();
  }

  /// Withdraws this round's preview rows and pending details for one course.
  ///
  /// Used when a later V3 page fails validation after earlier pages were
  /// already published. Other courses' preview rows and the formal repository
  /// are untouched; the retraction is emitted as one consistent snapshot.
  void retractCourse(String courseKey) {
    final ids = _courseRowIds.remove(courseKey);
    if (ids == null || ids.isEmpty) return;
    for (final id in ids) {
      assignments.remove(id);
      pendingDetailIds.remove(id);
      _unconfirmedIds.remove(id);
    }
    _emit();
  }

  void beginDetails(List<Assignment> rows) {
    pendingDetailIds
      ..clear()
      ..addAll(rows
          .where((item) =>
              !item.isCompleted &&
              !(item.deadlineTrusted && item.deadlineAt != null))
          .map((item) => item.id));
    stage = AssignmentSyncStage.details;
    _emit();
  }

  void attempt(String id) {
    pendingDetailIds.add(id);
    attemptedCount++;
    _emit();
  }

  void replace(Assignment assignment) {
    assignments[assignment.id] = assignment;
    _emit();
  }

  void resolve(String id, Assignment assignment) {
    assignments[id] = assignment;
    pendingDetailIds.remove(id);
    if (assignment.deadlineReadFailed) {
      _unconfirmedIds.add(id);
    } else {
      _unconfirmedIds.remove(id);
    }
    resolvedCount++;
    _emit();
  }

  void clearPending() {
    if (pendingDetailIds.isEmpty) return;
    pendingDetailIds.clear();
    _emit();
  }

  void _emit() {
    final ordered = assignments.values.toList()
      ..sort((a, b) {
        final ids = a.id.compareTo(b.id);
        return ids;
      });
    onProgress(AssignmentSyncProgress(
      stage: stage,
      assignments: ordered,
      pendingDetailIds: pendingDetailIds,
      resolvedCount: resolvedCount,
      attemptedCount: attemptedCount,
      unconfirmedCount: _unconfirmedIds.length,
      workListFailureCount: workListFailureCount,
    ));
  }
}

class _ChaoxingProfile {
  const _ChaoxingProfile({this.displayName, this.avatarUrl});

  final String? displayName;
  final String? avatarUrl;
}

class _RequestStats {
  int count = 0;
  int failures = 0;
  int parseFailures = 0;
  final List<int> httpSamples = [];
  final List<int> parseSamples = [];

  int get totalHttpMs => httpSamples.fold(0, (sum, value) => sum + value);
  int get totalParseMs => parseSamples.fold(0, (sum, value) => sum + value);
}

class _AttemptFailure {
  const _AttemptFailure(this.issue, {required this.transient, this.retryAfter});

  final SyncIssue issue;
  final bool transient;
  final Duration? retryAfter;
}

class _ResponseOutcome {
  const _ResponseOutcome.success()
      : auth = null,
        issue = null,
        retryAfter = null;

  const _ResponseOutcome.auth(this.auth)
      : issue = null,
        retryAfter = null;

  const _ResponseOutcome.issue(this.issue, {this.retryAfter}) : auth = null;

  final ChaoxingAuthenticationException? auth;
  final SyncIssue? issue;
  final Duration? retryAfter;
}

class _SessionCookie {
  _SessionCookie(this.cookie, this.domain, this.path, this.hostOnly)
      : expires = cookie.maxAge == null
            ? cookie.expires
            : DateTime.now().add(Duration(seconds: cookie.maxAge!));
  final Cookie cookie;
  final String domain;
  final String path;
  final bool hostOnly;
  final DateTime? expires;
  bool get expired => expires != null && !expires!.isAfter(DateTime.now());
  bool matches(Uri uri) =>
      !expired &&
      (!cookie.secure || uri.scheme == 'https') &&
      (uri.host == domain || (!hostOnly && uri.host.endsWith('.$domain'))) &&
      (uri.path == path ||
          (uri.path.startsWith(path) &&
              (path.endsWith('/') ||
                  uri.path.substring(path.length).startsWith('/'))));
}

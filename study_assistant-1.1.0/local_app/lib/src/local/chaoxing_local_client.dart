import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/assignment.dart';
import '../models/assignment_sync_progress.dart';
import '../models/sync_report.dart';
import 'chaoxing_api_parser.dart';
import 'chaoxing_assignment_parser.dart';

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
  ChaoxingLocalClient({Dio? dio, Future<void> Function(Duration)? wait})
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
  final Future<void> Function(Duration) _wait;
  CancelToken? _activeRequestToken;
  static Future<void> _defaultWait(Duration delay) =>
      Future<void>.delayed(delay);

  final _requestStats = <String, _RequestStats>{};
  final _openCircuits = <String, SyncIssue>{};
  final _consecutiveTransientFailures = <String, int>{};
  int _syncRetryCount = 0;
  int? _fullSyncElapsedMs;
  bool Function()? shouldStop;
  void Function(AssignmentSyncProgress)? onProgress;

  void cancelActiveRequests() {
    _activeRequestToken?.cancel('主动停止后台学习通请求');
    _activeRequestToken = null;
    _sessionGeneration++;
  }

  CancelToken _startRequestToken() {
    _activeRequestToken?.cancel('开始新的学习通请求');
    return _activeRequestToken = CancelToken();
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
    if (path.contains('stucoursemiddle')) return '课程入口';
    if (path.contains('stu-base-info')) return '课程导航';
    if (path.endsWith('/work/list') || path.endsWith('/work/api/task')) {
      return '作业列表';
    }
    if (path.contains('/work/')) return '作业详情';
    return '其他';
  }

  void _resetSyncTracking({required bool clearRequestStats}) {
    if (clearRequestStats) _requestStats.clear();
    _openCircuits.clear();
    _consecutiveTransientFailures.clear();
    _syncRetryCount = 0;
    _fullSyncElapsedMs = null;
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

  Future<bool> verifyInBrowser() async {
    final generation = _sessionGeneration;
    final target = _verificationTarget ?? _courseVerificationProbe;
    if (target == null) throw StateError('请先刷新作业以确认需要验证的页面');
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
    // clearing cookies and generation. Otherwise a late response could keep
    // running after logout even though its result is discarded.
    cancelActiveRequests();
    _resetSyncTracking(clearRequestStats: true);
    _sessionGeneration++;
    _cookies.clear();
    _loginPayload = null;
    courses = [];
    hasCourseResponse = false;
    issues = [];
    succeededCourses = 0;
    failedCourses = 0;
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
    final body = response.data?.toString() ?? '';
    final payload = _decodeJsonPayload(response.data);
    final success = payload is Map &&
        (payload['status'] == true || payload['result'] == true);
    if (!success) {
      return ChaoxingLoginResult(
        success: false,
        message: _extractMessage(body) ?? '学习通登录失败，请检查账号和密码',
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
    issues = [];
    _deadlineReadsBlockedBy = null;
    try {
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
      final course = refs
          .where((c) => c.courseId == courseId && c.clazzId == clazzId)
          .firstOrNull;
      if (course == null) {
        _noteParseFailure('课程列表');
        throw const SyncReadException(SyncIssue(
            SyncIssueKind.notFound, '目标课程暂时无法读取，请刷新作业后重试',
            stage: 'courses'));
      }
      final rows = await _fetchCourseWork(course, generation: generation);
      if (generation != _sessionGeneration) return const [];
      if (rows == null) {
        final issue = issues.isNotEmpty
            ? issues.first
            : const SyncIssue(SyncIssueKind.schemaChanged, '本次未能读取目标课程作业',
                stage: 'work');
        throw SyncReadException(issue);
      }
      return _dedupeAssignments(rows);
    } finally {
      if (generation == _sessionGeneration) {
        _fullSyncElapsedMs = syncWatch.elapsedMilliseconds;
      }
    }
  }

  Future<List<Assignment>> fetchAssignments() async {
    _startRequestToken();
    final generation = _sessionGeneration;
    final syncWatch = Stopwatch()..start();
    _resetSyncTracking(clearRequestStats: true);
    final progress =
        onProgress == null ? null : _SyncProgressTracker(onProgress!);
    progress?.setStage(AssignmentSyncStage.courses);
    lastSyncWarning = null;
    _deadlineReadsBlockedBy = null;
    issues = [];
    hasCourseResponse = false;
    succeededCourses = 0;
    failedCourses = 0;
    try {
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
        final refs = ChaoxingApiParser.parseCourseRefs(payload);
        return (payload: payload, raw: raw, refs: refs);
      });
      final payload = parsedCourses.payload;
      final raw = parsedCourses.raw;
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
      if (raw.length != courses.length) {
        failedCourses = raw.length - courses.length;
        issues.add(const SyncIssue(SyncIssueKind.schemaChanged, '部分课程结构无法识别'));
        problems.add('部分课程无法识别');
      }
      final assignments = <Assignment>[];
      var recognized = courses.isEmpty;
      for (final course in courses) {
        if (shouldStop?.call() == true) {
          failedCourses += courses.length - succeededCourses;
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
          if (generation != _sessionGeneration) return const [];
          failure = e.issue;
        } catch (_) {
          if (generation != _sessionGeneration) return const [];
          failure = const SyncIssue(SyncIssueKind.schemaChanged, '作业响应无法识别');
        }
        final label = '${course.courseName}（班级 ${course.clazzId}）';
        if (work == null) {
          failedCourses++;
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
            failedCourses = courses.length - succeededCourses;
            break;
          }
        } else {
          recognized = true;
          succeededCourses++;
          assignments.addAll(work);
          if (work.any((a) => a.deadlineReadFailed)) {
            failedCourses++;
            issues.add(SyncIssue(SyncIssueKind.partial, '$label 部分截止时间尚未确认',
                courseKey: '${course.courseId}:${course.clazzId}',
                stage: 'detail',
                elapsedMs: watch.elapsedMilliseconds));
            problems.add('$label 部分截止时间未读取');
          }
        }
        if (_deadlineReadsBlockedBy != null) {
          final unread = courses.length - courses.indexOf(course) - 1;
          if (unread > 0) {
            issues.add(SyncIssue(
                _deadlineReadsBlockedBy!, '本次读取已暂停，另有 $unread 门课程尚未更新',
                stage: 'workList'));
          }
          failedCourses = courses.length - succeededCourses + 1;
          break;
        }
      }
      if (problems.isNotEmpty) {
        lastSyncWarning = '已更新 $succeededCourses 门课程，$failedCourses 门待重试';
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
      if (generation == _sessionGeneration) {
        _fullSyncElapsedMs = syncWatch.elapsedMilliseconds;
      }
    }
  }

  Future<List<Assignment>?> _fetchCourseWork(ChaoxingCourseRef course,
      {required int generation, _SyncProgressTracker? progress}) async {
    final courseUri =
        Uri.https('mooc1.chaoxing.com', '/visit/stucoursemiddle', {
      'courseid': course.courseId,
      'clazzid': course.clazzId,
      if (course.cpi != null) 'cpi': course.cpi!,
      'ismooc2': '1',
      'v': '2',
    });
    _courseVerificationProbe = courseUri;
    if (_v3FormalApiConfirmed) {
      return _fetchV3FormalHomework(course,
          generation: generation, progress: progress);
    }
    final middle = await _courseGet(courseUri, generation: generation);
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
    final workEnc = middlePage.workEnc;
    if (kDebugMode) {
      debugPrint(
          '[SyncCourse] status=${middle?.statusCode} signed=${workEnc?.isNotEmpty == true} vue=${html.contains('/mooc2-ans-vue/')}');
    }
    final navigationUri =
        (workEnc == null || workEnc.isEmpty) && html.contains('/mooc2-ans-vue/')
            ? await _fetchNavigationWorkUri(course, generation: generation)
            : null;
    if (generation != _sessionGeneration) return null;
    if ((workEnc == null || workEnc.isEmpty) &&
        navigationUri == null &&
        html.contains('/mooc2-ans-vue/')) {
      final work = await _fetchV3FormalHomework(course,
          generation: generation, progress: progress);
      if (generation != _sessionGeneration) return null;
      _v3FormalApiConfirmed = true;
      return work;
    }
    if ((workEnc == null || workEnc.isEmpty) && navigationUri == null) {
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
    final list = await _courseGet(uri, generation: generation);
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
        generation: generation, progress: progress);
  }

  Future<List<Assignment>> _hydrateWorkDeadlines(List<Assignment> rows,
      {required int generation,
      _SyncProgressTracker? progress,
      Map<String, DateTime> starts = const {}}) async {
    final result = <Assignment>[];
    progress?.beginDetails(rows);
    for (final item in rows) {
      if (item.isCompleted) {
        final prior = previousAssignments[item.id];
        final completed = item.copyWith(
            deadlineAt: item.deadlineAt ?? prior?.deadlineAt,
            deadlineTrusted:
                item.deadlineAt != null || prior?.deadlineTrusted == true,
            deadlineRawText: prior?.deadlineRawText);
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
      if (_deadlineReadsBlockedBy == null) {
        progress?.attempt(item.id);
        final watch = Stopwatch()..start();
        try {
          final response = await _courseGet(Uri.parse(item.submitUrl!),
              generation: generation);
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
                  startedAt: starts[item.id]),
            );
          });
          evidence = detail.evidence;
          if (kDebugMode) {
            debugPrint(
                '[DeadlineRead] status=${response?.statusCode} bytes=${detail.body.length} startAnchor=${starts.containsKey(item.id)} exact=${evidence.deadlineAt != null} noLimit=${evidence.noLimit} missingYear=${evidence.missingYear} notOpen=${evidence.notOpen}');
          }
          if (evidence.deadlineAt == null && !evidence.noLimit) {
            _noteParseFailure('作业详情');
            failure = SyncIssue(
                evidence.notOpen
                    ? SyncIssueKind.partial
                    : SyncIssueKind.schemaChanged,
                evidence.notOpen
                    ? '作业尚未开放，开放后可读取截止时间'
                    : evidence.missingYear
                        ? '作业详情只提供月日，截止年份待确认'
                        : '作业详情未提供可识别的截止信息',
                stage: 'detail',
                courseKey: item.courseKey,
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
              elapsedMs: watch.elapsedMilliseconds);
        } on SyncReadException catch (e) {
          failure = SyncIssue(e.issue.kind, e.issue.message,
              stage: 'detail',
              courseKey: item.courseKey,
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
      if (failure != null) issues.add(failure);
      final resolved = item.copyWith(
          deadlineAt: evidence.deadlineAt,
          clearDeadlineAt: evidence.noLimit,
          deadlineTrusted: evidence.deadlineAt != null || evidence.noLimit,
          deadlineReadFailed: evidence.deadlineAt == null && !evidence.noLimit,
          deadlineRawText: evidence.missingYear
              ? '${evidence.rawText}（年份待确认）'
              : evidence.rawText);
      result.add(resolved);
      progress?.resolve(item.id, resolved);
    }
    return result;
  }

  // fanyav3 obtains its signed navigation from this first-party endpoint.
  // Only follow the formal homework page, with the same course/class identity.
  Future<Uri?> _fetchNavigationWorkUri(ChaoxingCourseRef course,
      {required int generation}) async {
    final response = await _safeGet<dynamic>(
        'https://mooc2-ans.chaoxing.com/mooc2-ans/coursemanagev3/stu-base-info',
        queryParameters: {
          'courseId': course.courseId,
          'clazzId': course.clazzId,
          if (course.cpi != null) 'cpi': course.cpi!
        },
        headers: {
          'User-Agent': courseUserAgent
        });
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
      {required int generation, _SyncProgressTracker? progress}) async {
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
            headers: {
              'User-Agent': courseUserAgent
            });
        if (generation != _sessionGeneration) {
          progress?.retractCourse(courseKey);
          return const [];
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
            final state = evaluation != 0
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
                deadlineReadFailed: false,
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
          return _hydrateWorkDeadlines(result,
              generation: generation, starts: starts, progress: progress);
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
  Future<Response<dynamic>?> _courseGet(Uri uri, {int? generation}) async {
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
      final response = await _safeGet<dynamic>(uri.toString(),
          headers: {'User-Agent': courseUserAgent});
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

  Future<Response<T>?> _safeGet<T>(
    String uri, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    final parsedUri = Uri.parse(uri);
    final kind = _requestKind(parsedUri.path);
    final generation = _sessionGeneration;
    var attempt = 0;
    while (true) {
      if (generation != _sessionGeneration) return null;
      final circuit = _openCircuits[kind];
      if (circuit != null) {
        throw SyncReadException(SyncIssue(
          circuit.kind,
          '连续请求失败，已暂停本次刷新中的$kind请求',
          stage: circuit.stage,
          httpStatus: circuit.httpStatus,
          retryAfter: circuit.retryAfter,
          retryAfterSeconds: circuit.retryAfterSeconds,
          circuitOpen: true,
        ));
      }
      attempt++;
      final watch = Stopwatch()..start();
      Response<T>? response;
      DioException? transportError;
      try {
        // ResponseType.plain keeps Dio's JSON transformer out of the measured
        // network window; JSON/HTML parsing is measured separately below.
        response = await _dio.get<T>(
          uri,
          queryParameters: queryParameters,
          options: Options(
            responseType: ResponseType.plain,
            validateStatus: (status) => status != null,
            headers: _headers(parsedUri, headers),
          ),
          cancelToken: _activeRequestToken,
        );
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) {
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
          await _wait(delay);
          continue;
        }
        throw SyncReadException(failure.issue);
      }
      final received = response!;
      _rememberCookies(received);
      final parseWatch = Stopwatch()..start();
      _ResponseOutcome outcome;
      try {
        outcome = _evaluateResponse(received, parsedUri, kind);
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
          await _wait(delay);
          continue;
        }
        throw SyncReadException(issue);
      }
      _consecutiveTransientFailures.remove(kind);
      return received;
    }
  }

  _ResponseOutcome _evaluateResponse(
      Response<dynamic> response, Uri uri, String kind) {
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
    final visible = body.replaceAll(
        RegExp(r'<(script|style)\b[^>]*>[\s\S]*?</\1>', caseSensitive: false),
        '');
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
      _verificationTarget = _courseVerificationProbe ?? uri;
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
        '作业详情' => 'detail',
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

  String? _extractMessage(String body) {
    final match = RegExp(r'"(?:msg|message)"\s*:\s*"([^"]+)"').firstMatch(body);
    return match?.group(1);
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
  final Map<String, Set<String>> _courseRowIds = {};
  AssignmentSyncStage stage = AssignmentSyncStage.courses;
  int resolvedCount = 0;
  int attemptedCount = 0;

  void setStage(AssignmentSyncStage value) {
    stage = value;
    _emit();
  }

  void addRows(List<Assignment> rows, {String? courseKey}) {
    for (final assignment in rows) {
      assignments[assignment.id] = assignment;
      if (courseKey != null) {
        (_courseRowIds[courseKey] ??= <String>{}).add(assignment.id);
      }
    }
    stage = AssignmentSyncStage.workLists;
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

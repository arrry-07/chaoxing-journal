import 'dart:convert';
import 'dart:io';

import '../models/sync_report.dart';
import 'chaoxing_exam_visibility.dart';

/// Classifies Chaoxing requests and responses without session or transport state.
abstract final class ChaoxingRequestPolicy {
  static const _maxAttemptsPerRequest = 2;
  static const _maxRetriesPerSync = 2;
  static const _normalRetryDelay = Duration(milliseconds: 500);
  static const _maxRetryDelay = Duration(seconds: 2);

  static String requestKindForPath(String path) {
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

  static SyncIssue httpIssueForStatus(int status, String kind,
      {String? retryAfterRaw, Duration? retryAfter}) {
    final stage = stageForKind(kind);
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

  static bool isTransientIssue(SyncIssue issue) {
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

  static Duration? parseRetryAfter(String? raw, {required DateTime now}) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final seconds = int.tryParse(value);
    if (seconds != null) {
      return seconds < 0 ? null : Duration(seconds: seconds);
    }
    try {
      final target = HttpDate.parse(value).toUtc();
      final wait = target.difference(now.toUtc());
      return wait.isNegative ? Duration.zero : wait;
    } catch (_) {
      return null;
    }
  }

  static String stageForKind(String kind) => switch (kind) {
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

  static dynamic decodeJsonPayload(dynamic payload) {
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

  static Duration? computeRetryDelay({
    required int attempt,
    required int retriesUsed,
    required SyncIssue issue,
    required bool transient,
    required Duration? retryAfter,
    required bool circuitOpened,
  }) {
    if (!transient ||
        circuitOpened ||
        attempt >= _maxAttemptsPerRequest ||
        retriesUsed >= _maxRetriesPerSync) {
      return null;
    }
    if (issue.kind == SyncIssueKind.rateLimited || retryAfter != null) {
      return retryAfter == null || retryAfter > _maxRetryDelay
          ? null
          : retryAfter;
    }
    return _normalRetryDelay;
  }

  static ChaoxingResponseDecision evaluateResponse({
    required int status,
    required Uri uri,
    required String kind,
    required Object? data,
    required String location,
    required String? retryAfterRaw,
    required DateTime now,
  }) =>
      evaluateDecodedResponse(
        status: status,
        uri: uri,
        kind: kind,
        body: data is String ? data : '',
        payload: decodeJsonPayload(data),
        location: location,
        retryAfterRaw: retryAfterRaw,
        now: now,
      );

  static ChaoxingResponseDecision evaluateDecodedResponse({
    required int status,
    required Uri uri,
    required String kind,
    required String body,
    required Object? payload,
    required String location,
    required String? retryAfterRaw,
    required DateTime now,
  }) {
    final stage = stageForKind(kind);
    final message = payload is Map
        ? (payload['msg'] ?? payload['message'] ?? payload['errorMsg'] ?? '')
            .toString()
        : '';
    // The explicit challenge code takes precedence over generic login text.
    if (payload is Map && payload['code']?.toString() == '9010') {
      return _verificationRequired(status, stage);
    }
    if (payload is Map &&
        (payload['result'] == false || payload['status'] == false) &&
        RegExp(r'未登录|请先登录|登录已失效|登录失效|登录超时|login required|unauthorized',
                caseSensitive: false)
            .hasMatch(message)) {
      return const ChaoxingResponseDecision.authExpired();
    }
    if (payload is Map &&
        ((message.contains('9010') && message.contains('验证码')) ||
            RegExp(r'请输入验证码|请完成.{0,12}(?:验证|校验)|安全验证|访问异常|人机验证|verify\.chaoxing',
                    caseSensitive: false)
                .hasMatch(message))) {
      return _verificationRequired(status, stage);
    }
    if (status == 401 ||
        (status >= 300 &&
            status < 400 &&
            (location.contains('passport2') || location.contains('/login'))) ||
        (body.contains('<html') &&
            (body.contains('请登录') ||
                body.contains('passport2.chaoxing.com/login')))) {
      return const ChaoxingResponseDecision.authExpired();
    }
    if (status == 403 || status == 404 || status == 429 || status >= 500) {
      final retryAfter = parseRetryAfter(retryAfterRaw, now: now);
      return ChaoxingResponseDecision.issue(
          httpIssueForStatus(status, kind,
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
    final visibleText = visible.replaceAll(RegExp(r'<[^>]+>'), ' ');
    final challenge = RegExp(
                r'请输入验证码|请完成.{0,12}(?:验证|校验)|安全验证|访问异常|人机验证|verify\.chaoxing',
                caseSensitive: false)
            .hasMatch(visibleText) ||
        (visibleText.contains('9010') && visibleText.contains('验证码')) ||
        location.contains('antispider');
    if (challenge) return _verificationRequired(status, stage);
    if (status >= 200 && status < 400) {
      return const ChaoxingResponseDecision.success();
    }
    return ChaoxingResponseDecision.issue(SyncIssue(
        SyncIssueKind.network, '接口返回 HTTP $status，请稍后重试',
        stage: stage, httpStatus: status));
  }

  static ChaoxingResponseDecision _verificationRequired(
          int status, String stage) =>
      ChaoxingResponseDecision.issue(SyncIssue(
          SyncIssueKind.verificationRequired, '学习通要求人工验证，请点击完成安全验证',
          stage: stage, httpStatus: status));

  static Uri? trustedVerificationUri(String? raw) {
    final uri = Uri.tryParse(raw ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        !(uri.host == 'chaoxing.com' || uri.host.endsWith('.chaoxing.com'))) {
      return null;
    }
    return uri;
  }

  static List<({Uri uri, String? userAgent, String cookies})> verificationRows(
      Iterable<dynamic> rows) {
    final ordered = <({Uri uri, String? userAgent, String cookies})>[];
    for (final row in rows.whereType<Map>()) {
      final uri = trustedVerificationUri(row['url']?.toString());
      if (uri == null) continue;
      final agent = row['userAgent'];
      ordered.add((
        uri: uri,
        userAgent: agent is String &&
                agent.length < 512 &&
                !agent.contains(RegExp(r'[\r\n]'))
            ? agent
            : null,
        cookies: row['cookies']?.toString() ?? '',
      ));
    }
    int rank(Uri uri) {
      if (uri.path.isNotEmpty && uri.path != '/') return 2;
      return uri.host == 'chaoxing.com' ? 0 : 1;
    }

    return [
      for (var precedence = 0; precedence < 3; precedence++)
        ...ordered.where((row) => rank(row.uri) == precedence),
    ];
  }

  static ({List<Cookie> cookies, int malformed}) parseVerificationCookies(
      String raw, Uri uri) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    final cookies = <Cookie>[];
    var malformed = 0;
    for (final pair in raw.split(';')) {
      final split = pair.indexOf('=');
      if (split < 1) continue;
      final name = pair.substring(0, split).trim();
      final value = pair.substring(split + 1).trim();
      // An empty WebView pair must never erase a valid session cookie.
      if (value.isEmpty) continue;
      try {
        final cookie = Cookie(name, value)
          ..path = path
          ..secure = true;
        if (uri.host == 'chaoxing.com') cookie.domain = '.chaoxing.com';
        cookies.add(cookie);
      } on FormatException {
        malformed++;
      }
    }
    return (cookies: cookies, malformed: malformed);
  }
}

class ChaoxingResponseDecision {
  const ChaoxingResponseDecision.success()
      : authExpired = false,
        issue = null,
        retryAfter = null;

  const ChaoxingResponseDecision.authExpired()
      : authExpired = true,
        issue = null,
        retryAfter = null;

  const ChaoxingResponseDecision.issue(this.issue, {this.retryAfter})
      : authExpired = false;

  final bool authExpired;
  final SyncIssue? issue;
  final Duration? retryAfter;
}

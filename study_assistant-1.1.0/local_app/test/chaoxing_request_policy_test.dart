import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_request_policy.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';

void main() {
  final now = DateTime.utc(2026, 11, 28, 12);

  test('request paths and explicit source kinds map to diagnostic stages', () {
    for (final (path, kind, stage) in [
      ('/mycourse/backclazzdata', '课程列表', 'courses'),
      ('/visit/stucoursemiddle', '课程入口', 'coursePage'),
      ('/mooc2/work/api/task', '作业列表', 'workList'),
      ('/mooc2/work/task', '作业详情', 'detail'),
      ('/exam-ans/exam/test/examcode/examlist', '账号考试', 'examAccount'),
      ('/exam/test', '课程考试补充', 'exam'),
      ('/v2/apis/active/getData', '任务引擎探测', 'taskEnginePlan'),
    ]) {
      expect(ChaoxingRequestPolicy.requestKindForPath(path), kind);
      expect(ChaoxingRequestPolicy.stageForKind(kind), stage);
    }
    expect(ChaoxingRequestPolicy.stageForKind('AI实践'), 'classroom');
  });

  test('Retry-After accepts seconds and HTTP dates within the retry budget',
      () {
    Duration? parse(String raw) =>
        ChaoxingRequestPolicy.parseRetryAfter(raw, now: now);
    expect(parse(' 2 '), const Duration(seconds: 2));
    expect(parse('Sat, 28 Nov 2026 12:00:01 GMT'), const Duration(seconds: 1));
    expect(parse('Sat, 28 Nov 2026 11:59:59 GMT'), Duration.zero);
    expect(parse('-1'), isNull);
    expect(parse('later'), isNull);

    final limited = ChaoxingRequestPolicy.httpIssueForStatus(429, '作业列表',
        retryAfterRaw: '2', retryAfter: parse('2'));
    expect(limited.kind, SyncIssueKind.rateLimited);
    expect(limited.stage, 'workList');
    expect(limited.retryAfterSeconds, 2);
    Duration? delay(SyncIssue issue,
            {Duration? retryAfter,
            int attempt = 1,
            int retriesUsed = 0,
            bool circuitOpened = false}) =>
        ChaoxingRequestPolicy.computeRetryDelay(
          attempt: attempt,
          retriesUsed: retriesUsed,
          issue: issue,
          transient: ChaoxingRequestPolicy.isTransientIssue(issue),
          retryAfter: retryAfter,
          circuitOpened: circuitOpened,
        );
    expect(delay(limited), isNull);
    expect(delay(limited, retryAfter: parse('2')), const Duration(seconds: 2));
    expect(delay(limited, retryAfter: parse('3')), isNull);

    final unavailable = ChaoxingRequestPolicy.httpIssueForStatus(503, '账号考试');
    expect(unavailable.kind, SyncIssueKind.serverError);
    expect(delay(unavailable), const Duration(milliseconds: 500));
    expect(delay(unavailable, attempt: 2), isNull);
    expect(delay(unavailable, retriesUsed: 2), isNull);
    expect(delay(unavailable, circuitOpened: true), isNull);
    final denied = ChaoxingRequestPolicy.httpIssueForStatus(403, '账号考试');
    expect(denied.kind, SyncIssueKind.forbidden);
    expect(delay(denied), isNull);
  });

  test('response evaluation distinguishes login, challenge, and inert markup',
      () {
    ChaoxingResponseDecision evaluate(Object data,
            {int status = 200,
            String location = '',
            String kind = '课程入口',
            String path = '/visit/stucoursemiddle'}) =>
        ChaoxingRequestPolicy.evaluateResponse(
          status: status,
          uri: Uri.https('mooc1.chaoxing.com', path),
          kind: kind,
          data: data,
          location: location,
          retryAfterRaw: null,
          now: now,
        );
    expect(evaluate('redirect', status: 302, location: '/login').authExpired,
        isTrue);
    expect(evaluate({'status': false, 'msg': '登录已失效'}).authExpired, isTrue);
    expect(evaluate('{"status":false,"code":9010}', status: 202).issue?.kind,
        SyncIssueKind.verificationRequired);
    expect(evaluate('<html>请完成安全验证</html>').issue?.kind,
        SyncIssueKind.verificationRequired);
    expect(
        evaluate('<script>安全验证</script><style>访问异常</style>课程').issue, isNull);
    expect(
        evaluate('<div id="tipWin" style="display:none">请输入验证码</div>',
                kind: '课程考试补充', path: '/exam/test')
            .issue,
        isNull);
  });

  test('verification keeps trusted root, host, then path cookie rows', () {
    expect(
        ChaoxingRequestPolicy.trustedVerificationUri(
            'https://mooc1.chaoxing.com.evil.invalid/'),
        isNull);
    expect(
        ChaoxingRequestPolicy.trustedVerificationUri(
            'http://mooc1.chaoxing.com/'),
        isNull);
    expect(
        ChaoxingRequestPolicy.trustedVerificationUri(
            'https://user@mooc1.chaoxing.com/'),
        isNull);
    final rows = ChaoxingRequestPolicy.verificationRows([
      {'url': 'https://mooc1.chaoxing.com/visit', 'cookies': 'path=ok'},
      {'url': 'https://notice.chaoxing.com/', 'userAgent': 'bad\r\nheader'},
      {
        'url': 'https://chaoxing.com/',
        'cookies': 'p=ok; p=; bad name=x; a=b=c'
      },
      {'url': 'https://mooc1.chaoxing.com.evil.invalid/', 'cookies': 'p=bad'},
    ]);
    expect(rows.map((r) => '${r.uri.host}${r.uri.path}'), [
      'chaoxing.com/',
      'notice.chaoxing.com/',
      'mooc1.chaoxing.com/visit',
    ]);
    expect(rows[1].userAgent, isNull);
    final parsed = ChaoxingRequestPolicy.parseVerificationCookies(
        rows.first.cookies, rows.first.uri);
    expect(parsed.malformed, 1);
    expect(parsed.cookies.map((c) => (c.name, c.value, c.domain)), [
      ('p', 'ok', '.chaoxing.com'),
      ('a', 'b=c', '.chaoxing.com'),
    ]);
  });
}

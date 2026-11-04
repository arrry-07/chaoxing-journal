import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/assignment.dart';
import 'chaoxing_api_parser.dart';
import 'chaoxing_assignment_parser.dart';

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
  ChaoxingLocalClient({Dio? dio})
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
            );

  final Dio _dio;
  final Map<String, String> _cookies = {};

  String? lastSyncWarning;
  Set<String> trackedActivityIds = {};
  void clearSession() {
    _cookies.clear();
    lastSyncWarning = null;
  }

  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async {
    clearSession();
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
    );
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
    final profile = await _fetchProfile(response.data, sessionProfile);
    final avatarUrl = await _resolveAvatarUrl(profile.avatarUrl);
    return ChaoxingLoginResult(
      success: true,
      displayName: profile.displayName,
      avatarUrl: avatarUrl,
    );
  }

  Future<List<Assignment>> fetchAssignments() async {
    lastSyncWarning = null;
    final mcode =
        _readCookie('UID') ?? _readCookie('uid') ?? _readCookie('_uid');
    final response = await _safeGet<dynamic>(
      'https://mooc1-api.chaoxing.com/mycourse/backclazzdata',
      queryParameters: {'view': 'json', if (mcode != null) 'mcode': mcode},
    );
    final payload = _decodeJsonPayload(response?.data);
    final raw = payload is Map
        ? payload['channelList'] ?? payload['courses'] ?? payload['data']
        : null;
    final courses = ChaoxingApiParser.parseCourseRefs(payload);
    if (raw is! List ||
        (raw.isNotEmpty && courses.isEmpty) ||
        (payload is Map &&
            (payload['result'] == false || payload['status'] == false))) {
      throw StateError('无法读取课程列表，请检查学习通登录状态和网络。');
    }
    final problems = <String>{};
    if (raw.length != courses.length) problems.add('部分课程无法识别');
    final assignments = <Assignment>[];
    var recognized = courses.isEmpty;
    for (final course in courses) {
      final work = await _fetchCourseWork(course);
      final label = '${course.courseName}（班级 ${course.clazzId}）';
      if (work == null) {
        problems.add('$label 作业列表未读取');
      } else {
        recognized = true;
        assignments.addAll(work);
        if (work.any((a) => a.deadlineReadFailed)) {
          problems.add('$label 部分截止时间未读取');
        }
      }
      final activities = await _safeGet<dynamic>(
        'https://mobilelearn.chaoxing.com/v2/apis/active/student/activelist',
        queryParameters: {
          'fid': '0',
          'courseId': course.courseId,
          'classId': course.clazzId,
          if (course.cpi != null) 'cpi': course.cpi
        },
      );
      final activityPayload = _decodeJsonPayload(activities?.data);
      final data = activityPayload is Map
          ? activityPayload['data'] ?? activityPayload
          : null;
      if (data is! Map ||
          (data['activeList'] ?? data['list'] ?? data['activities']) is! List ||
          (activityPayload is Map && activityPayload['result'] == false)) {
        problems.add('$label 活动未读取');
        continue;
      }
      if (work == null || trackedActivityIds.isNotEmpty) {
        final fallback =
            ChaoxingApiParser.parseActivityAssignments(activityPayload, course);
        assignments.addAll(work == null ? fallback : fallback.where((a) => trackedActivityIds.contains(a.id)));
        if (fallback.isNotEmpty) recognized = true;
      }
      final exams = ChaoxingApiParser.parseActivityExamAssignments(
          activityPayload, course);
      if (exams.isNotEmpty) recognized = true;
      assignments.addAll(exams);
    }
    if (problems.isNotEmpty) lastSyncWarning = problems.join('；');
    if (!recognized) throw StateError(lastSyncWarning ?? '无法读取学习通作业');
    return _dedupeAssignments(assignments);
  }

  Future<List<Assignment>?> _fetchCourseWork(ChaoxingCourseRef course) async {
    final middle = await _courseGet(
        Uri.https('mooc1.chaoxing.com', '/visit/stucoursemiddle', {
      'courseid': course.courseId,
      'clazzid': course.clazzId,
      if (course.cpi != null) 'cpi': course.cpi!,
      'ismooc2': '1',
      'v': '2',
    }));
    final html = middle?.data?.toString() ?? '';
    final workEnc = ChaoxingAssignmentParser.hiddenValue(html, 'workEnc');
    if (workEnc == null || workEnc.isEmpty) return null;
    final uri = Uri.https('mooc1.chaoxing.com', '/mooc2/work/list', {
      'courseId': course.courseId,
      'classId': course.clazzId,
      if (course.cpi != null) 'cpi': course.cpi!,
      'ut': 's',
      'enc': workEnc,
      'openc': ChaoxingAssignmentParser.hiddenValue(html, 'openc') ?? '',
      'stuenc': ChaoxingAssignmentParser.hiddenValue(html, 'enc') ?? '',
      'isdisplaytable': '2',
      't': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    final list = await _courseGet(uri);
    final parsed = ChaoxingAssignmentParser.parseSignedWorkList(
        list?.data?.toString() ?? '',
        courseId: course.courseId,
        clazzId: course.clazzId,
        courseName: course.courseName,
        baseUri: uri);
    if (parsed == null) return null;
    final result = <Assignment>[];
    for (final item in parsed) {
      final detail = await _courseGet(Uri.parse(item.submitUrl!));
      final content = detail?.data?.toString() ?? '';
      final date = ChaoxingAssignmentParser.parseDetailDeadline(content);
      final noLimit = RegExp(r'(?:作答时间|截止时间)\s*[:：]\s*(?:不限|无截止时间|长期有效)')
          .hasMatch(_stripTags(content));
      result.add(item.copyWith(
          deadlineAt: date, deadlineReadFailed: date == null && !noLimit));
    }
    return result;
  }

  // Only forward the authenticated session within Chaoxing when the course
  // middle page redirects to the current deployment.
  Future<Response<dynamic>?> _courseGet(Uri uri) async {
    for (var i = 0; i < 5; i++) {
      if (uri.scheme != 'https' || !uri.host.endsWith('.chaoxing.com')) {
        return null;
      }
      final response = await _safeGet<dynamic>(uri.toString());
      if (response == null || response.statusCode! < 300) return response;
      final location = response.headers.value('location');
      if (location == null || location.isEmpty) return null;
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
    try {
      final response = await _dio.get<T>(
        uri,
        queryParameters: queryParameters,
        options: Options(headers: _headers(headers)),
      );
      _rememberCookies(response);
      final status = response.statusCode ?? 0;
      if (status >= 200 && status < 400) {
        return response;
      }
    } catch (_) {
      // Chaoxing endpoints differ by school/session. Keep the sync pipeline best-effort.
    }
    return null;
  }

  Map<String, String> _headers([Map<String, String>? extra]) {
    return {
      if (_cookies.isNotEmpty)
        'Cookie': _cookies.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join('; '),
      if (extra != null) ...extra,
    };
  }

  void _rememberCookies(Response<dynamic> response) {
    final raw = response.headers['set-cookie'];
    if (raw == null) {
      return;
    }
    for (final header in raw) {
      final pair = header.split(';').first;
      final separator = pair.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      _cookies[pair.substring(0, separator).trim()] =
          pair.substring(separator + 1).trim();
    }
  }

  String? _readCookie(String name) => _cookies[name];

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
    if (redirectUrl == null) {
      return const _ChaoxingProfile();
    }
    final response = await _safeGet<dynamic>(
      redirectUrl,
      headers: {'Accept': 'text/html,application/xhtml+xml,*/*'},
    );
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
          headers: _headers(
              {'Accept': 'image/avif,image/webp,image/apng,image/*,*/*'}),
        ),
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

class _ChaoxingProfile {
  const _ChaoxingProfile({this.displayName, this.avatarUrl});

  final String? displayName;
  final String? avatarUrl;
}

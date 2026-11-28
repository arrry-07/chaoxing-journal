part of 'chaoxing_local_client.dart';

extension _SessionClient on ChaoxingLocalClient {
  Future<bool> _verifyInBrowser({bool courseInspection = false}) async {
    final generation = _sessionGeneration;
    final candidate = _verificationTarget ??
        (courseInspection ? _courseVerificationProbe : null);
    final target =
        ChaoxingRequestPolicy.trustedVerificationUri(candidate?.toString());
    if (target == null) throw const VerificationTargetUnavailable();
    final rows = await const MethodChannel('study_assistant/external_links')
        .invokeListMethod<dynamic>('verifySession', {
      'url': target.toString(),
      'userAgent': ChaoxingLocalClient.courseUserAgent,
      'cookies': [
        for (final entry in _cookies.where((e) => !e.expired))
          {
            'url': 'https://${entry.domain}${entry.path}',
            'value': entry.cookie.toString()
          }
      ],
    });
    if (generation != _sessionGeneration || rows == null) return false;
    _skippedMalformedVerifyCookies = 0;
    for (final row in ChaoxingRequestPolicy.verificationRows(rows)) {
      final (:uri, :userAgent, :cookies) = row;
      if (userAgent != null) _dio.options.headers['User-Agent'] = userAgent;
      final path = uri.path.isEmpty ? '/' : uri.path;
      final isRootDomain = uri.host == 'chaoxing.com';
      final parsed =
          ChaoxingRequestPolicy.parseVerificationCookies(cookies, uri);
      _skippedMalformedVerifyCookies += parsed.malformed;
      for (final validated in parsed.cookies) {
        final name = validated.name;
        final value = validated.value;
        final matches = _cookies
            .where((e) => e.cookie.name == name && e.matches(uri))
            .toList();
        if (matches.any((e) =>
                e.cookie.value == validated.value &&
                e.expires == null &&
                (!isRootDomain || !e.hostOnly)) &&
            matches.every((e) =>
                e.domain != uri.host ||
                e.path != path ||
                (e.cookie.value == validated.value && e.expires == null))) {
          continue;
        }
        if (isRootDomain) {
          _cookies.removeWhere((e) =>
              e.cookie.name == name && e.domain == uri.host && e.path == path);
          _cookies.add(_SessionCookie(validated, uri.host, path, false));
        } else if (path == '/') {
          // Never mutate parent `.chaoxing.com` cookies from a subdomain row.
          // Replace only same-host entries (including stale path-scoped copies)
          // with fresh host-only entries so `expires` is also refreshed.
          final sameHost = matches.where((e) => e.domain == uri.host).toList();
          if (sameHost.isNotEmpty) {
            _cookies.removeWhere((e) =>
                e.cookie.name == name &&
                e.domain == uri.host &&
                sameHost.contains(e));
            for (final prev in sameHost) {
              final refreshed = Cookie(name, value)
                ..path = prev.path
                ..secure = true;
              _cookies
                  .add(_SessionCookie(refreshed, uri.host, prev.path, true));
            }
          } else {
            _cookies.removeWhere((e) =>
                e.cookie.name == name &&
                e.domain == uri.host &&
                e.path == path);
            _cookies.add(_SessionCookie(validated, uri.host, path, true));
          }
        } else {
          _cookies.removeWhere((e) =>
              e.cookie.name == name && e.domain == uri.host && e.path == path);
          _cookies.add(_SessionCookie(validated, uri.host, path, true));
        }
      }
    }
    // Returning closes the browser; only the subsequent signed request can prove success.
    return true;
  }

  Future<ChaoxingLoginResult> _loadProfile() async {
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

  void _clearSession() {
    // Stop any transport that still belongs to the previous identity before
    // clearing cookies and generation. A session replacement is a stale-result
    // case, not an explicit user/Worker cancellation, so old callers keep the
    // existing empty-result contract; Store cancellation uses the default.
    // ignore: unnecessary_this
    this.cancelActiveRequests(reportCancelled: false);
    _resetSyncTracking(clearRequestStats: true);
    _sessionGeneration++;
    _cookies.clear();
    _loginPayload = null;
    courses = [];
    hasCourseResponse = false;
    nextSyncCourseSelector = null;
    lastSyncScope = AssignmentSyncScope.all;
    plannedCourses = 0;
    skippedCourses = 0;
    lastPlannedCourseKeys = const {};
    lastFailedCourseKeys = const {};
    _lastExamFailedCourseKeys.clear();
    issues = [];
    sourceResults = const [];
    succeededCourses = 0;
    failedCourses = 0;
    detailUnconfirmedCount = 0;
    _detailUnconfirmedCourseKeys.clear();
    _verificationTarget = null;
    _courseVerificationProbe = null;
    _v3FormalApiConfirmed = false;
    _sessionVueExamCourses.clear();
    _sessionHasPcExamCredential = false;
    _deadlineReadsBlockedBy = null;
    lastSyncWarning = null;
  }

  Future<ChaoxingLoginResult> _login({
    required String account,
    required String password,
  }) async {
    // Keep the virtual call explicit in the part implementation.
    // ignore: unnecessary_this
    this.clearSession();
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
    final payload = ChaoxingRequestPolicy.decodeJsonPayload(response.data);
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

  Map<String, String> _headers(Uri uri, [Map<String, String>? extra]) {
    _cookies.removeWhere((c) => c.expired);
    final matching = _cookies.where((c) => c.matches(uri)).toList()
      ..sort((a, b) {
        final byPath = b.path.length.compareTo(a.path.length);
        if (byPath != 0) return byPath;
        if (a.hostOnly != b.hostOnly) return a.hostOnly ? -1 : 1;
        return b.domain.length.compareTo(a.domain.length);
      });
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
    final decoded = ChaoxingRequestPolicy.decodeJsonPayload(payload);
    final displayName = _extractDisplayName(decoded);
    final avatarFromPayload = _extractAvatarUrl(decoded);
    return _ChaoxingProfile(
      displayName: displayName,
      avatarUrl: avatarFromPayload ??
          (useCookieAvatar ? _avatarUrlFromCookie() : null),
    );
  }

  String? _extractLoginRedirectUrl(dynamic payload) {
    final decoded = ChaoxingRequestPolicy.decodeJsonPayload(payload);
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

class _ChaoxingProfile {
  const _ChaoxingProfile({this.displayName, this.avatarUrl});

  final String? displayName;
  final String? avatarUrl;
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

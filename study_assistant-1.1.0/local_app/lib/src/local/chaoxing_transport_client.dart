part of 'chaoxing_local_client.dart';

extension _TransportClient on ChaoxingLocalClient {
  void _cancelActiveRequests({required bool reportCancelled}) {
    _syncCourseEntries = null;
    _syncExamEntryCourses = null;
    _stopRequested = reportCancelled;
    _activeRequestToken?.cancel('主动停止后台学习通请求');
    _activeRequestToken = null;
    _sessionGeneration++;
  }

  CancelToken _startRequestToken() {
    _syncCourseEntries = null;
    _syncExamEntryCourses = null;
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

  Future<Response<dynamic>?> _readCourseEntryOrGet(Uri uri,
      {required int generation,
      String? requestKind,
      String? circuitKind,
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
    final key = ChaoxingLocalClient._courseEntryCacheKey(uri);
    if (generation != _sessionGeneration ||
        _stopRequested ||
        token?.isCancelled == true) {
      return null;
    }
    if (eligible && cache.containsKey(key)) return cache[key];
    final response = await _safeGet<dynamic>(uri.toString(),
        headers: {'User-Agent': ChaoxingLocalClient.courseUserAgent},
        requestKind: requestKind,
        circuitKind: circuitKind,
        verificationProbe: verificationProbe);
    if (eligible &&
        identical(cache, _syncCourseEntries) &&
        identical(token, _activeRequestToken) &&
        !_stopRequested &&
        generation == _sessionGeneration &&
        response?.statusCode == 200) {
      final html = response?.data?.toString() ?? '';
      if (ChaoxingAssignmentParser.hiddenValue(html, 'examEnc')?.isNotEmpty ==
          true) {
        cache[key] = response!;
        _sessionHasPcExamCredential = true;
        final cId = ChaoxingParamHelper.singleQueryValue(
            uri, ChaoxingParamHelper.courseIdKeys);
        final clzId = ChaoxingParamHelper.singleQueryValue(
            uri, ChaoxingParamHelper.clazzIdKeys);
        if (cId != null && clzId != null) {
          _syncExamEntryCourses?.add('$cId:$clzId');
        }
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
    String? circuitKind,
    String method = 'GET',
    Map<String, dynamic>? form,
    Uri? verificationProbe,
    Future<ChaoxingResponseDecision> Function(Response<T>, Uri)? classify,
  }) async {
    final parsedUri = Uri.parse(uri);
    final kind =
        requestKind ?? ChaoxingRequestPolicy.requestKindForPath(parsedUri.path);
    final breakerKind = circuitKind ?? kind;
    final generation = _sessionGeneration;
    final requestToken = _activeRequestToken;
    var attempt = 0;
    while (true) {
      if (_stopRequested) {
        throw const SyncReadException(SyncIssue(
          SyncIssueKind.cancelled,
          '本次同步已取消',
          stage: 'request',
        ));
      }
      if (generation != _sessionGeneration ||
          requestToken?.isCancelled == true) {
        return null;
      }
      // The exam collector stops the group immediately once its circuit opens.
      final reportExamCircuit =
          breakerKind == '课程考试' || breakerKind == '课程考试补充';
      final circuit = _openCircuits[breakerKind];
      if (circuit != null) {
        throw SyncReadException(_pausedRequestIssue(breakerKind, circuit));
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
          cancelToken: requestToken,
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
        final opened = _registerTransientFailure(breakerKind, failure);
        final delay = ChaoxingRequestPolicy.computeRetryDelay(
            attempt: attempt,
            retriesUsed: _syncRetryCount,
            issue: failure.issue,
            transient: failure.transient,
            retryAfter: failure.retryAfter,
            circuitOpened: opened);
        if (delay != null) {
          _syncRetryCount++;
          await _waitOrCancel(delay);
          continue;
        }
        throw SyncReadException(opened && reportExamCircuit
            ? _pausedRequestIssue(breakerKind, failure.issue)
            : failure.issue);
      }
      final received = response!;
      _rememberCookies(received);
      final parseWatch = Stopwatch()..start();
      ChaoxingResponseDecision outcome;
      try {
        outcome = classify == null
            ? _evaluateResponse(received, parsedUri, kind)
            : await classify(received, parsedUri);
      } catch (_) {
        outcome = ChaoxingResponseDecision.issue(SyncIssue(
            SyncIssueKind.schemaChanged, '学习通响应无法解析，请稍后重试',
            stage: ChaoxingRequestPolicy.stageForKind(kind),
            httpStatus: received.statusCode));
      }
      if (_stopRequested) {
        throw const SyncReadException(SyncIssue(
          SyncIssueKind.cancelled,
          '本次同步已取消',
          stage: 'request',
        ));
      }
      if (generation != _sessionGeneration ||
          requestToken?.isCancelled == true) {
        return null;
      }
      if (outcome.issue?.kind == SyncIssueKind.verificationRequired) {
        _verificationTarget ??= verificationProbe ?? parsedUri;
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
            !httpFailed && (outcome.authExpired || outcome.issue != null),
      );
      if (outcome.authExpired) {
        _consecutiveTransientFailures.remove(breakerKind);
        throw ChaoxingAuthenticationException(status);
      }
      final issue = outcome.issue;
      if (issue != null) {
        final failure = _AttemptFailure(
          issue,
          transient: ChaoxingRequestPolicy.isTransientIssue(issue),
          retryAfter: outcome.retryAfter,
        );
        final opened = _registerTransientFailure(breakerKind, failure);
        final delay = ChaoxingRequestPolicy.computeRetryDelay(
            attempt: attempt,
            retriesUsed: _syncRetryCount,
            issue: failure.issue,
            transient: failure.transient,
            retryAfter: failure.retryAfter,
            circuitOpened: opened);
        if (delay != null) {
          _syncRetryCount++;
          await _waitOrCancel(delay);
          continue;
        }
        throw SyncReadException(opened && reportExamCircuit
            ? _pausedRequestIssue(breakerKind, issue)
            : issue);
      }
      _consecutiveTransientFailures.remove(breakerKind);
      return received;
    }
  }

  ChaoxingResponseDecision _evaluateResponse(
      Response<dynamic> response, Uri uri, String kind) {
    final status = response.statusCode ?? 0;
    final decision = ChaoxingRequestPolicy.evaluateResponse(
      status: status,
      uri: uri,
      kind: kind,
      data: response.data,
      location: response.headers.value('location') ?? '',
      retryAfterRaw: response.headers['retry-after']?.singleOrNull,
      now: DateTime.now(),
    );
    final challenge =
        decision.issue?.kind == SyncIssueKind.verificationRequired;
    if (kDebugMode && uri.path.contains('stucoursemiddle')) {
      final body = response.data is String ? response.data as String : '';
      debugPrint(
          '[SyncShape] stage=coursePage status=$status workEnc=${ChaoxingAssignmentParser.hiddenValue(body, 'workEnc') != null} captchaLibrary=${body.toLowerCase().contains('captcha')} challenge=$challenge');
    }
    return decision;
  }

  _AttemptFailure _networkFailure(DioException error, String kind) {
    final response = error.response;
    if (response != null && response.statusCode != null) {
      final status = response.statusCode!;
      final retryAfterRaw = response.headers['retry-after']?.singleOrNull;
      final retryAfter = ChaoxingRequestPolicy.parseRetryAfter(retryAfterRaw,
          now: DateTime.now());
      final issue = ChaoxingRequestPolicy.httpIssueForStatus(status, kind,
          retryAfterRaw: retryAfterRaw, retryAfter: retryAfter);
      return _AttemptFailure(issue,
          transient: ChaoxingRequestPolicy.isTransientIssue(issue),
          retryAfter: retryAfter);
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
        stage: ChaoxingRequestPolicy.stageForKind(kind),
      ),
      transient: transient,
    );
  }
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

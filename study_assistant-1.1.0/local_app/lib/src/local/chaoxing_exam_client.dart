part of 'chaoxing_local_client.dart';

String _examFailureMessage(String source, Object error) {
  if (error is SyncReadException) return error.issue.message;
  final code = error is StateError ? error.message.toString() : '';
  final reason = switch (code) {
    'examPhoneSchema' => '课程考试列表页面结构无法识别',
    'examRepeatedPage' => '课程考试列表分页出现重复记录',
    'examEmptyMore' => '课程考试列表分页为空但仍提示更多',
    'examPageLimit' => '课程考试列表分页超过安全上限',
    'examCredentialMissing' => '课程页未提供考试读取凭证',
    'examPcSchema' => '考试时间页面结构无法识别',
    'examPcRepeated' => '考试时间列表分页出现重复记录',
    'examPcIncomplete' => '考试时间列表分页数量不完整',
    'examPcUnreadable' => '已完成考试不允许查看，未能确认考试信息',
    'examListDisagreement' => '手机考试列表与考试时间列表不一致',
    'accountExamSchema' => '账号考试列表页面结构无法识别',
    'accountExamRepeated' => '账号考试列表分页出现重复记录',
    'accountExamIncomplete' => '账号考试列表分页数量不完整',
    'accountExamRowSkippedNoId' => '部分历史账号考试缺少唯一标识，已跳过未识别行',
    'examNoticeSchema' => '考试通知列表结构无法识别',
    'examNoticeRepeated' => '考试通知分页游标重复',
    'examNoticeLimit' => '考试通知分页超过安全上限',
    'unsafeExamRedirect' => '考试页面跳转未通过安全检查',
    'examRedirectMissing' => '考试页面跳转缺少目标地址',
    'examRedirectLimit' => '考试页面跳转次数超过上限',
    _ => source == 'examAccount'
        ? '账号考试读取失败'
        : source == 'examNotice'
            ? '考试通知读取失败'
            : '课程考试读取失败',
  };
  return code.isEmpty ? reason : '$reason（$code）';
}

extension _ExamCollection on ChaoxingLocalClient {
  bool get _hasExamObservation => sourceResults.any((s) =>
      const {'exam', 'examAccount', 'examNotice'}.contains(s.source) &&
      (s.phase == SyncSourcePhase.success || s.recordCount > 0));
  Future<List<Assignment>> _fetchExams(List<ChaoxingCourseRef> refs,
      {required int generation,
      bool includeAccount = true,
      bool collectCourseNotices = false}) async {
    if (!enableExams) return const [];
    final rows = <Assignment>[];
    bool current() {
      if (_stopRequested) {
        throw const SyncReadException(
            SyncIssue(SyncIssueKind.cancelled, '本次同步已取消', stage: 'exam'));
      }
      return generation == _sessionGeneration;
    }

    void checkWindow() {
      if (shouldStop?.call() == true) {
        throw const SyncReadException(SyncIssue(
            SyncIssueKind.partial, '检查窗口已结束，已保留此前取得的课业',
            stage: 'exam'));
      }
    }

    void failure(String source, Object error, {String? courseKey}) {
      if (error is SyncReadException &&
          error.issue.kind == SyncIssueKind.cancelled) {
        throw error;
      }
      final reason = error is SyncReadException
          ? error.issue.kind
          : error is ChaoxingAuthenticationException
              ? SyncIssueKind.authExpired
              : SyncIssueKind.schemaChanged;
      issues.add(SyncIssue(reason, _examFailureMessage(source, error),
          stage: source,
          courseKey: courseKey,
          httpStatus:
              error is SyncReadException ? error.issue.httpStatus : null));
    }

    SyncSourceResult report(
            String source, int success, int failed, List<Assignment> observed,
            {List<String> extraReasons = const []}) =>
        SyncSourceResult(
            source: source,
            phase: failed == 0 && extraReasons.isEmpty
                ? SyncSourcePhase.success
                : success > 0 || observed.isNotEmpty
                    ? SyncSourcePhase.partial
                    : SyncSourcePhase.failed,
            succeededCourses: success,
            failedCourses: failed,
            recordCount: observed.length,
            unconfirmedCount: observed
                .where((a) => a.status == 'unknown' || !a.timelineTrusted)
                .length,
            reasonCodes: {
              if (failed > 0) 'listOrMetadataUnavailable',
              ...extraReasons,
            }.toList());
    var succeeded = 0, failed = 0;
    final examExtraReasons = <String>{};
    SyncIssueKind? blocked;
    for (final course in refs) {
      if (!current()) return const [];
      final courseKey = '${course.courseId}:${course.clazzId}';
      if (blocked != null) {
        failed++;
        continue;
      }
      final observed = <Assignment>[];
      try {
        final seen = <String>{};
        var finished = false;
        for (var page = 1; page <= 100; page++) {
          checkWindow();
          final response = page == 1
              ? await _examListGet(
                  Uri.https(
                      'mooc1-api.chaoxing.com',
                      '/phone/moocAnalysis/examList',
                      {'courseId': course.courseId, 'classId': course.clazzId}),
                  generation: generation)
              : await _safeGet<dynamic>(
                  'https://mooc1-api.chaoxing.com/mooc-ans/phone/moocAnalysis/examList',
                  method: 'POST',
                  form: {
                    'courseId': course.courseId,
                    'classId': course.clazzId,
                    'pageSize': '20',
                    'pageNum': '$page'
                  },
                  requestKind: '课程考试');
          if (!current()) return const [];
          final parsed = ChaoxingExamParser.phone(
              response?.data?.toString() ?? '', course);
          if (parsed == null) throw StateError('examPhoneSchema');
          if (parsed.rows.any((r) => !seen.add(r.id))) {
            throw StateError('examRepeatedPage');
          }
          observed.addAll(parsed.rows);
          if (!parsed.more) {
            finished = true;
            break;
          }
          if (parsed.rows.isEmpty) throw StateError('examEmptyMore');
        }
        if (!finished) throw StateError('examPageLimit');
        // PC time evidence is supplemental. Failure retains phone identities.
        {
          checkWindow();
          final middle = await _examListGet(
              Uri.https('mooc1.chaoxing.com', '/visit/stucoursemiddle', {
                'courseid': course.courseId,
                'clazzid': course.clazzId,
                'ismooc2': '1',
                'v': '2',
                if (course.cpi != null) 'cpi': course.cpi!
              }),
              generation: generation);
          if (!current()) return const [];
          final html = middle?.data?.toString() ?? '';
          final enc = ChaoxingAssignmentParser.hiddenValue(html, 'examEnc');
          final workEnc = ChaoxingAssignmentParser.hiddenValue(html, 'workEnc');
          if (enc == null || enc.isEmpty) {
            // A course with a valid work entry and empty phone exam list
            // simply does not enable the exam module; treat it as 0 exams.
            if (observed.isEmpty && workEnc != null && workEnc.isNotEmpty) {
              succeeded++;
              rows.addAll(observed);
              continue;
            }
            throw StateError('examCredentialMissing');
          }
          final pcRows = <Assignment>[];
          final phoneIds = observed.map((a) => a.id).toSet();
          final pcSeen = <String>{};
          var pcSkipped = 0;
          var pcObserved = 0;
          int? expectedTotal;
          for (var page = 0; page < 100; page++) {
            checkWindow();
            final response = await _examListGet(
                Uri.https('mooc1.chaoxing.com', '/exam/test', {
                  'courseId': course.courseId,
                  'classId': course.clazzId,
                  'ut': 's',
                  'cpi': ChaoxingAssignmentParser.hiddenValue(html, 'cpi') ??
                      course.cpi ??
                      '',
                  'openc':
                      ChaoxingAssignmentParser.hiddenValue(html, 'openc') ?? '',
                  'enc': enc,
                  'start': '${page * 9}'
                }),
                generation: generation);
            if (!current()) return const [];
            final parsed = ChaoxingExamParser.coursePc(
                response?.data?.toString() ?? '', course);
            if (parsed == null ||
                (expectedTotal != null && parsed.total != expectedTotal)) {
              throw StateError('examPcSchema');
            }
            expectedTotal = parsed.total;
            pcObserved += parsed.observed;
            pcSkipped += parsed.skipped;
            if (parsed.rows.any((r) => !pcSeen.add(r.id))) {
              throw StateError('examPcRepeated');
            }
            pcRows.addAll(parsed.rows);
            // Retain each validated page before requesting the next one.
            for (final row in parsed.rows) {
              final index = observed.indexWhere((a) => a.id == row.id);
              if (index >= 0) {
                observed[index] = row.copyWith(status: observed[index].status);
              } else {
                observed.add(row);
              }
            }
            if (pcObserved >= parsed.total) break;
            if (parsed.observed == 0) throw StateError('examPcIncomplete');
          }
          if (pcRows.length + pcSkipped != expectedTotal) {
            throw StateError('examPcIncomplete');
          }
          // A completed, non-viewable PC row has no stable node ID. It is a
          // legitimate supplemental gap only when the phone list already
          // supplied an identity; it must not turn the whole course into a
          // schema failure or be guessed by title/order.
          if (observed.isEmpty && pcSkipped > 0 && pcRows.isEmpty) {
            throw StateError('examPcUnreadable');
          }
          final unmatchedPhoneIds = phoneIds.difference(pcSeen);
          if (unmatchedPhoneIds.length > pcSkipped) {
            throw StateError('examListDisagreement');
          }
        }
        succeeded++;
      } catch (error) {
        if (!current()) return const [];
        if (observed.isNotEmpty) {
          examExtraReasons.add('examPcSupplementUnavailable');
        }
        failure('exam', error, courseKey: courseKey);
        failed++;
        final kind = error is SyncReadException
            ? error.issue.kind
            : error is ChaoxingAuthenticationException
                ? SyncIssueKind.authExpired
                : null;
        if (const {
          SyncIssueKind.authExpired,
          SyncIssueKind.verificationRequired,
          SyncIssueKind.rateLimited
        }.contains(kind)) {
          blocked = kind;
        }
      }
      rows.addAll(observed);
    }
    if (!current()) return const [];
    sourceResults = [
      ...sourceResults,
      report('exam', succeeded, failed, rows,
          extraReasons: examExtraReasons.toList()),
    ];
    if (includeAccount) {
      final accountRows = <Assignment>[];
      var accountFailed = false;
      var accountSkippedNoId = 0;
      try {
        int? total;
        final ids = <String>{};
        for (var page = 0; page < 100; page++) {
          checkWindow();
          final response = await _examListGet(
              Uri.https(
                  'mooc1-api.chaoxing.com',
                  '/exam-ans/exam/test/examcode/examlist',
                  {'start': '${page * 12}'}),
              generation: generation);
          if (!current()) return const [];
          final parsed =
              ChaoxingExamParser.account(response?.data?.toString() ?? '');
          if (parsed == null || (total != null && total != parsed.total)) {
            throw StateError('accountExamSchema');
          }
          total = parsed.total;
          if (parsed.rows.any((a) => !ids.add(a.id))) {
            throw StateError('accountExamRepeated');
          }
          accountRows.addAll(parsed.rows);
          accountSkippedNoId += parsed.skippedWithoutId;
          if (accountRows.length + accountSkippedNoId >= total) break;
          if (parsed.rows.isEmpty && parsed.skippedWithoutId == 0) {
            throw StateError('accountExamIncomplete');
          }
        }
        if (accountRows.length + accountSkippedNoId != total) {
          throw StateError('accountExamIncomplete');
        }
      } catch (error) {
        if (!current()) return const [];
        failure('examAccount', error);
        accountFailed = true;
      }
      rows.addAll(accountRows);
      sourceResults = [
        ...sourceResults,
        report(
          'examAccount',
          accountFailed ? 0 : 1,
          accountFailed ? 1 : 0,
          accountRows,
          extraReasons: accountSkippedNoId > 0
              ? const ['accountExamRowSkippedNoId']
              : const [],
        ),
      ];
      final notices = <Assignment>[];
      final courseNotices = <CourseNotice>[];
      final courseNoticeIds = <String>{};
      var noticeFailed = false;
      var courseNoticeFailed = false;
      try {
        final cursors = <String>{}, ids = <String>{};
        var cursor = '', done = false;
        for (var page = 0; page < 100; page++) {
          checkWindow();
          final response = await _safeGet<dynamic>(
              'https://notice.chaoxing.com/pc/notice/getNoticeList',
              method: 'POST',
              requestKind: '考试通知',
              form: {
                'type': '0',
                'notice_type': '0',
                'lastValue': cursor,
                'sort': '0',
                'folderUUID': '',
                'kw': '',
                'startTime': '',
                'endTime': '',
                'gKw': '',
                'gName': '',
                'year': '',
                'tag': '',
                'fidsCode': '',
                'filterSenderPuids': '',
                'filterTags': ''
              });
          if (!current()) return const [];
          final decodedPayload = _decodeJsonPayload(response?.data);
          final parsed = ChaoxingExamParser.notices(decodedPayload);
          if (parsed == null) throw StateError('examNoticeSchema');
          for (final a in parsed.rows) {
            if (ids.add(a.id)) notices.add(a);
          }
          if (collectCourseNotices && page < 5) {
            final parsedCourseNotices =
                ChaoxingNoticeParser.parsePage(decodedPayload, courses: refs);
            if (parsedCourseNotices == null) {
              courseNoticeFailed = true;
            } else {
              for (final item in parsedCourseNotices.rows) {
                if (courseNoticeIds.add(item.id)) courseNotices.add(item);
              }
            }
          }
          if (parsed.cursor == null) {
            done = true;
            break;
          }
          if (!cursors.add(parsed.cursor!)) {
            throw StateError('examNoticeRepeated');
          }
          cursor = parsed.cursor!;
        }
        if (!done) throw StateError('examNoticeLimit');
      } catch (error) {
        if (!current()) return const [];
        failure('examNotice', error);
        noticeFailed = true;
        if (collectCourseNotices) courseNoticeFailed = true;
      }
      rows.addAll(notices);
      if (collectCourseNotices) {
        _lastFetchedNotices = List.unmodifiable(courseNotices);
      }
      sourceResults = [
        ...sourceResults,
        report(
            'examNotice', noticeFailed ? 0 : 1, noticeFailed ? 1 : 0, notices),
        if (collectCourseNotices)
          SyncSourceResult(
            source: 'courseNotice',
            phase: courseNoticeFailed
                ? (courseNotices.isNotEmpty
                    ? SyncSourcePhase.partial
                    : SyncSourcePhase.failed)
                : SyncSourcePhase.success,
            succeededCourses: courseNoticeFailed ? 0 : 1,
            failedCourses: courseNoticeFailed ? 1 : 0,
            recordCount: courseNotices.length,
            unconfirmedCount:
                courseNotices.where((n) => !n.publishedTrusted).length,
            reasonCodes: courseNoticeFailed
                ? const ['listOrMetadataUnavailable']
                : const [],
          ),
      ];
    }
    if (!current()) return const [];
    // Missing observations invalidate personal status; disappearance is not a
    // cancellation or a submission. Preserve personal notes and stable IDs.
    final ids = rows.map((a) => a.id).toSet();
    final keys = refs.map((c) => '${c.courseId}:${c.clazzId}').toSet();
    for (final old in previousAssignments.values) {
      if (!old.isExam ||
          ids.contains(old.id) ||
          (!includeAccount && !keys.contains(old.courseKey))) {
        continue;
      }
      rows.add(old.copyWith(
          status: 'unknown',
          availability: AssignmentAvailability.unknown,
          clearCompletedAt: true,
          lastSyncedAt: DateTime.now()));
    }
    final enriched = ChaoxingExamParser.enrichNotices(rows);
    final freshNotices = enriched
        .where((a) => a.isExam && a.exam!.noticeOnly && ids.contains(a.id))
        .toList();
    sourceResults = [
      for (final source in sourceResults)
        if (source.source == 'examNotice')
          SyncSourceResult(
              source: source.source,
              phase: source.phase,
              succeededCourses: source.succeededCourses,
              failedCourses: source.failedCourses,
              recordCount: freshNotices.length,
              unconfirmedCount: freshNotices
                  .where((a) => a.status == 'unknown' || !a.timelineTrusted)
                  .length,
              reasonCodes: source.reasonCodes)
        else
          source
    ];
    return enriched;
  }

  Future<Response<dynamic>?> _examListGet(Uri uri,
      {required int generation}) async {
    final initial =
        uri.queryParameters.map((k, v) => MapEntry(k.toLowerCase(), v));
    final expectedCourse = initial['courseid'];
    final expectedClass = initial['classid'] ?? initial['clazzid'];
    for (var i = 0; i < 5; i++) {
      if (generation != _sessionGeneration) return null;
      if (uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          uri.port != 443 ||
          uri.hasFragment ||
          !uri.host.endsWith('.chaoxing.com') ||
          !const {
            '/visit/stucoursemiddle',
            '/mooc2-ans/mycourse/stu',
            '/phone/moocAnalysis/examList',
            '/mooc-ans/phone/moocAnalysis/examList',
            '/exam/test',
            '/exam-ans/exam/test',
            '/exam-ans/exam/test/examcode/examlist',
          }.contains(uri.path)) {
        throw StateError('unsafeExamRedirect');
      }
      final isCoursePage = uri.path == '/mooc2-ans/mycourse/stu';
      if (isCoursePage &&
          (uri.host != 'mooc2-ans.chaoxing.com' ||
              expectedCourse == null ||
              expectedClass == null)) {
        throw StateError('unsafeExamRedirect');
      }
      final found = <String>{};
      for (final entry in uri.queryParametersAll.entries) {
        final key = entry.key.toLowerCase();
        final expected = key == 'courseid'
            ? expectedCourse
            : const {'classid', 'clazzid'}.contains(key)
                ? expectedClass
                : null;
        if (expected == null) continue;
        if (entry.value.any((v) => v != expected)) {
          throw StateError('unsafeExamRedirect');
        }
        found.add(key == 'courseid' ? 'course' : 'class');
      }
      if (isCoursePage && found.length != 2) {
        throw StateError('unsafeExamRedirect');
      }
      final response = await _readCourseEntryOrGet(uri,
          generation: generation,
          requestKind: uri.path.contains('/examcode/examlist')
              ? '账号考试'
              : uri.path == '/visit/stucoursemiddle'
                  ? '课程入口'
                  : '课程考试');
      if (generation != _sessionGeneration) return null;
      if (response == null || (response.statusCode ?? 0) < 300) return response;
      final location = response.headers.value('location');
      if (location == null) throw StateError('examRedirectMissing');
      uri = uri.resolve(location);
    }
    throw StateError('examRedirectLimit');
  }
}

part of 'chaoxing_local_client.dart';

extension _CourseworkClient on ChaoxingLocalClient {
  Future<List<Assignment>> _fetchAssignmentsForCourse(
      {required String courseId, required String clazzId}) async {
    _startRequestToken();
    final generation = _sessionGeneration;
    final syncWatch = Stopwatch()..start();
    _resetSyncTracking(clearRequestStats: false);
    _verificationTarget = null;
    _courseVerificationProbe = null;
    final entryCache = _syncCourseEntries = <String, Response<dynamic>>{};
    final examEntryCourses = _syncExamEntryCourses = <String>{};
    issues = [];
    sourceResults = const [];
    _deadlineReadsBlockedBy = null;
    detailUnconfirmedCount = 0;
    _detailUnconfirmedCourseKeys.clear();
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
              ChaoxingRequestPolicy.decodeJsonPayload(response?.data)));
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
      if (rows == null) {
        _syncCourseEntries?.clear();
        _syncExamEntryCourses?.clear();
      }
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
      if (identical(_syncExamEntryCourses, examEntryCourses)) {
        _syncExamEntryCourses = null;
      }
      if (generation == _sessionGeneration) {
        _fullSyncElapsedMs = syncWatch.elapsedMilliseconds;
      }
    }
  }

  /// Fetches ONLY the single visited non-exam target within its course without
  /// scanning other assignments' detail pages, classroom activities, or exams.
  Future<Assignment?> _fetchReturnedWork(Assignment target) async {
    if (target.isExam ||
        target.courseId == null ||
        target.clazzId == null ||
        (!target.isFormal && !target.isSupportedClassroomTask)) {
      return null;
    }
    _startRequestToken();
    final generation = _sessionGeneration;
    _verificationTarget = null;
    _courseVerificationProbe = null;
    final entryCache = _syncCourseEntries = <String, Response<dynamic>>{};
    final examEntryCourses = _syncExamEntryCourses = <String>{};
    issues = [];
    sourceResults = const [];
    _deadlineReadsBlockedBy = null;
    detailUnconfirmedCount = 0;
    _detailUnconfirmedCourseKeys.clear();
    try {
      final mcode =
          _readCookie('UID') ?? _readCookie('uid') ?? _readCookie('_uid');
      final response = await _safeGet<dynamic>(
        'https://mooc1-api.chaoxing.com/mycourse/backclazzdata',
        queryParameters: {'view': 'json', if (mcode != null) 'mcode': mcode},
      );
      if (generation != _sessionGeneration) return null;
      final refs = _measureParse(
        '课程列表',
        () => ChaoxingApiParser.parseCourseRefs(
          ChaoxingRequestPolicy.decodeJsonPayload(response?.data),
        ),
      );
      final course = refs
          .where(
            (c) => c.courseId == target.courseId && c.clazzId == target.clazzId,
          )
          .firstOrNull;
      if (course == null) return null;

      bool matchesTarget(Assignment candidate) =>
          candidate.id == target.id ||
          (target.courseTaskKey != null &&
              candidate.courseTaskKey == target.courseTaskKey);

      if (target.isSupportedClassroomTask) {
        if (!enableClassroomTasks) return null;
        final uid =
            _readCookie('UID') ?? _readCookie('uid') ?? _readCookie('_uid');
        final courseProbe = _courseVerificationEntry(course);
        _courseVerificationProbe = courseProbe;
        final activityResp = await _safeGet<dynamic>(
          'https://mobilelearn.chaoxing.com/v2/apis/active/student/activelist',
          queryParameters: {
            'fid': 0,
            'courseId': course.courseId,
            'classId': course.clazzId,
            'showNotStartedActive': 0,
          },
          requestKind: '课堂活动列表',
          verificationProbe: courseProbe,
        );
        if (generation != _sessionGeneration) return null;
        final activities = _measureParse(
          '课堂活动列表',
          () => ChaoxingClassroomParser.readActivityList(
            ChaoxingRequestPolicy.decodeJsonPayload(activityResp?.data),
            courseId: course.courseId,
            clazzId: course.clazzId,
            courseName: course.courseName,
          ),
        );
        final seeds = activities.entries
            .where((entry) => entry.canHydrate && matchesTarget(entry.seed))
            .map((entry) => entry.seed)
            .toList();
        if (seeds.length != 1) return null;
        final hydrated = await _hydrateClassroomTask(
          seeds.single,
          uid: uid,
          generation: generation,
          expectedCpi: course.cpi,
          verificationProbe: courseProbe,
        );
        if (generation != _sessionGeneration) return null;
        return matchesTarget(hydrated) ? hydrated : null;
      }

      final work = await _fetchCourseWork(
        course,
        generation: generation,
        targetAssignmentId: target.id,
        targetCourseTaskKey: target.courseTaskKey,
      );
      if (generation != _sessionGeneration || work == null) return null;
      final matches = work.where(matchesTarget).toList();
      return matches.length == 1 ? matches.single : null;
    } finally {
      if (identical(_syncCourseEntries, entryCache)) _syncCourseEntries = null;
      if (identical(_syncExamEntryCourses, examEntryCourses)) {
        _syncExamEntryCourses = null;
      }
    }
  }

  Future<List<Assignment>> _fetchAssignmentsWithOptions({
    bool collectCourseNotices = false,
    bool enableTaskEngineProbe = false,
  }) async {
    _collectCourseNoticesInNextSync = collectCourseNotices;
    _enableTaskEngineProbeInNextSync = enableTaskEngineProbe;
    try {
      // Keep the virtual call explicit in the part implementation.
      // ignore: unnecessary_this
      return await this.fetchAssignments();
    } finally {
      _collectCourseNoticesInNextSync = false;
      _enableTaskEngineProbeInNextSync = false;
      nextSyncCourseSelector = null;
    }
  }

  Future<List<Assignment>> _fetchAssignments() async {
    final collectNotices = _collectCourseNoticesInNextSync;
    final enableProbe = _enableTaskEngineProbeInNextSync;
    final courseSelector = nextSyncCourseSelector;
    _collectCourseNoticesInNextSync = false;
    _enableTaskEngineProbeInNextSync = false;
    nextSyncCourseSelector = null;
    _lastFetchedNotices = const [];
    _startRequestToken();
    final generation = _sessionGeneration;
    final syncWatch = Stopwatch()..start();
    _resetSyncTracking(clearRequestStats: true);
    _verificationTarget = null;
    _courseVerificationProbe = null;
    final entryCache = _syncCourseEntries = <String, Response<dynamic>>{};
    final examEntryCourses = _syncExamEntryCourses = <String>{};
    final progress =
        onProgress == null ? null : _SyncProgressTracker(onProgress!);
    progress?.setStage(AssignmentSyncStage.courses);
    lastSyncWarning = null;
    _deadlineReadsBlockedBy = null;
    issues = [];
    sourceResults = const [];
    hasCourseResponse = false;
    lastSyncScope = AssignmentSyncScope.all;
    plannedCourses = 0;
    skippedCourses = 0;
    lastPlannedCourseKeys = const {};
    lastFailedCourseKeys = const {};
    _lastExamFailedCourseKeys.clear();
    final trackedFailedCourseKeys = <String>{};
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
        final payload = ChaoxingRequestPolicy.decodeJsonPayload(response?.data);
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
      final selection = courseSelector != null
          ? courseSelector(courses)
          : SyncScopeSelection.all(courses);
      final targetCourses = selection.targetCourses;
      lastSyncScope = selection.scope;
      plannedCourses = targetCourses.length;
      skippedCourses = selection.skippedCourseKeys.length;
      lastPlannedCourseKeys = Set.unmodifiable(
        targetCourses.map(SyncScopeSelection.courseKeyOf),
      );
      progress?.setScopeCounts(
        planned: plannedCourses,
        skipped: skippedCourses,
      );
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
      var recognized =
          courses.isEmpty || (targetCourses.isEmpty && invalidCourseCount == 0);
      final formalWatch = Stopwatch()..start();
      for (final course in targetCourses) {
        if (shouldStop?.call() == true) {
          formalFailedCourseKeys.addAll(targetCourses
              .skip(targetCourses.indexOf(course))
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
          _syncExamEntryCourses?.clear();
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
          progress?.markCourseFinished(failed: true);
          if (issue.kind == SyncIssueKind.verificationRequired) {
            formalFailedCourseKeys.addAll(targetCourses
                .skip(targetCourses.indexOf(course))
                .map((c) => '${c.courseId}:${c.clazzId}'));
            break;
          }
        } else {
          recognized = true;
          succeededCourses++;
          assignments.addAll(work);
          progress?.markCourseFinished(failed: false);
          if (work.any((a) => a.deadlineReadFailed)) {
            problems.add('$label 部分截止时间未读取');
          }
        }
        if (_deadlineReadsBlockedBy != null) {
          final unread =
              targetCourses.length - targetCourses.indexOf(course) - 1;
          if (unread > 0) {
            issues.add(SyncIssue(
                _deadlineReadsBlockedBy!, '本次读取已暂停，另有 $unread 门课程尚未更新',
                stage: 'workList'));
            for (final remaining
                in targetCourses.skip(targetCourses.indexOf(course) + 1)) {
              formalFailedCourseKeys
                  .add('${remaining.courseId}:${remaining.clazzId}');
            }
          }
          break;
        }
      }
      _recordPhase('formalWork', formalWatch);
      trackedFailedCourseKeys.addAll(formalFailedCourseKeys);
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
      final classroom = await _fetchClassroomTasks(targetCourses,
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
      trackedFailedCourseKeys.addAll(failedCourseKeys);
      failedCourses = invalidCourseCount + failedCourseKeys.length;
      if (classroom.failedCourses > 0) {
        problems.add('部分课堂任务信息尚未读取');
      }
      if (enableExams) {
        progress?.setStage(AssignmentSyncStage.exams);
      }
      final examWatch = Stopwatch()..start();
      final exams = await _fetchExams(
        targetCourses,
        generation: generation,
        includeAccount: selection.includeAccountExams,
        collectCourseNotices: collectNotices,
        skippedCourseKeys: selection.skippedCourseKeys,
        noticeCatalog: courses,
      );
      _recordPhase('exams', examWatch);
      trackedFailedCourseKeys.addAll(_lastExamFailedCourseKeys);
      if (generation != _sessionGeneration) return const [];
      assignments.addAll(exams);
      recognized = recognized || _hasExamObservation;
      if (enableProbe && enableClassroomTasks && targetCourses.isNotEmpty) {
        final probeWatch = Stopwatch()..start();
        if (_verificationRequiredThisSync) {
          sourceResults = [
            ...sourceResults,
            _verificationPausedSource('taskEnginePlan', targetCourses.length),
          ];
        } else {
          await _probeTaskEnginePlans(targetCourses, generation: generation);
          _recordPhase('taskEnginePlan', probeWatch);
        }
        if (generation != _sessionGeneration) return const [];
      }
      bool examSourceIncomplete(SyncSourceResult s) =>
          const {'exam', 'examAccount', 'examNotice'}.contains(s.source) &&
          s.phase != SyncSourcePhase.success &&
          !s.isNormalDegradation;
      if (sourceResults.any(examSourceIncomplete)) {
        problems.add('部分考试或通知来源尚未读取');
      }
      if (_verificationRequiredThisSync) {
        lastSyncWarning = '学习通要求人工验证，已暂停剩余读取';
      } else if (problems.isNotEmpty) {
        final examProblem = sourceResults.any(examSourceIncomplete);
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
      lastFailedCourseKeys = Set.unmodifiable({
        ...trackedFailedCourseKeys,
        ..._lastExamFailedCourseKeys,
      });
      if (identical(_syncCourseEntries, entryCache)) _syncCourseEntries = null;
      if (identical(_syncExamEntryCourses, examEntryCourses)) {
        _syncExamEntryCourses = null;
      }
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
        final decoded = ChaoxingRequestPolicy.decodeJsonPayload(response?.data);
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

  Future<CourseChapterSnapshot> _fetchCourseChapters(
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
      headers: {'User-Agent': ChaoxingLocalClient.courseUserAgent},
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
      List<Assignment> rows, int succeeded, int failed) {
    final verificationPaused =
        _deadlineReadsBlockedBy == SyncIssueKind.verificationRequired ||
            issues.any((issue) =>
                issue.kind == SyncIssueKind.verificationRequired &&
                const {'courses', 'coursePage', 'work', 'workList', 'detail'}
                    .contains(issue.stage));
    return SyncSourceResult(
        source: 'courseWork',
        phase: failed == 0 && !verificationPaused
            ? SyncSourcePhase.success
            : succeeded > 0 || rows.isNotEmpty
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
        detailUnconfirmedCount: detailUnconfirmedCount,
        reasonCodes: [
          if (failed > 0) 'listOrMetadataUnavailable',
          if (verificationPaused) 'verificationPaused',
        ]);
  }

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
      final ({
        List<({Assignment seed, bool canHydrate})> entries,
        Set<int> incompleteTypes
      }) activities;
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
                ChaoxingRequestPolicy.decodeJsonPayload(response?.data),
                courseId: course.courseId,
                clazzId: course.clazzId,
                courseName: course.courseName));
        recognized = recognized ||
            activities.entries.isNotEmpty ||
            activities.incompleteTypes.length <
                ChaoxingClassroomParser.activityTypes.length;
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
      if (activities.incompleteTypes.isNotEmpty) {
        issues.add(_classroomIssue(const FormatException('activityIdentity')));
        for (final type in activities.incompleteTypes) {
          reasons[type]!.add('activityIdentityFailed');
        }
      }
      for (final type in ChaoxingClassroomParser.activityTypes) {
        var complete = !activities.incompleteTypes.contains(type);
        final sourceCourseKey =
            '${course.courseId}:${course.clazzId}:classroomActivity:$type';
        try {
          final entries = activities.entries
              .where((entry) => entry.seed.activityType == type)
              .toList();
          if (listBlockedBy == SyncIssueKind.verificationRequired) {
            complete = false;
            reasons[type]!.add('verificationPaused');
          } else {
            progress?.addRows([for (final entry in entries) entry.seed],
                courseKey: sourceCourseKey);
          }
          if (!isCurrent()) return stale;
          for (final (:seed, :canHydrate) in entries) {
            if (listBlockedBy == SyncIssueKind.verificationRequired) {
              // A paused source must not replace a cached row with an unread seed.
              progress?.discard(seed.id, courseKey: sourceCourseKey);
              if (!isCurrent()) return stale;
              continue;
            }
            Assignment task = seed;
            progress?.attempt(seed.id);
            if (!isCurrent()) return stale;
            if (blockedTypes.contains(type) || shouldStop?.call() == true) {
              complete = false;
              reasons[type]!.add('sourceReadStopped');
            } else if (canHydrate) {
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
                  reasons[type]!.add('verificationPaused');
                  progress?.discard(seed.id, courseKey: sourceCourseKey);
                  if (!isCurrent()) return stale;
                  continue;
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
          progress?.retractCourse(sourceCourseKey);
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
      return ChaoxingAiPracticeParser.personal(seed,
          ChaoxingRequestPolicy.decodeJsonPayload(response?.data), context);
    }
    final kind = seed.activityType == 35 ? '个人分组任务' : '随堂练习';
    Future<dynamic> read(String path, Map<String, dynamic> parameters) async {
      final response = await _safeGet<dynamic>(
          'https://mobilelearn.chaoxing.com$path',
          queryParameters: parameters,
          requestKind: kind,
          verificationProbe: verificationProbe);
      if (generation != _sessionGeneration) return null;
      return ChaoxingRequestPolicy.decodeJsonPayload(response?.data);
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

  Future<List<Assignment>?> _fetchCourseWork(
    ChaoxingCourseRef course, {
    required int generation,
    _SyncProgressTracker? progress,
    String? targetAssignmentId,
    String? targetCourseTaskKey,
  }) async {
    final courseUri = _courseVerificationEntry(course);
    _courseVerificationProbe = courseUri;
    if (_v3FormalApiConfirmed) {
      return _fetchV3FormalHomework(
        course,
        generation: generation,
        progress: progress,
        verificationProbe: courseUri,
        targetAssignmentId: targetAssignmentId,
        targetCourseTaskKey: targetCourseTaskKey,
      );
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
      final isVue = html.contains('/mooc2-ans-vue/') ||
          _ExamCollection._isVueExamCoursePath(middle?.realUri.path ?? '');
      if (middle?.statusCode == 200 && isVue) {
        _sessionVueExamCourses.add('${course.courseId}:${course.clazzId}');
      }
      if (isVue || middle?.statusCode == 200) {
        try {
          final work = await _fetchV3FormalHomework(
            course,
            generation: generation,
            progress: progress,
            verificationProbe: courseUri,
            targetAssignmentId: targetAssignmentId,
            targetCourseTaskKey: targetCourseTaskKey,
          );
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
    if (generation != _sessionGeneration || _stopRequested) return null;
    final parseWatch = Stopwatch()..start();
    final List<Assignment>? parsed;
    try {
      parsed = await ChaoxingAssignmentParser.parseSignedWorkListAsync(
        list?.data?.toString() ?? '',
        courseId: course.courseId,
        clazzId: course.clazzId,
        courseName: course.courseName,
        baseUri: uri,
      );
    } catch (_) {
      if (generation != _sessionGeneration || _stopRequested) return null;
      _recordParse('作业列表', parseWatch.elapsedMilliseconds, failed: true);
      rethrow;
    }
    if (generation != _sessionGeneration || _stopRequested) return null;
    _recordParse('作业列表', parseWatch.elapsedMilliseconds);
    if (parsed == null) {
      _noteParseFailure('作业列表');
      return null;
    }
    if (targetAssignmentId != null || targetCourseTaskKey != null) {
      final targeted = parsed
          .where((row) =>
              row.id == targetAssignmentId ||
              (targetCourseTaskKey != null &&
                  row.courseTaskKey == targetCourseTaskKey))
          .toList();
      if (targeted.length != 1) return const [];
      return _hydrateWorkDeadlines(targeted,
          generation: generation,
          verificationProbe: courseUri,
          readStartTimes: () async => (await _readV3FormalHomework(course,
                  generation: generation,
                  requestKind: '截止时间佐证',
                  verificationProbe: courseUri,
                  targetAssignmentId: targetAssignmentId,
                  targetCourseTaskKey: targetCourseTaskKey))
              .starts);
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
        headers: {'User-Agent': ChaoxingLocalClient.courseUserAgent},
        verificationProbe: verificationProbe);
    if (generation != _sessionGeneration) return null;
    final payload = _measureParse(
        '课程导航', () => ChaoxingRequestPolicy.decodeJsonPayload(response?.data));
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
                ChaoxingParamHelper.singleQueryValue(
                        target, ChaoxingParamHelper.courseIdKeys) ==
                    course.courseId &&
                ChaoxingParamHelper.singleQueryValue(
                        target, ChaoxingParamHelper.clazzIdKeys) ==
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
  Future<List<Assignment>> _fetchV3FormalHomework(
    ChaoxingCourseRef course, {
    required int generation,
    _SyncProgressTracker? progress,
    Uri? verificationProbe,
    String? targetAssignmentId,
    String? targetCourseTaskKey,
  }) async {
    final list = await _readV3FormalHomework(
      course,
      generation: generation,
      progress: progress,
      verificationProbe: verificationProbe,
      targetAssignmentId: targetAssignmentId,
      targetCourseTaskKey: targetCourseTaskKey,
    );
    if (generation != _sessionGeneration) return const [];
    return _hydrateWorkDeadlines(list.rows,
        generation: generation,
        starts: list.starts,
        progress: progress,
        verificationProbe: verificationProbe);
  }

  bool _matchesOptionalWorkIdentity(
      Uri uri, Set<String> keys, String expected) {
    final value = ChaoxingParamHelper.singleQueryValue(uri, keys);
    return value == expected ||
        (value == null && !ChaoxingParamHelper.hasAnyQueryValue(uri, keys));
  }

  Future<({List<Assignment> rows, Map<String, DateTime> starts})>
      _readV3FormalHomework(
    ChaoxingCourseRef course, {
    required int generation,
    _SyncProgressTracker? progress,
    String requestKind = '作业列表',
    Uri? verificationProbe,
    String? targetAssignmentId,
    String? targetCourseTaskKey,
  }) async {
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
            headers: {'User-Agent': ChaoxingLocalClient.courseUserAgent});
        if (generation != _sessionGeneration) {
          progress?.retractCourse(courseKey);
          return (
            rows: const <Assignment>[],
            starts: const <String, DateTime>{}
          );
        }
        final pageRows = <Assignment>[];
        final pageResult = _measureParse('作业列表', () {
          final payload =
              ChaoxingRequestPolicy.decodeJsonPayload(response?.data);
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
            final id = url == null
                ? null
                : ChaoxingParamHelper.singleQueryValue(
                    url, ChaoxingParamHelper.workIdKeys);
            if (url == null ||
                url.scheme != 'https' ||
                !url.host.endsWith('.chaoxing.com') ||
                id == null ||
                id.isEmpty ||
                !url.path.contains('/work/') ||
                !_matchesOptionalWorkIdentity(
                    url, ChaoxingParamHelper.courseIdKeys, course.courseId) ||
                !_matchesOptionalWorkIdentity(
                    url, ChaoxingParamHelper.clazzIdKeys, course.clazzId)) {
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
                  DateTime.fromMillisecondsSinceEpoch(start);
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
        if (targetAssignmentId != null || targetCourseTaskKey != null) {
          final targeted = pageRows
              .where((row) =>
                  row.id == targetAssignmentId ||
                  (targetCourseTaskKey != null &&
                      row.courseTaskKey == targetCourseTaskKey))
              .toList();
          if (targeted.length == 1) {
            return (rows: targeted, starts: starts);
          }
          if (targeted.length > 1) {
            return (rows: const <Assignment>[], starts: starts);
          }
        }
        if (result.length == pageResult.total) {
          if (targetAssignmentId != null || targetCourseTaskKey != null) {
            return (rows: const <Assignment>[], starts: starts);
          }
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

  List<Assignment> _dedupeAssignments(List<Assignment> assignments) {
    final byId = <String, Assignment>{};
    for (final assignment in assignments) {
      byId[assignment.id] = assignment;
    }
    return byId.values.toList()..sort(Assignment.compareByDeadline);
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
  int plannedCourses = 0;
  int completedCourses = 0;
  int skippedCourses = 0;
  int failedCourses = 0;

  void setScopeCounts({required int planned, required int skipped}) {
    plannedCourses = planned;
    skippedCourses = skipped;
    _emit();
  }

  void markCourseFinished({required bool failed}) {
    if (failed) {
      failedCourses++;
    } else {
      completedCourses++;
    }
    _emit();
  }

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

  void discard(String id, {required String courseKey}) {
    if (assignments.remove(id) == null) return;
    _courseRowIds[courseKey]?.remove(id);
    pendingDetailIds.remove(id);
    _unconfirmedIds.remove(id);
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
      plannedCourses: plannedCourses,
      completedCourses: completedCourses,
      skippedCourses: skippedCourses,
      failedCourses: failedCourses,
    ));
  }
}

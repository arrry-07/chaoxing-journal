// Keep explicit receivers on calls that dispatch through the store.
// ignore_for_file: unnecessary_this

part of 'assignment_store.dart';

extension _AssignmentStoreSync on AssignmentStore {
  String _exportSanitizedSyncDiagnostics() =>
      ChaoxingSyncDiagnosticsExporter.exportJson(
        appVersion: AppVersion.display,
        report: syncReport,
        phaseElapsedMs: chaoxingClient.diagnostics.phaseElapsedMs,
        requestTimings: chaoxingClient.requestTimings,
      );

  String get _syncSummary {
    if (_warningBuckets.isNotEmpty && syncReport.phase == SyncPhase.success) {
      return this.hasWidgetWarningOnly ? '作业已更新，小组件需要处理' : '作业已更新，提醒或小组件需要处理';
    }
    return syncReport.summary;
  }

  DateTime? get _effectiveLastSyncAt =>
      _lastSyncAt ??
      (syncReport.phase == SyncPhase.success
          ? syncReport.lastFullSuccessAt
          : null);

  List<Assignment> get _visibleAssignments => AssignmentQuery.currentDisplay(
        this.courseAssignments,
        _clock(),
        coursework: _authenticated
            ? _courseworkState
            : const LocalCourseworkState.empty(),
      );

  List<Assignment> get _homeDisplayAssignments {
    return AssignmentQuery.currentDisplay(
      this.homeCatalogAssignments,
      DateTime.now(),
      index: this.homeDisplayIndex,
      coursework: _authenticated
          ? _courseworkState
          : const LocalCourseworkState.empty(),
    );
  }

  List<Assignment> get _homeCatalogAssignments {
    if (_homeCatalogCache != null) return _homeCatalogCache!;
    if (_homePreviewAssignments.isEmpty) {
      final sources = this.courseAssignments;
      // The store's own snapshot is already scoped and immutable. Overrides
      // keep the same filtering and snapshot semantics as before.
      final next = identical(sources, _courseworkSourcesCache)
          ? sources
          : List<Assignment>.unmodifiable(AssignmentQuery.scope(sources, {}));
      _homeCatalogCache = next;
      return next;
    }
    final merged = LocalAssignmentRepository.mergeAssignments(
      [..._assignments, ..._hiddenAssignments],
      _homePreviewAssignments,
      hiddenCompletedIds:
          _hiddenAssignments.map((assignment) => assignment.id).toSet(),
      includeCompleted: true,
    );
    final hiddenIds =
        _hiddenAssignments.map((assignment) => assignment.id).toSet();
    final next = List<Assignment>.unmodifiable([
      for (final group in AssignmentGrouping.group(
        _catalogAssignmentsFrom(merged),
        hiddenIds: hiddenIds,
      ))
        if (!group.hidden) ...group.sources,
    ]);
    _homeCatalogCache = next;
    return next;
  }

  AssignmentDisplayIndex get _resolveHomeDisplayIndex => _homeDisplayIndex ??=
      AssignmentDisplayIndex.from(this.homeCatalogAssignments);

  bool _isHomeAssignmentPreviewOnly(String assignmentId) {
    if (_homePreviewAssignments.isEmpty) return false;
    final previewIds =
        _previewIdsCache ??= {for (final a in _homePreviewAssignments) a.id};
    if (!previewIds.contains(assignmentId)) return false;
    final persistedIds =
        _persistedIdsCache ??= {for (final a in _assignments) a.id};
    return !persistedIds.contains(assignmentId);
  }

  List<Assignment> _catalogAssignmentsFrom(Iterable<Assignment> records) =>
      AssignmentQuery.scope(records.toList(), {})
          .where((assignment) =>
              assignment.courseKey == null ||
              this.isCourseActive(assignment.courseKey!))
          .toList();

  Map<String, dynamic>? get _syncStatus => {
        'localOnly': true,
        'lastSyncedAt': _lastSyncAt?.toIso8601String(),
        'stale': _lastSyncAt == null ||
            DateTime.now().difference(_lastSyncAt!).inHours >= 24,
      };

  Future<bool> _syncCourseChapters({String? courseKey}) async {
    final account = _account;
    final epoch = _generation;
    if (account == null || !_authenticated) return false;
    var succeeded = false;
    await _run(() async {
      if (!_isSessionStateCurrent(
        epoch: epoch,
        account: account,
        checkAccount: true,
      )) {
        return;
      }
      _syncCancelled = false;
      final chapterOperation = ++_syncOperation;
      bool chapterCancelled() =>
          _syncCancelled || chapterOperation != _syncOperation;
      _isChapterSyncing = true;
      _chapterSyncProgressText = '正在准备读取章节进度…';
      this._notify();
      try {
        final targets = <ChaoxingCourseRef>[];
        final clientByKey = {
          for (final c in chaoxingClient.courses)
            '${c.courseId}:${c.clazzId}': c,
        };
        if (courseKey != null) {
          final match = clientByKey[courseKey] ??
              _courses
                  .where((c) => c.key == courseKey)
                  .map((c) => ChaoxingCourseRef(
                        courseId: c.courseId,
                        clazzId: c.clazzId,
                        courseName: c.name,
                        teacherNames: c.teacherNames,
                        folderName: c.folderName,
                        clazzName: c.clazzName,
                        courseStartAt: c.courseStartAt,
                        courseEndAt: c.courseEndAt,
                      ))
                  .firstOrNull;
          if (match != null) targets.add(match);
        } else {
          final followed = _courses
              .where((c) => this.follows(c.key))
              .toList(growable: false);
          for (final c in followed) {
            targets.add(clientByKey[c.key] ??
                ChaoxingCourseRef(
                  courseId: c.courseId,
                  clazzId: c.clazzId,
                  courseName: c.name,
                  teacherNames: c.teacherNames,
                  folderName: c.folderName,
                  clazzName: c.clazzName,
                  courseStartAt: c.courseStartAt,
                  courseEndAt: c.courseEndAt,
                ));
          }
        }
        if (targets.isEmpty) {
          _error = courseKey != null ? '未找到目标课程，请先同步课程列表' : '当前没有已关注的课程';
          return;
        }
        if (chaoxingClient.needsSessionInitialization) {
          await _refreshChaoxingSession(syncOperation: chapterOperation);
        }
        var updatedCount = 0;
        String? firstIssue;
        for (var i = 0; i < targets.length; i++) {
          if (!_isSessionStateCurrent(
            epoch: epoch,
            account: account,
            checkAccount: true,
            syncOperation: chapterOperation,
          )) {
            break;
          }
          final target = targets[i];
          _chapterSyncProgressText =
              '正在读取 ${target.courseName}（${i + 1}/${targets.length}）';
          this._notify();
          try {
            CourseChapterSnapshot snapshot;
            try {
              snapshot = await chaoxingClient.fetchCourseChapters(target);
            } on ChaoxingAuthenticationException {
              if (!_isSessionStateCurrent(
                epoch: epoch,
                syncOperation: chapterOperation,
              )) {
                break;
              }
              await _refreshChaoxingSession(syncOperation: chapterOperation);
              if (!_isSessionStateCurrent(
                epoch: epoch,
                syncOperation: chapterOperation,
              )) {
                break;
              }
              snapshot = await chaoxingClient.fetchCourseChapters(target);
            }
            if (chapterCancelled() ||
                _generation != epoch ||
                account != _account ||
                _disposed) {
              break;
            }
            final merged = _courseChapters.upsertCourse(snapshot);
            await repository.saveCourseChapters(merged, account);
            if (_generation != epoch || _disposed) break;
            _courseChapters = merged;
            updatedCount++;
            this._notify();
          } on StaleSessionWriteException {
            break;
          } on SyncReadException catch (e) {
            if (e.issue.kind == SyncIssueKind.cancelled) {
              _error = '已取消读取章节进度';
              break;
            }
            firstIssue ??= e.issue.message;
          } catch (e) {
            firstIssue ??= '${target.courseName} 章节进度读取失败：$e';
          }
        }
        succeeded =
            updatedCount > 0 && firstIssue == null && !chapterCancelled();
        if (chapterCancelled()) {
          _error = updatedCount > 0
              ? '已取消读取，已保存前 $updatedCount 门课的章节进度'
              : '已取消读取章节进度';
        } else if (firstIssue != null) {
          _error = updatedCount > 0
              ? '已更新 $updatedCount 门课章节进度；$firstIssue'
              : firstIssue;
        }
      } finally {
        _isChapterSyncing = false;
        _chapterSyncProgressText = null;
      }
    });
    return succeeded;
  }

  ReturnCheckConfirmation? _consumeReturnCheckConfirmation() {
    final current = _pendingReturnConfirmation;
    _pendingReturnConfirmation = null;
    return current;
  }

  void _beginAssignmentVisit(String id) {
    if (!_authenticated || this.findAssignment(id) == null) return;
    _visitedAssignment = id;
    _visitGeneration = _generation;
    _activeVisitTicket = ++_nextVisitTicket;
    _visitLeftApp = false;
    _pendingReturnConfirmation = null;
    returnCheckMessage = null;
  }

  void _cancelAssignmentVisit(String id) {
    if (_visitedAssignment == id) {
      _visitedAssignment = null;
      _activeVisitTicket = null;
      _visitLeftApp = false;
    }
  }

  void _markAssignmentVisitLeftApp() {
    if (_visitedAssignment != null && _activeVisitTicket != null) {
      _visitLeftApp = true;
    }
  }

  void _dismissReturnCheck() {
    returnCheckMessage = null;
    this._notify();
  }

  Future<void> _checkReturnedAssignment() async {
    final id = _visitedAssignment;
    final generation = _visitGeneration;
    final ticket = _activeVisitTicket;
    if (id == null || ticket == null || !_visitLeftApp) return;
    _visitedAssignment = null;
    _activeVisitTicket = null;
    _visitLeftApp = false;
    _pendingReturnConfirmation = null;
    if (generation == null || !_isSessionStateCurrent(epoch: generation)) {
      return;
    }
    final target = this.findAssignment(id);
    if (target == null ||
        (!target.isExam &&
            (target.courseId == null || target.clazzId == null))) {
      return;
    }
    returnCheckMessage = target.isExam ? '正在核对刚才考试的作答状态…' : '正在核对刚才作业的提交状态…';
    this._notify();
    var confirmed = false;
    await _run(() async {
      if (!_isSessionStateCurrent(epoch: generation)) return;
      if (chaoxingClient.needsSessionInitialization) {
        await _refreshChaoxingSession();
        if (!_isSessionStateCurrent(epoch: generation)) return;
      }
      chaoxingClient.previousAssignments = {
        for (final a in [..._assignments, ..._hiddenAssignments]) a.id: a
      };
      late List<Assignment> incoming;
      if (target.isExam) {
        try {
          incoming = target.courseId == null
              ? await chaoxingClient.fetchAssignments()
              : await chaoxingClient.fetchAssignmentsForCourse(
                  courseId: target.courseId!, clazzId: target.clazzId!);
        } on ChaoxingAuthenticationException {
          if (!_isSessionStateCurrent(epoch: generation)) return;
          await _refreshChaoxingSession();
          if (!_isSessionStateCurrent(epoch: generation)) return;
          incoming = target.courseId == null
              ? await chaoxingClient.fetchAssignments()
              : await chaoxingClient.fetchAssignmentsForCourse(
                  courseId: target.courseId!, clazzId: target.clazzId!);
        }
      } else {
        Assignment? single;
        try {
          single = await chaoxingClient.fetchReturnedWork(target);
        } on ChaoxingAuthenticationException {
          if (!_isSessionStateCurrent(epoch: generation)) return;
          await _refreshChaoxingSession();
          if (!_isSessionStateCurrent(epoch: generation)) return;
          single = await chaoxingClient.fetchReturnedWork(target);
        }
        incoming = single == null ? const <Assignment>[] : [single];
      }
      if (!_isSessionStateCurrent(epoch: generation)) return;
      final observed = incoming
          .where((a) =>
              a.id == id ||
              (target.courseTaskKey != null &&
                  a.courseTaskKey == target.courseTaskKey))
          .firstOrNull;
      final before = [..._assignments, ..._hiddenAssignments];
      final accepted = incoming
          .where((a) =>
              a.isExam ||
              a.isSupportedClassroomTask ||
              a.id != id ||
              a.statusLabel != '提交状态未知')
          .toList();
      await _markReminderMutationPending();
      await repository.mergeAndSave(accepted,
          completeSync: false,
          canCommit: () async => _isSessionStateCurrent(epoch: generation));
      if (!_isSessionStateCurrent(epoch: generation)) return;
      await _reloadJournal();
      if (!_isSessionStateCurrent(epoch: generation)) return;
      await _recordChanges(before, accepted);
      if (!_isSessionStateCurrent(epoch: generation)) return;
      if (repository.identityConflictCount > 0) {
        returnCheckMessage = '已读取最新状态，部分旧记录存在重复关联，已暂停其提醒；请查看本地记录。';
        confirmed = true;
        return;
      }
      final latestBefore =
          before.where((a) => a.id == id).firstOrNull ?? target;
      final conflictsWithConfirmation = latestBefore.isCompleted &&
          !latestBefore.isExam &&
          !latestBefore.isSupportedClassroomTask &&
          observed != null &&
          !observed.isCompleted &&
          observed.status != 'returned';
      final unconfirmed = observed == null ||
          observed.status == 'unknown' ||
          observed.statusLabel == '提交状态未知' ||
          conflictsWithConfirmation;
      if (unconfirmed) {
        returnCheckMessage = observed?.isSupportedClassroomTask == true
            ? '本次未能确认提交状态，已更新为待确认；确认前暂停提醒。'
            : '本次未能确认提交状态，已保留原记录；请稍后刷新核对。';
      } else if (observed.isCompleted) {
        if (!latestBefore.isCompleted) {
          final event = ReturnCheckConfirmation(
            id: ++_nextConfirmationId,
            accountEpoch: this.accountEpoch,
            assignmentId: observed.id,
            title: observed.title,
            message: '《${observed.title}》已确认提交',
            confirmedAt: _clock(),
          );
          _pendingReturnConfirmation = event;
          returnCheckMessage = event.message;
        } else {
          returnCheckMessage =
              '已确认提交：${observed.title}（${observed.statusLabel}）';
        }
      } else {
        returnCheckMessage = '刚才的作业仍为${observed.statusLabel}，提醒继续保留。';
      }
      confirmed = true;
    });
    if (!_isSessionStateCurrent(epoch: generation)) return;
    if (!confirmed) returnCheckMessage = '本次未能确认提交状态，已保留原记录和提醒；请稍后重试。';
    this._notify();
  }

  Future<void> _recordChanges(
    List<Assignment> before,
    List<Assignment> incoming, {
    bool completeSync = false,
    _SessionSnapshot? session,
  }) async {
    final snap = session ?? _captureSession();
    try {
      final after = [..._assignments, ..._hiddenAssignments];
      final observedIds = incoming.expand<String>((a) {
        final ids = after
            .where((saved) =>
                saved.id == a.id ||
                (a.courseTaskKey != null &&
                    saved.courseTaskKey == a.courseTaskKey))
            .map((saved) => saved.id)
            .toSet();
        return ids.isEmpty ? [a.id] : ids;
      }).toSet();
      final loaded = await _runScopedWrite(snap, (prefs) async {
        await changeLog.record(
          before,
          after,
          observedIds,
          completeSync: completeSync,
          prefs: prefs,
          at: _clock(),
        );
        return changeLog.load(prefs: prefs);
      });
      if (!_isSessionCurrent(snap)) return;
      changes = loaded;
      _termCatalogCache = null;
    } on StaleSessionWriteException {
      return;
    } catch (_) {
      if (snap.generation == _generation && !_disposed) {
        _recoveryWarnings.add('部分作业变化记录未能保存或读取，请稍后重试');
      }
    }
  }

  void _handleHomeProgress(int generation, AssignmentSyncProgress progress) {
    if (!_isSessionStateCurrent(epoch: generation)) return;
    _queuedHomeProgress = progress;
    final firstBatch =
        _homePreviewAssignments.isEmpty && progress.assignments.isNotEmpty;
    final finalDetails = progress.stage == AssignmentSyncStage.details &&
        progress.pendingDetailIds.isEmpty &&
        progress.resolvedCount >= progress.attemptedCount;
    final firstState = _homeSyncProgress == null;
    final stageChanged = _homeSyncProgress?.stage != progress.stage;
    if (firstBatch || finalDetails || firstState || stageChanged) {
      _publishHomeProgress(generation, progress);
      return;
    }
    _homeProgressTimer ??= Timer(const Duration(milliseconds: 100), () {
      _homeProgressTimer = null;
      if (!_isSessionStateCurrent(epoch: generation)) return;
      final latest = _queuedHomeProgress;
      if (latest != null) _publishHomeProgress(generation, latest);
    });
  }

  void _publishHomeProgress(int generation, AssignmentSyncProgress progress) {
    if (!_isSessionStateCurrent(epoch: generation)) return;
    _homeProgressTimer?.cancel();
    _homeProgressTimer = null;
    _queuedHomeProgress = null;
    _homeSyncProgress = progress;
    _homePreviewAssignments = List.of(progress.assignments);
    _homePendingDeadlineIds = Set.of(progress.pendingDetailIds);
    _invalidateHomeDisplayIndex();
    this._notify();
  }

  void _markHomePreviewSaving(int generation) {
    if (!_isSessionStateCurrent(epoch: generation)) return;
    // A retraction may still be waiting in the 100ms merge queue. Saving must
    // publish the newest snapshot, otherwise the failed course's temporary
    // rows reappear until the whole sync clears the preview.
    final progress = _queuedHomeProgress ?? _homeSyncProgress;
    if (progress == null) return;
    _publishHomeProgress(
      generation,
      AssignmentSyncProgress(
        stage: AssignmentSyncStage.saving,
        assignments: progress.assignments,
        pendingDetailIds: const {},
        resolvedCount: progress.resolvedCount,
        attemptedCount: progress.attemptedCount,
        unconfirmedCount: progress.unconfirmedCount,
        workListFailureCount: progress.workListFailureCount,
      ),
    );
  }

  void _clearHomePreview({bool notify = false}) {
    final hadPreview =
        _homePreviewAssignments.isNotEmpty || _homeSyncProgress != null;
    _homeProgressTimer?.cancel();
    _homeProgressTimer = null;
    _queuedHomeProgress = null;
    _homeSyncProgress = null;
    _homePreviewAssignments = [];
    _homePendingDeadlineIds = {};
    _invalidateHomeDisplayIndex();
    if (notify && hadPreview && !_disposed) this._notify();
  }

  void _cancelSynchronization() {
    _syncCancelled = true;
    _syncOperation++;
    _syncInFlight = null;
    chaoxingClient.cancelActiveRequests();
    _clearHomePreview(notify: true);
  }

  void _ensureSyncActive(int operation) {
    if (_disposed || _syncCancelled || operation != _syncOperation) {
      throw const SyncCancelledException();
    }
  }

  Future<void> _syncAssignmentsForTrigger(
    BackgroundSyncTrigger trigger, {
    bool skipTaskEngineProbe = false,
    AssignmentSyncScope? scope,
    Set<String>? targetedCourseKeys,
  }) async {
    await _syncForTrigger(
      trigger,
      skipTaskEngineProbe: skipTaskEngineProbe,
      scope: scope,
      targetedCourseKeys: targetedCourseKeys,
    );
  }

  Future<String?> _syncForTrigger(
    BackgroundSyncTrigger trigger, {
    bool skipTaskEngineProbe = false,
    AssignmentSyncScope? scope,
    Set<String>? targetedCourseKeys,
  }) {
    if (!_authenticated) return Future.value();
    final existing = _syncInFlight;
    if (existing != null) return existing;
    late final Future<String?> currentFuture;
    currentFuture = _performCoordinatedSync(
      trigger,
      skipTaskEngineProbe: skipTaskEngineProbe,
      scope: scope,
      targetedCourseKeys: targetedCourseKeys,
    ).whenComplete(() {
      if (identical(_syncInFlight, currentFuture)) {
        _syncInFlight = null;
      }
    });
    _syncInFlight = currentFuture;
    return currentFuture;
  }

  Future<String?> _performCoordinatedSync(
    BackgroundSyncTrigger trigger, {
    bool skipTaskEngineProbe = false,
    AssignmentSyncScope? scope,
    Set<String>? targetedCourseKeys,
  }) async {
    final operation = ++_syncOperation;
    final generation = _generation;
    _syncCancelled = false;
    _syncSkipReason = null;
    _syncSkipReasonOperation = null;
    _syncSkipReasonGeneration = null;
    final account = _account;
    final accountHash = _accountHash;
    final sessionEpoch = _nativeSessionEpoch;
    String? leaseRequest;
    DateTime? leaseRequestedAt;
    SyncLeaseResult? lease;
    if (_nativeReminderAvailable && accountHash != null) {
      leaseRequestedAt = DateTime.now();
      // The Worker's owner is stable for write leases and engine cleanup, but
      // every sync acquisition needs its own request id: native terminal ids
      // are tombstones and must never be reused by a later acquisition.
      final prefix = nativeLeaseOwner ??
          accountHash.substring(0, min(8, accountHash.length));
      leaseRequest = '$prefix-${leaseRequestedAt.microsecondsSinceEpoch}-'
          '${Random().nextInt(1 << 31)}';
      lease = await backgroundReminderGateway.acquireSyncLease(
        accountHash: accountHash,
        requestId: leaseRequest,
        requestedAt: leaseRequestedAt,
      );
      if (!lease.acquired) {
        if (_isSessionStateCurrent(
          epoch: generation,
          account: account,
          checkAccount: true,
          expectedAuthenticated: null,
          syncOperation: operation,
        )) {
          _backgroundWarning = '另一轮作业检查仍在进行，本次已合并等待';
          this._notify();
        }
        return null;
      }
    }
    try {
      if (!_isSessionStateCurrent(
        epoch: generation,
        expectedAuthenticated: null,
        syncOperation: operation,
      )) {
        return null;
      }
      if (lease != null &&
          lease.waited &&
          leaseRequestedAt != null &&
          (lease.lastAttemptAt?.isAfter(leaseRequestedAt) ?? false)) {
        if (lease.lastFullSuccessAt?.isAfter(leaseRequestedAt) ?? false) {
          await _run(_reloadJournal);
          return null;
        }
        _error = '另一轮作业检查未成功，本次合并到现有节奏，不立即重试';
        this._notify();
        return null;
      }
      if (trigger != BackgroundSyncTrigger.manual &&
          !DaytimeCheckPolicy.isInWindow(_clock())) {
        return BackgroundCheckResult.outsideWindowSkipReason;
      }
      await _run(() async {
        if (!_isSessionStateCurrent(
          epoch: generation,
          syncOperation: operation,
        )) {
          return;
        }
        if (_nativeReminderAvailable &&
            accountHash != null &&
            !await backgroundReminderGateway.isSessionCurrent(
              accountHash,
              sessionEpoch,
            )) {
          return;
        }
        if (!_isSessionStateCurrent(
          epoch: generation,
          syncOperation: operation,
        )) {
          return;
        }
        await _syncAssignmentsBody(
          trigger,
          operation: operation,
          skipTaskEngineProbe: skipTaskEngineProbe,
          scope: scope,
          targetedCourseKeys: targetedCourseKeys,
        );
        if (trigger == BackgroundSyncTrigger.daytime) {
          await _maybeRunHistoricalSweepAfterDaytimeSync(
            session: _captureSession(syncOperation: operation),
          );
        }
      });
      if (_syncSkipReasonOperation == operation &&
          _syncSkipReasonGeneration == generation) {
        return _syncSkipReason;
      }
      return null;
    } finally {
      if (accountHash != null &&
          leaseRequest != null &&
          lease != null &&
          lease.acquired) {
        try {
          await backgroundReminderGateway.releaseSyncLease(
            accountHash: accountHash,
            requestId: leaseRequest,
          );
        } catch (error) {
          // Keep the sync result intact; an unconfirmed release is visible and
          // the native engine-destroy path remains the safety net.
          if (_isSessionStateCurrent(
            epoch: generation,
            account: account,
            checkAccount: true,
            expectedAuthenticated: null,
          )) {
            _backgroundWarning = '同步租约释放未确认：$error';
            _warningBuckets.addServiceWarning(_backgroundWarning!);
            this._notify();
          }
        }
      }
    }
  }

  Future<void> _importAssignmentsFromHtml(String html) async {
    await _run(() async {
      final incoming = await ChaoxingAssignmentParser.parseWorkHtmlAsync(
        html,
        fallbackCourseName: '学习通课程',
        sourcePrefix: 'manual',
        baseUri: Uri.parse('https://mooc1.chaoxing.com'),
      );
      await _markReminderMutationPending();
      await repository.mergeAndSave(incoming, completeSync: false);
      await _reloadJournal();
    });
  }

  Future<void> _reloadJournal({
    bool completeSync = false,
    bool detectNewAssignments = false,
    bool syncCompleted = false,
    bool allowSourceBaselineUpdate = true,
    String? syncFailure,
    DateTime? completedAt,
  }) async {
    final generation = _generation;
    final journal = await repository.loadJournal();
    if (generation != _generation || _disposed) return;
    _assignments
      ..clear()
      ..addAll(journal);
    _hiddenAssignments = await repository.loadHiddenAssignments();
    if (generation != _generation || _disposed) return;
    _journalRestoreFailed = false;
    _invalidateHomeDisplayIndex();
    await _reconcileCourseworkState();
    if (generation != _generation || _disposed) return;
    final durableSyncAt = await repository.lastSyncAt();
    if (generation != _generation || _disposed) return;
    _lastSyncAt = durableSyncAt;
    var reportReconciled = false;
    if (durableSyncAt != null) {
      final fullTimestampMissingOrStale =
          syncReport.lastFullSuccessAt == null ||
              durableSyncAt.isAfter(syncReport.lastFullSuccessAt!);
      final dataTimestampMissingOrStale =
          syncReport.lastDataSuccessAt == null ||
              durableSyncAt.isAfter(syncReport.lastDataSuccessAt!);
      final interruptedAfterFullSave = fullTimestampMissingOrStale &&
          (syncReport.attemptedAt == null ||
              durableSyncAt.isAfter(syncReport.attemptedAt!));
      final reportMissingForDurableData = syncReport.phase == SyncPhase.idle;
      if (fullTimestampMissingOrStale ||
          dataTimestampMissingOrStale ||
          interruptedAfterFullSave ||
          reportMissingForDurableData) {
        syncReport = syncReport.copyWith(
          phase: interruptedAfterFullSave || reportMissingForDurableData
              ? SyncPhase.partial
              : null,
          lastDataSuccessAt: dataTimestampMissingOrStale ? durableSyncAt : null,
          lastFullSuccessAt: fullTimestampMissingOrStale ? durableSyncAt : null,
          issues: interruptedAfterFullSave
              ? [
                  ...syncReport.issues,
                  const SyncIssue(SyncIssueKind.storage,
                      '本机作业数据已完成保存，但最终同步报告中断；已从数据仓库恢复时间记录',
                      stage: 'persistence')
                ]
              : reportMissingForDurableData
                  ? [
                      ...syncReport.issues,
                      const SyncIssue(SyncIssueKind.storage,
                          '本机作业数据存在，但同步结果报告缺失或损坏；已从数据仓库恢复时间记录',
                          stage: 'persistence')
                    ]
                  : null,
        );
        reportReconciled = true;
      }
    }
    if (reportReconciled) {
      try {
        await _persistSyncReport();
      } on StaleSessionWriteException {
        return;
      } catch (error) {
        _recoveryWarnings.add('已从作业仓库恢复同步时间，但同步报告未能重新保存：$error');
      }
    }
    if (generation != _generation || _disposed) return;
    await _afterAssignmentsChanged(
      completeSync: completeSync,
      detectNewAssignments: detectNewAssignments,
      syncCompleted: syncCompleted,
      allowSourceBaselineUpdate: allowSourceBaselineUpdate,
      syncFailure: syncFailure,
      completedAt: completedAt,
    );
  }

  Future<bool> _reconcileExternalSyncState() async {
    final account = _account;
    final generation = _generation;
    if (!_authenticated ||
        account == null ||
        _loading ||
        _autoSyncRunning ||
        _disposed) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (!_isSessionStateCurrent(
          epoch: generation,
          account: account,
          checkAccount: true,
        ) ||
        _loading) {
      return false;
    }
    if (prefs.containsKey('journal_account_switch')) return false;
    final owner = prefs.getString('journal_account_owner');
    if (owner != null && owner != AccountIdentity.hash(account)) {
      return false;
    }
    final durableAttempt =
        DateTime.tryParse(prefs.getString('sync_attempt_at') ?? '')?.toLocal();
    final durableData =
        DateTime.tryParse(prefs.getString('sync_data_at') ?? '')?.toLocal();
    final attemptAdvanced = durableAttempt != null &&
        (_lastSyncAttemptAt == null ||
            durableAttempt.isAfter(_lastSyncAttemptAt!));
    final dataAdvanced = durableData != null &&
        (syncReport.lastDataSuccessAt == null ||
            durableData.isAfter(syncReport.lastDataSuccessAt!));
    if (!attemptAdvanced && !dataAdvanced) return false;

    var reconciled = false;
    await _run(() async {
      if (!_isSessionStateCurrent(
        epoch: generation,
        account: account,
        checkAccount: true,
      )) {
        return;
      }
      final refreshed = await SharedPreferences.getInstance();
      await refreshed.reload();
      if (refreshed.containsKey('journal_account_switch')) return;
      final currentOwner = refreshed.getString('journal_account_owner');
      if (currentOwner != null &&
          currentOwner != AccountIdentity.hash(account)) {
        return;
      }
      final nextAttempt =
          DateTime.tryParse(refreshed.getString('sync_attempt_at') ?? '')
              ?.toLocal();
      if (nextAttempt != null &&
          (_lastSyncAttemptAt == null ||
              nextAttempt.isAfter(_lastSyncAttemptAt!))) {
        _lastSyncAttemptAt = nextAttempt;
      }
      _serverBackoffUntil = DateTime.tryParse(
              refreshed.getString(AssignmentStore._serverBackoffKey) ?? '')
          ?.toLocal();
      final rawReport = refreshed.getString('sync_report_v1');
      if (rawReport != null) {
        try {
          final decoded = jsonDecode(rawReport);
          if (decoded is Map<String, dynamic>) {
            syncReport = SyncReport.fromJson(decoded);
          }
        } on FormatException catch (error) {
          debugPrint(
              '[AssignmentStore] reconcileSyncReport: ${error.runtimeType}');
        } on TypeError catch (error) {
          debugPrint(
              '[AssignmentStore] reconcileSyncReport: ${error.runtimeType}');
        } on ArgumentError catch (error) {
          debugPrint(
              '[AssignmentStore] reconcileSyncReport: ${error.runtimeType}');
        }
      }
      _courseworkState = await repository.loadCourseworkState(account);
      await _reloadJournal();
      reconciled = true;
    });
    return reconciled;
  }

  Future<bool> _runDueAutoSync({DateTime? now}) async {
    if (!_authenticated || _loading || _autoSyncRunning || _disposed) {
      return false;
    }
    await this.reconcileExternalSyncState();
    if (!_authenticated ||
        !_backgroundCheckSettings.enabled ||
        _loading ||
        _autoSyncRunning ||
        _disposed) {
      return false;
    }
    final currentNow = now ?? DateTime.now();
    if (!DaytimeCheckPolicy.isDue(
          localNow: currentNow,
          lastAttemptAt: _latestAttemptAt,
          intervalMinutes: _backgroundCheckSettings.intervalMinutes,
        ) ||
        (_serverBackoffUntil?.isAfter(currentNow) ?? false)) {
      return false;
    }

    _lastSyncAttemptAt = currentNow;
    _autoSyncRunning = true;
    try {
      await this.syncAssignmentsForTrigger(BackgroundSyncTrigger.foregroundDue);
      await _reconcileBackgroundControls(now: currentNow);
      return _error == null;
    } finally {
      _autoSyncRunning = false;
    }
  }

  Future<BackgroundCheckResult> _runBackgroundAutomaticCheckAndRecord(
    BackgroundSyncTrigger trigger,
  ) async {
    final result = await _runBackgroundAutomaticCheck(trigger);
    await _recordBackgroundCheckObservation(trigger, result);
    return result;
  }

  Future<BackgroundCheckResult> _runBackgroundAutomaticCheck(
    BackgroundSyncTrigger trigger,
  ) async {
    _remoteReadInvoked = false;
    final now = _clock();
    if (!_authenticated) {
      return const BackgroundCheckResult(
        success: false,
        skipped: true,
        nextTargetAt: null,
        message: '未登录',
      );
    }
    if (trigger == BackgroundSyncTrigger.daytime &&
        !_backgroundCheckSettings.enabled) {
      return const BackgroundCheckResult(
        success: false,
        skipped: true,
        nextTargetAt: null,
        message: '白天后台检查已关闭',
      );
    }
    if (trigger == BackgroundSyncTrigger.notificationSignal &&
        !_backgroundCheckSettings.notificationListenerEnabled) {
      return BackgroundCheckResult(
        success: false,
        skipped: true,
        nextTargetAt: null,
        message: '通知监听已关闭',
      );
    }
    if (!DaytimeCheckPolicy.isInWindow(now)) {
      return BackgroundCheckResult(
        success: false,
        skipped: true,
        nextTargetAt: trigger == BackgroundSyncTrigger.notificationSignal
            ? _nextNotificationWindowTarget(now)
            : _nextBackgroundTarget(now),
        message: '当前不在白天检查窗口',
        skipReason: BackgroundCheckResult.outsideWindowSkipReason,
        remoteReadInvoked: _remoteReadInvoked,
      );
    }
    if (trigger == BackgroundSyncTrigger.daytime &&
        !DaytimeCheckPolicy.isDue(
          localNow: now,
          lastAttemptAt: _latestAttemptAt,
          intervalMinutes: _backgroundCheckSettings.intervalMinutes,
        )) {
      return BackgroundCheckResult(
        success: true,
        skipped: true,
        nextTargetAt: _nextBackgroundTarget(now),
        message: '合并到已有检查节奏',
      );
    }
    final syncSkipReason = await _syncForTrigger(trigger);
    if (syncSkipReason == BackgroundCheckResult.outsideWindowSkipReason) {
      return BackgroundCheckResult(
        success: false,
        skipped: true,
        nextTargetAt: trigger == BackgroundSyncTrigger.notificationSignal
            ? _nextNotificationWindowTarget(_clock())
            : _nextBackgroundTarget(_clock()),
        message: '当前不在白天检查窗口',
        skipReason: BackgroundCheckResult.outsideWindowSkipReason,
        remoteReadInvoked: _remoteReadInvoked,
      );
    }
    final success = _error == null ||
        syncReport.phase == SyncPhase.success ||
        syncReport.phase == SyncPhase.partial;
    return BackgroundCheckResult(
      success: success && !_loading,
      skipped: false,
      nextTargetAt: trigger == BackgroundSyncTrigger.notificationSignal
          ? _nextNotificationWindowTarget(_clock())
          : _nextBackgroundTarget(_clock()),
      message: _error,
      remoteReadInvoked: _remoteReadInvoked,
    );
  }

  SyncCourseSelector _buildSyncCourseSelector(
    AssignmentSyncScope requestedScope,
    Set<String> targetedCourseKeys,
  ) =>
      AssignmentSyncCoordinator.buildSyncCourseSelector(
        scope: requestedScope,
        targetedCourseKeys: targetedCourseKeys,
        buildTermCatalog: (courses) => CourseTermCatalog.build(
          courses: courses,
          assignments: [..._assignments, ..._hiddenAssignments],
          notices: _courseNotices.items,
          preferences: _courseTermPreferences,
          now: _clock(),
          coursework: _courseworkState,
          unfollowedCourseKeys: _unfollowed,
          hiddenAssignmentIds: {for (final a in _hiddenAssignments) a.id},
          changes: changes,
        ),
      );

  Future<void> _maybeRunHistoricalSweepAfterDaytimeSync({
    required _SessionSnapshot session,
  }) async {
    if (!_isSessionCurrent(session) || _disposed || _syncCancelled) return;
    final plan = AssignmentSyncCoordinator.planHistoricalSweep(
      phase: syncReport.phase,
      operationError: _error,
      issues: chaoxingClient.issues,
      clock: _clock,
      serverBackoffUntil: _serverBackoffUntil,
      readTermCatalog: () => this.termCatalog,
      state: _historicalSweepState,
    );
    if (plan == null) return;

    final account = session.account;
    if (account == null) return;
    final canCommit = _scopedWriteGateFor(session);

    final savedReport = syncReport;
    final savedError = _error;
    final batchSet = plan.courseKeys.toSet();
    final priorRecords = [..._assignments, ..._hiddenAssignments];
    var swept = const <Assignment>[];
    var abortedMidBatch = false;
    try {
      chaoxingClient.nextSyncCourseSelector = _buildSyncCourseSelector(
        AssignmentSyncScope.historicalSweep,
        batchSet,
      );
      chaoxingClient.shouldStop =
          () => !DaytimeCheckPolicy.isInWindow(_clock());
      chaoxingClient.previousAssignments = {
        for (final a in priorRecords) a.id: a,
      };
      swept = await chaoxingClient.fetchAssignmentsWithOptions(
        collectCourseNotices: false,
        enableTaskEngineProbe: false,
      );
    } on SyncReadException catch (error) {
      if (error.issue.kind == SyncIssueKind.cancelled) {
        throw const SyncCancelledException();
      }
      abortedMidBatch = true;
    } on ChaoxingAuthenticationException {
      abortedMidBatch = true;
    } catch (_) {
      abortedMidBatch = true;
    } finally {
      chaoxingClient.onProgress = null;
      chaoxingClient.shouldStop = null;
      chaoxingClient.nextSyncCourseSelector = null;
    }

    if (!_isSessionCurrent(session) || _disposed || _syncCancelled) return;
    if (chaoxingClient.issues.isNotEmpty) {
      try {
        await _updateServerBackoff(chaoxingClient.issues, session: session);
      } catch (_) {/* Keep sweep non-blocking for daytime sync state. */}
    }

    final nextState = plan.recordResult(
      _historicalSweepState,
      reportedFailedKeys: chaoxingClient.lastFailedCourseKeys,
      abortedMidBatch: abortedMidBatch,
    );
    try {
      await repository.saveHistoricalSweepState(
        nextState,
        account,
        canCommit: canCommit,
      );
      if (!_isSessionCurrent(session)) return;
      _historicalSweepState = nextState;
    } on StaleSessionWriteException {
      return;
    } catch (_) {
      // Cursor persistence failure leaves old cursor intact without failing
      // the primary daytime sync.
    }

    if (swept.isNotEmpty && _isSessionCurrent(session)) {
      try {
        await _markReminderMutationPending();
        await repository.mergeAndSave(
          swept,
          completeSync: false,
          canCommit: canCommit,
        );
        if (_isSessionCurrent(session)) {
          await _reloadJournal(
            completeSync: false,
            detectNewAssignments: false,
            syncCompleted: true,
            allowSourceBaselineUpdate: false,
          );
        }
      } on StaleSessionWriteException {
        return;
      } catch (_) {
        // Keep primary daytime sync state intact when best-effort historical merge fails.
      }
    }
    if (_isSessionCurrent(session)) {
      syncReport = savedReport;
      _error = savedError;
    }
  }

  Future<void> _syncAssignmentsBody(
    BackgroundSyncTrigger trigger, {
    required int operation,
    bool skipTaskEngineProbe = false,
    AssignmentSyncScope? scope,
    Set<String>? targetedCourseKeys,
  }) async {
    final requestedScope = scope ?? AssignmentSyncScope.current;
    final targetedKeys =
        Set<String>.unmodifiable(targetedCourseKeys ?? const {});
    if (trigger == BackgroundSyncTrigger.manual) {
      _lastRequestedSyncScope = requestedScope;
      _lastTargetedCourseKeys = targetedKeys;
    }
    final priorCurrentSuccessAt = syncReport.lastCurrentSuccessAt;
    final priorFullSuccessAt = _lastSyncAt ?? syncReport.lastFullSuccessAt;
    _lastSyncSourceResults = const [];
    final syncSession = _captureSession(syncOperation: operation);
    final generation = syncSession.generation;
    final syncAccount = syncSession.account;
    _activeSyncSession = syncSession;
    final startedAt = _autoSyncRunning && _lastSyncAttemptAt != null
        ? _lastSyncAttemptAt!
        : _clock();
    final automatic = trigger != BackgroundSyncTrigger.manual;
    if (automatic && !DaytimeCheckPolicy.isInWindow(startedAt)) {
      _syncSkipReason = BackgroundCheckResult.outsideWindowSkipReason;
      _syncSkipReasonOperation = operation;
      _syncSkipReasonGeneration = generation;
      await _reconcileBackgroundControls(now: startedAt);
      return;
    }
    if (automatic && (_serverBackoffUntil?.isAfter(startedAt) ?? false)) {
      await _reconcileBackgroundControls(now: startedAt);
      return;
    }
    if (trigger == BackgroundSyncTrigger.notificationSignal &&
        notificationRemoteStart != null) {
      final authorization =
          await backgroundReminderGateway.authorizeNotificationRemoteStart(
        notificationRemoteStart!,
      );
      if (authorization == NotificationRemoteAuthorization.outsideWindow) {
        _syncSkipReason = BackgroundCheckResult.outsideWindowSkipReason;
        _syncSkipReasonOperation = operation;
        _syncSkipReasonGeneration = generation;
        await _reconcileBackgroundControls(now: startedAt);
        return;
      }
      if (authorization != NotificationRemoteAuthorization.granted) {
        _error = '提醒任务的会话已变化，已跳过本次后台读取';
        return;
      }
      if (!DaytimeCheckPolicy.isInWindow(_clock())) {
        _syncSkipReason = BackgroundCheckResult.outsideWindowSkipReason;
        _syncSkipReasonOperation = operation;
        _syncSkipReasonGeneration = generation;
        await _reconcileBackgroundControls(now: _clock());
        return;
      }
      _remoteReadInvoked = true;
    }
    final attempted = startedAt;
    _hadCacheBeforeLastSync =
        _assignments.isNotEmpty || _hiddenAssignments.isNotEmpty;
    _lastSyncAttemptAt = attempted;
    syncReport = SyncReport(
        phase: SyncPhase.running,
        attemptedAt: attempted,
        lastDataSuccessAt: syncReport.lastDataSuccessAt,
        lastCurrentSuccessAt: priorCurrentSuccessAt,
        lastFullSuccessAt: priorFullSuccessAt,
        syncScope: requestedScope);
    try {
      await _persistSyncReport(session: syncSession);
    } on StaleSessionWriteException {
      return;
    }
    this._notify();
    final bool attemptMirrorSaved;
    try {
      attemptMirrorSaved = await _writeScopedPreferenceAndVerify(
        'sync_attempt_at',
        attempted.toUtc().toIso8601String(),
        session: syncSession,
      );
    } on StaleSessionWriteException {
      return;
    }
    _ensureSyncActive(operation);
    if (chaoxingClient.needsSessionInitialization) {
      await _refreshChaoxingSession(syncOperation: operation);
      _ensureSyncActive(operation);
      if (!_isSessionCurrent(syncSession)) return;
      _needsProfileRecovery = false;
    }
    final previous = [..._assignments, ..._hiddenAssignments];
    chaoxingClient.previousAssignments = {for (final a in previous) a.id: a};
    chaoxingClient.trackedActivityIds = _assignments
        .followedBy(_hiddenAssignments)
        .where((a) => a.id.startsWith('cx:activity:'))
        .map((a) => a.id)
        .toSet();
    List<Assignment> incoming;
    final stopCheck =
        automatic ? () => !DaytimeCheckPolicy.isInWindow(_clock()) : null;
    chaoxingClient.shouldStop = stopCheck;
    final manualSync = trigger == BackgroundSyncTrigger.manual;
    final showPreview = manualSync;
    void attachProgress() {
      chaoxingClient.onProgress = showPreview
          ? (progress) => _handleHomeProgress(generation, progress)
          : null;
    }

    attachProgress();
    var savingStageMarked = false;
    var staleCourseWrite = false;
    // Persistence begins with the course cache; mark that stage before the
    // first write can suspend, not only before the journal merge.
    void markSavingStage() {
      if (savingStageMarked) return;
      savingStageMarked = true;
      _markHomePreviewSaving(generation);
    }

    try {
      chaoxingClient.nextSyncCourseSelector = _buildSyncCourseSelector(
        requestedScope,
        targetedKeys,
      );
      incoming = await chaoxingClient.fetchAssignmentsWithOptions(
        collectCourseNotices: manualSync,
        enableTaskEngineProbe: manualSync && !skipTaskEngineProbe,
      );
    } on ChaoxingAuthenticationException {
      chaoxingClient.onProgress = null;
      _clearHomePreview(notify: true);
      await _refreshChaoxingSession(syncOperation: operation);
      _ensureSyncActive(operation);
      if (!_isSessionCurrent(syncSession)) return;
      _needsProfileRecovery = false;
      attachProgress();
      chaoxingClient.nextSyncCourseSelector = _buildSyncCourseSelector(
        requestedScope,
        targetedKeys,
      );
      incoming = await chaoxingClient.fetchAssignmentsWithOptions(
        collectCourseNotices: manualSync,
        enableTaskEngineProbe: manualSync && !skipTaskEngineProbe,
      );
    } on SyncReadException catch (error) {
      if (error.issue.kind == SyncIssueKind.cancelled) {
        throw const SyncCancelledException();
      }
      rethrow;
    } finally {
      chaoxingClient.onProgress = null;
      chaoxingClient.shouldStop = null;
      chaoxingClient.nextSyncCourseSelector = null;
      if (_isSessionCurrent(syncSession) && chaoxingClient.hasCourseResponse) {
        final nextCourses = chaoxingClient.courses
            .map((c) => CourseRef(
                  courseId: c.courseId,
                  clazzId: c.clazzId,
                  name: c.courseName,
                  teacherNames: c.teacherNames,
                  folderName: c.folderName,
                  clazzName: c.clazzName,
                  courseStartAt: c.courseStartAt,
                  courseEndAt: c.courseEndAt,
                ))
            .toList();
        if (syncAccount == null) {
          throw StateError('当前学习通账号已变化，课程资料未保存');
        }
        markSavingStage();
        try {
          await repository.saveCourses(
            nextCourses,
            account: syncAccount,
            canCommit: _scopedWriteGateFor(syncSession),
          );
          if (_isSessionCurrent(syncSession)) {
            _courses = nextCourses;
            _invalidateHomeDisplayIndex();
          }
        } on StaleSessionWriteException {
          staleCourseWrite = true;
        }
      }
    }
    if (generation != _generation || _disposed) return;
    _ensureSyncActive(operation);
    if (staleCourseWrite) return;
    var warning = chaoxingClient.lastSyncWarning;
    // Snapshot scope, issues, sources, and counts before optional profile
    // recovery, because _refreshChaoxingSession() calls login()->clearSession()
    // and would otherwise wipe this round's sync telemetry.
    final usedSelector = chaoxingClient.hasCourseResponse;
    final effectiveScope = usedSelector
        ? chaoxingClient.lastSyncScope
        : (requestedScope == AssignmentSyncScope.targeted ||
                requestedScope == AssignmentSyncScope.historicalSweep
            ? requestedScope
            : AssignmentSyncScope.all);
    final plannedCount = usedSelector
        ? chaoxingClient.plannedCourses
        : (requestedScope == AssignmentSyncScope.targeted ||
                requestedScope == AssignmentSyncScope.historicalSweep
            ? targetedKeys.length
            : 0);
    final skippedCount = usedSelector ? chaoxingClient.skippedCourses : 0;
    final clientSucceededCourses = chaoxingClient.succeededCourses;
    final clientFailedCourses = chaoxingClient.failedCourses;
    final capturedIssues = List<SyncIssue>.of(chaoxingClient.issues);
    var capturedSourceResults =
        List<SyncSourceResult>.of(chaoxingClient.sourceResults);
    _lastSyncSourceResults = capturedSourceResults;
    final capturedNotices =
        List<CourseNotice>.of(chaoxingClient.lastFetchedNotices);
    if (_needsProfileRecovery && !chaoxingClient.deferProfile) {
      _needsProfileRecovery = false;
      try {
        await _refreshChaoxingSession(syncOperation: operation);
      } catch (_) {
        // Profile recovery is optional after a successful homework fetch.
      }
    }
    if (generation != _generation || _disposed) return;
    _ensureSyncActive(operation);
    final isCurrentCoverage = effectiveScope == AssignmentSyncScope.current ||
        effectiveScope == AssignmentSyncScope.all;
    final isFullCoverage = effectiveScope == AssignmentSyncScope.all ||
        (effectiveScope == AssignmentSyncScope.current && skippedCount == 0);
    final cleanSuccess = warning == null;

    final before = [..._assignments, ..._hiddenAssignments];
    await _markReminderMutationPending();
    markSavingStage();
    try {
      await repository.mergeAndSave(
        incoming,
        completeSync: cleanSuccess && isFullCoverage,
        canCommit: _scopedWriteGateFor(syncSession),
      );
    } on StaleSessionWriteException {
      _ensureSyncActive(operation);
      rethrow;
    }
    if (generation != _generation || _disposed) return;
    if (repository.identityConflictCount > 0) {
      warning ??= '部分旧记录存在重复关联，已暂停其提醒，请查看本地记录';
      final sources = repository.identityConflictSources;
      capturedSourceResults = [
        for (final source in capturedSourceResults)
          sources.contains(source.source)
              ? source.withIdentityConflict()
              : source,
      ];
      _lastSyncSourceResults = capturedSourceResults;
      chaoxingClient.sourceResults = capturedSourceResults;
    }
    final dataSuccessAt = DateTime.now();
    final bool dataMirrorSaved;
    try {
      dataMirrorSaved = await _writeScopedPreferenceAndVerify(
        'sync_data_at',
        dataSuccessAt.toUtc().toIso8601String(),
        session: syncSession,
      );
    } on StaleSessionWriteException {
      return;
    }
    final timestampMirrorFailed = !attemptMirrorSaved || !dataMirrorSaved;
    final reportIssues = List<SyncIssue>.of(capturedIssues);
    var courseNoticeReadFailed = false;
    var courseNoticeSaveFailed = false;
    final courseNoticeResults = capturedSourceResults
        .where((source) => source.source == 'courseNotice')
        .toList();
    if (courseNoticeResults.isNotEmpty &&
        courseNoticeResults.first.phase != SyncSourcePhase.success) {
      courseNoticeReadFailed = true;
      reportIssues.add(const SyncIssue(
        SyncIssueKind.partial,
        '部分课程通知未更新',
        stage: 'courseNotice',
      ));
    }
    if (manualSync &&
        capturedSourceResults.any((s) =>
            s.source == 'courseNotice' && s.phase != SyncSourcePhase.failed)) {
      final account = syncAccount;
      if (account != null &&
          _isSessionStateCurrent(
            epoch: generation,
            account: account,
            checkAccount: true,
            expectedAuthenticated: null,
          )) {
        try {
          final mergedNotices = _courseNotices.mergeIncoming(capturedNotices);
          await repository.saveCourseNotices(mergedNotices, account);
          if (_isSessionStateCurrent(
            epoch: generation,
            account: account,
            checkAccount: true,
            expectedAuthenticated: null,
          )) {
            _courseNotices = mergedNotices;
            _invalidateHomeDisplayIndex();
          }
        } on StaleSessionWriteException {
          return;
        } catch (error) {
          courseNoticeSaveFailed = true;
          reportIssues.add(SyncIssue(
              SyncIssueKind.storage, '作业已保存，但课程通知缓存未能更新：$error',
              stage: 'persistence'));
        }
      }
    }
    if (repository.identityConflictCount > 0) {
      reportIssues.add(const SyncIssue(
          SyncIssueKind.partial, '部分旧记录存在重复关联，已暂停其提醒，请查看本地记录',
          stage: 'identity'));
    }
    if (timestampMirrorFailed) {
      reportIssues.add(const SyncIssue(SyncIssueKind.storage,
          '作业数据已保存，但兼容同步时间记录未能完整更新；当前同步报告保留了准确时间，请重试以修复记录',
          stage: 'persistence'));
    }
    final nextCurrentSuccessAt = (cleanSuccess && isCurrentCoverage)
        ? dataSuccessAt
        : priorCurrentSuccessAt;
    final nextFullSuccessAt =
        (cleanSuccess && isFullCoverage) ? dataSuccessAt : priorFullSuccessAt;
    syncReport = SyncReport(
        phase: warning == null &&
                !timestampMirrorFailed &&
                !courseNoticeReadFailed &&
                !courseNoticeSaveFailed
            ? SyncPhase.success
            : SyncPhase.partial,
        attemptedAt: attempted,
        lastDataSuccessAt: dataSuccessAt,
        lastCurrentSuccessAt: nextCurrentSuccessAt,
        lastFullSuccessAt: nextFullSuccessAt,
        syncScope: effectiveScope,
        plannedCourses: plannedCount,
        skippedCourses: skippedCount,
        succeededCourses: clientSucceededCourses,
        failedCourses: clientFailedCourses,
        sourceResults: capturedSourceResults,
        issues: reportIssues);
    try {
      await _updateServerBackoff(reportIssues, session: syncSession);
    } on StaleSessionWriteException {
      return;
    }
    final timestampWarning =
        timestampMirrorFailed ? '作业数据已保存，但同步时间记录未能完整保存；请重新同步核对' : null;
    final courseNoticeWarning = courseNoticeReadFailed ? '部分课程通知未更新' : null;
    _error = [warning, timestampWarning, courseNoticeWarning]
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .join('；');
    if (_error!.isEmpty) _error = null;
    try {
      await _persistSyncReport(session: syncSession);
    } on StaleSessionWriteException {
      return;
    } catch (_) {
      // The journal already contains the data and last-full-sync timestamp.
      // Keep the in-memory result non-successful and let the next launch
      // recover the previous running report as failed rather than claiming
      // that the status record was saved.
      syncReport = SyncReport(
          phase: SyncPhase.partial,
          attemptedAt: attempted,
          lastDataSuccessAt: dataSuccessAt,
          lastCurrentSuccessAt: nextCurrentSuccessAt,
          lastFullSuccessAt: nextFullSuccessAt,
          syncScope: effectiveScope,
          plannedCourses: plannedCount,
          skippedCourses: skippedCount,
          succeededCourses: clientSucceededCourses,
          failedCourses: clientFailedCourses,
          sourceResults: capturedSourceResults,
          issues: [
            ...reportIssues,
            const SyncIssue(
                SyncIssueKind.storage, '作业数据已保存，但同步结果记录未能保存；请重新同步核对',
                stage: 'persistence')
          ]);
      _error = '作业数据已保存，但同步结果记录未能保存；请重新同步核对';
    }
    try {
      await _reloadJournal(
        completeSync: cleanSuccess && isCurrentCoverage,
        detectNewAssignments:
            effectiveScope != AssignmentSyncScope.historicalSweep,
        syncCompleted: true,
        allowSourceBaselineUpdate: isCurrentCoverage,
        syncFailure: warning,
        completedAt: dataSuccessAt,
      );
      if (generation != _generation || _disposed) return;
      _clearHomePreview(notify: true);
      await _recordChanges(
        before,
        incoming,
        completeSync: cleanSuccess && isCurrentCoverage,
        session: syncSession,
      );
      _error ??= warning;
    } on StaleSessionWriteException {
      return;
    } catch (error) {
      syncReport = syncReport.copyWith(
        phase: SyncPhase.partial,
        issues: [
          ...syncReport.issues,
          SyncIssue(SyncIssueKind.storage, '作业数据已保存，但同步后的本机状态刷新未完成：$error',
              stage: 'persistence')
        ],
      );
      _error = '作业数据已保存，但同步后的本机状态刷新未完成；请重新打开或重新同步核对';
      try {
        await _persistSyncReport(session: syncSession);
      } on StaleSessionWriteException {
        return;
      } catch (_) {
        _error = '$_error；同步状态记录也未能保存';
      }
    }
  }

  Future<void> _refreshChaoxingSession({int? syncOperation}) async {
    final generation = _generation;
    bool sessionIsCurrent({String? account}) => _isSessionStateCurrent(
          epoch: generation,
          account: account,
          checkAccount: account != null,
          expectedAuthenticated: null,
          syncOperation: syncOperation,
        );

    if (!sessionIsCurrent()) return;
    final account = _account ?? await sessionStore.readChaoxingAccount();
    if (!sessionIsCurrent()) return;
    final password = await sessionStore.readChaoxingPassword();
    if (!sessionIsCurrent()) return;
    if (account == null ||
        account.trim().isEmpty ||
        password == null ||
        password.isEmpty) {
      return;
    }
    // Restored sessions also skip optional profile/avatar requests. A profile
    // challenge must not prevent the authenticated course request from running.
    chaoxingClient.deferProfile = true;
    final ChaoxingLoginResult result;
    try {
      result = await chaoxingClient.login(account: account, password: password);
    } catch (_) {
      if (sessionIsCurrent()) rethrow;
      chaoxingClient.clearSession();
      return;
    }
    if (!sessionIsCurrent()) {
      chaoxingClient.clearSession();
      return;
    }
    if (!result.success) {
      throw StateError(result.message ?? '登录失败');
    }
    _account = account;
    if (result.displayName != null || result.avatarUrl != null) {
      final displayName = result.displayName ??
          _chaoxingDisplayName ??
          await sessionStore.readChaoxingDisplayName();
      if (!sessionIsCurrent(account: account)) return;
      final avatarUrl = result.avatarUrl ??
          _chaoxingAvatarUrl ??
          await sessionStore.readChaoxingAvatarUrl();
      if (!sessionIsCurrent(account: account)) return;
      await sessionStore.saveChaoxingAccount(
        account: account,
        password: password,
        displayName: displayName,
        avatarUrl: avatarUrl,
      );
      if (!sessionIsCurrent(account: account)) return;
      _chaoxingDisplayName = displayName;
      _chaoxingAvatarUrl = avatarUrl;
    }
  }

  Future<void> _updateServerBackoff(
    Iterable<SyncIssue> issues, {
    _SessionSnapshot? session,
  }) async {
    final snap = session ?? _captureSession();
    final update = AssignmentSyncCoordinator.serverBackoffUpdate(
      issues: issues,
      phase: syncReport.phase,
      clock: DateTime.now,
    );
    if (update == null) return;
    final until = update.until;
    await _runScopedWrite(snap, (prefs) async {
      if (until == null) {
        await prefs.remove(AssignmentStore._serverBackoffKey);
      } else {
        await prefs.setString(
          AssignmentStore._serverBackoffKey,
          until.toUtc().toIso8601String(),
        );
      }
    });
    if (_isSessionCurrent(snap)) {
      _serverBackoffUntil = until;
    }
  }

  Future<void> _recordBackgroundAttempt({
    required DateTime attemptedAt,
    required bool dataSucceeded,
    required bool fullSucceeded,
    required String? failure,
  }) async {
    final accountHash = _accountHash;
    if (!_nativeReminderAvailable || !_authenticated || accountHash == null) {
      return;
    }
    try {
      await backgroundReminderGateway.recordAttempt(
        accountHash: accountHash,
        sessionEpoch: _nativeSessionEpoch,
        attemptedAt: attemptedAt,
        dataSucceeded: dataSucceeded,
        fullSucceeded: fullSucceeded,
        failure: failure,
      );
      await _reconcileBackgroundControls(now: attemptedAt);
    } catch (error) {
      _backgroundWarning = error.toString();
    }
  }
}

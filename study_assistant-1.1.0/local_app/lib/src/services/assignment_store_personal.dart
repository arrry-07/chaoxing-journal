part of 'assignment_store.dart';

extension _AssignmentStorePersonal on AssignmentStore {
  Future<bool> _saveHomeFilters(HomeFilters next, int expectedEpoch) {
    final account = _account;
    if (account == null || !_isSessionStateCurrent(epoch: expectedEpoch)) {
      return Future<bool>.value(false);
    }
    final encoded = next.encode();
    final write = (_filterWrites ?? Future<void>.value()).then((_) async {
      if (!_isSessionStateCurrent(
        epoch: expectedEpoch,
        account: account,
        checkAccount: true,
      )) {
        return false;
      }
      try {
        await repository.saveHomeFilters(next, account);
      } on StaleSessionWriteException {
        return false;
      } catch (error) {
        if (_isSessionStateCurrent(
          epoch: expectedEpoch,
          account: account,
          checkAccount: true,
        )) {
          _error = _friendlyError(error);
          _notify();
        }
        return false;
      }
      if (!_isSessionStateCurrent(
        epoch: expectedEpoch,
        account: account,
        checkAccount: true,
      )) {
        return false;
      }
      _error = null;
      homeFilters = HomeFilters.decode(encoded);
      _notify();
      return true;
    });
    _filterWrites = write.then<void>((_) {}, onError: (Object _) {});
    return write;
  }

  Future<bool> _saveNotebook(
    StudyNotebook Function(StudyNotebook) update,
    int expectedEpoch,
  ) async {
    final account = _account;
    var saved = false;
    await _run(() async {
      if (account == null ||
          !_isSessionStateCurrent(
            epoch: expectedEpoch,
            account: account,
            checkAccount: true,
            requireNotDisposed: false,
          )) {
        return;
      }
      final next = update(notebook);
      await repository.saveNotebook(next, account);
      if (!_isSessionStateCurrent(
        epoch: expectedEpoch,
        requireNotDisposed: false,
      )) {
        return;
      }
      final previous = notebook;
      notebook = StudyNotebook.decode(next.encode());
      _invalidatePinnableKeys();
      saved = true;
      await _cleanupRemovedManualAttachments(previous, notebook);
      if (_pinsNeedSave || _pinned.keys.any(ManualEntry.isManualKey)) {
        await _prunePins();
      }
      if (!_ownsAuthenticatedSession(expectedEpoch, account)) {
        return;
      }
      final manualSucceeded = await _afterAssignmentsChanged(
        updateAssignmentReminders: false,
        updateSummary: false,
        updateManual: true,
        updateWidget: false,
      );
      await _recordManualCancellationOutcomes(
        previous,
        notebook,
        rescheduleSucceeded: manualSucceeded,
      );
    });
    return saved;
  }

  Future<bool> _savePersonal(
    PersonalWorkspace Function(PersonalWorkspace) update,
    int expectedEpoch,
  ) async {
    final account = _account;
    var saved = false;
    await _run(() async {
      if (account == null ||
          !_isSessionStateCurrent(
            epoch: expectedEpoch,
            account: account,
            checkAccount: true,
            requireNotDisposed: false,
          )) {
        return;
      }
      final previous = personal;
      final next = update(previous);
      await repository.savePersonalWorkspace(next, account);
      if (!_isSessionStateCurrent(
        epoch: expectedEpoch,
        requireNotDisposed: false,
      )) {
        return;
      }
      personal = PersonalWorkspace.decode(next.encode());
      saved = true;
      final summarySettingsChanged =
          previous.summaryEnabled != personal.summaryEnabled ||
              previous.summaryHour != personal.summaryHour ||
              previous.summaryMinute != personal.summaryMinute;
      final plansChanged = AssignmentPersonalStateCoordinator.dailyPlansChanged(
        previous.plans,
        personal.plans,
      );
      final needSummary = summarySettingsChanged ||
          ((previous.summaryEnabled || personal.summaryEnabled) &&
              plansChanged);
      if (needSummary) {
        await _afterAssignmentsChanged(
          updateAssignmentReminders: false,
          updateSummary: true,
          updateManual: false,
          updateWidget: false,
        );
      }
    });
    return saved;
  }

  Future<bool> _markNoticeLocalRead(
    String noticeId, {
    bool read = true,
    int expectedEpoch = -1,
  }) async {
    final epoch = expectedEpoch >= 0 ? expectedEpoch : _generation;
    if (expectedEpoch >= 0 && expectedEpoch != _generation) return false;
    final account = _account;
    var saved = false;
    await _run(() async {
      if (account == null ||
          !_isSessionStateCurrent(
            epoch: epoch,
            account: account,
            checkAccount: true,
          )) {
        return;
      }
      final next = _courseNotices.markLocalRead(noticeId, read: read);
      await repository.saveCourseNotices(next, account);
      if (!_isSessionStateCurrent(
        epoch: epoch,
        account: account,
        checkAccount: true,
      )) {
        return;
      }
      _courseNotices = next;
      saved = true;
    });
    return saved;
  }

  Future<bool> _markAllNoticesLocalRead({Iterable<String>? noticeIds}) async {
    final account = _account;
    final epoch = _generation;
    var saved = false;
    await _run(() async {
      if (account == null ||
          !_isSessionStateCurrent(
            epoch: epoch,
            account: account,
            checkAccount: true,
            requireNotDisposed: false,
          )) {
        return;
      }
      final next =
          _courseNotices.markAllLocalRead(noticeIds: noticeIds?.toSet());
      await repository.saveCourseNotices(next, account);
      if (!_isSessionStateCurrent(
        epoch: epoch,
        account: account,
        checkAccount: true,
        requireNotDisposed: false,
      )) {
        return;
      }
      _courseNotices = next;
      saved = true;
    });
    return saved;
  }

  Future<ManualEntry?> _createReminderFromNotice(
    CourseNotice notice, {
    required DateTime remindAt,
    int expectedEpoch = -1,
  }) async {
    final epoch = expectedEpoch >= 0 ? expectedEpoch : _generation;
    if (expectedEpoch >= 0 && expectedEpoch != _generation) return null;
    final account = _account;
    ManualEntry? created;
    await _run(() async {
      if (account == null ||
          !_isSessionStateCurrent(
            epoch: epoch,
            account: account,
            checkAccount: true,
          )) {
        return;
      }
      final existing = notice.linkedManualEntryId == null
          ? null
          : notebook.entries
              .where((e) => e.id == notice.linkedManualEntryId)
              .firstOrNull;
      if (existing != null) {
        created = existing;
        return;
      }
      if (notebook.entries.length >= 500) {
        _error = '待办已达 500 条上限，请清理后再添加';
        return;
      }
      final baseId = 'notice-${notice.id.substring(10, 24)}';
      var candidateId = baseId;
      var suffix = 1;
      while (notebook.entries.any((e) => e.id == candidateId)) {
        candidateId = '$baseId-${suffix++}';
      }
      final rawTitle = '[课程通知] ${notice.title}';
      final entryTitle =
          rawTitle.length > 200 ? rawTitle.substring(0, 200) : rawTitle;
      final entryCourse = notice.courseName == '通知中心' ? '' : notice.courseName;
      final entryNote = notice.summary.length > 500
          ? notice.summary.substring(0, 500)
          : notice.summary;
      final entry = ManualEntry(
        id: candidateId,
        title: entryTitle,
        kind: 'todo',
        course: entryCourse.length > 200
            ? entryCourse.substring(0, 200)
            : entryCourse,
        note: entryNote,
        at: remindAt.toUtc(),
        remind: true,
      );
      final nextNotebook = notebook.withEntries([...notebook.entries, entry]);
      await repository.saveNotebook(nextNotebook, account);
      if (!_isSessionStateCurrent(
        epoch: epoch,
        account: account,
        checkAccount: true,
      )) {
        return;
      }
      final previous = notebook;
      notebook = StudyNotebook.decode(nextNotebook.encode());
      _invalidatePinnableKeys();
      final manualSucceeded = await _afterAssignmentsChanged();
      await _recordManualCancellationOutcomes(
        previous,
        notebook,
        rescheduleSucceeded: manualSucceeded,
      );
      if (!_isSessionStateCurrent(
        epoch: epoch,
        account: account,
        checkAccount: true,
      )) {
        return;
      }
      final nextNotices = _courseNotices.bindManualEntry(notice.id, entry.id);
      await repository.saveCourseNotices(nextNotices, account);
      if (!_isSessionStateCurrent(
        epoch: epoch,
        account: account,
        checkAccount: true,
      )) {
        return;
      }
      _courseNotices = nextNotices;
      created = entry;
    });
    return created;
  }

  Future<ManualEntry?> _createTodoFromChapterNode(
    CourseChapterSnapshot snapshot,
    ChapterNode node, {
    DateTime? remindAt,
    int minutes = 30,
    int expectedEpoch = -1,
  }) async {
    final epoch = expectedEpoch >= 0 ? expectedEpoch : _generation;
    if (expectedEpoch >= 0 && expectedEpoch != _generation) return null;
    final account = _account;
    ManualEntry? created;
    await _run(() async {
      if (account == null ||
          !_isSessionStateCurrent(
            epoch: epoch,
            account: account,
            checkAccount: true,
          )) {
        return;
      }
      final existing = node.linkedManualEntryId == null
          ? null
          : notebook.entries
              .where((e) => e.id == node.linkedManualEntryId)
              .firstOrNull;
      if (existing != null) {
        created = existing;
        return;
      }
      if (notebook.entries.length >= 500) {
        _error = '待办已达 500 条上限，请清理后再添加';
        return;
      }
      final digest = sha256
          .convert(utf8.encode(node.sectionId))
          .toString()
          .substring(0, 14);
      var candidateId = 'chap-$digest';
      var suffix = 1;
      while (notebook.entries.any((e) => e.id == candidateId)) {
        candidateId = 'chap-$digest-${suffix++}';
      }
      final rawTitle = '[章节任务点] ${node.code} ${node.title}';
      final entryTitle =
          rawTitle.length > 200 ? rawTitle.substring(0, 200) : rawTitle;
      final entryNote = node.state == ChapterTaskState.pendingPoints
          ? '待完成任务点：${node.pendingPoints} 个'
          : '';
      final entry = ManualEntry(
        id: candidateId,
        title: entryTitle,
        kind: 'todo',
        course: snapshot.courseName.length > 200
            ? snapshot.courseName.substring(0, 200)
            : snapshot.courseName,
        note: entryNote,
        at: remindAt?.toUtc(),
        remind: remindAt != null,
        minutes: minutes.clamp(0, 1440),
      );
      final nextNotebook = notebook.withEntries([...notebook.entries, entry]);
      await repository.saveNotebook(nextNotebook, account);
      if (!_isSessionStateCurrent(
        epoch: epoch,
        account: account,
        checkAccount: true,
      )) {
        return;
      }
      final previous = notebook;
      notebook = StudyNotebook.decode(nextNotebook.encode());
      _invalidatePinnableKeys();
      final manualSucceeded = await _afterAssignmentsChanged();
      await _recordManualCancellationOutcomes(
        previous,
        notebook,
        rescheduleSucceeded: manualSucceeded,
      );
      if (!_isSessionStateCurrent(
        epoch: epoch,
        account: account,
        checkAccount: true,
      )) {
        return;
      }
      final nextCatalog = _courseChapters.bindManualEntry(
        snapshot.courseKey,
        node.sectionId,
        entry.id,
      );
      await repository.saveCourseChapters(nextCatalog, account);
      if (!_isSessionStateCurrent(
        epoch: epoch,
        account: account,
        checkAccount: true,
      )) {
        return;
      }
      _courseChapters = nextCatalog;
      created = entry;
    });
    return created;
  }

  Future<bool> _acknowledgeDeadlineAlert(String changeId) async {
    final normalized = changeId.trim();
    if (normalized.isEmpty) return false;
    if (_acknowledgedDeadlineChangeIds.contains(normalized)) return true;
    final snap = _captureSession();
    if (!snap.authenticated || snap.account == null) return false;
    var nextSet = <String>{..._acknowledgedDeadlineChangeIds, normalized};
    try {
      await _runScopedWrite(snap, (prefs) async {
        final durable =
            await repository.readAcknowledgedDeadlineChangeIdsInPrefs(prefs);
        final merged = <String>{
          ..._acknowledgedDeadlineChangeIds,
          ...durable,
        };
        final nextOrdered = <String>[
          normalized,
          for (final c in changes)
            if (merged.contains(c.effectiveChangeId) &&
                c.effectiveChangeId != normalized)
              c.effectiveChangeId,
          for (final id in merged)
            if (id != normalized) id,
        ];
        nextSet = nextOrdered.take(300).toSet();
        await repository.writeAcknowledgedDeadlineChangeIdsInPrefs(
          prefs,
          nextOrdered,
        );
      });
    } on StaleSessionWriteException {
      return false;
    } on LocalStorageLeaseReleaseException {
      const warning = '时间变更提醒确认状态已保存，本机写入通道释放未确认，请稍后重试其他写入';
      if (snap.generation == _generation &&
          !_recoveryWarnings.contains(warning)) {
        _recoveryWarnings.add(warning);
      }
    } catch (_) {
      return false;
    }
    if (!_isSessionCurrent(snap)) return false;
    _acknowledgedDeadlineChangeIds = nextSet;
    _notify();
    return true;
  }

  Future<bool> _mutateCourseworkState(
    _SessionSnapshot snap,
    LocalCourseworkState Function(Assignment current) transform, {
    required String leaseWarning,
  }) async {
    var saved = false;
    await _run(() async {
      if (!_isSessionCurrent(snap)) return;
      final next = transform(Assignment(
        id: '_',
        courseName: '',
        title: '',
        deadlineAt: null,
        requirementsText: '',
        status: 'unknown',
        lastSyncedAt: _clock(),
      ));
      if (next == _courseworkState) {
        saved = true;
        return;
      }
      await _markReminderMutationPending();
      if (!_isSessionCurrent(snap)) return;
      try {
        await _runScopedWrite(
          snap,
          (prefs) => repository.writeCourseworkStateInPrefs(prefs, next),
        );
      } on StaleSessionWriteException {
        return;
      } on LocalStorageLeaseReleaseException {
        if (snap.generation == _generation &&
            !_recoveryWarnings.contains(leaseWarning)) {
          _recoveryWarnings.add(leaseWarning);
        }
      } catch (_) {
        return;
      }
      if (!_isSessionCurrent(snap)) return;
      _courseworkState = next;
      _invalidateHomeDisplayIndex();
      saved = true;
      await _afterAssignmentsChanged(
        updateSummary: true,
        updateManual: false,
        updateWidget: true,
      );
      if (_isSessionCurrent(snap)) _notify();
    });
    return saved;
  }

  Future<bool> _setManualDeadline(Assignment assignment, DateTime? at) async {
    final snap = _captureSession();
    if (!snap.authenticated || snap.account == null || assignment.isExam) {
      return false;
    }
    if (at != null &&
        !CourseworkDeadline.canSetManualDeadline(
          assignment,
          entry: courseworkEntryFor(assignment),
        )) {
      return false;
    }
    return _mutateCourseworkState(
      snap,
      (_) {
        final current = findAnyAssignment(assignment.id) ?? assignment;
        return AssignmentPersonalStateCoordinator.computeManualDeadlineState(
              currentState: _courseworkState,
              target: current,
              at: at,
            ) ??
            _courseworkState;
      },
      leaseWarning: '手动截止状态已保存，本机写入通道释放未确认，请稍后重试其他写入',
    );
  }

  Future<bool> _setLocallyCompleted(
    Assignment assignment,
    bool completed,
  ) async {
    final snap = _captureSession();
    if (!snap.authenticated || snap.account == null) return false;
    return _mutateCourseworkState(
      snap,
      (_) {
        final current = findAnyAssignment(assignment.id) ?? assignment;
        return AssignmentPersonalStateCoordinator.computeLocallyCompletedState(
          currentState: _courseworkState,
          target: current,
          completed: completed,
        );
      },
      leaseWarning: '本机完成状态已保存，本机写入通道释放未确认，请稍后重试其他写入',
    );
  }

  Future<void> _reconcileCourseworkState() async {
    final snap = _captureSession();
    if (!snap.authenticated ||
        snap.account == null ||
        _journalRestoreFailed ||
        repository.recoveryWarning != null ||
        _courseworkState.isEmpty) {
      return;
    }
    final reconciled = CourseworkDeadline.reconcileWithAssignments(
      _courseworkState,
      [..._assignments, ..._hiddenAssignments],
    );
    if (reconciled == _courseworkState) return;
    try {
      await _runScopedWrite(
        snap,
        (prefs) => repository.writeCourseworkStateInPrefs(prefs, reconciled),
      );
    } on StaleSessionWriteException {
      return;
    } on LocalStorageLeaseReleaseException {
      const warning = '个人截止状态已同步清理，本机写入通道释放未确认，请稍后重试其他写入';
      if (snap.generation == _generation &&
          !_recoveryWarnings.contains(warning)) {
        _recoveryWarnings.add(warning);
      }
    } catch (_) {
      const warning = '部分个人截止状态同步整理未能保存，请稍后重试';
      if (snap.generation == _generation &&
          !_recoveryWarnings.contains(warning)) {
        _recoveryWarnings.add(warning);
      }
      return;
    }
    if (!_isSessionCurrent(snap)) return;
    _courseworkState = reconciled;
    _invalidateHomeDisplayIndex();
  }

  Set<String> _pinAliases(Assignment assignment) =>
      AssignmentPersonalStateCoordinator.pinAliases(
        assignment,
        courseworkGroups: courseworkGroups,
      );

  void _invalidatePinnableKeys() =>
      _pinnableKeysCache = _pinnableKeysCacheMinute = null;

  Set<String> _pinnableKeys() {
    final now = _clock();
    final minute = now.millisecondsSinceEpoch ~/ 60000;
    if (_pinnableKeysCache != null && _pinnableKeysCacheMinute == minute) {
      return _pinnableKeysCache!;
    }
    _pinnableKeysCacheMinute = minute;
    return _pinnableKeysCache = {
      for (final item in visibleAssignments) AssignmentStore.pinKeyOf(item),
      for (final entry in notebook.entries)
        if (!entry.done) AssignmentStore.manualPinKeyOf(entry),
    };
  }

  bool _canTogglePin(Assignment assignment) =>
      _manageBackgroundSchedule &&
      _authenticated &&
      _account != null &&
      _pinnableKeys().contains(AssignmentStore.pinKeyOf(assignment));

  bool _canToggleManualPin(ManualEntry entry) =>
      _manageBackgroundSchedule &&
      _authenticated &&
      _account != null &&
      !entry.done &&
      _pinnableKeys().contains(AssignmentStore.manualPinKeyOf(entry));

  Future<bool> _togglePinKey(
    String key,
    Iterable<String> aliases,
    bool Function() canToggle,
  ) async {
    final account = _account;
    final generation = _generation;
    if (account == null || !canToggle()) return false;
    var saved = false;
    await _run(() async {
      bool stillOwned() => _ownsAuthenticatedSession(generation, account);
      bool valid() => stillOwned() && canToggle();
      if (!valid()) return;
      final next = _pinned.toggle(key, aliases);
      final persisted = await _savePins(next, account, generation);
      if (!persisted || !stillOwned()) return;
      _pinned = next;
      _pinsNeedSave = false;
      saved = true;
    });
    return saved;
  }

  Future<bool> _reorderPinned(List<String> visibleOrderedKeys) async {
    final account = _account;
    final generation = _generation;
    if (account == null || !_authenticated || !_manageBackgroundSchedule) {
      return false;
    }
    final cleanOrdered = [
      for (final raw in visibleOrderedKeys)
        if (raw.trim().isNotEmpty) raw.trim(),
    ];
    // Filters may hide pinned slots; only the visible subset is reordered.
    final pinnable = _pinnableKeys();
    if (AssignmentPersonalStateCoordinator.validateAndReorderVisiblePins(
          current: _pinned,
          visibleOrderedKeys: cleanOrdered,
          pinnableKeys: pinnable,
        ) ==
        null) {
      return false;
    }
    final visibleKeySet = cleanOrdered.toSet();
    var saved = false;
    await _run(() async {
      if (!_manageBackgroundSchedule ||
          !_ownsAuthenticatedSession(generation, account)) {
        return;
      }
      final next = _pinned.reorderVisible(cleanOrdered, visibleKeySet);
      if (next == null) return;
      if (!await _savePins(next, account, generation) ||
          !_ownsAuthenticatedSession(generation, account)) {
        return;
      }
      _pinned = next;
      _pinsNeedSave = false;
      saved = true;
    });
    return saved;
  }

  bool _ownsAuthenticatedSession(int generation, String? account) =>
      account != null &&
      _isSessionStateCurrent(
        epoch: generation,
        account: account,
        checkAccount: true,
      );

  Future<bool> _savePins(
    PinnedAssignments pins,
    String account,
    int generation,
  ) async {
    try {
      await repository.savePinnedAssignments(pins, account);
      return true;
    } on StaleSessionWriteException {
      return false;
    } on LocalStorageLeaseReleaseException {
      const warning = '置顶状态已保存，本机写入通道释放未确认，请稍后重试其他写入';
      if (_ownsAuthenticatedSession(generation, account) &&
          !_recoveryWarnings.contains(warning)) {
        _recoveryWarnings.add(warning);
      }
      return true;
    }
  }

  Future<void> _prunePins() async {
    final account = _account;
    // Only the foreground store manages pins, and never prune after a
    // failed/damaged journal read. Keys absent merely due to unfollowed
    // courses, partial sync frames, or filters must remain pinned on disk.
    if (!_manageBackgroundSchedule ||
        !_authenticated ||
        account == null ||
        (_pinned.isEmpty && !_pinsNeedSave) ||
        _journalRestoreFailed ||
        repository.recoveryWarning != null) {
      return;
    }
    final retained = AssignmentPersonalStateCoordinator.computePrunedPins(
      current: _pinned,
      localRecordGroups: localRecordGroups,
      notebook: notebook,
      now: _clock(),
      isLocallyCompleted: isLocallyCompleted,
    );
    if (retained == _pinned && !_pinsNeedSave) return;
    _pinned = retained;
    _pinsNeedSave = true;
    final generation = _generation;
    try {
      final persisted = await _savePins(_pinned, account, generation);
      if (persisted && _ownsAuthenticatedSession(generation, account)) {
        _pinsNeedSave = false;
      }
    } catch (_) {
      // The next successful journal update can retry without restoring pins
      // for entries already removed during this session.
    }
  }

  Future<bool> _mutateCourseTermPreferences(
    _SessionSnapshot snap,
    CourseTermPreferences Function(CourseTermPreferences current) transform, {
    required String leaseWarning,
  }) async {
    var saved = false;
    await _run(() async {
      if (!_isSessionCurrent(snap)) return;
      final next = transform(_courseTermPreferences);
      if (next == _courseTermPreferences) {
        saved = true;
        return;
      }
      await _markReminderMutationPending();
      if (!_isSessionCurrent(snap)) return;
      try {
        await _runScopedWrite(
          snap,
          (prefs) => repository.writeCourseTermPreferencesInPrefs(prefs, next),
        );
      } on StaleSessionWriteException {
        return;
      } on LocalStorageLeaseReleaseException {
        if (snap.generation == _generation &&
            !_recoveryWarnings.contains(leaseWarning)) {
          _recoveryWarnings.add(leaseWarning);
        }
      } catch (_) {
        return;
      }
      if (!_isSessionCurrent(snap)) return;
      _courseTermPreferences = next;
      _invalidateHomeDisplayIndex();
      saved = true;
      await _afterAssignmentsChanged(
        updateSummary: true,
        updateManual: false,
        updateWidget: true,
      );
      if (_isSessionCurrent(snap)) _notify();
    });
    return saved;
  }

  Future<bool> _setCourseManualTerm(
    String courseKey,
    AcademicTerm? term,
  ) async {
    final snap = _captureSession();
    if (!snap.authenticated || snap.account == null) return false;
    return _mutateCourseTermPreferences(
      snap,
      (current) => current.withManualTerm(courseKey, term?.key),
      leaseWarning: '学期归属已保存，本机写入通道释放未确认，请稍后重试其他写入',
    );
  }

  Future<bool> _setCourseArchiveMode(
    String courseKey,
    CourseArchiveMode mode,
  ) async {
    final snap = _captureSession();
    if (!snap.authenticated || snap.account == null) return false;
    return _mutateCourseTermPreferences(
      snap,
      (current) => current.withArchiveMode(courseKey, mode),
      leaseWarning: '课程归档状态已保存，本机写入通道释放未确认，请稍后重试其他写入',
    );
  }

  Future<bool> _batchUpdateCourseTerms({
    required Iterable<String> courseKeys,
    AcademicTerm? manualTerm,
    bool updateManualTerm = false,
    CourseArchiveMode? archiveMode,
    CourseBlockMode? blockMode,
  }) async {
    final keys = AssignmentPersonalStateCoordinator.normalizeCourseKeys(
      courseKeys,
    );
    if (!AssignmentPersonalStateCoordinator.hasBatchCourseTermChanges(
      courseKeys: keys,
      updateManualTerm: updateManualTerm,
      archiveMode: archiveMode,
      blockMode: blockMode,
    )) {
      return true;
    }
    final snap = _captureSession();
    if (!snap.authenticated || snap.account == null) return false;
    final saved = await _mutateCourseTermPreferences(
      snap,
      (current) =>
          AssignmentPersonalStateCoordinator.applyBatchCourseTermUpdates(
        current: current,
        courseKeys: keys,
        manualTerm: manualTerm,
        updateManualTerm: updateManualTerm,
        archiveMode: archiveMode,
        blockMode: blockMode,
      ),
      leaseWarning: '批量课程设置已保存，本机写入通道释放未确认，请稍后重试其他写入',
    );
    if (saved && _isSessionCurrent(snap)) {
      final cleared =
          AssignmentPersonalStateCoordinator.clearedCourseFilterIfBlocked(
        currentFilters: homeFilters,
        updatedCourseKeys: keys,
        isCourseBlocked: termCatalog.isBlocked,
      );
      if (cleared != null) {
        await saveHomeFilters(cleared, snap.generation);
      }
    }
    return saved;
  }

  Future<bool> _setCourseBlockMode(
    String courseKey,
    CourseBlockMode mode,
  ) async {
    final snap = _captureSession();
    if (!snap.authenticated || snap.account == null) return false;
    final saved = await _mutateCourseTermPreferences(
      snap,
      (current) => current.withBlockMode(courseKey, mode),
      leaseWarning: '课程屏蔽状态已保存，本机写入通道释放未确认，请稍后重试其他写入',
    );
    if (saved && _isSessionCurrent(snap)) {
      final cleared =
          AssignmentPersonalStateCoordinator.clearedCourseFilterIfBlocked(
        currentFilters: homeFilters,
        updatedCourseKeys: {courseKey},
        isCourseBlocked: termCatalog.isBlocked,
      );
      if (cleared != null) {
        await saveHomeFilters(cleared, snap.generation);
      }
    }
    return saved;
  }

  Future<bool> _dismissCourseRecall(String courseKey) async {
    final snap = _captureSession();
    if (!snap.authenticated || snap.account == null) return false;
    return _mutateCourseTermPreferences(
      snap,
      (current) => AssignmentPersonalStateCoordinator.applyDismissCourseRecall(
        current: current,
        courseKey: courseKey,
        latestRecallEventUtc:
            termCatalog.entryFor(courseKey)?.latestRecallEventUtc,
        now: _clock(),
      ),
      leaseWarning: '召回忽略状态已保存，本机写入通道释放未确认，请稍后重试其他写入',
    );
  }

  Future<bool> _archivePastCourses() async {
    final snap = _captureSession();
    if (!snap.authenticated || snap.account == null) return false;
    return _mutateCourseTermPreferences(
      snap,
      (current) =>
          current.withBatchArchive(termCatalog.archivablePastCourseKeys),
      leaseWarning: '往期课程已批量归档，本机写入通道释放未确认，请稍后重试其他写入',
    );
  }

  Future<String?> _saveDisplay(DisplayPreferences next) {
    final snap = _captureSession();
    display = next;
    // Serialize preference writes independently of coursework operations.
    final write = (_displayWrites ?? Future<void>.value()).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final previous =
          DisplayPreferences.decode(prefs.getString('display_preferences_v1'));
      if (!await prefs.setString('display_preferences_v1', next.encode())) {
        throw StateError('显示设置未能保存');
      }
      return previous.widgetRange != next.widgetRange;
    });
    _displayWrites = write.then<void>((_) {}, onError: (Object _) {});
    _notify();
    return _finishDisplaySave(next, write, snap);
  }

  Future<String?> _finishDisplaySave(
    DisplayPreferences next,
    Future<bool> write,
    _SessionSnapshot snap,
  ) async {
    final bool rangeChanged;
    try {
      rangeChanged = await write;
    } catch (_) {
      return '显示设置未能保存，当前调整仅在本次使用时生效';
    }
    if (!rangeChanged ||
        !_isSessionCurrent(snap) ||
        display.widgetRange != next.widgetRange) {
      return null;
    }
    final effectiveCoursework = snap.authenticated
        ? _courseworkState
        : const LocalCourseworkState.empty();
    final now = _clock();
    final activeCatalog = snap.authenticated ? termCatalog : null;
    final items = next.forWidget(
      snap.authenticated ? courseAssignments : <Assignment>[],
      now,
      coursework: effectiveCoursework,
    );
    try {
      await _runScopedWrite(
        snap,
        (_) {
          widgetSnapshotService.clock = _clock;
          widgetSnapshotService.courseworkState = effectiveCoursework;
          widgetSnapshotService.termCatalog = activeCatalog;
          return widgetSnapshotService.saveAssignmentsForContext(
            items,
            authenticated: snap.authenticated,
            range: next.widgetRange,
          );
        },
      );
      return null;
    } on StaleSessionWriteException {
      return null;
    } catch (_) {
      return '显示设置已保存，小组件更新失败，请稍后刷新';
    }
  }

  Future<void> _followCourse(String key, bool followed) {
    final snap = _captureSession();
    return _run(() async {
      if (!_isSessionCurrent(snap)) return;
      await _markReminderMutationPending();
      if (!_isSessionCurrent(snap)) return;
      final next = {..._unfollowed};
      if (followed) {
        next.remove(key);
      } else {
        next.add(key);
      }
      try {
        await _runScopedWrite(snap, (prefs) async {
          if (!await prefs.setStringList('unfollowed_courses', next.toList())) {
            throw StateError('课程关注设置未能保存，请重试');
          }
        });
      } on StaleSessionWriteException {
        return;
      }
      if (!_isSessionCurrent(snap)) return;
      _unfollowed
        ..clear()
        ..addAll(next);
      _invalidateHomeDisplayIndex();
      await _afterAssignmentsChanged();
    });
  }

  Future<bool> _setAssignmentsHidden(
    Iterable<String> assignmentIds,
    bool hidden,
  ) async {
    final ids = assignmentIds.toSet();
    if (ids.isEmpty) return true;
    final epoch = accountEpoch;
    final account = _account;
    final accountHash = _accountHash;
    if (!_authenticated || account == null || accountHash == null) {
      return false;
    }
    var saved = false;
    await _run(() async {
      if (!_isSessionStateCurrent(
        epoch: epoch,
        account: account,
        checkAccount: true,
        accountHash: accountHash,
        checkAccountHash: true,
        requireNotDisposed: false,
      )) {
        return;
      }
      await _markReminderMutationPending();
      if (!_isSessionStateCurrent(
        epoch: epoch,
        account: account,
        checkAccount: true,
        accountHash: accountHash,
        checkAccountHash: true,
        requireNotDisposed: false,
      )) {
        return;
      }
      try {
        await repository.updateCompletionMany(
          ids,
          hidden,
          canCommit: () async {
            if (!_isSessionStateCurrent(
              epoch: epoch,
              account: account,
              checkAccount: true,
              requireNotDisposed: false,
            )) {
              return false;
            }
            if (!_nativeReminderAvailable) return true;
            return backgroundReminderGateway.isSessionCurrent(
              accountHash,
              _nativeSessionEpoch,
            );
          },
        );
      } on StateError {
        if (accountEpoch != epoch) return;
        rethrow;
      }
      if (!_isSessionStateCurrent(
        epoch: epoch,
        account: account,
        checkAccount: true,
        accountHash: accountHash,
        checkAccountHash: true,
        requireNotDisposed: false,
      )) {
        return;
      }
      await _reloadJournal();
      saved = true;
    });
    return saved;
  }

  Future<void> _cleanupRemovedManualAttachments(
    StudyNotebook previous,
    StudyNotebook current,
  ) async {
    final retained = <String>{
      for (final entry in current.entries)
        for (final item in entry.attachments) item.relativePath,
    };
    final removed = <String>[
      for (final entry in previous.entries)
        for (final item in entry.attachments)
          if (!retained.contains(item.relativePath)) item.relativePath,
    ];
    if (removed.isEmpty) return;
    try {
      await manualAttachmentService.deleteFiles(removed);
    } catch (error) {
      debugPrint('[ManualAttachment] cleanup: ${error.runtimeType}');
    }
  }
}

// Keep explicit receivers on calls that dispatch through the store.
// ignore_for_file: unnecessary_this

part of 'assignment_store.dart';

extension _AssignmentStoreReminders on AssignmentStore {
  DateTime? get _nextBackgroundCheckAt {
    if (!_authenticated || !_backgroundCheckSettings.enabled) return null;
    return _nextBackgroundTarget(DateTime.now());
  }

  Future<bool> _saveAutoSyncIntervalMinutes(int minutes) => minutes == 0
      ? this.saveBackgroundCheckEnabled(false)
      : this.saveBackgroundCheckIntervalMinutes(minutes);

  Future<bool> _saveBackgroundCheckEnabled(bool enabled) =>
      _saveBackgroundCheckSettings(
        (current) => current.copyWith(enabled: enabled),
      );

  Future<bool> _saveBackgroundCheckIntervalMinutes(int minutes) =>
      _saveBackgroundCheckSettings(
        (current) => current.copyWith(
          enabled: true,
          intervalMinutes: DaytimeCheckPolicy.normalizeIntervalMinutes(minutes),
        ),
      );

  Future<bool> _saveNotificationListenerEnabled(bool enabled) =>
      _saveBackgroundCheckSettings(
        (current) => current.copyWith(notificationListenerEnabled: enabled),
      );

  Future<bool> _saveNewAssignmentReminderEnabled(bool enabled) =>
      _saveBackgroundCheckSettings(
        (current) => current.copyWith(newAssignmentReminderEnabled: enabled),
      );

  Future<BackgroundReminderHealth?> _inspectBackgroundReminderHealth() async {
    final accountHash = _accountHash;
    if (!_nativeReminderAvailable || !_authenticated || accountHash == null) {
      return null;
    }
    // Once the bridge is expected, a failed read is not "zero reminders"; let
    // the caller surface the failure instead of fabricating a healthy state.
    return backgroundReminderGateway.inspectHealth(
      accountHash: accountHash,
      sessionEpoch: _nativeSessionEpoch,
    );
  }

  Future<void> _saveNotificationDetails(bool value) {
    final snap = _captureSession();
    return _run(() async {
      if (!_isSessionCurrent(snap)) return;
      await _markReminderMutationPending();
      if (!_isSessionCurrent(snap)) return;
      if (!value) {
        try {
          await _cancelPrivateNotifications();
        } catch (_) {
          throw StateError('旧提醒未能清理，通知详情尚未关闭，请在提醒体检重试');
        }
        if (!_isSessionCurrent(snap)) return;
      }
      try {
        await _runScopedWrite(snap, (prefs) async {
          if (value) {
            await prefs.remove(AssignmentStore._privacyVerifiedHiddenKey);
          }
          if (!await prefs.setBool('notification_details_v1', value)) {
            throw StateError('通知隐私设置未能保存');
          }
          if (!value) {
            await _writeBoolPreferenceAndVerify(
              prefs,
              AssignmentStore._privacyVerifiedHiddenKey,
              true,
            );
          }
        });
      } on StaleSessionWriteException {
        return;
      }
      if (!_isSessionCurrent(snap)) return;
      notificationService.showDetails = value;
      _privacyCleanupPending = false;
      await _reconcileBackgroundControls();
      if (!_isSessionCurrent(snap)) return;
      await _afterAssignmentsChanged();
      if (!_isSessionCurrent(snap)) return;
      if (_warningBuckets.isNotEmpty) {
        throw StateError('隐私设置已保存，部分旧提醒未更新，请在提醒体检重试');
      }
    });
  }

  Future<bool> _saveReminderRule(List<int> offsetsMinutes) async {
    final snap = _captureSession();
    var saved = false;
    await _run(() async {
      if (!_isSessionCurrent(snap)) return;
      await _markReminderMutationPending();
      if (!_isSessionCurrent(snap)) return;
      final List<int> normalized;
      try {
        normalized = await _runScopedWrite(
          snap,
          (_) => reminderRuleStore.saveOffsetsMinutes(offsetsMinutes),
        );
      } on StaleSessionWriteException {
        return;
      }
      if (!_isSessionCurrent(snap)) return;
      _reminderOffsetsMinutes = normalized;
      saved = true;
      await _afterAssignmentsChanged();
    });
    return saved;
  }

  Future<bool> _saveBackgroundCheckSettings(
    BackgroundCheckSettings Function(BackgroundCheckSettings current) transform,
  ) async {
    final snap = _captureSession();
    var saved = false;
    await _run(() async {
      if (!_isSessionCurrent(snap)) return;
      final next = transform(_backgroundCheckSettings);
      try {
        await _runScopedWrite(
          snap,
          (prefs) => backgroundCheckSettingsStore.save(next, prefs: prefs),
        );
      } on StaleSessionWriteException {
        return;
      }
      if (!_isSessionCurrent(snap)) return;
      _backgroundCheckSettings = next;
      if (!await _reconcileBackgroundControls()) {
        throw StateError('设置已保存，但后台提醒设置未确认，请重试');
      }
      if (!_isSessionCurrent(snap)) return;
      saved = true;
    });
    return saved;
  }

  Future<bool> _saveAllowUrgentDeadlineNightBreakthrough(bool enabled) async {
    final snap = _captureSession();
    var saved = false;
    await _run(() async {
      if (!_isSessionCurrent(snap)) return;
      await _markReminderMutationPending();
      if (!_isSessionCurrent(snap)) return;
      try {
        await _runScopedWrite(
          snap,
          (prefs) => repository.writeAllowUrgentNightBreakthroughInPrefs(
            prefs,
            enabled,
          ),
        );
      } on StaleSessionWriteException {
        return;
      }
      if (!_isSessionCurrent(snap)) return;
      _allowUrgentDeadlineNightBreakthrough = enabled;
      notificationService.allowUrgentNightBreakthrough =
          snap.authenticated && enabled;
      saved = true;
      await _afterAssignmentsChanged(updateSummary: false);
    });
    return saved;
  }

  Future<bool> _saveDeadlineChannelId(String channelId) async {
    final normalized =
        LocalAssignmentRepository.normalizeDeadlineChannelId(channelId);
    if (normalized == null) {
      _error = '未知的截止提醒通知渠道';
      _notify();
      return false;
    }
    final snap = _captureSession();
    var saved = false;
    await _run(() async {
      if (!_isSessionCurrent(snap)) return;
      await _markReminderMutationPending();
      if (!_isSessionCurrent(snap)) return;
      try {
        await _runScopedWrite(
          snap,
          (prefs) async {
            await repository.writeDeadlineChannelIdInPrefs(
              prefs,
              normalized,
            );
            await prefs.setBool(
              AssignmentStore._deadlineChannelV3AutoMigratedKey,
              true,
            );
          },
        );
      } on StaleSessionWriteException {
        return;
      }
      if (!_isSessionCurrent(snap)) return;
      _deadlineChannelId = normalized;
      notificationService.activeDeadlineChannelId = snap.authenticated
          ? normalized
          : LocalNotificationService.assignmentV3Channel;
      saved = true;
      await _afterAssignmentsChanged(updateSummary: false);
    });
    return saved;
  }

  Future<TestDeadlineNotificationOutcome> _sendTestDeadlineNotification({
    int delayMillis = 3000,
  }) async {
    final decision =
        AssignmentReminderCoordinator.evaluateTestDeadlineNotification(
      now: _clock(),
      authenticated: _authenticated,
      deadlineChannelId: _deadlineChannelId,
      activeDeadlineChannelId: activeDeadlineChannelId,
    );
    if (decision.quietHoursOutcome != null) {
      return decision.quietHoursOutcome!;
    }
    final targetChannel = decision.targetChannelId;
    notificationService.activeDeadlineChannelId = targetChannel;
    if (_nativeReminderAvailable) {
      try {
        return await backgroundReminderGateway.sendTestDeadlineNotification(
          accountHash: _authenticated ? _accountHash : null,
          channelId: targetChannel,
          delayMillis: delayMillis,
        );
      } catch (error) {
        return TestDeadlineNotificationOutcome(
          status: TestDeadlineNotificationStatus.blocked,
          channelId: targetChannel,
          warning: '发送测试提醒失败：$error',
        );
      }
    }
    try {
      final ok = await notificationService.showTestNotification();
      return ok
          ? TestDeadlineNotificationOutcome(
              status: TestDeadlineNotificationStatus.posted,
              channelId: targetChannel,
            )
          : TestDeadlineNotificationOutcome(
              status: TestDeadlineNotificationStatus.blocked,
              channelId: targetChannel,
              warning:
                  notificationService.lastWarning ?? '未能请求测试通知，请检查通知权限与渠道。',
            );
    } catch (error) {
      return TestDeadlineNotificationOutcome(
        status: TestDeadlineNotificationStatus.blocked,
        channelId: targetChannel,
        warning: '发送测试提醒失败：$error',
      );
    }
  }

  Future<void> _recordBackgroundCheckObservation(
    BackgroundSyncTrigger trigger,
    BackgroundCheckResult result,
  ) async {
    if (!_nativeReminderAvailable || !_reminderHistoryReady) return;
    if (trigger == BackgroundSyncTrigger.daytime &&
        result.skipped &&
        result.success &&
        result.skipReason == null) {
      return;
    }
    final accountHash = _accountHash;
    final epoch = _nativeSessionEpoch;
    if (accountHash == null || epoch <= 0) return;
    final isOutsideWindow =
        result.skipReason == BackgroundCheckResult.outsideWindowSkipReason;
    final stage = isOutsideWindow
        ? 'deferred'
        : result.skipped
            ? 'blocked'
            : result.success
                ? 'scheduled'
                : 'unconfirmed';
    final reasonCode =
        result.skipReason ?? (result.success ? null : 'backgroundCheckFailed');
    final logicalKey = trigger == BackgroundSyncTrigger.notificationSignal
        ? 'background:notificationSignal:${backgroundSignalVersion ?? 0}'
        : 'background:${trigger.name}';
    final owner = notificationRemoteStart?.workerId ?? nativeLeaseOwner;
    final observationId = (owner != null && owner.isNotEmpty)
        ? 'bg:${trigger.name}:${backgroundSignalVersion ?? 0}:$owner:$stage:${reasonCode ?? ''}'
        : null;
    try {
      final context =
          await backgroundReminderGateway.acquireReminderObservationContext(
        accountHash: accountHash,
        sessionEpoch: epoch,
      );
      await backgroundReminderGateway.appendReminderObservation(
        context: context,
        observation: ReminderObservation(
          observationId: observationId,
          subjectKind: 'account',
          logicalKey: logicalKey,
          category: 'backgroundCheck',
          stage: stage,
          reasonCode: reasonCode,
          observedAt: _clock(),
          scheduledAt: result.nextTargetAt,
        ),
      );
    } on ReminderHistoryException catch (error) {
      _warningBuckets.addServiceWarning('提醒记录未能写入：${error.message}');
    } catch (error) {
      _warningBuckets.addServiceWarning('提醒记录未能写入：$error');
    }
  }

  Future<void> _prepareReminderHistorySession() async {
    if (!reminderHistoryEnabled) return;
    final accountHash = _accountHash;
    final epoch = _nativeSessionEpoch;
    if (!_nativeReminderAvailable ||
        !_authenticated ||
        accountHash == null ||
        epoch <= 0) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    try {
      final control = await backgroundReminderGateway.getReminderHistoryControl(
        accountHash: accountHash,
        sessionEpoch: epoch,
      );
      var generation = control.historyGeneration;
      if (control.purgePending) {
        final token = control.purgeToken;
        if (token == null) {
          _reminderHistoryReady = false;
          _warningBuckets.addServiceWarning('提醒记录仍在清理，当前记录功能暂不可用');
          return;
        }
        final finished =
            await backgroundReminderGateway.finishReminderHistoryLogout(token);
        generation = finished.historyGeneration;
      }
      final pendingRequest =
          prefs.getString(AssignmentStore._historyPurgeRequestKey);
      final pendingGeneration =
          prefs.getInt(AssignmentStore._historyPurgeGenerationKey);
      if (pendingRequest != null && pendingRequest.isNotEmpty) {
        final expected = pendingGeneration == null || pendingGeneration <= 0
            ? generation
            : pendingGeneration;
        try {
          final started =
              await backgroundReminderGateway.beginReminderHistoryLogout(
            expectedHistoryGeneration: expected,
            requestId: pendingRequest,
            accountHash: accountHash,
            sessionEpoch: epoch,
          );
          final finished = await backgroundReminderGateway
              .finishReminderHistoryLogout(started.purgeToken);
          generation = finished.historyGeneration;
        } on ReminderHistoryException catch (error) {
          if (error.code != 'stale_history_generation') rethrow;
          generation =
              (await backgroundReminderGateway.getReminderHistoryControl(
            accountHash: accountHash,
            sessionEpoch: epoch,
          ))
                  .historyGeneration;
        }
        await prefs.remove(AssignmentStore._historyPurgeRequestKey);
        await prefs.remove(AssignmentStore._historyPurgeGenerationKey);
      }
      generation = await backgroundReminderGateway.enableReminderHistorySession(
        accountHash: accountHash,
        sessionEpoch: epoch,
        expectedHistoryGeneration: generation,
      );
      _reminderHistoryGeneration = generation;
      _reminderHistoryReady = true;
    } on ReminderHistoryException catch (error) {
      _reminderHistoryReady = false;
      _warningBuckets.addServiceWarning('提醒记录暂不可用：${error.message}');
    } catch (error) {
      _reminderHistoryReady = false;
      _warningBuckets.addServiceWarning('提醒记录暂不可用：$error');
    }
  }

  Future<String?> _retireReminderHistoryBeforeLogout(
    String accountHash,
    int sessionEpoch,
  ) async {
    if (!reminderHistoryEnabled) return null;
    if (!_nativeReminderAvailable) {
      await _persistHistoryPurgeIntent();
      return null;
    }
    final requestId =
        'logout-${DateTime.now().microsecondsSinceEpoch}-$_generation';
    final prefs = await SharedPreferences.getInstance();
    try {
      final control = await backgroundReminderGateway.getReminderHistoryControl(
        accountHash: accountHash,
        sessionEpoch: sessionEpoch,
      );
      var generation = control.historyGeneration;
      if (control.purgePending && control.purgeToken != null) {
        final finished = await backgroundReminderGateway
            .finishReminderHistoryLogout(control.purgeToken!);
        generation = finished.historyGeneration;
      } else if (control.purgePending) {
        await prefs.setString(
          AssignmentStore._historyPurgeRequestKey,
          requestId,
        );
        await prefs.setInt(
          AssignmentStore._historyPurgeGenerationKey,
          generation,
        );
        return null;
      }
      final started =
          await backgroundReminderGateway.beginReminderHistoryLogout(
        expectedHistoryGeneration: generation,
        requestId: requestId,
        accountHash: accountHash,
        sessionEpoch: sessionEpoch,
      );
      await backgroundReminderGateway
          .finishReminderHistoryLogout(started.purgeToken);
      _reminderHistoryReady = false;
      _reminderHistoryGeneration = 0;
      return null;
    } catch (error) {
      await _persistHistoryPurgeIntent(
        requestId: requestId,
        generation: _reminderHistoryGeneration,
      );
      _reminderHistoryReady = false;
      final warning = '退出时提醒记录清理未确认：$error';
      _warningBuckets.addServiceWarning(warning);
      return warning;
    }
  }

  Future<void> _persistHistoryPurgeIntent({
    String? requestId,
    int? generation,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AssignmentStore._historyPurgeRequestKey,
        requestId ??
            'logout-${DateTime.now().microsecondsSinceEpoch}-$_generation',
      );
      await prefs.setInt(
        AssignmentStore._historyPurgeGenerationKey,
        generation ?? _reminderHistoryGeneration,
      );
    } catch (_) {
      // The logout path already reports the unconfirmed native cleanup.
    }
  }

  Future<bool> _afterAssignmentsChanged({
    bool completeSync = false,
    bool detectNewAssignments = false,
    bool syncCompleted = false,
    bool allowSourceBaselineUpdate = true,
    String? syncFailure,
    DateTime? completedAt,
    bool updateAssignmentReminders = true,
    bool updateSummary = true,
    bool updateManual = true,
    bool updateWidget = true,
  }) async {
    final snap = _captureSession();
    if (updateAssignmentReminders) {
      await _prunePins();
      if (!_isSessionCurrent(snap)) {
        return false;
      }
    }
    var manualRescheduleSucceeded = false;
    final fullRefresh = updateAssignmentReminders &&
        updateSummary &&
        updateManual &&
        updateWidget;
    if (fullRefresh) {
      _warningBuckets.clearAll();
    } else {
      _warningBuckets.clearSelectedBuckets(
        deadline: updateAssignmentReminders,
        summary: updateSummary,
        manual: updateManual,
        widget: updateWidget,
      );
    }
    // Restored app preferences can outlive excluded/nonportable credentials.
    // Do not publish their private content to lockscreen or widget before login.
    final scoped = snap.authenticated ? courseAssignments : <Assignment>[];
    if (_privacyCleanupPending) {
      try {
        await _cancelPrivateNotifications();
      } catch (error) {
        _warningBuckets.addBucketWarning(
          ReminderWarningBucket.privacy,
          _privacyCleanupMessage(error),
        );
      }
    }
    final effectiveCoursework = snap.authenticated
        ? _courseworkState
        : const LocalCourseworkState.empty();
    notificationService.courseworkState = effectiveCoursework;
    notificationService.allowUrgentNightBreakthrough =
        snap.authenticated && _allowUrgentDeadlineNightBreakthrough;
    notificationService.activeDeadlineChannelId = snap.authenticated
        ? _deadlineChannelId
        : LocalNotificationService.assignmentV3Channel;
    if (!_privacyCleanupPending) {
      if (updateAssignmentReminders) {
        if (_nativeReminderAvailable && _authenticated) {
          final controlsApplied = await _reconcileBackgroundControls();
          if (!controlsApplied) {
            // Fail closed: publishing a plan while showDetails/schedule settings
            // were not applied would activate the previous native settings.
            _warningBuckets.addBucketWarning(
              ReminderWarningBucket.deadline,
              _backgroundWarning ?? '后台提醒设置未能应用，本次未更新提醒计划',
            );
          } else {
            try {
              if (await _ensureLegacyAssignmentVerified()) {
                await _applyNativeReminderPlan(
                  completeSync: completeSync,
                  detectNewAssignments: detectNewAssignments,
                  syncCompleted: syncCompleted,
                  allowSourceBaselineUpdate: allowSourceBaselineUpdate,
                  failure: syncFailure,
                  completedAt: completedAt,
                );
              }
            } catch (error) {
              _warningBuckets.addBucketWarning(
                ReminderWarningBucket.deadline,
                '后台作业提醒状态未能更新：$error',
              );
            }
          }
        } else {
          try {
            await notificationService.rescheduleAssignments(
              scoped,
              offsetsMinutes: _reminderOffsetsMinutes,
            );
          } catch (_) {
            _warningBuckets.addBucketWarning(
              ReminderWarningBucket.deadline,
              '提醒安排失败，请检查通知权限后重试',
            );
          }
          if (notificationService.lastWarning != null) {
            _warningBuckets.addBucketWarning(
              ReminderWarningBucket.deadline,
              notificationService.lastWarning!,
            );
          }
        }
      }
      if (_manageBackgroundSchedule && updateSummary) {
        try {
          await notificationService.rescheduleSummary(
            scoped,
            _authenticated ? personal : PersonalWorkspace(),
            _lastSyncAt,
          );
          if (notificationService.lastWarning != null) {
            _warningBuckets.addBucketWarning(
              ReminderWarningBucket.summary,
              notificationService.lastWarning!,
            );
          }
        } catch (error) {
          final detail = notificationService.lastWarning ?? error.toString();
          _warningBuckets.addBucketWarning(
            ReminderWarningBucket.summary,
            _authenticated && personal.summaryEnabled
                ? '每日摘要未能更新：$detail'
                : '旧摘要未能清理：$detail',
          );
        }
        await _recordPluginScheduleOutcomes(
          notificationService.lastScheduleOutcomes,
        );
      }
      if (_manageBackgroundSchedule && updateManual) {
        try {
          await notificationService
              .rescheduleManual(_authenticated ? notebook.entries : []);
          manualRescheduleSucceeded = !notificationService.lastScheduleOutcomes
              .any((item) => item.stage == 'scheduleFailed');
          if (notificationService.lastWarning != null) {
            _warningBuckets.addBucketWarning(
              ReminderWarningBucket.manual,
              '个人日程：${notificationService.lastWarning!}',
            );
          }
        } catch (error) {
          manualRescheduleSucceeded = false;
          final detail = notificationService.lastWarning ?? error.toString();
          _warningBuckets.addBucketWarning(
            ReminderWarningBucket.manual,
            '个人日程提醒未能更新或清理：$detail',
          );
        }
        await _recordPluginScheduleOutcomes(
          notificationService.lastScheduleOutcomes,
        );
      }
    }
    if (!_isSessionCurrent(snap) || !updateWidget) {
      return manualRescheduleSucceeded;
    }
    final now = _clock();
    final activeCatalog = snap.authenticated ? termCatalog : null;
    final widgetItems = display.forWidget(
      scoped,
      now,
      coursework: effectiveCoursework,
    );
    if (_manageBackgroundSchedule) {
      try {
        await _runScopedWrite(
          snap,
          (_) {
            widgetSnapshotService.clock = _clock;
            widgetSnapshotService.courseworkState = effectiveCoursework;
            widgetSnapshotService.termCatalog = activeCatalog;
            return widgetSnapshotService.saveAssignmentsForContext(
              widgetItems,
              authenticated: snap.authenticated,
              range: display.widgetRange,
            );
          },
        );
      } on StaleSessionWriteException {
        return manualRescheduleSucceeded;
      } catch (_) {
        if (snap.generation == _generation && !_disposed) {
          _warningBuckets.addBucketWarning(
            ReminderWarningBucket.widget,
            '作业已保存在本机，小组件更新失败，请稍后刷新',
          );
        }
      }
    } else if (snap.authenticated && !_privacyCleanupPending) {
      try {
        await _runScopedWrite(
          snap,
          (_) {
            widgetSnapshotService.clock = _clock;
            widgetSnapshotService.courseworkState = effectiveCoursework;
            widgetSnapshotService.termCatalog = activeCatalog;
            return widgetSnapshotService.saveAssignmentsForContext(
              widgetItems,
              authenticated: true,
              range: display.widgetRange,
            );
          },
        );
      } on StaleSessionWriteException {
        return manualRescheduleSucceeded;
      } catch (error) {
        debugPrint('[WidgetSnapshot] background_refresh_skipped: $error');
      }
    }
    return manualRescheduleSucceeded;
  }

  Future<void> _markReminderMutationPending() async {
    final accountHash = _accountHash;
    if (!_nativeReminderAvailable || !_authenticated || accountHash == null) {
      return;
    }
    await backgroundReminderGateway.markPendingUpdate(
      accountHash: accountHash,
      sessionEpoch: _nativeSessionEpoch,
    );
  }

  Future<void> _recordPluginScheduleOutcomes(
    List<ReminderScheduleOutcome> outcomes,
  ) async {
    if (!_nativeReminderAvailable ||
        !_reminderHistoryReady ||
        outcomes.isEmpty) {
      return;
    }
    final accountHash = _accountHash;
    final epoch = _nativeSessionEpoch;
    if (accountHash == null || epoch <= 0) return;
    try {
      final context =
          await backgroundReminderGateway.acquireReminderObservationContext(
        accountHash: accountHash,
        sessionEpoch: epoch,
      );
      final result =
          await backgroundReminderGateway.recordReminderScheduleOutcome(
        context: context,
        outcomes: outcomes,
      );
      if (result.warning != null) {
        _warningBuckets.addServiceWarning(result.warning!);
      }
    } on ReminderHistoryException catch (error) {
      _warningBuckets.addServiceWarning('提醒记录未能写入：${error.message}');
    } catch (error) {
      _warningBuckets.addServiceWarning('提醒记录未能写入：$error');
    }
  }

  Future<void> _recordManualCancellationOutcomes(
    StudyNotebook previous,
    StudyNotebook current, {
    required bool rescheduleSucceeded,
  }) async {
    if (!_nativeReminderAvailable ||
        !_reminderHistoryReady ||
        !_authenticated) {
      return;
    }
    final outcomes =
        AssignmentReminderCoordinator.buildManualCancellationOutcomes(
      previous: previous,
      current: current,
      rescheduleSucceeded: rescheduleSucceeded,
      now: DateTime.now(),
    );
    await _recordPluginScheduleOutcomes(outcomes);
  }

  ReminderObservationContext _historyReadContext() {
    final accountHash = _accountHash;
    if (!_nativeReminderAvailable ||
        !_reminderHistoryReady ||
        accountHash == null ||
        _nativeSessionEpoch <= 0 ||
        _reminderHistoryGeneration <= 0) {
      throw const ReminderHistoryException(
        'history_unavailable',
        '提醒记录当前不可用',
      );
    }
    return ReminderObservationContext(
      accountHash: accountHash,
      sessionEpoch: _nativeSessionEpoch,
      historyGeneration: _reminderHistoryGeneration,
      operationSequence: 0,
    );
  }

  Future<ReminderHistoryPage> _loadReminderHistory({
    int? snapshotMaxId,
    int? beforeId,
    String? category,
    List<ReminderSubjectRef> subjectRefs = const [],
  }) =>
      backgroundReminderGateway.listReminderHistory(
        context: _historyReadContext(),
        snapshotMaxId: snapshotMaxId,
        beforeId: beforeId,
        category: category,
        subjectRefs: subjectRefs,
      );

  Future<ReminderSubjectEvidence> _inspectReminderSubjects(
    List<ReminderSubjectRef> refs,
  ) async {
    final context = _historyReadContext();
    if (refs.length <= 50) {
      return backgroundReminderGateway.inspectReminderSubjects(
        context: context,
        subjectRefs: refs,
      );
    }
    final nativeEvents = <ReminderNativeSubjectEvidence>[];
    final pluginEvidence = <ReminderPluginSubjectEvidence>[];
    final warnings = <String>[];
    var checkedAt = DateTime.now();
    var generation = context.historyGeneration;
    for (var start = 0; start < refs.length; start += 50) {
      final end = (start + 50).clamp(0, refs.length);
      final page = await backgroundReminderGateway.inspectReminderSubjects(
        context: context,
        subjectRefs: refs.sublist(start, end),
      );
      checkedAt = page.checkedAt;
      generation = page.historyGeneration;
      nativeEvents.addAll(page.nativeEvents);
      pluginEvidence.addAll(page.pluginEvidence);
      warnings.addAll(page.queryWarnings);
    }
    return ReminderSubjectEvidence(
      checkedAt: checkedAt,
      nativeEvents: nativeEvents,
      pluginEvidence: pluginEvidence,
      queryWarnings: warnings,
      historyGeneration: generation,
    );
  }

  Future<ReminderExplanation> _explainReminder({
    required String kind,
    required String id,
  }) =>
      AssignmentReminderCoordinator.explainReminder(
        kind: kind,
        id: id,
        now: DateTime.now(),
        authenticated: _authenticated,
        nativeReminderAvailable: _nativeReminderAvailable,
        accountHash: _accountHash,
        nativeSessionEpoch: _nativeSessionEpoch,
        personal: personal,
        notebook: notebook,
        lastSyncAt: _lastSyncAt,
        courseAssignments: courseAssignments,
        hiddenAssignmentIds: _effectiveHiddenAssignmentIds(),
        unfollowedCourseKeys: _unfollowed,
        reminderOffsetsMinutes: _reminderOffsetsMinutes,
        newAssignmentReminderEnabled:
            _backgroundCheckSettings.newAssignmentReminderEnabled,
        courseworkState: _courseworkState,
        allowUrgentNightBreakthrough: _allowUrgentDeadlineNightBreakthrough,
        courseworkGroupFor: this.courseworkGroupFor,
        findAssignment: this.findAssignment,
        inspectHealth: notificationService.inspectHealth,
        readScheduleEvidence: notificationService.readScheduleEvidence,
        inspectSubjects: this.inspectReminderSubjects,
        loadPlanState: (accountHash, sessionEpoch) =>
            backgroundReminderGateway.loadPlanState(
          accountHash: accountHash,
          sessionEpoch: sessionEpoch,
        ),
      );

  Future<void> _retryReminderRecovery() {
    final generation = _generation;
    return _run(() async {
      if (_disposed || generation != _generation) return;
      await notificationService.recoverPendingSchedules();
      if (_disposed || generation != _generation) return;
      await _afterAssignmentsChanged();
    });
  }

  Future<bool> _maybeMigrateLegacyAssignmentSchedules() async {
    return await _ensureLegacyAssignmentVerified();
  }

  Future<void> _maybeMigrateLegacyManualSchedules({
    bool? legacyAssignmentVerified,
  }) async {
    if (!_authenticated ||
        !_manageBackgroundSchedule ||
        _privacyCleanupPending ||
        _disposed) {
      return;
    }
    final snap = _captureSession();
    notificationService.allowUrgentNightBreakthrough =
        _allowUrgentDeadlineNightBreakthrough;
    notificationService.courseworkState = _courseworkState;
    try {
      await notificationService
          .migrateLegacyManualChannelIfNeeded(notebook.entries);
    } catch (error) {
      if (!_isSessionCurrent(snap)) return;
      _warningBuckets.addBucketWarning(
        ReminderWarningBucket.manual,
        '个人日程提醒渠道迁移未完成：$error',
      );
    }
    if (!_isSessionCurrent(snap)) return;
    try {
      await notificationService.migrateLegacySummaryChannelIfNeeded(
        courseAssignments,
        personal,
        _lastSyncAt,
      );
    } catch (error) {
      if (!_isSessionCurrent(snap)) return;
      _warningBuckets.addBucketWarning(
        ReminderWarningBucket.summary,
        '每日摘要提醒渠道迁移未完成：$error',
      );
    }
    if (!_isSessionCurrent(snap)) return;
    var canRetireLegacyDeadline =
        _deadlineChannelId == LocalNotificationService.assignmentV3Channel;
    if (canRetireLegacyDeadline && _nativeReminderAvailable) {
      if (legacyAssignmentVerified != null) {
        canRetireLegacyDeadline = legacyAssignmentVerified;
      } else {
        try {
          canRetireLegacyDeadline =
              await notificationService.isLegacyAssignmentMigrationComplete();
        } catch (_) {
          canRetireLegacyDeadline = false;
        }
      }
    }
    if (!_isSessionCurrent(snap)) return;
    var deadlineRescheduledForV3 = false;
    try {
      await notificationService.retireLegacyUpdatesAndDeadlineChannelsIfNeeded(
        retireDeadlineV1: canRetireLegacyDeadline,
        beforeRetireDeadlineV1: !_nativeReminderAvailable
            ? () async {
                if (!_isSessionCurrent(snap)) return false;
                deadlineRescheduledForV3 = true;
                await notificationService.rescheduleAssignments(
                  courseAssignments,
                  offsetsMinutes: _reminderOffsetsMinutes,
                );
                if (!_isSessionCurrent(snap)) return false;
                if (notificationService.lastDeadlineScheduleFailed) {
                  final reason = notificationService.lastWarning ?? '截止提醒重排未完成';
                  _warningBuckets.addBucketWarning(
                    ReminderWarningBucket.deadline,
                    '截止提醒渠道升级重排未完成：$reason',
                  );
                  return false;
                }
                return true;
              }
            : null,
      );
    } catch (error) {
      if (!_isSessionCurrent(snap)) return;
      if (deadlineRescheduledForV3) {
        _warningBuckets.addBucketWarning(
          ReminderWarningBucket.deadline,
          '截止提醒渠道升级重排未完成：$error',
        );
      }
      // Best-effort legacy v1/v2 channel cleanup.
    }
    if (!_isSessionCurrent(snap)) return;
    if (_migratedDeadlineChannelToV3ThisRestore && !_nativeReminderAvailable) {
      _migratedDeadlineChannelToV3ThisRestore = false;
      if (!deadlineRescheduledForV3) {
        try {
          await notificationService.rescheduleAssignments(
            courseAssignments,
            offsetsMinutes: _reminderOffsetsMinutes,
          );
        } catch (error) {
          if (!_isSessionCurrent(snap)) return;
          _warningBuckets.addBucketWarning(
            ReminderWarningBucket.deadline,
            '截止提醒渠道升级重排未完成：$error',
          );
        }
      }
    }
  }

  /// The native migration revision is the only activation fact. The Flutter
  /// boolean is mirrored for diagnostics/tests but never authorizes delivery.
  Future<bool> _ensureLegacyAssignmentVerified() async {
    if (!_nativeReminderAvailable) return true;
    try {
      if (await notificationService.isLegacyAssignmentMigrationComplete()) {
        await _mirrorLegacyCleanupMarker();
        return true;
      }
      await notificationService.removeLegacyAssignmentSchedules();
      if (!await notificationService.isLegacyAssignmentMigrationComplete()) {
        _warningBuckets.addServiceWarning('旧作业提醒迁移未完成，已暂缓原生提醒计划');
        return false;
      }
      await _mirrorLegacyCleanupMarker();
      return true;
    } catch (error) {
      _warningBuckets.addServiceWarning('旧作业提醒迁移尚未完成：$error');
      return false;
    }
  }

  Future<void> _mirrorLegacyCleanupMarker() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(AssignmentStore._legacyScheduleCleanupKey) == true) {
      return;
    }
    if (!await _writeBoolPreferenceAndVerify(
      prefs,
      AssignmentStore._legacyScheduleCleanupKey,
      true,
    )) {
      _warningBuckets.addServiceWarning('旧作业提醒已清理，但本机完成标记未能保存；不影响原生迁移状态');
    }
  }

  Future<void> _applyNativeReminderPlan({
    required bool completeSync,
    required bool detectNewAssignments,
    required bool syncCompleted,
    bool allowSourceBaselineUpdate = true,
    String? failure,
    DateTime? completedAt,
  }) async {
    final accountHash = _accountHash;
    if (!_authenticated || accountHash == null) return;
    final sessionEpoch = _nativeSessionEpoch;
    final state = await backgroundReminderGateway.loadPlanState(
      accountHash: accountHash,
      sessionEpoch: sessionEpoch,
    );
    final now = completedAt ?? _clock();
    final plan = AssignmentReminderPlanner.planAfterSync(
      accountHash: accountHash,
      sessionEpoch: sessionEpoch,
      assignments: [..._assignments, ..._hiddenAssignments],
      hiddenAssignmentIds: _effectiveHiddenAssignmentIds(),
      unfollowedCourseKeys: _unfollowed,
      knownAssignmentIds: state.knownAssignmentIds,
      sentNewAssignmentIds: state.sentNewAssignmentIds,
      baselineCompleted: state.baselineCompleted,
      baselinedSources: state.baselinedSources,
      completedSourceKeys: (syncCompleted && allowSourceBaselineUpdate)
          ? {
              for (final source in (_lastSyncSourceResults.isNotEmpty
                  ? _lastSyncSourceResults
                  : chaoxingClient.sourceResults))
                if (source.phase == SyncSourcePhase.success) source.source,
            }
          : const {},
      completeSync: completeSync,
      detectNewAssignments: detectNewAssignments,
      newAssignmentReminderEnabled:
          _backgroundCheckSettings.newAssignmentReminderEnabled,
      reminderOffsetsMinutes: _reminderOffsetsMinutes,
      now: now,
      courseworkState: _courseworkState,
      archivedCourseKeys: _archivedReminderCourseKeys(),
      allowUrgentNightBreakthrough: _allowUrgentDeadlineNightBreakthrough,
    );
    final result = await backgroundReminderGateway.applyPlan(
      accountHash: accountHash,
      sessionEpoch: sessionEpoch,
      plan: plan,
      completedAt: now,
      failure: failure,
      syncCompleted: syncCompleted,
      expectedMutationVersion: state.mutationVersion,
    );
    _backgroundWarning = result.warning;
    if (result.warning != null) {
      _warningBuckets.addServiceWarning(result.warning!);
    }
  }

  DateTime? get _latestAttemptAt {
    final attempt = _lastSyncAttemptAt;
    final success = _lastSyncAt;
    if (attempt == null) return success;
    if (success == null || attempt.isAfter(success)) return attempt;
    return success;
  }

  DateTime? _nextBackgroundTarget(DateTime now) {
    if (!_backgroundCheckSettings.enabled) return null;
    var target = DaytimeCheckPolicy.nextTarget(
      localNow: now,
      lastAttemptAt: _latestAttemptAt,
      intervalMinutes: _backgroundCheckSettings.intervalMinutes,
    );
    final backoff = _serverBackoffUntil;
    if (backoff != null && backoff.isAfter(target)) {
      target = backoff;
    }
    return target;
  }

  DateTime? _nextNotificationWindowTarget(DateTime now) {
    if (!_backgroundCheckSettings.notificationListenerEnabled) return null;
    var target = DaytimeCheckPolicy.isInWindow(now)
        ? now
        : DaytimeCheckPolicy.nextWindowStart(now);
    final backoff = _serverBackoffUntil;
    if (backoff != null && backoff.isAfter(target)) {
      target = backoff;
    }
    return target;
  }

  Set<String> _archivedReminderCourseKeys() {
    return {
      for (final entry in termCatalog.entries)
        if (entry.state == CourseCatalogState.archived || entry.isBlocked)
          entry.courseKey,
    };
  }

  /// Applies settings/schedule to the native side. Returns false only when a
  /// control write was not confirmed, so callers can refuse to activate a plan
  /// under stale settings. Health is diagnostic and never blocks that result.
  Future<bool> _reconcileBackgroundControls({DateTime? now}) async {
    if (!_nativeReminderAvailable) return true;
    final current = now ?? DateTime.now();
    final accountHash = _accountHash;
    try {
      if (_authenticated && accountHash != null) {
        await backgroundReminderGateway.updateSettings(
          accountHash,
          _nativeSessionEpoch,
          _backgroundCheckSettings,
          showDetails: notificationService.showDetails,
          reconcileSchedules: _manageBackgroundSchedule,
          allowUrgentNightBreakthrough: _allowUrgentDeadlineNightBreakthrough,
          deadlineChannelId: _deadlineChannelId,
        );
      }
      if (_manageBackgroundSchedule) {
        await backgroundReminderGateway.reconcileDaytimeSchedule(
          targetAt: _authenticated ? _nextBackgroundTarget(current) : null,
          enabled: _authenticated && _backgroundCheckSettings.enabled,
          intervalMinutes: _backgroundCheckSettings.intervalMinutes,
        );
      }
    } catch (error) {
      _backgroundWarning =
          '后台提醒设置未确认：${error.toString().replaceFirst('PlatformException', '后台提醒')}';
      return false;
    }
    try {
      if (accountHash != null) {
        final health = await backgroundReminderGateway.inspectHealth(
          accountHash: accountHash,
          sessionEpoch: _nativeSessionEpoch,
        );
        _backgroundWarning = health.lastFailure;
      }
    } catch (error) {
      _backgroundWarning = '后台提醒体检读取失败：$error';
    }
    return true;
  }

  Future<void> _cancelPrivateNotifications() async {
    _privacyCleanupPending = true;
    try {
      await _persistPrivacyCleanupPending(true);
      if (_manageBackgroundSchedule) {
        await notificationService.cancelPrivateSchedules();
      }
      final nativeTargets = <String>{
        ..._pendingNativeCleanupAccounts,
        if (_nativeReminderAvailable && _accountHash != null) _accountHash!,
      };
      var pendingChanged = false;
      for (final target in nativeTargets) {
        final pendingAccount = _pendingNativeCleanupAccounts.contains(target);
        if (!_nativeReminderAvailable) {
          // No bridge means no proof the old account was cleaned. Keep the
          // durable target; deleting it here would silently lose retry state.
          continue;
        }
        if (pendingAccount) {
          // Account-level cleanup also cancels background work and alarms;
          // delivery cleanup alone is not enough to retry a failed logout.
          await backgroundReminderGateway.clearActiveAccount(target);
        }
        await backgroundReminderGateway
            .cancelAssignmentDeliveryKeepEvents(target);
        if (pendingAccount && _pendingNativeCleanupAccounts.remove(target)) {
          pendingChanged = true;
        }
      }
      if (pendingChanged) {
        // Retry evidence is only cleared after the native side confirmed the
        // delivery cleanup for that old identity.
        await _persistNativeCleanupAccounts();
      }
      if (_pendingNativeCleanupAccounts.isEmpty) {
        await _persistPrivacyCleanupPending(false);
        final prefs = await SharedPreferences.getInstance();
        if (_manageBackgroundSchedule &&
            prefs.getBool('notification_details_v1') == false) {
          await _writeBoolPreferenceAndVerify(
            prefs,
            AssignmentStore._privacyVerifiedHiddenKey,
            true,
          );
        }
        _privacyCleanupPending = false;
      } else {
        // A failed account-level cleanup is still pending even when delivery
        // cancellation succeeded. Keep the durable marker for the next retry.
        await _persistPrivacyCleanupPending(true);
        _privacyCleanupPending = true;
        throw StateError('原生提醒通道不可用，旧账号清理状态未确认');
      }
    } catch (error) {
      _privacyCleanupPending = true;
      try {
        await _persistPrivacyCleanupPending(true);
      } catch (_) {
        // The in-memory state remains fail-closed even if persistence fails.
      }
      throw StateError(_privacyCleanupMessage(error));
    }
  }

  Future<void> _persistPrivacyCleanupPending(bool pending) async {
    final prefs = await SharedPreferences.getInstance();
    if (pending) {
      if (prefs.getBool(AssignmentStore._privacyCleanupPendingKey) != true) {
        final saved = await prefs.setBool(
          AssignmentStore._privacyCleanupPendingKey,
          true,
        );
        if (!saved) {
          await prefs.reload();
          if (prefs.getBool(AssignmentStore._privacyCleanupPendingKey) !=
              true) {
            throw StateError('通知隐私待清理状态未能保存');
          }
        }
      }
      return;
    }
    final removed =
        await prefs.remove(AssignmentStore._privacyCleanupPendingKey);
    if (!removed) {
      await prefs.reload();
      if (prefs.getBool(AssignmentStore._privacyCleanupPendingKey) == true) {
        throw StateError('通知隐私待清理状态未能清除');
      }
    }
  }

  Future<void> _persistNativeCleanupAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    if (_pendingNativeCleanupAccounts.isEmpty) {
      final removed =
          await prefs.remove(AssignmentStore._nativeCleanupAccountsKey);
      if (!removed) {
        await prefs.reload();
        if (prefs.getStringList(AssignmentStore._nativeCleanupAccountsKey) !=
            null) {
          throw StateError('旧账号原生提醒清理目标未能清除');
        }
      }
      return;
    }
    final values = _pendingNativeCleanupAccounts.toList()..sort();
    if (!await prefs.setStringList(
      AssignmentStore._nativeCleanupAccountsKey,
      values,
    )) {
      await prefs.reload();
      if (!listEquals(
        prefs.getStringList(AssignmentStore._nativeCleanupAccountsKey),
        values,
      )) {
        throw StateError('旧账号原生提醒清理目标未能保存');
      }
    }
  }

  String _privacyCleanupMessage(Object error) =>
      notificationService.lastWarning ??
      error
          .toString()
          .replaceFirst('Bad state: ', '')
          .replaceFirst('旧账号私人通知未能完整清理：', '');
}

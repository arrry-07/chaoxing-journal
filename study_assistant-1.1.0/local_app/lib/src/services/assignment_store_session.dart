// Keep explicit receivers on calls that dispatch through the store.
// ignore_for_file: unnecessary_this

part of 'assignment_store.dart';

extension _AssignmentStoreSession on AssignmentStore {
  Future<void> _restoreSession() async {
    _warningBuckets.clearAll();
    _recoveryWarnings.clear();
    _nativeReminderAvailable = nativeReminderDeliveryEnabled &&
        await backgroundReminderGateway.isAvailable();
    repository.crossEngineLockEnabled = _nativeReminderAvailable;
    try {
      _account = await sessionStore.readChaoxingAccount();
      _authenticated = _account?.trim().isNotEmpty == true;
      _accountHash = _authenticated ? AccountIdentity.hash(_account!) : null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final notificationClickMessage =
          prefs.getString(AssignmentStore._notificationClickMissingKey);
      if (notificationClickMessage != null) {
        _error = notificationClickMessage;
        await prefs.remove(AssignmentStore._notificationClickMissingKey);
      }
    } catch (error) {
      debugPrint('[AssignmentStore] restoreIdentity: ${error.runtimeType}');
      _recoveryWarnings.add('本机数据恢复未完成：登录信息暂时无法读取，请重新登录');
    }
    try {
      if (_authenticated) {
        if (_nativeReminderAvailable) {
          _nativeSessionEpoch =
              await backgroundReminderGateway.ensureActiveAccount(
            _accountHash!,
          );
          await _prepareReminderHistorySession();
        }
        await repository.activateAccount(_account!, previousAccount: _account);
      }
      await _restoreAccountData();
    } catch (error) {
      debugPrint('[AssignmentStore] restoreAccount: ${error.runtimeType}');
      _authenticated = false;
      _assignments.clear();
      _hiddenAssignments = [];
      _recoveryWarnings.add('账号本机记录暂时无法恢复，请重新登录后重试');
      widgetSnapshotService.clock = _clock;
      widgetSnapshotService.courseworkState =
          const LocalCourseworkState.empty();
      widgetSnapshotService.termCatalog = null;
      if (_manageBackgroundSchedule) {
        try {
          await widgetSnapshotService.saveAssignmentsForContext(
            const [],
            authenticated: false,
            range: display.widgetRange,
          );
        } catch (widgetError) {
          debugPrint(
              '[WidgetSnapshot] restore_clear: ${widgetError.runtimeType}');
        }
      }
    }
    try {
      _chaoxingDisplayName = await sessionStore.readChaoxingDisplayName();
      _chaoxingAvatarUrl = await sessionStore.readChaoxingAvatarUrl();
      _needsProfileRecovery = _authenticated &&
          (_chaoxingDisplayName == null || _chaoxingAvatarUrl == null);
    } catch (error) {
      debugPrint('[AssignmentStore] restoreProfile: ${error.runtimeType}');
      _recoveryWarnings.add('个人资料暂时无法恢复，不影响重新登录和读取作业');
    }
    await _reconcileBackgroundControls();
    final legacyAssignmentVerified =
        await _maybeMigrateLegacyAssignmentSchedules();
    await _maybeMigrateLegacyManualSchedules(
      legacyAssignmentVerified: legacyAssignmentVerified,
    );
    this._notify();
  }

  Future<void> _restoreAccountData() async {
    _clearHomePreview();
    homeFilters = const HomeFilters();
    notebook = StudyNotebook();
    personal = PersonalWorkspace();
    _courseNotices = CourseNoticeCollection();
    _courseChapters = CourseChapterCatalog();
    _isChapterSyncing = false;
    _chapterSyncProgressText = null;
    changes = [];
    _acknowledgedDeadlineChangeIds = <String>{};
    _assignments.clear();
    _hiddenAssignments = [];
    _courses = [];
    _unfollowed.clear();
    _pinned = const PinnedAssignments.empty();
    _courseworkState = const LocalCourseworkState.empty();
    _courseTermPreferences = const CourseTermPreferences.empty();
    _historicalSweepState = const HistoricalSweepState.empty();
    _lastRequestedSyncScope = AssignmentSyncScope.current;
    _lastTargetedCourseKeys = const {};
    _lastSyncSourceResults = const [];
    _termCatalogCache = null;
    _visitedAssignment = null;
    _activeVisitTicket = null;
    _visitLeftApp = false;
    _pendingReturnConfirmation = null;
    _pinsNeedSave = false;
    _journalRestoreFailed = false;
    _reminderOffsetsMinutes = ReminderRuleStore.defaultOffsetsMinutes;
    _allowUrgentDeadlineNightBreakthrough = false;
    _deadlineChannelId = LocalNotificationService.assignmentV3Channel;
    _migratedDeadlineChannelToV3ThisRestore = false;
    notificationService.activeDeadlineChannelId =
        LocalNotificationService.assignmentV3Channel;
    _lastSyncAt = null;
    _lastSyncAttemptAt = null;
    _serverBackoffUntil = null;
    syncReport = const SyncReport();
    var stageNumber = 0;
    Future<void> stage(String name, Future<void> Function() action) async {
      stageNumber++;
      try {
        await action();
      } catch (error) {
        debugPrint(
            '[AssignmentStore] restoreStage$stageNumber: ${error.runtimeType}');
        _recoveryWarnings.add('$name恢复未完成，请重新同步或保存设置');
      }
    }

    await stage('通知隐私', () async {
      final prefs = await SharedPreferences.getInstance();
      final details = prefs.getBool('notification_details_v1') ?? false;
      final cleanupPending =
          prefs.getBool(AssignmentStore._privacyCleanupPendingKey) ?? false;
      final verifiedHidden =
          prefs.getBool(AssignmentStore._privacyVerifiedHiddenKey) ?? false;
      _pendingNativeCleanupAccounts
        ..clear()
        ..addAll(
            prefs.getStringList(AssignmentStore._nativeCleanupAccountsKey) ??
                const []);
      notificationService.showDetails = details;
      _privacyCleanupPending =
          (_manageBackgroundSchedule && !details && !verifiedHidden) ||
              cleanupPending ||
              _pendingNativeCleanupAccounts.isNotEmpty;
      if (_privacyCleanupPending) {
        try {
          await _cancelPrivateNotifications();
        } catch (error) {
          _recoveryWarnings.add(_privacyCleanupMessage(error));
        }
      }
    });
    await stage('显示设置', () async {
      final prefs = await SharedPreferences.getInstance();
      display =
          DisplayPreferences.decode(prefs.getString('display_preferences_v1'));
    });
    await stage('首页筛选', () async {
      if (_authenticated) homeFilters = await repository.loadHomeFilters();
    });
    await stage('置顶课业', () async {
      final account = _account;
      if (_manageBackgroundSchedule && _authenticated && account != null) {
        _pinned = await repository.loadPinnedAssignments(account);
      }
    });
    await stage('个人课业状态', () async {
      final account = _account;
      if (_authenticated && account != null) {
        _courseworkState = await repository.loadCourseworkState(account);
      }
    });
    await stage('课程学期设置', () async {
      final account = _account;
      if (_authenticated && account != null) {
        _courseTermPreferences =
            await repository.loadCourseTermPreferences(account);
      }
    });
    await stage('往期巡检状态', () async {
      final account = _account;
      if (_authenticated && account != null) {
        _historicalSweepState =
            await repository.loadHistoricalSweepState(account);
      }
    });
    await stage('提醒设置', () async {
      _reminderOffsetsMinutes = await reminderRuleStore.loadOffsetsMinutes();
      final account = _account;
      _allowUrgentDeadlineNightBreakthrough =
          (_authenticated && account != null)
              ? await repository.loadAllowUrgentNightBreakthrough(account)
              : false;
      final savedDeadlineChannel = (_authenticated && account != null)
          ? await repository.loadDeadlineChannelId(account)
          : null;
      if (_authenticated && account != null) {
        final prefs = await SharedPreferences.getInstance();
        final alreadyAutoMigrated =
            prefs.getBool(AssignmentStore._deadlineChannelV3AutoMigratedKey) ??
                false;
        final isLegacyChannel = savedDeadlineChannel ==
                LocalNotificationService.assignmentChannel ||
            savedDeadlineChannel ==
                LocalNotificationService.assignmentV2Channel;
        if (isLegacyChannel && !alreadyAutoMigrated) {
          final snap = _captureSession();
          try {
            await _runScopedWrite(
              snap,
              (scopedPrefs) async {
                await repository.writeDeadlineChannelIdInPrefs(
                  scopedPrefs,
                  LocalNotificationService.assignmentV3Channel,
                );
                await scopedPrefs.setBool(
                  AssignmentStore._deadlineChannelV3AutoMigratedKey,
                  true,
                );
              },
            );
            _migratedDeadlineChannelToV3ThisRestore = true;
          } on StaleSessionWriteException {
            // Session changed mid-restore; leave persisted state untouched.
          } catch (_) {
            // Keep running restore using the upgraded in-memory default below.
          }
          _deadlineChannelId = LocalNotificationService.assignmentV3Channel;
        } else {
          _deadlineChannelId =
              await notificationService.resolveDefaultDeadlineChannel(
            storedChannelId: savedDeadlineChannel,
          );
          if (_deadlineChannelId ==
                  LocalNotificationService.assignmentV3Channel &&
              !alreadyAutoMigrated) {
            final snap = _captureSession();
            try {
              await _runScopedWrite(
                snap,
                (scopedPrefs) => scopedPrefs.setBool(
                  AssignmentStore._deadlineChannelV3AutoMigratedKey,
                  true,
                ),
              );
            } on StaleSessionWriteException {
              // Session changed mid-restore; leave persisted state untouched.
            } catch (_) {
              // Keep running restore using the upgraded in-memory default.
            }
          }
        }
      } else {
        _deadlineChannelId = LocalNotificationService.assignmentV3Channel;
      }
      notificationService.activeDeadlineChannelId = _authenticated
          ? _deadlineChannelId
          : LocalNotificationService.assignmentV3Channel;
    });
    await stage('自动同步设置', () async {
      final snap = _captureSession();
      _backgroundCheckSettings = await _runScopedWrite(
        snap,
        (prefs) => backgroundCheckSettingsStore.loadAndMigrate(prefs: prefs),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      _serverBackoffUntil = DateTime.tryParse(
              prefs.getString(AssignmentStore._serverBackoffKey) ?? '')
          ?.toLocal();
    });
    await stage('同步记录', () async {
      final prefs = await SharedPreferences.getInstance();
      _lastSyncAttemptAt =
          DateTime.tryParse(prefs.getString('sync_attempt_at') ?? '')
              ?.toLocal();
      final dataAt = DateTime.tryParse(prefs.getString('sync_data_at') ?? '');
      final report = prefs.getString('sync_report_v1');
      Map<String, dynamic>? reportJson;
      var reportDamaged = false;
      if (report != null) {
        try {
          final decoded = jsonDecode(report);
          if (decoded is Map<String, dynamic>) {
            reportJson = decoded;
          } else {
            reportDamaged = true;
          }
        } on FormatException catch (error) {
          debugPrint(
              '[AssignmentStore] restoreSyncReportJson: ${error.runtimeType}');
          reportDamaged = true;
        }
      }
      if (reportJson != null) {
        try {
          SyncReport.fromJson(reportJson);
        } on FormatException catch (error) {
          debugPrint(
              '[AssignmentStore] restoreSyncReport: ${error.runtimeType}');
          reportJson = null;
          reportDamaged = true;
        } on TypeError catch (error) {
          debugPrint(
              '[AssignmentStore] restoreSyncReport: ${error.runtimeType}');
          reportJson = null;
          reportDamaged = true;
        } on ArgumentError catch (error) {
          debugPrint(
              '[AssignmentStore] restoreSyncReport: ${error.runtimeType}');
          reportJson = null;
          reportDamaged = true;
        }
      }
      if (reportDamaged) {
        _recoveryWarnings.add('同步记录恢复未完成：原同步报告损坏，已依据可验证的本机时间重建部分状态');
      }
      var reportNeedsRepair = reportDamaged;
      if (reportJson != null) {
        final rawPhase = reportJson['phase'];
        syncReport = SyncReport.fromJson(reportJson);
        final reportAttempt = syncReport.attemptedAt;
        if (reportAttempt != null &&
            (_lastSyncAttemptAt == null ||
                reportAttempt.isAfter(_lastSyncAttemptAt!))) {
          // The v1 report is the canonical attempt timestamp. The legacy
          // mirror may be missing if its SharedPreferences write failed.
          _lastSyncAttemptAt = reportAttempt;
        }
        if (dataAt != null &&
            (syncReport.lastDataSuccessAt == null ||
                dataAt.isAfter(syncReport.lastDataSuccessAt!))) {
          // sync_data_at is written only after mergeAndSave has completed.
          // If it is newer than the report, the report is stale even when its
          // old phase says success/failed; do not present that attempt as a
          // fully successful sync whose final status was never persisted.
          final interruptedAfterDataSave = rawPhase == 'running' ||
              syncReport.attemptedAt == null ||
              dataAt.isAfter(syncReport.attemptedAt!);
          syncReport = syncReport.copyWith(
            phase: interruptedAfterDataSave ? SyncPhase.partial : null,
            lastDataSuccessAt: dataAt.toLocal(),
            issues: interruptedAfterDataSave
                ? [
                    ...syncReport.issues,
                    const SyncIssue(SyncIssueKind.storage,
                        '上次同步已写入作业数据，但在保存最终同步报告前中断；请重新同步核对',
                        stage: 'persistence')
                  ]
                : null,
          );
          // Persist the mirror reconciliation even when the existing phase
          // remains failed (for example, a newer failed attempt after older
          // durable data). The timestamps are still independently useful.
          reportNeedsRepair = true;
        }
      } else {
        DateTime? durableFullAt;
        try {
          durableFullAt = await repository.lastSyncAt();
        } catch (error) {
          // The independent data timestamp is still useful if the journal
          // cannot currently be read. Do not let a damaged repository hide
          // evidence that a partial sync had already saved records.
          _recoveryWarnings.add('完整同步时间暂时无法从作业仓库读取：$error');
        }
        syncReport = AssignmentSessionCoordinator.recoverMissingSyncReport(
          attemptedAt: _lastSyncAttemptAt,
          dataAt: dataAt,
          durableFullAt: durableFullAt,
          reportDamaged: reportDamaged,
        );
        reportNeedsRepair = syncReport.phase != SyncPhase.idle;
      }
      if (reportNeedsRepair) {
        await _persistSyncReport();
      }
    });
    await stage('课程关注', () async {
      final prefs = await SharedPreferences.getInstance();
      _unfollowed.addAll(prefs.getStringList('unfollowed_courses') ?? []);
    });
    await stage('课程资料', () async {
      _courses = await repository.loadCourses(account: _account);
    });
    await stage('个人计划与记录', () async {
      personal = await repository.loadPersonalWorkspace();
    });
    await stage('个人待办与学期归档', () async {
      notebook = await repository.loadNotebook();
      _invalidatePinnableKeys();
    });
    await stage('课程通知', () async {
      _courseNotices = await repository.loadCourseNotices();
    });
    await stage('章节进度', () async {
      _courseChapters = await repository.loadCourseChapters();
    });
    await stage('作业记录', () async {
      try {
        await _reloadJournal();
        _journalRestoreFailed = false;
      } catch (_) {
        _journalRestoreFailed = true;
        rethrow;
      }
      _hadCacheBeforeLastSync =
          _assignments.isNotEmpty || _hiddenAssignments.isNotEmpty;
    });
    await stage('作业变化', () async {
      changes = await changeLog.load();
      _termCatalogCache = null;
    });
    await stage('时间变更确认状态', () async {
      final account = _account;
      if (_authenticated && account != null) {
        _acknowledgedDeadlineChangeIds =
            await repository.loadAcknowledgedDeadlineChangeIds(account);
      }
    });
  }

  Future<void> _loginChaoxing({
    required String account,
    required String password,
    required bool agreementAccepted,
  }) async {
    if (_loginRunning) return;
    if (!agreementAccepted) {
      _error = '请先阅读并同意服务协议和隐私协议';
      this._notify();
      return;
    }
    _loginRunning = true;
    final generation = ++_generation;
    this.cancelSynchronization();
    _visitedAssignment = null;
    _activeVisitTicket = null;
    _visitLeftApp = false;
    _pendingReturnConfirmation = null;
    returnCheckMessage = null;
    var loginSucceeded = false;
    chaoxingClient.deferProfile = true;
    try {
      await _run(() async {
        if (generation != _generation || _disposed) return;
        final result = await chaoxingClient.login(
          account: account,
          password: password,
        );
        if (generation != _generation || _disposed) {
          chaoxingClient.clearSession();
          return;
        }
        if (!result.success) {
          chaoxingClient.clearSession();
          throw StateError(result.message ?? '登录失败');
        }
        final oldAccount = _account;
        final oldAccountHash = _accountHash;
        final oldNativeEpoch = _nativeSessionEpoch;
        final transition = AssignmentSessionTransition(
          account: account,
          previousAccount: oldAccount,
          previousAccountHash: oldAccountHash,
          previousNativeEpoch: oldNativeEpoch,
        );
        final normalizedAccount = transition.account;
        final newAccountHash = transition.accountHash;
        String? oldPassword;
        if (oldAccount != null) {
          try {
            oldPassword = await sessionStore.readChaoxingPassword();
          } catch (_) {
            /* A damaged old credential must not block reauthentication. */
          }
          if (generation != _generation || _disposed) {
            chaoxingClient.clearSession();
            return;
          }
        }
        final oldName = _chaoxingDisplayName, oldAvatar = _chaoxingAvatarUrl;
        var nativeSwitched = false;
        var repositoryActivated = false;
        try {
          if (_nativeReminderAvailable) {
            try {
              final nativeEpoch = transition.keepsNativeAccount
                  ? await backgroundReminderGateway
                      .rotateSessionEpoch(newAccountHash)
                  : await backgroundReminderGateway.switchAccount(
                      previousAccountHash: transition.nativeSwitchSourceHash,
                      accountHash: newAccountHash,
                    );
              if (nativeEpoch <= 0) {
                throw StateError('原生会话代次无效');
              }
              _nativeSessionEpoch = nativeEpoch;
              _accountHash = newAccountHash;
              nativeSwitched = true;
            } catch (error) {
              // The server accepted the login, but native reminder state did not
              // follow. Do not commit the new local identity with split ownership.
              chaoxingClient.clearSession();
              throw StateError('原生提醒账号切换失败，登录未完成：$error');
            }
            if (generation != _generation || _disposed) {
              throw const _LoginInterruptedException();
            }
          }
          if (transition.changesLocalAccount) {
            // Full privacy cleanup also removes delivered notifications that
            // are no longer pending and have no v2 active-ID manifest.
            await _cancelPrivateNotifications();
            if (generation != _generation || _disposed) {
              throw const _LoginInterruptedException();
            }
            widgetSnapshotService.clock = _clock;
            widgetSnapshotService.courseworkState =
                const LocalCourseworkState.empty();
            widgetSnapshotService.termCatalog = null;
            await widgetSnapshotService.saveAssignmentsForContext(
              const [],
              authenticated: false,
              range: display.widgetRange,
            );
            if (generation != _generation || _disposed) {
              throw const _LoginInterruptedException();
            }
          }
          await repository.activateAccount(normalizedAccount,
              previousAccount: oldAccount);
          repositoryActivated = true;
          if (generation != _generation || _disposed) {
            throw const _LoginInterruptedException();
          }
          await sessionStore.saveChaoxingAccount(
            account: normalizedAccount,
            password: password,
            displayName: result.displayName,
            avatarUrl: result.avatarUrl,
          );
        } catch (error) {
          // The server has already authenticated the new account. A local
          // rollback must also invalidate those cookies before any old-account sync.
          chaoxingClient.clearSession();
          try {
            final rollback = transition.rollback(
              nativeSwitched: _nativeReminderAvailable && nativeSwitched,
              previousPassword: oldPassword,
            );
            switch (rollback.native) {
              case NativeLoginRollback.none:
                break;
              case NativeLoginRollback.keepRotatedEpoch:
                _accountHash = oldAccountHash;
              case NativeLoginRollback.switchBack:
                _nativeSessionEpoch =
                    await backgroundReminderGateway.switchAccount(
                  previousAccountHash: newAccountHash,
                  accountHash: oldAccountHash!,
                );
                _accountHash = oldAccountHash;
              case NativeLoginRollback.clearNewAccount:
                await backgroundReminderGateway
                    .clearActiveAccount(newAccountHash);
                _accountHash = null;
                _nativeSessionEpoch = 0;
            }
            if (repositoryActivated) {
              if (oldAccount != null) {
                await repository.activateAccount(oldAccount);
              } else {
                await repository.clear();
              }
            }
            final credentials = rollback.credentials;
            if (credentials != null) {
              await sessionStore.saveChaoxingAccount(
                  account: credentials.account,
                  password: credentials.password,
                  displayName: oldName,
                  avatarUrl: oldAvatar);
            } else {
              await sessionStore.clear();
            }
            if (!_disposed &&
                _nativeReminderAvailable &&
                nativeSwitched &&
                _authenticated &&
                _accountHash != null &&
                _nativeSessionEpoch > 0) {
              await _prepareReminderHistorySession();
            } else if (_nativeReminderAvailable && nativeSwitched) {
              _reminderHistoryReady = false;
              _reminderHistoryGeneration = 0;
            }
          } catch (_) {
            _authenticated = false;
            _account = null;
            _reminderHistoryReady = false;
            _reminderHistoryGeneration = 0;
            _assignments.clear();
            _hiddenAssignments = [];
            _courses = [];
            _unfollowed.clear();
            _pinned = const PinnedAssignments.empty();
            _courseworkState = const LocalCourseworkState.empty();
            _courseTermPreferences = const CourseTermPreferences.empty();
            _historicalSweepState = const HistoricalSweepState.empty();
            _termCatalogCache = null;
            _acknowledgedDeadlineChangeIds = <String>{};
            _pinsNeedSave = false;
            _courseNotices = CourseNoticeCollection();
            _courseChapters = CourseChapterCatalog();
            _invalidateHomeDisplayIndex();
            try {
              await sessionStore.clear();
            } catch (_) {/* Already failed closed. */}
            if (!_disposed) await _afterAssignmentsChanged();
          }
          if (error is _LoginInterruptedException) return;
          rethrow;
        }
        // The account and credentials are committed at this point.
        if (transition.releasesPreviousFiles) {
          await personalFileService.releaseAll();
          try {
            await manualAttachmentService.deleteAllAttachments();
          } catch (error) {
            debugPrint(
                '[ManualAttachment] switch_cleanup: ${error.runtimeType}');
          }
        }
        if (generation != _generation || _disposed) {
          chaoxingClient.clearSession();
          return;
        }
        if (transition.changesLocalAccount) {
          await sessionStore.clearWebSession();
          if (generation != _generation || _disposed) {
            chaoxingClient.clearSession();
            return;
          }
          chaoxingClient.previousAssignments = {};
          chaoxingClient.trackedActivityIds = {};
        }
        _recoveryWarnings.clear();
        _account = normalizedAccount;
        _accountHash = newAccountHash;
        _authenticated = true;
        String? historyRetireWarning;
        if (_nativeReminderAvailable) {
          if (transition.retiresPreviousHistory) {
            historyRetireWarning = await _retireReminderHistoryBeforeLogout(
              oldAccountHash!,
              oldNativeEpoch,
            );
            if (generation != _generation || _disposed) {
              chaoxingClient.clearSession();
              return;
            }
          }
          await _prepareReminderHistorySession();
          if (generation != _generation || _disposed) {
            chaoxingClient.clearSession();
            return;
          }
        }
        await _restoreAccountData();
        if (generation != _generation || _disposed) {
          chaoxingClient.clearSession();
          return;
        }
        if (historyRetireWarning != null) {
          _recoveryWarnings.add(historyRetireWarning);
        }
        _chaoxingDisplayName = result.displayName;
        _chaoxingAvatarUrl = result.avatarUrl;
        _agreementAccepted = true;
        _authenticated = true;
        loginSucceeded = true;
        await _reconcileBackgroundControls();
        await _maybeMigrateLegacyManualSchedules();
      });
    } finally {
      _loginRunning = false;
    }
    if (loginSucceeded &&
        _authenticated &&
        !_disposed &&
        generation == _generation) {
      unawaited(this.syncAssignmentsForTrigger(
        BackgroundSyncTrigger.manual,
        skipTaskEngineProbe: true,
      ));
      unawaited(_hydrateProfile(generation));
    }
  }

  Future<void> _hydrateProfile(int generation) async {
    if (!chaoxingClient.canHydrateProfile) return;
    try {
      final profile = await chaoxingClient.loadProfile();
      if (!_isSessionStateCurrent(epoch: generation)) return;
      final pending = (_operations ?? Future<void>.value()).then((_) async {
        if (!_isSessionStateCurrent(epoch: generation)) return;
        final password = await sessionStore.readChaoxingPassword();
        if (password == null || generation != _generation) return;
        final name = profile.displayName ?? _chaoxingDisplayName;
        final avatar = profile.avatarUrl ?? _chaoxingAvatarUrl;
        await sessionStore.saveChaoxingAccount(
            account: _account!,
            password: password,
            displayName: name,
            avatarUrl: avatar);
        _chaoxingDisplayName = name;
        _chaoxingAvatarUrl = avatar;
        if (!_disposed) this._notify();
      });
      _operations =
          pending.then<void>((_) {}, onError: (Object _, StackTrace __) {});
      await pending;
    } catch (_) {
      /* Optional profile loading must not prevent homework access. */
    }
  }

  Future<bool> _restoreLocalBackup(BackupSnapshot snapshot) async {
    final generation = _generation;
    final account = AssignmentSessionCoordinator.backupRestoreAccount(
      account: _account,
      authenticated: _authenticated,
    );
    if (account == null) return false;
    var restored = false;
    await _run(() async {
      if (!_isSessionStateCurrent(
        epoch: generation,
        account: account,
        checkAccount: true,
      )) {
        return;
      }
      await _markReminderMutationPending();
      restored = await repository.restoreBackupSnapshot(snapshot, account);
      if (!_isSessionStateCurrent(
        epoch: generation,
        account: account,
        checkAccount: true,
      )) {
        restored = false;
        return;
      }
      if (restored) {
        _visitedAssignment = null;
        returnCheckMessage = null;
        await _restoreAccountData();
      }
    });
    return restored;
  }

  Future<void> _logout() async {
    final logoutGen = ++_generation;
    this.cancelSynchronization();
    chaoxingClient.clearSession();
    _clearHomePreview(notify: true);
    _visitedAssignment = null;
    _activeVisitTicket = null;
    _visitLeftApp = false;
    _pendingReturnConfirmation = null;
    returnCheckMessage = null;
    changes = [];
    _termCatalogCache = null;
    _acknowledgedDeadlineChangeIds = <String>{};
    await _run(() async {
      if (logoutGen != _generation || _disposed) return;
      final accountHash = _accountHash;
      final sessionEpoch = _nativeSessionEpoch;
      String? historyLogoutWarning;
      String? widgetLogoutWarning;
      if (_nativeReminderAvailable && accountHash != null) {
        historyLogoutWarning = await _retireReminderHistoryBeforeLogout(
          accountHash,
          sessionEpoch,
        );
        if (logoutGen != _generation || _disposed) return;
        try {
          await backgroundReminderGateway.clearActiveAccount(accountHash);
        } catch (error) {
          if (logoutGen != _generation || _disposed) return;
          // Local identity removal must still complete. Keep the old account
          // hash so the native cleanup can be retried without account identity.
          _pendingNativeCleanupAccounts.add(accountHash);
          try {
            await _persistNativeCleanupAccounts();
          } catch (persistError) {
            if (logoutGen == _generation && !_disposed) {
              _error = '退出后原生提醒清理未确认，且清理目标未能保存：$persistError';
            }
          }
          if (logoutGen != _generation || _disposed) return;
          _privacyCleanupPending = true;
        }
        if (logoutGen != _generation || _disposed) return;
      }
      _accountHash = null;
      _nativeSessionEpoch = 0;
      widgetSnapshotService.clock = _clock;
      widgetSnapshotService.courseworkState =
          const LocalCourseworkState.empty();
      widgetSnapshotService.termCatalog = null;
      try {
        await repository.runScopedWrite(
          (_) => widgetSnapshotService.saveAssignmentsForContext(
            const [],
            authenticated: false,
            range: display.widgetRange,
          ),
          canCommit: () async => logoutGen == _generation && !_disposed,
        );
      } on StaleSessionWriteException {
        if (logoutGen != _generation || _disposed) return;
        widgetLogoutWarning = '退出时未能确认小组件内容已清除';
      } catch (error) {
        debugPrint('[WidgetSnapshot] logout: ${error.runtimeType}');
        widgetLogoutWarning = '退出时未能确认小组件内容已清除';
      }
      if (logoutGen != _generation || _disposed) return;
      try {
        await _cancelPrivateNotifications();
      } catch (_) {
        if (logoutGen != _generation || _disposed) return;
        // Logout must still remove the local identity. Keep cleanup pending so
        // a later refresh or app start can retry cancellable notifications.
        _privacyCleanupPending = true;
      }
      if (logoutGen != _generation || _disposed) return;
      await personalFileService.releaseAll();
      if (logoutGen != _generation || _disposed) return;
      try {
        await manualAttachmentService.deleteAllAttachments();
      } catch (error) {
        debugPrint('[ManualAttachment] logout_cleanup: ${error.runtimeType}');
      }
      if (logoutGen != _generation || _disposed) return;
      chaoxingClient.clearSession();
      chaoxingClient.previousAssignments = {};
      chaoxingClient.trackedActivityIds = {};
      await sessionStore.clear();
      if (logoutGen != _generation || _disposed) return;
      await repository.clear();
      if (logoutGen != _generation || _disposed) return;
      try {
        await repository.runScopedWrite(
          (prefs) => reminderRuleStore.clear(prefs: prefs),
          canCommit: () async => logoutGen == _generation && !_disposed,
        );
      } on StaleSessionWriteException {
        return;
      }
      if (logoutGen != _generation || _disposed) return;
      _authenticated = false;
      _account = null;
      homeFilters = const HomeFilters();
      personal = PersonalWorkspace();
      notebook = StudyNotebook();
      _courseNotices = CourseNoticeCollection();
      _courseChapters = CourseChapterCatalog();
      _isChapterSyncing = false;
      _chapterSyncProgressText = null;
      _agreementAccepted = false;
      _needsProfileRecovery = false;
      _reminderOffsetsMinutes = ReminderRuleStore.defaultOffsetsMinutes;
      _allowUrgentDeadlineNightBreakthrough = false;
      _deadlineChannelId = LocalNotificationService.assignmentV3Channel;
      notificationService.activeDeadlineChannelId =
          LocalNotificationService.assignmentV3Channel;
      _chaoxingDisplayName = null;
      _chaoxingAvatarUrl = null;
      _error = null;
      _warningBuckets.clearAll();
      _recoveryWarnings.clear();
      _assignments.clear();
      _lastSyncAt = null;
      _lastSyncAttemptAt = null;
      _serverBackoffUntil = null;
      _hiddenAssignments = [];
      _courses = [];
      _unfollowed.clear();
      _pinned = const PinnedAssignments.empty();
      _courseworkState = const LocalCourseworkState.empty();
      _courseTermPreferences = const CourseTermPreferences.empty();
      _historicalSweepState = const HistoricalSweepState.empty();
      _lastRequestedSyncScope = AssignmentSyncScope.current;
      _lastTargetedCourseKeys = const {};
      _lastSyncSourceResults = const [];
      _termCatalogCache = null;
      _pinsNeedSave = false;
      _invalidateHomeDisplayIndex();
      syncReport = const SyncReport();
      _visitedAssignment = null;
      _activeVisitTicket = null;
      _visitLeftApp = false;
      _pendingReturnConfirmation = null;
      returnCheckMessage = null;
      changes = [];
      _acknowledgedDeadlineChangeIds = <String>{};
      repository.recoveryWarning = null;
      await _reconcileBackgroundControls();
      if (logoutGen != _generation || _disposed) return;
      await _afterAssignmentsChanged(updateWidget: false);
      if (logoutGen != _generation || _disposed) return;
      if (widgetLogoutWarning != null) {
        _warningBuckets.addServiceWarning(widgetLogoutWarning);
      }
      if (historyLogoutWarning != null) {
        _warningBuckets.addServiceWarning(historyLogoutWarning);
      }
      _error = AssignmentSessionCoordinator.logoutError(
        serviceWarnings: _warningBuckets.serviceWarnings,
        historyWarning: historyLogoutWarning,
        nativeCleanupPending: _pendingNativeCleanupAccounts.isNotEmpty,
        currentError: _error,
      );
    });
  }
}

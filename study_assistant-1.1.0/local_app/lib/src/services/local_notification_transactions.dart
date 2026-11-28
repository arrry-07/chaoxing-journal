part of 'local_notification_service.dart';

extension _LocalNotificationTransactions on LocalNotificationService {
  Future<void> _cancelPrivateSchedules() async {
    _pendingManualTestTimer?.cancel();
    _pendingManualTestTimer = null;
    await _ensurePluginInitialized();
    await _runScheduleMutation(() async {
      _pendingManualTestTimer?.cancel();
      _pendingManualTestTimer = null;
      final prefs = await SharedPreferences.getInstance();
      final ids = <int>{};
      final validActiveManifests = <String>{};
      final validJournals = <String>{};
      final damagedActiveManifests = <String>{};
      final damagedJournals = <String>{};
      final damaged = <String>[];
      Object? systemReadFailure;

      // Privacy cleanup must not be coupled to recovery of an unrelated
      // category. Even if a manifest is damaged, the OS pending-request list
      // still identifies scheduled private payloads that can be cancelled.
      try {
        final pending = await _plugin.pendingNotificationRequests();
        ids.addAll(pending
            .where((item) =>
                NotificationSchedulePolicy.isPrivatePayload(item.payload))
            .map((item) => item.id));
      } catch (error) {
        systemReadFailure = error;
      }

      // Delivered notifications no longer appear in the pending-request
      // list. Include still-visible notifications so a damaged or missing
      // manifest cannot leave lock-screen content behind unnoticed.
      try {
        final active = await _plugin.getActiveNotifications();
        ids.addAll(active
            .where(
                (item) => _isPrivateActiveNotification(item) && item.id != null)
            .map((item) => item.id!));
      } catch (error) {
        systemReadFailure ??= error;
      }

      for (final category in LocalNotificationService._scheduleCategories) {
        try {
          final activeIds = _readActiveIds(prefs, category);
          if (prefs.containsKey(_activeKey(category))) {
            validActiveManifests.add(category);
          }
          ids.addAll(activeIds);
        } catch (error) {
          damagedActiveManifests.add(category);
          damaged.add('$category 已生效提醒清单损坏：$error');
        }
        try {
          final journal = _readJournal(prefs, category);
          if (journal != null) {
            ids.addAll(journal['oldIds'] as List<int>);
            ids.addAll(journal['newIds'] as List<int>);
            validJournals.add(category);
          }
        } catch (error) {
          damagedJournals.add(category);
          damaged.add('$category 提醒事务记录损坏：$error');
        }
      }

      final failures = await _cancelIds(ids);
      if (failures.isNotEmpty) {
        lastWarning = '隐私提醒清理未完成，部分通知仍可能保留：${failures.join('; ')}';
        throw StateError(lastWarning!);
      }

      // If the OS list could not be read, do not erase otherwise-valid
      // manifests: they are still needed to retry the unknown remainder.
      if (systemReadFailure != null) {
        lastWarning = '已取消可识别的隐私提醒，但系统通知状态读取失败，无法确认清理完整性：$systemReadFailure';
        throw StateError(lastWarning!);
      }

      try {
        for (final category in LocalNotificationService._scheduleCategories) {
          // A corrupt journal may contain the only copy of staged or already
          // delivered IDs. Keep all metadata for that category for diagnosis.
          if (damagedJournals.contains(category)) continue;
          final activeIsDamaged = damagedActiveManifests.contains(category);
          final journalIsValid = validJournals.contains(category);
          // A valid journal contains the complete old/new ID sets, so after
          // cancelling both sets it can safely repair a damaged active list.
          if (activeIsDamaged && !journalIsValid) continue;
          if (validActiveManifests.contains(category) || activeIsDamaged) {
            await _writeActiveIds(prefs, category, const []);
          }
          if (journalIsValid) await _removeJournal(prefs, category);
          if (category == 'summary') {
            await prefs.remove(LocalNotificationService._summaryEvidenceKey);
          }
        }
      } catch (error) {
        lastWarning = '已取消可识别的隐私提醒，但本机恢复记录清理失败：$error';
        throw StateError(lastWarning!);
      }

      for (final category
          in validJournals.intersection(damagedActiveManifests)) {
        damaged.removeWhere((item) => item.startsWith('$category 已生效提醒清单损坏：'));
      }

      if (damaged.isNotEmpty) {
        // Keep damaged records visible for manual recovery. Their delivered
        // notification IDs cannot be reconstructed from pending requests.
        lastWarning = '已尽可能清理可识别的隐私提醒，但部分历史通知无法确认：${damaged.join('；')}';
        throw StateError(lastWarning!);
      }
      lastWarning = null;
    });
  }

  Future<bool> _isLegacyAssignmentMigrationComplete() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await LocalNotificationService._legacyMigrationChannel
              .invokeMethod<bool>('isMigrationComplete') ??
          false;
    } on PlatformException catch (error) {
      debugPrint('[Notification] legacyMigrationStatus: ${error.runtimeType}');
      return false;
    } on MissingPluginException catch (error) {
      debugPrint('[Notification] legacyMigrationStatus: ${error.runtimeType}');
      return false;
    }
  }

  Future<void> _removeLegacyAssignmentSchedules() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _ensurePluginInitialized();
    await _runScheduleMutation(() async {
      final prefs = await SharedPreferences.getInstance();
      final owned = <int>{};
      final pending = await _plugin.pendingNotificationRequests();
      for (final item in pending) {
        if (item.payload?.startsWith('a:') == true) owned.add(item.id);
      }
      final active = await _plugin.getActiveNotifications();
      for (final item in active) {
        if (item.id != null && item.payload?.startsWith('a:') == true) {
          owned.add(item.id!);
        }
      }
      try {
        owned.addAll(_readActiveIds(prefs, 'assignments'));
      } catch (error) {
        throw StateError('旧作业提醒清单损坏，未执行迁移：$error');
      }
      try {
        final journal = _readJournal(prefs, 'assignments');
        if (journal != null) {
          owned.addAll(journal['oldIds'] as List<int>);
          owned.addAll(journal['newIds'] as List<int>);
        }
      } catch (error) {
        throw StateError('旧作业提醒事务记录损坏，未执行迁移：$error');
      }

      final Map<Object?, Object?>? result;
      try {
        result = await LocalNotificationService._legacyMigrationChannel
            .invokeMethod<Map<Object?, Object?>>(
          'retireLegacyAssignments',
          {
            'ownedIds': owned.toList()..sort(),
            'excludeIds': [DailySummary.baseId + 8, DailySummary.baseId + 9],
          },
        );
      } catch (error) {
        throw StateError('旧作业提醒迁移失败：$error');
      }
      if (result == null) {
        throw StateError('旧作业提醒迁移原生通道未返回结果');
      }
      if (result['completed'] != true) {
        final unknown = result['preservedUnknownIds'];
        final warning = result['warning'];
        throw StateError(
          '旧作业提醒迁移未完成'
          '${unknown is List && unknown.isNotEmpty ? '；保留未知归属：${unknown.join(', ')}' : ''}'
          '${warning == null ? '' : '；$warning'}',
        );
      }

      // Native proof and its durability barrier succeeded; only now retire the
      // local manifests so a failed migration remains retryable.
      await _writeActiveIds(prefs, 'assignments', const []);
      await _removeJournal(prefs, 'assignments');
    });
  }

  Future<PluginScheduleEvidenceSnapshot> _readScheduleEvidence() async {
    await _ensurePluginInitialized();
    final byId = <int, PluginScheduleEvidence>{};
    String? error;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final item in pending) {
        byId[item.id] = PluginScheduleEvidence(
          id: item.id,
          payload: item.payload,
          channelId: null,
          pending: true,
          active: false,
        );
      }
    } catch (readError) {
      error = '待投递提醒读取失败：$readError';
    }
    try {
      final active = await _plugin.getActiveNotifications();
      for (final item in active) {
        final id = item.id;
        if (id == null) continue;
        final previous = byId[id];
        byId[id] = PluginScheduleEvidence(
          id: id,
          payload: item.payload ?? previous?.payload,
          channelId: item.channelId ?? previous?.channelId,
          pending: previous?.pending ?? false,
          active: true,
        );
      }
    } catch (readError) {
      error = error == null
          ? '当前可见提醒读取失败：$readError'
          : '$error；当前可见提醒读取失败：$readError';
    }
    return PluginScheduleEvidenceSnapshot(
      items: byId.values.toList(),
      error: error,
      checkedAt: DateTime.now(),
    );
  }

  List<({String logicalKey, int scheduledAtMs, int? notificationId})>
      _readSummaryEvidence(SharedPreferences prefs) {
    final raw = prefs.getString(LocalNotificationService._summaryEvidenceKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final records =
          <({String logicalKey, int scheduledAtMs, int? notificationId})>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final key = item['logicalKey'] as String?;
        final scheduledAtMs = (item['scheduledAtMs'] as num?)?.toInt();
        final notificationId = (item['notificationId'] as num?)?.toInt();
        if (key == null || key.isEmpty || scheduledAtMs == null) continue;
        records.add((
          logicalKey: key,
          scheduledAtMs: scheduledAtMs,
          notificationId: notificationId,
        ));
      }
      return records;
    } on FormatException catch (error) {
      debugPrint('[Notification] summaryEvidence: ${error.runtimeType}');
      return const [];
    } on TypeError catch (error) {
      debugPrint('[Notification] summaryEvidence: ${error.runtimeType}');
      return const [];
    }
  }

  Future<void> _recoverPendingSchedules() async {
    await _ensurePluginInitialized();
    await _runScheduleMutation(_recoverAllScheduleTransactionsLocked);
  }

  Future<bool> _hasPendingScheduleRecovery() async {
    try {
      return await _readScheduleRecovery();
    } on Exception catch (error) {
      // When recovery state is unreadable, retain the pending indicator.
      debugPrint('[Notification] scheduleRecoveryState: ${error.runtimeType}');
      return true;
    } on TypeError catch (error) {
      debugPrint('[Notification] scheduleRecoveryState: ${error.runtimeType}');
      return true;
    }
  }

  Future<bool> _readScheduleRecovery() async {
    final prefs = await SharedPreferences.getInstance();
    final activeIdsByCategory = <String, Set<int>>{};
    for (final category in LocalNotificationService._scheduleCategories) {
      if (prefs.getString(_journalKey(category)) != null) return true;
      activeIdsByCategory[category] = _readActiveIds(prefs, category).toSet();
    }
    final pending = await _plugin.pendingNotificationRequests();
    for (final item in pending) {
      if (item.id < 2000000000) continue;
      final category =
          NotificationSchedulePolicy.scheduleCategoryForPayload(item.payload);
      if (category != null &&
          !activeIdsByCategory[category]!.contains(item.id)) {
        return true;
      }
    }
    final active = await _plugin.getActiveNotifications();
    for (final item in active) {
      final id = item.id;
      if (id == null || id < 2000000000) continue;
      final category =
          NotificationSchedulePolicy.scheduleCategoryForPayload(item.payload);
      if (category != null && !activeIdsByCategory[category]!.contains(id)) {
        return true;
      }
    }
    return false;
  }

  Future<List<int>> _replaceScheduleBatch({
    required String category,
    required bool Function(String?) belongs,
    bool Function(String?)? retainOldPayload,
    required List<Object> schedules,
    required Future<void> Function(int id, Object item) schedule,
  }) async {
    return _runScheduleMutation(() async {
      await _recoverScheduleTransactionLocked(category);
      final prefs = await SharedPreferences.getInstance();
      var pending = await _plugin.pendingNotificationRequests();
      var oldIds = <int>{
        ..._readActiveIds(prefs, category),
        ...pending
            .where((item) => belongs(item.payload))
            .map((item) => item.id),
      };
      if (retainOldPayload != null) {
        final staleIds = <int>{
          for (final item in pending)
            if (belongs(item.payload) && !retainOldPayload(item.payload))
              item.id,
        };
        // Delivered notifications usually omit payload on Android. Only an
        // explicit p: payload is safe evidence for mapping an ID to an entry.
        try {
          final visible = await _plugin.getActiveNotifications();
          for (final item in visible) {
            final id = item.id;
            if (id == null ||
                !belongs(item.payload) ||
                retainOldPayload(item.payload)) {
              continue;
            }
            staleIds.add(id);
            oldIds.add(id);
          }
        } catch (_) {
          // Pending requests still cover future reminders. An unreadable
          // delivered-notification list must not block that cleanup.
        }
        if (staleIds.isNotEmpty) {
          final retained = oldIds.difference(staleIds);
          await _writeJournal(prefs, category, {
            'version': 2,
            'category': category,
            'phase': 'committed',
            'oldIds': staleIds.toList()..sort(),
            'newIds': retained.toList()..sort(),
          });
          // Persist the cleanup decision before cancelling. Recovery either
          // finishes the cancellation or leaves the committed journal for a
          // later health/startup retry.
          await _recoverScheduleTransactionLocked(category);
          pending = await _plugin.pendingNotificationRequests();
          oldIds = <int>{
            ..._readActiveIds(prefs, category),
            ...pending
                .where((item) => belongs(item.payload))
                .map((item) => item.id),
          };
        }
      }
      final reserved = <int>{...pending.map((item) => item.id)};
      for (final otherCategory
          in LocalNotificationService._scheduleCategories) {
        try {
          reserved.addAll(_readActiveIds(prefs, otherCategory));
        } catch (error) {
          if (otherCategory == category) rethrow;
          lastWarning = NotificationSchedulePolicy.appendWarning(
              lastWarning, '$otherCategory 的已生效提醒清单损坏，已隔离该类别并保留现有通知');
        }
        try {
          final otherJournal = _readJournal(prefs, otherCategory);
          if (otherJournal != null) {
            reserved.addAll(otherJournal['oldIds'] as List<int>);
            reserved.addAll(otherJournal['newIds'] as List<int>);
          }
        } catch (error) {
          if (otherCategory == category) rethrow;
          lastWarning = NotificationSchedulePolicy.appendWarning(
              lastWarning, '$otherCategory 的提醒事务记录损坏，已隔离该类别并保留现有通知');
        }
      }
      final newIds = NotificationSchedulePolicy.allocateNotificationIds(
        schedules.length,
        reserved,
        nextInt: Random.secure().nextInt,
      );
      final journal = <String, Object>{
        'version': 2,
        'category': category,
        'phase': 'staging',
        'oldIds': oldIds.toList()..sort(),
        'newIds': newIds,
      };
      await _writeJournal(prefs, category, journal);

      try {
        for (var index = 0; index < schedules.length; index++) {
          await schedule(newIds[index], schedules[index]);
        }
      } catch (error, stack) {
        final compensationFailures = await _cancelIds(newIds);
        if (compensationFailures.isEmpty) {
          try {
            await _removeJournal(prefs, category);
          } catch (cleanupError) {
            lastWarning = '新提醒安排失败，补偿通知已取消，但事务记录清理失败；下次启动将继续恢复';
            throw StateError('$error；事务记录清理失败：$cleanupError');
          }
          Error.throwWithStackTrace(error, stack);
        }
        lastWarning = '新提醒安排失败，部分临时提醒未能撤销；旧提醒已保留，系统将在下次启动或重试时继续恢复';
        throw StateError('$error；补偿取消失败：${compensationFailures.join('; ')}');
      }

      final committed = <String, Object>{...journal, 'phase': 'committed'};
      try {
        await _writeJournal(prefs, category, committed);
      } catch (error, stack) {
        // A preferences write can fail after the platform has already made
        // the value durable. Never cancel the new batch until a read-back
        // proves that the committed marker was not persisted.
        String? persisted;
        var stateVerified = false;
        try {
          await prefs.reload();
          persisted = prefs.getString(_journalKey(category));
          stateVerified = true;
        } catch (_) {
          stateVerified = false;
        }
        final committedRaw = jsonEncode(committed);
        final stagingRaw = jsonEncode(journal);
        if (stateVerified && persisted == committedRaw) {
          await _recoverScheduleTransactionLocked(category);
          return newIds;
        }
        if (!stateVerified || (persisted != stagingRaw && persisted != null)) {
          lastWarning = '提醒提交状态无法核实；新旧提醒和事务记录均予以保留，请重试恢复，勿手动清理通知';
          throw StateError('$error；无法确认事务记录当前状态，已保留新旧批次');
        }
        if (persisted == null) {
          // The previously durable staging record is unexpectedly absent.
          // Recreate it before compensation so a process restart can finish
          // cleanup if this operation is interrupted again.
          try {
            await _writeJournal(prefs, category, journal);
          } catch (repairError) {
            lastWarning = '事务提交失败且无法重建恢复记录；新旧提醒均予以保留，需人工检查本机提醒状态';
            throw StateError('$error；恢复记录重建失败：$repairError');
          }
        }
        final compensationFailures = await _cancelIds(newIds);
        if (compensationFailures.isNotEmpty) {
          lastWarning = '提醒批次提交失败，临时提醒撤销未完成；旧提醒已保留，请重试恢复';
          throw StateError('$error；补偿取消失败：${compensationFailures.join('; ')}');
        }
        try {
          await _removeJournal(prefs, category);
        } catch (cleanupError) {
          lastWarning = '新提醒已取消，但事务记录清理失败；请重试提醒恢复';
          throw StateError('$error；事务记录清理失败：$cleanupError');
        }
        Error.throwWithStackTrace(error, stack);
      }

      // Once the committed marker is durable, the new batch is authoritative.
      // A failed old-batch cancellation leaves a committed journal for retry.
      await _recoverScheduleTransactionLocked(category);
      return newIds;
    });
  }

  Future<T> _runScheduleMutation<T>(Future<T> Function() action) async {
    final previous = LocalNotificationService._scheduleMutationQueue;
    final completed = Completer<void>();
    LocalNotificationService._scheduleMutationQueue = completed.future;
    try {
      await previous;
      return await action();
    } finally {
      completed.complete();
    }
  }

  Future<void> _recoverAllScheduleTransactionsLocked() async {
    final failures = <String>[];
    final activeIdsByCategory = <String, Set<int>>{};
    final hasActiveManifestByCategory = <String, bool>{};
    final blockedOrphanCategories = <String>{};
    for (final category in LocalNotificationService._scheduleCategories) {
      final prefs = await SharedPreferences.getInstance();
      try {
        await _recoverScheduleTransactionLocked(category);
        activeIdsByCategory[category] = _readActiveIds(prefs, category).toSet();
        hasActiveManifestByCategory[category] =
            prefs.containsKey(_activeKey(category));
      } catch (error) {
        failures.add('$category: $error');
        // A v2 journal carries its owning category. If it has been copied or
        // swapped into another category's key, do not reinterpret the IDs as
        // an orphan of the embedded category and guess which phase won.
        try {
          final raw = prefs.getString(_journalKey(category));
          final decoded = raw == null ? null : jsonDecode(raw);
          final owner = decoded is Map ? decoded['category'] : null;
          if (owner is String &&
              LocalNotificationService._scheduleCategories.contains(owner) &&
              owner != category) {
            blockedOrphanCategories.add(owner);
          } else if (decoded is Map && decoded['version'] == 1) {
            final legacyIds = <int>{
              if (decoded['oldIds'] is List)
                ...(decoded['oldIds'] as List).whereType<int>(),
              if (decoded['newIds'] is List)
                ...(decoded['newIds'] as List).whereType<int>(),
            };
            for (final other in LocalNotificationService._scheduleCategories
                .where((item) => item != category)) {
              try {
                if (legacyIds
                    .intersection(_readActiveIds(prefs, other).toSet())
                    .isNotEmpty) {
                  blockedOrphanCategories.add(other);
                }
              } catch (_) {
                // The damaged manifest is handled by its own category pass.
              }
            }
            try {
              final pending = await _plugin.pendingNotificationRequests();
              final active = await _plugin.getActiveNotifications();
              for (final item in pending) {
                final owner =
                    NotificationSchedulePolicy.scheduleCategoryForPayload(
                        item.payload);
                if (legacyIds.contains(item.id) &&
                    owner != null &&
                    owner != category) {
                  blockedOrphanCategories.add(owner);
                }
              }
              for (final item in active) {
                final id = item.id;
                final owner =
                    NotificationSchedulePolicy.scheduleCategoryForPayload(
                        item.payload);
                if (id != null &&
                    legacyIds.contains(id) &&
                    owner != null &&
                    owner != category) {
                  blockedOrphanCategories.add(owner);
                }
              }
            } catch (_) {
              // The primary v1 ownership check already failed closed.
            }
          }
        } catch (_) {
          // The primary recovery error already records unreadable metadata.
        }
      }
    }
    final orphaned = <String, Set<int>>{};
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final item in pending) {
        if (item.id >= 2000000000) {
          final category =
              NotificationSchedulePolicy.scheduleCategoryForPayload(
                  item.payload);
          if (category != null && activeIdsByCategory.containsKey(category)) {
            final foreignManifest = activeIdsByCategory.entries
                .where((entry) =>
                    entry.key != category && entry.value.contains(item.id))
                .firstOrNull;
            if (foreignManifest != null) {
              blockedOrphanCategories.add(category);
              failures.add(
                  '$category 通知 ID 同时登记在 ${foreignManifest.key} 清单，已保留并等待核对');
            } else if (!activeIdsByCategory[category]!.contains(item.id)) {
              orphaned.putIfAbsent(category, () => <int>{}).add(item.id);
            }
          }
        }
      }
    } catch (error) {
      failures.add('待投递通知扫描失败: $error');
    }
    try {
      // A transaction notification may have fired while the process was
      // stopped. It is then absent from pendingNotificationRequests but still
      // visible in NotificationManager; include it in orphan reconciliation.
      final active = await _plugin.getActiveNotifications();
      for (final item in active) {
        final id = item.id;
        if (id == null || id < 2000000000) continue;
        final category =
            NotificationSchedulePolicy.scheduleCategoryForPayload(item.payload);
        if (category != null && activeIdsByCategory.containsKey(category)) {
          final foreignManifest = activeIdsByCategory.entries
              .where(
                  (entry) => entry.key != category && entry.value.contains(id))
              .firstOrNull;
          if (foreignManifest != null) {
            blockedOrphanCategories.add(category);
            failures.add(
                '$category 当前可见通知 ID 同时登记在 ${foreignManifest.key} 清单，已保留并等待核对');
          } else if (!activeIdsByCategory[category]!.contains(id)) {
            orphaned.putIfAbsent(category, () => <int>{}).add(id);
          }
        }
      }
    } catch (error) {
      failures.add('当前可见通知扫描失败: $error');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final entry in orphaned.entries) {
        final category = entry.key;
        if (blockedOrphanCategories.contains(category)) {
          failures.add('$category 的事务记录出现在其他类别，已保留通知并等待人工核对');
          continue;
        }
        if (hasActiveManifestByCategory[category] != true) {
          failures.add('$category 存在未登记的事务通知，但有效提醒清单缺失，无法安全判断新旧批次；已保留通知');
          continue;
        }
        final oldIds = activeIdsByCategory[category]!.toList()..sort();
        final newIds = entry.value.toList()..sort();
        try {
          await _writeJournal(prefs, category, {
            'version': 2,
            'category': category,
            'phase': 'staging',
            'oldIds': oldIds,
            'newIds': newIds,
          });
          await _recoverScheduleTransactionLocked(category);
        } catch (error) {
          // If no durable journal can be written, still attempt cancellation.
          // A failed cancellation remains discoverable in the OS pending list.
          final cancelFailures = await _cancelIds(newIds);
          if (cancelFailures.isNotEmpty) {
            failures.add(
                '$category 存在未登记的事务通知，恢复记录写入失败且取消失败：${cancelFailures.join('; ')}；$error');
            continue;
          }
          try {
            // If the journal write actually reached storage before its
            // acknowledgement failed, finish removing that now-resolved
            // staging record instead of leaving a permanent false warning.
            await _recoverScheduleTransactionLocked(category);
          } catch (cleanupError) {
            failures.add('$category 未登记通知已取消，但恢复记录仍未能收敛：$cleanupError');
          }
        }
      }
    } catch (error) {
      failures.add('未登记的通知事务: $error');
    }
    if (failures.isNotEmpty) {
      lastWarning = '提醒恢复仍有未完成操作：${failures.join('；')}';
      throw StateError(lastWarning!);
    }
    lastWarning = null;
  }

  Future<void> _recoverScheduleTransactionLocked(String category) async {
    final prefs = await SharedPreferences.getInstance();
    final journal = _readJournal(prefs, category);
    if (journal == null) return;
    var unresolvedOldIds = <int>{};
    if (journal['version'] == 1) {
      await _verifyLegacyJournalOwnership(category, journal, prefs);
    } else {
      unresolvedOldIds =
          await _verifyV2JournalOwnership(category, journal, prefs);
    }
    final phase = journal['phase'] as String;
    final oldIds = journal['oldIds'] as List<int>;
    final newIds = journal['newIds'] as List<int>;
    if (phase == 'staging') {
      final failures = await _cancelIds(newIds);
      if (failures.isNotEmpty) {
        lastWarning = '提醒批次尚未提交，临时通知撤销失败：${failures.join('; ')}';
        throw StateError(lastWarning!);
      }
      await _removeJournal(prefs, category);
      return;
    }
    if (phase == 'committed') {
      final cancellableIds =
          oldIds.where((id) => !unresolvedOldIds.contains(id)).toList();
      final failures = await _cancelIds(cancellableIds);
      if (failures.isNotEmpty) {
        lastWarning = '新提醒批次已生效，旧通知清理失败：${failures.join('; ')}';
        throw StateError(lastWarning!);
      }
      await _writeActiveIds(prefs, category, newIds);
      if (unresolvedOldIds.isNotEmpty) {
        await _writeJournal(prefs, category, {
          'version': 2,
          'category': category,
          'phase': 'committed',
          'oldIds': unresolvedOldIds.toList()..sort(),
          'newIds': newIds,
        });
        lastWarning = NotificationSchedulePolicy.appendWarning(
            lastWarning,
            '已取消 ${cancellableIds.length} 条可确认的待投递个人提醒；'
            '系统可见通知完整性未确认，'
            '${unresolvedOldIds.length} 条旧提醒仍待核对');
        throw StateError(lastWarning!);
      }
      await _removeJournal(prefs, category);
      return;
    }
    throw FormatException('未知提醒事务阶段：$phase');
  }

  Future<Set<int>> _verifyV2JournalOwnership(
    String category,
    Map<String, dynamic> journal,
    SharedPreferences prefs,
  ) async {
    final transactionIds = <int>{
      ...(journal['oldIds'] as List<int>),
      ...(journal['newIds'] as List<int>),
    };
    for (final other in LocalNotificationService._scheduleCategories
        .where((item) => item != category)) {
      final foreignIds = _readActiveIds(prefs, other).toSet();
      if (transactionIds.intersection(foreignIds).isNotEmpty) {
        throw FormatException('v2 $category 事务包含 $other 类别的通知 ID');
      }
    }

    final pending = await _plugin.pendingNotificationRequests();
    final List<ActiveNotification> active;
    try {
      active = await _plugin.getActiveNotifications();
    } catch (error) {
      if (category != 'manual' || journal['phase'] != 'committed') {
        rethrow;
      }
      // Delivered-notification enumeration is unavailable. Only cancel IDs
      // that the pending list still proves belong to this manual batch via an
      // explicit p: payload. Anything else stays in the journal for a later
      // recovery; never infer ownership from an ID alone.
      final pendingById = <int, String?>{
        for (final item in pending) item.id: item.payload,
      };
      final unresolved = <int>{};
      for (final id in journal['oldIds'] as List<int>) {
        if (!pendingById.containsKey(id)) {
          unresolved.add(id);
          continue;
        }
        final payload = pendingById[id];
        final owner =
            NotificationSchedulePolicy.scheduleCategoryForPayload(payload);
        if (owner == 'manual' &&
            NotificationSchedulePolicy.isValidManualPayload(payload)) {
          continue;
        }
        if (owner != null && owner != category) {
          throw FormatException('v2 $category 事务 ID 实际属于 $owner 通知类别');
        }
        unresolved.add(id);
      }
      final oldIdSet = (journal['oldIds'] as List<int>).toSet();
      for (final item in pending) {
        if (!transactionIds.contains(item.id)) continue;
        if (oldIdSet.contains(item.id) && unresolved.contains(item.id)) {
          continue;
        }
        final owner =
            NotificationSchedulePolicy.scheduleCategoryForPayload(item.payload);
        if (owner != category) {
          throw FormatException('v2 $category 事务 ID 缺少可证明的类别归属');
        }
      }
      if (lastWarning?.contains('当前可见通知列表读取失败') != true) {
        lastWarning = NotificationSchedulePolicy.appendWarning(
            lastWarning,
            '当前可见通知列表读取失败；已投递通知的完整性未确认，'
            '仅处理有明确 p: 归属证据的待投递个人提醒');
      }
      return unresolved;
    }
    void verifyVisible(int id, String? owner) {
      if (!transactionIds.contains(id)) return;
      if (owner == null) {
        throw FormatException('v2 $category 事务 ID 缺少可证明的类别归属');
      }
      if (owner != category) {
        throw FormatException('v2 $category 事务 ID 实际属于 $owner 通知类别');
      }
    }

    for (final item in pending) {
      verifyVisible(item.id,
          NotificationSchedulePolicy.scheduleCategoryForPayload(item.payload));
    }
    for (final item in active) {
      final id = item.id;
      if (id == null || !transactionIds.contains(id)) continue;
      var owner =
          NotificationSchedulePolicy.scheduleCategoryForPayload(item.payload);
      final channelOwner =
          NotificationSchedulePolicy.scheduleCategoryForChannel(item.channelId);
      if (owner != null && channelOwner != null && owner != channelOwner) {
        throw FormatException('v2 $category 事务 ID 的 payload 与原生渠道归属冲突');
      }
      // Android v18 omits payload for delivered notifications. A matching
      // native channel is independent category evidence for a v2 journal with
      // explicit category and non-overlapping manifests. Do not guess from an
      // ID alone, an unknown nonempty payload, or a tagged notification.
      if (owner == null &&
          (item.payload == null || item.payload!.isEmpty) &&
          item.tag == null) {
        owner = channelOwner;
      }
      verifyVisible(id, owner);
    }
    return const <int>{};
  }

  Future<void> _verifyLegacyJournalOwnership(
    String category,
    Map<String, dynamic> journal,
    SharedPreferences prefs,
  ) async {
    final oldIds = (journal['oldIds'] as List<int>).toSet();
    final newIds = (journal['newIds'] as List<int>).toSet();
    final transactionIds = {...oldIds, ...newIds};
    var foreignManifestUnreadable = false;

    for (final other in LocalNotificationService._scheduleCategories
        .where((item) => item != category)) {
      try {
        final foreignIds = _readActiveIds(prefs, other).toSet();
        if (transactionIds.intersection(foreignIds).isNotEmpty) {
          throw FormatException('旧版 $category 事务包含已登记在 $other 类别的通知 ID');
        }
      } on FormatException catch (error) {
        if (error.message.contains('已登记在')) rethrow;
        foreignManifestUnreadable = true;
      }
    }

    final pending = await _plugin.pendingNotificationRequests();
    final active = await _plugin.getActiveNotifications();
    var visibleTransactionIdMatches = false;
    void verifyVisible(int id, String? payload) {
      if (!transactionIds.contains(id)) return;
      final owner =
          NotificationSchedulePolicy.scheduleCategoryForPayload(payload);
      if (owner != null && owner != category) {
        throw FormatException('旧版 $category 事务 ID 实际属于 $owner 通知类别');
      }
      if (owner == category) {
        visibleTransactionIdMatches = true;
      }
    }

    for (final item in pending) {
      verifyVisible(item.id, item.payload);
    }
    for (final item in active) {
      final id = item.id;
      if (id != null) verifyVisible(id, item.payload);
    }

    // v1 did not persist its owning category. A manifest stored beside the
    // journal is not independent evidence: both keys may have been copied or
    // swapped together. Require at least one transaction ID to remain visible
    // in the OS with a payload that proves this category. Otherwise preserve
    // the journal rather than destructively guessing its owner.
    if (!visibleTransactionIdMatches || foreignManifestUnreadable) {
      throw const FormatException('旧版提醒事务缺少类别归属证据，已保留原通知等待人工核对');
    }
  }

  Map<String, dynamic>? _readJournal(SharedPreferences prefs, String category) {
    final raw = prefs.getString(_journalKey(category));
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        !const [1, 2].contains(decoded['version']) ||
        (decoded['version'] == 2 && decoded['category'] != category) ||
        (decoded['category'] != null && decoded['category'] != category) ||
        !const ['staging', 'committed'].contains(decoded['phase'])) {
      throw const FormatException('提醒事务记录格式无效');
    }
    List<int> ids(dynamic value, {bool transactional = false}) {
      if (value is! List ||
          value.any((id) =>
              id is! int ||
              id < 0 ||
              id > 0x7fffffff ||
              (transactional && id < 2000000000))) {
        throw const FormatException('提醒事务 ID 列表无效');
      }
      final result = value.cast<int>();
      if (result.toSet().length != result.length) {
        throw const FormatException('提醒事务 ID 重复');
      }
      return result;
    }

    final oldIds = ids(decoded['oldIds']);
    // Staging always allocates fresh transactional IDs. A committed cleanup
    // may retain still-valid legacy manual IDs in newIds; category ownership
    // is still verified below before any cancellation.
    final newIds = ids(
      decoded['newIds'],
      transactional: decoded['phase'] == 'staging',
    );
    if (oldIds.toSet().intersection(newIds.toSet()).isNotEmpty) {
      throw const FormatException('提醒事务新旧 ID 重叠');
    }
    return {
      'version': decoded['version'] as int,
      if (decoded['category'] is String) 'category': decoded['category'],
      'phase': decoded['phase'] as String,
      'oldIds': oldIds,
      'newIds': newIds,
    };
  }

  List<int> _readActiveIds(SharedPreferences prefs, String category) {
    final raw = prefs.getStringList(_activeKey(category)) ?? const [];
    final ids = <int>[];
    for (final item in raw) {
      final id = int.tryParse(item);
      if (id == null || id < 0 || id > 0x7fffffff) {
        throw FormatException('已生效提醒 ID 无效：$category');
      }
      ids.add(id);
    }
    if (ids.toSet().length != ids.length) {
      throw FormatException('已生效提醒 ID 重复：$category');
    }
    return ids;
  }

  Future<void> _writeJournal(SharedPreferences prefs, String category,
      Map<String, Object> journal) async {
    final encoded = jsonEncode(journal);
    Object? writeFailure;
    try {
      if (await prefs.setString(_journalKey(category), encoded)) return;
      writeFailure = StateError('提醒事务记录写入返回失败');
    } catch (error) {
      writeFailure = error;
    }
    try {
      await prefs.reload();
      if (prefs.getString(_journalKey(category)) == encoded) return;
    } catch (verifyError) {
      throw StateError('提醒事务记录写入结果无法核实：$writeFailure；$verifyError');
    }
    throw StateError('提醒事务记录未能持久化：$writeFailure');
  }

  Future<void> _writeActiveIds(
      SharedPreferences prefs, String category, List<int> ids) async {
    final encoded = ids.map((id) => '$id').toList();
    if (!await prefs.setStringList(_activeKey(category), encoded)) {
      await prefs.reload();
      if (!listEquals(prefs.getStringList(_activeKey(category)), encoded)) {
        throw StateError('已生效提醒清单未能持久化');
      }
    }
  }

  Future<void> _removeJournal(SharedPreferences prefs, String category) async {
    if (!await prefs.remove(_journalKey(category))) {
      await prefs.reload();
      if (prefs.getString(_journalKey(category)) != null) {
        throw StateError('提醒事务记录未能清理');
      }
    }
  }

  Future<List<String>> _cancelIds(Iterable<int> ids) async {
    final failures = <String>[];
    for (final id in ids.toSet()) {
      try {
        await _plugin.cancel(id);
      } catch (error) {
        failures.add('$id: $error');
      }
    }
    return failures;
  }

  String _journalKey(String category) =>
      '${LocalNotificationService._scheduleJournalPrefix}$category';
  String _activeKey(String category) =>
      '${LocalNotificationService._scheduleActivePrefix}$category';

  bool _isPrivateActiveNotification(ActiveNotification item) {
    // Android plugin v18 omits payload on delivered notifications, but still
    // returns the channel and tag. Only full privacy cleanup may use this
    // fallback for untagged notifications on app-owned channels. Journal
    // recovery requires independent evidence of category ownership.
    return item.tag == null &&
        (NotificationSchedulePolicy.isPrivatePayload(item.payload) ||
            NotificationSchedulePolicy.scheduleCategoryForChannel(
                    item.channelId) !=
                null);
  }
}

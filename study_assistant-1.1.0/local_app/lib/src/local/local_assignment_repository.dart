import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/assignment.dart';
import '../models/course.dart';
import '../models/course_chapter_progress.dart';
import '../models/course_notice.dart';
import '../models/backup_snapshot.dart';
import '../models/personal_workspace.dart';
import '../models/study_notebook.dart';
import '../models/home_filters.dart';
import '../services/reminder_rule_store.dart';
import '../services/background_reminder_gateway.dart';
import '../services/background_check_settings.dart';

/// A journal or course write could not be confirmed against durable storage.
///
/// The preference plugin updates its in-process cache before the platform
/// write completes, so a failed write must be verified with
/// [SharedPreferences.reload] before callers decide that nothing was stored.
class LocalStorageWriteException implements Exception {
  const LocalStorageWriteException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LocalAssignmentRepository {
  LocalAssignmentRepository({
    BackgroundReminderGateway backgroundReminderGateway =
        const BackgroundReminderGateway(),
    String? writeLeaseOwner,
  })  : _backgroundReminderGateway = backgroundReminderGateway,
        _writeOwner = writeLeaseOwner ??
            'repository-${DateTime.now().microsecondsSinceEpoch}-'
                '${Random().nextInt(1 << 31)}';

  final BackgroundReminderGateway _backgroundReminderGateway;
  final String _writeOwner;
  bool crossEngineLockEnabled = false;
  int _identityConflictCount = 0;
  Set<String> _identityConflictSources = {};

  /// Ambiguous identities retained by the most recent successful merge.
  int get identityConflictCount => _identityConflictCount;
  Set<String> get identityConflictSources =>
      Set.unmodifiable(_identityConflictSources);
  static const _key = 'chaoxing_journal_v2';
  static const _personalKey = 'personal_workspace_v1';
  static const _notebookKey = 'notebook_v1';
  static const _homeFiltersKey = 'home_filters_v1';
  static const _noticesKey = 'course_notices_v1';
  static const _chaptersKey = 'course_chapters_v1';
  static const _maxAdditionalRecoveryBackups = 3;
  static const _maxRecoveryValueBytes = 4 * 1024 * 1024;
  static const _recoveryWriteFailedWarning =
      '恢复副本写入失败，恢复副本未保存；原始损坏数据仍保留在本机，已停止写入。请检查本机存储空间，不要清除应用数据。';
  // Old app versions stored account-independent data in three preferences.
  static const _oldItems = 'local_assignments';
  static const _oldSync = 'local_last_sync_at';
  static const _oldHidden = 'local_hidden_completed_assignment_ids';
  static const _ownerKey = 'journal_account_owner';
  static const _switchKey = 'journal_account_switch';
  static const _archivePrefix = 'journal_account_archive_';
  static const _scopedKeys = [
    _key,
    _oldItems,
    _oldSync,
    _oldHidden,
    'course_refs',
    'unfollowed_courses',
    'reminder_offsets_minutes',
    'auto_sync_interval_minutes',
    'background_check_enabled_v1',
    'background_check_interval_minutes_v1',
    'notification_listener_enabled_v1',
    'new_assignment_reminder_enabled_v1',
    'background_check_legacy_migration_v1',
    'background_server_backoff_until_v1',
    'sync_attempt_at',
    'sync_data_at',
    'sync_report_v1',
    'assignment_changes_v1',
    _personalKey,
    _notebookKey,
    _homeFiltersKey,
    _noticesKey,
    _chaptersKey,
    '${_key}_recovery_backup',
    '${_key}_recovery_backups',
    'course_refs_recovery_backup',
    '${_personalKey}_recovery_backup',
    '${_personalKey}_recovery_backups',
    '${_notebookKey}_recovery_backup',
    '${_notebookKey}_recovery_backups',
    '${_noticesKey}_recovery_backup',
    '${_noticesKey}_recovery_backups',
    '${_chaptersKey}_recovery_backup',
    '${_chaptersKey}_recovery_backups',
  ];

  static String _owner(String account) =>
      sha256.convert(utf8.encode(account.trim())).toString();

  Future<HomeFilters> loadHomeFilters() => _serialized(() async {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.get(_homeFiltersKey);
        return HomeFilters.decode(raw is String ? raw : null);
      });

  Future<void> saveHomeFilters(HomeFilters filters, String account) =>
      _serialized(() async {
        final prefs = await SharedPreferences.getInstance();
        _checkOwner(prefs, account);
        try {
          await _require(prefs.setString(_homeFiltersKey, filters.encode()));
        } catch (_) {
          // The plugin updates its cache before the platform write succeeds.
          // Reload so a failed preference cannot reappear on route restoration.
          await prefs.reload();
          rethrow;
        }
      });

  Future<StudyNotebook> loadNotebook() => _serialized(() async {
        final p = await SharedPreferences.getInstance();
        return _readProtected(
          p,
          _notebookKey,
          StudyNotebook.decode,
          StudyNotebook.new,
          '部分个人待办与学期归档无法读取，原始数据已保留备份；空记录仅为临时显示，请勿覆盖原数据。',
        );
      });
  Future<void> saveNotebook(StudyNotebook value, String account) =>
      _serialized(() async {
        final p = await SharedPreferences.getInstance();
        _checkOwner(p, account);
        await _protectExisting(
          p,
          _notebookKey,
          StudyNotebook.decode,
          '部分个人待办与学期归档无法读取，原始数据已保留备份；空记录仅为临时显示，请勿覆盖原数据。',
        );
        final raw = value.encode();
        StudyNotebook.decode(raw);
        await _require(p.setString(_notebookKey, raw));
      });

  Future<PersonalWorkspace> loadPersonalWorkspace() => _serialized(() async {
        final p = await SharedPreferences.getInstance();
        return _readProtected(
          p,
          _personalKey,
          PersonalWorkspace.decode,
          PersonalWorkspace.new,
          '部分个人计划与记录无法读取，原始数据已保留备份；空记录仅为临时显示，请勿覆盖原数据。',
        );
      });
  Future<void> savePersonalWorkspace(PersonalWorkspace value, String account) =>
      _serialized(() async {
        final p = await SharedPreferences.getInstance();
        _checkOwner(p, account);
        await _protectExisting(
          p,
          _personalKey,
          PersonalWorkspace.decode,
          '部分个人计划与记录无法读取，原始数据已保留备份；空记录仅为临时显示，请勿覆盖原数据。',
        );
        final raw = value.encode();
        PersonalWorkspace.decode(raw);
        await _require(p.setString(_personalKey, raw));
      });

  Future<CourseNoticeCollection> loadCourseNotices() => _serialized(() async {
        final p = await SharedPreferences.getInstance();
        return _readProtected(
          p,
          _noticesKey,
          CourseNoticeCollection.decode,
          CourseNoticeCollection.new,
          '部分课程通知缓存无法读取，原始数据已保留备份；空记录仅为临时显示，请重新同步获取。',
        );
      });

  Future<void> saveCourseNotices(
          CourseNoticeCollection value, String account) =>
      _serialized(() async {
        final p = await SharedPreferences.getInstance();
        _checkOwner(p, account);
        await _protectExisting(
          p,
          _noticesKey,
          CourseNoticeCollection.decode,
          '部分课程通知缓存无法读取，原始数据已保留备份；空记录仅为临时显示，请重新同步获取。',
        );
        final raw = value.encode();
        CourseNoticeCollection.decode(raw);
        await _writeVerified(p, _noticesKey, raw, '课程通知保存失败');
      });

  Future<CourseChapterCatalog> loadCourseChapters() => _serialized(() async {
        final p = await SharedPreferences.getInstance();
        return _readProtected(
          p,
          _chaptersKey,
          CourseChapterCatalog.decode,
          CourseChapterCatalog.new,
          '部分章节进度缓存无法读取，原始数据已保留备份；空记录仅为临时显示，请重新手动读取。',
        );
      });

  Future<void> saveCourseChapters(CourseChapterCatalog value, String account) =>
      _serialized(() async {
        final p = await SharedPreferences.getInstance();
        _checkOwner(p, account);
        await _protectExisting(
          p,
          _chaptersKey,
          CourseChapterCatalog.decode,
          '部分章节进度缓存无法读取，原始数据已保留备份；空记录仅为临时显示，请重新手动读取。',
        );
        final raw = value.encode();
        CourseChapterCatalog.decode(raw);
        await _writeVerified(p, _chaptersKey, raw, '章节进度保存失败');
      });

  Future<T> _readProtected<T>(
    SharedPreferences prefs,
    String key,
    T Function(String) decode,
    T Function() fallback,
    String warning,
  ) async {
    final raw = prefs.getString(key);
    if (raw == null) return fallback();
    try {
      return decode(raw);
    } on FormatException {
      await _backupDamagedValue(prefs, key, raw, warning);
      return fallback();
    } on TypeError {
      await _backupDamagedValue(prefs, key, raw, warning);
      return fallback();
    }
  }

  Future<void> _protectExisting(
    SharedPreferences prefs,
    String key,
    Object? Function(String) decode,
    String warning,
  ) async {
    final raw = prefs.getString(key);
    if (raw == null) return;
    try {
      decode(raw);
    } on FormatException {
      await _backupDamagedValue(prefs, key, raw, warning);
    } on TypeError {
      await _backupDamagedValue(prefs, key, raw, warning);
    }
  }

  void _checkOwner(SharedPreferences prefs, String account) {
    if (account.trim().isEmpty ||
        prefs.getString(_ownerKey) != _owner(account) ||
        prefs.containsKey(_switchKey)) {
      throw StateError('当前账号已变化，请重新打开备份页面');
    }
  }

  Future<void> validateBackupOwner(BackupSnapshot snapshot, String account) =>
      _serialized(() async {
        final prefs = await SharedPreferences.getInstance();
        _checkOwner(prefs, account);
        if (snapshot.owner != _owner(account)) throw StateError('此备份不属于当前账号');
      });

  Future<BackupSnapshot> createBackupSnapshot(String account) =>
      _serialized(() async {
        final prefs = await SharedPreferences.getInstance();
        _checkOwner(prefs, account);
        if (recoveryWarning != null) {
          throw StateError('检测到本机数据恢复警告，当前数据不完整，已阻止导出。原始损坏数据仍保留在本机。');
        }
        final state = await _read();
        final backgroundSettings =
            await const BackgroundCheckSettingsStore().loadAndMigrate();
        final snapshot = BackupSnapshot.create(
            owner: _owner(account),
            createdAt: DateTime.now(),
            records: state.byId.values.toList(),
            courseTaskKeys: state.courseTaskKeys,
            hidden: state.hidden.intersection(state.byId.keys.toSet()),
            courses: await _loadCourses(account: account),
            unfollowed:
                (prefs.getStringList('unfollowed_courses') ?? []).toSet(),
            reminderOffsets: await ReminderRuleStore().loadOffsetsMinutes(),
            autoSyncIntervalMinutes: backgroundSettings.enabled
                ? backgroundSettings.intervalMinutes
                : 0,
            notebook: await _readProtected(
              prefs,
              _notebookKey,
              StudyNotebook.decode,
              StudyNotebook.new,
              '部分个人待办与学期归档无法读取，原始数据已保留备份；空记录仅为临时显示，请勿覆盖原数据。',
            ),
            personal: await _readProtected(
              prefs,
              _personalKey,
              PersonalWorkspace.decode,
              PersonalWorkspace.new,
              '部分个人计划与记录无法读取，原始数据已保留备份；空记录仅为临时显示，请勿覆盖原数据。',
            ),
            notices: await _readProtected(
              prefs,
              _noticesKey,
              CourseNoticeCollection.decode,
              CourseNoticeCollection.new,
              '部分课程通知缓存无法读取，原始数据已保留备份；空记录仅为临时显示，请重新同步获取。',
            ),
            chapters: await _readProtected(
              prefs,
              _chaptersKey,
              CourseChapterCatalog.decode,
              CourseChapterCatalog.new,
              '部分章节进度缓存无法读取，原始数据已保留备份；空记录仅为临时显示，请重新手动读取。',
            ));
        if (recoveryWarning != null) {
          throw StateError('检测到本机数据恢复警告，当前数据不完整，已阻止导出。原始损坏数据仍保留在本机。');
        }
        return snapshot;
      });

  /// Restore only absent records/preferences. Imported observations must be
  /// confirmed by a real sync before they can drive submission UI or reminders.
  Future<bool> restoreBackupSnapshot(BackupSnapshot snapshot, String account) =>
      _serialized(() async {
        final prefs = await SharedPreferences.getInstance();
        _checkOwner(prefs, account);
        if (snapshot.owner != _owner(account)) throw StateError('此备份不属于当前账号');
        // Validate again at the trust boundary even for in-memory callers.
        final validated = BackupSnapshot.decode(snapshot.encode());
        final state = await _read();
        for (final a in validated.records) {
          if (state.byId.containsKey(a.id)) continue;
          state.byId[a.id] = Assignment(
              id: a.id,
              source: a.source,
              exam: a.exam,
              activityType: a.activityType,
              availability: a.availability,
              courseName: a.courseName,
              title: a.title,
              deadlineAt: a.deadlineAt,
              requirementsText: a.requirementsText,
              status: 'unknown',
              // A backup's device clock is not a new server observation. A
              // future source clock must never outrank the next real sync.
              lastSyncedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
              deadlineTrusted: false,
              deadlineRawText: '备份记录，待同步确认',
              publishedAt: a.publishedAt,
              availableFromAt: a.availableFromAt,
              availableFromText: a.availableFromText);
          final taskKey = validated.courseTaskKeys[a.id];
          if (taskKey != null) state.courseTaskKeys[a.id] = taskKey;
          if (validated.hidden.contains(a.id)) state.hidden.add(a.id);
        }
        final courses = {
          for (final c in await _loadCourses(account: account)) c.key: c
        };
        for (final c in validated.courses) {
          courses.putIfAbsent(c.key, () => c);
        }
        final before = <String, dynamic>{
          'owner': prefs.getString(_ownerKey),
          'values': {
            for (final key in _scopedKeys)
              if (prefs.containsKey(key)) key: prefs.get(key)
          }
        };
        // The same durable checkpoint as account activation. On restart activation
        // repairs an interrupted restore before exposing any records.
        await _require(prefs.setString(_switchKey, jsonEncode(before)));
        try {
          await _save(state);
          await _require(prefs.setString('course_refs',
              jsonEncode(courses.values.map((c) => c.toJson()).toList())));
          if (!prefs.containsKey('unfollowed_courses')) {
            await _require(prefs.setStringList(
                'unfollowed_courses', validated.unfollowed.toList()));
          }
          if (!prefs.containsKey('reminder_offsets_minutes')) {
            await _require(prefs.setStringList('reminder_offsets_minutes',
                validated.reminderOffsets.map((v) => '$v').toList()));
          }
          // Sync interval is global: a historical account backup must not alter it.
          final local = await _readProtected(
            prefs,
            _personalKey,
            PersonalWorkspace.decode,
            PersonalWorkspace.new,
            '部分个人计划与记录无法读取，原始数据已保留备份；空记录仅为临时显示，请勿覆盖原数据。',
          );
          final imported = validated.personal;
          final keys =
              local.plans.map((p) => '${p.day}:${p.assignmentId}').toSet();
          final merged = PersonalWorkspace(
              work: {
                ...imported.work,
                ...local.work
              },
              plans: [
                ...local.plans,
                ...imported.plans
                    .where((p) => !keys.contains('${p.day}:${p.assignmentId}'))
              ],
              summaryEnabled: local.summaryEnabled,
              summaryHour: local.summaryHour,
              summaryMinute: local.summaryMinute);
          final encoded = merged.encode();
          PersonalWorkspace.decode(encoded);
          await _require(prefs.setString(_personalKey, encoded));
          final notebook = (await _readProtected(
            prefs,
            _notebookKey,
            StudyNotebook.decode,
            StudyNotebook.new,
            '部分个人待办与学期归档无法读取，原始数据已保留备份；空记录仅为临时显示，请勿覆盖原数据。',
          ))
              .mergeMissing(validated.notebook);
          final notebookRaw = notebook.encode();
          StudyNotebook.decode(notebookRaw);
          await _require(prefs.setString(_notebookKey, notebookRaw));
          final validEntryIds = {for (final e in notebook.entries) e.id};
          if (validated.notices.items.isNotEmpty) {
            final notices = (await _readProtected(
              prefs,
              _noticesKey,
              CourseNoticeCollection.decode,
              CourseNoticeCollection.new,
              '部分课程通知缓存无法读取，原始数据已保留备份；空记录仅为临时显示，请重新同步获取。',
            ))
                .mergeImported(validated.notices, validEntryIds: validEntryIds);
            final noticesRaw = notices.encode();
            CourseNoticeCollection.decode(noticesRaw);
            await _require(prefs.setString(_noticesKey, noticesRaw));
          }
          if (validated.chapters.byCourse.isNotEmpty) {
            final chapters = (await _readProtected(
              prefs,
              _chaptersKey,
              CourseChapterCatalog.decode,
              CourseChapterCatalog.new,
              '部分章节进度缓存无法读取，原始数据已保留备份；空记录仅为临时显示，请重新手动读取。',
            ))
                .mergeImported(validated.chapters,
                    validEntryIds: validEntryIds);
            final chaptersRaw = chapters.encode();
            CourseChapterCatalog.decode(chaptersRaw);
            await _require(prefs.setString(_chaptersKey, chaptersRaw));
          }
          await _require(prefs.remove(_switchKey));
          return true;
        } catch (_) {
          await _restoreScope(prefs, before);
          await _require(prefs.remove(_switchKey));
          rethrow;
        }
      });

  // Archive before switching. A durable checkpoint restores the old active
  // scope if the process stops between individual SharedPreferences writes.
  Future<void> activateAccount(String account, {String? previousAccount}) =>
      _serialized(() async {
        recoveryWarning = null;
        final prefs = await SharedPreferences.getInstance();
        final pending = prefs.getString(_switchKey);
        if (pending != null) {
          await _restoreScope(
              prefs, jsonDecode(pending) as Map<String, dynamic>);
          await _require(prefs.remove(_switchKey));
        }
        final target = _owner(account);
        final current = prefs.getString(_ownerKey);
        if (current == target) return;
        if (current == null && previousAccount?.trim() == account.trim()) {
          await _require(prefs.setString(_ownerKey, target));
          return;
        }
        final before = <String, dynamic>{
          'owner': current ??
              (previousAccount == null ? null : _owner(previousAccount)),
          'values': {
            for (final key in _scopedKeys)
              if (prefs.containsKey(key)) key: prefs.get(key)
          },
        };
        final archived = prefs.getString('$_archivePrefix$target');
        final after = archived == null
            ? <String, dynamic>{'owner': target, 'values': <String, dynamic>{}}
            : jsonDecode(archived) as Map<String, dynamic>;
        if (after['owner'] != target) throw StateError('账号本机记录归属不一致');
        final checkpoint = jsonEncode(before);
        await _require(prefs.setString(
            '$_archivePrefix${before['owner'] ?? 'unclaimed'}', checkpoint));
        await _require(prefs.setString(_switchKey, checkpoint));
        try {
          await _restoreScope(prefs, after);
          await _require(prefs.remove(_switchKey));
        } catch (_) {
          // Keep the checkpoint if rollback itself fails; next activation will
          // retry it before exposing or merging any active records.
          await _restoreScope(prefs, before);
          await _require(prefs.remove(_switchKey));
          rethrow;
        }
      });

  static Future<void> _require(Future<bool> write) async {
    if (!await write) throw StateError('未能保存账号本机记录，原记录已保留');
  }

  /// Writes [value] and confirms the durable value after a false return or an
  /// exception. A failure may still have reached the platform, so treating the
  /// first error as "nothing was written" would either lose a durable value or
  /// leave the in-process cache showing data that will vanish on restart.
  static Future<void> _writeVerified(
    SharedPreferences prefs,
    String key,
    String value,
    String failureMessage,
  ) async {
    Object? writeError;
    try {
      if (await prefs.setString(key, value)) return;
      writeError = '原生写入未确认';
    } catch (error) {
      writeError = error;
    }
    try {
      await prefs.reload();
    } catch (reloadError) {
      throw LocalStorageWriteException(
          '$failureMessage，写入结果未确认；重新读取也失败：$reloadError');
    }
    String? durable;
    try {
      durable = prefs.getString(key);
    } catch (_) {
      // A different stored type cannot match a string write; treat it as not
      // written instead of leaking a cast error from the verification step.
      durable = null;
    }
    if (durable == value) {
      // The platform reported an error, but the value is durable. Reporting a
      // rollback here would contradict the data the next read will return.
      return;
    }
    throw LocalStorageWriteException('$failureMessage，原记录已保留：$writeError');
  }

  static Future<void> _restoreScope(
      SharedPreferences prefs, Map<String, dynamic> snapshot) async {
    final values = snapshot['values'] as Map<String, dynamic>;
    for (final key in _scopedKeys) {
      final value = values[key];
      if (value == null) {
        await _require(prefs.remove(key));
      } else if (value is String) {
        await _require(prefs.setString(key, value));
      } else if (value is List) {
        await _require(prefs.setStringList(key, value.cast<String>()));
      } else if (value is int) {
        await _require(prefs.setInt(key, value));
      } else if (value is bool) {
        await _require(prefs.setBool(key, value));
      } else {
        throw StateError('账号本机记录格式无法识别');
      }
    }
    final owner = snapshot['owner'] as String?;
    await _require(owner == null
        ? prefs.remove(_ownerKey)
        : prefs.setString(_ownerKey, owner));
  }

  final Map<String, String> _recoveryStatusByKey = {};
  String? get recoveryWarning => _recoveryStatusByKey.isEmpty
      ? null
      : _recoveryStatusByKey.values.join('；');
  set recoveryWarning(String? value) {
    _recoveryStatusByKey.clear();
    if (value != null && value.isNotEmpty) {
      _recoveryStatusByKey['_external'] = value;
    }
  }

  Future<List<CourseRef>> loadCourses({String? account}) =>
      _serialized(() => _loadCourses(account: account));

  Future<List<CourseRef>> _loadCourses({String? account}) async {
    final p = await SharedPreferences.getInstance();
    if (account != null) {
      _checkOwner(p, account);
    } else if (p.containsKey(_switchKey)) {
      throw StateError('账号本机记录切换未完成，请重新登录后恢复');
    }
    final raw = p.get('course_refs');
    final valid = <CourseRef>[];
    var damaged = false;
    try {
      for (final item in jsonDecode(raw as String? ?? '[]') as List) {
        try {
          valid.add(CourseRef.fromJson(item as Map<String, dynamic>));
        } catch (_) {
          damaged = true;
        }
      }
    } catch (_) {
      damaged = true;
    }
    if (damaged) {
      if (!p.containsKey('course_refs_recovery_backup')) {
        await _require(p.setString('course_refs_recovery_backup',
            raw is String ? raw : jsonEncode(raw)));
      }
      _setRecoveryStatus(
        'course_refs',
        '部分课程资料无法读取，原始资料已备份；已保留可读取的作业，请重新同步。',
      );
    }
    return valid;
  }

  Future<void> saveCourses(List<CourseRef> courses, {String? account}) =>
      _serialized(() async {
        final p = await SharedPreferences.getInstance();
        if (account != null) {
          _checkOwner(p, account);
        } else if (p.containsKey(_switchKey)) {
          throw StateError('账号本机记录切换未完成，请重新登录后恢复');
        }
        await _writeVerified(
          p,
          'course_refs',
          jsonEncode(courses.map((c) => c.toJson()).toList()),
          '课程保存失败',
        );
      });

  Future<List<Assignment>> loadHiddenAssignments() => _serialized(() async {
        final state = await _read();
        return state.byId.values
            .where((a) => state.hidden.contains(a.id))
            .toList()
          ..sort(Assignment.compareByDeadline);
      });

  Future<void> _tail = Future.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) async {
      if (!crossEngineLockEnabled) return action();
      final acquired =
          await _backgroundReminderGateway.acquireWriteLease(_writeOwner);
      if (!acquired) {
        throw StateError('本机数据正在被另一后台任务更新，请稍后重试');
      }
      Object? primaryError;
      StackTrace? primaryStack;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        return await action();
      } catch (error, stack) {
        primaryError = error;
        primaryStack = stack;
        rethrow;
      } finally {
        try {
          await _backgroundReminderGateway.releaseWriteLease(_writeOwner);
        } catch (releaseError, releaseStack) {
          // Never let a release failure hide the real persistence error; when
          // the action succeeded, the unconfirmed release is the only failure.
          if (primaryError == null) {
            Error.throwWithStackTrace(
              StateError('本机数据已写入，但写租约释放未确认：$releaseError'),
              releaseStack,
            );
          }
          Error.throwWithStackTrace(
            StateError('$primaryError；写租约释放未确认：$releaseError'),
            primaryStack!,
          );
        }
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<List<Assignment>> loadJournal() =>
      _serialized(() async => (await _read()).journal);

  Future<List<Assignment>> loadAssignments() =>
      _serialized(() async => (await _read()).pending);

  Future<DateTime?> lastSyncAt() =>
      _serialized(() async => (await _read()).lastSync);

  Future<List<Assignment>> mergeAndSave(List<Assignment> incoming,
          {bool completeSync = true, Future<bool> Function()? canCommit}) =>
      _serialized(() async {
        if (canCommit != null && !await canCommit()) {
          throw StateError('账号会话已变化，旧同步结果已拒绝提交');
        }
        final state = await _read();
        state.merge(incoming);
        if (completeSync && state.identityConflictCount == 0) {
          state.lastSync = DateTime.now();
        }
        await _save(state);
        _identityConflictCount = state.identityConflictCount;
        _identityConflictSources = {...state.identityConflictSources};
        return state.pending;
      });

  Future<List<Assignment>> updateCompletion(String id, bool hidden) =>
      _serialized(() async {
        final state = await _read();
        if (hidden) {
          state.hidden.add(id);
        } else {
          state.hidden.remove(id);
        }
        await _save(state);
        return state.pending;
      });

  /// Applies one hide/restore operation to every source in a coursework group.
  /// The optional commit gate runs inside the serialized write transaction so
  /// an account/session change cannot partially hide a stale group.
  Future<List<Assignment>> updateCompletionMany(
    Iterable<String> ids,
    bool hidden, {
    Future<bool> Function()? canCommit,
  }) =>
      _serialized(() async {
        if (canCommit != null && !await canCommit()) {
          throw StateError('账号会话已变化，旧隐藏结果已拒绝提交');
        }
        final state = await _read();
        final existing = ids.where(state.byId.containsKey).toSet();
        if (hidden) {
          state.hidden.addAll(existing);
        } else {
          state.hidden.removeAll(existing);
        }
        await _save(state);
        return state.pending;
      });

  static List<Assignment> mergeAssignments(
      List<Assignment> existing, List<Assignment> incoming,
      {Set<String> hiddenCompletedIds = const {},
      bool includeCompleted = false}) {
    final state = _Journal(existing, {...hiddenCompletedIds}, null);
    state.merge(incoming);
    return includeCompleted ? state.journal : state.pending;
  }

  Future<void> clear() => _serialized(() async {
        final prefs = await SharedPreferences.getInstance();
        for (final key in {
          'sync_attempt_at',
          'sync_data_at',
          'course_refs',
          'unfollowed_courses',
          _oldItems,
          _oldHidden,
          _oldSync,
          _key,
          '${_key}_recovery_backup',
          '${_key}_recovery_backups',
          ..._scopedKeys,
          _ownerKey,
          _switchKey,
          ...prefs.getKeys().where((key) => key.startsWith(_archivePrefix)),
        }) {
          await _require(prefs.remove(key));
        }
      });

  Future<_Journal> _read() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_switchKey)) {
      throw StateError('账号本机记录切换未完成，请重新登录后恢复');
    }
    final encoded = prefs.getString(_key);
    if (encoded != null) {
      try {
        final decoded = jsonDecode(encoded) as Map<String, dynamic>;
        final version = decoded['schemaVersion'];
        if (version != null && (version is! int || !{1, 2}.contains(version))) {
          throw StateError('本机记录来自较新版本，请升级应用后重试');
        }
        final records = decoded['records'] as List;
        final courseTaskKeys = <String, String>{};
        final valid = await _readRecords(records, prefs, encoded,
            courseTaskKeys: courseTaskKeys);
        return _Journal(valid, Set<String>.from(decoded['hidden'] as List),
            DateTime.tryParse(decoded['lastSync'] as String? ?? '')?.toLocal(),
            courseTaskKeys: courseTaskKeys);
      } on FormatException {
        await _backupDamaged(prefs, encoded);
        return _Journal([], {}, null);
      } on TypeError {
        await _backupDamaged(prefs, encoded);
        return _Journal([], {}, null);
      }
    }
    final rawLegacy = prefs.getString(_oldItems) ?? '[]';
    List<Assignment> items;
    try {
      items =
          await _readRecords(jsonDecode(rawLegacy) as List, prefs, rawLegacy);
    } on FormatException {
      await _backupDamaged(prefs, rawLegacy);
      items = [];
    } on TypeError {
      await _backupDamaged(prefs, rawLegacy);
      items = [];
    }
    // This was the other provider's unique prefix, including in old hidden IDs.
    bool obsolete(String id) => id.startsWith('snzl:');
    final hidden = (prefs.getStringList(_oldHidden) ?? [])
        .where((id) => !obsolete(id))
        .toSet();
    final retained = items.where((item) => !obsolete(item.id)).toList();
    for (final item in retained) {
      // v1 also copied server-completed records into its manual hide list.
      if (item.status == 'completed' && item.completedAt != null) {
        hidden.add(item.id);
      } else if (item.isCompleted) {
        hidden.remove(item.id);
      }
    }
    final foreignOnly =
        retained.isEmpty && items.any((item) => obsolete(item.id));
    final state = _Journal(
        retained,
        hidden,
        foreignOnly
            ? null
            : DateTime.tryParse(prefs.getString(_oldSync) ?? ''));
    await _save(state);
    for (final key in [_oldItems, _oldHidden, _oldSync]) {
      await prefs.remove(key);
    }
    return state;
  }

  Future<List<Assignment>> _readRecords(
      List records, SharedPreferences prefs, String raw,
      {Map<String, String>? courseTaskKeys}) async {
    final valid = <Assignment>[];
    for (final record in records) {
      try {
        final value = record as Map<String, dynamic>;
        final assignment = Assignment.fromJson(value);
        final key = value['courseTaskKey'];
        if (key != null) {
          if (BackupSnapshot.isValidCourseTaskKey(assignment, key)) {
            courseTaskKeys?[assignment.id] = key as String;
          } else {
            await _backupDamaged(prefs, raw);
          }
        }
        valid.add(assignment);
      } on FormatException {
        await _backupDamaged(prefs, raw);
      } on TypeError {
        await _backupDamaged(prefs, raw);
      }
    }
    return valid;
  }

  Future<void> _backupDamaged(SharedPreferences prefs, String raw) async {
    await _backupDamagedValue(
      prefs,
      _key,
      raw,
      '部分本机记录无法读取，原始数据已保留备份；请重新同步作业。',
    );
  }

  Future<void> _backupDamagedValue(
    SharedPreferences prefs,
    String dataKey,
    String raw,
    String warning,
  ) async {
    if (utf8.encode(raw).length > _maxRecoveryValueBytes) {
      final message =
          '损坏数据超过恢复副本容量上限（4 MiB），恢复副本未保存；原始损坏数据仍保留在本机，已停止写入。请勿清除应用数据。';
      _setRecoveryStatus(dataKey, message);
      throw StateError(message);
    }
    final key = '${dataKey}_recovery_backup';
    if (!prefs.containsKey(key) && !await prefs.setString(key, raw)) {
      _setRecoveryStatus(dataKey, _recoveryWriteFailedWarning);
      await prefs.reload();
      throw StateError(_recoveryWriteFailedWarning);
    }
    if (prefs.getString(key) != raw) {
      final additionalKey = '${dataKey}_recovery_backups';
      final additional = prefs.getStringList(additionalKey) ?? [];
      if (!additional.contains(raw)) {
        if (additional.length >= _maxAdditionalRecoveryBackups) {
          final message =
              '恢复副本已达上限（3 个），新恢复副本未保存；原始损坏数据仍保留在本机，旧恢复副本未删除，已停止写入。请勿清除应用数据。';
          _setRecoveryStatus(dataKey, message);
          throw StateError(message);
        }
        if (!await prefs.setStringList(additionalKey, [...additional, raw])) {
          final message =
              '历史恢复副本写入失败，新恢复副本未保存；原始损坏数据仍保留在本机，已停止写入。请检查本机存储空间，不要清除应用数据。';
          _setRecoveryStatus(dataKey, message);
          await prefs.reload();
          throw StateError(message);
        }
      }
    }
    _setRecoveryStatus(dataKey, warning);
  }

  void _setRecoveryStatus(String dataKey, String warning) {
    _recoveryStatusByKey[dataKey] = warning;
  }

  Future<void> _save(_Journal state) async {
    final prefs = await SharedPreferences.getInstance();
    await _writeVerified(
      prefs,
      _key,
      jsonEncode(state.toJson()),
      '未能保存本机作业记录',
    );
  }
}

class _Journal {
  _Journal(List<Assignment> records, this.hidden, this.lastSync,
      {Map<String, String> courseTaskKeys = const {}})
      : byId = {
          // The UI reads the full journal, so migrate legacy completion labels
          // into status instead of filtering them only from the pending getter.
          for (final a in records)
            a.id:
                _oldCompletedPeerReview(a) ? a.copyWith(status: 'submitted') : a
        },
        courseTaskKeys = {
          ...courseTaskKeys,
          for (final a in records)
            if (a.source == AssignmentSource.classroomActivity &&
                a.courseTaskKey != null)
              a.id: a.courseTaskKey!,
        };
  final Map<String, Assignment> byId;
  final Map<String, String> courseTaskKeys;
  final Set<String> hidden;
  DateTime? lastSync;
  int identityConflictCount = 0;
  final identityConflictSources = <String>{};

  Map<String, dynamic> toJson() => {
        'schemaVersion': 2,
        'records': byId.values
            .map((a) => {
                  ...a.toJson(),
                  if (courseTaskKeys[a.id] != null)
                    'courseTaskKey': courseTaskKeys[a.id],
                })
            .toList(),
        'hidden': hidden.toList()..sort(),
        'lastSync': lastSync?.toUtc().toIso8601String(),
      };
  List<Assignment> get journal =>
      byId.values.where((a) => !hidden.contains(a.id)).toList()
        ..sort(Assignment.compareByDeadline);
  List<Assignment> get pending => journal
      .where((a) => !a.isCompleted && !_oldCompletedPeerReview(a))
      .toList();

  // Only old parsed peer-review rows used a combined label in place of status.
  static bool _oldCompletedPeerReview(Assignment a) =>
      !_isTypedClassroomTask(a) &&
      a.status == 'pending' &&
      RegExp(r'^互评作业\s+(已互评|已完成|已提交|已评价|评价完成|互评完成)$')
          .hasMatch(a.requirementsText.trim());

  static bool _isTypedClassroomTask(Assignment a) =>
      a.source == AssignmentSource.classroomActivity &&
      const {35, 42, 77}.contains(a.activityType);

  static String? _workKey(Assignment a) {
    // A classroom task may carry a work URL, but activeId is not workId.
    if (a.source == AssignmentSource.classroomActivity &&
        a.activityType != null) {
      return null;
    }
    if (a.id.startsWith('cx:work:')) return a.id;
    final uri = Uri.tryParse(a.submitUrl ?? '');
    if (uri == null || !uri.host.endsWith('.chaoxing.com')) return null;
    final q = uri.queryParameters.map((k, v) => MapEntry(k.toLowerCase(), v));
    final course = q['courseid'],
        clazz = q['classid'] ?? q['clazzid'] ?? q['jclassid'];
    final work = q['workid'] ?? q['taskrefid'];
    if ([course, clazz, work].any((v) => v == null || v.isEmpty)) return null;
    return 'cx:work:$course:$clazz:$work';
  }

  static String? _activityKey(Assignment a) {
    if (a.source == AssignmentSource.classroomActivity &&
        a.courseTaskKey != null) {
      return a.courseTaskKey;
    }
    final uri = Uri.tryParse(a.submitUrl ?? '');
    if (uri == null || !uri.host.endsWith('.chaoxing.com')) return null;
    final q = uri.queryParameters.map((k, v) => MapEntry(k.toLowerCase(), v));
    final course = q['courseid'],
        clazz = q['classid'] ?? q['clazzid'] ?? q['jclassid'];
    final active = q['activeid'];
    if ([course, clazz, active].any((v) => v == null || v.isEmpty)) return null;
    return 'cx:${a.id.startsWith('cx:exam:') ? 'exam' : 'activity'}:$course:$clazz:$active';
  }

  static String? _classroomTaskKey(Assignment a) {
    if (a.activityType != null &&
        !const {35, 42, 77}.contains(a.activityType)) {
      return null;
    }
    if (a.source == AssignmentSource.legacyUnknown) {
      // Older rows may predate source classification. Only a model-validated
      // activity identity can upgrade them, never a title or work-ID suffix.
      return a
          .copyWith(source: AssignmentSource.classroomActivity)
          .courseTaskKey;
    }
    return a.source == AssignmentSource.classroomActivity
        ? _activityKey(a)
        : null;
  }

  void _mergeClassroomTask(Assignment item) {
    final key = item.courseTaskKey!;
    item = item.copyWith(persistedCourseTaskKey: key);
    final matches = byId.values
        .where((a) => (_classroomTaskKey(a) ?? courseTaskKeys[a.id]) == key)
        .toList();
    final incompatible = matches.any(
        (a) => a.activityType != null && a.activityType != item.activityType);
    Assignment? prior;
    if (matches.length > 1 || incompatible) {
      // Never choose one alias and delete the others. Their IDs may each own
      // personal notes, attachment references and daily-plan entries.
      identityConflictCount++;
      identityConflictSources.add(item.reminderSourceKey!);
      for (final alias in matches) {
        if (alias.id == item.id) continue;
        byId[alias.id] = alias.copyWith(
            status: 'unknown',
            availability: AssignmentAvailability.unknown,
            clearCompletedAt: true);
      }
      prior = byId[item.id];
      if (prior != null &&
          ((_classroomTaskKey(prior) ?? courseTaskKeys[prior.id]) != key ||
              (prior.activityType != null &&
                  prior.activityType != item.activityType))) {
        return;
      }
    } else if (matches.isNotEmpty) {
      prior = matches.single;
    } else if (byId.containsKey(item.id)) {
      // A reused storage ID with another business identity is also ambiguous.
      identityConflictCount++;
      identityConflictSources.add(item.reminderSourceKey!);
      return;
    }
    if (prior != null) {
      if (item.lastSyncedAt.isBefore(prior.lastSyncedAt)) return;
      item = item.copyWith(
          id: prior.id,
          submitUrl: item.submitUrl ?? prior.submitUrl,
          aiPracticePublishUuid: item.submitUrl == null
              ? prior.aiPracticePublishUuid
              : item.aiPracticePublishUuid);
      // An opaque legacy ID depends on its verified activity URL. A work URL
      // or a URL for another activity must not change that retained identity.
      if (item.submitUrl != null && item.linkedActivityKey != key) {
        item = item.copyWith(
            submitUrl: prior.submitUrl,
            aiPracticePublishUuid: prior.aiPracticePublishUuid,
            clearAiPracticePublishUuid: prior.aiPracticePublishUuid == null,
            clearSubmitUrl: prior.submitUrl == null);
      }
      item = _preserveFailedDeadline(item, prior);
    }
    // Personal activity evidence can reopen a task. Unknown is also the
    // current observation, so a previous completedAt must not imply completion.
    if (!item.isCompleted) item = item.copyWith(clearCompletedAt: true);
    byId[item.id] = item;
    courseTaskKeys[item.id] = key;
  }

  static Assignment _preserveFailedDeadline(Assignment item, Assignment prior) {
    var next = item;
    if (next.publishedAt == null && prior.publishedAt != null) {
      next = next.copyWith(publishedAt: prior.publishedAt);
    }
    if (next.availableFromAt == null && prior.availableFromAt != null) {
      next = next.copyWith(availableFromAt: prior.availableFromAt);
    }
    if (next.availableFromText == null && prior.availableFromText != null) {
      next = next.copyWith(availableFromText: prior.availableFromText);
    }
    // Completed work sometimes stops exposing its deadline in a refreshed
    // list. That absence is not evidence that the previous time was wrong.
    final preserveCompleted = next.isCompleted &&
        !next.deadlineTrusted &&
        prior.deadlineTrusted &&
        prior.deadlineAt != null;
    if (!next.deadlineReadFailed && !preserveCompleted) return next;
    return next.copyWith(
        deadlineAt: prior.deadlineAt,
        deadlineTrusted: prior.deadlineTrusted,
        deadlineRawText: prior.deadlineRawText,
        clearDeadlineRawText: prior.deadlineRawText == null,
        clearDeadlineAt: prior.deadlineAt == null);
  }

  void merge(List<Assignment> incoming) {
    final oldIds = <String, List<String>>{};
    for (final a in byId.values) {
      if (_isTypedClassroomTask(a)) continue;
      for (final key in {_workKey(a), _activityKey(a)}) {
        if (key != null) (oldIds[key] ??= []).add(a.id);
      }
    }
    for (var item in incoming) {
      if (item.hasExamIdentity) {
        final prior = byId[item.id];
        if (prior == null || !item.lastSyncedAt.isBefore(prior.lastSyncedAt)) {
          if (prior?.hasExamIdentity == true) {
            final info = item.exam!.retainingHistoricalTimes(prior!.exam!);
            item = item.copyWith(
                exam: info,
                deadlineAt: info.endAt,
                deadlineTrusted: info.endTrusted,
                clearDeadlineAt: info.endAt == null);
          }
          byId[item.id] =
              item.isCompleted ? item : item.copyWith(clearCompletedAt: true);
        }
        continue;
      }
      if (item.isSupportedClassroomTask) {
        _mergeClassroomTask(item);
        continue;
      }
      // Generic activity observations cannot replace typed personal evidence,
      // even when an earlier upgrade retained an opaque journal ID.
      final classroomKey = _classroomTaskKey(item);
      if (classroomKey != null &&
          byId.values.any((a) =>
              _isTypedClassroomTask(a) &&
              (_classroomTaskKey(a) ?? courseTaskKeys[a.id]) == classroomKey)) {
        continue;
      }
      final key = _workKey(item) ?? _activityKey(item) ?? item.id;
      var prior = byId[key];
      if (prior != null && _isTypedClassroomTask(prior)) continue;
      final aliases = <String>{
        ...oldIds.remove(key) ?? const <String>[],
        ...oldIds.remove(_activityKey(item)) ?? const <String>[]
      }..removeWhere(
          (id) => byId[id] != null && _isTypedClassroomTask(byId[id]!));
      final candidates = {if (prior != null) key, ...aliases};
      if (candidates.length > 1) {
        identityConflictCount++;
        aliases.clear();
      }
      for (final alias in aliases) {
        if (alias == key) continue;
        final old = byId.remove(alias);
        courseTaskKeys.remove(alias);
        prior ??= old;
        if (hidden.remove(alias)) hidden.add(key);
      }
      if (item.id != key) item = item.copyWith(id: key);
      if (prior != null) {
        if (item.lastSyncedAt.isBefore(prior.lastSyncedAt)) {
          byId[key] = prior.copyWith(id: key);
          continue;
        }
        item = _preserveFailedDeadline(item, prior);
        // An ambiguous response cannot undo a verified submission. Reopening
        // requires the student's explicit returned / redo state.
        if (prior.isCompleted &&
            !item.isCompleted &&
            item.status != 'returned') {
          item = item.copyWith(
              status: prior.status, completedAt: prior.completedAt);
        }
      }
      if (_oldCompletedPeerReview(item)) {
        item = item.copyWith(status: 'submitted');
      }
      byId[key] = item;
    }
  }
}

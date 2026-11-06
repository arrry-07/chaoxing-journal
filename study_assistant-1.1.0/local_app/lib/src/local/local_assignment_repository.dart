import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/assignment.dart';
import '../models/course.dart';
import '../models/backup_snapshot.dart';
import '../models/personal_workspace.dart';
import '../models/study_notebook.dart';
import '../services/reminder_rule_store.dart';

class LocalAssignmentRepository {
  static const _key = 'chaoxing_journal_v2';
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
    'sync_attempt_at',
    'sync_data_at',
    'sync_report_v1',
    'assignment_changes_v1',
    'personal_workspace_v1',
    'notebook_v1',
    '${_key}_recovery_backup',
    '${_key}_recovery_backups',
    'course_refs_recovery_backup',
  ];

  static String _owner(String account) =>
      sha256.convert(utf8.encode(account.trim())).toString();

  Future<StudyNotebook> loadNotebook() => _serialized(() async {
        final p = await SharedPreferences.getInstance();
        final raw = p.getString('notebook_v1');
        return raw == null ? StudyNotebook() : StudyNotebook.decode(raw);
      });
  Future<void> saveNotebook(StudyNotebook value, String account) =>
      _serialized(() async {
        final p = await SharedPreferences.getInstance();
        _checkOwner(p, account);
        final raw = value.encode();
        StudyNotebook.decode(raw);
        await _require(p.setString('notebook_v1', raw));
      });

  Future<PersonalWorkspace> loadPersonalWorkspace() => _serialized(() async {
        final p = await SharedPreferences.getInstance();
        final raw = p.getString('personal_workspace_v1');
        return raw == null
            ? PersonalWorkspace()
            : PersonalWorkspace.decode(raw);
      });
  Future<void> savePersonalWorkspace(PersonalWorkspace value, String account) =>
      _serialized(() async {
        final p = await SharedPreferences.getInstance();
        _checkOwner(p, account);
        final raw = value.encode();
        PersonalWorkspace.decode(raw);
        await _require(p.setString('personal_workspace_v1', raw));
      });

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
        final state = await _read();
        return BackupSnapshot.create(
            owner: _owner(account),
            createdAt: DateTime.now(),
            records: state.byId.values.toList(),
            hidden: state.hidden.intersection(state.byId.keys.toSet()),
            courses: await loadCourses(),
            unfollowed:
                (prefs.getStringList('unfollowed_courses') ?? []).toSet(),
            reminderOffsets: await ReminderRuleStore().loadOffsetsMinutes(),
            autoSyncIntervalMinutes:
                prefs.getInt('auto_sync_interval_minutes') ?? 30,
            notebook: prefs.getString('notebook_v1') == null
                ? StudyNotebook()
                : StudyNotebook.decode(prefs.getString('notebook_v1')!),
            personal: prefs.getString('personal_workspace_v1') == null
                ? PersonalWorkspace()
                : PersonalWorkspace.decode(
                    prefs.getString('personal_workspace_v1')!));
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
              courseName: a.courseName,
              title: a.title,
              deadlineAt: a.deadlineAt,
              requirementsText: a.requirementsText,
              status: 'unknown',
              // A backup's device clock is not a new server observation. A
              // future source clock must never outrank the next real sync.
              lastSyncedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
              deadlineTrusted: false,
              deadlineRawText: '备份记录，待同步确认');
          if (validated.hidden.contains(a.id)) state.hidden.add(a.id);
        }
        final courses = {for (final c in await loadCourses()) c.key: c};
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
          final rawPersonal = prefs.getString('personal_workspace_v1');
          final local = rawPersonal == null
              ? PersonalWorkspace()
              : PersonalWorkspace.decode(rawPersonal);
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
          await _require(prefs.setString('personal_workspace_v1', encoded));
          final rawNotebook = prefs.getString('notebook_v1');
          final notebook = (rawNotebook == null
                  ? StudyNotebook()
                  : StudyNotebook.decode(rawNotebook))
              .mergeMissing(validated.notebook);
          final notebookRaw = notebook.encode();
          StudyNotebook.decode(notebookRaw);
          await _require(prefs.setString('notebook_v1', notebookRaw));
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
      } else {
        throw StateError('账号本机记录格式无法识别');
      }
    }
    final owner = snapshot['owner'] as String?;
    await _require(owner == null
        ? prefs.remove(_ownerKey)
        : prefs.setString(_ownerKey, owner));
  }

  String? recoveryWarning;
  Future<List<CourseRef>> loadCourses() async {
    final p = await SharedPreferences.getInstance();
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
      recoveryWarning = '部分课程资料无法读取，原始资料已备份；已保留可读取的作业，请重新同步。';
    }
    return valid;
  }

  Future<void> saveCourses(List<CourseRef> courses) async {
    final p = await SharedPreferences.getInstance();
    if (!await p.setString(
        'course_refs', jsonEncode(courses.map((c) => c.toJson()).toList()))) {
      throw StateError('课程保存失败');
    }
  }

  Future<List<Assignment>> loadHiddenAssignments() => _serialized(() async {
        final state = await _read();
        return state.byId.values
            .where((a) => state.hidden.contains(a.id))
            .toList()
          ..sort(Assignment.compareByDeadline);
      });

  Future<void> _tail = Future.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
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
          {bool completeSync = true}) =>
      _serialized(() async {
        final state = await _read();
        state.merge(incoming);
        if (completeSync) state.lastSync = DateTime.now();
        await _save(state);
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

  static List<Assignment> mergeAssignments(
      List<Assignment> existing, List<Assignment> incoming,
      {Set<String> hiddenCompletedIds = const {}}) {
    final state = _Journal(existing, {...hiddenCompletedIds}, null);
    state.merge(incoming);
    return state.pending;
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
        if (decoded['schemaVersion'] != null && decoded['schemaVersion'] != 1) {
          throw StateError('本机记录来自较新版本，请升级应用后重试');
        }
        final records = decoded['records'] as List;
        final valid = await _readRecords(records, prefs, encoded);
        return _Journal(valid, Set<String>.from(decoded['hidden'] as List),
            DateTime.tryParse(decoded['lastSync'] as String? ?? '')?.toLocal());
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
      List records, SharedPreferences prefs, String raw) async {
    final valid = <Assignment>[];
    for (final record in records) {
      try {
        valid.add(Assignment.fromJson(record as Map<String, dynamic>));
      } on FormatException {
        await _backupDamaged(prefs, raw);
      } on TypeError {
        await _backupDamaged(prefs, raw);
      }
    }
    return valid;
  }

  Future<void> _backupDamaged(SharedPreferences prefs, String raw) async {
    final key = '${_key}_recovery_backup';
    if (!prefs.containsKey(key) && !await prefs.setString(key, raw)) {
      throw StateError('无法备份损坏记录，已停止写入以保护原数据');
    }
    if (prefs.getString(key) != raw) {
      final additionalKey = '${_key}_recovery_backups';
      final additional = prefs.getStringList(additionalKey) ?? [];
      if (!additional.contains(raw) &&
          !await prefs.setStringList(additionalKey, [...additional, raw])) {
        throw StateError('无法备份损坏记录，已停止写入以保护原数据');
      }
    }
    recoveryWarning = '部分本机记录无法读取，原始数据已保留备份；请重新同步作业。';
  }

  Future<void> _save(_Journal state) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_key, jsonEncode(state.toJson()))) {
      throw StateError('未能保存本机作业记录');
    }
  }
}

class _Journal {
  _Journal(List<Assignment> records, this.hidden, this.lastSync)
      : byId = {
          // The UI reads the full journal, so migrate legacy completion labels
          // into status instead of filtering them only from the pending getter.
          for (final a in records)
            a.id:
                _oldCompletedPeerReview(a) ? a.copyWith(status: 'submitted') : a
        };
  final Map<String, Assignment> byId;
  final Set<String> hidden;
  DateTime? lastSync;

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'records': byId.values.map((a) => a.toJson()).toList(),
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
      a.status == 'pending' &&
      RegExp(r'^互评作业\s+(已互评|已完成|已提交|已评价|评价完成|互评完成)$')
          .hasMatch(a.requirementsText.trim());

  static String? _workKey(Assignment a) {
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
    final uri = Uri.tryParse(a.submitUrl ?? '');
    if (uri == null || !uri.host.endsWith('.chaoxing.com')) return null;
    final q = uri.queryParameters.map((k, v) => MapEntry(k.toLowerCase(), v));
    final course = q['courseid'],
        clazz = q['classid'] ?? q['clazzid'] ?? q['jclassid'];
    final active = q['activeid'];
    if ([course, clazz, active].any((v) => v == null || v.isEmpty)) return null;
    return 'cx:${a.id.startsWith('cx:exam:') ? 'exam' : 'activity'}:$course:$clazz:$active';
  }

  void merge(List<Assignment> incoming) {
    final oldIds = <String, List<String>>{};
    for (final a in byId.values) {
      for (final key in {_workKey(a), _activityKey(a)}) {
        if (key != null) (oldIds[key] ??= []).add(a.id);
      }
    }
    for (var item in incoming) {
      final key = _workKey(item) ?? _activityKey(item) ?? item.id;
      var prior = byId[key];
      final aliases = <String>{
        ...oldIds.remove(key) ?? const <String>[],
        ...oldIds.remove(_activityKey(item)) ?? const <String>[]
      };
      for (final alias in aliases) {
        if (alias == key) continue;
        final old = byId.remove(alias);
        prior ??= old;
        if (hidden.remove(alias)) hidden.add(key);
      }
      if (item.id != key) item = item.copyWith(id: key);
      if (prior != null) {
        if (item.lastSyncedAt.isBefore(prior.lastSyncedAt)) {
          byId[key] = prior.copyWith(id: key);
          continue;
        }
        if (item.deadlineReadFailed) {
          item = item.copyWith(
              deadlineAt: prior.deadlineAt,
              deadlineTrusted: prior.deadlineTrusted,
              clearDeadlineAt: prior.deadlineAt == null);
        }
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

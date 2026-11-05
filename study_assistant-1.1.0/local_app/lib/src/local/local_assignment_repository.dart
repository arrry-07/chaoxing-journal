import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/assignment.dart';
import '../models/course.dart';

class LocalAssignmentRepository {
  static const _key = 'chaoxing_journal_v2';
  // Old app versions stored account-independent data in three preferences.
  static const _oldItems = 'local_assignments';
  static const _oldSync = 'local_last_sync_at';
  static const _oldHidden = 'local_hidden_completed_assignment_ids';

  String? recoveryWarning;
  Future<List<CourseRef>> loadCourses() async {
    final p = await SharedPreferences.getInstance();
    return (jsonDecode(p.getString('course_refs') ?? '[]') as List)
        .map((j) => CourseRef.fromJson(j as Map<String, dynamic>))
        .toList();
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
        for (final key in [
          'sync_attempt_at',
          'sync_data_at',
          'course_refs',
          'unfollowed_courses',
          _oldItems,
          _oldHidden,
          _oldSync,
          _key,
          '${_key}_recovery_backup',
          '${_key}_recovery_backups'
        ]) {
          await prefs.remove(key);
        }
      });

  Future<_Journal> _read() async {
    final prefs = await SharedPreferences.getInstance();
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
            DateTime.tryParse(decoded['lastSync'] as String? ?? ''));
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
        'lastSync': lastSync?.toIso8601String(),
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

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/assignment.dart';

class LocalAssignmentRepository {
  static const _key = 'chaoxing_journal_v2';
  // Old app versions stored account-independent data in three preferences.
  static const _oldItems = 'local_assignments';
  static const _oldSync = 'local_last_sync_at';
  static const _oldHidden = 'local_hidden_completed_assignment_ids';

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
        for (final key in [_oldItems, _oldHidden, _oldSync, _key]) {
          await prefs.remove(key);
        }
      });

  Future<_Journal> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_key);
    if (encoded != null) return _Journal.fromJson(jsonDecode(encoded));
    final items = (jsonDecode(prefs.getString(_oldItems) ?? '[]') as List)
        .map((e) => Assignment.fromJson(e as Map<String, dynamic>))
        .toList();
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
            a.id: _oldCompletedPeerReview(a)
                ? a.copyWith(status: 'submitted')
                : a
        };
  final Map<String, Assignment> byId;
  final Set<String> hidden;
  DateTime? lastSync;

  factory _Journal.fromJson(Map<String, dynamic> json) => _Journal(
        (json['records'] as List)
            .map((e) => Assignment.fromJson(e as Map<String, dynamic>))
            .toList(),
        Set<String>.from(json['hidden'] as List),
        DateTime.tryParse(json['lastSync'] as String? ?? ''),
      );
  Map<String, dynamic> toJson() => {
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

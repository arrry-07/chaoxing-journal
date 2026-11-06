import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/assignment.dart';
import '../models/assignment_change.dart';

class AssignmentChangeLog {
  static const key = 'assignment_changes_v1';
  Future<List<AssignmentChange>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(key);
    if (raw == null) return [];
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return (j['events'] as List)
        .map((v) =>
            AssignmentChange.fromJson(Map<String, dynamic>.from(v as Map)))
        .take(200)
        .toList();
  }

  Future<void> record(List<Assignment> previous, List<Assignment> current,
      Set<String> observedIds,
      {bool completeSync = true}) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(key);
    final initialized = raw != null &&
        ((jsonDecode(raw) as Map)['initialized'] ?? true) == true;
    final old = await load();
    final delta = initialized
        ? AssignmentChange.compare(
            previous, current, observedIds, DateTime.now())
        : <AssignmentChange>[];
    if (!await p.setString(
        key,
        jsonEncode({
          'version': 1,
          'initialized': initialized || completeSync,
          'events': [
            ...delta.reversed.map((e) => e.toJson()),
            ...old.map((e) => e.toJson())
          ].take(200).toList()
        }))) {
      throw StateError('作业变化记录未能保存');
    }
  }
}

import 'package:shared_preferences/shared_preferences.dart';

class ReminderRuleStore {
  static const defaultOffsetsMinutes = [1440, 180, 30];
  static const _key = 'reminder_offsets_minutes';

  Future<List<int>> loadOffsetsMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return normalizeOffsets(
      prefs
          .getStringList(_key)
          ?.map((item) => int.tryParse(item))
          .whereType<int>()
          .toList(),
    );
  }

  Future<List<int>> saveOffsetsMinutes(List<int> offsetsMinutes) async {
    final normalized = normalizeOffsets(offsetsMinutes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      normalized.map((item) => item.toString()).toList(),
    );
    return normalized;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static List<int> normalizeOffsets(List<int>? offsetsMinutes) {
    final values = (offsetsMinutes == null || offsetsMinutes.isEmpty
            ? defaultOffsetsMinutes
            : offsetsMinutes)
        .where((item) => item > 0)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return values;
  }
}

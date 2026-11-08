import 'package:shared_preferences/shared_preferences.dart';
import '../models/reminder_rule_limits.dart';

class ReminderRuleStore {
  static const defaultOffsetsMinutes = [1440, 180, 30];
  static const _key = 'reminder_offsets_minutes';

  Future<List<int>> loadOffsetsMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return normalizeStoredOffsets(
      prefs
          .getStringList(_key)
          ?.map((item) => int.tryParse(item))
          .whereType<int>()
          .toList(),
    );
  }

  Future<List<int>> saveOffsetsMinutes(List<int> offsetsMinutes) async {
    if (offsetsMinutes.any(
        (item) => item < 1 || item > ReminderRuleLimits.maxOffsetMinutes)) {
      throw ArgumentError.value(
        offsetsMinutes,
        'offsetsMinutes',
        '提醒时间必须为 1 至 525600 分钟',
      );
    }
    final normalized = normalizeOffsets(offsetsMinutes);
    if (normalized.length > ReminderRuleLimits.maxRuleCount) {
      throw ArgumentError.value(
        offsetsMinutes,
        'offsetsMinutes',
        '最多保存 32 条提醒规则',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final expected = normalized.map((item) => item.toString()).toList();
    final saved = await prefs.setStringList(
      _key,
      expected,
    );
    if (!saved) {
      try {
        await prefs.reload();
      } catch (_) {
        throw StateError('提醒设置保存结果无法确认，请稍后重试');
      }
      final persisted = prefs.getStringList(_key);
      if (persisted == null ||
          persisted.length != expected.length ||
          Iterable<int>.generate(expected.length)
              .any((index) => persisted[index] != expected[index])) {
        throw StateError('提醒设置未能保存，请重试');
      }
    }
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
        .where(
            (item) => item > 0 && item <= ReminderRuleLimits.maxOffsetMinutes)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return values;
  }

  /// Reading old data must not rewrite or discard rules that predate the
  /// current input limits. The user can review them explicitly in settings.
  static List<int> normalizeStoredOffsets(List<int>? offsetsMinutes) {
    final values = (offsetsMinutes == null || offsetsMinutes.isEmpty
            ? defaultOffsetsMinutes
            : offsetsMinutes)
        .where((item) => item > 0)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return values;
  }

  static bool requiresReview(List<int> offsetsMinutes) =>
      offsetsMinutes.length > ReminderRuleLimits.maxRuleCount ||
      offsetsMinutes.any(
          (item) => item < 1 || item > ReminderRuleLimits.maxOffsetMinutes);
}

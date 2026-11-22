import 'package:shared_preferences/shared_preferences.dart';
import '../models/reminder_rule_limits.dart';

enum ReminderFrequencyPreset {
  gentle(
    label: '温和',
    description: '提前 1 天、3 小时',
    offsetsMinutes: [1440, 180],
  ),
  recommended(
    label: '推荐冲刺',
    description: '提前 1 天、12 / 6 / 3 / 1 小时与 30 分钟',
    offsetsMinutes: [1440, 720, 360, 180, 60, 30],
  ),
  intensive(
    label: '极致死线',
    description: '提前 2 天、1 天、12 / 6 / 2 / 1 小时与 30 分钟',
    offsetsMinutes: [2880, 1440, 720, 360, 120, 60, 30],
  );

  const ReminderFrequencyPreset({
    required this.label,
    required this.description,
    required this.offsetsMinutes,
  });

  final String label;
  final String description;
  final List<int> offsetsMinutes;
}

class ReminderRuleStore {
  static const defaultOffsetsMinutes = [1440, 720, 360, 180, 60, 30];
  static const _key = 'reminder_offsets_minutes';

  static ReminderFrequencyPreset? matchPreset(Iterable<int> offsets) {
    final normalized = offsets.where((item) => item > 0).toSet();
    if (normalized.isEmpty ||
        offsets.any(
            (item) => item < 1 || item > ReminderRuleLimits.maxOffsetMinutes)) {
      return null;
    }
    for (final preset in ReminderFrequencyPreset.values) {
      final target = preset.offsetsMinutes.toSet();
      if (normalized.length == target.length &&
          normalized.every(target.contains)) {
        return preset;
      }
    }
    return null;
  }

  Future<List<int>> loadOffsetsMinutes({SharedPreferences? prefs}) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    return normalizeStoredOffsets(
      store
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

  Future<void> clear({SharedPreferences? prefs}) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    await p.remove(_key);
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

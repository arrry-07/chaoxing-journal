abstract final class ReminderRuleLimits {
  static const maxRuleCount = 32;
  static const maxOffsetMinutes = 365 * 24 * 60;

  // Older releases imposed no input cap. These broader bounds keep realistic
  // legacy data portable while still bounding untrusted backup input.
  static const maxLegacyRuleCount = 256;
  static const maxLegacyOffsetMinutes = 100 * 365 * 24 * 60;
}

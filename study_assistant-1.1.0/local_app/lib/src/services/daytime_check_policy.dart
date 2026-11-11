/// Pure local-time rules for learning-assignment background checks.
///
/// The policy deliberately uses [DateTime] local construction rather than a
/// fixed UTC offset so daylight-saving transitions follow the device timezone.
class DaytimeCheckPolicy {
  const DaytimeCheckPolicy._();

  static const startHour = 8;
  static const allowedIntervalsMinutes = [120, 240, 360];
  static const defaultIntervalMinutes = 240;

  static bool isInWindow(DateTime localNow) =>
      localNow.hour >= startHour && localNow.hour < 24;

  static DateTime windowStartFor(DateTime localTime) =>
      DateTime(localTime.year, localTime.month, localTime.day, startHour);

  static DateTime nextMidnightAfter(DateTime localTime) =>
      DateTime(localTime.year, localTime.month, localTime.day + 1);

  static DateTime nextWindowStart(DateTime localNow) {
    final todayStart = windowStartFor(localNow);
    return localNow.isBefore(todayStart)
        ? todayStart
        : DateTime(localNow.year, localNow.month, localNow.day + 1, startHour);
  }

  static DateTime nextAfterExecution(
    DateTime actualStart,
    int intervalMinutes,
  ) {
    final interval = normalizeIntervalMinutes(intervalMinutes);
    final candidate = actualStart.add(Duration(minutes: interval));
    if (!candidate.isBefore(nextMidnightAfter(actualStart))) {
      return DateTime(
          actualStart.year, actualStart.month, actualStart.day + 1, startHour);
    }
    if (!isInWindow(candidate)) {
      return DateTime(
          candidate.year, candidate.month, candidate.day, startHour);
    }
    return candidate;
  }

  /// Returns the single next target, collapsing every missed point into one.
  static DateTime nextTarget({
    required DateTime localNow,
    required DateTime? lastAttemptAt,
    required int intervalMinutes,
  }) {
    if (!isInWindow(localNow)) {
      return nextWindowStart(localNow);
    }

    final last = lastAttemptAt?.toLocal();
    if (last == null || _localDate(last) != _localDate(localNow)) {
      return localNow;
    }
    if (last.isAfter(localNow)) {
      // A wall-clock rollback must not make the check immediately due again.
      return nextAfterExecution(localNow, intervalMinutes);
    }

    final candidate = nextAfterExecution(last, intervalMinutes);
    if (!candidate.isAfter(localNow)) {
      return localNow;
    }
    return candidate;
  }

  static bool isDue({
    required DateTime localNow,
    required DateTime? lastAttemptAt,
    required int intervalMinutes,
  }) {
    if (!isInWindow(localNow)) return false;
    final target = nextTarget(
      localNow: localNow,
      lastAttemptAt: lastAttemptAt,
      intervalMinutes: intervalMinutes,
    );
    return !target.isAfter(localNow);
  }

  static int normalizeIntervalMinutes(int minutes) {
    if (allowedIntervalsMinutes.contains(minutes)) return minutes;
    return defaultIntervalMinutes;
  }

  static String _localDate(DateTime value) =>
      '${value.year}-${value.month}-${value.day}';
}

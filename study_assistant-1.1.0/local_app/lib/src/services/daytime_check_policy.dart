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
      localNow.toLocal().hour >= startHour;

  static DateTime windowStartFor(DateTime localTime) {
    final local = localTime.toLocal();
    return DateTime(local.year, local.month, local.day, startHour);
  }

  static DateTime nextMidnightAfter(DateTime localTime) {
    final local = localTime.toLocal();
    return DateTime(local.year, local.month, local.day + 1);
  }

  static DateTime nextWindowStart(DateTime localNow) {
    final todayStart = windowStartFor(localNow);
    return localNow.isBefore(todayStart)
        ? todayStart
        : DateTime(
            todayStart.year, todayStart.month, todayStart.day + 1, startHour);
  }

  static DateTime nextAfterExecution(
    DateTime actualStart,
    int intervalMinutes,
  ) {
    final interval = normalizeIntervalMinutes(intervalMinutes);
    final localStart = actualStart.toLocal();
    final candidate = localStart.add(Duration(minutes: interval));
    if (!candidate.isBefore(nextMidnightAfter(localStart))) {
      return DateTime(
          localStart.year, localStart.month, localStart.day + 1, startHour);
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
    final local = localNow.toLocal();
    if (!isInWindow(local)) {
      return nextWindowStart(local);
    }

    final last = lastAttemptAt?.toLocal();
    if (last == null || _localDate(last) != _localDate(local)) {
      return local;
    }
    if (last.isAfter(local)) {
      // A wall-clock rollback must not make the check immediately due again.
      return nextAfterExecution(local, intervalMinutes);
    }

    final candidate = nextAfterExecution(last, intervalMinutes);
    if (!candidate.isAfter(local)) {
      return local;
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

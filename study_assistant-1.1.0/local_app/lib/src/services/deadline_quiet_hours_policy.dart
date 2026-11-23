import 'package:timezone/timezone.dart' as tz;

/// Provenance of a scheduled deadline anchor.
///
/// Only explicit [official] and user-set [manual] deadlines may drive audible
/// deadline notifications; inferred/unknown records must never break through or
/// schedule deadline alarms.
enum DeadlineScheduleSource {
  official('official'),
  manual('manual'),
  unknown('unknown');

  const DeadlineScheduleSource(this.wireValue);

  final String wireValue;

  static DeadlineScheduleSource fromWire(String? raw) => switch (raw) {
        'official' => DeadlineScheduleSource.official,
        'manual' => DeadlineScheduleSource.manual,
        _ => DeadlineScheduleSource.unknown,
      };
}

typedef PlannedDeadlineSlot = ({DateTime notifyAt, List<int> offsetMinutes});

/// Pure cross-timezone quiet-hours rules for audible deadline & personal
/// notifications.
///
/// Quiet hours are `[23:30, 07:30)` in the target timezone (default device local).
/// This is intentionally independent of [DaytimeCheckPolicy] (`08:00–24:00`),
/// which continues to govern background sync checks.
class DeadlineQuietHoursPolicy {
  const DeadlineQuietHoursPolicy._();

  static const quietStartHour = 23;
  static const quietStartMinute = 30;
  static const quietEndHour = 7;
  static const quietEndMinute = 30;
  static const preNightHour = 22;
  static const preNightMinute = 30;
  static const urgentBreakthroughMaxMinutes = 60;

  static DateTime _inZone(DateTime instant, tz.Location? location) =>
      location == null
          ? instant.toLocal()
          : tz.TZDateTime.from(instant.toUtc(), location);

  static DateTime _atLocalWallTime(
    DateTime zoneRef,
    int dayDelta,
    int hour,
    int minute,
    tz.Location? location,
  ) {
    final targetDate =
        DateTime.utc(zoneRef.year, zoneRef.month, zoneRef.day + dayDelta);
    if (location == null) {
      return DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
        hour,
        minute,
      );
    }
    return tz.TZDateTime(
      location,
      targetDate.year,
      targetDate.month,
      targetDate.day,
      hour,
      minute,
    );
  }

  static int _minuteOfDay(DateTime zoned) => zoned.hour * 60 + zoned.minute;

  /// Returns whether [instant] falls in `[23:30, 07:30)` in [location].
  static bool isQuiet(DateTime instant, {tz.Location? location}) {
    final zoned = _inZone(instant, location);
    final minuteOfDay = _minuteOfDay(zoned);
    const start = quietStartHour * 60 + quietStartMinute;
    const end = quietEndHour * 60 + quietEndMinute;
    return minuteOfDay >= start || minuteOfDay < end;
  }

  /// Next `07:30` after a quiet-hours instant, or [instant] when already awake.
  static DateTime nextQuietEnd(DateTime instant, {tz.Location? location}) {
    final zoned = _inZone(instant, location);
    final minuteOfDay = _minuteOfDay(zoned);
    const start = quietStartHour * 60 + quietStartMinute;
    const end = quietEndHour * 60 + quietEndMinute;
    if (minuteOfDay >= start) {
      return _atLocalWallTime(zoned, 1, quietEndHour, quietEndMinute, location);
    }
    if (minuteOfDay < end) {
      return _atLocalWallTime(zoned, 0, quietEndHour, quietEndMinute, location);
    }
    return zoned;
  }

  /// True iff urgent breakthrough is explicitly enabled, the deadline has a
  /// trusted official/manual provenance, and [notifyAt] is within 60 minutes
  /// before [deadlineAt].
  static bool canBreakThroughQuiet({
    required DateTime notifyAt,
    required DateTime deadlineAt,
    required DeadlineScheduleSource source,
    required bool allowUrgentNightBreakthrough,
  }) {
    if (!allowUrgentNightBreakthrough ||
        source == DeadlineScheduleSource.unknown) {
      return false;
    }
    final remaining = deadlineAt.toUtc().difference(notifyAt.toUtc());
    return remaining > Duration.zero &&
        remaining <= const Duration(minutes: urgentBreakthroughMaxMinutes);
  }

  /// Returns a deduplicated `22:30` pre-night warning instant when a coursework
  /// `deadline` falls inside `[23:30, 07:30)`. Never emits past times or for
  /// `examStart`.
  static DateTime? preNightWarningAt({
    required DateTime deadlineAt,
    required DateTime now,
    required String eventKind,
    tz.Location? location,
  }) {
    if (eventKind != 'deadline' || !isQuiet(deadlineAt, location: location)) {
      return null;
    }
    final zonedDeadline = _inZone(deadlineAt, location);
    final minuteOfDay = _minuteOfDay(zonedDeadline);
    const start = quietStartHour * 60 + quietStartMinute;
    final dayDelta = minuteOfDay >= start ? 0 : -1;
    final preNight = _atLocalWallTime(
      zonedDeadline,
      dayDelta,
      preNightHour,
      preNightMinute,
      location,
    );
    if (!preNight.toUtc().isAfter(now.toUtc()) ||
        !preNight.toUtc().isBefore(deadlineAt.toUtc())) {
      return null;
    }
    return preNight;
  }

  /// Plans deduplicated notification slots sorted chronologically.
  static List<PlannedDeadlineSlot> planDeadlineSlots({
    required DateTime deadlineAt,
    required DateTime now,
    required List<int> offsetsMinutes,
    required DeadlineScheduleSource source,
    required String eventKind,
    required bool allowUrgentNightBreakthrough,
    tz.Location? location,
  }) {
    final nowUtc = now.toUtc();
    final deadlineUtc = deadlineAt.toUtc();
    if (source == DeadlineScheduleSource.unknown ||
        !deadlineUtc.isAfter(nowUtc)) {
      return const [];
    }

    final slotsByEpoch = <int, (DateTime notifyAt, Set<int> offsets)>{};
    for (final offset in offsetsMinutes) {
      if (offset <= 0) continue;
      final candidateUtc = deadlineUtc.subtract(Duration(minutes: offset));
      final candidateZoned = _inZone(candidateUtc, location);
      final shifted = isQuiet(candidateZoned, location: location) &&
              !canBreakThroughQuiet(
                notifyAt: candidateZoned,
                deadlineAt: deadlineUtc,
                source: source,
                allowUrgentNightBreakthrough: allowUrgentNightBreakthrough,
              )
          ? nextQuietEnd(candidateZoned, location: location)
          : candidateZoned;
      final shiftedUtc = shifted.toUtc();
      if (!shiftedUtc.isAfter(nowUtc) || !shiftedUtc.isBefore(deadlineUtc)) {
        continue;
      }
      final epochMs = shiftedUtc.millisecondsSinceEpoch;
      final existing = slotsByEpoch[epochMs];
      if (existing == null) {
        slotsByEpoch[epochMs] = (shifted, <int>{offset});
      } else {
        existing.$2.add(offset);
      }
    }

    final preNight = preNightWarningAt(
      deadlineAt: deadlineUtc,
      now: nowUtc,
      eventKind: eventKind,
      location: location,
    );
    if (preNight != null) {
      final epochMs = preNight.toUtc().millisecondsSinceEpoch;
      if (!slotsByEpoch.containsKey(epochMs)) {
        final remainingMinutes =
            deadlineUtc.difference(preNight.toUtc()).inMinutes.clamp(1, 525600);
        slotsByEpoch[epochMs] = (preNight, <int>{remainingMinutes});
      }
    }

    final entries = slotsByEpoch.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return [
      for (final entry in entries)
        (
          notifyAt: entry.value.$1,
          offsetMinutes: List<int>.unmodifiable(
            entry.value.$2.toList()..sort((a, b) => b.compareTo(a)),
          ),
        ),
    ];
  }

  /// Applies quiet-hours guard to an explicit personal todo/exam reminder
  /// candidate time.
  static DateTime? adjustManualCandidate({
    required DateTime candidateAt,
    required DateTime eventAt,
    required DateTime now,
    required bool allowUrgentNightBreakthrough,
    tz.Location? location,
  }) {
    final nowUtc = now.toUtc();
    final eventUtc = eventAt.toUtc();
    final candidateUtc = candidateAt.toUtc();
    if (!candidateUtc.isAfter(nowUtc) || !candidateUtc.isBefore(eventUtc)) {
      return null;
    }
    final zoned = _inZone(candidateUtc, location);
    final adjusted = isQuiet(zoned, location: location) &&
            !canBreakThroughQuiet(
              notifyAt: zoned,
              deadlineAt: eventUtc,
              source: DeadlineScheduleSource.manual,
              allowUrgentNightBreakthrough: allowUrgentNightBreakthrough,
            )
        ? nextQuietEnd(zoned, location: location)
        : zoned;
    final adjustedUtc = adjusted.toUtc();
    if (!adjustedUtc.isAfter(nowUtc) || !adjustedUtc.isBefore(eventUtc)) {
      return null;
    }
    return adjusted;
  }
}

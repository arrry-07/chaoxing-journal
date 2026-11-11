import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/services/daytime_check_policy.dart';

void main() {
  group('daytime window', () {
    test('uses inclusive 08:00 and exclusive next midnight', () {
      expect(DaytimeCheckPolicy.isInWindow(DateTime(2026, 11, 11, 7, 59, 59)),
          isFalse);
      expect(DaytimeCheckPolicy.isInWindow(DateTime(2026, 11, 11, 8)), isTrue);
      expect(DaytimeCheckPolicy.isInWindow(DateTime(2026, 11, 11, 23, 59, 59)),
          isTrue);
      expect(DaytimeCheckPolicy.isInWindow(DateTime(2026, 11, 12)), isFalse);
    });

    test('targets 08:00 when called before the window', () {
      final target = DaytimeCheckPolicy.nextTarget(
        localNow: DateTime(2026, 11, 11, 3),
        lastAttemptAt: DateTime(2026, 11, 10, 20),
        intervalMinutes: 240,
      );
      expect(target, DateTime(2026, 11, 11, 8));
    });

    test('first daytime check is due immediately and missed slots collapse',
        () {
      final now = DateTime(2026, 11, 11, 15);
      expect(
        DaytimeCheckPolicy.nextTarget(
          localNow: now,
          lastAttemptAt: null,
          intervalMinutes: 240,
        ),
        now,
      );
      expect(
        DaytimeCheckPolicy.nextTarget(
          localNow: now,
          lastAttemptAt: DateTime(2026, 11, 11, 8),
          intervalMinutes: 240,
        ),
        now,
      );
    });

    test('late execution anchors the next interval to actual start', () {
      final actual = DateTime(2026, 11, 11, 9, 10);
      expect(
        DaytimeCheckPolicy.nextAfterExecution(actual, 240),
        DateTime(2026, 11, 11, 13, 10),
      );
      expect(
        DaytimeCheckPolicy.nextAfterExecution(
            DateTime(2026, 11, 11, 21, 10), 240),
        DateTime(2026, 11, 12, 8),
      );
    });

    test(
        'supports 2, 4 and 6 hour intervals without a second daily run after '
        'the last daytime slot', () {
      final actual = DateTime(2026, 11, 11, 8);
      expect(DaytimeCheckPolicy.nextAfterExecution(actual, 120),
          DateTime(2026, 11, 11, 10));
      expect(DaytimeCheckPolicy.nextAfterExecution(actual, 240),
          DateTime(2026, 11, 11, 12));
      expect(DaytimeCheckPolicy.nextAfterExecution(actual, 360),
          DateTime(2026, 11, 11, 14));
    });

    test('clock rollback does not create an immediate repeated check', () {
      final rolledBack = DateTime(2026, 11, 11, 10);
      final target = DaytimeCheckPolicy.nextTarget(
        localNow: rolledBack,
        lastAttemptAt: DateTime(2026, 11, 11, 14),
        intervalMinutes: 240,
      );
      expect(target, DateTime(2026, 11, 11, 14));
      expect(
        DaytimeCheckPolicy.isDue(
          localNow: rolledBack,
          lastAttemptAt: DateTime(2026, 11, 11, 14),
          intervalMinutes: 240,
        ),
        isFalse,
      );
    });

    test('unknown intervals normalize to four hours', () {
      expect(DaytimeCheckPolicy.normalizeIntervalMinutes(15), 240);
      expect(DaytimeCheckPolicy.normalizeIntervalMinutes(120), 120);
      expect(DaytimeCheckPolicy.normalizeIntervalMinutes(360), 360);
    });
  });
}

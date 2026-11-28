import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/notification_schedule_policy.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  test('deadline choice accepts only the three deadline channels', () {
    const ids = [
      'assignment_deadlines',
      'assignment_deadlines_v2',
      'assignment_deadlines_v3',
    ];
    for (final id in ids) {
      expect(
          NotificationSchedulePolicy.normalizeDeadlineChannelId(' $id '), id);
    }
    for (final id in [
      null,
      '',
      'assignment_updates_v3',
      'assignment_silent',
      'personal_schedule_v3',
      'daily_summary_v3',
    ]) {
      expect(NotificationSchedulePolicy.normalizeDeadlineChannelId(id), isNull);
    }
  });

  test('legacy and current channels keep their names and recovery ownership',
      () {
    const channels = {
      'assignment_deadlines': ('assignments', '作业截止提醒'),
      'assignment_deadlines_v2': ('assignments', '作业截止提醒'),
      'assignment_deadlines_v3': ('assignments', '作业截止提醒'),
      'assignment_silent': ('assignments', '作业截止提醒'),
      'assignment_updates': ('assignments', '作业变化提醒'),
      'assignment_updates_v2': ('assignments', '新增作业提醒'),
      'assignment_updates_v3': ('assignments', '新增作业提醒'),
      'personal_schedule': ('manual', '待办与考试提醒'),
      'personal_schedule_v2': ('manual', '待办与考试提醒'),
      'personal_schedule_v3': ('manual', '待办与考试提醒'),
      'daily_summary': ('summary', '每日课业摘要'),
      'daily_summary_v2': ('summary', '每日课业摘要'),
      'daily_summary_v3': ('summary', '每日课业摘要'),
    };
    for (final MapEntry(key: id, value: (category, name)) in channels.entries) {
      expect(
          NotificationSchedulePolicy.scheduleCategoryForChannel(id), category,
          reason: id);
      expect(NotificationSchedulePolicy.channelNameForId(id), name, reason: id);
    }
    expect(NotificationSchedulePolicy.scheduleCategoryForChannel(null), isNull);
    expect(NotificationSchedulePolicy.scheduleCategoryForChannel('unknown'),
        isNull);
    expect(NotificationSchedulePolicy.channelNameForId('unknown'), '作业截止提醒');
  });

  test('test notifications are private without owning a schedule journal', () {
    const payloads = {
      'a:studyassistant:///assignments/42': 'assignments',
      'p:exam-42': 'manual',
      'd:summary': 'summary',
      't:manual-notification-test': null,
      't:notification-test': null,
    };
    for (final MapEntry(key: payload, value: category) in payloads.entries) {
      expect(NotificationSchedulePolicy.isPrivatePayload(payload), isTrue);
      expect(NotificationSchedulePolicy.scheduleCategoryForPayload(payload),
          category);
    }
    for (final payload in [null, '', 'unrelated:p:42']) {
      expect(NotificationSchedulePolicy.isPrivatePayload(payload), isFalse);
      expect(NotificationSchedulePolicy.scheduleCategoryForPayload(payload),
          isNull);
    }
  });

  test('manual ownership proof requires a well-formed manual payload', () {
    for (final payload in ['p:课业-42', 'p:${'x' * 100}']) {
      expect(NotificationSchedulePolicy.isValidManualPayload(payload), isTrue);
    }
    for (final payload in [
      null,
      'a:42',
      'p:',
      'p:line\nbreak',
      'p:\u007f',
      'p:${'x' * 101}',
    ]) {
      expect(NotificationSchedulePolicy.isValidManualPayload(payload), isFalse);
    }
    expect(NotificationSchedulePolicy.isPrivatePayload('p:'), isTrue);
  });

  group('personal reminder eligibility', () {
    late tz.Location shanghai;
    late ManualEntry nightEntry;

    setUpAll(() {
      timezone_data.initializeTimeZones();
      shanghai = tz.getLocation('Asia/Shanghai');
      nightEntry = ManualEntry(
        id: 'night-exam',
        title: '早场考试',
        kind: ManualEntry.kindExam,
        at: tz.TZDateTime(shanghai, 2030, 11, 20, 7, 30),
        remind: true,
      );
    });

    test('quiet hours would move the reminder to the event start', () {
      final now = DateTime.utc(2030, 11, 19, 21);
      expect(
        NotificationSchedulePolicy.isManualReminderQuietHoursSkipped(
          nightEntry,
          now: now,
          location: shanghai,
        ),
        isTrue,
      );
      expect(
        NotificationSchedulePolicy.isManualReminderQuietHoursSkipped(
          nightEntry,
          now: now,
          allowUrgentNightBreakthrough: true,
          location: shanghai,
        ),
        isFalse,
      );
      expect(
        NotificationSchedulePolicy.isManualReminderWindowMissed(
          nightEntry,
          now: now,
        ),
        isFalse,
      );
    });

    test('the exact 30-minute boundary is missed, even with breakthrough', () {
      final now = DateTime.utc(2030, 11, 19, 23);
      expect(
        NotificationSchedulePolicy.isManualReminderWindowMissed(nightEntry,
            now: now),
        isTrue,
      );
      expect(
        NotificationSchedulePolicy.isManualReminderQuietHoursSkipped(
          nightEntry,
          now: now,
          allowUrgentNightBreakthrough: true,
          location: shanghai,
        ),
        isFalse,
      );
    });

    test('completed, disabled and unscheduled reminders have neither reason',
        () {
      const unscheduled = ManualEntry(
        id: 'later',
        title: '时间待定',
        kind: ManualEntry.kindTodo,
        remind: true,
      );
      final now = DateTime.utc(2030, 11, 19, 23);
      for (final entry in [
        nightEntry.copyWith(done: true),
        nightEntry.copyWith(remind: false),
        unscheduled,
      ]) {
        expect(
          NotificationSchedulePolicy.isManualReminderWindowMissed(entry,
              now: now),
          isFalse,
        );
        expect(
          NotificationSchedulePolicy.isManualReminderQuietHoursSkipped(
            entry,
            now: now,
            location: shanghai,
          ),
          isFalse,
        );
      }
    });
  });

  test('remaining-time text clamps negative values and labels exams', () {
    expect(NotificationSchedulePolicy.formatDeadlineRemainingText(-1),
        '还剩 0 分钟截止');
    expect(NotificationSchedulePolicy.formatDeadlineRemainingText(1440),
        '还剩 1 天截止');
    expect(
        NotificationSchedulePolicy.formatDeadlineRemainingText(1501,
            examStart: true),
        '还剩 1 天 1 小时 1 分钟开考');
  });

  test('allocation skips existing and repeated IDs without changing input', () {
    const first = 2000000000;
    const reserved = {first, first + 2};
    final offsets = [0, 1, 1, 2, 3, 0x7fffffff - first - 1].iterator;
    final ids = NotificationSchedulePolicy.allocateNotificationIds(
      3,
      reserved,
      nextInt: (upperBound) {
        expect(upperBound, 0x7fffffff - first);
        expect(offsets.moveNext(), isTrue);
        return offsets.current;
      },
    );
    expect(ids, [first + 1, first + 3, 0x7ffffffe]);
    expect(reserved, {first, first + 2});
  });

  test('empty allocation does not draw from the generator', () {
    expect(
      NotificationSchedulePolicy.allocateNotificationIds(
        0,
        const {},
        nextInt: (_) => throw StateError('unexpected allocation'),
      ),
      isEmpty,
    );
  });

  test('the most recent warning precedes existing context', () {
    expect(NotificationSchedulePolicy.appendWarning(null, '新问题'), '新问题');
    expect(NotificationSchedulePolicy.appendWarning('', '新问题'), '新问题');
    expect(NotificationSchedulePolicy.appendWarning('已有问题', '新问题'), '新问题；已有问题');
  });
}

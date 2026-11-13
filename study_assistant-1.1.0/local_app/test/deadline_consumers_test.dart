import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/widget_snapshot.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

class _Snapshot extends WidgetSnapshotService {
  List<WidgetSnapshotItem> items = [];
  @override
  Future<void> saveSnapshot(List<WidgetSnapshotItem> items) async {
    this.items = items;
  }
}

Assignment work(String id, DateTime? date, {String status = 'pending'}) =>
    Assignment(
        id: id,
        submitUrl:
            'https://mooc1.chaoxing.com/work/task?courseId=1&classId=2&workId=${Uri.encodeComponent(id)}',
        courseName: '课程',
        title: id,
        deadlineAt: date,
        requirementsText: '',
        status: status,
        lastSyncedAt: DateTime.now());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('snapshot keeps near, far, undated, pending and overdue in order',
      () async {
    final now = DateTime.now();
    final snapshot = _Snapshot();
    final extended =
        work('延期', now).copyWith(deadlineAt: now.add(const Duration(days: 3)));
    final undated = extended.copyWith(id: '无日期', clearDeadlineAt: true);
    final pending = extended.copyWith(
      id: '待确认',
      deadlineAt: now.add(const Duration(days: 2)),
      deadlineTrusted: false,
    );
    final far = extended.copyWith(
      id: '较远',
      deadlineAt: now.add(const Duration(days: 40)),
    );
    final overdue = extended.copyWith(
      id: '逾期',
      deadlineAt: now.subtract(const Duration(days: 1)),
    );
    expect(Assignment.fromJson(undated.toJson()).deadlineAt, isNull);
    expect(undated.isOverdue, isFalse);
    final assignments = [
      undated,
      extended,
      work('明天', now.add(const Duration(days: 1))),
      pending,
      far,
      overdue,
      work('已提交', now, status: 'submitted'),
      work('已批改', now, status: 'graded')
    ];
    await snapshot.saveAssignments(assignments);
    expect(snapshot.items.map((i) => i.assignmentId),
        ['明天', '延期', '较远', '无日期', '待确认', '逾期']);
    expect(snapshot.items[1].deadlineAt, extended.deadlineAt);
    expect(snapshot.items[1].toJson()['deadlineText'], isNotEmpty);
    final noDeadline = WidgetSnapshotItem.fromJson(snapshot.items[3].toJson());
    expect(noDeadline.deadlineAt, isNull);
    expect(noDeadline.remainingText, '未设置截止时间');
    expect(noDeadline.urgencyLevel, 'unknown');
  });

  test('widget does not show a failed deadline read as a current countdown',
      () async {
    final snapshot = _Snapshot();
    final item = work('failed', DateTime.now().add(const Duration(days: 1)))
        .copyWith(deadlineReadFailed: true);
    await snapshot.saveAssignments([item]);
    expect(snapshot.items.single.deadlineAt, isNull);
    expect(snapshot.items.single.remainingText, contains('上次'));
    expect(snapshot.items.single.urgencyLevel, 'unknown');
  });

  test('widget treats conflicting status and overdue as non-countdown states',
      () async {
    final now = DateTime.now();
    final snapshot = _Snapshot();
    final unknown = work(
      'unknown',
      now.add(const Duration(days: 1)),
      status: 'unknown',
    );
    final overdue = work(
      'overdue',
      now.subtract(const Duration(minutes: 1)),
    );

    await snapshot.saveAssignments([unknown, overdue]);

    expect(snapshot.items.map((item) => item.assignmentId),
        ['unknown', 'overdue']);
    expect(snapshot.items.first.deadlineAt, isNull);
    expect(snapshot.items.first.remainingText, contains('待确认'));
    expect(snapshot.items.first.urgencyLevel, 'unknown');
    expect(snapshot.items.last.deadlineAt, overdue.deadlineAt);
    expect(snapshot.items.last.remainingText, '已逾期');
  });

  test('extension replaces same ID and removed deadline cancels reminder',
      () async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    timezone_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final active = <int, Map>{};
    final cancelled = <int>[];
    var failSchedule = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'getNotificationAppLaunchDetails':
          return {'notificationLaunchedApp': false};
        case 'getNotificationChannels':
          return [];
        case 'createNotificationChannel':
          return true;
        case 'requestNotificationsPermission':
          return true;
        case 'pendingNotificationRequests':
          return active.values.toList();
        case 'zonedSchedule':
          if (failSchedule) throw PlatformException(code: 'unavailable');
          final args = call.arguments as Map;
          active[args['id'] as int] = args;
          return null;
        case 'cancel':
          final id = (call.arguments as Map)['id'] as int;
          cancelled.add(id);
          active.remove(id);
          return null;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final service = LocalNotificationService();
    final original = work('作业', DateTime.now().add(const Duration(days: 2)));
    await service.rescheduleAssignments([original], offsetsMinutes: [30]);
    final first = active.values.single;
    final extended = original.copyWith(
        deadlineAt: original.deadlineAt!.add(const Duration(days: 1)));
    await service.rescheduleAssignments([extended], offsetsMinutes: [30]);
    expect(cancelled, [first['id']]);
    expect(active.keys.single, isNot(first['id']));
    final next = active.values.single;
    expect(
        DateTime.parse(next['scheduledDateTime'])
            .difference(DateTime.parse(first['scheduledDateTime'])),
        const Duration(days: 1));
    failSchedule = true;
    await service.rescheduleAssignments([
      extended.copyWith(
          deadlineAt: extended.deadlineAt!.add(const Duration(days: 1)))
    ], offsetsMinutes: [
      30
    ]);
    expect(service.lastWarning, contains('未能完整更新'));
    expect(active.values.single, next);
    expect(cancelled, contains(first['id']));
    expect(cancelled, hasLength(2),
        reason:
            'the failed staging ID is cancelled before the old batch is retained');
    failSchedule = false;
    await service.rescheduleAssignments(
        [extended.copyWith(clearDeadlineAt: true)],
        offsetsMinutes: [30]);
    expect(cancelled, containsAll([first['id'], next['id']]));
    expect(cancelled, hasLength(3),
        reason:
            'the failed staged ID is compensated before the active batch is retired');
    expect(active, isEmpty);
  });
}

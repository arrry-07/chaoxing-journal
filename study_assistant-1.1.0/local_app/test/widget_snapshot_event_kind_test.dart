import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/display_preferences.dart';
import 'package:study_assistant_mobile/src/models/widget_snapshot.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';
import 'review_core_remediation_test.dart' as f;

class _Snapshot extends WidgetSnapshotService {
  List<WidgetSnapshotItem> items = [];
  int saveCalls = 0;
  bool shouldFail = false;

  @override
  Future<void> saveSnapshot(List<WidgetSnapshotItem> items) async {
    saveCalls++;
    if (shouldFail) {
      throw StateError('widget bridge unavailable');
    }
    this.items = items;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 11, 17, 8);

  Assignment exam(String id, DateTime start) => Assignment(
        id: 'cx:exam:1:2:$id',
        source: AssignmentSource.exam,
        courseName: '课程',
        title: '考试',
        deadlineAt: null,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
        exam: ExamInfo(
          examId: id,
          courseId: '1',
          clazzId: '2',
          startAt: start,
          startTrusted: true,
          lifecycle: 'scheduled',
        ),
      );

  Assignment work(String id, DateTime deadline) => Assignment(
        id: 'cx:work:1:2:$id',
        courseName: '课程',
        title: '作业',
        deadlineAt: deadline,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      );

  test('widget JSON distinguishes exam start from an assignment deadline',
      () async {
    final start = now.add(const Duration(hours: 2));
    final deadline = now.add(const Duration(hours: 3));
    final snapshot = _Snapshot();

    await snapshot.saveAssignments([
      exam('3', start),
      work('4', deadline),
    ]);

    final byId = {
      for (final item in snapshot.items)
        item.assignmentId:
            jsonDecode(jsonEncode(item.toJson())) as Map<String, dynamic>,
    };
    final examJson = byId['cx:exam:1:2:3']!;
    final workJson = byId['cx:work:1:2:4']!;
    expect(examJson['eventKind'], 'examStart');
    expect(workJson['eventKind'], 'deadline');
    expect(DateTime.parse(examJson['deadlineAt'] as String).toUtc(),
        start.toUtc());
    expect(DateTime.parse(workJson['deadlineAt'] as String).toUtc(),
        deadline.toUtc());
  });

  test('old or unknown widget snapshots fall back to a deadline', () {
    final base = <String, dynamic>{
      'assignmentId': 'cx:work:1:2:5',
      'title': '旧作业',
      'courseName': '课程',
      'deadlineAt': now.add(const Duration(days: 1)).toIso8601String(),
      'remainingText': '1天',
      'urgencyLevel': 'normal',
      'deepLinkUrl': 'studyassistant:///assignments/old',
    };
    final old = WidgetSnapshotItem.fromJson(base);
    final unknown = WidgetSnapshotItem.fromJson({
      ...base,
      'eventKind': 'unsupported',
    });

    expect(old.toJson()['eventKind'], 'deadline');
    expect(unknown.toJson()['eventKind'], 'deadline');
  });

  test(
      'saveAssignmentsForContext captures full pending count beyond top 6 and range label',
      () async {
    final snapshot = _Snapshot();
    final rows = [
      for (var i = 1; i <= 8; i++) work('$i', now.add(Duration(hours: i))),
    ];

    await snapshot.saveAssignmentsForContext(
      rows,
      authenticated: true,
      range: WidgetRange.week,
    );

    expect(snapshot.items, hasLength(6));
    expect(snapshot.lastSavedTotalCount, 8);
    expect(snapshot.lastSavedAuthenticated, isTrue);
    expect(snapshot.lastSavedRangeLabel, '7日待办');

    await snapshot.saveAssignmentsForContext(
      const [],
      authenticated: false,
      range: WidgetRange.today,
    );
    expect(snapshot.items, isEmpty);
    expect(snapshot.lastSavedTotalCount, 0);
    expect(snapshot.lastSavedAuthenticated, isFalse);
    expect(snapshot.lastSavedRangeLabel, '今日待办');
  });

  test(
      'foreground logout preserves widget warning while headless sync refreshes best-effort',
      () async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final fgWidget = _Snapshot()..shouldFail = true;
    final fgStore = AssignmentStore(
      sessionStore: f.Session(),
      notificationService: f.Notifications(),
      widgetSnapshotService: fgWidget,
      chaoxingClient: f.Client(),
      manageBackgroundSchedule: true,
    );
    addTearDown(fgStore.dispose);
    await fgStore.restoreSession();
    await fgStore.logout();
    expect(fgStore.error, contains('桌面内容可能仍保留'));

    final bgWidget = _Snapshot();
    final bgStore = AssignmentStore(
      sessionStore: f.Session(),
      notificationService: f.Notifications(),
      widgetSnapshotService: bgWidget,
      chaoxingClient: f.Client(),
      manageBackgroundSchedule: false,
    );
    addTearDown(bgStore.dispose);
    await bgStore.restoreSession();
    await bgStore.syncAssignments();
    expect(bgWidget.saveCalls, greaterThanOrEqualTo(1));
    expect(bgWidget.lastSavedAuthenticated, isTrue);
    expect(bgWidget.items, isNotEmpty);

    bgWidget.shouldFail = true;
    await bgStore.syncAssignments();
    expect(bgStore.error, isNull);
  });

  test('headless logout clears the previously saved widget data', () async {
    const channel = MethodChannel('home_widget');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final data = <String, Object?>{};
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'saveWidgetData') {
        final args = call.arguments as Map;
        data[args['id'] as String] = args['data'];
      }
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: f.Session(),
      notificationService: f.Notifications(),
      widgetSnapshotService: WidgetSnapshotService(),
      chaoxingClient: f.Client(),
      manageBackgroundSchedule: false,
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    await store.syncAssignments();
    expect(data['assignment_authenticated'], isTrue);
    expect(jsonDecode(data['assignment_snapshot'] as String), isNotEmpty);
    expect(data['assignment_snapshot_at'], isA<String>());

    await store.logout();

    expect(data['assignment_authenticated'], isFalse);
    expect(jsonDecode(data['assignment_snapshot'] as String), isEmpty);
    expect(data['assignment_total_count'], 0);
    expect(data['assignment_snapshot_at'], isNull);
  });

  test('signed-out snapshot removes a previously written timestamp', () async {
    const channel = MethodChannel('home_widget');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final writes = <Object?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'saveWidgetData') {
        final args = call.arguments as Map;
        if (args['id'] == 'assignment_snapshot_at') writes.add(args['data']);
      }
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final service = WidgetSnapshotService();
    await service.saveAssignmentsForContext(
      [work('1', DateTime.now().add(const Duration(days: 1)))],
    );
    await service.saveAssignmentsForContext(const [], authenticated: false);
    expect(writes.first, isA<String>());
    expect(writes.last, isNull);
    expect(writes, hasLength(2));
  });
}

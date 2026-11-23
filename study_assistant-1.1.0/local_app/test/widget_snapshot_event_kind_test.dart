import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/models/course_term_preferences.dart';
import 'package:study_assistant_mobile/src/models/display_preferences.dart';
import 'package:study_assistant_mobile/src/models/local_coursework_state.dart';
import 'package:study_assistant_mobile/src/models/widget_snapshot.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/course_term_catalog.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';
import 'review_core_remediation_test.dart' as f;

class _Snapshot extends WidgetSnapshotService {
  _Snapshot({super.clock});

  List<WidgetSnapshotItem> items = [];
  final history = <({
    bool authenticated,
    int totalCount,
    String rangeLabel,
    List<WidgetSnapshotItem> items
  })>[];
  int saveCalls = 0;
  bool shouldFail = false;

  @override
  Future<void> saveSnapshot(List<WidgetSnapshotItem> items) async {
    saveCalls++;
    if (shouldFail) {
      throw StateError('widget bridge unavailable');
    }
    this.items = items;
    history.add((
      authenticated: lastSavedAuthenticated,
      totalCount: lastSavedTotalCount,
      rangeLabel: lastSavedRangeLabel,
      items: List<WidgetSnapshotItem>.of(items),
    ));
  }
}

class _BrokenRestoreRepo extends LocalAssignmentRepository {
  @override
  Future<void> activateAccount(String account,
      {String? previousAccount}) async {
    throw StateError('db unavailable');
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

  test('legacy and unknown deadlineSource JSON decode safely to official', () {
    final base = <String, dynamic>{
      'assignmentId': 'cx:work:1:2:9',
      'title': '旧缓存作业',
      'courseName': '课程',
      'deadlineAt': now.add(const Duration(days: 1)).toIso8601String(),
      'remainingText': '1天',
      'urgencyLevel': 'normal',
      'deepLinkUrl': 'studyassistant:///assignments/9',
    };
    final legacy = WidgetSnapshotItem.fromJson(base);
    final unknown = WidgetSnapshotItem.fromJson({
      ...base,
      'deadlineSource': 'custom_future',
    });
    final manual = WidgetSnapshotItem.fromJson({
      ...base,
      'deadlineSource': 'manual',
    });

    expect(legacy.deadlineSource, 'official');
    expect(legacy.isManualDeadline, isFalse);
    expect(unknown.deadlineSource, 'official');
    expect(manual.deadlineSource, 'manual');
    expect(manual.isManualDeadline, isTrue);
    expect(manual.toJson()['deadlineSource'], 'manual');
  });

  test(
      'Stage 2 manual deadline/completion and Stage 3 active term catalog govern widget snapshots',
      () async {
    final fixedNow = DateTime.utc(2026, 11, 20, 4); // 12:00 Beijing (2026-fall)
    final snapshot = _Snapshot(clock: () => fixedNow);
    final unconfirmedWork = Assignment(
      id: 'cx:work:1:10:1',
      courseName: '高等数学',
      title: '待确认截止作业',
      deadlineAt: null,
      deadlineTrusted: false,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: fixedNow,
    );
    final archivedWork = Assignment(
      id: 'cx:work:2:20:1',
      courseName: '往期历史',
      title: '往期未完成',
      deadlineAt: null,
      deadlineTrusted: false,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: fixedNow,
    );
    final recalledWork = Assignment(
      id: 'cx:work:3:30:1',
      courseName: '召回课程',
      title: '本学期延交补测',
      deadlineAt: fixedNow.add(const Duration(days: 2)),
      deadlineTrusted: true,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: fixedNow,
    );
    final manualAt = fixedNow.add(const Duration(hours: 6)); // 18:00 Beijing
    final coursework = LocalCourseworkState(entries: {
      'cx:work:1:10:1': LocalCourseworkEntry(manualDeadlineAt: manualAt),
    });
    const activeCourse = CourseRef(
      courseId: '1',
      clazzId: '10',
      name: '高等数学',
      folderName: '2026年秋',
    );
    const archivedCourse = CourseRef(
      courseId: '2',
      clazzId: '20',
      name: '往期历史',
      folderName: '2025年秋',
    );
    const recalledCourse = CourseRef(
      courseId: '3',
      clazzId: '30',
      name: '召回课程',
      folderName: '2025年秋',
    );
    final allRows = [unconfirmedWork, archivedWork, recalledWork];
    final catalog = CourseTermCatalog.build(
      courses: const [activeCourse, archivedCourse, recalledCourse],
      assignments: allRows,
      notices: const [],
      preferences: const CourseTermPreferences.empty(),
      now: fixedNow,
      coursework: coursework,
    );
    expect(catalog.isArchived('2:20'), isTrue);
    expect(catalog.isRecalled('3:30'), isTrue);

    final widgetRows = const DisplayPreferences(widgetRange: WidgetRange.today)
        .forWidget(allRows, fixedNow, coursework: coursework);
    expect(widgetRows.map((a) => a.id), contains('cx:work:1:10:1'));

    snapshot.courseworkState = coursework;
    snapshot.termCatalog = catalog;
    await snapshot.saveAssignmentsForContext(
      allRows,
      authenticated: true,
      range: WidgetRange.week,
    );
    expect(snapshot.lastSavedTotalCount, 2);
    final byId = {for (final item in snapshot.items) item.assignmentId: item};
    expect(byId.keys, containsAll(['cx:work:1:10:1', 'cx:work:3:30:1']));
    expect(byId.containsKey('cx:work:2:20:1'), isFalse);

    final manualItem = byId['cx:work:1:10:1']!;
    expect(manualItem.deadlineSource, 'manual');
    expect(manualItem.deadlineAt!.toUtc(), manualAt.toUtc());
    expect(manualItem.toJson()['deadlineText'], '11月20日 18:00');
    expect(manualItem.remainingText, '6小时');

    // Official takeover + local completion both update widget projection cleanly.
    final overtakenCoursework = LocalCourseworkState(entries: {
      'cx:work:1:10:1': LocalCourseworkEntry(
        manualDeadlineAt: manualAt,
        officialTakenOver: true,
      ),
      'cx:work:3:30:1': const LocalCourseworkEntry(locallyCompleted: true),
    });
    final officialWork = Assignment(
      id: 'cx:work:1:10:1',
      courseName: '高等数学',
      title: '待确认截止作业',
      deadlineAt: fixedNow.add(const Duration(hours: 10)),
      deadlineTrusted: true,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: fixedNow,
    );
    snapshot.courseworkState = overtakenCoursework;
    snapshot.termCatalog = catalog;
    await snapshot.saveAssignmentsForContext(
      [officialWork, recalledWork],
      authenticated: true,
      range: WidgetRange.all,
    );
    expect(snapshot.lastSavedTotalCount, 1);
    expect(snapshot.items.single.assignmentId, 'cx:work:1:10:1');
    expect(snapshot.items.single.deadlineSource, 'official');
    expect(snapshot.items.single.toJson()['deadlineText'], '11月20日 22:00');
  });

  test(
      'AssignmentStore updates widget on manual reschedule, local complete, archive/recall/dismiss, backup restore, account switch, and failed restore',
      () async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final fixedNow = DateTime.utc(2026, 11, 20, 4);
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('A');
    const activeCourse = CourseRef(
      courseId: '1',
      clazzId: '2',
      name: '高等数学',
      folderName: '2026年秋',
    );
    const pastCourse = CourseRef(
      courseId: '2',
      clazzId: '20',
      name: '往期物理',
      folderName: '2025年秋',
    );
    final work1 = Assignment(
      id: 'cx:work:1:2:u1',
      courseName: '高等数学',
      title: '待定截止作业',
      deadlineAt: null,
      deadlineTrusted: false,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: fixedNow,
    );
    final work2 = Assignment(
      id: 'cx:work:1:2:backup1',
      courseName: '高等数学',
      title: '备份还原作业',
      deadlineAt: null,
      deadlineTrusted: false,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: fixedNow,
    );
    final recalledWork = Assignment(
      id: 'cx:work:2:20:r1',
      courseName: '往期物理',
      title: '召回测试',
      deadlineAt: fixedNow.add(const Duration(days: 2)),
      deadlineTrusted: true,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: fixedNow,
    );
    await repo.saveCourses(const [activeCourse, pastCourse], account: 'A');
    await repo.mergeAndSave([work1, work2, recalledWork], completeSync: true);

    final widget = _Snapshot(clock: () => fixedNow);
    final store = AssignmentStore(
      repository: repo,
      sessionStore: f.Session(),
      notificationService: f.Notifications(),
      widgetSnapshotService: widget,
      chaoxingClient: f.Client(),
      clock: () => fixedNow,
    );
    addTearDown(store.dispose);

    await store.restoreSession();
    expect(widget.items.map((e) => e.assignmentId),
        containsAll(['cx:work:1:2:u1', 'cx:work:2:20:r1']));

    // 1. Manual deadline -> marks snapshot item manual with resolved time.
    final manualAt = fixedNow.add(const Duration(hours: 8));
    expect(await store.setManualDeadline(work1, manualAt), isTrue);
    final afterManual =
        widget.items.singleWhere((e) => e.assignmentId == 'cx:work:1:2:u1');
    expect(afterManual.deadlineSource, 'manual');
    expect(afterManual.deadlineAt!.toUtc(), manualAt.toUtc());

    // 2. Local completion -> removes from widget snapshot.
    expect(await store.setLocallyCompleted(work1, true), isTrue);
    expect(
      widget.items.any((e) => e.assignmentId == 'cx:work:1:2:u1'),
      isFalse,
    );

    // 3. Dismiss recall -> archived course disappears from widget; manual restore brings it back.
    expect(await store.dismissCourseRecall(pastCourse.key), isTrue);
    expect(
      widget.items.any((e) => e.assignmentId == 'cx:work:2:20:r1'),
      isFalse,
    );
    expect(
      await store.setCourseArchiveMode(
          pastCourse.key, CourseArchiveMode.restored),
      isTrue,
    );
    expect(
      widget.items.any((e) => e.assignmentId == 'cx:work:2:20:r1'),
      isTrue,
    );

    // 4. Backup restore re-projects coursework state to widget.
    final backupManualAt = fixedNow.add(const Duration(hours: 12));
    expect(await store.setManualDeadline(work2, backupManualAt), isTrue);
    final backup = await repo.createBackupSnapshot('A');
    expect(await store.setManualDeadline(work2, null), isTrue);
    expect(
      widget.items
          .singleWhere((e) => e.assignmentId == 'cx:work:1:2:backup1')
          .deadlineSource,
      'official',
    );
    expect(await store.restoreLocalBackup(backup), isTrue);
    expect(
      widget.items
          .singleWhere((e) => e.assignmentId == 'cx:work:1:2:backup1')
          .deadlineSource,
      'manual',
    );

    // 5. Account switch clears old account widget snapshot before B writes anything.
    widget.history.clear();
    await store.loginChaoxing(
      account: 'B',
      password: 'dummy',
      agreementAccepted: true,
    );
    await store.syncAssignments();
    expect(widget.history.first.authenticated, isFalse);
    expect(widget.history.first.items, isEmpty);
    expect(widget.history.last.authenticated, isTrue);
    expect(
      widget.items.any((e) => e.assignmentId == 'cx:work:1:2:backup1'),
      isFalse,
    );

    // 6. Failed restoreSession fail-closes widget cache without throwing.
    final brokenWidget = _Snapshot(clock: () => fixedNow);
    final brokenStore = AssignmentStore(
      repository: _BrokenRestoreRepo(),
      sessionStore: f.Session(),
      notificationService: f.Notifications(),
      widgetSnapshotService: brokenWidget,
      chaoxingClient: f.Client(),
      clock: () => fixedNow,
    );
    addTearDown(brokenStore.dispose);
    await brokenStore.restoreSession();
    expect(brokenStore.isAuthenticated, isFalse);
    expect(brokenWidget.saveCalls, greaterThanOrEqualTo(1));
    expect(brokenWidget.lastSavedAuthenticated, isFalse);
    expect(brokenWidget.items, isEmpty);
  });
}

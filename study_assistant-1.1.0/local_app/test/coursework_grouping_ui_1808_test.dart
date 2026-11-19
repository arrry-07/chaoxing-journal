import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:study_assistant_mobile/src/features/local_records_screen.dart';
import 'package:study_assistant_mobile/src/features/profile_screen.dart';
import 'package:study_assistant_mobile/src/features/stats_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

Assignment _exam({
  required String id,
  required String examId,
  String? related,
  bool notice = false,
  required String title,
  String status = 'unknown',
}) =>
    Assignment(
      id: id,
      source: AssignmentSource.exam,
      exam: ExamInfo(
        examId: examId,
        relatedExamId: related,
        courseId: '1',
        clazzId: '2',
        startAt: DateTime.utc(2026, 11, 20, 1),
        endAt: DateTime.utc(2026, 11, 20, 2),
        startTrusted: !notice,
        endTrusted: !notice,
        lifecycle: notice ? 'unknown' : 'scheduled',
        noticeOnly: notice,
      ),
      courseName: '高等数学',
      title: title,
      deadlineAt: null,
      requirementsText: '',
      status: status,
      lastSyncedAt: DateTime.utc(2026, 11, 16, 8),
    );

AssignmentStore _store() => AssignmentStore(
      sessionStore: SecureSessionStore(),
      notificationService: LocalNotificationService(),
      widgetSnapshotService: WidgetSnapshotService(),
    );

void main() {
  final formal = _exam(
    id: 'cx:exam:1:2:3',
    examId: '3',
    title: '高等数学期末考试',
  );
  final noticeA = _exam(
    id: 'cx:examNotice:inbox:801',
    examId: '801',
    related: '3',
    notice: true,
    title: '考试通知 A',
  );
  final noticeB = _exam(
    id: 'cx:examNotice:inbox:802',
    examId: '802',
    related: '3',
    notice: true,
    title: '考试通知 B',
  );
  final work = Assignment(
    id: 'cx:work:1:2:ui',
    courseName: '大学英语',
    title: '章节作业',
    deadlineAt: DateTime.utc(2026, 11, 30, 10),
    requirementsText: '',
    status: 'pending',
    lastSyncedAt: DateTime.utc(2026, 11, 16, 8),
  );

  testWidgets('local records count one exam group and show source count',
      (tester) async {
    final store = _store();
    addTearDown(store.dispose);
    store.replaceAssignmentsForTest([formal, noticeA, noticeB, work]);

    await tester.pumpWidget(
      MaterialApp(home: LocalRecordsScreen(store: store)),
    );

    expect(find.text('2 条记录'), findsOneWidget);
    expect(find.textContaining('考试 · 3 条来源'), findsOneWidget);
    expect(find.text('章节作业'), findsOneWidget);
  });

  testWidgets('statistics use one raw primary per exam group', (tester) async {
    final store = _store();
    addTearDown(store.dispose);
    store.replaceAssignmentsForTest([formal, noticeA, noticeB, work]);
    final now = DateTime.utc(2026, 11, 16, 8);

    await tester.pumpWidget(
      MaterialApp(home: StatsScreen(store: store, clock: () => now)),
    );

    expect(find.text('共 2 项课业'), findsOneWidget);
    expect(find.text('提交未知 1 份'), findsOneWidget);
    expect(find.text('待完成 1 份'), findsOneWidget);
  });

  testWidgets('profile summary counts grouped coursework', (tester) async {
    final store = _store();
    addTearDown(store.dispose);
    store.replaceAssignmentsForTest([formal, noticeA, noticeB, work]);

    await tester.pumpWidget(MaterialApp(home: ProfileScreen(store: store)));
    await tester.scrollUntilVisible(find.text('学习记录'), 300);

    expect(find.text('2 项课业 · 0 条变化'), findsOneWidget);
    expect(find.textContaining('3 条作业'), findsNothing);
  });

  testWidgets('detail page exposes every original source read-only',
      (tester) async {
    final store = _store();
    addTearDown(store.dispose);
    store.replaceAssignmentsForTest([formal, noticeA, noticeB, work]);

    await tester.pumpWidget(MaterialApp(
      home: AssignmentDetailScreen(
        store: store,
        assignmentId: formal.id,
        clock: () => DateTime.utc(2026, 11, 16, 8),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('assignment-source-records')));
    await tester.pumpAndSettle();

    expect(find.text('正式考试 · 未开始'), findsOneWidget);
    expect(find.textContaining('考试通知'), findsNWidgets(2));
    expect(find.text('查看'), findsNWidgets(3));
    await tester.tap(find.text('查看').first);
    await tester.pumpAndSettle();
    expect(find.text('原始来源详情'), findsOneWidget);
  });
}

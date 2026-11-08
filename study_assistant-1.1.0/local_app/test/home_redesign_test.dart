import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/stats_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/features/widgets/completion_pie_chart.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Store extends AssignmentStore {
  _Store()
      : super(
            sessionStore: SecureSessionStore(),
            notificationService: LocalNotificationService(),
            widgetSnapshotService: WidgetSnapshotService());
  int syncCalls = 0;
  int testEpoch = 0;
  @override
  int get accountEpoch => testEpoch;
  @override
  Future<void> syncAssignments() async {
    syncCalls++;
  }

  void changed() => notifyListeners();
}

Assignment work(int i,
        {String status = 'pending', DateTime? due, String? title}) =>
    Assignment(
        id: 'cx:work:1:${i.isEven ? '8888' : '9999'}:$i',
        courseName: '高等数学2（下）',
        title: title ?? '作业$i',
        deadlineAt: due,
        requirementsText: '',
        status: status,
        lastSyncedAt: DateTime.now());
void main() {
  testWidgets(
      'expanded cards share exact list bounds and keep numeric course titles',
      (t) async {
    final s = _Store()
      ..replaceAssignmentsForTest(
          [work(0, title: '短题'), work(1, title: '这是一份明显更长的实验报告标题与阅读任务')]);
    addTearDown(s.dispose);
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: AssignmentListScreen(store: s))));
    await t.pumpAndSettle();
    final cards = find.byType(AssignmentCard);
    expect(cards, findsNWidgets(2));
    final first = t.getRect(cards.first), last = t.getRect(cards.last);
    expect((first.left - last.left).abs(), lessThanOrEqualTo(1));
    expect((first.right - last.right).abs(), lessThanOrEqualTo(1));
    expect(first.width, greaterThan(700));
    expect(find.text('高等数学2（下）'), findsNWidgets(2));
    expect(find.textContaining('班级'), findsNothing);
    expect(s.assignments.first.courseKey, '1:8888');
    expect(find.textContaining('未来30天暂无'), findsNothing);
    s.changed();
    await t.pumpAndSettle();
    expect(find.text('短题'), findsOneWidget);
  });
  testWidgets('retry performs sync and running state disables refresh',
      (t) async {
    final s = _Store()
      ..syncReport = const SyncReport(
          phase: SyncPhase.failed,
          issues: [SyncIssue(SyncIssueKind.network, 'fixture')]);
    addTearDown(s.dispose);
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: AssignmentListScreen(store: s))));
    await t.tap(find.byTooltip('刷新作业'));
    expect(s.syncCalls, 1);
    s.syncReport = const SyncReport(phase: SyncPhase.running);
    s.changed();
    await t.pump();
    expect(find.text('重试'), findsNothing);
    expect(
        t
            .widget<IconButton>(find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '刷新作业'))
            .onPressed,
        isNull);
  });
  testWidgets('home supports search deadline filters and visible freshness',
      (t) async {
    final now = DateTime.now();
    final s = _Store()
      ..replaceAssignmentsForTest([
        work(1, title: '高等数学练习', due: now.add(const Duration(days: 2))),
        work(2, title: 'English Essay', due: now.add(const Duration(days: 20))),
        work(3, title: '逾期的实验报告', due: now.subtract(const Duration(days: 1))),
        work(4, title: '待确认作业', status: 'unknown'),
      ])
      ..syncReport = SyncReport(
          phase: SyncPhase.success,
          lastDataSuccessAt: now.subtract(const Duration(hours: 25)));
    addTearDown(s.dispose);
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: AssignmentListScreen(store: s))));
    await t.pumpAndSettle();

    final updated = now.subtract(const Duration(hours: 25)).toLocal();
    final freshness =
        '${updated.hour.toString().padLeft(2, '0')}:${updated.minute.toString().padLeft(2, '0')} 更新 · 超过24小时未更新';
    expect(find.text(freshness), findsOneWidget);

    await t.tap(find.text('搜索与筛选'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'English');
    await t.tap(find.text('应用'));
    await t.pumpAndSettle();
    expect(find.text('English Essay'), findsOneWidget);
    expect(find.text('高等数学练习'), findsNothing);

    await t.tap(find.text('已筛选'));
    await t.pumpAndSettle();
    await t.tap(find.text('7天内'));
    await t.tap(find.text('应用'));
    await t.pumpAndSettle();
    expect(find.text('没有符合搜索或期限条件的作业'), findsOneWidget);
    expect(find.text('English Essay'), findsNothing);

    await t.tap(find.text('已筛选'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '');
    await t.tap(find.text('应用'));
    await t.pumpAndSettle();
    expect(find.text('高等数学练习'), findsOneWidget);
    expect(find.text('逾期的实验报告'), findsNothing);
    expect(find.text('待确认作业'), findsNothing);

    await t.tap(find.text('已筛选'));
    await t.pumpAndSettle();
    await t.tap(find.text('已逾期'));
    await t.tap(find.text('应用'));
    await t.pumpAndSettle();
    expect(find.text('逾期的实验报告'), findsOneWidget);
    expect(find.text('高等数学练习'), findsNothing);

    await t.tap(find.text('已筛选'));
    await t.pumpAndSettle();
    await t.tap(find.text('期限待确认'));
    await t.tap(find.text('应用'));
    await t.pumpAndSettle();
    expect(find.text('待确认作业'), findsOneWidget);
    expect(find.text('逾期的实验报告'), findsNothing);

    s.testEpoch++;
    s.changed();
    await t.pump();
    expect(find.text('搜索与筛选'), findsOneWidget);
    expect(find.text('高等数学练习'), findsOneWidget);
    expect(find.text('English Essay'), findsOneWidget);
  });
  testWidgets(
      'statistics keep same-name classes separate and no fake empty percentage',
      (t) async {
    final s = _Store();
    addTearDown(s.dispose);
    await t
        .pumpWidget(MaterialApp(home: Scaffold(body: StatsScreen(store: s))));
    expect(find.text('暂无可统计的作业'), findsOneWidget);
    expect(find.byType(CompletionPieChart), findsNothing);
    s.replaceAssignmentsForTest([work(0), work(1, status: 'unknown')]);
    s.changed();
    await t.pump();
    expect(find.text('高等数学2（下） · 分组1'), findsOneWidget);
    expect(find.text('高等数学2（下） · 分组2'), findsOneWidget);
    expect(find.byType(CompletionPieChart), findsOneWidget);
    s.replaceAssignmentsForTest([work(0, status: 'unknown')]);
    s.changed();
    await t.pump();
    expect(find.text('全部状态待确认'), findsOneWidget);
  });
}

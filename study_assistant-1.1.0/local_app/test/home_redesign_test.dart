import 'package:flutter/material.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/stats_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/features/widgets/completion_pie_chart.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/assignment_sync_progress.dart';
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
  List<Assignment> previewAssignments = [];
  AssignmentSyncProgress? previewProgress;
  Set<String> previewOnlyIds = {};
  Set<String> pendingIds = {};
  @override
  int get accountEpoch => testEpoch;
  @override
  List<Assignment> get homeDisplayAssignments => previewAssignments.isEmpty
      ? super.homeDisplayAssignments
      : previewAssignments;
  @override
  AssignmentSyncProgress? get homeSyncProgress => previewProgress;
  @override
  bool isHomeAssignmentPreviewOnly(String assignmentId) =>
      previewOnlyIds.contains(assignmentId);
  @override
  bool isHomeDeadlinePending(String assignmentId) =>
      pendingIds.contains(assignmentId);
  @override
  Future<void> syncAssignments() async {
    syncCalls++;
  }

  @override
  Future<bool> saveHomeFilters(HomeFilters next, int expectedEpoch) async {
    homeFilters = next;
    notifyListeners();
    return true;
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

Future<void> tapSheetOption(WidgetTester tester, String label) async {
  final target = find.text(label);
  if (label == '应用') {
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

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
    await t.pump();
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
    await tapSheetOption(t, '应用');
    expect(find.text('English Essay'), findsOneWidget);
    expect(find.text('高等数学练习'), findsNothing);

    await t.tap(find.text('已筛选'));
    await t.pumpAndSettle();
    await tapSheetOption(t, '已逾期');
    await tapSheetOption(t, '应用');
    expect(find.text('没有符合搜索或期限条件的作业'), findsOneWidget);
    expect(find.text('English Essay'), findsNothing);

    await t.tap(find.text('已筛选'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '');
    await tapSheetOption(t, '应用');
    expect(find.text('高等数学练习'), findsNothing);
    expect(find.text('逾期的实验报告'), findsOneWidget);
    expect(find.text('待确认作业'), findsNothing);

    await t.tap(find.text('已筛选'));
    await t.pumpAndSettle();
    await tapSheetOption(t, '未截止');
    await tapSheetOption(t, '应用');
    expect(find.text('高等数学练习'), findsOneWidget);
    expect(find.text('English Essay'), findsOneWidget);
    expect(find.text('逾期的实验报告'), findsNothing);
    expect(find.text('待确认作业'), findsNothing);

    await t.tap(find.text('已筛选'));
    await t.pumpAndSettle();
    await tapSheetOption(t, '全部');
    await tapSheetOption(t, '应用');
    expect(find.text('高等数学练习'), findsOneWidget);
    expect(find.text('English Essay'), findsOneWidget);
    await t.scrollUntilVisible(find.text('逾期的实验报告'), 180);
    expect(find.text('逾期的实验报告'), findsOneWidget);
    await t.scrollUntilVisible(find.text('待确认作业'), 180);
    expect(find.text('待确认作业'), findsOneWidget);
    expect(find.text('状态或截止待确认'), findsWidgets);
    expect(find.text('需要确认'), findsNothing);
    await t.scrollUntilVisible(find.text('今日计划'), -180);

    s.testEpoch++;
    s.homeFilters = const HomeFilters();
    s.changed();
    await t.pump();
    expect(find.text('搜索与筛选'), findsOneWidget);
    expect(find.text('高等数学练习'), findsOneWidget);
    expect(find.text('English Essay'), findsOneWidget);
  });

  testWidgets(
      'title sort uses one full-deadline list and survives clearing filters',
      (t) async {
    final now = DateTime.now();
    final alpha =
        work(1, title: 'Alpha 作业', due: now.add(const Duration(days: 2)));
    final mike =
        work(2, title: 'Mike 作业', due: now.add(const Duration(days: 1)));
    final zulu =
        work(3, title: 'Zulu 作业', due: now.add(const Duration(days: 10)));
    final s = _Store()..replaceAssignmentsForTest([zulu, mike, alpha]);
    addTearDown(s.dispose);
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1000, 2000);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: AssignmentListScreen(store: s))));
    await t.pumpAndSettle();

    await t.tap(find.text('搜索与筛选'));
    await t.pumpAndSettle();
    expect(find.text('搜索、筛选与排序'), findsOneWidget);
    for (final label in [
      '默认分组',
      '截止时间：近到远',
      '截止时间：远到近',
      '课程名称',
      '作业名称',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    await tapSheetOption(t, '作业名称');
    await tapSheetOption(t, '应用');

    expect(s.homeFilters.sortOrder, HomeSortOrder.title);
    expect(find.byKey(const ValueKey('current-home-sort')), findsOneWidget);
    expect(find.text('作业名称'), findsOneWidget);
    expect(find.text('已筛选'), findsNothing);
    expect(find.text('搜索与筛选'), findsOneWidget);
    expect(
        t
            .widgetList<AssignmentCard>(find.byType(AssignmentCard))
            .every((card) => !card.showFullDeadline),
        isTrue);

    final alphaTop =
        t.getTopLeft(find.byKey(ValueKey('assignment-${alpha.id}'))).dy;
    final mikeTop =
        t.getTopLeft(find.byKey(ValueKey('assignment-${mike.id}'))).dy;
    final zuluTop =
        t.getTopLeft(find.byKey(ValueKey('assignment-${zulu.id}'))).dy;
    expect(alphaTop, lessThan(mikeTop));
    expect(mikeTop, lessThan(zuluTop));
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Text &&
            RegExp(r'^\d+月\d+日 周[一二三四五六日]$').hasMatch(widget.data ?? '')),
        findsNWidgets(3));

    await t.tap(find.text('搜索与筛选'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '不存在');
    await tapSheetOption(t, '应用');
    expect(find.text('已筛选'), findsOneWidget);
    expect(find.text('没有符合搜索或期限条件的作业'), findsOneWidget);

    await t.tap(find.text('清除搜索与期限条件'));
    await t.pumpAndSettle();
    expect(s.homeFilters.query, '');
    expect(s.homeFilters.sortOrder, HomeSortOrder.title);
    expect(find.text('Alpha 作业'), findsOneWidget);
    expect(find.text('Mike 作业'), findsOneWidget);
    expect(find.text('Zulu 作业'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('home preview distinguishes pending, saving and openable rows',
      (t) async {
    final pending = work(7, title: '新同步作业');
    final s = _Store()
      ..syncReport = const SyncReport(phase: SyncPhase.running)
      ..previewAssignments = [pending]
      ..previewOnlyIds = {pending.id}
      ..pendingIds = {pending.id}
      ..previewProgress = AssignmentSyncProgress(
        stage: AssignmentSyncStage.details,
        assignments: [pending],
        pendingDetailIds: {pending.id},
        resolvedCount: 1,
        attemptedCount: 2,
      );
    addTearDown(s.dispose);
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: AssignmentListScreen(store: s))));
    await t.pump();

    expect(find.text('正在确认截止时间，已处理 1 项详情'), findsOneWidget);
    expect(find.text('正在确认截止时间'), findsOneWidget);
    final card = t.widget<AssignmentCard>(find.byType(AssignmentCard));
    expect(card.deadlinePending, isTrue);
    expect(card.previewOnly, isTrue);
    expect(card.previewSaving, isFalse);
    await t.tap(find.text('待保存预览'));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.byType(AssignmentListScreen), findsOneWidget);

    final saved = pending.copyWith(
      deadlineAt: DateTime.now().add(const Duration(days: 1)),
      deadlineTrusted: true,
    );
    s
      ..previewAssignments = [saved]
      ..previewOnlyIds = {saved.id}
      ..pendingIds = {}
      ..previewProgress = AssignmentSyncProgress(
        stage: AssignmentSyncStage.saving,
        assignments: [saved],
        pendingDetailIds: const {},
        resolvedCount: 2,
        attemptedCount: 2,
      )
      ..changed();
    await t.pump();
    expect(find.text('正在保存作业'), findsOneWidget);
    expect(find.text('正在保存到本机'), findsOneWidget);
    expect(find.text('正在确认截止时间'), findsNothing);
    expect(
      t.widget<AssignmentCard>(find.byType(AssignmentCard)).previewSaving,
      isTrue,
    );
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

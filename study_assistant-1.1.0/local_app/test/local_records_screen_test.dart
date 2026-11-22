import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_grouped_card.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_sliver_grouped_card.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:study_assistant_mobile/src/features/local_records_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/local_record_query.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';
import 'review_core_remediation_test.dart' as f;

class _Notifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}
}

class _Widgets extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

final _recordsNow = DateTime.utc(2026, 11, 17, 2);

Assignment _record(String title, int index, {bool otherSource = false}) =>
    Assignment(
      id: otherSource ? 'cx:activity:1:2:$index' : 'cx:work:1:2:w$index',
      source: otherSource
          ? AssignmentSource.classroomActivity
          : AssignmentSource.courseWork,
      activityType: otherSource ? 99 : null,
      courseName: '大学物理',
      title: title,
      deadlineAt: _recordsNow.add(Duration(days: index + 1)),
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: _recordsNow,
    );

Future<AssignmentStore> _recordsStore(List<Assignment> records) async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  final store = AssignmentStore(
    sessionStore: f.Session(),
    notificationService: _Notifications(),
    widgetSnapshotService: _Widgets(),
  );
  addTearDown(store.dispose);
  await store.restoreSession();
  store.replaceAssignmentsForTest(records);
  return store;
}

Future<AssignmentStore> _searchStore() => _recordsStore([
      _record('牛顿力学实验', 1),
      _record('热学测验', 2),
    ]);

Widget _recordsApp(
  AssignmentStore store, {
  LocalRecordFilterSpec initialFilter = const LocalRecordFilterSpec(),
}) =>
    MaterialApp(
      theme: StudyAssistantTheme.light,
      home: LocalRecordsScreen(
        store: store,
        clock: () => _recordsNow,
        initialFilter: initialFilter,
      ),
    );

void _expectRecordsDividerBetween(
  WidgetTester tester,
  Finder upperTitle,
  Finder lowerTitle,
) {
  final upper = tester.getRect(upperTitle).bottom;
  final lower = tester.getRect(lowerTitle).top;
  final dividers = find.byType(Divider).evaluate().where((element) {
    final divider = element.widget as Divider;
    final rect = tester.getRect(find.byElementPredicate((e) => e == element));
    return divider.height == 0.6 &&
        divider.thickness == 0.6 &&
        divider.indent == 52 &&
        divider.endIndent == 16 &&
        rect.top >= upper &&
        rect.bottom <= lower;
  });
  expect(dividers, hasLength(1));
}

const _paintWidth = 144;
const _paintScale = 5;

Widget _cardPaintFixture(Key key, Widget sliver) => RepaintBoundary(
      key: key,
      child: SizedBox(
        width: _paintWidth.toDouble(),
        height: 140,
        child: CustomScrollView(
          primary: false,
          slivers: [
            SliverPadding(padding: const EdgeInsets.all(4), sliver: sliver),
          ],
        ),
      ),
    );

Future<ByteData> _paintBytes(WidgetTester tester, Key key) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final image = await boundary.toImage(pixelRatio: _paintScale.toDouble());
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
  }
}

int _paintPixel(ByteData bytes, Offset point) {
  final x = (point.dx * _paintScale).floor();
  final y = (point.dy * _paintScale).floor();
  return bytes.getUint32((y * _paintWidth * _paintScale + x) * 4);
}

void main() {
  testWidgets(
      'local records screen supports source tabs, status chips, reset banner and detail restore of hidden item',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: f.Session(),
      notificationService: _Notifications(),
      widgetSnapshotService: _Widgets(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    final now = DateTime.utc(2026, 11, 17, 2);
    final pendingWork = Assignment(
      id: 'cx:work:1:2:w1',
      courseName: '大学物理',
      title: '牛顿力学实验',
      deadlineAt: now.add(const Duration(days: 2)),
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
    );
    final completedWork = Assignment(
      id: 'cx:work:1:2:w2',
      courseName: '大学物理',
      title: '热学测验',
      deadlineAt: now.add(const Duration(days: 3)),
      requirementsText: '',
      status: 'submitted',
      lastSyncedAt: now,
    );
    final hiddenExam = Assignment(
      id: 'cx:exam:1:3:301',
      source: AssignmentSource.exam,
      courseName: '线性代数',
      title: '线代期中考试',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
      exam: ExamInfo(
        examId: '301',
        courseId: '1',
        clazzId: '3',
        startAt: now.add(const Duration(days: 5)),
        startTrusted: true,
        lifecycle: 'scheduled',
      ),
    );
    final hiddenExamNotice = Assignment(
      id: 'cx:examNotice:inbox:901',
      source: AssignmentSource.exam,
      courseName: '线性代数',
      title: '线代期中考试通知',
      deadlineAt: null,
      requirementsText: '请到主教学楼201参加',
      status: 'unknown',
      lastSyncedAt: now,
      exam: const ExamInfo(
        examId: '901',
        relatedExamId: '301',
        courseId: '1',
        clazzId: '3',
        noticeOnly: true,
        location: '主教学楼201',
      ),
    );
    final unsupported = Assignment(
      id: 'cx:activity:1:2:999',
      source: AssignmentSource.classroomActivity,
      activityType: 99,
      courseName: '大学物理',
      title: '其他课堂活动',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
    );

    await store.repository.mergeAndSave([
      pendingWork,
      completedWork,
      hiddenExam,
      hiddenExamNotice,
      unsupported,
    ]);
    await store.refreshAssignments();
    await store
        .setAssignmentsHidden([hiddenExam.id, hiddenExamNotice.id], true);

    final router = GoRouter(
      initialLocation: '/records?from=stats&scope=followedStats&status=pending',
      routes: [
        ShellRoute(
          builder: (_, __, child) => AppShell(
            assignmentStore: store,
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/records',
              builder: (_, state) => LocalRecordsScreen(
                store: store,
                initialFilter: LocalRecordFilterSpec.fromQueryParameters(
                  state.uri.queryParameters,
                ),
                clock: () => now,
              ),
            ),
            GoRoute(
              path: '/assignments/:id',
              builder: (_, state) => AssignmentDetailScreen(
                store: store,
                assignmentId: state.pathParameters['id']!,
                clock: () => now,
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: StudyAssistantTheme.light,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    // Scoped entry from stats keeps count 1 (pendingWork), hides completedWork & unsupported.
    expect(find.text('1 条记录'), findsOneWidget);
    expect(find.text('牛顿力学实验'), findsOneWidget);
    expect(find.text('热学测验'), findsNothing);
    expect(find.text('其他课堂活动'), findsNothing);
    expect(find.text('查看全部本机记录'), findsOneWidget);

    final listScrollable = find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axis == Axis.vertical,
    );

    // Reset shows all 2 non-hidden coursework groups, still excluding unsupported.
    await tester.tap(find.text('查看全部本机记录'));
    await tester.pumpAndSettle();
    expect(find.text('2 条记录'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('热学测验'),
      150,
      scrollable: listScrollable,
    );
    expect(find.text('热学测验'), findsOneWidget);
    expect(find.text('其他课堂活动'), findsNothing);

    // Filter by status chip '已完成' shows only 热学测验.
    await tester.scrollUntilVisible(
      find.text('已完成'),
      -150,
      scrollable: listScrollable,
    );
    await tester.tap(find.text('已完成'));
    await tester.pumpAndSettle();
    expect(find.text('1 条记录'), findsOneWidget);
    expect(find.text('热学测验'), findsOneWidget);
    expect(find.text('牛顿力学实验'), findsNothing);

    // Source isolation: unsupported only under 历史与其他来源.
    await tester.tap(find.text('历史与其他来源'));
    await tester.pumpAndSettle();
    expect(find.text('1 条记录'), findsOneWidget);
    expect(find.text('其他课堂活动'), findsOneWidget);

    // Hidden tab shows merged exam group, tapping opens detail with projection + restore.
    await tester.tap(find.text('已隐藏'));
    await tester.pumpAndSettle();
    expect(find.text('1 条记录'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('考试 · 2 条来源'),
      150,
      scrollable: listScrollable,
    );
    expect(find.text('线代期中考试'), findsOneWidget);
    expect(find.textContaining('考试 · 2 条来源'), findsOneWidget);

    await tester.tap(find.text('线代期中考试'));
    await tester.pumpAndSettle();

    expect(find.byType(AssignmentDetailScreen), findsOneWidget);
    expect(find.textContaining('当前课业已在本机隐藏'), findsOneWidget);
    expect(find.textContaining('地点 主教学楼201'), findsOneWidget);
    expect(find.text('安排每日计划'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('恢复到课业清单'),
      150,
      scrollable: listScrollable,
    );
    expect(find.text('恢复到课业清单'), findsOneWidget);
    await tester.tap(find.text('恢复到课业清单'));
    await tester.pumpAndSettle();

    expect(find.text('已恢复到课业清单'), findsOneWidget);
    expect(store.hiddenAssignments, isEmpty);
    expect(find.text('安排每日计划'), findsOneWidget);
  });

  testWidgets(
      'local records screen renders without overflow at 320w and 2x text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: f.Session(),
      notificationService: _Notifications(),
      widgetSnapshotService: _Widgets(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    final now = DateTime.utc(2026, 11, 17, 2);
    store.replaceAssignmentsForTest([
      Assignment(
        id: 'cx:work:1:2:w1',
        courseName: '概率论与数理统计（计算机类长课程名称）',
        title: '长标题用于测试窄屏二倍字号自动换行与零溢出展示',
        deadlineAt: now.add(const Duration(days: 2)),
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: LocalRecordsScreen(store: store, clock: () => now),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'local records screen clears scoped filters on account logout or change',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: f.Session(),
      notificationService: _Notifications(),
      widgetSnapshotService: _Widgets(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await tester.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: LocalRecordsScreen(
          store: store,
          initialFilter: const LocalRecordFilterSpec(
            from: 'stats',
            scope: LocalRecordScopeFilter.followedStats,
            courseKey: '1:2',
            query: 'old-query',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('查看全部本机记录'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'pending-query');
    await tester.pump(const Duration(milliseconds: 50));
    await store.logout();
    await tester.pumpAndSettle();
    expect(find.text('查看全部本机记录'), findsNothing);
    expect(find.text('0 条记录'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('本机暂未保存课业记录'), findsOneWidget);
  });

  testWidgets('local records search waits and filters only the latest input',
      (tester) async {
    final store = await _searchStore();
    await tester.pumpWidget(_recordsApp(store));
    expect(find.text('2 条记录'), findsOneWidget);

    final search = find.byType(TextField);
    await tester.enterText(search, '牛顿');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byTooltip('清除搜索'), findsOneWidget);
    expect(find.text('2 条记录'), findsOneWidget, reason: '输入 50 ms 后仍应显示未过滤的记录');

    await tester.enterText(search, '热学');
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.text('2 条记录'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 90));
    expect(find.text('1 条记录'), findsOneWidget);
    expect(find.text('热学测验'), findsOneWidget);
    expect(find.text('牛顿力学实验'), findsNothing);
  });

  for (final useScopeReset in [false, true]) {
    testWidgets(
        'local records ${useScopeReset ? 'scope reset' : 'search clear'} restores all rows immediately and cancels pending input',
        (tester) async {
      final store = await _searchStore();
      await tester.pumpWidget(_recordsApp(
        store,
        initialFilter: LocalRecordFilterSpec(
          from: useScopeReset ? 'stats' : null,
          query: '牛顿',
        ),
      ));
      expect(find.text('1 条记录'), findsOneWidget);
      expect(find.text('牛顿力学实验'), findsOneWidget);

      final search = find.byType(TextField);
      await tester.enterText(search, '不存在的记录');
      await tester.pump(const Duration(milliseconds: 50));
      await tester
          .tap(useScopeReset ? find.text('查看全部本机记录') : find.byTooltip('清除搜索'));
      await tester.pump();

      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      expect(find.byTooltip('清除搜索'), findsNothing);
      expect(find.text('2 条记录'), findsOneWidget);
      expect(find.text('热学测验'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('2 条记录'), findsOneWidget);
    });
  }

  testWidgets('local records new initial filter replaces pending search',
      (tester) async {
    final store = await _searchStore();
    await tester.pumpWidget(_recordsApp(store));
    await tester.enterText(find.byType(TextField), '牛顿');
    await tester.pump(const Duration(milliseconds: 50));

    await tester.pumpWidget(_recordsApp(
      store,
      initialFilter: const LocalRecordFilterSpec(query: '热学'),
    ));
    expect(find.text('热学测验'), findsOneWidget);
    expect(find.text('牛顿力学实验'), findsNothing);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('热学测验'), findsOneWidget);
    expect(find.text('牛顿力学实验'), findsNothing);
  });

  testWidgets('local records unmount cancels search before its delay elapses',
      (tester) async {
    final store = await _searchStore();
    await tester.pumpWidget(_recordsApp(store));
    await tester.enterText(find.byType(TextField), '牛顿');
    await tester.pump(const Duration(milliseconds: 50));

    await tester.pumpWidget(const SizedBox.shrink());
    expect(find.byType(LocalRecordsScreen), findsNothing);
    expect(tester.takeException(), isNull);
    // The widget test binding checks for pending timers when this test returns.
  });

  for (final category in [
    LocalRecordCategory.coursework,
    LocalRecordCategory.otherSources,
  ]) {
    testWidgets('local records ${category.label} loads 120 rows on demand',
        (tester) async {
      String title(int index) => '本地记录 ${index.toString().padLeft(3, '0')}';
      final store = await _recordsStore([
        for (var index = 1; index <= 120; index++)
          _record(
            title(index),
            index,
            otherSource: category == LocalRecordCategory.otherSources,
          ),
      ]);
      await tester.pumpWidget(_recordsApp(
        store,
        initialFilter: LocalRecordFilterSpec(
          category: category,
          sort: LocalRecordSortOrder.lastSyncedDesc,
        ),
      ));
      await tester.pumpAndSettle();

      final first = find.text(title(1));
      final last = find.text(title(120));
      expect(find.text('120 条记录'), findsOneWidget);
      expect(first.hitTestable(), findsOneWidget);
      _expectRecordsDividerBetween(tester, first, find.text(title(2)));
      expect(tester.takeException(), isNull);
      // Check the initial build after exercising the end of the list, too.
      final lastWasBuiltInitially = last.evaluate().isNotEmpty;

      await tester.scrollUntilVisible(
        last,
        420,
        maxScrolls: 40,
        scrollable: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axis == Axis.vertical,
        ),
      );
      await tester.pumpAndSettle();
      expect(last.hitTestable(), findsOneWidget);
      _expectRecordsDividerBetween(tester, find.text(title(119)), last);
      expect(tester.takeException(), isNull);
      expect(lastWasBuiltInitially, isFalse, reason: '第 120 行应在滚动接近末尾时才构建');
    });
  }

  for (final theme in [StudyAssistantTheme.light, StudyAssistantTheme.dark]) {
    for (final rowCount in [1, 3]) {
      testWidgets(
          'journal sliver card matches grouped card edges with $rowCount rows in ${theme.brightness.name}',
          (tester) async {
        const originalKey = ValueKey('original-card');
        const sliverKey = ValueKey('sliver-card');
        final dividerIndent =
            theme.brightness == Brightness.light ? 52.0 : 16.0;
        const row = SizedBox(height: 40);
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Row(
              children: [
                _cardPaintFixture(
                  originalKey,
                  SliverToBoxAdapter(
                    child: JournalGroupedCard(
                      dividerIndent: dividerIndent,
                      children: List.filled(rowCount, row),
                    ),
                  ),
                ),
                _cardPaintFixture(
                  sliverKey,
                  JournalSliverGroupedCard(
                    itemCount: rowCount,
                    itemBuilder: (_, __) => row,
                    dividerIndent: dividerIndent,
                  ),
                ),
              ],
            ),
          ),
        ));
        expect(tester.takeException(), isNull);

        final bottom = 4 + rowCount * 40 + (rowCount - 1) * 0.6;
        final probes = {
          'sheet': const Offset(72, 20),
          'top border': const Offset(72, 4.4),
          'below top border': const Offset(72, 5.1),
          'top-left clipped corner': const Offset(4.4, 4.4),
          'top-right clipped corner': const Offset(139.6, 4.4),
          'outside top-left arc': const Offset(10, 7),
          'inside top-right arc': const Offset(132, 8),
          'left border': const Offset(4.4, 24),
          'right border': const Offset(139.6, 24),
          'bottom border': Offset(72, bottom - 0.4),
          'above bottom border': Offset(72, bottom - 1.1),
          'bottom-left clipped corner': Offset(4.4, bottom - 0.4),
          'bottom-right clipped corner': Offset(139.6, bottom - 0.4),
          'inside bottom-left arc': Offset(12, bottom - 4),
          'outside bottom-right arc': Offset(134, bottom - 3),
          if (rowCount > 1) ...{
            'left border through first seam': const Offset(4.4, 44.3),
            'first divider': const Offset(72, 44.3),
            'before divider indent': Offset(4 + dividerIndent - 1, 44.3),
            'past divider end indent': const Offset(125, 44.3),
            'final divider': const Offset(72, 84.9),
            'right border through final seam': const Offset(139.6, 84.9),
          },
        };
        final comparison = await tester.runAsync(() async => (
              original: await _paintBytes(tester, originalKey),
              sliver: await _paintBytes(tester, sliverKey),
            ));
        final samples = comparison!;
        final sheet = _paintPixel(samples.original, probes['sheet']!);
        expect(
            _paintPixel(samples.original, probes['top border']!), isNot(sheet));
        if (rowCount > 1) {
          expect(_paintPixel(samples.original, probes['first divider']!),
              isNot(sheet));
        }
        for (final probe in probes.entries) {
          expect(_paintPixel(samples.sliver, probe.value),
              _paintPixel(samples.original, probe.value),
              reason: probe.key);
        }
      });
    }
  }

  testWidgets('journal sliver card preserves keyed expansion and icon actions',
      (tester) async {
    const rowKey = ValueKey('课题甲');
    final titles = ValueNotifier(['课题甲', '课题乙']);
    addTearDown(titles.dispose);
    var iconTaps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<List<String>>(
          valueListenable: titles,
          builder: (context, rows, _) => CustomScrollView(
            slivers: [
              JournalSliverGroupedCard(
                itemCount: rows.length,
                findChildIndexCallback: (key) {
                  final index = rows.indexOf((key as ValueKey<String>).value);
                  return index == -1 ? null : index;
                },
                itemBuilder: (context, index) {
                  final title = rows[index];
                  return ExpansionTile(
                    key: ValueKey(title),
                    title: Text(title),
                    trailing: IconButton(
                      tooltip: '$title 操作',
                      icon: const Icon(Icons.bookmark_border),
                      onPressed: () => iconTaps++,
                    ),
                    children: [Text('$title 详情')],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(rowKey));
    await tester.pumpAndSettle();
    expect(find.text('课题甲 详情'), findsOneWidget);

    titles.value = titles.value.reversed.toList();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('课题乙')).dy,
        lessThan(tester.getTopLeft(find.byKey(rowKey)).dy));
    expect(find.text('课题甲 详情'), findsOneWidget);
    await tester.tap(find.byTooltip('课题甲 操作'));
    expect(iconTaps, 1);
    expect(tester.takeException(), isNull);
  });
}

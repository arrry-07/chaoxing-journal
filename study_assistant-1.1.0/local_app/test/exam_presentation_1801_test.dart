import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/login_screen.dart';
import 'package:study_assistant_mobile/src/features/profile_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

final _now = DateTime.utc(2026, 11, 16);
Assignment _item({String title = '合成考试', ExamInfo? exam}) => Assignment(
      id: 'cx:exam:1:2:3',
      courseName: '合成课程',
      title: title,
      deadlineAt: null,
      requirementsText: '',
      status: 'unknown',
      lastSyncedAt: _now,
      exam: exam ?? const ExamInfo(examId: '3'),
    );

class _Store extends AssignmentStore {
  _Store(this.item)
      : super(
            sessionStore: SecureSessionStore(),
            notificationService: LocalNotificationService(),
            widgetSnapshotService: WidgetSnapshotService());
  final Assignment item;
  @override
  Assignment? findAssignment(String id) => id == item.id ? item : null;
}

void main() {
  test('unknown exam fields do not produce placeholder lines or status', () {
    expect(AssignmentCard.examScheduleLines(_item()), isEmpty);
    expect(AssignmentCard.examStateLabel(_item(), _now), '考试');
  });

  test('only trusted times and supplied location/duration are displayed', () {
    final item = _item(
        exam: ExamInfo(
            examId: '3',
            startAt: _now,
            startTrusted: false,
            endAt: _now.add(const Duration(hours: 1)),
            endTrusted: true,
            durationMinutes: 60,
            location: ' A301 '));
    final lines = AssignmentCard.examScheduleLines(item);
    expect(lines, ['结束 2026年11月16日 09:00', '时长 60 分钟', '地点 A301']);
  });

  testWidgets('undated card has no rail and aligns metadata with title',
      (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Padding(
      padding: const EdgeInsets.all(16),
      child: AssignmentCard(
        assignment: _item(),
        now: _now,
        onTap: () {},
        onOpenAssignment: () {},
      ),
    ))));
    expect(find.text('—'), findsNothing);
    expect(find.textContaining('待确认'), findsNothing);
    expect(t.getTopLeft(find.text('合成考试')).dx, 16);
    expect(t.getTopLeft(find.text('考试')).dx, 16);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'missing exam title displays course once without fabricated title',
      (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AssignmentCard(
      assignment: _item(title: ''),
      now: _now,
      onTap: () {},
    ))));
    expect(find.text('合成课程'), findsOneWidget);
    expect(find.text('考试'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  testWidgets(
      'detail hides unknown fields and labels unverified times without assuming their origin',
      (t) async {
    final item = _item(exam: ExamInfo(examId: '3', startAt: _now));
    final store = _Store(item);
    addTearDown(store.dispose);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body:
                AssignmentDetailScreen(store: store, assignmentId: item.id))));
    expect(find.text('部分信息尚未核实'), findsOneWidget);
    expect(find.textContaining('地点'), findsNothing);
    expect(find.textContaining('历史'), findsNothing);
    expect(find.text('开考 2026年11月16日 08:00'), findsNothing);
    await t.tap(find.text('未核实的时间记录'));
    await t.pumpAndSettle();
    expect(find.text('开考（未核实） 2026年11月16日 08:00'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('agreement helper aligns with text and links remain interactive',
      (t) async {
    final store = _Store(_item());
    addTearDown(store.dispose);
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(320, 900);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(MaterialApp(home: LoginScreen(store: store)));
    final helper = find.text('课程与作业数据保存在本机。');
    await t.ensureVisible(helper);
    expect(t.getTopLeft(helper).dx, t.getTopLeft(find.text('我已阅读并同意')).dx);
    await t.tap(find.byType(Checkbox));
    await t.pump();
    expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    for (final title in ['《服务协议》', '《隐私协议》']) {
      final link = find.widgetWithText(TextButton, title);
      expect(t.widget<TextButton>(link).onPressed, isNotNull);
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('themed logout still opens confirmation and can be cancelled',
      (t) async {
    final store = _Store(_item());
    addTearDown(store.dispose);
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: ProfileScreen(store: store))));
    final logout = find.widgetWithText(OutlinedButton, '退出登录');
    await t.scrollUntilVisible(logout, 400);
    // The enclosing profile section can already be built below the viewport.
    // Finish layout and explicitly position the button before a real tap.
    await t.pumpAndSettle();
    await Scrollable.ensureVisible(t.element(logout), alignment: 0.5);
    await t.pumpAndSettle();
    expect(logout.hitTestable(), findsOneWidget);
    expect(t.widget<OutlinedButton>(logout).onPressed, isNotNull);
    final style = t.widget<OutlinedButton>(logout).style!;
    expect(style.foregroundColor!.resolve({}), Journal.ink);
    expect(style.backgroundColor!.resolve({}), Journal.paper);
    await t.tap(logout);
    await t.pumpAndSettle();
    expect(find.text('退出并清理本机记录？'), findsOneWidget);
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(find.text('退出并清理本机记录？'), findsNothing);
  });

  test(
      'scheduled is explicit even without time and terminal states take priority',
      () {
    expect(
        AssignmentCard.examStateLabel(
            _item(exam: const ExamInfo(examId: '3', lifecycle: 'scheduled')),
            _now),
        '考试 · 未开始');
    for (final lifecycle in ['scheduled', 'inProgress', 'ended']) {
      final item = _item(
          exam: ExamInfo(
              examId: '3',
              lifecycle: lifecycle,
              endAt: _now,
              endTrusted: true));
      expect(AssignmentCard.examStateLabel(item, _now), '考试 · 已结束');
    }
    expect(
        AssignmentCard.examStateLabel(
            _item(
                exam: ExamInfo(
                    examId: '3',
                    lifecycle: 'cancelled',
                    endAt: _now,
                    endTrusted: true)),
            _now),
        '考试 · 已取消');
    expect(
        AssignmentCard.examStateLabel(
            _item(
                exam: ExamInfo(
                    examId: '3',
                    lifecycle: 'scheduled',
                    endAt: _now,
                    endTrusted: false)),
            _now),
        '考试 · 未开始');
  });

  testWidgets(
      'detail clock updates at end boundary and is disposed with observer',
      (t) async {
    var now = _now;
    var reads = 0;
    final item = _item(
        exam: ExamInfo(
            examId: '3',
            lifecycle: 'scheduled',
            endAt: _now.add(const Duration(minutes: 1)),
            endTrusted: true));
    final store = _Store(item);
    addTearDown(store.dispose);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AssignmentDetailScreen(
                store: store,
                assignmentId: item.id,
                clock: () {
                  reads++;
                  return now;
                }))));
    expect(find.text('考试 · 未开始'), findsOneWidget);
    now = _now.add(const Duration(minutes: 1));
    await t.pump(const Duration(minutes: 1));
    expect(find.text('考试 · 已结束'), findsOneWidget);
    expect(find.textContaining('已提交'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
    final readsAtDispose = reads;
    await t.pump(const Duration(minutes: 2));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(reads, readsAtDispose);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'resuming detail refreshes time without waiting for next clock tick',
      (t) async {
    var now = _now;
    final item = _item(
        exam: ExamInfo(
            examId: '3',
            lifecycle: 'inProgress',
            endAt: _now.add(const Duration(minutes: 5)),
            endTrusted: true));
    final store = _Store(item);
    addTearDown(store.dispose);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AssignmentDetailScreen(
                store: store, assignmentId: item.id, clock: () => now))));
    expect(find.text('考试 · 进行中'), findsOneWidget);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = _now.add(const Duration(minutes: 6));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(find.text('考试 · 已结束'), findsOneWidget);
    expect(find.textContaining('已提交'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
    expect(t.takeException(), isNull);
  });
}

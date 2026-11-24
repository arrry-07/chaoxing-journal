import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/todo_copy_formatter.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Session extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'A';

  @override
  Future<String?> readChaoxingDisplayName() async => '测试姓名';

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _Notifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
}

class _Widgets extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _Store extends AssignmentStore {
  _Store()
      : super(
          sessionStore: _Session(),
          notificationService: _Notifications(),
          widgetSnapshotService: _Widgets(),
        );
}

Assignment _work(
  String id, {
  required String title,
  required String courseName,
  String courseId = '1',
  String clazzId = '2',
  DateTime? deadlineAt,
  bool trusted = true,
  bool readFailed = false,
  String status = 'pending',
  String? submitUrl,
  AssignmentAvailability availability = AssignmentAvailability.available,
}) =>
    Assignment(
      id: 'cx:work:$courseId:$clazzId:$id',
      courseName: courseName,
      title: title,
      requirementsText: '私有备注不应出现 https://mooc1.chaoxing.com/secret?enc=123',
      status: status,
      deadlineAt: deadlineAt,
      deadlineTrusted: trusted,
      deadlineReadFailed: readFailed,
      submitUrl: submitUrl ??
          'https://mooc1.chaoxing.com/work?courseId=$courseId&clazzId=$clazzId&enc=tok123&cpi=999',
      availability: availability,
      lastSyncedAt: DateTime.utc(2026, 12, 28),
    );

Assignment _exam(
  String id, {
  required String title,
  required String courseName,
  DateTime? startAt,
  DateTime? endAt,
  bool trusted = true,
  bool noticeOnly = false,
  String? relatedExamId,
  String lifecycle = 'scheduled',
  String status = 'pending',
}) =>
    Assignment(
      id: noticeOnly ? 'cx:examNotice:inbox:$id' : 'cx:exam:3:4:$id',
      source: AssignmentSource.exam,
      courseName: courseName,
      title: title,
      requirementsText: '考场内部说明不应复制',
      status: status,
      deadlineAt: endAt,
      lastSyncedAt: DateTime.utc(2026, 12, 28),
      exam: ExamInfo(
        examId: id,
        relatedExamId: relatedExamId,
        courseId: '3',
        clazzId: '4',
        noticeOnly: noticeOnly,
        startAt: startAt,
        endAt: endAt,
        startTrusted: trusted && startAt != null,
        endTrusted: trusted && endAt != null,
        lifecycle: lifecycle,
        location: '秘密考场 101',
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  });

  group('TodoCopyFormatter next-7-day pure snapshots & sanitization', () {
    test(
        'formats cross-year Beijing timezone window, same-name course ordering, 2B manual/official takeover, and personal items without course',
        () async {
      // Now = 2026-12-28 00:30 Beijing (UTC 2026-12-27 16:30).
      // 7-day calendar window = 2026-12-28 .. 2027-01-03 inclusive.
      final now = DateTime.utc(2026, 12, 27, 16, 30);

      // Same-name courses sorted stably by courseTaskKey identity when timestamps tie.
      final sameCourseB = _work(
        'b',
        courseId: '20',
        clazzId: '1',
        courseName: '大学物理',
        title: '热学测验',
        deadlineAt: DateTime.utc(2026, 12, 28, 16, 0), // 2026-12-29 00:00 BJT
      );
      final sameCourseA = _work(
        'a',
        courseId: '10',
        clazzId: '1',
        courseName: '大学物理',
        title: '力学实验',
        deadlineAt: DateTime.utc(2026, 12, 28, 16, 0), // 2026-12-29 00:00 BJT
      );

      // 2B manual deadline (untrusted official).
      final manualOnlyWork = _work(
        'manual-1',
        courseId: '5',
        clazzId: '1',
        courseName: '数字逻辑',
        title: '第四次作业',
        deadlineAt: null,
        trusted: false,
      );
      // 2B overtaken by official confirmed deadline at another instant.
      final officialTakeover = _work(
        'takeover',
        courseId: '6',
        clazzId: '1',
        courseName: '线性代数',
        title: '第六章作业',
        deadlineAt: DateTime.utc(2026, 12, 31, 15, 59), // 2026-12-31 23:59 BJT
        trusted: true,
      );
      // 2B overtaken by official confirmed NO deadline -> stays excluded even if manual cached.
      final officialNoDeadline = _work(
        'takeover-none',
        courseId: '7',
        clazzId: '1',
        courseName: '形势与政策',
        title: '长期讨论',
        deadlineAt: null,
        trusted: true,
      );

      final trustedExam = _exam(
        '99',
        title: '编译原理期末机考',
        courseName: '编译原理',
        startAt: DateTime.utc(2027, 1, 2, 1, 0), // 2027-01-02 09:00 BJT
        endAt: DateTime.utc(2027, 1, 2, 3, 0),
      );
      final staleNoticeSameExam = _exam(
        'n99',
        relatedExamId: '99',
        noticeOnly: true,
        title: '编译原理通知副本',
        courseName: '编译原理',
        startAt: DateTime.utc(2026, 12, 29, 1, 0),
        endAt: DateTime.utc(2026, 12, 29, 3, 0),
      );
      final noticeOnlyExam = _exam(
        'n100',
        noticeOnly: true,
        title: '纯通知考试',
        courseName: '通知课程',
        startAt: DateTime.utc(2026, 12, 29, 2, 0),
        endAt: DateTime.utc(2026, 12, 29, 4, 0),
      );
      final cancelledExam = _exam(
        '101',
        lifecycle: 'cancelled',
        title: '已取消考试',
        courseName: '编译原理',
        startAt: DateTime.utc(2026, 12, 29, 5, 0),
      );
      final overdueWork = _work(
        'overdue',
        courseName: '逾期课',
        title: '昨天已逾期',
        deadlineAt: now.subtract(const Duration(minutes: 1)),
      );
      final completedWork = _work(
        'done',
        courseName: '已交课',
        title: '已提交作业',
        status: 'submitted',
        deadlineAt: DateTime.utc(2026, 12, 28, 12, 0),
      );
      final unavailableWork = _work(
        'unavail',
        courseName: '失效课',
        title: '已失效作业',
        availability: AssignmentAvailability.unavailable,
        deadlineAt: DateTime.utc(2026, 12, 28, 12, 0),
      );
      final day7Excluded = _work(
        'day7',
        courseId: '99',
        clazzId: '9',
        courseName: '下周课',
        title: '第七天凌晨excluded',
        deadlineAt:
            DateTime.utc(2027, 1, 3, 16, 0), // 2027-01-04 00:00 BJT (Day +7!)
      );
      final day6Included = _work(
        'day6',
        courseId: '98',
        clazzId: '9',
        courseName: '边界课',
        title: '第六天边界included',
        deadlineAt:
            DateTime.utc(2027, 1, 3, 15, 59), // 2027-01-03 23:59 BJT (Day +6!)
      );

      final repo = LocalAssignmentRepository();
      await repo.activateAccount('A');
      await repo.mergeAndSave(
        [
          sameCourseB,
          sameCourseA,
          manualOnlyWork,
          officialTakeover,
          officialNoDeadline,
          trustedExam,
          staleNoticeSameExam,
          noticeOnlyExam,
          cancelledExam,
          overdueWork,
          completedWork,
          unavailableWork,
          day6Included,
          day7Excluded,
        ],
        completeSync: true,
      );
      final store = _Store();
      addTearDown(store.dispose);
      await store.restoreSession();

      // Inject 2B manual deadlines: manualOnly stays manual, takeover & takeover-none get reconciled.
      await store.setManualDeadline(
        manualOnlyWork,
        DateTime.utc(2026, 12, 28, 12, 0), // 2026-12-28 20:00 BJT
      );
      await store.setManualDeadline(
        officialTakeover.copyWith(
            deadlineTrusted: false, clearDeadlineAt: true),
        DateTime.utc(2026, 12, 29, 8, 0),
      );
      await store.setManualDeadline(
        officialNoDeadline.copyWith(deadlineTrusted: false),
        DateTime.utc(2026, 12, 29, 8, 0),
      );
      await store.refreshAssignments();

      final manualEntries = [
        ManualEntry(
          id: 'todo-no-course',
          title: '交实验室材料',
          kind: 'todo',
          course: '',
          note: '绝对不能复制的私有备注',
          location: '秘密地点不应复制',
          at: DateTime.utc(2027, 1, 1, 1, 30), // 2027-01-01 09:30 BJT
        ),
        ManualEntry(
          id: 'exam-manual',
          title: '英语口语加试',
          kind: 'exam',
          course: '大学英语',
          at: DateTime.utc(2026, 12, 30, 6, 0), // 2026-12-30 14:00 BJT
        ),
        ManualEntry(
          id: 'todo-done',
          title: '已完成个人待办',
          kind: 'todo',
          at: DateTime.utc(2026, 12, 29, 4, 0),
          done: true,
        ),
      ];

      final result = TodoCopyFormatter.formatNext7Days(
        store.homeCatalogAssignments,
        manualEntries: manualEntries,
        now: now,
        index: store.homeDisplayIndex,
        coursework: store.courseworkState,
      );

      expect(result.isEmpty, isFalse);
      expect(result.count, 8);
      final text = result.text!;
      expect(
        text,
        '近 7 天待办（2026年12月28日–2027年1月3日，北京时间）\n'
        '\n'
        '12月28日 周一\n'
        '- 20:00 截止（自己添加） · 数字逻辑 · 第四次作业\n'
        '\n'
        '12月29日 周二\n'
        '- 00:00 截止 · 大学物理 · 力学实验\n'
        '- 00:00 截止 · 大学物理 · 热学测验\n'
        '\n'
        '12月30日 周三\n'
        '- 14:00 开考（自己添加） · 大学英语 · 英语口语加试\n'
        '\n'
        '12月31日 周四\n'
        '- 23:59 截止 · 线性代数 · 第六章作业\n'
        '\n'
        '2027年1月1日 周五\n'
        '- 09:30 截止（自己添加） · 交实验室材料\n'
        '\n'
        '2027年1月2日 周六\n'
        '- 09:00 开考 · 编译原理 · 编译原理期末机考\n'
        '\n'
        '2027年1月3日 周日\n'
        '- 23:59 截止 · 边界课 · 第六天边界included',
      );
      expect(text, isNot(contains('私有备注')));
      expect(text, isNot(contains('秘密地点')));
      expect(text, isNot(contains('秘密考场')));
      expect(text, isNot(contains('enc=')));
      expect(text, isNot(contains('cx:')));
    });

    test(
        'sanitizes control characters, signed URLs, credentials, PII, and handles empty lists safely',
        () {
      final now = DateTime.utc(2026, 11, 23, 2); // 10:00 BJT
      final dirty = _work(
        'dirty-1',
        courseName:
            '软件工程\r\n学号：20240012345 姓名:张三 https://mooc1.chaoxing.com/course?cpi=123&enc=secret',
        title:
            '实验报告\t\u202E 提交到 https://example.com/upload?token=abc123&sig=xyz (手机号: 13812345678, test@example.com) Bearer tok_secret_abc',
        deadlineAt: DateTime.utc(2026, 11, 24, 15, 59),
      );
      final pureUrlTitle = _work(
        'url-only',
        courseName: '计算机网络',
        title: 'https://mooc1.chaoxing.com/work?workId=1&enc=deadbeef',
        deadlineAt: DateTime.utc(2026, 11, 24, 15, 59),
      );

      final result = TodoCopyFormatter.formatNext7Days(
        [dirty, pureUrlTitle],
        now: now,
      );
      expect(result.isEmpty, isFalse);
      final text = result.text!;
      expect(text, contains('软件工程 · 实验报告 提交到'));
      expect(text, contains('计算机网络 · 未命名待办'));
      expect(text, isNot(contains('\r')));
      expect(text, isNot(contains('\t')));
      expect(text, isNot(contains('\u202E')));
      expect(text, isNot(contains('https://')));
      expect(text, isNot(contains('20240012345')));
      expect(text, isNot(contains('13812345678')));
      expect(text, isNot(contains('test@example.com')));
      expect(text, isNot(contains('Bearer')));
      expect(text, isNot(contains('tok_secret_abc')));
      expect(text, isNot(contains('张三')));
      expect(text, isNot(contains('enc=')));

      expect(TodoCopyFormatter.formatNext7Days([], now: now).isEmpty, isTrue);
    });
  });

  group('Home more menu & clipboard integration', () {
    testWidgets(
        'does not copy on initial build, gives empty feedback without touching clipboard, copies on tap, handles failure, and navigates to sync',
        (tester) async {
      final clipboardCalls = <String>[];
      var throwOnSet = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          if (throwOnSet) {
            throw PlatformException(code: 'copy_failed');
          }
          final map = call.arguments as Map<dynamic, dynamic>;
          clipboardCalls.add(map['text'] as String);
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      final now = DateTime.utc(2026, 11, 23, 2); // 10:00 BJT
      final store = _Store();
      addTearDown(store.dispose);

      final router = GoRouter(
        initialLocation: '/assignments',
        routes: [
          GoRoute(
            path: '/assignments',
            builder: (_, __) => Scaffold(
              body: AssignmentListScreen(store: store, clock: () => now),
            ),
          ),
          GoRoute(
            path: '/sync',
            builder: (_, __) => const Scaffold(body: Text('同步详情页面')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(
        theme: StudyAssistantTheme.light,
        routerConfig: router,
      ));
      await tester.pumpAndSettle();

      // Never copies on build.
      expect(clipboardCalls, isEmpty);

      // Open 更多 -> 复制近 7 天待办 on empty store -> feedback without Clipboard.setData.
      await tester.tap(find.byKey(const ValueKey('home-more-menu')));
      await tester.pumpAndSettle();
      expect(find.text('复制近 7 天待办'), findsOneWidget);
      expect(find.text('同步详情'), findsOneWidget);

      await tester.tap(find.text('复制近 7 天待办'));
      await tester.pumpAndSettle();
      expect(clipboardCalls, isEmpty);
      expect(find.text('近 7 天暂无可复制的待办'), findsOneWidget);

      // Populate an item inside next 7 days and copy again.
      store.replaceAssignmentsForTest([
        _work(
          'home-1',
          courseName: '操作系统',
          title: '进程调度实验 https://mooc1.chaoxing.com/w?enc=123',
          deadlineAt: DateTime.utc(2026, 11, 24, 15, 59),
        ),
      ]);
      await tester.pumpWidget(MaterialApp.router(
        theme: StudyAssistantTheme.light,
        routerConfig: router,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('home-more-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制近 7 天待办'));
      await tester.pumpAndSettle();

      expect(clipboardCalls, hasLength(1));
      expect(clipboardCalls.single, contains('23:59 截止 · 操作系统 · 进程调度实验'));
      expect(clipboardCalls.single, isNot(contains('https://')));
      expect(find.text('已复制近 7 天待办（共 1 项）'), findsOneWidget);

      // Clipboard PlatformException shows failure feedback cleanly.
      throwOnSet = true;
      await tester.tap(find.byKey(const ValueKey('home-more-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制近 7 天待办'));
      await tester.pumpAndSettle();
      expect(find.text('复制失败，请稍后重试'), findsOneWidget);

      // 更多 -> 同步详情 navigates to /sync.
      await tester.tap(find.byKey(const ValueKey('home-more-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('同步详情'));
      await tester.pumpAndSettle();
      expect(find.text('同步详情页面'), findsOneWidget);
    });
  });
}

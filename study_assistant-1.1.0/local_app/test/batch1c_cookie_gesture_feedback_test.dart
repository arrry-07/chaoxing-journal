import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:study_assistant_mobile/src/features/course_study_hub_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_context_menu.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_picker_sheet.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_swipe_tile.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/models/display_preferences.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/interaction_feedback_service.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _HubSyncStore extends AssignmentStore {
  _HubSyncStore(this.onSync, this.onChapters)
      : super(
          sessionStore: SecureSessionStore(),
          notificationService: LocalNotificationService(),
          widgetSnapshotService: WidgetSnapshotService(),
        );

  final Future<void> Function() onSync;
  final Future<bool> Function(String? courseKey) onChapters;

  SyncReport nextReport = const SyncReport();
  String? nextError;
  int nextEpoch = 1;
  final List<CourseRef> fakeCourses = const [
    CourseRef(courseId: '10', clazzId: '20', name: '高等数学'),
  ];

  @override
  bool get isAuthenticated => true;

  @override
  int get accountEpoch => nextEpoch;

  @override
  String? get error => nextError;

  @override
  List<CourseRef> get courses => fakeCourses;

  @override
  Future<void> syncAssignments() async {
    await onSync();
    syncReport = nextReport;
    notifyListeners();
  }

  @override
  Future<bool> syncCourseChapters({String? courseKey}) async {
    final ok = await onChapters(courseKey);
    notifyListeners();
    return ok;
  }
}

void main() {
  group('S6: verifyInBrowser Cookie isolation, empty rejection & diagnostics',
      () {
    test(
        'subdomain cookie does not poison parent .chaoxing.com, empty pair does not wipe valid cookie, and malformed cookies are counted',
        () async {
      const channel = MethodChannel('study_assistant/external_links');
      var round = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'verifySession');
        round++;
        if (round == 1) {
          return [
            {
              'url': 'https://chaoxing.com/',
              'cookies': 'UID=12345; sharedTok=parentVal',
            },
            {
              'url': 'https://mooc1.chaoxing.com/',
              'cookies':
                  'sharedTok=mooc1Only; UID=; bad name=1; broken=has space',
            },
          ];
        }
        return const [];
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      final sent = <String, String>{};
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
          sent['${o.uri.host}${o.uri.path}'] =
              o.headers['Cookie']?.toString() ?? '';
          final body = switch (o.uri.path) {
            '/mycourse/backclazzdata' => {
                'courses': [
                  {'courseId': '1', 'clazzId': '2', 'courseName': '物理'}
                ]
              },
            '/visit/stucoursemiddle' => round == 0
                ? '<html><body>请完成安全验证</body></html>'
                : '<input id="workEnc" value="w">',
            '/mooc2-ans/mycourse/stu' => '<input id="workEnc" value="w">',
            '/mooc2/work/list' => '<div>暂无作业</div>',
            _ => '',
          };
          h.resolve(Response(requestOptions: o, data: body, statusCode: 200));
        }));

      final client = ChaoxingLocalClient(
        dio: dio,
        enableExams: false,
        enableClassroomTasks: false,
        wait: (_) async {},
      );
      await expectLater(
          client.fetchAssignments(), throwsA(isA<SyncReadException>()));
      expect(await client.verifyInBrowser(), isTrue);
      expect(client.skippedMalformedVerifyCookies, 2);

      sent.clear();
      await client.fetchAssignments();

      // Another subdomain (mooc1-api) MUST still receive parent `.chaoxing.com`
      // `sharedTok=parentVal` and intact `UID=12345` — never poisoned by mooc1!
      final apiCookies = sent['mooc1-api.chaoxing.com/mycourse/backclazzdata']!;
      expect(apiCookies, contains('UID=12345'));
      expect(apiCookies, contains('sharedTok=parentVal'));
      expect(apiCookies, isNot(contains('sharedTok=mooc1Only')));
    });
  });

  group(
      'M4: Gesture dead-zone clamp, edge exclusion & overlay double-pop guard',
      () {
    testWidgets(
        'JournalSwipeTile clamps raw overdrag so reversing immediately moves tile back and ignores edge-back starts',
        (tester) async {
      var rightCount = 0;
      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
          body: JournalSwipeTile(
            rightAction: JournalSwipeAction(
              label: '今日计划',
              icon: Icons.check,
              color: Colors.blue,
              backgroundColor: Colors.blue.shade50,
              onTrigger: () => rightCount++,
            ),
            child: const SizedBox(
              width: double.infinity,
              height: 64,
              child: Text('任务项'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Drag starting inside the left 24dp Android edge-back zone is ignored.
      final edgeGesture = await tester.startGesture(const Offset(8, 32));
      await edgeGesture.moveBy(const Offset(120, 0));
      await tester.pump();
      final edgeTransform = tester.widget<Transform>(
        find.byKey(const ValueKey('journal-swipe-foreground')),
      );
      expect(edgeTransform.transform.storage[12], 0.0);
      await edgeGesture.up();
      await tester.pumpAndSettle();
      expect(rightCount, 0);

      // Overdrag far right (+500px), then reverse by 30px: tile must respond
      // immediately instead of sitting in a dead zone.
      final drag = await tester.startGesture(const Offset(100, 32));
      await drag.moveBy(const Offset(500, 0));
      await tester.pump();
      final peakOffset = tester
          .widget<Transform>(
            find.byKey(const ValueKey('journal-swipe-foreground')),
          )
          .transform
          .storage[12];
      expect(peakOffset, closeTo(108.0, 0.5));

      await drag.moveBy(const Offset(-30, 0));
      await tester.pump();
      final afterReverse = tester
          .widget<Transform>(
            find.byKey(const ValueKey('journal-swipe-foreground')),
          )
          .transform
          .storage[12];
      expect(afterReverse, lessThan(peakOffset - 5.0));
      await drag.cancel();
      await tester.pumpAndSettle();
    });

    testWidgets(
        'showJournalContextMenu handles very short screen without overflow and guards against double-pop',
        (tester) async {
      tester.view.physicalSize = const Size(360, 220);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var selectedCount = 0;
      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showJournalContextMenu(
                context: context,
                anchorRect: const Rect.fromLTWH(16, 40, 328, 80),
                previewCard: const SizedBox(height: 80, child: Text('预览')),
                actions: [
                  JournalContextMenuAction(
                    label: '置顶',
                    icon: Icons.push_pin_outlined,
                    onSelected: () => selectedCount++,
                  ),
                  JournalContextMenuAction(
                    label: '删除',
                    icon: Icons.delete_outline,
                    destructive: true,
                    onSelected: () {},
                  ),
                ],
              ),
              child: const Text('打开菜单'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('打开菜单'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('置顶'), findsOneWidget);

      // Fast double-tap must trigger action once and must NOT pop root route.
      await tester.tap(find.text('置顶'));
      await tester.pump(const Duration(milliseconds: 10));
      if (find.text('置顶').evaluate().isNotEmpty) {
        await tester.tap(find.text('置顶'), warnIfMissed: false);
      }
      await tester.pumpAndSettle();

      expect(selectedCount, 1);
      expect(find.text('打开菜单'), findsOneWidget);
    });

    testWidgets(
        'showJournalPickerSheet guards double-pop on close/option and avoids keyboard double bottom padding',
        (tester) async {
      String? picked;
      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            padding: EdgeInsets.only(bottom: 34),
            viewInsets: EdgeInsets.only(bottom: 260),
          ),
          child: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  picked = await showJournalPickerSheet<String>(
                    context,
                    title: '选择课程',
                    options: const [
                      JournalPickerOption(value: 'a', label: '课程A'),
                      JournalPickerOption(value: 'b', label: '课程B'),
                    ],
                  );
                },
                child: const Text('打开选择'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('打开选择'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('课程A'));
      await tester.pump(const Duration(milliseconds: 10));
      if (find.text('课程B').evaluate().isNotEmpty) {
        await tester.tap(find.text('课程B'), warnIfMissed: false);
      }
      await tester.pumpAndSettle();

      expect(picked, 'a');
      expect(find.text('打开选择'), findsOneWidget);
    });
  });

  group('M5: InteractionFeedback backward clock jump & preview isolation', () {
    test(
        'backward clock step never freezes tap throttle and preview does not suppress next tap',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      InteractionFeedback.debugReset();
      addTearDown(InteractionFeedback.debugReset);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        const channel = MethodChannel('study_assistant/interaction_sound');
        final kinds = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'feedback') {
            kinds.add((call.arguments as Map)['kind'] as String);
          }
          return null;
        });
        addTearDown(() => TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null));

        var clock = DateTime.utc(2026, 11, 22, 12, 0, 10);
        InteractionFeedback.now = () => clock;
        const prefs =
            DisplayPreferences(soundEnabled: true, hapticsEnabled: true);

        // Preview call must NOT pollute throttle for immediate tap.
        InteractionFeedback.trigger(prefs,
            kind: InteractionSoundKind.pin, preview: true);
        InteractionFeedback.trigger(prefs, kind: InteractionSoundKind.tap);
        expect(kinds, ['pin', 'tap']);

        // Clock steps backwards by 5 minutes (NTP adjustment): next tap must NOT be frozen!
        kinds.clear();
        clock = clock.subtract(const Duration(minutes: 5));
        InteractionFeedback.trigger(prefs, kind: InteractionSoundKind.tap);
        expect(kinds, ['tap']);

        // Normal rapid tap within 90ms after reset is still throttled.
        kinds.clear();
        clock = clock.add(const Duration(milliseconds: 40));
        InteractionFeedback.trigger(prefs, kind: InteractionSoundKind.tap);
        expect(kinds, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('M3: syncDone wired on AssignmentDetailScreen & CourseStudyHubScreen',
      () {
    testWidgets(
        'AssignmentDetailScreen refresh and CourseStudyHubScreen notices/chapters refresh emit syncDone only on clean success',
        (tester) async {
      await initializeDateFormatting('zh_CN');
      InteractionFeedback.debugReset();
      addTearDown(InteractionFeedback.debugReset);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        const channel = MethodChannel('study_assistant/interaction_sound');
        final kinds = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
            (call) async {
          if (call.method == 'feedback') {
            kinds.add((call.arguments as Map)['kind'] as String);
          }
          return null;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null));

        var syncOk = true;
        var chapterOk = true;
        late _HubSyncStore store;
        store = _HubSyncStore(
          () async {
            store.nextReport = SyncReport(
              phase: syncOk ? SyncPhase.success : SyncPhase.partial,
              attemptedAt: DateTime(2026, 11, 22, 10, syncOk ? 1 : 2),
            );
            store.nextError = null;
          },
          (_) async => chapterOk,
        );
        addTearDown(store.dispose);

        final work = Assignment(
          id: 'cx:work:10:20:1',
          courseName: '高等数学',
          title: '作业一',
          deadlineAt: DateTime.utc(2026, 11, 25, 12),
          requirementsText: '完成习题',
          status: 'pending',
          lastSyncedAt: DateTime.utc(2026, 11, 22, 10),
        );
        store.replaceAssignmentsForTest([work]);

        // 1. AssignmentDetailScreen refresh
        await tester.pumpWidget(MaterialApp(
          theme: StudyAssistantTheme.light,
          home: AssignmentDetailScreen(store: store, assignmentId: work.id),
        ));
        await tester.pumpAndSettle();

        final refreshDetailBtn = find.text('刷新作业信息');
        await tester.scrollUntilVisible(
          refreshDetailBtn,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        kinds.clear();
        syncOk = true;
        await tester.tap(refreshDetailBtn);
        await tester.pumpAndSettle();
        expect(kinds.where((k) => k == 'syncDone'), ['syncDone']);

        kinds.clear();
        syncOk = false;
        await tester.tap(refreshDetailBtn);
        await tester.pumpAndSettle();
        expect(kinds.where((k) => k == 'syncDone'), isEmpty);

        // 2. CourseStudyHubScreen notices refresh
        await tester.pumpWidget(MaterialApp(
          theme: StudyAssistantTheme.light,
          home: CourseStudyHubScreen(store: store, initialTab: 'notices'),
        ));
        await tester.pumpAndSettle();

        kinds.clear();
        syncOk = true;
        await tester.tap(find.byTooltip('手动同步通知'));
        await tester.pumpAndSettle();
        expect(kinds.where((k) => k == 'syncDone'), ['syncDone']);

        // 3. CourseStudyHubScreen chapters refresh (header + per-course)
        await tester.pumpWidget(MaterialApp(
          theme: StudyAssistantTheme.light,
          home: CourseStudyHubScreen(store: store, initialTab: 'chapters'),
        ));
        await tester.pumpAndSettle();

        kinds.clear();
        chapterOk = true;
        await tester.tap(find.byTooltip('刷新课程章节'));
        await tester.pumpAndSettle();
        expect(kinds.where((k) => k == 'syncDone'), ['syncDone']);

        kinds.clear();
        chapterOk = false;
        await tester.tap(find.byTooltip('刷新 高等数学 章节进度'));
        await tester.pumpAndSettle();
        expect(kinds.where((k) => k == 'syncDone'), isEmpty);

        kinds.clear();
        chapterOk = true;
        await tester.tap(find.byTooltip('刷新 高等数学 章节进度'));
        await tester.pumpAndSettle();
        expect(kinds.where((k) => k == 'syncDone'), ['syncDone']);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}

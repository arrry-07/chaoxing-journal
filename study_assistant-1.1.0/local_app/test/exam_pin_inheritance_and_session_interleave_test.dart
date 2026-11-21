import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/assignment_sync_progress.dart';
import 'package:study_assistant_mobile/src/models/display_preferences.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_reminder_planner.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/background_check_settings.dart';
import 'package:study_assistant_mobile/src/services/background_reminder_gateway.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

Assignment _examNotice({
  String id = '801',
  String? relatedExamId = '3',
  String courseId = '1',
  String clazzId = '2',
  String title = '期末考试',
  DateTime? now,
}) =>
    Assignment(
      id: 'cx:examNotice:inbox:$id',
      source: AssignmentSource.exam,
      courseName: '计算机网络',
      title: title,
      deadlineAt: null,
      requirementsText: '',
      status: 'unknown',
      submitUrl: 'https://notice.chaoxing.com/pc/notice/myNotice',
      lastSyncedAt: now ?? DateTime.utc(2026, 11, 21),
      exam: ExamInfo(
        examId: id,
        relatedExamId: relatedExamId,
        courseId: courseId,
        clazzId: clazzId,
        lifecycle: 'unknown',
        noticeOnly: true,
      ),
    );

Assignment _formalExam({
  String examId = '3',
  String courseId = '1',
  String clazzId = '2',
  String title = '期末考试',
  String lifecycle = 'scheduled',
  DateTime? startAt,
  DateTime? endAt,
  DateTime? now,
}) {
  final start = startAt ?? DateTime.utc(2026, 12, 10, 1);
  final end = endAt ?? start.add(const Duration(hours: 2));
  return Assignment(
    id: 'cx:exam:$courseId:$clazzId:$examId',
    source: AssignmentSource.exam,
    courseName: '计算机网络',
    title: title,
    deadlineAt: null,
    requirementsText: '',
    status: 'pending',
    submitUrl: Uri.https(
        'mooc1-api.chaoxing.com',
        '/phone/moocAnalysis/examList',
        {'courseId': courseId, 'classId': clazzId}).toString(),
    lastSyncedAt: now ?? DateTime.utc(2026, 11, 21),
    exam: ExamInfo(
      examId: examId,
      courseId: courseId,
      clazzId: clazzId,
      startAt: start,
      endAt: end,
      startTrusted: true,
      endTrusted: true,
      durationMinutes: 120,
      location: 'A-101',
      lifecycle: lifecycle,
      noticeOnly: false,
    ),
  );
}

Assignment _work(
  String id, {
  String title = '日常作业',
  String status = 'pending',
  DateTime? deadlineAt,
  DateTime? syncedAt,
}) =>
    Assignment(
      id: 'cx:work:1:2:$id',
      courseName: '高等数学',
      title: title,
      deadlineAt: deadlineAt,
      requirementsText: '',
      status: status,
      lastSyncedAt: syncedAt ?? DateTime.utc(2026, 11, 21),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('zh_CN'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'pinned exam notice inherits to replacing formal exam and unpins cleanly',
      (tester) async {
    const account = 'student-a';
    final now = DateTime.now();
    final notice = _examNotice(now: now);
    final formal = _formalExam(
      startAt: now.add(const Duration(days: 5)),
      now: now,
    );
    final earlierWork = _work(
      '91',
      title: '较早截止作业',
      deadlineAt: now.add(const Duration(days: 1)),
      syncedAt: now,
    );
    final client = _QueuedClient([
      [notice, earlierWork],
      [formal, notice, earlierWork],
    ]);
    final repository = LocalAssignmentRepository();
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(account: account, password: 'pw'),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _RecordingWidgetSnapshotService(),
      repository: repository,
      chaoxingClient: client,
      clock: () => now,
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    await store.syncAssignments();
    expect(await store.togglePin(notice), isTrue);
    expect(store.isPinned(notice), isTrue);
    expect(await repository.loadPinnedIds(account), {'exam:1:2:3'});

    await store.syncAssignments();

    expect(
        store.visibleAssignments.where((a) => a.isExam).single.id, formal.id);
    expect(store.isPinned(formal), isTrue);
    expect(store.canTogglePin(formal), isTrue);
    expect(await repository.loadPinnedIds(account), {'exam:1:2:3'});

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: Scaffold(body: AssignmentListScreen(store: store)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final cards =
        tester.widgetList<AssignmentCard>(find.byType(AssignmentCard)).toList();
    expect(find.text('置顶'), findsOneWidget);
    expect(cards.first.assignment.id, formal.id);

    expect(await store.togglePin(formal), isTrue);
    expect(store.isPinned(formal), isFalse);
    expect(store.isPinned(notice), isFalse);
    expect(await repository.loadPinnedIds(account), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('legacy notice id pin migrates on restore and unpins without residue',
      () async {
    const account = 'student-legacy';
    final now = DateTime.now();
    final notice = _examNotice(now: now);
    final formal =
        _formalExam(startAt: now.add(const Duration(days: 3)), now: now);
    final repository = LocalAssignmentRepository();
    await repository.activateAccount(account);
    await repository.mergeAndSave([notice, formal], completeSync: true);
    await repository.savePinnedIds({notice.id}, account);

    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(account: account, password: 'pw'),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _RecordingWidgetSnapshotService(),
      repository: repository,
      chaoxingClient: _QueuedClient([
        [notice, formal],
      ]),
      clock: () => now,
    );
    addTearDown(store.dispose);

    await store.restoreSession();
    expect(store.isPinned(formal), isTrue);
    expect(store.isPinned(notice), isTrue);
    expect(await repository.loadPinnedIds(account), {'exam:1:2:3'});

    expect(await store.togglePin(formal), isTrue);
    expect(store.isPinned(formal), isFalse);
    expect(store.isPinned(notice), isFalse);
    expect(await repository.loadPinnedIds(account), isEmpty);
  });

  test('unlinked exam notice never inherits and ended formal exam prunes pin',
      () async {
    const account = 'student-edge';
    final now = DateTime.now();
    final unlinkedNotice = _examNotice(
      id: '899',
      relatedExamId: null,
      now: now,
    );
    final linkedNotice = _examNotice(id: '801', relatedExamId: '3', now: now);
    final formal =
        _formalExam(startAt: now.add(const Duration(days: 4)), now: now);
    final endedFormal = _formalExam(
      lifecycle: 'ended',
      startAt: now.subtract(const Duration(hours: 3)),
      endAt: now.subtract(const Duration(hours: 1)),
      now: now,
    );
    final client = _QueuedClient([
      [unlinkedNotice, linkedNotice],
      [unlinkedNotice, linkedNotice, formal],
      [endedFormal, linkedNotice],
    ]);
    final repository = LocalAssignmentRepository();
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(account: account, password: 'pw'),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _RecordingWidgetSnapshotService(),
      repository: repository,
      chaoxingClient: client,
      clock: () => now,
    );
    addTearDown(store.dispose);

    await store.restoreSession();
    await store.syncAssignments();
    expect(await store.togglePin(unlinkedNotice), isTrue);
    expect(await store.togglePin(linkedNotice), isTrue);

    await store.syncAssignments();
    expect(store.isPinned(formal), isTrue);
    expect(store.isPinned(unlinkedNotice), isTrue);

    // Clear linked pin first, verify unlinked notice pin does NOT pin formal exam.
    expect(await store.togglePin(formal), isTrue);
    expect(store.isPinned(formal), isFalse);
    expect(store.isPinned(unlinkedNotice), isTrue);

    // Re-pin linked formal exam, then let formal exam end -> pin auto-pruned.
    expect(await store.togglePin(formal), isTrue);
    expect(store.isPinned(formal), isTrue);
    await store.syncAssignments();
    expect(store.isPinned(formal), isFalse);
    expect(store.isPinned(linkedNotice), isFalse);
    expect(await repository.loadPinnedIds(account), {unlinkedNotice.id});
  });

  test(
      'queued pin and hide are safely dropped across logout and account switch',
      () async {
    Future<void> verifyInterleave({required bool switchAccount}) async {
      SharedPreferences.setMockInitialValues({});
      final now = DateTime.now();
      final work = _work('11',
          title: '账号A作业',
          deadlineAt: now.add(const Duration(days: 2)),
          syncedAt: now);
      final syncGate = Completer<List<Assignment>>();
      final syncStarted = Completer<void>();
      final client = _GatedClient(
        syncGate: syncGate,
        syncStarted: syncStarted,
        afterGateQueue: [
          if (switchAccount) [_work('22', title: '账号B作业', syncedAt: now)],
        ],
      );
      final gateway = _TestGateway();
      final repository = LocalAssignmentRepository(
        backgroundReminderGateway: gateway,
      );
      final store = AssignmentStore(
        sessionStore: _MemorySessionStore(account: 'student-a', password: 'pw'),
        notificationService: _NoopNotificationService(),
        widgetSnapshotService: _RecordingWidgetSnapshotService(),
        repository: repository,
        chaoxingClient: client,
        backgroundReminderGateway: gateway,
        nativeReminderDeliveryEnabled: true,
        clock: () => now,
      );
      addTearDown(store.dispose);

      await repository.activateAccount('student-a');
      await repository.mergeAndSave([work], completeSync: true);
      await store.restoreSession();

      final syncFuture = store.syncAssignments();
      await syncStarted.future;

      final pinFuture = store.togglePin(work);
      final hideFuture = store.hideAssignment(work.id);

      final terminalFuture = switchAccount
          ? store.loginChaoxing(
              account: 'student-b',
              password: 'pw-b',
              agreementAccepted: true,
            )
          : store.logout();

      syncGate.complete([work]);
      final pinSaved = await pinFuture;
      final hideSaved = await hideFuture;
      await syncFuture;
      await terminalFuture;

      expect(pinSaved, isFalse);
      expect(hideSaved, isFalse);
      expect(store.error, isNull);

      if (switchAccount) {
        expect(store.isAuthenticated, isTrue);
        expect(store.account, 'student-b');
        expect(await repository.loadPinnedIds('student-b'), isEmpty);
        expect(await repository.loadHiddenAssignments(), isEmpty);

        await repository.activateAccount('student-a');
        expect(await repository.loadPinnedIds('student-a'), isEmpty);
        expect(await repository.loadHiddenAssignments(), isEmpty);
      } else {
        expect(store.isAuthenticated, isFalse);
        expect(store.isPinned(work), isFalse);
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        expect(prefs.getStringList('pinned_assignment_ids_v1'), isNull);
        expect(prefs.getString('journal_account_owner'), isNull);
      }
    }

    await verifyInterleave(switchAccount: false);
    await verifyInterleave(switchAccount: true);
  });

  test(
      'throttled home progress preview timer discards stale callbacks across logout and switch',
      () async {
    Future<void> verifyProgress({required bool switchAccount}) async {
      SharedPreferences.setMockInitialValues({});
      final now = DateTime.now();
      final previewA1 = _work(
        '101',
        title: '账号A流式条目1',
        deadlineAt: now.add(const Duration(days: 1)),
        syncedAt: now,
      );
      final previewA2 = _work(
        '102',
        title: '账号A流式条目2',
        deadlineAt: now.add(const Duration(days: 2)),
        syncedAt: now,
      );
      final workB = _work(
        '201',
        title: '账号B正式条目',
        deadlineAt: now.add(const Duration(days: 3)),
        syncedAt: now,
      );
      final gate = Completer<List<Assignment>>();
      final timerArmed = Completer<void>();
      late final void Function(AssignmentSyncProgress) capturedOnProgress;
      final client = _StreamingProgressClient(
        onStart: (progressCallback) {
          capturedOnProgress = progressCallback;
          progressCallback(AssignmentSyncProgress(
            stage: AssignmentSyncStage.workLists,
            assignments: [previewA1],
            pendingDetailIds: const {'cx:work:1:2:101'},
            resolvedCount: 0,
            attemptedCount: 1,
          ));
          progressCallback(AssignmentSyncProgress(
            stage: AssignmentSyncStage.details,
            assignments: [previewA1],
            pendingDetailIds: const {'cx:work:1:2:101'},
            resolvedCount: 0,
            attemptedCount: 1,
          ));
          // Second details update hits the 100ms throttle timer branch.
          progressCallback(AssignmentSyncProgress(
            stage: AssignmentSyncStage.details,
            assignments: [previewA1, previewA2],
            pendingDetailIds: const {'cx:work:1:2:102'},
            resolvedCount: 1,
            attemptedCount: 2,
          ));
          timerArmed.complete();
        },
        gate: gate,
        afterGateQueue: [
          if (switchAccount) [workB],
        ],
      );
      final widgets = _RecordingWidgetSnapshotService();
      final store = AssignmentStore(
        sessionStore: _MemorySessionStore(account: 'student-a', password: 'pw'),
        notificationService: _NoopNotificationService(),
        widgetSnapshotService: widgets,
        chaoxingClient: client,
        clock: () => now,
      );
      addTearDown(store.dispose);
      await store.restoreSession();

      final syncFuture = store.syncAssignments();
      await timerArmed.future;
      expect(store.homeDisplayAssignments.map((a) => a.title), ['账号A流式条目1']);

      final actionFuture = switchAccount
          ? store.loginChaoxing(
              account: 'student-b',
              password: 'pw-b',
              agreementAccepted: true,
            )
          : store.logout();

      // Immediately after synchronous entry of logout/login, preview must be gone.
      expect(client.cancelledCount, greaterThan(0));
      expect(store.homeSyncProgress, isNull);
      expect(store.homeDisplayAssignments, isEmpty);

      // Fire a late stale progress callback & wait past the 100ms throttle timer.
      capturedOnProgress(AssignmentSyncProgress(
        stage: AssignmentSyncStage.saving,
        assignments: [previewA1, previewA2],
        pendingDetailIds: const {},
        resolvedCount: 2,
        attemptedCount: 2,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 130));
      expect(
        store.homeDisplayAssignments.any((a) => a.title.startsWith('账号A')),
        isFalse,
      );

      gate.complete([previewA1, previewA2]);
      await syncFuture;
      await actionFuture;

      if (switchAccount) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(store.account, 'student-b');
        expect(store.homeDisplayAssignments.map((a) => a.id), [workB.id]);
        expect(store.assignments.map((a) => a.id), [workB.id]);
      } else {
        expect(store.isAuthenticated, isFalse);
        expect(store.homeDisplayAssignments, isEmpty);
        expect(store.assignments, isEmpty);
        expect(widgets.lastAuthenticated, isFalse);
      }
    }

    await verifyProgress(switchAccount: false);
    await verifyProgress(switchAccount: true);
  });

  test(
      'foreground resumes and reconciles headless background sync with write lease and pin pruning',
      () async {
    const account = 'student-reconcile';
    var clockNow = DateTime(2026, 11, 21, 10, 0);
    final pendingWork = _work(
      '301',
      title: '仍待交作业',
      deadlineAt: DateTime(2026, 11, 25, 20),
      syncedAt: clockNow,
    );
    final completedLater = _work(
      '302',
      title: '后台已提交作业',
      deadlineAt: DateTime(2026, 11, 26, 20),
      syncedAt: clockNow,
    );
    final gateway = _TestGateway();
    final session = _MemorySessionStore(account: account, password: 'pw');
    final fgClient = _QueuedClient([
      [pendingWork, completedLater],
    ]);
    final fgRepo = LocalAssignmentRepository(
      backgroundReminderGateway: gateway,
      writeLeaseOwner: 'fg-owner',
    );
    final fgStore = AssignmentStore(
      sessionStore: session,
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _RecordingWidgetSnapshotService(),
      repository: fgRepo,
      chaoxingClient: fgClient,
      backgroundReminderGateway: gateway,
      nativeReminderDeliveryEnabled: true,
      clock: () => clockNow,
    );
    addTearDown(fgStore.dispose);

    await fgStore.restoreSession();
    await fgStore.syncAssignments();
    expect(fgClient.calls, 1);

    // First pin encounters an unconfirmed write-lease release: pin still persists
    // and surfaces a recovery warning cleanly.
    gateway.failNextWriteRelease = true;
    expect(await fgStore.togglePin(pendingWork), isTrue);
    expect(gateway.failNextWriteRelease, isFalse);
    expect(fgStore.error, contains('置顶状态已保存'));
    expect(await fgStore.togglePin(completedLater), isTrue);
    expect(await fgRepo.loadPinnedIds(account),
        {pendingWork.courseTaskKey, completedLater.courseTaskKey});

    // Advance to the next daytime slot (10:00 tomorrow) so DaytimeCheckPolicy
    // considers background check due relative to fgStore's real sync timestamp.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final fgBase = fgStore.lastSyncAt!;
    clockNow = DateTime(fgBase.year, fgBase.month, fgBase.day + 1, 10, 0);
    final bgClient = _QueuedClient([
      [
        pendingWork,
        completedLater.copyWith(status: 'submitted'),
      ],
    ]);
    final bgRepo = LocalAssignmentRepository(
      backgroundReminderGateway: gateway,
      writeLeaseOwner: 'bg-owner',
    );
    final bgStore = AssignmentStore(
      sessionStore: session,
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _RecordingWidgetSnapshotService(),
      repository: bgRepo,
      chaoxingClient: bgClient,
      backgroundReminderGateway: gateway,
      manageBackgroundSchedule: false,
      nativeReminderDeliveryEnabled: true,
      clock: () => clockNow,
    );
    addTearDown(bgStore.dispose);

    await bgStore.restoreSession();
    final bgResult = await bgStore
        .runBackgroundAutomaticCheck(BackgroundSyncTrigger.daytime);
    expect(bgResult.success, isTrue);
    expect(bgClient.calls, 1);

    // Foreground resumes 1 minute after background's sync timestamp: must
    // reconcile background sync from durable storage, prune the completed pin,
    // and avoid duplicate fetch.
    final ranNetworkSync = await fgStore.runDueAutoSync(
      now: clockNow.add(const Duration(minutes: 1)),
    );
    expect(ranNetworkSync, isFalse);
    expect(fgClient.calls, 1);
    expect(fgStore.findAssignment(completedLater.id)?.status, 'submitted');
    expect(fgStore.isPinned(pendingWork), isTrue);
    expect(fgStore.isPinned(completedLater), isFalse);
    expect(await fgRepo.loadPinnedIds(account), {pendingWork.courseTaskKey});
  });
}

class _MemorySessionStore extends SecureSessionStore {
  _MemorySessionStore({this.account, this.password});

  String? account;
  String? password;
  String? displayName;
  String? avatarUrl;

  @override
  Future<void> saveChaoxingAccount({
    required String account,
    required String password,
    String? displayName,
    String? avatarUrl,
  }) async {
    this.account = account;
    this.password = password;
    this.displayName = displayName;
    this.avatarUrl = avatarUrl;
  }

  @override
  Future<String?> readChaoxingAccount() async => account;

  @override
  Future<String?> readChaoxingPassword() async => password;

  @override
  Future<String?> readChaoxingDisplayName() async => displayName;

  @override
  Future<String?> readChaoxingAvatarUrl() async => avatarUrl;

  @override
  Future<void> clear() async {
    account = null;
    password = null;
    displayName = null;
    avatarUrl = null;
  }

  @override
  Future<void> clearWebSession() async {}
}

class _NoopNotificationService extends LocalNotificationService {
  @override
  Future<bool> isLegacyAssignmentMigrationComplete() async => true;

  @override
  Future<void> removeLegacyAssignmentSchedules() async {}

  @override
  Future<void> cancelPrivateSchedules() async {}

  @override
  Future<void> rescheduleManual(List<ManualEntry> items) async {}

  @override
  Future<void> rescheduleSummary(List<Assignment> items,
      PersonalWorkspace personal, DateTime? lastSync) async {}

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}
}

class _RecordingWidgetSnapshotService extends WidgetSnapshotService {
  bool? lastAuthenticated;

  @override
  Future<void> saveAssignmentsForContext(
    List<Assignment> assignments, {
    bool authenticated = true,
    WidgetRange range = WidgetRange.all,
  }) async {
    lastAuthenticated = authenticated;
    await saveAssignments(assignments);
  }

  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _QueuedClient extends ChaoxingLocalClient {
  _QueuedClient(this.queue) : super(enableExams: true);

  final List<List<Assignment>> queue;
  int calls = 0;

  @override
  bool get needsSessionInitialization => false;

  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async =>
      const ChaoxingLoginResult(success: true);

  @override
  Future<List<Assignment>> fetchAssignments() async {
    calls++;
    return queue.removeAt(0);
  }
}

class _GatedClient extends ChaoxingLocalClient {
  _GatedClient({
    required this.syncGate,
    required this.syncStarted,
    required this.afterGateQueue,
  });

  final Completer<List<Assignment>> syncGate;
  final Completer<void> syncStarted;
  final List<List<Assignment>> afterGateQueue;
  var _first = true;

  @override
  bool get needsSessionInitialization => false;

  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async =>
      const ChaoxingLoginResult(success: true);

  @override
  Future<List<Assignment>> fetchAssignments() async {
    if (_first) {
      _first = false;
      syncStarted.complete();
      return syncGate.future;
    }
    return afterGateQueue.isEmpty ? const [] : afterGateQueue.removeAt(0);
  }
}

class _StreamingProgressClient extends ChaoxingLocalClient {
  _StreamingProgressClient({
    required this.onStart,
    required this.gate,
    required this.afterGateQueue,
  });

  final void Function(void Function(AssignmentSyncProgress) onProgress) onStart;
  final Completer<List<Assignment>> gate;
  final List<List<Assignment>> afterGateQueue;
  int cancelledCount = 0;
  var _first = true;

  @override
  bool get needsSessionInitialization => false;

  @override
  void cancelActiveRequests({bool reportCancelled = true}) {
    cancelledCount++;
    super.cancelActiveRequests(reportCancelled: reportCancelled);
  }

  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async =>
      const ChaoxingLoginResult(success: true);

  @override
  Future<List<Assignment>> fetchAssignments() async {
    if (_first) {
      _first = false;
      onStart(onProgress!);
      return gate.future;
    }
    return afterGateQueue.isEmpty ? const [] : afterGateQueue.removeAt(0);
  }
}

class _TestGateway extends BackgroundReminderGateway {
  String? activeAccountHash;
  int currentEpoch = 1;
  int mutationVersion = 0;
  bool baseline = false;
  Set<String> baselinedSources = {};
  Set<String> known = {};
  Set<String> sentNew = {};
  DateTime? lastAttempt;
  DateTime? lastFull;
  bool failNextWriteRelease = false;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<int> ensureActiveAccount(String accountHash) async {
    activeAccountHash = accountHash;
    return currentEpoch;
  }

  @override
  Future<bool> isSessionCurrent(String accountHash, int sessionEpoch) async =>
      activeAccountHash == accountHash && currentEpoch == sessionEpoch;

  @override
  Future<int> switchAccount({
    required String? previousAccountHash,
    required String accountHash,
  }) async {
    activeAccountHash = accountHash;
    currentEpoch++;
    return currentEpoch;
  }

  @override
  Future<int> rotateSessionEpoch(String accountHash) async {
    activeAccountHash = accountHash;
    currentEpoch++;
    return currentEpoch;
  }

  @override
  Future<int> clearActiveAccount(String accountHash) async {
    if (activeAccountHash == accountHash) {
      activeAccountHash = null;
      currentEpoch++;
    }
    return 1;
  }

  @override
  Future<void> cancelAssignmentDeliveryKeepEvents(String accountHash) async {}

  @override
  Future<void> cancelAssignmentReminders(String accountHash) async {}

  @override
  Future<bool> acquireWriteLease(String owner) async => true;

  @override
  Future<void> releaseWriteLease(String owner) async {
    if (failNextWriteRelease) {
      failNextWriteRelease = false;
      throw StateError('simulated write lease timeout');
    }
  }

  @override
  Future<SyncLeaseResult> acquireSyncLease({
    required String accountHash,
    required String requestId,
    required DateTime requestedAt,
  }) async =>
      const SyncLeaseResult(
        acquired: true,
        waited: false,
        lastAttemptAt: null,
        lastFullSuccessAt: null,
      );

  @override
  Future<void> releaseSyncLease({
    required String accountHash,
    required String requestId,
  }) async {}

  @override
  Future<void> markPendingUpdate({
    required String accountHash,
    required int sessionEpoch,
  }) async {
    mutationVersion++;
  }

  @override
  Future<void> updateSettings(
    String accountHash,
    int sessionEpoch,
    BackgroundCheckSettings settings, {
    required bool showDetails,
    bool reconcileSchedules = true,
  }) async {
    mutationVersion++;
  }

  @override
  Future<void> reconcileDaytimeSchedule({
    required DateTime? targetAt,
    required bool enabled,
    required int intervalMinutes,
  }) async {}

  @override
  Future<ReminderPlanState> loadPlanState({
    required String accountHash,
    required int sessionEpoch,
  }) async =>
      ReminderPlanState(
        accountHash: accountHash,
        sessionEpoch: sessionEpoch,
        baselineCompleted: baseline,
        baselinedSources: {...baselinedSources},
        knownAssignmentIds: {...known},
        sentNewAssignmentIds: {...sentNew},
        lastAttemptAt: lastAttempt,
        lastFullSuccessAt: lastFull,
        pendingUpdate: true,
        mutationVersion: mutationVersion,
      );

  @override
  Future<ReminderPlanApplyResult> applyPlan({
    required String accountHash,
    required int sessionEpoch,
    required AssignmentReminderPlan plan,
    required DateTime completedAt,
    required String? failure,
    required bool syncCompleted,
    required int expectedMutationVersion,
  }) async {
    baseline = plan.baselineCompleted;
    baselinedSources = {...plan.baselinedSources};
    known = {...plan.knownAssignmentIds};
    sentNew.addAll(plan.newEvents.map((e) => e.assignmentId));
    if (syncCompleted) {
      lastAttempt = completedAt;
      if (failure == null) lastFull = completedAt;
    }
    return ReminderPlanApplyResult(
      scheduledDeadlineCount: plan.deadlineEvents.length,
      pendingNewCount: plan.newEvents.length,
      warning: null,
    );
  }

  @override
  Future<void> recordAttempt({
    required String accountHash,
    required int sessionEpoch,
    required DateTime attemptedAt,
    required bool dataSucceeded,
    required bool fullSucceeded,
    required String? failure,
  }) async {}

  @override
  Future<BackgroundReminderHealth> inspectHealth({
    required String accountHash,
    required int sessionEpoch,
  }) async =>
      const BackgroundReminderHealth(
        backgroundEnabled: true,
        intervalMinutes: 240,
        newAssignmentReminderEnabled: true,
        notificationListenerEnabled: false,
        notificationListenerGranted: false,
        nextCheckAt: null,
        pendingNewCount: 0,
        pendingDeadlineCount: 0,
        baselineCompleted: true,
        pendingSignalCount: 0,
        migrationPending: false,
        lastFailure: null,
      );
}

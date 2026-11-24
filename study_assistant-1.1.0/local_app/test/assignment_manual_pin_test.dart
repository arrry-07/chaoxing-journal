import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/pinned_assignments.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/account_identity.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';

import 'review_core_remediation_test.dart' as core;

final _now = DateTime.utc(2026, 11, 23, 6); // Beijing 14:00

ManualEntry _manual(String id, {bool done = false}) => ManualEntry(
      id: id,
      title: '手动 $id',
      kind: 'todo',
      course: '个人',
      at: _now.add(const Duration(hours: 2)),
      done: done,
    );

class _FixedStore extends AssignmentStore {
  _FixedStore({
    core.Session? session,
    super.repository,
    DateTime Function()? clock,
    core.Client? client,
  }) : super(
          sessionStore: session ?? core.Session(),
          notificationService: core.Notifications(),
          widgetSnapshotService: core.WidgetService(),
          chaoxingClient: client ?? core.Client(),
          clock: clock ?? (() => _now),
        );

  @override
  Future<bool> runDueAutoSync({DateTime? now}) async => false;
}

class _PinSaveRepository extends LocalAssignmentRepository {
  _PinSaveRepository(this.onSaved);

  final void Function() onSaved;

  @override
  Future<void> savePinnedAssignments(
      PinnedAssignments pins, String account) async {
    await super.savePinnedAssignments(pins, account);
    onSaved();
  }
}

class _ControllablePinRepository extends LocalAssignmentRepository {
  bool throwStaleOnSave = false;
  Completer<void>? saveStarted;
  Completer<void>? saveGate;
  Object? gateError;
  void Function()? onSaved;
  int saveCalls = 0;

  @override
  Future<void> savePinnedAssignments(
      PinnedAssignments pins, String account) async {
    saveCalls++;
    final started = saveStarted;
    if (started != null && !started.isCompleted) started.complete();
    final gate = saveGate;
    if (gate != null) {
      saveGate = null;
      await gate.future;
      final error = gateError;
      if (error != null) {
        gateError = null;
        throw error;
      }
    }
    if (throwStaleOnSave) {
      throw StaleSessionWriteException('simulated stale pin write');
    }
    await super.savePinnedAssignments(pins, account);
    onSaved?.call();
  }
}

Future<_FixedStore> _store() async {
  final store = _FixedStore();
  addTearDown(store.dispose);
  await store.restoreSession();
  return store;
}

Future<_FixedStore> _pinStore(
  LocalAssignmentRepository repository, {
  DateTime Function()? clock,
  core.Client? client,
}) async {
  final store =
      _FixedStore(repository: repository, clock: clock, client: client);
  addTearDown(store.dispose);
  await store.restoreSession();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('manual pin mixes with coursework reorder and prunes on completion',
      () async {
    final assignment = core.sample('pin-a');
    final store = await _store();
    await store.repository.mergeAndSave([assignment]);
    await store.restoreSession();

    final first = _manual('m1');
    expect(
      await store.saveNotebook(
        (_) => StudyNotebook(entries: [first]),
        store.accountEpoch,
      ),
      isTrue,
    );
    expect(store.canToggleManualPin(first), isTrue);
    expect(await store.toggleManualPin(first), isTrue);
    expect(store.isManualPinned(first), isTrue);

    expect(store.canTogglePin(assignment), isTrue);
    expect(await store.togglePin(assignment), isTrue);
    expect(
        store.pinnedKeys,
        containsAll(<String>[
          AssignmentStore.manualPinKeyOf(first),
          AssignmentStore.pinKeyOf(assignment),
        ]));

    expect(
      await store.reorderPinned([
        AssignmentStore.manualPinKeyOf(first),
        AssignmentStore.pinKeyOf(assignment),
      ]),
      isTrue,
    );
    expect(store.pinnedKeys.take(2), [
      AssignmentStore.manualPinKeyOf(first),
      AssignmentStore.pinKeyOf(assignment),
    ]);

    expect(
      await store.saveNotebook(
        (n) => n.withEntries([
          for (final entry in n.entries)
            entry.id == first.id ? entry.completed(true) : entry,
        ]),
        store.accountEpoch,
      ),
      isTrue,
    );
    expect(store.isManualPinned(first), isFalse);
    expect(store.pinnedKeys,
        isNot(contains(AssignmentStore.manualPinKeyOf(first))));
  });

  test('deleting a manual entry clears its pin and logout isolates account',
      () async {
    final session = core.Session();
    final store = _FixedStore(session: session);
    addTearDown(store.dispose);
    await store.restoreSession();
    final entry = _manual('m2');
    expect(
      await store.saveNotebook(
        (_) => StudyNotebook(entries: [entry]),
        store.accountEpoch,
      ),
      isTrue,
    );
    expect(await store.toggleManualPin(entry), isTrue);
    expect(store.isManualPinned(entry), isTrue);

    expect(
      await store.saveNotebook(
        (_) => StudyNotebook(),
        store.accountEpoch,
      ),
      isTrue,
    );
    expect(store.pinnedKeys, isEmpty);

    expect(
      await store.saveNotebook(
        (_) => StudyNotebook(entries: [entry]),
        store.accountEpoch,
      ),
      isTrue,
    );
    expect(await store.toggleManualPin(entry), isTrue);
    await store.logout();
    expect(store.pinnedKeys, isEmpty);
    session.account = 'B';
    await store.restoreSession();
    expect(store.isAuthenticated, isTrue);
    expect(store.account, 'B');
    expect(store.notebook.entries, isEmpty);
    expect(store.isManualPinned(entry), isFalse);
  });

  test('an exam ending during pin save keeps stored and active pins in sync',
      () async {
    final end = _now.add(const Duration(minutes: 1));
    final exam = Assignment(
      id: 'cx:exam:1:2:pin-boundary',
      courseName: '测试课程',
      title: '即将结束的考试',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: _now,
      source: AssignmentSource.exam,
      exam: ExamInfo(
        examId: 'pin-boundary',
        courseId: '1',
        clazzId: '2',
        endAt: end,
        endTrusted: true,
        lifecycle: 'scheduled',
      ),
    );
    var clock = _now;
    final repository = _PinSaveRepository(() => clock = end);
    final store = _FixedStore(repository: repository, clock: () => clock);
    addTearDown(store.dispose);
    await store.restoreSession();
    await repository.mergeAndSave([exam]);
    await store.restoreSession();

    expect(store.canTogglePin(exam), isTrue);
    expect(await store.togglePin(exam), isTrue);
    expect(store.canTogglePin(exam), isFalse);
    expect(await repository.loadPinnedIds('A'),
        contains(AssignmentStore.pinKeyOf(exam)));
    expect(store.isPinned(exam), isTrue);
  });

  test('reorderPinned accepts a filtered subset and rejects bad keys',
      () async {
    final assignment = core.sample('pin-c');
    final store = await _store();
    await store.repository.mergeAndSave([assignment]);
    await store.restoreSession();
    final first = _manual('m-first');
    final second = _manual('m-second');
    expect(
      await store.saveNotebook(
        (_) => StudyNotebook(entries: [first, second]),
        store.accountEpoch,
      ),
      isTrue,
    );
    expect(await store.togglePin(assignment), isTrue);
    expect(await store.toggleManualPin(first), isTrue);
    expect(await store.toggleManualPin(second), isTrue);
    final pinned = store.pinnedKeys.take(3).toList();
    expect(pinned, hasLength(3));

    // A course/type filter can show only part of the pinned block.
    expect(await store.reorderPinned([pinned[1]]), isTrue);
    expect(await store.reorderPinned([pinned[1], pinned[0]]), isTrue);
    expect(store.pinnedKeys.take(2), [pinned[1], pinned[0]]);

    expect(await store.reorderPinned([pinned[0], pinned[0]]), isFalse);
    expect(await store.reorderPinned(['manual:missing']), isFalse);
    expect(await store.reorderPinned([]), isFalse);
  });

  test(
      'togglePin and toggleManualPin return false and keep memory unchanged '
      'on StaleSessionWriteException', () async {
    final work = core.sample('pin-stale');
    final manual = _manual('m-stale');
    final repo = _ControllablePinRepository();
    final store = await _pinStore(repo);
    await repo.mergeAndSave([work]);
    await store.restoreSession();
    expect(
      await store.saveNotebook(
        (_) => StudyNotebook(entries: [manual]),
        store.accountEpoch,
      ),
      isTrue,
    );

    // 1a: a rejected first pin must not claim success or memory ownership.
    repo.throwStaleOnSave = true;
    expect(await store.togglePin(work), isFalse);
    expect(store.isPinned(work), isFalse);
    expect(store.pinnedKeys, isEmpty);
    expect(store.error, isNull);
    expect(await repo.loadPinnedIds('A'), isEmpty);

    expect(await store.toggleManualPin(manual), isFalse);
    expect(store.isManualPinned(manual), isFalse);
    expect(store.pinnedKeys, isEmpty);
    expect(store.error, isNull);

    // 1b: a rejected unpin must keep the stored and active pins.
    repo.throwStaleOnSave = false;
    expect(await store.togglePin(work), isTrue);
    expect(await store.toggleManualPin(manual), isTrue);
    repo.throwStaleOnSave = true;
    expect(await store.togglePin(work), isFalse);
    expect(store.isPinned(work), isTrue);
    expect(await store.toggleManualPin(manual), isFalse);
    expect(store.isManualPinned(manual), isTrue);
    expect(store.pinnedKeys.toSet(), <String>{
      AssignmentStore.pinKeyOf(work),
      AssignmentStore.manualPinKeyOf(manual),
    });
    expect(await repo.loadPinnedIds('A'), <String>{
      AssignmentStore.pinKeyOf(work),
      AssignmentStore.manualPinKeyOf(manual),
    });
    expect(store.error, isNull);

    // 1c: the real repository owner guard rejects the same way.
    repo.throwStaleOnSave = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'journal_account_owner',
      AccountIdentity.hash('B'),
    );
    expect(await store.togglePin(work), isFalse);
    expect(store.isPinned(work), isTrue);
    expect(await store.toggleManualPin(manual), isFalse);
    expect(store.isManualPinned(manual), isTrue);
    expect(store.error, isNull);
    expect((store.error ?? '').contains('备份'), isFalse);
  });

  test(
      'reorderPinned returns false and keeps order unchanged on '
      'StaleSessionWriteException', () async {
    final work = core.sample('pin-order');
    final manual = _manual('m-order');
    final repo = _ControllablePinRepository();
    final store = await _pinStore(repo);
    await repo.mergeAndSave([work]);
    await store.restoreSession();
    expect(
      await store.saveNotebook(
        (_) => StudyNotebook(entries: [manual]),
        store.accountEpoch,
      ),
      isTrue,
    );
    expect(await store.togglePin(work), isTrue);
    expect(await store.toggleManualPin(manual), isTrue);
    final workKey = AssignmentStore.pinKeyOf(work);
    final manualKey = AssignmentStore.manualPinKeyOf(manual);
    final before = <String>[workKey, manualKey];
    expect(store.pinnedKeys.take(2), before);
    expect(store.hasManualPinOrder, isFalse);

    // 2a: a rejected save must not reorder memory or claim manual order.
    repo.throwStaleOnSave = true;
    expect(await store.reorderPinned([manualKey, workKey]), isFalse);
    expect(store.pinnedKeys.take(2), before);
    expect(store.hasManualPinOrder, isFalse);
    expect(store.error, isNull);
    final stored = await repo.loadPinnedAssignments('A');
    expect(stored.keys, before);
    expect(stored.manuallyOrdered, isFalse);

    // 2b: the real repository owner guard rejects the same way.
    repo.throwStaleOnSave = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'journal_account_owner',
      AccountIdentity.hash('B'),
    );
    expect(await store.reorderPinned([manualKey, workKey]), isFalse);
    expect(store.pinnedKeys.take(2), before);
    expect(store.hasManualPinOrder, isFalse);
    expect(store.error, isNull);
  });

  test(
      'reorderPinned syncs memory when an exam ends during a committed '
      'pin save', () async {
    final end = _now.add(const Duration(minutes: 1));
    final exam = Assignment(
      id: 'cx:exam:1:2:pin-reorder-boundary',
      courseName: '测试课程',
      title: '即将结束的考试',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: _now,
      source: AssignmentSource.exam,
      exam: ExamInfo(
        examId: 'pin-reorder-boundary',
        courseId: '1',
        clazzId: '2',
        endAt: end,
        endTrusted: true,
        lifecycle: 'scheduled',
      ),
    );
    final work = core.sample('pin-reorder-work');
    var clock = _now;
    final repo = _ControllablePinRepository();
    final store = await _pinStore(repo, clock: () => clock);
    await repo.mergeAndSave([exam, work]);
    await store.restoreSession();
    expect(await store.togglePin(exam), isTrue);
    expect(await store.togglePin(work), isTrue);
    final examKey = AssignmentStore.pinKeyOf(exam);
    final workKey = AssignmentStore.pinKeyOf(work);
    expect(store.pinnedKeys.take(2), <String>[examKey, workKey]);

    repo.onSaved = () => clock = end;
    expect(await store.reorderPinned([workKey, examKey]), isTrue);
    expect(store.canTogglePin(exam), isFalse);
    expect(store.pinnedKeys.take(2), <String>[workKey, examKey]);
    expect(store.hasManualPinOrder, isTrue);
    final stored = await repo.loadPinnedAssignments('A');
    expect(stored.keys, <String>[workKey, examKey]);
  });

  test(
      'togglePin and reorderPinned drop in-flight commit when logout or '
      'account switch occurs during save', () async {
    final work = core.sample('pin-flight-a');
    final work2 = core.sample('pin-flight-b');
    final session = core.Session();
    final repo = _ControllablePinRepository();
    final store = _FixedStore(session: session, repository: repo);
    addTearDown(store.dispose);
    await store.restoreSession();

    Future<void> seed() async {
      session.account = 'A';
      await store.restoreSession();
      await repo.mergeAndSave([work, work2]);
      await store.restoreSession();
      expect(store.account, 'A');
    }

    // 4a: logout during a togglePin save.
    await seed();
    final toggleStarted = Completer<void>();
    final toggleGate = Completer<void>();
    repo.saveStarted = toggleStarted;
    repo.saveGate = toggleGate;
    final pendingToggle = store.togglePin(work);
    await toggleStarted.future;
    final logoutFuture = store.logout();
    toggleGate.complete();
    expect(await pendingToggle, isFalse);
    await logoutFuture;
    expect(store.isAuthenticated, isFalse);
    expect(store.pinnedKeys, isEmpty);
    expect(store.error, isNull);

    // 4b: logout during a reorderPinned save.
    await seed();
    expect(await store.togglePin(work), isTrue);
    expect(await store.togglePin(work2), isTrue);
    final workKey = AssignmentStore.pinKeyOf(work);
    final secondKey = AssignmentStore.pinKeyOf(work2);
    expect(store.pinnedKeys.take(2), <String>[workKey, secondKey]);
    final reorderStarted = Completer<void>();
    final reorderGate = Completer<void>();
    repo.saveStarted = reorderStarted;
    repo.saveGate = reorderGate;
    final pendingReorder = store.reorderPinned([secondKey, workKey]);
    await reorderStarted.future;
    final reorderLogout = store.logout();
    reorderGate.complete();
    expect(await pendingReorder, isFalse);
    await reorderLogout;
    expect(store.isAuthenticated, isFalse);
    expect(store.pinnedKeys, isEmpty);

    // 4c: account switch while the reorder save is still held.
    await seed();
    expect(await store.togglePin(work), isTrue);
    expect(await store.togglePin(work2), isTrue);
    final switchStarted = Completer<void>();
    final switchGate = Completer<void>();
    repo.saveStarted = switchStarted;
    repo.saveGate = switchGate;
    final switchPending = store.reorderPinned([secondKey, workKey]);
    await switchStarted.future;
    final switchFuture = store.loginChaoxing(
      account: 'B',
      password: 'pw',
      agreementAccepted: true,
    );
    switchGate.complete();
    expect(await switchPending, isFalse);
    await switchFuture;
    expect(store.account, 'B');
    expect(store.pinnedKeys, isEmpty);
    expect(await repo.loadPinnedIds('B'), isEmpty);

    // 4d: the account switch makes the in-flight write report itself stale.
    if (store.isAuthenticated) await store.logout();
    await seed();
    expect(await store.togglePin(work), isTrue);
    expect(await store.togglePin(work2), isTrue);
    final staleStarted = Completer<void>();
    final staleGate = Completer<void>();
    repo.saveStarted = staleStarted;
    repo.saveGate = staleGate;
    repo.gateError = StaleSessionWriteException('switched');
    final stalePending = store.reorderPinned([secondKey, workKey]);
    await staleStarted.future;
    final staleSwitch = store.loginChaoxing(
      account: 'B',
      password: 'pw',
      agreementAccepted: true,
    );
    staleGate.complete();
    expect(await stalePending, isFalse);
    await staleSwitch;
    expect(store.account, 'B');
    expect(store.pinnedKeys, isEmpty);
    expect(await repo.loadPinnedIds('B'), isEmpty);
    expect(store.error, isNull);
  });

  test(
      '_prunePins preserves pending save retry across '
      'StaleSessionWriteException for refreshAssignments and saveNotebook',
      () async {
    // 5a: journal refresh prunes memory, then retries the disk write.
    final work = core.sample('pin-prune-refresh');
    final manual = _manual('m-prune');
    final repo = _ControllablePinRepository();
    final store = await _pinStore(repo);
    await repo.mergeAndSave([work]);
    await store.restoreSession();
    expect(
      await store.saveNotebook(
        (_) => StudyNotebook(entries: [manual]),
        store.accountEpoch,
      ),
      isTrue,
    );
    expect(await store.togglePin(work), isTrue);
    expect(await store.toggleManualPin(manual), isTrue);
    final workKey = AssignmentStore.pinKeyOf(work);
    final manualKey = AssignmentStore.manualPinKeyOf(manual);

    await repo.mergeAndSave(
      [core.sample('pin-prune-refresh', status: 'submitted')],
    );
    repo.throwStaleOnSave = true;
    await store.refreshAssignments();
    expect(store.isPinned(work), isFalse);
    expect((await repo.loadPinnedAssignments('A')).keys, contains(workKey));

    repo.throwStaleOnSave = false;
    await store.refreshAssignments();
    final stored = await repo.loadPinnedAssignments('A');
    expect(stored.keys, isNot(contains(workKey)));
    expect(stored.keys, contains(manualKey));

    // 5b: the last manual pin removed from memory retries via saveNotebook.
    SharedPreferences.setMockInitialValues({});
    final repo2 = _ControllablePinRepository();
    final store2 = await _pinStore(repo2);
    final first = _manual('m-prune-notebook');
    expect(
      await store2.saveNotebook(
        (_) => StudyNotebook(entries: [first]),
        store2.accountEpoch,
      ),
      isTrue,
    );
    expect(await store2.toggleManualPin(first), isTrue);
    final firstKey = AssignmentStore.manualPinKeyOf(first);
    expect((await repo2.loadPinnedAssignments('A')).keys, contains(firstKey));

    repo2.throwStaleOnSave = true;
    expect(
      await store2.saveNotebook(
        (n) => n.withEntries([
          for (final entry in n.entries)
            entry.id == first.id ? entry.completed(true) : entry,
        ]),
        store2.accountEpoch,
      ),
      isTrue,
    );
    expect(store2.pinnedKeys, isEmpty);
    expect((await repo2.loadPinnedAssignments('A')).keys, contains(firstKey));

    repo2.throwStaleOnSave = false;
    final second = _manual('m-prune-unrelated');
    expect(
      await store2.saveNotebook(
        (n) => n.withEntries([...n.entries, second]),
        store2.accountEpoch,
      ),
      isTrue,
    );
    expect((await repo2.loadPinnedAssignments('A')).keys, isEmpty);
  });

  test(
      'stale togglePin or reorderPinned does not clear pending prune save '
      'flag', () async {
    final work1 = core.sample('pin-pending-1');
    final work2 = core.sample('pin-pending-2');
    final manual = _manual('m-pending');
    final repo = _ControllablePinRepository();
    final store = await _pinStore(repo);
    await repo.mergeAndSave([work1, work2]);
    await store.restoreSession();
    expect(
      await store.saveNotebook(
        (_) => StudyNotebook(entries: [manual]),
        store.accountEpoch,
      ),
      isTrue,
    );
    expect(await store.togglePin(work1), isTrue);
    expect(await store.togglePin(work2), isTrue);
    expect(await store.toggleManualPin(manual), isTrue);
    final firstKey = AssignmentStore.pinKeyOf(work1);
    final secondKey = AssignmentStore.pinKeyOf(work2);
    final manualKey = AssignmentStore.manualPinKeyOf(manual);

    await repo.mergeAndSave(
      [core.sample('pin-pending-1', status: 'submitted')],
    );
    repo.throwStaleOnSave = true;
    await store.refreshAssignments();
    expect(store.isPinned(work1), isFalse);
    expect(store.pinnedKeys.take(2), <String>[secondKey, manualKey]);

    expect(await store.togglePin(work2), isFalse);
    expect(
      await store.reorderPinned([manualKey, secondKey]),
      isFalse,
    );
    expect(store.pinnedKeys.take(2), <String>[secondKey, manualKey]);
    expect(store.hasManualPinOrder, isFalse);
    expect(store.error, isNull);

    repo.throwStaleOnSave = false;
    await store.refreshAssignments();
    final stored = await repo.loadPinnedAssignments('A');
    expect(stored.keys, isNot(contains(firstKey)));
    expect(stored.keys, containsAll(<String>[secondKey, manualKey]));
  });
}

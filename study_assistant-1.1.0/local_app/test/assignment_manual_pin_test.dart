import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
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
  _FixedStore()
      : super(
          sessionStore: core.Session(),
          notificationService: core.Notifications(),
          widgetSnapshotService: core.WidgetService(),
          chaoxingClient: core.Client(),
          clock: () => _now,
        );

  @override
  Future<bool> runDueAutoSync({DateTime? now}) async => false;
}

Future<_FixedStore> _store() async {
  final store = _FixedStore();
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
    final store = _FixedStore();
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
    expect(store.notebook.entries, isEmpty);
    expect(store.isManualPinned(entry), isFalse);
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
}

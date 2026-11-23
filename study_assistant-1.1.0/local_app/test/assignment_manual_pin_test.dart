import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';

import 'review_core_remediation_test.dart' as core;

ManualEntry _manual(String id, {bool done = false}) => ManualEntry(
      id: id,
      title: '手动 $id',
      kind: 'todo',
      course: '个人',
      at: DateTime(2030, 11, 7, 9),
      done: done,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('manual pin mixes with coursework reorder and prunes on completion',
      () async {
    final assignment = core.sample('pin-a');
    final store = core.makeStore(core.Session());
    addTearDown(store.dispose);
    await store.restoreSession();
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
    final store = core.makeStore(session);
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
}

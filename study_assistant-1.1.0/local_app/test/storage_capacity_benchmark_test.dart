// Opt-in desktop/mocked-preferences measurement, never a device storage benchmark.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('synthetic storage capacity and CPU baseline', () async {
    final results = <Map<String, Object?>>[];
    final at = DateTime.utc(2026, 11, 6);
    for (final count in [32, 500, 2000]) {
      SharedPreferences.setMockInitialValues({});
      final repository = LocalAssignmentRepository();
      await repository.activateAccount('synthetic-a');
      final rows = [
        for (var i = 0; i < count; i++)
          Assignment(
              id: 'cx:work:1:2:$i',
              courseName: '合成课程',
              title: '合成作业$i',
              deadlineAt: at.add(Duration(days: i % 30)),
              requirementsText: '合成说明' * 40,
              status: i % 4 == 0 ? 'submitted' : 'pending',
              lastSyncedAt: at)
      ];
      final expected = {for (final row in rows) row.id: row.toJson()};
      await repository.mergeAndSave(rows);
      final merges = <int>[], loads = <int>[], switches = <int>[];
      for (var round = 0; round < 9; round++) {
        final w = Stopwatch()..start();
        await repository.mergeAndSave(rows);
        w.stop();
        if (round >= 2) merges.add(w.elapsedMicroseconds);
        w.reset();
        w.start();
        final loaded = await repository.loadJournal();
        w.stop();
        if (round >= 2) loads.add(w.elapsedMicroseconds);
        expect(loaded.length, count);
        expect({for (final row in loaded) row.id: row.toJson()}, expected);
        expect(loaded.where((a) => a.isCompleted).length, (count + 3) ~/ 4);
        w.reset();
        w.start();
        await repository.activateAccount('synthetic-b',
            previousAccount: 'synthetic-a');
        expect(await repository.loadJournal(), isEmpty);
        await repository.activateAccount('synthetic-a',
            previousAccount: 'synthetic-b');
        w.stop();
        if (round >= 2) switches.add(w.elapsedMicroseconds);
        final restored = await repository.loadJournal();
        expect({for (final row in restored) row.id: row.toJson()}, expected);
      }
      int median(List<int> v) {
        v.sort();
        return v[v.length ~/ 2];
      }

      final prefs = await SharedPreferences.getInstance();
      final journal = prefs.getString('chaoxing_journal_v2')!;
      final total = prefs.getKeys().fold<int>(0, (v, k) {
        final value = prefs.get(k);
        return v +
            utf8.encode(value is String ? value : jsonEncode(value)).length;
      });
      final notebook = StudyNotebook(terms: [
        for (var i = 0; i < 12; i++)
          TermArchive.capture(
              id: 'term$i',
              label: '合成学期$i',
              rows: rows,
              personal: PersonalWorkspace(),
              entries: [])
      ]);
      final raw = notebook.encode();
      var accepted = true;
      try {
        expect(StudyNotebook.decode(raw).terms.length, 12);
      } on FormatException {
        accepted = false;
        expect(utf8.encode(raw).length, greaterThan(4 * 1024 * 1024));
      }
      results.add({
        'records': count,
        'journalUtf8Bytes': utf8.encode(journal).length,
        'preferenceValuesUtf8BytesWithAccountArchives': total,
        'mockMergeMedianUs': median(merges),
        'mockLoadMedianUs': median(loads),
        'mockAccountRoundTripMedianUs': median(switches),
        'twelveSnapshotsUtf8Bytes': utf8.encode(raw).length,
        'twelveSnapshotsAccepted': accepted,
        'samples': 7,
        'warmups': 2
      });
    }
    // Output contains synthetic sizes/timings only, no records or identifiers.
    stdout.writeln('STORAGE_BENCHMARK_JSON=${jsonEncode(results)}');
  }, skip: !const bool.fromEnvironment('RUN_STORAGE_BENCHMARK'));
}

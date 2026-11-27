import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/models/pinned_assignments.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';

void main() {
  test('local pins follow the active account and clear with local data',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalAssignmentRepository();
    await repository.activateAccount('account-a');
    expect(await repository.loadPinnedIds('account-a'), isEmpty);
    await repository
        .savePinnedIds({' work-2 ', 'work-1', '', 'work-2'}, 'account-a');
    expect(await repository.loadPinnedIds('account-a'), {'work-1', 'work-2'});

    await repository.activateAccount('account-b');
    expect(await repository.loadPinnedIds('account-b'), isEmpty);
    await expectLater(repository.loadPinnedIds('account-a'), throwsStateError);
    await expectLater(repository.savePinnedIds({'wrong-account'}, 'account-a'),
        throwsStateError);
    await repository.savePinnedIds({'work-3'}, 'account-b');

    await repository.activateAccount('account-a');
    expect(await repository.loadPinnedIds('account-a'), {'work-1', 'work-2'});
    await repository.clear();
    await repository.activateAccount('account-b');
    expect(await repository.loadPinnedIds('account-b'), isEmpty);
  });

  test(
    'mergeAssignments skips previously completed assignments when refreshed',
    () {
      final existing = Assignment(
        id: 'web:course-1:work-1',
        courseName: '软件工程',
        title: '需求分析报告',
        deadlineAt: DateTime.parse('2026-05-08T10:00:00.000Z'),
        requirementsText: '提交 PDF',
        status: 'completed',
        completedAt: DateTime.parse('2026-05-05T10:00:00.000Z'),
        lastSyncedAt: DateTime.parse('2026-05-05T09:00:00.000Z'),
      );
      final incoming = Assignment(
        id: 'web:course-1:work-1',
        courseName: '软件工程',
        title: '需求分析报告（更新）',
        deadlineAt: DateTime.parse('2026-05-09T10:00:00.000Z'),
        requirementsText: '提交 PDF 和截图',
        status: 'pending',
        lastSyncedAt: DateTime.parse('2026-05-05T11:00:00.000Z'),
      );

      final merged = LocalAssignmentRepository.mergeAssignments(
        [existing],
        [incoming],
      );

      expect(merged, isEmpty);
    },
  );

  test('mergeAssignments skips assignments hidden by manual completion', () {
    final incoming = Assignment(
      id: 'web:course-1:work-1',
      courseName: '软件工程',
      title: '需求分析报告',
      deadlineAt: DateTime.parse('2026-05-09T10:00:00.000Z'),
      requirementsText: '提交 PDF',
      status: 'pending',
      lastSyncedAt: DateTime.parse('2026-05-05T11:00:00.000Z'),
    );

    final merged = LocalAssignmentRepository.mergeAssignments(
      [],
      [incoming],
      hiddenCompletedIds: {'web:course-1:work-1'},
    );

    expect(merged, isEmpty);
  });

  test('mergeAndSave hides assignments that are waiting for review', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalAssignmentRepository();
    final reviewing = Assignment(
      id: 'cx:activity:reviewing',
      courseName: '大学英语',
      title: '章节作业',
      deadlineAt: DateTime.parse('2026-05-09T10:00:00.000Z'),
      requirementsText: '完成后提交',
      status: 'submitted',
      lastSyncedAt: DateTime.parse('2026-05-05T11:00:00.000Z'),
    );

    final afterSync = await repository.mergeAndSave([reviewing]);
    final afterReload = await repository.loadAssignments();

    expect(afterSync, isEmpty);
    expect(afterReload, isEmpty);
  });

  test('FB-006 submitted null deadline keeps the last trusted deadline',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalAssignmentRepository();
    final trusted = DateTime.parse('2026-11-20T10:00:00.000Z');
    final first = Assignment(
      id: 'cx:work:course:class:submitted',
      courseName: '大学英语',
      title: '已提交作业',
      deadlineAt: trusted,
      requirementsText: '',
      status: 'submitted',
      deadlineTrusted: true,
      deadlineRawText: '2026-11-20 18:00',
      lastSyncedAt: DateTime.parse('2026-11-16T08:00:00.000Z'),
    );
    final refreshed = first.copyWith(
      deadlineTrusted: false,
      clearDeadlineAt: true,
      clearDeadlineRawText: true,
      lastSyncedAt: DateTime.parse('2026-11-16T09:00:00.000Z'),
    );

    await repository.mergeAndSave([first]);
    await repository.mergeAndSave([refreshed]);

    final stored = (await repository.loadJournal())
        .singleWhere((item) => item.id == first.id);
    expect(stored.status, 'submitted');
    expect(stored.deadlineAt!.toUtc(), trusted);
    expect(stored.deadlineTrusted, isTrue);
    expect(stored.deadlineRawText, '2026-11-20 18:00');
  });

  test('start evidence round-trips and survives a failed deadline refresh',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalAssignmentRepository();
    final published = DateTime.utc(2026, 11, 2, 3);
    final available = DateTime.utc(2026, 11, 16, 16);
    final deadline = DateTime.utc(2026, 11, 20, 10);
    final first = Assignment(
      id: 'cx:work:course:class:start',
      courseName: '信息安全技术',
      title: '第二次讨论作业',
      deadlineAt: deadline,
      publishedAt: published,
      availableFromAt: available,
      availableFromText: '2026-11-17 00:00',
      requirementsText: '',
      status: 'pending',
      deadlineTrusted: true,
      deadlineRawText: '2026-11-20 18:00',
      lastSyncedAt: DateTime.utc(2026, 11, 16, 8),
    );
    await repository.mergeAndSave([first]);
    await repository.mergeAndSave([
      first.copyWith(
        deadlineReadFailed: true,
        deadlineTrusted: false,
        clearDeadlineAt: true,
        lastSyncedAt: DateTime.utc(2026, 11, 16, 9),
      )
    ]);

    final stored = (await repository.loadJournal())
        .singleWhere((item) => item.id == first.id);
    expect(stored.deadlineAt!.toUtc(), deadline);
    expect(stored.publishedAt!.toUtc(), published);
    expect(stored.availableFromAt!.toUtc(), available);
    expect(stored.availableFromText, '2026-11-17 00:00');

    final json = stored.toJson();
    expect(json['publishedAt'], published.toIso8601String());
    expect(json['availableFromAt'], available.toIso8601String());
    final restored = Assignment.fromJson({
      ...json,
      'publishedAt': '2026-11-02 11:00',
    });
    expect(restored.publishedAt, isNull);
    expect(restored.availableFromAt!.toUtc(), available);
  });

  test(
    'mergeAssignments keeps unfinished peer review and filters completed peer review',
    () {
      final oldPeerReview = Assignment(
        id: 'cx:stu-work:peer-review',
        courseName: '大学英语',
        title: '互评作业',
        deadlineAt: DateTime.parse('2026-05-08T10:00:00.000Z'),
        requirementsText: '互评作业 已完成',
        status: 'pending',
        lastSyncedAt: DateTime.parse('2026-05-05T09:00:00.000Z'),
      );
      final incoming = Assignment(
        id: 'cx:stu-work:normal',
        courseName: '大学英语',
        title: '章节作业',
        deadlineAt: DateTime.parse('2026-05-09T10:00:00.000Z'),
        requirementsText: '提交 PDF',
        status: 'pending',
        lastSyncedAt: DateTime.parse('2026-05-05T11:00:00.000Z'),
      );
      final incomingPeerReview = Assignment(
        id: 'cx:stu-work:new-peer-review',
        courseName: '大学英语',
        title: '互评作业',
        deadlineAt: DateTime.parse('2026-05-09T10:00:00.000Z'),
        requirementsText: '互评作业 未完成',
        status: 'pending',
        lastSyncedAt: DateTime.parse('2026-05-05T11:00:00.000Z'),
      );

      final merged = LocalAssignmentRepository.mergeAssignments(
        [oldPeerReview],
        [incoming, incomingPeerReview],
      );

      expect(merged.map((item) => item.id), [
        'cx:stu-work:new-peer-review',
        'cx:stu-work:normal',
      ]);
    },
  );

  test(
    'mergeAssignments retains missing pending work until the server confirms its state',
    () {
      final oldPeerReview = Assignment(
        id: 'cx:stu-work:old-peer-review',
        courseName: '大学英语',
        title: '互评作业',
        deadlineAt: DateTime.parse('2026-05-08T10:00:00.000Z'),
        requirementsText: '互评作业',
        status: 'pending',
        lastSyncedAt: DateTime.parse('2026-05-05T09:00:00.000Z'),
      );
      final incoming = Assignment(
        id: 'cx:stu-work:new-work',
        courseName: '大学英语',
        title: '章节作业',
        deadlineAt: DateTime.parse('2026-05-09T10:00:00.000Z'),
        requirementsText: '提交 PDF',
        status: 'pending',
        lastSyncedAt: DateTime.parse('2026-05-05T11:00:00.000Z'),
      );

      final merged = LocalAssignmentRepository.mergeAssignments(
        [oldPeerReview],
        [incoming],
      );

      expect(merged.map((item) => item.id),
          ['cx:stu-work:old-peer-review', 'cx:stu-work:new-work']);
    },
  );

  test(
    'mergeAssignments filters completed peer review from latest sync result',
    () {
      final completedPeerReview = Assignment(
        id: 'cx:stu-work:completed-peer-review',
        courseName: '大学英语',
        title: '互评作业',
        deadlineAt: DateTime.parse('2026-05-09T10:00:00.000Z'),
        requirementsText: '互评作业 已互评',
        status: 'pending',
        lastSyncedAt: DateTime.parse('2026-05-05T11:00:00.000Z'),
      );

      final merged = LocalAssignmentRepository.mergeAssignments([], [
        completedPeerReview,
      ]);

      expect(merged, isEmpty);
    },
  );

  test('updateCompletion hides assignment across later syncs', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalAssignmentRepository();
    final assignment = Assignment(
      id: 'cx:stu-work:work-1',
      courseName: '大学英语',
      title: '章节作业',
      deadlineAt: DateTime.parse('2026-05-09T10:00:00.000Z'),
      requirementsText: '提交 PDF',
      status: 'pending',
      lastSyncedAt: DateTime.parse('2026-05-05T11:00:00.000Z'),
    );

    await repository.mergeAndSave([assignment]);
    final afterComplete = await repository.updateCompletion(
      assignment.id,
      true,
    );
    final afterRefresh = await repository.mergeAndSave([
      assignment.copyWith(
        lastSyncedAt: DateTime.parse('2026-05-05T12:00:00.000Z'),
      ),
    ]);

    expect(afterComplete, isEmpty);
    expect(afterRefresh, isEmpty);
    expect(await repository.loadAssignments(), isEmpty);
  });

  test('batch hide and restore updates every group source atomically',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalAssignmentRepository();
    final first = Assignment(
      id: 'cx:exam:1:2:3',
      source: AssignmentSource.exam,
      exam: const ExamInfo(examId: '3', courseId: '1', clazzId: '2'),
      courseName: '高等数学',
      title: '期末考试',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: DateTime.parse('2026-11-16T08:00:00.000Z'),
    );
    final second = Assignment(
      id: 'cx:examNotice:inbox:notice',
      source: AssignmentSource.exam,
      exam: const ExamInfo(
        examId: 'notice',
        relatedExamId: '3',
        courseId: '1',
        clazzId: '2',
        noticeOnly: true,
      ),
      courseName: '高等数学',
      title: '考试通知',
      deadlineAt: null,
      requirementsText: '',
      status: 'unknown',
      lastSyncedAt: DateTime.parse('2026-11-16T08:01:00.000Z'),
    );

    await repository.mergeAndSave([first, second]);
    await repository.updateCompletionMany([first.id, second.id], true);

    expect(await repository.loadAssignments(), isEmpty);
    expect(
      (await repository.loadHiddenAssignments()).map((item) => item.id).toSet(),
      {first.id, second.id},
    );

    await repository.updateCompletionMany([first.id, second.id], false);
    expect(
      (await repository.loadAssignments()).map((item) => item.id).toSet(),
      {first.id, second.id},
    );
  });

  test('batch hide rejects a stale account/session before writing', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalAssignmentRepository();
    final assignment = Assignment(
      id: 'cx:work:1:2:stale',
      courseName: '大学英语',
      title: '旧会话作业',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: DateTime.parse('2026-11-16T08:00:00.000Z'),
    );
    await repository.mergeAndSave([assignment]);

    await expectLater(
      repository.updateCompletionMany(
        [assignment.id],
        true,
        canCommit: () async => false,
      ),
      throwsStateError,
    );
    expect(await repository.loadHiddenAssignments(), isEmpty);
    expect((await repository.loadAssignments()).single.id, assignment.id);
  });

  group('Phase 2A PinnedAssignments v2 persistence', () {
    test(
        'migrates v1 pins without manual order, preserves v2 order per account, and rolls back failed writes',
        () async {
      SharedPreferences.setMockInitialValues({});
      final repository = LocalAssignmentRepository();
      await repository.activateAccount('alice');
      await repository.savePinnedIds({'w-b', 'w-a'}, 'alice');

      final migrated = await repository.loadPinnedAssignments('alice');
      expect(migrated.manuallyOrdered, isFalse);
      expect(migrated.keys, unorderedEquals(['w-a', 'w-b']));

      final ordered = PinnedAssignments(
        keys: ['w-b', 'w-c', 'w-a'],
        manuallyOrdered: true,
      );
      await repository.savePinnedAssignments(ordered, 'alice');
      expect((await repository.loadPinnedAssignments('alice')), ordered);
      expect(await repository.loadPinnedIds('alice'), {'w-a', 'w-b', 'w-c'});

      await repository.activateAccount('bob');
      expect((await repository.loadPinnedAssignments('bob')).isEmpty, isTrue);

      await repository.activateAccount('alice');
      expect((await repository.loadPinnedAssignments('alice')), ordered);

      // Failed write reloads SharedPreferences and preserves prior snapshot.
      final prefs = await SharedPreferences.getInstance();
      final originalStore = SharedPreferencesStorePlatform.instance;
      addTearDown(
          () => SharedPreferencesStorePlatform.instance = originalStore);
      SharedPreferencesStorePlatform.instance = _FailingPinPreferences({
        for (final k in prefs.getKeys()) 'flutter.$k': prefs.get(k)!,
      });
      await expectLater(
        repository.savePinnedAssignments(
          PinnedAssignments(keys: ['w-x'], manuallyOrdered: true),
          'alice',
        ),
        throwsA(isA<LocalStorageWriteException>()),
      );
      expect((await repository.loadPinnedAssignments('alice')), ordered);
    });

    test(
        'course metadata persists per account and decodes legacy 3-key course_refs cache',
        () async {
      SharedPreferences.setMockInitialValues({});
      final repository = LocalAssignmentRepository();
      await repository.activateAccount('alice');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'course_refs',
        jsonEncode([
          {'courseId': '1', 'clazzId': '2', 'name': '旧格式课程'},
        ]),
      );
      final legacyCourses = await repository.loadCourses(account: 'alice');
      expect(legacyCourses.single.teacherNames, isEmpty);
      expect(legacyCourses.single.folderName, isNull);

      const enriched = CourseRef(
        courseId: '1',
        clazzId: '2',
        name: '旧格式课程',
        teacherNames: ['赵老师', '钱老师'],
        folderName: '2026年秋',
      );
      await repository.saveCourses([enriched], account: 'alice');
      await repository.activateAccount('bob');
      expect(await repository.loadCourses(account: 'bob'), isEmpty);
      await repository.activateAccount('alice');
      final reloaded = await repository.loadCourses(account: 'alice');
      expect(reloaded.single.teacherNames, ['赵老师', '钱老师']);
      expect(reloaded.single.folderName, '2026年秋');
    });

    test(
        'M5 verified raw cache skips redundant decode, preserves damaged backup on external corruption, clears on account switch/clear, and saves >32KiB snapshots via Isolate.run',
        () async {
      SharedPreferences.setMockInitialValues({});
      final repository = LocalAssignmentRepository();
      await repository.activateAccount('alice');

      // 1) > 32 KiB notebook + personal workspace + journal roundtrip via real Isolate.run
      final entryNote = '备考笔记' * 250;
      final largeNotebook = StudyNotebook(
        entries: List.generate(
          40,
          (i) => ManualEntry(
            id: 'manual-large-$i',
            title: '大型待办快照测试$i',
            kind: 'todo',
            note: entryNote,
          ),
        ),
      );
      expect(largeNotebook.encode().length, greaterThan(32 * 1024));
      await repository.saveNotebook(largeNotebook, 'alice');
      final loadedNotebook = await repository.loadNotebook();
      expect(loadedNotebook.entries, hasLength(40));
      expect(loadedNotebook.entries.first.note, entryNote);

      // Subsequent save with identical verified raw hits cache cleanly.
      await repository.saveNotebook(loadedNotebook, 'alice');
      expect(repository.recoveryWarning, isNull);

      // 2) External corruption of the same key MUST bypass cache and trigger _backupDamagedValue.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notebook_v1', '{corrupted-json');
      await repository.saveNotebook(StudyNotebook(), 'alice');
      expect(prefs.getString('notebook_v1_recovery_backup'), '{corrupted-json');
      expect(repository.recoveryWarning, isNotNull);

      // 3) Large >32KiB journal mergeAndSave via Isolate.run
      final largeAssignments = List.generate(
        80,
        (i) => Assignment(
          id: 'cx:large:$i',
          courseName: '计算机网络',
          title: '第$i次大作业',
          deadlineAt: DateTime(2026, 5, 20, 18),
          requirementsText: '详细要求内容' * 120,
          status: 'pending',
          lastSyncedAt: DateTime(2026, 5, 10),
        ),
      );
      await repository.mergeAndSave(largeAssignments);
      final loadedJournal = await repository.loadJournal();
      expect(loadedJournal, hasLength(80));

      // 4) Post-encode canCommit re-check aborts stale large snapshot write
      //    after Isolate.run encoding completes.
      var checks = 0;
      await expectLater(
        repository.mergeAndSave(
          largeAssignments,
          canCommit: () async {
            checks++;
            return checks == 1;
          },
        ),
        throwsA(isA<StaleSessionWriteException>()),
      );
      expect(checks, 2);

      // 5) Account switch & clear invalidate verified raw cache safely.
      await repository.activateAccount('bob');
      expect((await repository.loadNotebook()).entries, isEmpty);
      await repository.clear();
      await repository.activateAccount('alice');
      expect((await repository.loadNotebook()).entries, isEmpty);
    });
  });
}

class _FailingPinPreferences extends InMemorySharedPreferencesStore {
  _FailingPinPreferences(super.data) : super.withData();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.pinned_assignments_v2') return false;
    return super.setValue(valueType, key, value);
  }
}

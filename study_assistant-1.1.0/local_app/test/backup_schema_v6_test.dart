import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/backup_snapshot.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/models/course_chapter_progress.dart';
import 'package:study_assistant_mobile/src/models/course_notice.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
      'keeps schema 5 when notices and chapters are empty, upgrades to schema 6 otherwise',
      () {
    final now = DateTime.utc(2030, 5, 1, 8, 0);
    final owner = BackupSnapshot.ownerFor('alice');
    final emptySnapshot = BackupSnapshot.create(
      owner: owner,
      createdAt: now,
      records: const [],
      hidden: const {},
      courses: const [],
      unfollowed: const {},
      reminderOffsets: const [120],
      autoSyncIntervalMinutes: 240,
    );
    expect(jsonDecode(emptySnapshot.encode())['schema'], 5);

    final notice = CourseNotice(
      id: 'cx:notice:${'1' * 64}',
      courseId: '7',
      clazzId: '11',
      courseName: '编译原理',
      title: '实验通知',
      publishedAt: now,
      publishedTrusted: true,
      extractedEventAt: now.add(const Duration(days: 2)),
      extractedEventTrusted: true,
      platformUnread: true,
      localRead: true,
      linkedManualEntryId: 'missing-entry-id',
      lastSyncedAt: now,
    );
    final validEntry = ManualEntry(
      id: 'chap-valid',
      title: '[章节任务点] 1.1 词法分析',
      kind: 'todo',
    );
    final chapter = CourseChapterSnapshot(
      courseId: '7',
      clazzId: '11',
      courseName: '编译原理',
      completedPoints: 2,
      totalPoints: 5,
      progressTrusted: true,
      nodes: [
        const ChapterNode(
          sectionId: 'cx:chapter:7:11:1:1.1',
          level: 1,
          code: '1.1',
          title: '词法分析',
          state: ChapterTaskState.pendingPoints,
          pendingPoints: 1,
          linkedManualEntryId: 'chap-valid',
        ),
        const ChapterNode(
          sectionId: 'cx:chapter:7:11:1:1.2',
          level: 1,
          code: '1.2',
          title: '语法分析',
          state: ChapterTaskState.pendingPoints,
          pendingPoints: 1,
          linkedManualEntryId: 'dangling-entry',
        ),
      ],
      lastSyncedAt: now,
    );

    final v6 = BackupSnapshot.create(
      owner: owner,
      createdAt: now,
      records: const [],
      hidden: const {},
      courses: const [CourseRef(courseId: '7', clazzId: '11', name: '编译原理')],
      unfollowed: const {},
      reminderOffsets: const [120],
      autoSyncIntervalMinutes: 240,
      notebook: StudyNotebook(entries: [validEntry]),
      notices: CourseNoticeCollection(items: [notice]),
      chapters: CourseChapterCatalog(byCourse: {'7:11': chapter}),
    );

    final encoded = v6.encode();
    expect(jsonDecode(encoded)['schema'], 6);
    final decoded = BackupSnapshot.decode(encoded);
    expect(decoded.notices.items, hasLength(1));
    expect(decoded.notices.items.single.localRead, isTrue);
    expect(decoded.notices.items.single.publishedTrusted, isFalse);
    expect(decoded.notices.items.single.extractedEventTrusted, isFalse);
    expect(decoded.notices.items.single.linkedManualEntryId, isNull);

    final restoredCourse = decoded.chapters.byCourse['7:11']!;
    expect(restoredCourse.progressTrusted, isFalse);
    expect(restoredCourse.nodes[0].linkedManualEntryId, 'chap-valid');
    expect(restoredCourse.nodes[1].linkedManualEntryId, isNull);
  });

  test(
      'LocalAssignmentRepository scopes notices and chapters by account and restores schema 6 backup',
      () async {
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('alice');

    final now = DateTime.utc(2030, 5, 1, 8, 0);
    await repo.saveCourses(
      const [CourseRef(courseId: '7', clazzId: '11', name: '编译原理')],
      account: 'alice',
    );
    await repo.saveCourseNotices(
      CourseNoticeCollection(items: [
        CourseNotice(
          id: 'cx:notice:${'2' * 64}',
          courseId: '7',
          clazzId: '11',
          courseName: '编译原理',
          title: 'Alice 通知',
          lastSyncedAt: now,
        ),
      ]),
      'alice',
    );
    await repo.saveCourseChapters(
      CourseChapterCatalog(byCourse: {
        '7:11': CourseChapterSnapshot(
          courseId: '7',
          clazzId: '11',
          courseName: '编译原理',
          completedPoints: 1,
          totalPoints: 2,
          progressTrusted: true,
          nodes: const [],
          lastSyncedAt: now,
        ),
      }),
      'alice',
    );

    final snapshot = await repo.createBackupSnapshot('alice');
    expect(snapshot.notices.items, hasLength(1));
    expect(snapshot.chapters.byCourse, hasLength(1));

    await repo.activateAccount('bob', previousAccount: 'alice');
    expect((await repo.loadCourseNotices()).items, isEmpty);
    expect((await repo.loadCourseChapters()).byCourse, isEmpty);

    await repo.activateAccount('alice', previousAccount: 'bob');
    expect((await repo.loadCourseNotices()).items, hasLength(1));
    expect((await repo.loadCourseChapters()).byCourse, hasLength(1));

    await repo.clear();
    await repo.activateAccount('alice');
    expect((await repo.loadCourseNotices()).items, isEmpty);
    expect((await repo.loadCourseChapters()).byCourse, isEmpty);

    expect(await repo.restoreBackupSnapshot(snapshot, 'alice'), isTrue);
    expect((await repo.loadCourseNotices()).items.single.title, 'Alice 通知');
    expect(
        (await repo.loadCourseChapters()).byCourse['7:11']?.completedPoints, 1);
  });

  test(
      'schema 7 round-trips publication and start evidence without restoring trust',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('alice');
    final publishedAt = DateTime.utc(2026, 11, 2, 3);
    final availableFromAt = DateTime.utc(2026, 11, 16, 16);
    await repo.mergeAndSave([
      Assignment(
        id: 'cx:work:7:11:9',
        courseName: '编译原理',
        title: '第二次讨论作业',
        deadlineAt: DateTime.utc(2026, 11, 20, 10),
        publishedAt: publishedAt,
        availableFromAt: availableFromAt,
        availableFromText: '2026-11-17 00:00',
        deadlineTrusted: true,
        requirementsText: '正文包含 https://example.test/work?enc=secret',
        status: 'pending',
        lastSyncedAt: DateTime.utc(2026, 11, 19, 8),
        submitUrl: 'https://example.test/work?enc=secret',
      )
    ]);

    final snapshot = await repo.createBackupSnapshot('alice');
    final raw = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
    expect(raw['schema'], 7);
    expect(raw, contains('notices'));
    expect(raw, contains('chapters'));
    final portable = (raw['records'] as List).single as Map<String, dynamic>;
    expect(
      portable.keys,
      containsAll(['publishedAt', 'availableFromAt', 'availableFromText']),
    );
    expect(portable['publishedAt'], publishedAt.toIso8601String());
    expect(portable['availableFromAt'], availableFromAt.toIso8601String());
    expect(portable['availableFromText'], '2026-11-17 00:00');
    expect(snapshot.encode(), isNot(contains('enc=secret')));

    final decoded = BackupSnapshot.decode(snapshot.encode());
    expect(decoded.records.single.publishedAt!.toUtc(), publishedAt);
    expect(decoded.records.single.availableFromAt!.toUtc(), availableFromAt);
    expect(decoded.records.single.availableFromText, '2026-11-17 00:00');

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('chaoxing_journal_v2');
    await repo.restoreBackupSnapshot(decoded, 'alice');
    final restored = (await repo.loadJournal()).single;
    expect(restored.publishedAt!.toUtc(), publishedAt);
    expect(restored.availableFromAt!.toUtc(), availableFromAt);
    expect(restored.availableFromText, '2026-11-17 00:00');
    expect(restored.status, 'unknown');
    expect(restored.deadlineTrusted, isFalse);
    expect(restored.submitUrl, isNull);
    expect(restored.requirementsText, isEmpty);
  });

  test('schema 7 omits or rejects malformed start evidence', () {
    final now = DateTime.utc(2030, 5, 1, 8);
    final owner = BackupSnapshot.ownerFor('alice');
    Assignment work({String? publishedAt, String? availableFromText}) =>
        Assignment(
          id: 'cx:work:7:11:10',
          courseName: '编译原理',
          title: '讨论作业',
          deadlineAt: now,
          publishedAt: publishedAt == null ? null : now,
          availableFromText: availableFromText,
          requirementsText: '',
          status: 'pending',
          lastSyncedAt: now,
        );

    final ignoredText = BackupSnapshot.create(
      owner: owner,
      createdAt: now,
      records: [work(availableFromText: 'https://example.test/secret')],
      hidden: const {},
      courses: const [],
      unfollowed: const {},
      reminderOffsets: const [120],
      autoSyncIntervalMinutes: 240,
    );
    final ignoredRaw = jsonDecode(ignoredText.encode()) as Map<String, dynamic>;
    expect(ignoredRaw['schema'], 5);
    expect(
      (ignoredRaw['records'] as List).single,
      isNot(contains('availableFromText')),
    );

    final validRaw = jsonDecode(
      BackupSnapshot.create(
        owner: owner,
        createdAt: now,
        records: [
          work(
            publishedAt: now.toIso8601String(),
            availableFromText: '2030-05-01 08:00',
          )
        ],
        hidden: const {},
        courses: const [],
        unfollowed: const {},
        reminderOffsets: const [120],
        autoSyncIntervalMinutes: 240,
      ).encode(),
    ) as Map<String, dynamic>;
    expect(validRaw['schema'], 7);

    final badText = jsonDecode(jsonEncode(validRaw)) as Map<String, dynamic>;
    ((badText['records'] as List).single as Map)['availableFromText'] =
        'https://example.test/secret';
    expect(
      () => BackupSnapshot.decode(jsonEncode(badText)),
      throwsFormatException,
    );

    final badDate = jsonDecode(jsonEncode(validRaw)) as Map<String, dynamic>;
    ((badDate['records'] as List).single as Map)['publishedAt'] =
        '2026-11-02 11:00';
    expect(
      () => BackupSnapshot.decode(jsonEncode(badDate)),
      throwsFormatException,
    );
  });

  test('overlong optional start text cannot block the whole export', () {
    final now = DateTime.utc(2030, 5, 1, 8);
    final owner = BackupSnapshot.ownerFor('alice');
    final overlong = '11-20${' ' * 48}08:00';
    final snapshot = BackupSnapshot.create(
      owner: owner,
      createdAt: now,
      records: [
        Assignment(
          id: 'cx:work:7:11:20',
          courseName: '编译原理',
          title: '超长可选文本',
          deadlineAt: now,
          availableFromText: overlong,
          deadlineTrusted: true,
          requirementsText: '',
          status: 'pending',
          lastSyncedAt: now,
        ),
        Assignment(
          id: 'cx:work:7:11:21',
          courseName: '编译原理',
          title: '正常作业',
          deadlineAt: now.add(const Duration(days: 1)),
          deadlineTrusted: true,
          requirementsText: '',
          status: 'pending',
          lastSyncedAt: now,
        ),
      ],
      hidden: const {},
      courses: const [],
      unfollowed: const {},
      reminderOffsets: const [120],
      autoSyncIntervalMinutes: 240,
    );
    final raw = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
    expect(raw['schema'], 5);
    final records = (raw['records'] as List).cast<Map<String, dynamic>>();
    expect(records, hasLength(2));
    expect(
      records.singleWhere((r) => r['id'] == 'cx:work:7:11:20'),
      isNot(contains('availableFromText')),
    );
    expect(snapshot.records, hasLength(2));
    expect(snapshot.records.first.availableFromText, isNull);

    final tampered = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
    ((tampered['records'] as List).first as Map)['availableFromText'] =
        overlong;
    expect(
      () => BackupSnapshot.decode(jsonEncode(tampered)),
      throwsFormatException,
    );
  });

  test('backup-only time evidence cannot grant archival grace after sync',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('alice');
    final now = DateTime.utc(2026, 11, 19, 4);
    final id = 'cx:work:7:11:11';
    final oldDeadline = DateTime.utc(2026, 7, 1, 10);
    await repo.mergeAndSave([
      Assignment(
        id: id,
        courseName: '编译原理',
        title: '旧学期讨论作业',
        deadlineAt: oldDeadline,
        publishedAt: DateTime.utc(2026, 11, 10),
        availableFromAt: DateTime.utc(2026, 11, 12),
        availableFromText: '11-12 08:00',
        deadlineTrusted: true,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: DateTime.utc(2026, 7, 1, 10),
      )
    ]);
    final backup = await repo.createBackupSnapshot('alice');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('chaoxing_journal_v2');
    await repo.restoreBackupSnapshot(backup, 'alice');
    final restored = (await repo.loadJournal()).single;
    expect(restored.publishedAt, isNotNull);
    expect(restored.lastSyncedAt.millisecondsSinceEpoch, 0);

    await repo.mergeAndSave([
      Assignment(
        id: id,
        courseName: '编译原理',
        title: '旧学期讨论作业',
        deadlineAt: oldDeadline,
        deadlineTrusted: true,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: DateTime.utc(2026, 11, 19, 3),
      )
    ]);
    final synced = (await repo.loadJournal()).single;
    expect(synced.publishedAt, isNull);
    expect(synced.availableFromAt, isNull);
    expect(synced.availableFromText, isNull);
    expect(AssignmentQuery.isArchivedPastTerm(synced, now), isTrue);
  });

  test('time evidence from an earlier genuine sync remains mergeable',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('alice');
    final now = DateTime.utc(2026, 11, 19, 4);
    final id = 'cx:work:7:11:12';
    final publishedAt = DateTime.utc(2026, 11, 10);
    final availableFromAt = DateTime.utc(2026, 11, 12);
    await repo.mergeAndSave([
      Assignment(
        id: id,
        courseName: '编译原理',
        title: '旧学期讨论作业',
        deadlineAt: DateTime.utc(2026, 7, 1, 10),
        publishedAt: publishedAt,
        availableFromAt: availableFromAt,
        availableFromText: '11-12 08:00',
        deadlineTrusted: true,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: DateTime.utc(2026, 11, 18, 3),
      )
    ]);
    await repo.mergeAndSave([
      Assignment(
        id: id,
        courseName: '编译原理',
        title: '旧学期讨论作业',
        deadlineAt: DateTime.utc(2026, 7, 1, 10),
        deadlineTrusted: true,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: DateTime.utc(2026, 11, 19, 3),
      )
    ]);

    final synced = (await repo.loadJournal()).single;
    expect(synced.publishedAt!.toUtc(), publishedAt);
    expect(synced.availableFromAt!.toUtc(), availableFromAt);
    expect(synced.availableFromText, '11-12 08:00');
    expect(AssignmentQuery.isArchivedPastTerm(synced, now), isFalse);
  });
}

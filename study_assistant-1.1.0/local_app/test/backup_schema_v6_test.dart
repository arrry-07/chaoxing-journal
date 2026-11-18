import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/backup_snapshot.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/models/course_chapter_progress.dart';
import 'package:study_assistant_mobile/src/models/course_notice.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';

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
}

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_api_parser.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_chapter_parser.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/models/course_chapter_progress.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';

const _course = ChaoxingCourseRef(
  courseId: '2001',
  clazzId: '3001',
  courseName: '数字信号处理',
  cpi: '9001',
);

const _sampleHtml = '''
<div class="top">已完成任务点: <span class="num">5</span>/12</div>
<ul class="chapter_list">
  <li>
    <div class="catalog_num fl"><span><i><em>1</em></i></span></div>
    <div class="catalog_name newCatalog_name"><a class="clicktitle"><span title="信号基础 &amp; 系统">信号基础</span></a></div>
  </li>
  <li>
    <div class="chapter_item" title="1.1 离散时间信号">
      <span class="catalog_sbar">1.1</span>
      <span class="catalog_task"><span class="icon_yiwanc"></span></span>
    </div>
  </li>
  <li>
    <div class="chapter_item" title="1.2 Z 变换">
      <span class="catalog_sbar">1.2</span>
      <span class="catalog_task"><span class="catalog_points_yi">3</span></span>
    </div>
  </li>
  <li>
    <div class="chapter_item" title="1.3 实验讨论">
      <span class="catalog_sbar">1.3</span>
      <span class="catalog_task">暂未开放</span>
    </div>
  </li>
  <li>
    <div class="chapter_item" title="1.4 扩展阅读">
      <span class="catalog_sbar">1.4</span>
      <span class="catalog_task"></span>
    </div>
  </li>
</ul>
''';

void main() {
  test(
      'parses chapter progress summary and ordered chapter/section states like reference CLI',
      () {
    final snapshot = ChaoxingChapterParser.parse(_sampleHtml, _course);
    expect(snapshot, isNotNull);
    expect(snapshot!.progressTrusted, isTrue);
    expect(snapshot.completedPoints, 5);
    expect(snapshot.totalPoints, 12);
    expect(snapshot.pendingSectionCount, 1);
    expect(snapshot.pendingPointTotal, 3);
    expect(snapshot.nodes, hasLength(5));

    expect(snapshot.nodes[0].level, 0);
    expect(snapshot.nodes[0].code, '1');
    expect(snapshot.nodes[0].title, '信号基础 & 系统');

    expect(snapshot.nodes[1].level, 1);
    expect(snapshot.nodes[1].code, '1.1');
    expect(snapshot.nodes[1].state, ChapterTaskState.completed);

    expect(snapshot.nodes[2].level, 1);
    expect(snapshot.nodes[2].code, '1.2');
    expect(snapshot.nodes[2].state, ChapterTaskState.pendingPoints);
    expect(snapshot.nodes[2].pendingPoints, 3);

    expect(snapshot.nodes[3].state, ChapterTaskState.locked);
    expect(snapshot.nodes[4].state, ChapterTaskState.noTaskPoints);
  });

  test('marks progressTrusted false when summary counter is absent or invalid',
      () {
    final noBar = _sampleHtml.replaceFirst(
      RegExp(r'<div class="top">.*?</div>'),
      '',
    );
    final snapshot = ChaoxingChapterParser.parse(noBar, _course);
    expect(snapshot, isNotNull);
    expect(snapshot!.progressTrusted, isFalse);
    expect(snapshot.completedPoints, isNull);
    expect(snapshot.totalPoints, isNull);
    expect(snapshot.nodes, hasLength(5));
  });

  test(
      'oversized chapter fields and colliding codes survive catalog round trip',
      () {
    final codePrefix = '1' * 59;
    final longTitle = '节' * 510;
    final longCourseName = '课' * 260;
    String section(String code) => '''
  <li>
    <div class="chapter_item" title="$longTitle">
      <span class="catalog_sbar">$code</span>
      <span class="catalog_task"><span class="catalog_points_yi">1500</span></span>
    </div>
  </li>
''';
    final course = ChaoxingCourseRef(
      courseId: '1' * 120,
      clazzId: '2' * 120,
      courseName: longCourseName,
      cpi: '9001',
    );
    final snapshot = ChaoxingChapterParser.parse(
      '''
<ul class="chapter_list">
  ${section('${codePrefix}23')}
  ${section('${codePrefix}24')}
  ${section('${codePrefix}34')}
</ul>
''',
      course,
      now: DateTime.utc(2026, 11, 22),
    );
    expect(snapshot, isNotNull);
    final catalog = CourseChapterCatalog().upsertCourse(snapshot!);
    final restored = CourseChapterCatalog.decode(catalog.encode());

    expect(restored.toJson(), catalog.toJson());
    final persisted = restored.byCourse[snapshot.courseKey]!;
    expect(persisted.courseName, '课' * 200);
    expect(persisted.nodes.map((node) => node.code),
        ['${codePrefix}2', '${codePrefix}2', '${codePrefix}3']);
    expect(persisted.nodes.map((node) => node.title), everyElement('节' * 500));
    expect(persisted.nodes.map((node) => node.pendingPoints), [999, 999, 999]);
    final ids = persisted.nodes.map((node) => node.sectionId).toList();
    expect(ids.toSet(), hasLength(3));
    expect(ids.map((id) => id.length), everyElement(lessThanOrEqualTo(300)));
    expect(ids[1], endsWith('#2'));
  });

  test('chapter parser and snapshot reject the same invalid course identities',
      () {
    final now = DateTime.utc(2026, 11, 22);
    final baseline =
        ChaoxingChapterParser.parse(_sampleHtml, _course, now: now)!;
    final invalidIds = {
      'empty': '',
      'overlong': '1' * 121,
      'colon': '1:2',
      'embedded whitespace': '1 2',
      'control character': '1\x002',
      'DEL': '1\x7f2',
    };
    final acceptedByParser = <String>[];
    for (final field in ['courseId', 'clazzId']) {
      for (final entry in invalidIds.entries) {
        final reason = '$field: ${entry.key}';
        expect(
          () => CourseChapterSnapshot.fromJson(
            {...baseline.toJson(), field: entry.value},
          ),
          throwsFormatException,
          reason: reason,
        );
        final course = ChaoxingCourseRef(
          courseId: field == 'courseId' ? entry.value : _course.courseId,
          clazzId: field == 'clazzId' ? entry.value : _course.clazzId,
          courseName: _course.courseName,
          cpi: _course.cpi,
        );
        if (ChaoxingChapterParser.parse(_sampleHtml, course, now: now) !=
            null) {
          acceptedByParser.add(reason);
        }
      }
    }
    expect(acceptedByParser, isEmpty);
  });

  test('blank parsed course name falls back to a persistable label', () {
    const course = ChaoxingCourseRef(
      courseId: '2001',
      clazzId: '3001',
      courseName: '   ',
      cpi: '9001',
    );
    final snapshot = ChaoxingChapterParser.parse(
      _sampleHtml,
      course,
      now: DateTime.utc(2026, 11, 22),
    )!;
    final restored = CourseChapterSnapshot.fromJson(snapshot.toJson());
    expect(restored.courseName, '未命名课程');
  });

  test('throws chapterAccessDenied and rejects unknown HTML', () {
    expect(
      () => ChaoxingChapterParser.parse('<html>没有此页面访问权限</html>', _course),
      throwsA(isA<StateError>()
          .having((e) => e.message, 'msg', 'chapterAccessDenied')),
    );
    expect(
      ChaoxingChapterParser.parse('<html><body>404</body></html>', _course),
      isNull,
    );
  });

  test(
      'ChaoxingLocalClient.fetchCourseChapters resolves enc/openc and throws when missing',
      () async {
    var missingEnc = false;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.uri.path == '/visit/stucoursemiddle') {
          final body = missingEnc
              ? '<div>missing</div>'
              : '<input id="enc" value="enc-abc"><input id="openc" value="openc-xyz"><input id="cpi" value="9001">';
          h.resolve(Response(requestOptions: o, data: body, statusCode: 200));
          return;
        }
        if (o.uri.path == '/mooc2-ans/mycourse/studentcourse') {
          expect(o.uri.queryParameters['enc'], 'enc-abc');
          expect(o.uri.queryParameters['openc'], 'openc-xyz');
          expect(o.uri.queryParameters['fromMiddle'], '1');
          h.resolve(Response(
            requestOptions: o,
            data: _sampleHtml,
            statusCode: 200,
          ));
          return;
        }
        throw StateError('unexpected ${o.uri.path}');
      }));

    final client = ChaoxingLocalClient(dio: dio, wait: (_) async {});
    final snapshot = await client.fetchCourseChapters(_course);
    expect(snapshot.completedPoints, 5);
    expect(snapshot.totalPoints, 12);

    missingEnc = true;
    await expectLater(
      client.fetchCourseChapters(_course),
      throwsA(isA<SyncReadException>()
          .having((e) => e.issue.kind, 'kind', SyncIssueKind.schemaChanged)),
    );
  });
}

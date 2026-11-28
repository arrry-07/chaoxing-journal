import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_api_parser.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_assignment_parser.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_exam_parser.dart';

void main() {
  test('large signed work HTML round-trips through the async parser', () async {
    final html = '''
<!--${'padding' * 5000}-->
<li onclick="goTask(this);" data="/work/doHomeWorkNew?workId=333">
  <p class="overHidden2 fl">签名作业</p><p class="status fl">未提交</p>
</li>
''';
    final now = DateTime.utc(2026, 11, 28);
    expect(html.length,
        greaterThan(ChaoxingAssignmentParser.isolateParseThreshold));
    final rows = await ChaoxingAssignmentParser.parseSignedWorkListAsync(
      html,
      courseId: '111',
      clazzId: '222',
      courseName: '计算机网络',
      baseUri: Uri.parse('https://mooc1.chaoxing.com/mooc2/work/list'),
      now: now,
    );
    final row = rows!.single;
    expect(row.id, 'cx:work:111:222:333');
    expect(row.title, '签名作业');
    expect(row.courseName, '计算机网络');
    expect(row.submitUrl,
        'https://mooc1.chaoxing.com/work/doHomeWorkNew?workId=333');
    expect(row.lastSyncedAt.toUtc(), now);
  });

  test('parses Chaoxing work HTML into local assignments', () {
    const html = '''
      <div class="course-name">软件工程</div>
      <div class="work-item" data-id="work-1">
        <a href="/work/123">需求分析报告</a>
        <span>截止时间：2026-05-08 18:00</span>
        <p class="desc">提交 Markdown 与 PDF</p>
      </div>
    ''';

    final assignments = ChaoxingAssignmentParser.parseWorkHtml(
      html,
      fallbackCourseName: '默认课程',
      sourcePrefix: 'course-1',
      baseUri: Uri.parse('https://mooc1-api.chaoxing.com'),
    );

    expect(assignments, hasLength(1));
    expect(assignments.first.title, '需求分析报告');
    expect(assignments.first.courseName, '软件工程');
    expect(
      assignments.first.deadlineAt!.toUtc().toIso8601String(),
      '2026-05-08T10:00:00.000Z',
    );
    expect(assignments.first.requirementsText, contains('提交 Markdown'));
    expect(
      assignments.first.submitUrl,
      'https://mooc1-api.chaoxing.com/work/123',
    );
  });

  test('parses Chaoxing stu-work nav items with remaining time', () {
    const html = '''
      <ul class="nav">
        <li data="https://mooc1-api.chaoxing.com/work/doHomeWorkNew?courseId=111&clazzId=222&taskrefId=333">
          <div role="option">
            <p>章节测验</p>
            <span class="status">未提交</span>
            <span>大学英语</span>
            <span class="fr">剩余 2 天</span>
          </div>
        </li>
      </ul>
    ''';

    final assignments = ChaoxingAssignmentParser.parseWorkHtml(
      html,
      fallbackCourseName: '默认课程',
      sourcePrefix: 'stu-work',
      baseUri: Uri.parse('https://mooc1-api.chaoxing.com/work/stu-work'),
      now: DateTime(2026, 5, 5, 8),
    );

    expect(assignments, hasLength(1));
    expect(assignments.first.id, 'cx:stu-work:333');
    expect(assignments.first.title, '章节测验');
    expect(assignments.first.courseName, '大学英语');
    expect(assignments.first.deadlineAt, DateTime(2026, 5, 7, 8));
    expect(assignments.first.submitUrl, contains('courseId=111'));
  });

  test(
    'keeps unfinished peer review work and skips completed peer review work',
    () {
      const html = '''
      <ul class="nav">
        <li data="https://mooc1-api.chaoxing.com/work/doHomeWorkNew?courseId=111&clazzId=222&taskrefId=333">
          <p>互评作业</p>
          <span>大学英语</span>
          <span>已互评</span>
          <span>截止时间：2026-05-08 18:00</span>
        </li>
        <li data="https://mooc1-api.chaoxing.com/work/doHomeWorkNew?courseId=111&clazzId=222&taskrefId=334">
          <p>互评作业</p>
          <span>大学英语</span>
          <span>未完成</span>
          <span>截止时间：2026-05-09 18:00</span>
        </li>
      </ul>
    ''';

      final assignments = ChaoxingAssignmentParser.parseWorkHtml(
        html,
        fallbackCourseName: '默认课程',
        sourcePrefix: 'stu-work',
        baseUri: Uri.parse('https://mooc1-api.chaoxing.com/work/stu-work'),
      );

      expect(assignments, hasLength(1));
      expect(assignments.first.id, 'cx:stu-work:334');
    },
  );

  test('keeps peer review work when description asks to complete review', () {
    const html = '''
      <ul class="nav">
        <li data="https://mooc1-api.chaoxing.com/work/doHomeWorkNew?courseId=111&clazzId=222&taskrefId=335">
          <p>互评作业</p>
          <span>大学英语</span>
          <span>请在截止前完成互评</span>
          <span>截止时间：2026-05-09 18:00</span>
        </li>
      </ul>
    ''';

    final assignments = ChaoxingAssignmentParser.parseWorkHtml(
      html,
      fallbackCourseName: '默认课程',
      sourcePrefix: 'stu-work',
      baseUri: Uri.parse('https://mooc1-api.chaoxing.com/work/stu-work'),
    );

    expect(assignments.single.id, 'cx:stu-work:335');
    expect(assignments.single.status, 'unknown');
  });

  test(
      'M4 >32KiB work HTML and exam payloads parse via real Isolate.run matching sync results',
      () async {
    final now = DateTime(2026, 5, 5, 8);
    final pad = '<!-- ${'x' * 36000} -->';
    final largeWorkHtml = '''
      $pad
      <div class="course-name">编译原理</div>
      <div class="work-item" data-id="work-iso-1">
        <a href="/work/999">词法分析器实验</a>
        <span>截止时间：2026-05-12 23:59</span>
        <p class="desc">提交源码压缩包</p>
      </div>
    ''';
    expect(largeWorkHtml.length, greaterThan(32 * 1024));

    final syncWork = ChaoxingAssignmentParser.parseWorkHtml(
      largeWorkHtml,
      fallbackCourseName: '默认课程',
      sourcePrefix: 'course-iso',
      baseUri: Uri.parse('https://mooc1-api.chaoxing.com'),
      now: now,
    );
    final asyncWork = await ChaoxingAssignmentParser.parseWorkHtmlAsync(
      largeWorkHtml,
      fallbackCourseName: '默认课程',
      sourcePrefix: 'course-iso',
      baseUri: Uri.parse('https://mooc1-api.chaoxing.com'),
      now: now,
    );
    expect(asyncWork, hasLength(1));
    expect(asyncWork.single.id, syncWork.single.id);
    expect(asyncWork.single.title, '词法分析器实验');
    expect(asyncWork.single.deadlineAt, syncWork.single.deadlineAt);

    const course = ChaoxingCourseRef(
      courseId: '7',
      clazzId: '11',
      courseName: '编译原理',
    );
    final largePhoneExamHtml =
        '$pad<table class="listTable"><tr data="/exam/phone/task-exam?courseId=7&amp;classId=11&amp;taskrefId=888"><td>期中机试</td><td>不得保留成绩</td><td>未开始</td><td></td></tr></table><script>var havemore=false;</script>';
    expect(largePhoneExamHtml.length, greaterThan(32 * 1024));
    final syncPhone =
        ChaoxingExamParser.phone(largePhoneExamHtml, course, now: now);
    final asyncPhone = await ChaoxingExamParser.phoneAsync(
      largePhoneExamHtml,
      course,
      now: now,
    );
    expect(syncPhone, isNotNull);
    expect(asyncPhone, isNotNull);
    expect(asyncPhone!.rows, hasLength(1));
    expect(asyncPhone.rows.single.id, syncPhone!.rows.single.id);
    expect(asyncPhone.rows.single.title, '期中机试');
    expect(asyncPhone.rows.single.exam?.examId, '888');

    final largeCoursePcHtml =
        '''$pad<input id="courseId" value="7"><input id="classId" value="11"><ul><li class="lookLi"><div class="titTxt"><p><a title="期末上机考试" onclick="show(0)">期末上机考试</a></p><span>2026-06-15 14:00 至 2026-06-15 16:00</span><span><strong>已完成<strong onclick="goTest('7','777','2','2026','3','0','secret')">不得保留成绩</strong></strong></span></div></li></ul><script>page.showPage(0/9+1,Math.ceil(1/9),"changePage");</script>''';
    expect(largeCoursePcHtml.length, greaterThan(32 * 1024));
    final syncPc =
        ChaoxingExamParser.coursePc(largeCoursePcHtml, course, now: now);
    final asyncPc = await ChaoxingExamParser.coursePcAsync(
      largeCoursePcHtml,
      course,
      now: now,
    );
    expect(syncPc, isNotNull);
    expect(asyncPc, isNotNull);
    expect(asyncPc!.rows, hasLength(1));
    expect(asyncPc.rows.single.id, syncPc!.rows.single.id);
    expect(asyncPc.rows.single.title, '期末上机考试');
    expect(asyncPc.rows.single.exam?.examId, '777');

    final refer = Uri.encodeComponent(
      '/exam-ans/exam/test/examcode/examnotes?courseId=7&classId=11&examId=666',
    );
    final largeAccountHtml = '''
$pad
<table class="dataTable">
  <tr><th>序号</th><th>考试名称</th><th>时间</th><th>时长</th><th>考试状态</th><th>作答状态</th><th>分数</th><th>方式</th><th>操作</th></tr>
  <tr class="dataTr">
    <td>1</td><td>全校通识考试</td><td>2026-06-20 10:00 至 2026-06-20 12:00</td><td>120</td><td>未开始</td><td>未交</td><td>--</td><td>线上</td>
    <td><a href="javascript:;" onclick="go('https://mooc1-api.chaoxing.com/exam-ans/mycourse/transfer?moocId=7&amp;clazzid=11&amp;refer=$refer', stopExam)">查看</a></td>
  </tr>
</table>
<script>page.showPage(0/12+1,Math.ceil(1/12));</script>
''';
    expect(largeAccountHtml.length, greaterThan(32 * 1024));
    final syncAcc = ChaoxingExamParser.account(largeAccountHtml, now: now);
    final asyncAcc = await ChaoxingExamParser.accountAsync(
      largeAccountHtml,
      now: now,
    );
    expect(syncAcc, isNotNull);
    expect(asyncAcc, isNotNull);
    expect(asyncAcc!.rows, hasLength(1));
    expect(asyncAcc.rows.single.id, syncAcc!.rows.single.id);
    expect(asyncAcc.rows.single.title, '全校通识考试');
    expect(asyncAcc.rows.single.exam?.examId, '666');

    final largeNoticeRawJson = jsonEncode({
      'status': true,
      'notices': {
        'list': List.generate(
          60,
          (i) => {
            'uuid': 'notice-iso-$i',
            'title': '考试通知 $i',
            'content':
                '考试名称：编译原理考试$i\n考试时间：2026-06-21 09:00 至 2026-06-21 11:00\n说明：${'详情内容' * 150}',
            'sendTime': '2026-05-05 08:00:00',
          },
        ),
      },
    });
    expect(largeNoticeRawJson.length, greaterThan(32 * 1024));
    final syncNotices =
        ChaoxingExamParser.notices(largeNoticeRawJson, now: now);
    final asyncNotices = await ChaoxingExamParser.noticesAsync(
      largeNoticeRawJson,
      now: now,
      rawLengthHint: largeNoticeRawJson.length,
    );
    expect(syncNotices, isNotNull);
    expect(asyncNotices, isNotNull);
    expect(asyncNotices!.rows, hasLength(60));
    expect(asyncNotices.rows.length, syncNotices!.rows.length);
    expect(asyncNotices.rows.first.id, syncNotices.rows.first.id);
    expect(asyncNotices.rows.first.title, syncNotices.rows.first.title);
    expect(asyncNotices.rows.first.exam?.noticeOnly, isTrue);
  });
}

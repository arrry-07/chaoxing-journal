import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_assignment_parser.dart';

void main() {
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
}

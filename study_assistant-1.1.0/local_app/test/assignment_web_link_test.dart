import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_web_link.dart';

void main() {
  Assignment record(String? url) => Assignment(
      id: 'cx:work:1:2:3',
      courseName: '合成课程',
      title: '合成作业',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      submitUrl: url,
      lastSyncedAt: DateTime.utc(2026));
  const signed =
      'https://mooc1.chaoxing.com/mooc-ans/work/task?courseId=1&classId=2&workId=3&enc=a%2Bb%3d&x=1&x=2';

  test('returns the exact signed URL without rebuilding query encoding', () {
    expect(AssignmentWebLink.validatedUrl(record(signed)), signed);
  });
  test('accepts the documented task identity aliases with absent course fields',
      () {
    const url = 'https://mooc1.chaoxing.com/work/task?taskrefId=3&enc=abc';
    expect(AssignmentWebLink.validatedUrl(record(url)), url);
  });
  for (final raw in <String?>[
    null,
    '',
    ' $signed',
    '$signed ',
    signed.replaceFirst('https:', 'http:'),
    'javascript:alert(1)',
    'studyassistant:///assignments/cx:work:1:2:3',
    signed.replaceFirst('mooc1.chaoxing.com', 'evilchaoxing.com'),
    signed.replaceFirst('mooc1.chaoxing.com', 'chaoxing.com.evil.example'),
    signed.replaceFirst('mooc1.chaoxing.com', 'user@mooc1.chaoxing.com'),
    signed.replaceFirst('mooc1.chaoxing.com', '@mooc1.chaoxing.com'),
    signed.replaceFirst('mooc1.chaoxing.com', 'mooc1.chaoxing.com:444'),
    signed.replaceFirst('mooc1.chaoxing.com', 'mooc1.chaoxing.com:'),
    signed.replaceFirst('/work/task', '/work/%2Ftask'),
    signed.replaceFirst('/work/task', '/work/%5Ctask'),
    signed.replaceFirst('/mooc-ans/work/task', '/passport/login'),
    signed.replaceFirst('courseId=1', 'courseId=9'),
    signed.replaceFirst('classId=2', 'classId=9'),
    signed.replaceFirst('workId=3', 'workId=9'),
    signed.replaceFirst('&workId=3', ''),
    '$signed&courseId=9',
    '$signed&CourseId=9',
    '$signed&clazzid=9',
    '$signed&taskrefId=9',
    '$signed#https://evil.example',
  ]) {
    test('rejects unsafe cached homework URL ${raw?.split('?').first}', () {
      expect(AssignmentWebLink.validatedUrl(record(raw)), isNull);
    });
  }
}

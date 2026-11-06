import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';

void main() {
  test('nullable fields preserve by default and clear only with explicit flags',
      () {
    final now = DateTime.utc(2026, 11, 6);
    final a = Assignment(
        id: 'cx:work:1:2:3',
        title: '合成作业',
        courseName: '合成课程',
        deadlineAt: now,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
        deadlineRawText: '历史原始文本',
        submitUrl: 'https://mooc1.chaoxing.com/work/task?workId=3');
    expect(a.copyWith().deadlineRawText, a.deadlineRawText);
    expect(a.copyWith().submitUrl, a.submitUrl);
    final cleared =
        a.copyWith(clearDeadlineRawText: true, clearSubmitUrl: true);
    expect(cleared.deadlineRawText, isNull);
    expect(cleared.submitUrl, isNull);
    expect(cleared.deadlineAt, now);
    expect(cleared.status, 'pending');
    final restored = Assignment.fromJson(cleared.toJson());
    expect(restored.submitUrl, isNull);
    expect(restored.deadlineRawText, isNull);
    expect(a.copyWith(submitUrl: 'replacement').submitUrl, 'replacement');
    expect(
        a
            .copyWith(deadlineRawText: 'new', clearDeadlineRawText: true)
            .deadlineRawText,
        isNull);
  });
}

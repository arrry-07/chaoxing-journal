import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';
import 'package:study_assistant_mobile/src/services/assignment_web_link.dart';

Assignment activity(
        {int? type = 35,
        String status = 'pending',
        AssignmentAvailability availability = AssignmentAvailability.available,
        String? url}) =>
    Assignment(
        id: 'cx:activity:101:202:303',
        activityType: type,
        availability: availability,
        courseName: '合成课程',
        title: '个人任务',
        deadlineAt: DateTime.utc(2026, 12, 2),
        requirementsText: '',
        status: status,
        lastSyncedAt: DateTime.utc(2026, 11, 15),
        submitUrl: url ??
            'https://mobilelearn.chaoxing.com/page/renwuNew/stu/taskDetailStuForAnswer_new?courseId=101&classId=202&activeId=303&fid=0');

void main() {
  test('supported classroom tasks enter the same home scope as formal work',
      () {
    final task = activity();
    expect(task.isFormal, isFalse);
    expect(task.workId, isNull);
    expect(task.activityId, '303');
    expect(task.courseKey, '101:202');
    expect(AssignmentQuery.filterHome([task], now: DateTime.utc(2026, 11, 15)),
        [task]);
    expect(
        AssignmentQuery.scope(
            [activity(type: 47), activity(type: 77), activity(type: null)], {}),
        isEmpty);
    expect(
        AssignmentQuery.scope(
            [activity(availability: AssignmentAvailability.unavailable)], {}),
        isEmpty);
  });
  test('task links require matching course class and activity identity', () {
    final task = activity();
    expect(AssignmentWebLink.validatedUrl(task), task.submitUrl);
    for (final url in [
      '${task.submitUrl}&activeId=999',
      task.submitUrl!.replaceFirst('classId=202', 'classId=999'),
      task.submitUrl!.replaceFirst(
          '/page/renwuNew/stu/taskDetailStuForAnswer_new',
          '/widget/pcpick/stu/index'),
      task.submitUrl!.replaceFirst(
          'mobilelearn.chaoxing.com', 'evil.chaoxing.com.evil.example'),
    ]) {
      expect(AssignmentWebLink.validatedUrl(activity(url: url)), isNull);
    }
    final quiz = activity(
        type: 42,
        url:
            'https://mobilelearn.chaoxing.com/page/quiz/stu/answerQuestion2?courseId=101&classId=202&activeId=303');
    expect(AssignmentWebLink.validatedUrl(quiz), quiz.submitUrl);
    expect(AssignmentWebLink.validatedUrl(activity(type: 42)), isNull);
  });
}

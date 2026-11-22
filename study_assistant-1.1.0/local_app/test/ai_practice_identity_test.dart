import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/backup_snapshot.dart';
import 'package:study_assistant_mobile/src/services/assignment_web_link.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_ai_practice_parser.dart';

const pub = '11111111-1111-4111-8111-111111111111';
const entry =
    'https://mooc2-ans.chaoxing.com/ai-evaluate/v2/redirect/active/stu?courseid=7&clazzid=11&publishUuid=$pub';
Assignment record() => Assignment(
    id: 'opaque',
    source: AssignmentSource.classroomActivity,
    persistedCourseTaskKey: 'cx:activity:7:11:77',
    activityType: 77,
    aiPracticePublishUuid: pub,
    submitUrl: entry,
    courseName: '合成课程',
    title: 'AI 实践',
    deadlineAt: null,
    requirementsText: '',
    status: 'pending',
    lastSyncedAt: DateTime.utc(2030));

void main() {
  test('AI practice page context accepts mixed-case class field by name', () {
    final context = ChaoxingAiPracticeParser.pageContext(
      record(),
      '<input id="currentUserId" value="8"><input id="cpi" value="9">'
      '<input name="CoUrSeId" value="7"><input name="jClassId" value="11">'
      '<input id="publishRelationUuid" value="$pub">',
      uid: '8',
      expectedCpi: '9',
    );
    expect((context['courseid'], context['clazzid']), ('7', '11'));
    expect(context['publishRelationUuid'], pub);
  });

  test(
      'opaque activity identity survives journal and portable backup without resource URL',
      () {
    final a = Assignment.fromJson(record().toJson());
    expect(a.courseTaskKey, 'cx:activity:7:11:77');
    expect(a.activityId, '77');
    expect(AssignmentWebLink.validatedUrl(a), entry);
    final backup = BackupSnapshot.create(
        owner: BackupSnapshot.ownerFor('synthetic'),
        createdAt: DateTime.utc(2030),
        records: [a],
        hidden: {},
        courses: [],
        unfollowed: {},
        reminderOffsets: [60],
        autoSyncIntervalMinutes: 30);
    final restored = backup.records.single;
    expect(restored.isSupportedClassroomTask, isTrue);
    expect(restored.courseTaskKey, a.courseTaskKey);
    expect(restored.submitUrl, isNull);
    expect(restored.aiPracticePublishUuid, isNull);
    expect(AssignmentWebLink.validatedUrl(restored), isNull);
  });
  test('AI links reject wrong resources and conflicting identity aliases', () {
    for (final bad in [
      entry.replaceFirst(pub, '22222222-2222-4222-8222-222222222222'),
      '$entry&publishUuid=22222222-2222-4222-8222-222222222222',
      '$entry&classId=999',
      '$entry&courseId=999',
      entry.replaceFirst('/active/stu', '/active/tea'),
      entry.replaceFirst('mooc2-ans.chaoxing.com', 'evil.chaoxing.com'),
      entry.replaceFirst('https:', 'http:'),
      '$entry#fragment',
    ]) {
      expect(AssignmentWebLink.validatedUrl(record().copyWith(submitUrl: bad)),
          isNull);
      expect(record().copyWith(submitUrl: bad).activityId, '77');
    }
  });
  test(
      'aggregate personal score needs valid grading policy and scored attempts',
      () {
    final context = {'cpi': '8', 'publishRelationUuid': 'relation'};
    Assignment parse(dynamic score, dynamic count, dynamic scored, dynamic type,
            dynamic threshold) =>
        ChaoxingAiPracticeParser.personal(
            record(),
            {
              'status': true,
              'data': {
                'personId': '8',
                'publishRelationUuid': 'relation',
                'answerCount': count,
                'scoreCount': scored,
                'answerScore': score,
                'publishSetting': {
                  'scoreType': type,
                  'reachStandard': threshold
                },
                'endTime': '2030-01-02 00:00:00',
              }
            },
            context);
    for (final type in [0, 1, 2]) {
      expect(parse(60, 2, 2, type, 60).status, 'submitted');
      expect(parse(59, 2, 2, type, 60).status, 'pending');
    }
    expect(parse(99, 2, 0, 2, 60).status, 'unknown');
    expect(parse(99, 2, 3, 2, 60).status, 'unknown');
    expect(parse(99, 2, 2, 9, 60).status, 'unknown');
    expect(parse(double.nan, 2, 2, 2, 60).status, 'unknown');
    expect(parse(99, 2, 2, 2, null).status, 'unknown');
  });
}

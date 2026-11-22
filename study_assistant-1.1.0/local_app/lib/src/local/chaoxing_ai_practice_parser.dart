import 'dart:convert';
import '../models/assignment.dart';
import '../models/ai_practice_entry.dart';
import 'chaoxing_assignment_parser.dart';
import 'chaoxing_classroom_parser.dart';
import 'chaoxing_param_helper.dart';

class ChaoxingAiPracticeParser {
  static Assignment seedEntry(Assignment seed, dynamic content) {
    try {
      final data = content is String ? jsonDecode(content) : content;
      final raw = data is Map ? data['stuUrl'] : null;
      if (raw is! String) return seed;
      var uri = Uri.tryParse(raw);
      if (uri?.scheme == 'http' &&
          uri?.host == AiPracticeEntry.host &&
          uri?.port == 80 &&
          uri?.userInfo.isEmpty == true) {
        uri = uri!.replace(scheme: 'https', port: 443);
      }
      final valid = AiPracticeEntry.validate(uri?.toString() ?? '',
          courseId: seed.courseId!, clazzId: seed.clazzId!);
      return valid == null
          ? seed
          : seed.copyWith(
              submitUrl: valid.toString(),
              aiPracticePublishUuid: AiPracticeEntry.publication(valid));
    } on FormatException {
      return seed;
    }
  }

  static Map<String, String> pageContext(Assignment seed, String html,
      {required String? uid, String? expectedCpi}) {
    String value(String id) =>
        ChaoxingAssignmentParser.hiddenValue(html, id) ?? '';
    final cpi = value('cpi'), relation = value('publishRelationUuid');
    if (uid == null ||
        value('currentUserId') != uid ||
        ChaoxingParamHelper.hiddenInputValue(
                html, ChaoxingParamHelper.courseIdKeys) !=
            seed.courseId ||
        ChaoxingParamHelper.hiddenInputValue(
                html, ChaoxingParamHelper.clazzIdKeys) !=
            seed.clazzId ||
        cpi.isEmpty ||
        (expectedCpi != null && cpi != expectedCpi) ||
        !AiPracticeEntry.isUuid(relation)) {
      throw const FormatException('aiPracticePageIdentity');
    }
    return {
      'courseid': seed.courseId!,
      'clazzid': seed.clazzId!,
      'cpi': cpi,
      'publishRelationUuid': relation,
      'recordUuid': ''
    };
  }

  static Assignment personal(
      Assignment seed, dynamic payload, Map<String, String> context) {
    if (payload is! Map ||
        payload['status'] != true ||
        payload['data'] is! Map) {
      throw const FormatException('aiPracticePersonalSchema');
    }
    final data = payload['data'] as Map;
    if (data['personId']?.toString() != context['cpi'] ||
        data['publishRelationUuid'] != context['publishRelationUuid']) {
      throw const FormatException('aiPracticePersonalIdentity');
    }
    int? integer(dynamic v) => int.tryParse('$v');
    double? number(dynamic v) {
      final n = double.tryParse('$v');
      return n != null && n.isFinite && n >= 0 && n <= 100 ? n : null;
    }

    final count = integer(data['answerCount']),
        scored = integer(data['scoreCount']);
    final setting = data['publishSetting'];
    final scoreType = setting is Map ? integer(setting['scoreType']) : null;
    final threshold = setting is Map ? number(setting['reachStandard']) : null;
    final score = number(data['answerScore']);
    var status = 'unknown';
    if (count != null &&
        count >= 0 &&
        scored != null &&
        scored >= 0 &&
        scored <= count) {
      if (count == 0 && scored == 0 && score == null) status = 'pending';
      if (scored > 0 &&
          score != null &&
          threshold != null &&
          const {0, 1, 2}.contains(scoreType)) {
        // The server aggregate already applies average/latest/highest policy.
        status = score >= threshold ? 'submitted' : 'pending';
      }
    }
    final deadline = ChaoxingClassroomParser.absoluteTime(data['endTime']);
    final noLimit =
        const {'不限', '无截止时间', '不限制', 'no limit'}.contains(data['endTime']);
    return seed.copyWith(
        status: status,
        availability: AssignmentAvailability.available,
        deadlineAt: deadline,
        clearDeadlineAt: deadline == null,
        deadlineTrusted: deadline != null || noLimit,
        clearCompletedAt: true,
        deadlineRawText: noLimit ? '不限' : null,
        clearDeadlineRawText: !noLimit);
  }
}

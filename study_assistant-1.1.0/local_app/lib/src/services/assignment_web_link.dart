import '../models/ai_practice_entry.dart';
import '../models/assignment.dart';

/// Validate at the browser/clipboard boundary, including previously cached data.
/// Return the original string: rebuilding a signed URL can invalidate its enc.
class AssignmentWebLink {
  static String? validatedUrl(Assignment assignment) {
    final raw = assignment.submitUrl;
    if (assignment.isSupportedClassroomTask && assignment.activityType == 77) {
      return raw != null &&
              assignment.aiPracticePublishUuid != null &&
              assignment.availability != AssignmentAvailability.unavailable &&
              AiPracticeEntry.validate(raw,
                      courseId: assignment.courseId!,
                      clazzId: assignment.clazzId!,
                      publishUuid: assignment.aiPracticePublishUuid) !=
                  null
          ? raw
          : null;
    }
    if (raw == null ||
        raw.isEmpty ||
        raw.trim() != raw ||
        RegExp(r'[\x00-\x20\\]').hasMatch(raw)) {
      return null;
    }
    try {
      final uri = Uri.tryParse(raw);
      // Uri normalizes an empty userinfo or port away. Inspect their original
      // syntax too, rather than silently accepting an abnormal cached URL.
      final authority = RegExp(r'^https://([^/?#]+)', caseSensitive: false)
          .firstMatch(raw)?[1];
      if (uri == null ||
          authority == null ||
          authority.contains('@') ||
          (authority.contains(':') && !authority.endsWith(':443')) ||
          uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          uri.port != 443 ||
          uri.hasFragment ||
          !(uri.host == 'chaoxing.com' || uri.host.endsWith('.chaoxing.com')) ||
          !RegExp(r'^[a-z0-9-]+(?:\.[a-z0-9-]+)*$').hasMatch(uri.host) ||
          (assignment.isSupportedClassroomTask
              ? !_activityPathMatches(assignment.activityType!, uri.path)
              : !RegExp(
                      r'^/(?:mooc-ans/(?:mooc2/)?|mooc2/|mooc2-ans/)?work/[a-zA-Z0-9_.-]+$')
                  .hasMatch(uri.path))) {
        return null;
      }

      if (assignment.isSupportedClassroomTask) {
        if (assignment.availability == AssignmentAvailability.unavailable) {
          return null;
        }
        final expected = {
          'courseid': assignment.courseId,
          'classid': assignment.clazzId,
          'clazzid': assignment.clazzId,
          'jclassid': assignment.clazzId,
          'activeid': assignment.activityId
        };
        final found = <String>{};
        for (final entry in uri.queryParametersAll.entries) {
          final key = entry.key.toLowerCase();
          if (!expected.containsKey(key)) continue;
          if (entry.value.any((v) => v.isEmpty || v != expected[key])) {
            return null;
          }
          found.add(key);
        }
        if (!found.contains('courseid') ||
            !found.contains('activeid') ||
            !found.any(
                (k) => const {'classid', 'clazzid', 'jclassid'}.contains(k))) {
          return null;
        }
        return raw;
      }

      final expected = {
        'courseid': assignment.courseId,
        'classid': assignment.clazzId,
        'clazzid': assignment.clazzId,
        'jclassid': assignment.clazzId,
        'workid': assignment.workId,
        'taskrefid': assignment.workId,
      };
      var hasWorkIdentity = false;
      for (final entry in uri.queryParametersAll.entries) {
        final key = entry.key.toLowerCase();
        if (!expected.containsKey(key)) continue;
        if (key == 'workid' || key == 'taskrefid') hasWorkIdentity = true;
        // Check every spelling and repeated value, not only the first alias.
        if (entry.value.any((value) =>
            value.isEmpty ||
            (expected[key] != null && value != expected[key]))) {
          return null;
        }
      }
      if (!hasWorkIdentity || assignment.workId == null) return null;
      return raw;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  static bool _activityPathMatches(int type, String path) {
    if (type == 42) return path == '/page/quiz/stu/answerQuestion2';
    if (type != 35) return false;
    return const {
      '/page/renwuNew/stu/taskDetailStuForAnswer_new',
      '/page/renwuNew/stu/taskDetailStuAndAnsDetail_new',
      '/page/renwu/stu/taskDetailStuForAnswer',
      '/page/renwu/stu/taskDetailStuAndAnsDetail',
      '/page/renwuNew/notGroup/taskDetailStuForAnswerNotGroup_new',
      '/page/renwuNew/notGroup/taskDetailStuAndAnsDetailNotGroup_new',
      '/page/renwu/notGroup/taskDetailStuForAnswerNotGroup',
      '/page/renwu/notGroup/taskDetailStuAndAnsDetailNotGroup',
    }.contains(path);
  }
}

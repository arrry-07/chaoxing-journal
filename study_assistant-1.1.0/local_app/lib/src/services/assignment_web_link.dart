import '../models/assignment.dart';

/// Validate at the browser/clipboard boundary, including previously cached data.
/// Return the original string: rebuilding a signed URL can invalidate its enc.
class AssignmentWebLink {
  static String? validatedUrl(Assignment assignment) {
    final raw = assignment.submitUrl;
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
          !RegExp(r'^/(?:mooc-ans/(?:mooc2/)?|mooc2/|mooc2-ans/)?work/[a-zA-Z0-9_.-]+$')
              .hasMatch(uri.path)) {
        return null;
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
}

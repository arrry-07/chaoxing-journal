/// The publication UUID is a resource reference, never the PPT activity ID.
class AiPracticeEntry {
  static const host = 'mooc2-ans.chaoxing.com';
  static const path = '/ai-evaluate/v2/redirect/active/stu';
  static bool isUuid(String? value) =>
      value != null &&
      RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
          .hasMatch(value);

  static Uri? validate(String raw,
      {required String courseId,
      required String clazzId,
      String? publishUuid}) {
    if (RegExp(r'[\x00-\x20\\]').hasMatch(raw)) return null;
    final uri = Uri.tryParse(raw);
    final authority = RegExp(r'^https://([^/?#]+)').firstMatch(raw)?[1];
    if (uri == null ||
        authority == null ||
        authority.contains('@') ||
        (authority.contains(':') && !authority.endsWith(':443')) ||
        uri.scheme != 'https' ||
        uri.host != host ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.path != path) {
      return null;
    }
    final values = <String, String>{};
    for (final entry in uri.queryParametersAll.entries) {
      var key = entry.key.toLowerCase();
      if (key == 'classid' || key == 'jclassid') key = 'clazzid';
      if (!const {'courseid', 'clazzid', 'publishuuid'}.contains(key)) continue;
      for (final value in entry.value) {
        if (value.isEmpty ||
            (values.containsKey(key) && values[key] != value)) {
          return null;
        }
        values[key] = value;
      }
    }
    if (values['courseid'] != courseId ||
        values['clazzid'] != clazzId ||
        !isUuid(values['publishuuid']) ||
        (publishUuid != null && values['publishuuid'] != publishUuid)) {
      return null;
    }
    return uri;
  }

  static String publication(Uri uri) => uri.queryParameters.entries
      .firstWhere((e) => e.key.toLowerCase() == 'publishuuid')
      .value;
}

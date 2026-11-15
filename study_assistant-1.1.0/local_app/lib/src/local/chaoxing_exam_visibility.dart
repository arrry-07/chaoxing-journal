/// Remove only the confirmed, explicitly hidden start-code popups when checking
/// an official PC exam list for a challenge. The original response still goes
/// to the exam parser; this does not authorize opening an exam or sending a code.
String examListChallengeBody(String body,
    {required Uri uri, required String requestKind}) {
  if (requestKind != '课程考试' ||
      uri.scheme != 'https' ||
      uri.port != 443 ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      !const {'mooc1.chaoxing.com', 'mooc1-api.chaoxing.com'}
          .contains(uri.host) ||
      !const {'/exam/test', '/exam-ans/exam/test'}.contains(uri.path)) {
    return body;
  }

  final stack = <({int start, bool hiddenPopup})>[];
  final hidden = <({int start, int end})>[];
  var previousEnd = 0;
  for (final token in _htmlTags.allMatches(body)) {
    // A malformed div token cannot establish a safe closing boundary.
    if (_divToken.hasMatch(body.substring(previousEnd, token.start))) {
      return body;
    }
    previousEnd = token.end;
    final tag = token[0]!;
    final div = _divHead.firstMatch(tag);
    if (div == null) continue;
    if (div[1] == '/') {
      if (stack.isEmpty) return body;
      final opening = stack.removeLast();
      if (opening.hiddenPopup) {
        hidden.add((start: opening.start, end: token.end));
      }
    } else {
      // HTML divs are not void elements; ambiguous self-closing markup stays.
      if (tag.endsWith('/>')) return body;
      stack.add((start: token.start, hiddenPopup: _isHiddenStartPopup(tag)));
    }
  }
  if (_divToken.hasMatch(body.substring(previousEnd)) ||
      stack.any((opening) => opening.hiddenPopup)) {
    // In particular, do not erase a closed child of an unclosed hidden popup.
    return body;
  }
  if (hidden.isEmpty) return body;
  hidden.sort((a, b) => a.start.compareTo(b.start));
  final result = StringBuffer();
  var offset = 0;
  for (final range in hidden) {
    if (range.start < offset) continue; // Already inside a removed ancestor.
    result.write(body.substring(offset, range.start));
    result.write(' '); // Do not join unrelated words across a removed popup.
    offset = range.end;
  }
  result.write(body.substring(offset));
  return result.toString();
}

// Consume complete tags (including quoted attributes) and comments, so a fake
// div inside an attribute/comment cannot alter the nesting depth.
final _htmlTags = RegExp(
    r'''<!--[\s\S]*?(?:-->|$)|</?[A-Za-z][A-Za-z0-9:-]*\b(?:[^"'<>]|"[^"]*"|'[^']*')*>''',
    caseSensitive: false);
final _divHead = RegExp(r'^<(/?)div(?=[\s/>])', caseSensitive: false);
final _divToken = RegExp(r'</?div(?=[\s/>]|$)', caseSensitive: false);
final _tagAttributes = RegExp(
    r'''(?:^|\s)([A-Za-z_:][A-Za-z0-9_:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))''',
    caseSensitive: false);

bool _isHiddenStartPopup(String tag) {
  final attributes = <String, String>{};
  for (final attribute in _tagAttributes.allMatches(tag)) {
    final name = attribute[1]!.toLowerCase();
    if (name != 'id' && name != 'style') continue;
    if (attributes.containsKey(name)) return false;
    attributes[name] = attribute[2] ?? attribute[3] ?? attribute[4]!;
  }
  if (!const {
    'tipWin',
    'identifyCodeInp',
    'reTest-tipWin',
    'reTest-identifyCodeInp'
  }.contains(attributes['id'])) {
    return false;
  }
  final displays = (attributes['style'] ?? '')
      .split(';')
      .where((declaration) =>
          declaration.split(':').first.trim().toLowerCase() == 'display')
      .toList();
  // Multiple/unsupported declarations are deliberately not interpreted as hidden.
  return displays.length == 1 &&
      RegExp(r'^\s*display\s*:\s*none\s*(?:!\s*important\s*)?$',
              caseSensitive: false)
          .hasMatch(displays.single);
}

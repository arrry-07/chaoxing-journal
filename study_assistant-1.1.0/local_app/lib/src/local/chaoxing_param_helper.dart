/// Reads Chaoxing identity parameters without choosing between conflicts.
class ChaoxingParamHelper {
  const ChaoxingParamHelper._();

  static const courseIdKeys = {'courseid'};
  static const clazzIdKeys = {'clazzid', 'classid', 'jclassid'};
  static const examClazzIdKeys = {'clazzid', 'classid'};
  static const examIdKeys = {'examid'};
  static const moocIdKeys = {'moocid'};
  static const workIdKeys = {'workid', 'taskrefid'};

  static String? singleQueryValue(Uri uri, Set<String> lowerKeys) {
    String? value;
    for (final entry in uri.queryParametersAll.entries) {
      if (!lowerKeys.contains(entry.key.toLowerCase())) continue;
      final values = entry.value
          .map((raw) => raw.trim())
          .where((raw) => raw.isNotEmpty)
          .iterator;
      if (!values.moveNext()) continue;
      final next = values.current;
      if (values.moveNext() || (value != null && value != next)) return null;
      value = next;
    }
    return value;
  }

  /// Optional query identities may be omitted, but conflicting values may not.
  static bool hasAnyQueryValue(Uri uri, Set<String> lowerKeys) =>
      uri.queryParametersAll.entries.any((entry) =>
          lowerKeys.contains(entry.key.toLowerCase()) &&
          entry.value.any((raw) => raw.trim().isNotEmpty));

  static String? singleMapValue(
      Map<dynamic, dynamic> map, Set<String> lowerKeys) {
    String? value;
    for (final entry in map.entries) {
      if (!lowerKeys.contains(entry.key.toString().toLowerCase())) continue;
      final next = _nonEmpty(entry.value);
      if (next == null) continue;
      if (value != null && value != next) return null;
      value = next;
    }
    return value;
  }

  static bool hasAnyKey(Map<dynamic, dynamic>? map, Set<String> lowerKeys) =>
      map?.entries.any((entry) =>
          lowerKeys.contains(entry.key.toString().toLowerCase()) &&
          _nonEmpty(entry.value) != null) ??
      false;

  static final _input = RegExp(
    r'''<input(?=[\s/>])(?:[^>"']|"[^"]*"|'[^']*')*>''',
    caseSensitive: false,
  );
  static final _attribute = RegExp(
    r'''\s+([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
  );
  static final _entity = RegExp(
      r'&(?:#(x[0-9a-f]+|\d+)|nbsp|amp|lt|gt|quot|apos);',
      caseSensitive: false);

  static String? hiddenInputValue(String html, Set<String> lowerKeys) {
    String? value;
    for (final input in _input.allMatches(html)) {
      var matchesIdentity = false;
      final values = <String>[];
      for (final attribute in _attribute.allMatches(input[0]!)) {
        final key = attribute[1]!.toLowerCase();
        final raw = attribute[2] ?? attribute[3]!;
        if (key == 'id' || key == 'name') {
          matchesIdentity |=
              lowerKeys.contains(_decodeAttribute(raw).toLowerCase());
        } else if (key == 'value') {
          final next = _decodeAttribute(raw).trim();
          if (next.isNotEmpty) values.add(next);
        }
      }
      if (!matchesIdentity) continue;
      for (final next in values) {
        if (value != null && value != next) return null;
        value = next;
      }
    }
    return value;
  }

  static String? _nonEmpty(Object? raw) {
    final value = raw?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  static String _decodeAttribute(String raw) =>
      raw.replaceAllMapped(_entity, (match) {
        final number = match[1]?.toLowerCase();
        if (number != null) {
          final hex = number.startsWith('x');
          final point = int.tryParse(hex ? number.substring(1) : number,
              radix: hex ? 16 : 10);
          if (point != null &&
              point > 0 &&
              point <= 0x10ffff &&
              (point < 0xd800 || point > 0xdfff)) {
            return String.fromCharCode(point);
          }
        }
        return const {
              '&nbsp;': ' ',
              '&amp;': '&',
              '&lt;': '<',
              '&gt;': '>',
              '&quot;': '"',
              '&apos;': "'",
            }[match[0]!.toLowerCase()] ??
            match[0]!;
      });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_param_helper.dart';

void main() {
  const classKeys = ChaoxingParamHelper.clazzIdKeys;

  test('query aliases are case-insensitive and ignore blank occurrences', () {
    final uri = Uri.parse('?cLaSsId=%20&cLaSsId=%2011%20&JCLASSID=11');
    expect(ChaoxingParamHelper.singleQueryValue(uri, classKeys), '11');
  });

  for (final query in ['classId=11&classId=11', 'clazzId=11&classID=12']) {
    test('query rejects ambiguous class identity: $query', () {
      final uri = Uri.parse('?$query');
      expect(ChaoxingParamHelper.singleQueryValue(uri, classKeys), isNull);
      expect(ChaoxingParamHelper.hasAnyQueryValue(uri, classKeys), isTrue);
    });
  }

  test('blank or unrelated query parameters do not supply a class identity',
      () {
    final uri = Uri.parse('?classId=%20&unrelated=11');
    expect(ChaoxingParamHelper.singleQueryValue(uri, classKeys), isNull);
    expect(ChaoxingParamHelper.hasAnyQueryValue(uri, classKeys), isFalse);
  });

  test('exam identities accept only the two exam class aliases', () {
    final uri = Uri.parse('?jClassId=11');
    expect(
      ChaoxingParamHelper.singleQueryValue(
        uri,
        ChaoxingParamHelper.examClazzIdKeys,
      ),
      isNull,
    );
  });

  test('map aliases normalize values and reject disagreements', () {
    expect(
      ChaoxingParamHelper.singleMapValue(
        {'ClAzZiD': 11, 'jCLASSID': ' 11 ', 'classId': ' '},
        classKeys,
      ),
      '11',
    );
    expect(
      ChaoxingParamHelper.singleMapValue(
        {'classId': '11', 'CLASSID': '12'},
        classKeys,
      ),
      isNull,
    );
  });

  test('map identity presence requires a nonblank value', () {
    expect(
      ChaoxingParamHelper.hasAnyKey(
        {'CLASSID': null, 'clazzId': ' ', 'unrelated': 11},
        classKeys,
      ),
      isFalse,
    );
    expect(ChaoxingParamHelper.hasAnyKey({'JcLaSsId': 11}, classKeys), isTrue);
  });

  test('hidden inputs normalize id and name while ignoring data attributes',
      () {
    const html = '<input data-id="classId" value="12">'
        '<input-preview id="classId" value="13">'
        '<INPUT NAME="ClAsS&#73;D" value="&#49;&#x31;">'
        "<input value=' 11 ' id='JCLASSID'>";
    expect(ChaoxingParamHelper.hiddenInputValue(html, classKeys), '11');
  });

  test('hidden inputs reject conflicting class values', () {
    const html = '<input id="clazzId" value="11">'
        '<input name="classId" value="12">';
    expect(ChaoxingParamHelper.hiddenInputValue(html, classKeys), isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/app_deep_links.dart';

void main() {
  test('normalizes legacy widget assignment deep links', () {
    final location = AppDeepLinks.normalizeIncomingLocation(
      Uri.parse('studyassistant://assignments/cx:default:52795811'),
    );

    expect(location, '/assignments/cx%3Adefault%3A52795811');
  });

  test('normalizes canonical assignment deep links', () {
    final location = AppDeepLinks.normalizeIncomingLocation(
      Uri.parse('studyassistant:///assignments/cx:default:52795811'),
    );

    expect(location, '/assignments/cx%3Adefault%3A52795811');
  });

  test('keeps internal app locations untouched', () {
    final location = AppDeepLinks.normalizeIncomingLocation(
      Uri.parse('/assignments/cx:default:52795811'),
    );

    expect(location, isNull);
  });

  test('redirects legacy exam links to assignments', () {
    final location = AppDeepLinks.normalizeIncomingLocation(
      Uri.parse('studyassistant:///exams/cx:exam:52795811'),
    );

    expect(location, '/assignments');
  });

  test('builds canonical assignment widget uri', () {
    expect(
      AppDeepLinks.assignmentUri('cx:default:52795811'),
      'studyassistant:///assignments/cx%3Adefault%3A52795811',
    );
  });
}

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'browser verification imports only trusted session cookies and does not claim data success',
      () async {
    const channel = MethodChannel('study_assistant/external_links');
    var importDone = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'verifySession');
      expect(call.arguments['url'],
          startsWith('https://mooc1.chaoxing.com/visit/'));
      return [
        {'url': 'https://mooc1.chaoxing.com/', 'cookies': 'challenge=manual'},
        {'url': 'https://attacker.example/', 'cookies': 'evil=leak'}
      ];
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (importDone && o.uri.host == 'mooc1.chaoxing.com') {
          expect(o.headers['Cookie'], contains('challenge=manual'));
          expect(o.headers['Cookie'], isNot(contains('evil=')));
        }
        final data = o.uri.path == '/mycourse/backclazzdata'
            ? {
                'courses': [
                  {'courseId': '1', 'clazzId': '2', 'courseName': '课'}
                ]
              }
            : '<html>unrecognized</html>';
        h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
      }));
    final c = ChaoxingLocalClient(dio: dio);
    await expectLater(c.fetchAssignments(), throwsStateError);
    expect(await c.verifyInBrowser(), isTrue);
    expect(c.succeededCourses, 0);
    importDone = true;
    await expectLater(c.fetchAssignments(), throwsStateError);
  });
}

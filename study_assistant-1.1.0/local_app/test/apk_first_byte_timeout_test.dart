import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/services/apk_download_transport.dart';

void main() {
  test('headers without body do not bypass first-byte timeout and retry',
      () async {
    var calls = 0, cancelled = 0;
    final listening = Completer<void>();
    final bodies = <StreamController<Uint8List>>[];
    final requests = <CancelToken>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        calls++;
        if (requests.isNotEmpty) expect(requests.last.isCancelled, isTrue);
        requests.add(o.cancelToken!);
        final body = StreamController<Uint8List>(onListen: () {
          if (!listening.isCompleted) listening.complete();
        }, onCancel: () {
          cancelled++;
        });
        bodies.add(body);
        h.resolve(Response<ResponseBody>(
            requestOptions: o,
            statusCode: 200,
            data: ResponseBody(body.stream, 200)));
      }));
    var returned = false;
    Object? failure;
    final parent = CancelToken();
    final watched = ApkDownloadTransport(dio,
            receiveIdleTimeout: const Duration(milliseconds: 40))
        .open('https://example.org/a.apk', token: parent)
        .then<void>((_) {
      returned = true;
    }, onError: (Object e) {
      failure = e;
    });
    await listening.future;
    expect(returned, isFalse);
    await watched.timeout(const Duration(seconds: 5));
    expect(
        failure,
        isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.receiveTimeout));
    expect(calls, 2);
    expect(cancelled, 2);
    expect(parent.isCancelled, isFalse);
    expect(identical(requests.first, requests.last), isFalse);
    expect(returned, isFalse);
    for (final body in bodies) {
      await body.close();
    }
  });
  test(
      'cancelling after headers before first bytes closes its stream immediately',
      () async {
    var calls = 0, cancelled = 0;
    final listening = Completer<void>();
    final body = StreamController<Uint8List>(
        onListen: () => listening.complete(),
        onCancel: () {
          cancelled++;
        });
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        calls++;
        h.resolve(Response<ResponseBody>(
            requestOptions: o,
            statusCode: 200,
            data: ResponseBody(body.stream, 200)));
      }));
    final token = CancelToken();
    final future = ApkDownloadTransport(dio)
        .open('https://example.org/a.apk', token: token);
    final checked = expectLater(
        future,
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.cancel)));
    await listening.future;
    token.cancel('user cancelled');
    await checked.timeout(const Duration(milliseconds: 500));
    expect(calls, 1);
    expect(cancelled, 1);
    await body.close();
  });
}

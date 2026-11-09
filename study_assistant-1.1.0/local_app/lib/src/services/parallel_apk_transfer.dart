import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'apk_download_transport.dart';

/// Range requests stay on the configured release URL. The caller still verifies
/// the complete file hash and native package identity before installing it.
class ParallelApkTransfer {
  static const minimumSize = 8 * 1024 * 1024;
  static const bufferSize = 256 * 1024;

  /// Null means the APK was assembled. A 200 response is handed back intact
  /// when Range is unsupported, avoiding a second full download.
  static Future<Response<ResponseBody>?> download({
    required Dio dio,
    required String url,
    required int size,
    required File destination,
    required Directory working,
    required CancelToken token,
    void Function(Response<ResponseBody>)? validateFullResponse,
    void Function(int, int)? onProgress,
  }) async {
    Future<T> guarded<T>(Future<T> work) => Future.any([
          work,
          token.whenCancel.then<T>((error) => throw error),
        ]);
    void check() {
      if (token.isCancelled) throw token.cancelError!;
    }

    final lengths =
        List.generate(4, (i) => ((i + 1) * size ~/ 4) - (i * size ~/ 4));
    final received = List.filled(4, 0);
    final transport = ApkDownloadTransport(dio);
    Future<Response<ResponseBody>> request(int i) {
      final start = i * size ~/ 4;
      return guarded(transport.open(url,
          token: token,
          // Only the first Range probe precedes all body transfers. Later
          // sibling failures retain the existing cancel-and-cleanup behavior.
          retryInitialRequest: i == 0,
          // Spend the same single retry on the existing full-response fallback.
          retryWithoutRange: i == 0, validateHeaders: (response) {
        final hasRange = response.requestOptions.headers.keys
            .any((name) => name.toLowerCase() == 'range');
        if (i == 0 && (response.statusCode == 200 || !hasRange)) {
          final length = response.headers.value('content-length');
          if (response.statusCode != 200 ||
              response.data == null ||
              (length != null && int.tryParse(length) != size)) {
            throw StateError('安装包响应长度异常');
          }
          validateFullResponse?.call(response);
          return;
        }
        if (response.statusCode != 206 ||
            response.data == null ||
            response.headers.value('content-range') !=
                'bytes $start-${start + lengths[i] - 1}/$size' ||
            (response.headers.value('content-length') != null &&
                int.tryParse(response.headers.value('content-length')!) !=
                    lengths[i])) {
          throw StateError('安装包分段响应异常，请重试');
        }
      }, headers: {
        'Range': 'bytes=$start-${start + lengths[i] - 1}',
      }));
    }

    final first = await request(0);
    if (first.statusCode == 200) return first;
    final files =
        List.generate(4, (i) => File('${working.path}/range-$i.part'));
    Object? firstFailure;
    StackTrace? firstFailureStack;
    Future<void> receive(int i, Future<Response<ResponseBody>> pending) async {
      StreamIterator<Uint8List>? chunks;
      Stream<Uint8List>? stream;
      bool started = false;
      RandomAccessFile? output;
      try {
        final response = await pending;
        stream = response.data?.stream;
        final length = lengths[i];
        chunks = StreamIterator(stream!);
        output = await files[i].open(mode: FileMode.write);
        final buffer = BytesBuilder(copy: false);
        started = true;
        while (await guarded(chunks.moveNext())) {
          check();
          final chunk = chunks.current;
          if (received[i] + chunk.length > length) {
            throw StateError('安装包分段超出允许大小');
          }
          buffer.add(chunk);
          received[i] += chunk.length;
          if (buffer.length >= bufferSize) {
            await output.writeFrom(buffer.takeBytes());
          }
          onProgress?.call(received.fold<int>(0, (a, b) => a + b), size);
        }
        if (buffer.isNotEmpty) await output.writeFrom(buffer.takeBytes());
        if (received[i] != length) throw StateError('安装包分段下载不完整，请重试');
      } catch (error, stack) {
        firstFailure ??= error;
        firstFailureStack ??= stack;
        // Cancel siblings, then Future.wait waits for their cleanup before the
        // attempt's temporary directory can be removed by the owning service.
        token.cancel('安装包分段下载未完成');
        rethrow;
      } finally {
        try {
          if (started) {
            await chunks?.cancel();
          } else {
            await stream?.listen((_) {}, onError: (Object _) {}).cancel();
          }
        } finally {
          await output?.close();
        }
      }
    }

    try {
      await Future.wait(List.generate(
          4, (i) => receive(i, i == 0 ? Future.value(first) : request(i))));
    } catch (error, stack) {
      // Releasing sibling streams may complete their cancellation first. Keep
      // the originating transfer/validation error instead of masking its cause.
      Error.throwWithStackTrace(
          firstFailure ?? error, firstFailureStack ?? stack);
    }
    check();
    final output = await destination.open(mode: FileMode.write);
    try {
      for (final part in files) {
        await for (final chunk in part.openRead()) {
          check();
          await output.writeFrom(chunk);
        }
      }
    } finally {
      await output.close();
    }
    check();
    return null;
  }
}

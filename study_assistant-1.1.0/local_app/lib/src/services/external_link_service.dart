import 'package:flutter/services.dart';

class ExternalLinkService {
  static const _channel = MethodChannel('study_assistant/external_links');

  Future<bool> openUrl(String url) async {
    final opened = await _channel.invokeMethod<bool>('openUrl', {'url': url});
    return opened ?? false;
  }

  Future<Map<String, dynamic>> inspectApk(String filePath) async =>
      Map<String, dynamic>.from(await _channel
              .invokeMethod<Map>('inspectApk', {'filePath': filePath}) ??
          {});

  Future<bool> installApk(String filePath) async {
    final opened = await _channel.invokeMethod<bool>(
      'installApk',
      {'filePath': filePath},
    );
    return opened ?? false;
  }
}

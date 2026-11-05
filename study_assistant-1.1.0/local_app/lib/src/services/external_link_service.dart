import 'package:flutter/services.dart';

class ExternalLinkService {
  static const _channel = MethodChannel('study_assistant/external_links');

  Future<bool> openUrl(String url) async {
    return _open('openUrl', url);
  }

  /// A true result means the system accepted a browser launch. It gives no
  /// information about page loading, authentication, or homework submission.
  Future<bool> openBrowser(String url) => _open('openBrowser', url);

  Future<bool> _open(String method, String url) async {
    try {
      return await _channel.invokeMethod<bool>(method, {'url': url}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
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

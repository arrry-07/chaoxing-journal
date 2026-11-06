import 'package:flutter/services.dart';

enum AssignmentLaunchTarget {
  chaoxing,
  browser,
  unavailable;

  String get message => switch (this) {
        chaoxing => '已请求学习通打开此链接，请在学习通核对作业详情和登录状态。',
        browser => '当前学习通未提供此链接的直接入口，已请求浏览器打开作业网页，可能需要另行登录。',
        unavailable => '未能打开学习通或浏览器，请重试，或刷新作业信息后复制链接。',
      };
}

class ExternalLinkService {
  static const _channel = MethodChannel('study_assistant/external_links');

  Future<bool> openUrl(String url) async {
    return _open('openUrl', url);
  }

  /// A true result means the system accepted a browser launch. It gives no
  /// information about page loading, authentication, or homework submission.
  Future<bool> openBrowser(String url) => _open('openBrowser', url);

  /// Send the original HTTPS URL only to a registered public handler in the
  /// official package. No private activity names, invented schemes or cookies.
  Future<AssignmentLaunchTarget> openAssignment(String url) async {
    if (await _open('openChaoxingAssignment', url)) {
      return AssignmentLaunchTarget.chaoxing;
    }
    return await openBrowser(url)
        ? AssignmentLaunchTarget.browser
        : AssignmentLaunchTarget.unavailable;
  }

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

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/personal_workspace.dart';

class PersonalFileService {
  const PersonalFileService();

  static const channel = MethodChannel('study_assistant/personal_files');
  Future<PersonalLink?> pick() async {
    final data = await channel.invokeMapMethod<String, dynamic>('pick');
    if (data == null) return null;
    final url = data['url'], label = data['label'];
    if (url is! String ||
        label is! String ||
        !PersonalWorkspace.validFile(url) ||
        label.length > 200) {
      throw const FormatException('文件信息无效');
    }
    return PersonalLink(label, url);
  }

  Future<bool> open(String uri) async {
    if (!PersonalWorkspace.validFile(uri)) return false;
    try {
      return await channel.invokeMethod<bool>('open', {'uri': uri}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> releaseAll() async {
    if (kDebugMode) {
      if (BindingBase.debugBindingType() == null) return false;
      try {
        final messenger = ServicesBinding.instance.defaultBinaryMessenger;
        if (messenger.runtimeType.toString() == 'TestDefaultBinaryMessenger') {
          final dynamic testMessenger = messenger;
          if (testMessenger.allMessagesHandler == null &&
              testMessenger.checkMockMessageHandler(channel.name, null) ==
                  true) {
            return false;
          }
        }
      } catch (_) {
        // Fall through to the normal platform channel invocation.
      }
    }
    try {
      return await channel.invokeMethod<bool>('releaseAll') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

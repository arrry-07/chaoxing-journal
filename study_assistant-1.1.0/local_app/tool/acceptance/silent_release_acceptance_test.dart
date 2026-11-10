// Explicit public-network acceptance; not part of the offline test directory.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';
import 'package:study_assistant_mobile/src/services/app_update_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final output = Platform.environment['XXT_ACCEPTANCE_OUTPUT'];
  final hash = Platform.environment['XXT_EXPECTED_PATCH_SHA256'];
  if (output == null || hash == null) {
    throw StateError('Set explicit evidence directory and expected patch hash');
  }
  test(
      'public non-latest patch is discoverable manually and startup stays silent',
      () async {
    final service = AppUpdateService();
    final manual = await service.checkForManualUpdate(
        currentVersionName: '1.6.7', currentVersionCode: 52);
    expect(manual.status, UpdateCheckStatus.available);
    expect(manual.update!.versionName, '1.6.71');
    expect(manual.update!.sha256Hash, hash);
    final controller = AppUpdateController(service: service);
    addTearDown(controller.dispose);
    expect(await controller.checkOnStartup(), false);
    expect(controller.update, isNull);
    expect(controller.showBanner, false);
    final dir = await Directory(output).create(recursive: true);
    await File('${dir.path}/manual-startup-network-result.json')
        .writeAsString(jsonEncode({
      'manualQueryUsingNewClientCodeWithInstalledVersion': '1.6.7',
      'manualDiscoveredNonLatest': manual.update!.versionName,
      'sha256': manual.update!.sha256Hash,
      'newClientStartupPrompt': false,
      'newClientStartupBanner': false,
      'scope':
          'real GitHub metadata using production service; not a claim that old 1.6.7 manual code supports this',
    }));
  });
}

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/personal_file_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() =>
      messenger.setMockMethodCallHandler(PersonalFileService.channel, null));

  test('cancelled picker leaves no file association', () async {
    messenger.setMockMethodCallHandler(
        PersonalFileService.channel, (_) async => null);
    expect(await PersonalFileService().pick(), isNull);
  });
  test('file reference must be a provider content URI', () async {
    messenger.setMockMethodCallHandler(PersonalFileService.channel,
        (_) async => {'label': 'sample', 'url': 'file:///private/sample'});
    await expectLater(PersonalFileService().pick(), throwsFormatException);
    expect(await PersonalFileService().open('https://example.org'), isFalse);
  });
  test('valid selected document can be opened, revoked grant returns false',
      () async {
    var available = true;
    messenger.setMockMethodCallHandler(PersonalFileService.channel,
        (call) async {
      if (call.method == 'pick') {
        return {'label': 'sample', 'url': 'content://documents/sample'};
      }
      if (!available) throw PlatformException(code: 'unavailable');
      return true;
    });
    final service = PersonalFileService();
    final file = await service.pick();
    expect(file!.label, 'sample');
    expect(await service.open(file.url), isTrue);
    available = false;
    expect(await service.open(file.url), isFalse);
  });

  test('releaseAll returns false when the platform fails or is unavailable',
      () async {
    final service = PersonalFileService();
    messenger.setMockMethodCallHandler(PersonalFileService.channel,
        (call) async {
      expect(call.method, 'releaseAll');
      throw PlatformException(code: 'grant_cleanup_unavailable');
    });
    expect(await service.releaseAll(), isFalse);

    messenger.setMockMethodCallHandler(PersonalFileService.channel, null);
    expect(await service.releaseAll(), isFalse);
  });

  test('logout releases the restored account file grant through the channel',
      () async {
    const account = 'synthetic-account';
    const workId = 'cx:work:1:2:3';
    const file = PersonalLink('本机附件', 'content://documents/logout-fixture');
    FlutterSecureStorage.setMockInitialValues({
      'chaoxingAccount': account,
      'chaoxingPassword': 'synthetic-only',
    });
    addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
    SharedPreferences.setMockInitialValues({});
    final repository = LocalAssignmentRepository();
    await repository.activateAccount(account);
    await repository.savePersonalWorkspace(
      PersonalWorkspace(work: {
        workId: const PersonalWork(files: [file]),
      }),
      account,
    );
    final calls = <String>[];
    var grantHeld = true;
    messenger.setMockMethodCallHandler(PersonalFileService.channel,
        (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'open':
          return grantHeld && call.arguments['uri'] == file.url;
        case 'releaseAll':
          grantHeld = false;
          return true;
        default:
          throw MissingPluginException(call.method);
      }
    });
    final session = SecureSessionStore();
    final store = AssignmentStore(
      sessionStore: session,
      repository: repository,
      notificationService: LocalNotificationService(),
      widgetSnapshotService: _LogoutWidgetSnapshot(),
      manageBackgroundSchedule: false,
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    expect(store.account, account);
    final restoredFile = store.personal.work[workId]!.files.single;
    final service = PersonalFileService();
    expect(await service.open(restoredFile.url), isTrue);

    await store.logout();

    expect(store.isAuthenticated, isFalse);
    expect(await session.readChaoxingAccount(), isNull);
    expect(calls, ['open', 'releaseAll']);
    expect(await service.open(restoredFile.url), isFalse);
  });
}

class _LogoutWidgetSnapshot extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

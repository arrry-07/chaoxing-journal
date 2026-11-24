import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/manual_attachment.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/manual_attachment_service.dart';

import 'review_core_remediation_test.dart' as core;

ManualAttachment _att(String id, {String kind = ManualAttachment.kindImage}) =>
    ManualAttachment(
      id: id,
      kind: kind,
      name: kind == ManualAttachment.kindImage ? '$id.jpg' : '$id.pdf',
      relativePath: kind == ManualAttachment.kindImage
          ? 'manual_attachments/$id.jpg'
          : 'manual_attachments/$id.pdf',
      mimeType:
          kind == ManualAttachment.kindImage ? 'image/jpeg' : 'application/pdf',
      sizeBytes: 2048,
      addedAt: DateTime.utc(2026, 11, 25, 5, 0).toLocal(),
    );

class _RecordingAttachmentService extends ManualAttachmentService {
  final deletedBatches = <List<String>>[];
  int deleteAllCount = 0;
  bool throwOnDelete = false;

  @override
  Future<int> deleteFiles(Iterable<String> relativePaths) async {
    final list = relativePaths.toList();
    deletedBatches.add(list);
    if (throwOnDelete) throw StateError('disk busy');
    return list.length;
  }

  @override
  Future<bool> deleteAllAttachments() async {
    deleteAllCount++;
    if (throwOnDelete) throw StateError('disk busy');
    return true;
  }
}

class _StaleSaveRepo extends LocalAssignmentRepository {
  bool failNextNotebookSave = false;

  @override
  Future<void> saveNotebook(StudyNotebook value, String account) async {
    if (failNextNotebookSave) {
      failNextNotebookSave = false;
      throw StaleSessionWriteException('simulated stale write');
    }
    await super.saveNotebook(value, account);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ManualAttachmentService.channel, null);
  });

  group('ManualAttachmentService channel bridge', () {
    test('getAttachmentRoot caches root and resolveLocalFile prevents escape',
        () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ManualAttachmentService.channel,
              (call) async {
        calls++;
        expect(call.method, 'getAttachmentRoot');
        return '/data/user/0/app/files/manual_attachments';
      });
      final service = ManualAttachmentService();
      expect(
        await service.getAttachmentRoot(),
        '/data/user/0/app/files/manual_attachments',
      );
      expect(await service.getAttachmentRoot(), isNotNull);
      expect(calls, 1);

      final resolved = service.resolveLocalFile('manual_attachments/att_1.jpg');
      expect(
        resolved?.path.replaceAll('\\', '/'),
        '/data/user/0/app/files/manual_attachments/att_1.jpg',
      );
      expect(
        service.resolveLocalFile('manual_attachments/../escape.jpg'),
        isNull,
      );
    });

    test('capturePhoto, pickImages, pickAttachmentFile handle success & limits',
        () async {
      final nowMs = DateTime.utc(2026, 11, 25, 6, 0).millisecondsSinceEpoch;
      final recordedArgs = <String, dynamic>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ManualAttachmentService.channel,
              (call) async {
        switch (call.method) {
          case 'capturePhoto':
            return {
              'id': 'att_cam',
              'kind': 'image',
              'name': '拍照_att_cam.jpg',
              'relativePath': 'manual_attachments/att_cam.jpg',
              'mimeType': 'image/jpeg',
              'sizeBytes': 4096,
              'addedAtMs': nowMs,
            };
          case 'pickImages':
            recordedArgs['pickImages'] = call.arguments;
            return {
              'items': [
                {
                  'id': 'att_img1',
                  'kind': 'image',
                  'name': 'a.png',
                  'relativePath': 'manual_attachments/att_img1.png',
                  'mimeType': 'image/png',
                  'sizeBytes': 8192,
                  'addedAtMs': nowMs,
                },
              ],
              'skippedTooLarge': 1,
              'skippedFailed': 0,
            };
          case 'pickAttachmentFile':
            throw PlatformException(
              code: 'file_too_large',
              message: '单个文件不能超过 20 MB',
            );
          case 'openAttachment':
            return 'no_app';
          case 'deleteAttachmentFiles':
            recordedArgs['deleted'] = call.arguments;
            return 1;
          default:
            return null;
        }
      });

      final service = ManualAttachmentService();
      final photo = await service.capturePhoto();
      expect(photo.attachment?.id, 'att_cam');
      expect(photo.issue, AttachmentPickIssue.none);

      final batch = await service.pickImages(maxCount: 15);
      expect((recordedArgs['pickImages'] as Map)['maxCount'], 9);
      expect(batch.attachments, hasLength(1));
      expect(batch.skippedTooLarge, 1);
      expect(batch.message, contains('20 MB'));

      final oversizedFile = await service.pickAttachmentFile();
      expect(oversizedFile.attachment, isNull);
      expect(oversizedFile.issue, AttachmentPickIssue.tooLarge);
      expect(oversizedFile.message, contains('20 MB'));

      final openStatus = await service
          .openAttachment(_att('doc1', kind: ManualAttachment.kindFile));
      expect(openStatus, AttachmentOpenStatus.noApp);
      expect(
        await service.openAttachment(
          ManualAttachment(
            id: 'bad',
            kind: ManualAttachment.kindFile,
            name: 'bad',
            relativePath: 'manual_attachments/../x.pdf',
            mimeType: 'application/pdf',
            sizeBytes: 10,
            addedAt: DateTime.now(),
          ),
        ),
        AttachmentOpenStatus.missingFile,
      );

      final deleted = await service.deleteFiles([
        'manual_attachments/att_cam.jpg',
        'updates/other.apk',
      ]);
      expect(deleted, 1);
      expect(
        (recordedArgs['deleted'] as Map)['relativePaths'],
        ['manual_attachments/att_cam.jpg'],
      );
      expect(Platform.pathSeparator.isNotEmpty, isTrue);
    });
  });

  group('AssignmentStore attachment lifecycle cleanup', () {
    test(
        'saveNotebook deletes only unreferenced files, skips on stale failure, and cleans up on logout and account switch',
        () async {
      SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
      final session = core.Session();
      final client = core.Client();
      final repo = _StaleSaveRepo();
      final attachments = _RecordingAttachmentService();
      final store = AssignmentStore(
        sessionStore: session,
        notificationService: core.Notifications(),
        widgetSnapshotService: core.WidgetService(),
        manualAttachmentService: attachments,
        repository: repo,
        chaoxingClient: client,
      );
      addTearDown(store.dispose);
      await store.restoreSession();

      final img1 = _att('img1');
      final img2 = _att('img2');
      final file1 = _att('doc1', kind: ManualAttachment.kindFile);

      // Add entry with 3 attachments.
      expect(
        await store.saveNotebook(
          (_) => StudyNotebook(entries: [
            ManualEntry(
              id: 'm1',
              title: '带附件待办',
              kind: ManualEntry.kindTodo,
              attachments: [img1, img2, file1],
            ),
          ]),
          store.accountEpoch,
        ),
        isTrue,
      );
      expect(attachments.deletedBatches, isEmpty);

      // Remove img2 while keeping img1 and file1.
      expect(
        await store.saveNotebook(
          (n) => n.withEntries([
            n.entries.single.copyWith(attachments: [img1, file1]),
          ]),
          store.accountEpoch,
        ),
        isTrue,
      );
      expect(attachments.deletedBatches, [
        ['manual_attachments/img2.jpg'],
      ]);

      // Stale failure on delete must NOT clean existing files.
      repo.failNextNotebookSave = true;
      expect(
        await store.saveNotebook(
          (_) => StudyNotebook(),
          store.accountEpoch,
        ),
        isFalse,
      );
      expect(store.notebook.entries, hasLength(1));
      expect(attachments.deletedBatches, hasLength(1));

      // Actual delete of entry cleans remaining img1 & doc1.
      expect(
        await store.saveNotebook((_) => StudyNotebook(), store.accountEpoch),
        isTrue,
      );
      expect(attachments.deletedBatches.last, [
        'manual_attachments/img1.jpg',
        'manual_attachments/doc1.pdf',
      ]);

      // Re-login same account must NOT delete all attachments.
      client.cookieOwner = 'A';
      await store.loginChaoxing(
        account: 'A',
        password: 'pw',
        agreementAccepted: true,
      );
      expect(attachments.deleteAllCount, 0);

      // Switching to account B cleans all attachments.
      await store.loginChaoxing(
        account: 'B',
        password: 'pw',
        agreementAccepted: true,
      );
      expect(attachments.deleteAllCount, 1);

      // Logout also cleans all attachments.
      await store.logout();
      expect(attachments.deleteAllCount, 2);

      // Even if deleteAll throws, logout still completes cleanly.
      attachments.throwOnDelete = true;
      session.account = 'C';
      await store.restoreSession();
      await store.logout();
      expect(store.isAuthenticated, isFalse);
    });
  });
}

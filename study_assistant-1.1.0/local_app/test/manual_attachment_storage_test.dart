import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/backup_snapshot.dart';
import 'package:study_assistant_mobile/src/models/manual_attachment.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';

ManualAttachment _att(
  String id, {
  String kind = ManualAttachment.kindImage,
  String? relativePath,
  int sizeBytes = 1024,
  String mimeType = 'image/jpeg',
}) =>
    ManualAttachment(
      id: id,
      kind: kind,
      name: kind == ManualAttachment.kindImage ? '$id.jpg' : '$id.pdf',
      relativePath: relativePath ?? 'manual_attachments/$id.jpg',
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      addedAt: DateTime.utc(2026, 11, 25, 4, 0).toLocal(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PersonalWorkspace.map optionalKeys compatibility', () {
    test('strict mode stays intact when optionalKeys is omitted', () {
      expect(
        PersonalWorkspace.map({'a': 1, 'b': 'x'}, {'a', 'b'}),
        {'a': 1, 'b': 'x'},
      );
      expect(
        () => PersonalWorkspace.map({'a': 1, 'b': 'x', 'c': true}, {'a', 'b'}),
        throwsFormatException,
      );
      expect(
        () => PersonalWorkspace.map({'a': 1}, {'a', 'b'}),
        throwsFormatException,
      );
    });

    test('optionalKeys accepts required subset with allowed optional keys only',
        () {
      expect(
        PersonalWorkspace.map(
          {'a': 1, 'c': true},
          {'a'},
          optionalKeys: const {'b', 'c'},
        ),
        {'a': 1, 'c': true},
      );
      expect(
        () => PersonalWorkspace.map(
          {'a': 1, 'unknown': 2},
          {'a'},
          optionalKeys: const {'b', 'c'},
        ),
        throwsFormatException,
      );
    });
  });

  group('ManualAttachment validation', () {
    test('accepts valid image and file metadata and formats sizes', () {
      final img = _att('att_1', sizeBytes: 512);
      final file = _att(
        'att_2',
        kind: ManualAttachment.kindFile,
        relativePath: 'manual_attachments/report_2026.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 3 * 1024 * 1024,
      );
      expect(img.isImage, isTrue);
      expect(img.formattedSize, '512 B');
      expect(file.isImage, isFalse);
      expect(file.formattedSize, '3.0 MB');
      expect(ManualAttachment.fromJson(img.toJson()), img);
      expect(ManualAttachment.fromJson(file.toJson()), file);
    });

    test('rejects unsafe paths, invalid ids, oversized files, and bad mimes',
        () {
      for (final badPath in [
        '',
        'updates/foo.jpg',
        '/manual_attachments/a.jpg',
        'manual_attachments/../secret.jpg',
        r'manual_attachments\a.jpg',
        'manual_attachments/',
        'manual_attachments//a.jpg',
        'manual_attachments/中文文件名.jpg',
        'manual_attachments/${'a' * 250}.jpg',
      ]) {
        expect(
          ManualAttachment.isValidRelativePath(badPath),
          isFalse,
          reason: 'Should reject relativePath: $badPath',
        );
        final json = _att('valid').toJson()..['relativePath'] = badPath;
        expect(() => ManualAttachment.fromJson(json), throwsFormatException);
      }

      final overSize =
          _att('big', sizeBytes: ManualAttachment.maxFileBytes + 1).toJson();
      expect(() => ManualAttachment.fromJson(overSize), throwsFormatException);

      final negativeSize = _att('neg', sizeBytes: -1).toJson();
      expect(
        () => ManualAttachment.fromJson(negativeSize),
        throwsFormatException,
      );

      final badId = _att('id').toJson()..['id'] = '../evil';
      expect(() => ManualAttachment.fromJson(badId), throwsFormatException);

      final badMime = _att('m').toJson()..['mimeType'] = 'not a mime';
      expect(() => ManualAttachment.fromJson(badMime), throwsFormatException);
    });
  });

  group('StudyNotebook v1/v2 backward compatibility & portable backups', () {
    test(
        'reads legacy v1 notebook and persists v2 locally when attachments exist',
        () {
      final legacyRaw = jsonEncode({
        'version': 1,
        'entries': [
          {
            'id': 'legacy-1',
            'title': '旧待办',
            'kind': 'todo',
            'course': '高数',
            'location': '',
            'note': '纯文本',
            'at': '2030-01-01T02:00:00.000Z',
            'done': false,
            'remind': false,
            'minutes': 0,
          },
        ],
        'terms': [],
      });

      final decodedLegacy = StudyNotebook.decode(legacyRaw);
      expect(decodedLegacy.entries.single.id, 'legacy-1');
      expect(decodedLegacy.entries.single.updatedAt, isNull);
      expect(decodedLegacy.entries.single.attachments, isEmpty);
      expect(decodedLegacy.toJson()['version'], 1);

      final updatedEntry = decodedLegacy.entries.single.copyWith(
        updatedAt: DateTime.utc(2026, 11, 25, 4, 30),
        attachments: [
          _att('img1'),
          _att(
            'doc1',
            kind: ManualAttachment.kindFile,
            relativePath: 'manual_attachments/doc1.pdf',
            mimeType: 'application/pdf',
          ),
        ],
      );
      final v2Notebook = StudyNotebook(entries: [updatedEntry]);
      final v2Json = v2Notebook.toJson();
      expect(v2Json['version'], 2);

      final roundtrip = StudyNotebook.decode(v2Notebook.encode());
      expect(roundtrip.entries.single.attachments, hasLength(2));
      expect(
        roundtrip.entries.single.updatedAt?.toUtc(),
        DateTime.utc(2026, 11, 25, 4, 30),
      );
    });

    test('completed() preserves attachments and refreshes updatedAt', () {
      final ts = DateTime.utc(2026, 11, 25, 5, 0);
      final entry = ManualEntry(
        id: 'm-att',
        title: '带附件待办',
        kind: ManualEntry.kindTodo,
        attachments: [_att('img1')],
      );
      final done = entry.completed(true, now: ts);
      expect(done.done, isTrue);
      expect(done.attachments, [_att('img1')]);
      expect(done.updatedAt?.toUtc(), ts);
    });

    test('enforces max 9 images, max 20 attachments, and unique ids/paths', () {
      final tenImages = [
        for (var i = 0; i < 10; i++) _att('img_$i'),
      ];
      final entry10Images = ManualEntry(
        id: 'm-10-img',
        title: '十张图',
        kind: ManualEntry.kindTodo,
        attachments: tenImages,
      );
      expect(
        () => ManualEntry.fromJson(entry10Images.toJson()),
        throwsFormatException,
      );

      final validMaxMixed = ManualEntry(
        id: 'm-20-mix',
        title: '9图11文件',
        kind: ManualEntry.kindTodo,
        attachments: [
          for (var i = 0; i < 9; i++) _att('img_$i'),
          for (var i = 0; i < 11; i++)
            _att(
              'file_$i',
              kind: ManualAttachment.kindFile,
              relativePath: 'manual_attachments/file_$i.pdf',
              mimeType: 'application/pdf',
            ),
        ],
      );
      final decodedMax = ManualEntry.fromJson(validMaxMixed.toJson());
      expect(decodedMax.attachments, hasLength(20));

      final dupPath = ManualEntry(
        id: 'm-dup',
        title: '重复路径',
        kind: ManualEntry.kindTodo,
        attachments: [
          _att('a1', relativePath: 'manual_attachments/same.jpg'),
          _att('a2', relativePath: 'manual_attachments/same.jpg'),
        ],
      );
      expect(
        () => ManualEntry.fromJson(dupPath.toJson()),
        throwsFormatException,
      );

      // Legacy v1 payload must never smuggle v2 keys.
      final smuggledV1 = jsonEncode({
        'version': 1,
        'entries': [validMaxMixed.toJson()],
        'terms': [],
      });
      expect(() => StudyNotebook.decode(smuggledV1), throwsFormatException);
    });

    test(
        'BackupSnapshot strictly exports v1 legacy 10-key notebook so older builds can decode it',
        () async {
      final repo = LocalAssignmentRepository();
      await repo.activateAccount('student-a');
      final v2Entry = ManualEntry(
        id: 'm-backup-1',
        title: '含附件待办',
        kind: ManualEntry.kindTodo,
        course: '编译原理',
        note: '重要内容',
        updatedAt: DateTime.utc(2026, 11, 25, 6, 0),
        attachments: [
          _att('img_1'),
          _att(
            'pdf_1',
            kind: ManualAttachment.kindFile,
            relativePath: 'manual_attachments/pdf_1.pdf',
            mimeType: 'application/pdf',
          ),
        ],
      );
      await repo.saveNotebook(StudyNotebook(entries: [v2Entry]), 'student-a');

      final snapshot = await repo.createBackupSnapshot('student-a');
      final encoded = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
      final exportedNotebook = encoded['notebook'] as Map<String, dynamic>;

      // Exact legacy v1 keys as old builds expect via PersonalWorkspace.map().
      expect(exportedNotebook['version'], 1);
      final entries = exportedNotebook['entries'] as List<dynamic>;
      expect(entries, hasLength(1));
      final entryMap = entries.single as Map<String, dynamic>;
      expect(
        entryMap.keys.toSet(),
        const {
          'id',
          'title',
          'kind',
          'course',
          'location',
          'note',
          'at',
          'done',
          'remind',
          'minutes',
        },
      );
      expect(entryMap.containsKey('updatedAt'), isFalse);
      expect(entryMap.containsKey('attachments'), isFalse);

      // Portable decode works without error and strips attachments.
      final decoded = BackupSnapshot.decode(jsonEncode(encoded));
      expect(decoded.notebook.entries.single.title, '含附件待办');
      expect(decoded.notebook.entries.single.attachments, isEmpty);

      // Restoring that backup does NOT erase the local entry's existing attachments.
      await repo.restoreBackupSnapshot(decoded, 'student-a');
      final localAfterRestore = await repo.loadNotebook();
      expect(localAfterRestore.entries.single.attachments, hasLength(2));
    });
  });
}

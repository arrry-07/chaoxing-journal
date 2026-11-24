import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../models/manual_attachment.dart';
import '../../services/manual_attachment_service.dart';
import 'journal_grouped_card.dart';
import 'manual_attachment_gallery.dart';

class ManualAttachmentPickerSection extends StatelessWidget {
  const ManualAttachmentPickerSection({
    super.key,
    required this.attachments,
    required this.service,
    required this.busy,
    this.rootPath,
    this.statusHint,
    required this.onCapturePhoto,
    required this.onPickImages,
    required this.onPickFile,
    required this.onRemove,
  });

  final List<ManualAttachment> attachments;
  final ManualAttachmentService service;
  final bool busy;
  final String? rootPath;
  final String? statusHint;
  final VoidCallback onCapturePhoto;
  final VoidCallback onPickImages;
  final VoidCallback onPickFile;
  final ValueChanged<ManualAttachment> onRemove;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final images = [
      for (final item in attachments)
        if (item.isImage) item,
    ];
    final files = [
      for (final item in attachments)
        if (!item.isImage) item,
    ];
    final totalFull =
        attachments.length >= ManualAttachment.maxAttachmentsPerEntry;
    final imageFull = images.length >= ManualAttachment.maxImagesPerEntry;
    final canAddImage = !busy && !totalFull && !imageFull;
    final canAddFile = !busy && !totalFull;

    return JournalGroupedCard(
      title: '附件',
      padding: const EdgeInsets.all(14),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '图片 ${images.length}/${ManualAttachment.maxImagesPerEntry} · '
              '总计 ${attachments.length}/${ManualAttachment.maxAttachmentsPerEntry} · '
              '单个文件不超过 20 MB',
              style: journal.metadata,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('attachment-add-camera'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onPressed: canAddImage ? onCapturePhoto : null,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('拍照'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('attachment-add-gallery'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onPressed: canAddImage ? onPickImages : null,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('相册'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('attachment-add-file'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onPressed: canAddFile ? onPickFile : null,
                  icon: const Icon(Icons.attach_file_rounded, size: 18),
                  label: const Text('文件'),
                ),
              ],
            ),
            if (totalFull) ...[
              const SizedBox(height: 8),
              Text(
                '已达单条 20 个附件上限，删除部分附件后可继续添加。',
                style: journal.metadata.copyWith(color: journal.ochre),
              ),
            ] else if (imageFull) ...[
              const SizedBox(height: 8),
              Text(
                '图片已达 9 张上限，仍可继续添加文档或压缩包文件。',
                style: journal.metadata.copyWith(color: journal.ochre),
              ),
            ],
            if (statusHint != null) ...[
              const SizedBox(height: 8),
              Semantics(
                key: const ValueKey('attachment-picker-feedback'),
                liveRegion: true,
                child: Text(
                  statusHint!,
                  style: journal.metadata.copyWith(color: journal.ochre),
                ),
              ),
            ],
            if (images.isNotEmpty) ...[
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: images.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  final item = images[index];
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Semantics(
                        button: true,
                        excludeSemantics: true,
                        label: '查看图片 ${item.name}',
                        onTap: () => showAttachmentImageGallery(
                          context,
                          images: images,
                          initialIndex: index,
                          service: service,
                          rootPath: rootPath,
                        ),
                        child: InkWell(
                          key: ValueKey('editor-attachment-image-${item.id}'),
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => showAttachmentImageGallery(
                            context,
                            images: images,
                            initialIndex: index,
                            service: service,
                            rootPath: rootPath,
                          ),
                          child: AttachmentImageThumbnail(
                            attachment: item,
                            service: service,
                            rootPath: rootPath,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Semantics(
                          button: true,
                          excludeSemantics: true,
                          enabled: !busy,
                          label: '删除图片 ${item.name}',
                          onTap: busy ? null : () => onRemove(item),
                          child: Tooltip(
                            message: '删除图片',
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: Material(
                                type: MaterialType.transparency,
                                child: InkWell(
                                  key: ValueKey('attachment-remove-${item.id}'),
                                  customBorder: const CircleBorder(),
                                  onTap: busy ? null : () => onRemove(item),
                                  child: Align(
                                    alignment: Alignment.topRight,
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: const BoxDecoration(
                                          color: Color(0xB3191816),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close_rounded,
                                          size: 16,
                                          color: Color(0xFFFFFFFF),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
            if (files.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (var i = 0; i < files.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                Container(
                  key: ValueKey('editor-attachment-file-${files[i].id}'),
                  padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                  decoration: BoxDecoration(
                    color: journal.parchment,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: journal.cardBorder, width: 0.7),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.insert_drive_file_outlined,
                        size: 19,
                        color: journal.accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              files[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: journal.entryTitle.copyWith(fontSize: 14),
                            ),
                            Text(
                              files[i].formattedSize,
                              style: journal.metadata,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: ValueKey('attachment-remove-${files[i].id}'),
                        tooltip: '删除文件',
                        constraints: const BoxConstraints.tightFor(
                          width: 48,
                          height: 48,
                        ),
                        onPressed: busy ? null : () => onRemove(files[i]),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: journal.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ],
    );
  }
}

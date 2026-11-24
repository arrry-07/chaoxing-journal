import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../app/transient_feedback.dart';
import '../../models/manual_attachment.dart';
import '../../services/manual_attachment_service.dart';
import 'journal_grouped_card.dart';

Future<void> showAttachmentImageGallery(
  BuildContext context, {
  required List<ManualAttachment> images,
  required int initialIndex,
  required ManualAttachmentService service,
  String? rootPath,
}) async {
  if (images.isEmpty) return;
  final resolvedRoot = rootPath ?? await service.getAttachmentRoot();
  if (!context.mounted) return;
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _AttachmentFullscreenViewer(
        images: images,
        initialIndex: initialIndex.clamp(0, images.length - 1),
        service: service,
        rootPath: resolvedRoot,
      ),
    ),
  );
}

class AttachmentImageThumbnail extends StatelessWidget {
  const AttachmentImageThumbnail({
    super.key,
    required this.attachment,
    required this.service,
    this.rootPath,
  });

  final ManualAttachment attachment;
  final ManualAttachmentService service;
  final String? rootPath;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final file = service.resolveLocalFile(
      attachment.relativePath,
      rootPath: rootPath,
    );
    final hasFile = file != null && file.existsSync();
    return Container(
      decoration: BoxDecoration(
        color: journal.parchment,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: journal.cardBorder, width: 0.7),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasFile
          ? Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _PlaceholderImageTile(
                name: attachment.name,
              ),
            )
          : _PlaceholderImageTile(name: attachment.name),
    );
  }
}

class _PlaceholderImageTile extends StatelessWidget {
  const _PlaceholderImageTile({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, size: 22, color: journal.muted),
          const SizedBox(height: 4),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: journal.metadata.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _AttachmentFullscreenViewer extends StatefulWidget {
  const _AttachmentFullscreenViewer({
    required this.images,
    required this.initialIndex,
    required this.service,
    this.rootPath,
  });

  final List<ManualAttachment> images;
  final int initialIndex;
  final ManualAttachmentService service;
  final String? rootPath;

  @override
  State<_AttachmentFullscreenViewer> createState() =>
      _AttachmentFullscreenViewerState();
}

class _AttachmentFullscreenViewerState
    extends State<_AttachmentFullscreenViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.images[_index];
    return Scaffold(
      backgroundColor: const Color(0xFF121110),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121110),
        foregroundColor: const Color(0xFFEAE6DF),
        leading: IconButton(
          key: const ValueKey('attachment-viewer-close'),
          tooltip: '关闭预览',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(
          '${_index + 1} / ${widget.images.length}',
          key: const ValueKey('attachment-viewer-counter'),
          style: const TextStyle(color: Color(0xFFEAE6DF)),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.images.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (context, index) {
                final item = widget.images[index];
                final file = widget.service.resolveLocalFile(
                  item.relativePath,
                  rootPath: widget.rootPath,
                );
                final exists = file != null && file.existsSync();
                return InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: Center(
                    child: exists
                        ? Image.file(
                            file,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => _MissingFullImage(
                              name: item.name,
                            ),
                          )
                        : _MissingFullImage(name: item.name),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                '${current.name} · ${current.formattedSize}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFC4BFB6),
                  fontSize: 13.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingFullImage extends StatelessWidget {
  const _MissingFullImage({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            size: 44,
            color: Color(0xFFC4BFB6),
          ),
          const SizedBox(height: 10),
          Text(
            '$name\n图片文件已不存在于本机私有目录',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFC4BFB6), fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class ManualAttachmentGallery extends StatefulWidget {
  const ManualAttachmentGallery({
    super.key,
    required this.attachments,
    required this.service,
  });

  final List<ManualAttachment> attachments;
  final ManualAttachmentService service;

  @override
  State<ManualAttachmentGallery> createState() =>
      _ManualAttachmentGalleryState();
}

class _ManualAttachmentGalleryState extends State<ManualAttachmentGallery> {
  String? _rootPath;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _rootPath = widget.service.cachedRootPath;
    _loadRoot();
  }

  @override
  void didUpdateWidget(covariant ManualAttachmentGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service) || _rootPath == null) {
      _loadRoot();
    }
  }

  Future<void> _loadRoot() async {
    if (widget.attachments.isEmpty) return;
    final root = await widget.service.getAttachmentRoot();
    if (!mounted || root == null) return;
    if (_rootPath != root) {
      setState(() => _rootPath = root);
    }
  }

  Future<void> _openFile(ManualAttachment attachment) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final status = await widget.service.openAttachment(attachment);
      if (!mounted) return;
      switch (status) {
        case AttachmentOpenStatus.ok:
          break;
        case AttachmentOpenStatus.missingFile:
          showJournalMessage(context, '附件文件已缺失或被清理，无法打开');
        case AttachmentOpenStatus.noApp:
          showJournalMessage(context, '未找到可打开此类型文件的应用');
        case AttachmentOpenStatus.failed:
          showJournalMessage(context, '无法打开附件，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.attachments.isEmpty) {
      return const SizedBox.shrink(
          key: ValueKey('manual-detail-attachments-slot'));
    }
    final journal = Journal.of(context);
    final images = [
      for (final item in widget.attachments)
        if (item.isImage) item,
    ];
    final files = [
      for (final item in widget.attachments)
        if (!item.isImage) item,
    ];

    return Padding(
      key: const ValueKey('manual-detail-attachments-slot'),
      padding: const EdgeInsets.only(top: 12),
      child: JournalGroupedCard(
        title: '附件（${widget.attachments.length}）',
        padding: const EdgeInsets.all(14),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (images.isNotEmpty)
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
                    return Semantics(
                      button: true,
                      label: '查看图片 ${item.name}',
                      onTap: () => showAttachmentImageGallery(
                        context,
                        images: images,
                        initialIndex: index,
                        service: widget.service,
                        rootPath: _rootPath,
                      ),
                      excludeSemantics: true,
                      child: InkWell(
                        key: ValueKey('detail-attachment-image-${item.id}'),
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => showAttachmentImageGallery(
                          context,
                          images: images,
                          initialIndex: index,
                          service: widget.service,
                          rootPath: _rootPath,
                        ),
                        child: AttachmentImageThumbnail(
                          attachment: item,
                          service: widget.service,
                          rootPath: _rootPath,
                        ),
                      ),
                    );
                  },
                ),
              if (images.isNotEmpty && files.isNotEmpty)
                const SizedBox(height: 10),
              for (var i = 0; i < files.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _DetailFileTile(
                  attachment: files[i],
                  journal: journal,
                  onTap: () => _openFile(files[i]),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailFileTile extends StatelessWidget {
  const _DetailFileTile({
    required this.attachment,
    required this.journal,
    required this.onTap,
  });

  final ManualAttachment attachment;
  final JournalPalette journal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: journal.parchment,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: ValueKey('detail-attachment-file-${attachment.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.insert_drive_file_outlined,
                  size: 20,
                  color: journal.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: journal.entryTitle.copyWith(fontSize: 14.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        attachment.formattedSize,
                        style: journal.metadata,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: journal.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

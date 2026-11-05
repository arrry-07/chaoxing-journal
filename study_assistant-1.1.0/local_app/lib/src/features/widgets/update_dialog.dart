import 'package:flutter/material.dart';
import '../../app/app_version.dart';
import '../../services/app_update_controller.dart';
import '../../services/app_update_service.dart';
import '../../services/external_link_service.dart';

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, this.controller, this.service, this.links});
  final AppUpdateController? controller;
  final AppUpdateService? service;
  final ExternalLinkService? links;
  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  late final AppUpdateController task;
  @override
  void initState() {
    super.initState();
    task = widget.controller ??
        AppUpdateController(service: widget.service, links: widget.links);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          (task.phase == UpdatePhase.idle ||
              task.phase == UpdatePhase.checked)) {
        task.check();
      }
    });
  }

  @override
  void dispose() {
    if (widget.controller == null) task.dispose();
    super.dispose();
  }

  Future<void> downloadAndInstall() async {
    await task.download();
    // A background download must never open the installer over another screen/app.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (mounted &&
        ModalRoute.of(context)?.isCurrent == true &&
        task.phase == UpdatePhase.ready &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed)) {
      await task.install();
    }
  }

  Future<void> openRelease() async {
    try {
      final opened = await task.links.openUrl(
          task.update?.releaseUrl ?? '${AppUpdateService.releasesUrl}/latest');
      if (!opened) throw StateError('browser unavailable');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法打开浏览器，请稍后重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: task,
      builder: (context, _) {
        final update = task.update;
        final progress = task.progress;
        return AlertDialog(
          title: const Text('应用更新'),
          content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('当前版本 ${AppVersion.display}',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
                    Semantics(liveRegion: true, child: Text(task.message)),
                    if (task.busy) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                          value: task.phase == UpdatePhase.downloading
                              ? progress
                              : null),
                      if (task.phase == UpdatePhase.downloading &&
                          progress != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('${(progress * 100).floor()}%')),
                    ],
                    if (update != null) ...[
                      const SizedBox(height: 16),
                      Text(
                          '版本 ${update.versionName}${update.versionCode == null ? '' : '（${update.versionCode}）'}',
                          style: Theme.of(context).textTheme.titleMedium),
                      if (update.apkSize != null)
                        Text(
                            '下载大小 ${(update.apkSize! / 1048576).toStringAsFixed(1)} MB'),
                      if (update.releaseNotes.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(update.releaseNotes),
                      ],
                    ],
                    if (task.downloading) ...[
                      const SizedBox(height: 12),
                      const Text('收起后可继续使用应用；下载完成后再确认安装。'),
                    ],
                    if (!task.busy)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                            onPressed: openRelease,
                            child: const Text('查看 GitHub 发行版')),
                      ),
                  ]))),
          actions: [
            if (task.phase == UpdatePhase.downloading)
              TextButton(
                  onPressed: task.cancelDownload, child: const Text('取消下载')),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(task.downloading ? '后台下载' : '关闭')),
            if (!task.busy && update == null)
              TextButton(onPressed: task.check, child: const Text('重新检查')),
            if (!task.busy && update != null)
              FilledButton(
                  onPressed: task.downloadedPath == null
                      ? downloadAndInstall
                      : task.install,
                  child: Text(task.downloadedPath == null ? '下载并安装' : '安装更新')),
          ],
        );
      });
}

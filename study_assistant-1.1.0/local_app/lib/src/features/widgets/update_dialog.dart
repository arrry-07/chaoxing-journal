import 'package:flutter/material.dart';
import '../../app/app_version.dart';
import '../../app/journal.dart';
import '../../services/app_update_controller.dart';
import '../../services/app_update_service.dart';
import '../../services/external_link_service.dart';

Future<void> showUpdateDialog(
    BuildContext context, AppUpdateController task) async {
  if (task.dialogIsOpen) return;
  task.dialogIsOpen = true;
  task.hasShownDialog = true;
  try {
    await showDialog<void>(
        context: context, builder: (_) => UpdateDialog(controller: task));
  } finally {
    task.dialogIsOpen = false;
  }
}

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
  bool _savingIgnore = false;

  Future<void> ignoreVersion() async {
    setState(() => _savingIgnore = true);
    final saved = await task.ignoreCurrentVersion();
    if (!mounted) return;
    if (saved && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.pop(context);
    } else {
      setState(() => _savingIgnore = false);
    }
  }

  @override
  void initState() {
    super.initState();
    task = widget.controller ??
        AppUpdateController(service: widget.service, links: widget.links);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          (task.phase == UpdatePhase.idle ||
              task.phase == UpdatePhase.checked ||
              task.phase == UpdatePhase.checking)) {
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

  Widget actions(BuildContext context) {
    void close() => Navigator.pop(context);
    final phase = task.phase;
    final ready = task.downloadedPath != null;
    String? primary;
    VoidCallback? action;
    final secondary = <Widget>[];
    if (task.downloading) {
      primary = phase == UpdatePhase.verifying ? '收起，继续使用' : '后台下载';
      action = close;
      if (phase == UpdatePhase.downloading) {
        secondary.add(TextButton(
            onPressed: task.cancelDownload, child: const Text('取消下载')));
      }
    } else if (task.busy) {
      secondary.add(TextButton(onPressed: close, child: const Text('关闭')));
    } else if (task.update != null) {
      primary = ready
          ? '安装更新'
          : (phase == UpdatePhase.failed || phase == UpdatePhase.cancelled)
              ? '重新下载'
              : '下载并安装';
      action = ready ? task.install : downloadAndInstall;
      secondary.add(TextButton(
          onPressed: close,
          child: Text(ready
              ? '稍后安装'
              : phase == UpdatePhase.available
                  ? '稍后更新'
                  : '稍后再说')));
      if (!ready && phase == UpdatePhase.available) {
        secondary.add(TextButton(
            onPressed: _savingIgnore ? null : ignoreVersion,
            child: Text(_savingIgnore ? '正在保存…' : '忽略此版本')));
      }
    } else {
      if (phase == UpdatePhase.failed) {
        primary = '重新检查';
        action = task.check;
      }
      secondary.add(TextButton(onPressed: close, child: const Text('关闭')));
    }
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (primary != null)
            FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14)),
                onPressed: action,
                child: Text(primary)),
          if (secondary.isNotEmpty) ...[
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, c) {
              if (c.maxWidth < 260 ||
                  MediaQuery.textScalerOf(context).scale(14) > 21) {
                return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: secondary);
              }
              return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final button in secondary) Flexible(child: button)
                  ]);
            }),
          ],
        ]);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: task,
      builder: (context, _) {
        final update = task.update;
        final phase = task.phase;
        final title = switch (phase) {
          UpdatePhase.downloading => '正在下载更新',
          UpdatePhase.verifying => '正在校验更新',
          UpdatePhase.ready => '更新已就绪',
          UpdatePhase.installing => '准备安装更新',
          UpdatePhase.failed => update == null ? '检查更新失败' : '更新未完成',
          UpdatePhase.cancelled => '下载已取消',
          _ => update == null ? '应用更新' : '发现新版本',
        };
        return Dialog(
            backgroundColor: Journal.sheet,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: LayoutBuilder(builder: (context, bounds) {
                  final compact = bounds.maxHeight < 520 ||
                      MediaQuery.textScalerOf(context).scale(14) > 21;
                  final body = Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: Journal.section.copyWith(fontSize: 23)),
                        const SizedBox(height: 16),
                        if (update != null) ...[
                          Text(update.versionName,
                              style: Journal.display.copyWith(fontSize: 30)),
                          const SizedBox(height: 4),
                          Text(
                              '当前版本 ${AppVersion.display}'
                              '${update.apkSize == null ? '' : ' · ${(update.apkSize! / 1048576).toStringAsFixed(1)} MB'}',
                              style: Journal.metadata),
                          const SizedBox(height: 16),
                        ] else ...[
                          Text('当前版本 ${AppVersion.display}',
                              style: Journal.metadata),
                          const SizedBox(height: 12),
                        ],
                        if (task.message != title)
                          Semantics(
                              liveRegion: !task.downloading,
                              child: Text(task.message,
                                  style: Journal.metadata.copyWith(
                                      color: phase == UpdatePhase.failed
                                          ? Journal.berry
                                          : Journal.muted))),
                        if (task.busy) ...[
                          const SizedBox(height: 16),
                          ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                  minHeight: 6,
                                  value: phase == UpdatePhase.downloading
                                      ? task.progress
                                      : null)),
                          if (phase == UpdatePhase.downloading) ...[
                            const SizedBox(height: 8),
                            Text(
                                '${task.progress == null ? '' : '${(task.progress! * 100).floor()}% · '}${task.transferSummary}',
                                style: Journal.metadata),
                          ],
                        ],
                        if (task.downloading) ...[
                          const SizedBox(height: 12),
                          const Text('收起后可继续使用应用；下载完成后再确认安装。',
                              style: Journal.metadata),
                        ],
                        if (update != null &&
                            !task.downloading &&
                            update.releaseNotes.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Text('更新内容', style: Journal.entryTitle),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                              constraints: BoxConstraints(
                                  maxHeight: compact ? 140 : 180),
                              child: Scrollbar(
                                  child: SingleChildScrollView(
                                      primary: false,
                                      child: Text(update.releaseNotes,
                                          style: Journal.metadata
                                              .copyWith(color: Journal.ink))))),
                        ],
                        if (update != null &&
                            !task.busy &&
                            task.downloadedPath == null) ...[
                          const SizedBox(height: 16),
                          SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('尝试多连接加速',
                                  style: Journal.metadata),
                              subtitle: Text('下载较慢时可尝试，速度取决于网络。',
                                  style:
                                      Journal.metadata.copyWith(fontSize: 12)),
                              value: task.service.parallelDownloads,
                              onChanged: (v) => setState(
                                  () => task.service.parallelDownloads = v)),
                        ],
                        if (!task.busy)
                          TextButton(
                              onPressed: openRelease,
                              style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  alignment: Alignment.centerLeft),
                              child: const Text('查看 GitHub 发行版')),
                      ]);
                  final footer = Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: actions(context));
                  return Padding(
                      padding: const EdgeInsets.all(24),
                      child: compact
                          ? SingleChildScrollView(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [body, footer]))
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                  Flexible(
                                      child:
                                          SingleChildScrollView(child: body)),
                                  footer
                                ]));
                })));
      });
}

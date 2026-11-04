import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../app/app_version.dart';
import '../../services/app_update_service.dart';
import '../../services/external_link_service.dart';

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.service, this.links});
  final AppUpdateService service;
  final ExternalLinkService? links;
  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final cancel = CancelToken();
  UpdateCheckResult? result;
  bool busy = true;
  String? message;
  double? progress;
  String? downloadedPath;
  @override
  void initState() {
    super.initState();
    check();
  }

  @override
  void dispose() {
    cancel.cancel();
    super.dispose();
  }

  Future<void> check() async {
    setState(() {
      busy = true;
      message = null;
    });
    final r = await widget.service.checkConfigured(
        currentVersionCode: AppVersion.code, cancelToken: cancel);
    if (mounted) {
      setState(() {
        result = r;
        busy = false;
        message = r.message;
      });
    }
  }

  Future<void> install() async {
    setState(() {
      busy = true;
      message = '正在下载更新包';
    });
    try {
      final update = result!.update!;
      downloadedPath ??= (await widget.service
              .downloadApk(update, cancelToken: cancel, onProgress: (r, t) {
        if (mounted) setState(() => progress = t > 0 ? r / t : null);
      }))
          .path;
      if (!mounted) return;
      final links = widget.links ?? ExternalLinkService();
      final info = await links.inspectApk(downloadedPath!);
      if (info['compatible'] != true ||
          info['applicationId'] != update.applicationId ||
          info['versionCode'] != update.versionCode) {
        throw StateError(info['reason'] ?? '安装包身份与清单不符');
      }
      final opened = await links.installApk(downloadedPath!);
      if (mounted) {
        setState(() =>
            message = opened ? '已打开系统安装器，请确认安装；取消后仍可重试' : '无法打开安装器，请检查安装权限后重试');
      }
    } catch (e) {
      if (mounted) {
        setState(() => message = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('应用更新'),
          content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(message ?? '正在检查更新…'),
                if (busy) LinearProgressIndicator(value: progress),
                if (busy && progress != null)
                  Text('${(progress! * 100).round()}%'),
                if (result?.update != null) ...[
                  Text(
                      '版本 ${result!.update!.versionName}（${result!.update!.versionCode}）'),
                  if (result!.update!.apkSize != null)
                    Text(
                        '下载大小 ${(result!.update!.apkSize! / 1048576).toStringAsFixed(1)} MB'),
                  Text(result!.update!.releaseNotes)
                ]
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(busy ? '取消' : '关闭')),
            if (!busy &&
                {UpdateCheckStatus.networkError, UpdateCheckStatus.cancelled}
                    .contains(result?.status))
              TextButton(onPressed: check, child: const Text('重试')),
            if (!busy && result?.update != null)
              FilledButton(
                  onPressed: install,
                  child: Text(downloadedPath == null ? '下载并安装' : '重试安装')),
            if (!busy && result?.status != UpdateCheckStatus.available)
              TextButton(
                  onPressed: () async {
                    try {
                      await (widget.links ?? ExternalLinkService())
                          .openUrl(AppUpdateService.releasesUrl);
                    } catch (_) {
                      if (mounted) setState(() => message = '无法打开浏览器');
                    }
                  },
                  child: const Text('浏览器查看发行版'))
          ]);
}

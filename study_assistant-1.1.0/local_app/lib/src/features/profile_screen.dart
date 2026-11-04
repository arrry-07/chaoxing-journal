import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_version.dart';
import '../app/journal.dart';
import '../services/app_update_service.dart';
import '../services/assignment_store.dart';
import '../services/external_link_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.store,
    this.updateService,
    this.externalLinkService,
  });

  static const _githubUrl = AppUpdateService.repositoryUrl;

  final AssignmentStore store;
  final AppUpdateService? updateService;
  final ExternalLinkService? externalLinkService;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final courses =
            store.assignments.map((a) => a.courseName).toSet().toList()..sort();
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            _ProfileHeader(
              displayName: store.profileDisplayName,
              avatarUrl: store.profileAvatarUrl,
              accountLabel: store.account ?? '未绑定账号',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CourseCard(courses: courses),
                  const SizedBox(height: 14),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.notifications_none,
                        title: '提醒设置',
                        onTap: () => context.push('/reminders'),
                      ),
                      _SettingsTile(
                        icon: Icons.sync,
                        title: '同步学习通',
                        onTap: () => context.push('/sync'),
                      ),
                      _SettingsTile(
                        icon: Icons.inventory_2_outlined,
                        title: '本地记录',
                        subtitle: '${store.assignments.length} 条作业记录保存在本机',
                      ),
                      _SettingsTile(
                        icon: Icons.help_outline,
                        title: '帮助与反馈',
                        onTap: () => _openGithub(context, issues: true),
                      ),
                      _SettingsTile(
                        icon: Icons.info_outline,
                        title: '关于我们',
                        subtitle: 'arrry-07 · MIT License · v${AppVersion.display}',
                        onTap: () => _showAbout(context),
                      ),
                      _SettingsTile(
                        icon: Icons.system_update_alt,
                        title: '检查更新',
                        subtitle: '打开本仓库 Releases，登录后下载新版',
                        onTap: () => _checkForUpdates(context),
                      ),
                      _SettingsTile(
                        icon: Icons.code,
                        title: 'GitHub 源码',
                        subtitle: 'github.com/arrry-07/chaoxing-journal',
                        trailing: Icons.open_in_new,
                        onTap: () => _openGithub(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: store.logout,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                        side: const BorderSide(color: Color(0xFFFFE0E0)),
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('退出登录'),
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openGithub(BuildContext context, {bool issues = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await (externalLinkService ?? ExternalLinkService()).openUrl(
      issues ? '$_githubUrl/issues' : _githubUrl,
    );
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('无法打开 GitHub 链接，请检查浏览器或网络')),
      );
    }
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: '课业手记',
      applicationVersion: AppVersion.display,
      applicationLegalese: '基于 HY / study_assistant 二次开发\n原项目版权 © 2026 HY · MIT License',
      children: const [
        SizedBox(height: 8),
        Text('本应用用于本地同步学习通作业提醒，账号和作业数据仅保存在本机。'),
      ],
    );
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    // Private release assets require the user's GitHub browser session.
    // Never embed a repository access token in an Android application.
    if (AppUpdateService.privateRepository && updateService == null) {
      final opened = await (externalLinkService ?? ExternalLinkService())
          .openUrl(AppUpdateService.releasesUrl);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('无法打开更新页面，请在浏览器登录 GitHub 后重试')));
      }
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('正在检查更新...'),
        duration: Duration(seconds: 1),
      ),
    );
    try {
      final update = await (updateService ?? AppUpdateService()).checkForUpdate(
        currentVersionName: AppVersion.name,
        currentVersionCode: AppVersion.code,
      );
      if (!context.mounted) {
        return;
      }
      if (update == null) {
        messenger.showSnackBar(const SnackBar(content: Text('暂无可用更新信息；私有仓库请登录 GitHub 查看 Releases')));
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('发现新版本 ${update.versionName}'),
            content: Text(
              [
                '安装包：${update.apkName}',
                if (update.releaseNotes.trim().isNotEmpty) '',
                if (update.releaseNotes.trim().isNotEmpty)
                  update.releaseNotes.trim(),
              ].join('\n'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('稍后'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  final apkFile = await _downloadUpdateWithProgress(
                    context,
                    update,
                  );
                  if (apkFile == null) {
                    return;
                  }
                  if (context.mounted) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('安装包已下载，正在打开系统安装器')),
                    );
                  }
                  final opened =
                      await (externalLinkService ?? ExternalLinkService())
                          .installApk(apkFile.path);
                  if (!opened && context.mounted) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('无法打开系统安装器')),
                    );
                  }
                },
                icon: const Icon(Icons.download),
                label: const Text('下载并安装'),
              ),
            ],
          );
        },
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      navigator.popUntil((route) => route.isFirst || route.isCurrent);
      messenger.showSnackBar(const SnackBar(content: Text('检查更新失败，请稍后再试')));
    }
  }

  Future<File?> _downloadUpdateWithProgress(
    BuildContext context,
    AppUpdateInfo update,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ValueNotifier<_DownloadProgress>(
      const _DownloadProgress(receivedBytes: 0, totalBytes: 0),
    );
    File? apkFile;
    Object? downloadError;
    Future<void>? downloadFuture;
    var started = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (progressContext) {
        if (!started) {
          started = true;
          downloadFuture = (updateService ?? AppUpdateService()).downloadApk(
            update,
            onProgress: (received, total) {
              notifier.value = _DownloadProgress(
                receivedBytes: received,
                totalBytes: total,
              );
            },
          ).then((file) {
            apkFile = file;
          }).catchError((error) {
            downloadError = error;
          }).whenComplete(() {
            if (progressContext.mounted) {
              Navigator.of(progressContext).pop();
            }
          });
        }
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('正在下载更新包'),
            content: ValueListenableBuilder<_DownloadProgress>(
              valueListenable: notifier,
              builder: (context, progress, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: progress.hasTotal ? progress.ratio : null,
                    ),
                    const SizedBox(height: 12),
                    Text(progress.label),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
    await downloadFuture;
    notifier.dispose();

    if (downloadError != null) {
      if (context.mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('下载更新包失败，请稍后再试')));
      }
      return null;
    }
    return apkFile;
  }
}

class _DownloadProgress {
  const _DownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int totalBytes;

  bool get hasTotal => totalBytes > 0;

  double? get ratio {
    if (!hasTotal) {
      return null;
    }
    return (receivedBytes / totalBytes).clamp(0, 1).toDouble();
  }

  String get label {
    if (!hasTotal) {
      return '已下载 ${_formatBytes(receivedBytes)}';
    }
    final percent = ((ratio ?? 0) * 100).clamp(0, 100).round();
    return '$percent% · ${_formatBytes(receivedBytes)} / ${_formatBytes(totalBytes)}';
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.displayName,
    required this.avatarUrl,
    required this.accountLabel,
  });

  final String displayName;
  final String? avatarUrl;
  final String accountLabel;

  @override
  Widget build(BuildContext context) {
    final url = _profileAvatarUrl(avatarUrl);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 16, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: JournalHeading(
                  '我的手帐',
                  eyebrow: 'CAMPUS JOURNAL   /   04',
                ),
              ),
              IconButton(
                tooltip: '打开提醒设置',
                onPressed: () => context.push('/reminders'),
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: Journal.sage,
                child: url == null
                    ? const Icon(Icons.face_outlined)
                    : ClipOval(
                        child: Image.network(
                          url,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          headers: _profileAvatarHeaders(url),
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.face_outlined),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(accountLabel),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String? _profileAvatarUrl(String? avatarUrl) {
  final trimmed = avatarUrl?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null) {
    return trimmed;
  }
  if (uri.host.toLowerCase() != 'photo.chaoxing.com') {
    return trimmed;
  }
  final query = Map<String, String>.from(uri.queryParameters)
    ..['psize'] = '160_160c'
    ..['ext'] = 'png';
  return uri.replace(scheme: 'https', queryParameters: query).toString();
}

Map<String, String>? _profileAvatarHeaders(String? avatarUrl) {
  final uri = Uri.tryParse(avatarUrl ?? '');
  final host = uri?.host.toLowerCase();
  if (host == null ||
      (host != 'photo.chaoxing.com' && !host.endsWith('.cldisk.com'))) {
    return null;
  }
  return const {
    'Referer': 'https://photo.chaoxing.com/',
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
  };
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.courses});
  final List<String> courses;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('我的课程', style: Journal.section),
              const SizedBox(height: 10),
              if (courses.isEmpty) const Text('同步后，有作业的课程会记在这里。'),
              Wrap(
                spacing: 18,
                runSpacing: 10,
                children: [for (final name in courses) CourseLabel(name)],
              ),
            ],
          ),
        ),
      );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              '设置',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          for (var i = 0; i < children.length; i += 1) ...[
            children[i],
            if (i != children.length - 1)
              const Divider(height: 1, indent: 56, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.onTap,
    this.subtitle,
    this.trailing = Icons.chevron_right,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final IconData trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Journal.ink, size: 22),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: onTap == null ? null : Icon(trailing, color: Journal.muted),
      onTap: onTap,
    );
  }
}

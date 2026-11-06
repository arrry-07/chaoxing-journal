import 'widgets/update_scope.dart';
import 'widgets/update_dialog.dart';
import 'open_source_screen.dart';
import 'package:flutter/services.dart';

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
        final courses = store.courses.map((c) {
          final same =
              store.courses.where((other) => other.name == c.name).toList();
          return same.length > 1
              ? '${c.name}（${same.indexWhere((other) => other.key == c.key) + 1}班）'
              : c.name;
        }).toList();
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
                  _CourseCard(courses: courses.take(4).toList()),
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
                        onTap: () => context.push('/records'),
                      ),
                      _SettingsTile(
                        icon: Icons.visibility_off_outlined,
                        title: '已隐藏作业',
                        subtitle:
                            '${store.hiddenAssignments.length} 条，可恢复到作业清单',
                        onTap: () => _showHiddenAssignments(context),
                      ),
                      _SettingsTile(
                        icon: Icons.help_outline,
                        title: '帮助与反馈',
                        onTap: () => context.push('/help'),
                      ),
                      _SettingsTile(
                        icon: Icons.info_outline,
                        title: '关于我们',
                        subtitle:
                            'arrry-07 · MIT License · v${AppVersion.display}',
                        onTap: () => _showAbout(context),
                      ),
                      _SettingsTile(
                          icon: Icons.description_outlined,
                          title: '开源许可',
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) => const OpenSourceScreen()))),
                      _SettingsTile(
                        icon: Icons.system_update_alt,
                        title: '检查更新',
                        subtitle: '在应用内检查版本和下载更新',
                        onTap: () => _checkForUpdates(context),
                      ),
                      _SettingsTile(
                        icon: Icons.code,
                        title: 'GitHub 源码',
                        subtitle: 'github.com/arrry-07/chaoxing-journal',
                        trailing: Icons.open_in_new,
                        onTap: () async {
                          await Clipboard.setData(
                              const ClipboardData(text: _githubUrl));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('链接已复制')));
                          }
                        },
                        trailingOnPressed: () => _openGithub(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: store.isLoading
                          ? null
                          : () => _confirmLogout(context),
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

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出并清理本机记录？'),
        content: const SingleChildScrollView(
          child: Text(
            '退出将清除本机保存的账号密码、课程作业、隐藏状态、课程关注、提醒设置、同步记录、仓库损坏备份和账号切换备份（含其他账号），并清理作业通知与小组件。自动同步间隔会保留。\n\n学习通服务器上的课程作业不会删除。需要重新登录后同步，本机隐藏与关注选择无法从服务端恢复。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认退出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await store.logout();
      if (!context.mounted) return;
      if (store.error != null || store.isAuthenticated) {
        _showLogoutFailure(context);
      }
    } catch (_) {
      if (context.mounted) _showLogoutFailure(context);
    }
  }

  void _showLogoutFailure(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('退出未完成，请稍后重试；本机记录可能尚未全部清理')),
    );
  }

  void _showHiddenAssignments(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: AnimatedBuilder(
          animation: store,
          builder: (context, _) => Column(children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('已隐藏作业')),
            if (store.error != null)
              Padding(
                  padding: const EdgeInsets.all(12), child: Text(store.error!)),
            Expanded(
                child: store.hiddenAssignments.isEmpty
                    ? const Center(child: Text('暂无隐藏作业'))
                    : ListView.builder(
                        itemCount: store.hiddenAssignments.length,
                        itemBuilder: (context, index) {
                          final item = store.hiddenAssignments[index];
                          return ListTile(
                              title: Text(item.title),
                              subtitle: Text(item.courseName),
                              trailing: TextButton(
                                  onPressed: store.isLoading
                                      ? null
                                      : () => store.updateCompletion(
                                          item.id, false),
                                  child: const Text('恢复')));
                        })),
          ]),
        ),
      ),
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
      applicationName: '学习通课业手记',
      applicationVersion: AppVersion.display,
      applicationLegalese: '维护者 arrry-07',
      children: const [
        SizedBox(height: 8),
        Text('本应用用于本地同步学习通作业提醒，账号和作业数据仅保存在本机。'),
      ],
    );
  }

  Future<void> _checkForUpdates(BuildContext context) {
    final controller = AppUpdateScope.maybeOf(context);
    if (controller != null) return showUpdateDialog(context, controller);
    return showDialog<void>(
        context: context,
        builder: (_) => UpdateDialog(
            controller: AppUpdateScope.maybeOf(context),
            service: updateService ?? AppUpdateService(),
            links: externalLinkService));
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
              Row(children: [
                const Expanded(child: Text('我的课程', style: Journal.section)),
                IconButton(
                  tooltip: '管理全部课程',
                  onPressed: () => context.push('/courses'),
                  icon: const Icon(Icons.tune_rounded),
                ),
              ]),
              const SizedBox(height: 10),
              if (courses.isEmpty) const Text('同步后，有作业的课程会记在这里。'),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final name in courses)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: CourseLabel(name))
                ],
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
    this.trailingOnPressed,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final IconData trailing;
  final VoidCallback? onTap;
  final VoidCallback? trailingOnPressed;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Journal.ink, size: 22),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailingOnPressed != null
          ? IconButton(
              tooltip: '打开链接',
              onPressed: trailingOnPressed,
              icon: Icon(trailing))
          : onTap == null
              ? null
              : Icon(trailing, color: Journal.muted),
      onTap: onTap,
    );
  }
}

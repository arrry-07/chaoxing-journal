import 'display_settings_screen.dart';
import 'widgets/appearance_controls.dart';
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
        final journal = Journal.of(context);
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            _ProfileHeader(
              displayName: store.profileDisplayName,
              avatarUrl: store.profileAvatarUrl,
              accountLabel: _maskAccount(store.account),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    key: const ValueKey('profile-group-courses'),
                    color: journal.sheet,
                    clipBehavior: Clip.antiAlias,
                    child: IconTheme.merge(
                      data: IconThemeData(color: journal.ink),
                      child: _SettingsTile(
                        icon: Icons.school_outlined,
                        title: '我的课程',
                        subtitle: store.courses.isEmpty
                            ? '暂无课程，前往查看与同步'
                            : '已同步 ${store.courses.length} 门课程',
                        compactSubtitle: true,
                        onTap: () => context.push('/courses'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
                    child: Text('设置', style: journal.section),
                  ),
                  AppearanceControls(
                    store: store,
                    onMore: () {
                      final router = GoRouter.maybeOf(context);
                      if (router != null) {
                        router.push('/profile/display');
                      } else {
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute<void>(
                            builder: (_) => DisplaySettingsScreen(store: store),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _SettingsCard(
                    title: '学习与同步',
                    accentColor: journal.ink,
                    headerColor: journal.sage,
                    children: [
                      _SettingsTile(
                        icon: Icons.sync,
                        title: '同步学习通',
                        subtitle: '更新课程与作业等学习数据',
                        compactSubtitle: true,
                        onTap: () => context.push('/sync'),
                      ),
                      _SettingsTile(
                        icon: Icons.event_note_outlined,
                        title: '个人安排',
                        subtitle: '个人待办、考试与每日计划',
                        onTap: () => context.push('/profile/arrangements'),
                      ),
                      _SettingsTile(
                        icon: Icons.inventory_2_outlined,
                        title: '学习记录',
                        subtitle:
                            '${store.localRecordGroups.length} 项课业 · ${store.changes.length} 条变化',
                        onTap: () => context.push('/profile/records'),
                      ),
                      _SettingsTile(
                        icon: Icons.library_books_outlined,
                        title: '课程通知与章节',
                        subtitle: store.courseNotices.items.isEmpty &&
                                store.courseChapters.byCourse.isEmpty
                            ? '手动查看课程通知与章节任务点进度'
                            : '未读通知 ${store.unreadCourseNoticeCount} 条 · 待完成小节 ${store.pendingChapterSectionCount} 处',
                        onTap: () => context.push('/course-hub'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingsCard(
                    title: '数据与安全',
                    accentColor: journal.ink,
                    headerColor: journal.sage,
                    children: [
                      _SettingsTile(
                        icon: Icons.notifications_none_rounded,
                        title: '提醒与通知',
                        subtitle: '权限状态、提前提醒时间与每日摘要',
                        compactSubtitle: true,
                        onTap: () => context.push('/reminders'),
                      ),
                      _SettingsTile(
                        icon: Icons.enhanced_encryption_outlined,
                        title: '加密备份与恢复',
                        subtitle: '仅备份本机课业记录，不含登录凭据',
                        onTap: () => context.push('/backup'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingsCard(
                    title: '关于与更新',
                    accentColor: journal.ink,
                    headerColor: journal.sage,
                    children: [
                      _SettingsTile(
                        icon: Icons.help_outline,
                        title: '帮助与反馈',
                        subtitle: '查看使用说明，反馈问题与建议',
                        compactSubtitle: true,
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
                        subtitle: '查看应用使用的开源组件及许可证',
                        compactSubtitle: true,
                        onTap: () {
                          final router = GoRouter.maybeOf(context);
                          if (router != null) {
                            router.push('/open-source');
                          } else {
                            Navigator.of(context, rootNavigator: true).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const OpenSourceScreen(),
                              ),
                            );
                          }
                        },
                      ),
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
                        foregroundColor: journal.ink,
                        side: BorderSide(color: journal.rule, width: 0.8),
                        backgroundColor: journal.sheet,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        '退出登录并清理本机记录',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  SizedBox(height: JournalLayout.floatingNavClearance(context)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出并清理本机记录？'),
        content: const SingleChildScrollView(
          child: Text(
            '退出将清除本机保存的账号密码、课程作业、隐藏状态、课程关注、个人计划与备注清单、文件关联、提醒与摘要设置、同步记录、仓库损坏备份和账号切换备份（含其他账号），并清理作业通知与小组件。自动同步间隔会保留。\n\n学习通服务器上的课程作业不会删除。需要重新登录后同步；个人记录请先加密备份，本地文件关联需重新选择。建议先导出加密备份。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'backup'),
            child: const Text('先备份'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'cancel'),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'logout'),
            style: FilledButton.styleFrom(
              backgroundColor: Journal.of(context).berry,
              foregroundColor: Journal.of(context).sheet,
            ),
            child: const Text('退出并清理本机记录'),
          ),
        ],
      ),
    );
    if (action == 'backup' && context.mounted) {
      await context.push('/backup');
      return;
    }
    if (action != 'logout' || !context.mounted) return;
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
    final journal = Journal.of(context);
    final url = _profileAvatarUrl(avatarUrl);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const JournalHeading(
            '我的手帐',
            bookTitle: true,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: journal.rule, width: 1),
                ),
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: journal.sage,
                  child: url == null
                      ? const Icon(Icons.face_outlined)
                      : ClipOval(
                          child: Image.network(
                            url,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            headers: _profileAvatarHeaders(url),
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.face_outlined),
                          ),
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

String _maskAccount(String? account) {
  if (account == null) return '未绑定账号';
  final trimmed = account.trim();
  if (RegExp(r'^\d{11}$').hasMatch(trimmed)) {
    return '${trimmed.substring(0, 3)}****${trimmed.substring(7)}';
  }
  return account;
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

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.accentColor,
    required this.headerColor,
    required this.children,
  });

  final String title;
  final Color accentColor;
  final Color headerColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final foreground = Color.lerp(journal.ink, accentColor, .50)!;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: IconTheme.merge(
        data: IconThemeData(color: foreground),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              key: ValueKey('profile-group-$title'),
              width: double.infinity,
              decoration: BoxDecoration(
                color: journal.sectionHeaderFill,
                border: Border(
                  bottom: BorderSide(color: journal.divider, width: 0.6),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                title,
                style: journal.section.copyWith(
                  color: foreground,
                  fontSize: 17,
                ),
              ),
            ),
            for (var i = 0; i < children.length; i += 1) ...[
              children[i],
              if (i != children.length - 1)
                const Divider(height: 1, indent: 56, endIndent: 16),
            ],
          ],
        ),
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
    this.compactSubtitle = false,
    this.trailing = Icons.chevron_right,
    this.trailingOnPressed,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool compactSubtitle;
  final IconData trailing;
  final VoidCallback? onTap;
  final VoidCallback? trailingOnPressed;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return ListTile(
      leading: Icon(icon, color: IconTheme.of(context).color, size: 22),
      title: Text(title, style: journal.entryTitle),
      subtitle: subtitle == null ? null : Text(subtitle!),
      subtitleTextStyle: compactSubtitle
          ? Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 12,
                height: 1.4,
                color: journal.muted,
              )
          : null,
      trailing: trailingOnPressed != null
          ? IconButton(
              tooltip: '打开链接',
              onPressed: trailingOnPressed,
              icon: Icon(trailing))
          : onTap == null
              ? null
              : Icon(trailing, color: journal.muted),
      onTap: onTap,
    );
  }
}

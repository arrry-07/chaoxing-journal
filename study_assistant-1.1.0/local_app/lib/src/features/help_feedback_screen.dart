import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_version.dart';
import '../app/journal.dart';
import '../app/transient_feedback.dart';
import '../services/app_update_service.dart';
import '../services/external_link_service.dart';
import 'widgets/journal_buttons.dart';
import 'widgets/journal_grouped_card.dart';
import 'widgets/journal_modal_sheet.dart';

class HelpFeedbackScreen extends StatelessWidget {
  const HelpFeedbackScreen({super.key});
  static String get feedbackTemplate =>
      '学习通课业手记 ${AppVersion.display}\n问题：\n复现步骤：\n预期结果：\n实际结果：';
  static const questions = {
    '同步失败怎么办？':
        '先在“我的 → 同步学习通”查看本次读取结果，然后重试。若提示登录失效，请重新登录；若需要安全验证，点击同步详情中的“完成安全验证”，输入图片中的字符后继续。无需安装官方 App 即可使用本应用的账号登录与同步。',
    '为什么没有看到作业？':
        '首页关注课程班级中的正式作业。已完成、已隐藏、不再关注和历史来源的记录，可以在“我的 → 学习记录 → 本地记录”查看。截止时间或提交情况无法确认的作业，会放在首页的待确认分组中。',
    '如何开启截止提醒？':
        '在“我的 → 提醒与通知”选择提前提醒时间，并允许系统通知。系统省电限制可能影响投递；请保留必要权限。本应用不会代交作业。',
    '隐藏的作业怎么恢复？': '进入“我的 → 学习记录 → 已隐藏作业”点击恢复。隐藏只改变本机显示，不会改变学习通中的提交情况。',
    '怎样更新应用？':
        '在“我的 → 检查更新”请求 GitHub Release，发现新版本后可下载并校验安装包，再由系统确认安装。网络不可达或没有可用版本时可稍后重试。升级需要兼容当前包名和签名；请保留原应用数据，不要通过卸载解决安装冲突。',
  };

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Scaffold(
      backgroundColor: journal.paper,
      appBar: AppBar(
        backgroundColor: journal.paper,
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('帮助中心'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          JournalGroupedCard(
            title: '常见问题',
            children: [
              for (final e in questions.entries)
                JournalGroupTile(
                  title: e.key,
                  onTap: () => _detail(context, e.key, e.value),
                ),
            ],
          ),
          const SizedBox(height: 14),
          JournalGroupedCard(
            children: [
              JournalGroupTile(
                icon: Icons.info_outline_rounded,
                title: '版本说明',
                subtitle: '当前版本 ${AppVersion.display}',
                onTap: () => _detail(
                  context,
                  '版本说明',
                  '支持应用内安全验证、作业截止日历和中文帮助。通过“我的 → 检查更新”访问 GitHub Release，按检查、下载、校验、系统确认安装的流程更新；网络不可达时可重试，安装包需与当前包名和签名兼容。',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          JournalPrimaryButton(
            icon: Icons.edit_note_rounded,
            label: '意见反馈',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const FeedbackScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _detail(BuildContext c, String title, String body) =>
      Navigator.of(c).push(
        MaterialPageRoute<void>(
          builder: (_) {
            final journal = Journal.of(c);
            return Scaffold(
              backgroundColor: journal.paper,
              appBar: AppBar(
                backgroundColor: journal.paper,
                leading: IconButton(
                  tooltip: '返回',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(c).maybePop(),
                ),
                title: Text(title),
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                children: [
                  JournalGroupedCard(
                    padding: const EdgeInsets.all(18),
                    children: [
                      SelectableText(
                        body,
                        style: journal.metadata.copyWith(
                          color: journal.ink,
                          fontSize: 15,
                          height: 1.7,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );
}

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key, this.links});

  final ExternalLinkService? links;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  static const _feedbackEmail = '397079535@qq.com';

  final problem = TextEditingController(), steps = TextEditingController();
  ExternalLinkService get links => widget.links ?? ExternalLinkService();

  @override
  void dispose() {
    problem.dispose();
    steps.dispose();
    super.dispose();
  }

  String feedbackBody() => '学习通课业手记 ${AppVersion.display}\n'
      '系统：${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n'
      '问题：${problem.text.trim()}\n'
      '复现步骤：${steps.text.trim()}';

  bool validateProblem() {
    if (problem.text.trim().isNotEmpty) return true;
    showJournalMessage(context, '请先描述遇到的问题');
    return false;
  }

  Future<void> copy() async {
    if (!validateProblem()) return;
    await Clipboard.setData(ClipboardData(text: feedbackBody()));
    if (mounted) {
      showJournalMessage(context, '反馈内容已复制，请粘贴发送（尚未自动发送）');
    }
  }

  Future<void> copyEmail() async {
    await Clipboard.setData(const ClipboardData(text: _feedbackEmail));
    if (mounted) {
      showJournalMessage(context, '收件邮箱已复制');
    }
  }

  Future<void> composeEmail() async {
    if (!validateProblem()) return;
    final opened = await links.composeFeedbackEmail(
      '学习通课业手记 ${AppVersion.display} 反馈',
      feedbackBody(),
    );
    if (!mounted) return;
    if (opened) {
      showJournalMessage(context, '已打开邮件草稿，请在邮箱中确认发送');
      return;
    }
    await showJournalModalSheet<void>(
      context: context,
      backgroundColor: Journal.of(context).sheetElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final journal = Journal.of(sheetContext);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: journal.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('未能打开邮件草稿', style: journal.section),
              const SizedBox(height: 8),
              Text(
                '没有可用的邮件客户端，或系统未接受打开请求。当前填写内容已保留。',
                style: journal.metadata,
              ),
              const SizedBox(height: 12),
              SelectableText(
                _feedbackEmail,
                style: journal.metadata.copyWith(color: journal.ink),
              ),
              const SizedBox(height: 16),
              JournalPrimaryButton(
                label: '复制反馈内容',
                onPressed: () {
                  Navigator.pop(sheetContext);
                  copy();
                },
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: _feedbackEmail),
                  );
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  if (mounted) {
                    showJournalMessage(context, '收件地址已复制');
                  }
                },
                child: const Text('复制收件地址'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Scaffold(
      backgroundColor: journal.paper,
      appBar: AppBar(
        backgroundColor: journal.paper,
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('意见反馈'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          JournalGroupedCard(
            padding: const EdgeInsets.all(16),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: problem,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: '遇到了什么问题？',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: steps,
                    minLines: 2,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: '怎样出现的？（选填）',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '复制或打开邮件时会附带应用和系统版本，请勿填写登录凭据或含个人信息的截图。',
              style: journal.metadata.copyWith(fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 16),
          JournalPrimaryButton(
            buttonKey: const ValueKey('feedback-copy-content'),
            icon: Icons.copy_rounded,
            label: '一键复制反馈内容',
            onPressed: copy,
          ),
          const SizedBox(height: 10),
          JournalSecondaryButton(
            buttonKey: const ValueKey('feedback-copy-email'),
            icon: Icons.alternate_email_rounded,
            label: '一键复制收件邮箱（$_feedbackEmail）',
            onPressed: copyEmail,
          ),
          const SizedBox(height: 12),
          JournalGroupedCard(
            dividerIndent: 16,
            children: [
              JournalGroupTile(
                icon: Icons.mail_outline_rounded,
                title: '尝试用系统邮件发送',
                subtitle: '打开本机邮件客户端草稿，不会自动发送',
                onTap: composeEmail,
              ),
              JournalGroupTile(
                icon: Icons.open_in_new_rounded,
                title: '打开 GitHub 反馈页面',
                onTap: () async {
                  final ok = await links
                      .openUrl('${AppUpdateService.repositoryUrl}/issues');
                  if (!ok && context.mounted) {
                    showJournalMessage(context, '无法打开反馈页面，请先复制保存');
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/app_version.dart';
import '../app/journal.dart';
import '../services/external_link_service.dart';
import '../services/app_update_service.dart';

class HelpFeedbackScreen extends StatelessWidget {
  const HelpFeedbackScreen({super.key});
  static String get feedbackTemplate =>
      '学习通课业手记 ${AppVersion.display}\n问题：\n复现步骤：\n预期结果：\n实际结果：';
  static const questions = {
    '同步失败怎么办？':
        '先在“我的 → 同步学习通”查看本次读取结果，然后重试。若提示登录失效，请重新登录；若需要安全验证，点击同步详情中的“完成安全验证”，输入图片中的字符后继续。无需安装官方 App 即可使用本应用的账号登录与同步。',
    '为什么没有看到作业？':
        '首页关注课程班级中的正式作业。已完成、已隐藏、不再关注和历史来源的记录，可以在“我的 → 本地记录”查看。截止时间或提交情况无法确认的作业，会放在首页的待确认分组中。',
    '如何开启截止提醒？': '在“我的 → 提醒设置”选择提前提醒时间，并允许系统通知。系统省电限制可能影响投递；请保留必要权限。本应用不会代交作业。',
    '隐藏的作业怎么恢复？': '进入“我的 → 已隐藏作业”点击恢复。隐藏只改变本机显示，不会改变学习通中的提交情况。',
    '怎样更新应用？':
        '在“我的 → 检查更新”请求 GitHub Release，发现新版本后可下载并校验安装包，再由系统确认安装。网络不可达或没有可用版本时可稍后重试。升级需要兼容当前包名和签名；请保留原应用数据，不要通过卸载解决安装冲突。',
  };
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          leading: IconButton(
              tooltip: '返回',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop()),
          title: const Text('帮助中心')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('有什么可以帮你？', style: Journal.section),
        const SizedBox(height: 8),
        const Text('从常见问题开始，也可以留下你的使用感受。'),
        const SizedBox(height: 24),
        const Text('常见问题', style: Journal.section),
        const SizedBox(height: 8),
        for (final e in questions.entries)
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(e.key),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _detail(context, e.key, e.value)),
        const SizedBox(height: 24),
        FilledButton.icon(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const FeedbackScreen())),
            icon: const Icon(Icons.edit_note),
            label: const Text('意见反馈')),
        const SizedBox(height: 16),
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('版本说明'),
            subtitle: Text('当前版本 ${AppVersion.display}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _detail(context, '版本说明',
                '支持应用内安全验证、作业截止日历和中文帮助。通过“我的 → 检查更新”访问 GitHub Release，按检查、下载、校验、系统确认安装的流程更新；网络不可达时可重试，安装包需与当前包名和签名兼容。')),
      ]));
  void _detail(BuildContext c, String title, String body) =>
      Navigator.of(c).push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(
              appBar: AppBar(
                  leading: IconButton(
                      tooltip: '返回',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(c).maybePop()),
                  title: Text(title)),
              body: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Text(body, style: const TextStyle(height: 1.7))))));
}

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});
  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final problem = TextEditingController(), steps = TextEditingController();
  @override
  void dispose() {
    problem.dispose();
    steps.dispose();
    super.dispose();
  }

  Future<void> copy() async {
    if (problem.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先描述遇到的问题')));
      return;
    }
    await Clipboard.setData(ClipboardData(
        text:
            '学习通课业手记 ${AppVersion.display}\n系统：${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n问题：${problem.text.trim()}\n复现步骤：${steps.text.trim()}'));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('反馈内容已复制，尚未发送')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          leading: IconButton(
              tooltip: '返回',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop()),
          title: const Text('意见反馈')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(
            controller: problem,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
                labelText: '遇到了什么问题？', alignLabelWithHint: true)),
        const SizedBox(height: 20),
        TextField(
            controller: steps,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(
                labelText: '怎样出现的？（选填）', alignLabelWithHint: true)),
        const SizedBox(height: 16),
        const Text('复制时会附带应用和系统版本。请勿填写登录信息或附上含个人信息的截图。',
            style: TextStyle(color: Journal.muted)),
        const SizedBox(height: 20),
        FilledButton(onPressed: copy, child: const Text('复制反馈内容')),
        TextButton(
            onPressed: () async {
              final ok = await ExternalLinkService()
                  .openUrl('${AppUpdateService.repositoryUrl}/issues');
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('无法打开反馈页面，请先复制保存')));
              }
            },
            child: const Text('打开反馈页面（需要仓库访问权限）')),
        const Text('这里不会自动发送。你可以复制保存，或在有权限的反馈页面中粘贴提交。'),
      ]));
}

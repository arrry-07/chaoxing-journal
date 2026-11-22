import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_version.dart';
import '../app/journal.dart';
import 'widgets/journal_buttons.dart';
import 'widgets/journal_grouped_card.dart';

class OpenSourceScreen extends StatelessWidget {
  const OpenSourceScreen({super.key});

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
        title: const Text('开源许可'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          JournalGroupedCard(
            title: '应用与查询参考',
            children: [
              _licenseTile(
                context,
                'HY / study_assistant',
                '应用基础 · MIT 许可证',
                'assets/licenses/HY.txt',
              ),
              _licenseTile(
                context,
                'xuexitong-cli',
                '课程班级与正式作业查询参考 · MIT 许可证',
                'assets/licenses/xuexitong-cli.txt',
              ),
              _licenseTile(
                context,
                'lpinyin',
                '中文课程与作业名称拼音排序 · BSD 2-Clause 许可证',
                'assets/licenses/lpinyin.txt',
              ),
            ],
          ),
          const SizedBox(height: 14),
          const JournalGroupedCard(
            title: '字体与基础组件',
            children: [
              JournalGroupTile(
                title: '霞鹜文楷 · LXGW WenKai Screen',
                subtitle: '全应用字体 · SIL OFL 1.1；原文见完整声明',
              ),
              JournalGroupTile(
                title: 'Flutter 与第三方组件',
                subtitle: '界面、网络访问、安全存储及通知等能力',
              ),
            ],
          ),
          const SizedBox(height: 16),
          JournalSecondaryButton(
            label: '完整依赖与原始许可',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LicensePage(
                  applicationName: '学习通课业手记',
                  applicationVersion: AppVersion.name,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '保留各开源项目的版权与许可声明。',
              style: journal.metadata.copyWith(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _licenseTile(
    BuildContext context,
    String name,
    String purpose,
    String asset,
  ) =>
      JournalGroupTile(
        title: name,
        subtitle: purpose,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) {
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
                  title: Text(name),
                ),
                body: FutureBuilder<String>(
                  future: rootBundle.loadString(asset),
                  builder: (context, s) => s.hasData
                      ? ListView(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                          children: [
                            JournalGroupedCard(
                              padding: const EdgeInsets.all(16),
                              children: [
                                SelectableText(
                                  s.data!,
                                  style: journal.metadata
                                      .copyWith(color: journal.ink),
                                ),
                              ],
                            ),
                          ],
                        )
                      : const Center(child: CircularProgressIndicator()),
                ),
              );
            },
          ),
        ),
      );
}

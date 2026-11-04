import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/app_version.dart';
import '../app/journal.dart';

class OpenSourceScreen extends StatelessWidget {
  const OpenSourceScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          leading: IconButton(
              tooltip: '返回',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop()),
          title: const Text('开源许可')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('一起构成这本手记', style: Journal.section),
        const SizedBox(height: 12),
        const Text(
            '学习通课业手记使用了一些开放源代码的项目，用于界面、作业读取和本机提醒。保留作者的版权与许可声明，是对这些贡献的尊重，也是使用它们时应遵守的约定。'),
        const SizedBox(height: 24),
        const Text('应用与查询参考', style: Journal.section),
        _license(context, 'HY / study_assistant', '应用基础 · MIT 许可证',
            'assets/licenses/HY.txt'),
        _license(context, 'xuexitong-cli', '课程班级与正式作业查询参考 · MIT 许可证',
            'assets/licenses/xuexitong-cli.txt'),
        const SizedBox(height: 16),
        const Text('字体与基础组件', style: Journal.section),
        const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('霞鹜文楷 · LXGW WenKai Screen'),
            subtitle: Text('手写风离线字体 · SIL OFL 1.1；原文见完整声明')),
        const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Flutter 与第三方组件'),
            subtitle: Text('界面、网络访问、安全存储及通知等能力')),
        OutlinedButton(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const LicensePage(
                        applicationName: '学习通课业手记',
                        applicationVersion: AppVersion.name))),
            child: const Text('完整依赖与原始许可')),
      ]));
  Widget _license(
          BuildContext context, String name, String purpose, String asset) =>
      ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(name),
          subtitle: Text(purpose),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                      appBar: AppBar(
                          leading: IconButton(
                              tooltip: '返回',
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () =>
                                  Navigator.of(context).maybePop()),
                          title: Text(name)),
                      body: FutureBuilder<String>(
                          future: rootBundle.loadString(asset),
                          builder: (context, s) => s.hasData
                              ? SingleChildScrollView(
                                  padding: const EdgeInsets.all(20),
                                  child: SelectableText(s.data!))
                              : const Center(
                                  child: CircularProgressIndicator()))))));
}

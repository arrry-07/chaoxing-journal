import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/assignment_store.dart';

class CourseListScreen extends StatelessWidget {
  const CourseListScreen({super.key, required this.store});
  final AssignmentStore store;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('我的课程')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            const Text('关注课程影响首页、日历、提醒、小组件和统计；所有记录仍可在本地记录查看。'),
            const SizedBox(height: 12),
            if (store.isLoading) ...[
              const LinearProgressIndicator(semanticsLabel: '正在处理学习数据'),
              const SizedBox(height: 8),
              const Text('正在处理学习数据，请稍候。'),
              const SizedBox(height: 12),
            ],
            // Store 提示也可能来自其他操作，不将其误称为课程加载失败。
            if (store.error case final message?) ...[
              Text('当前提示：$message'),
              const SizedBox(height: 8),
            ],
            if (store.courses.isEmpty && !store.isLoading)
              const Text('尚未读取课程，请同步后重试。'),
            if (!store.isLoading &&
                (store.courses.isEmpty || store.error != null))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.push('/sync'),
                  icon: const Icon(Icons.sync),
                  label: const Text('查看同步状态'),
                ),
              ),
            for (final c in store.courses)
              SwitchListTile(
                  title: Text(c.name),
                  subtitle: Text('班级 ${c.clazzId}'),
                  value: store.follows(c.key),
                  onChanged: (v) => store.followCourse(c.key, v))
          ])));
}

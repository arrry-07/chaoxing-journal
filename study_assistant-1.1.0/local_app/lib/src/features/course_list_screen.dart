import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/journal.dart';
import '../services/assignment_store.dart';

class CourseListScreen extends StatelessWidget {
  const CourseListScreen({super.key, required this.store});
  final AssignmentStore store;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) => Scaffold(
          backgroundColor: Journal.of(context).paper,
          appBar: AppBar(
            backgroundColor: Journal.of(context).paper,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              const JournalHeading(
                '我的课程',
                eyebrow: 'CAMPUS JOURNAL   /   COURSES',
              ),
              const SizedBox(height: 8),
              Text(
                '关注课程影响首页、日历、提醒、小组件和统计；所有记录仍可在本地记录查看。',
                style: Journal.of(context).metadata,
              ),
              const SizedBox(height: 14),
              if (store.isLoading) ...[
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(semanticsLabel: '正在处理学习数据'),
                        SizedBox(height: 8),
                        Text('正在处理学习数据，请稍候。',
                            style: Journal.of(context).metadata),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Store 提示也可能来自其他操作，不将其误称为课程加载失败。
              if (store.error case final message?) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      '当前提示：$message',
                      style: Journal.of(context)
                          .metadata
                          .copyWith(color: Journal.of(context).berry),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (store.courses.isEmpty && !store.isLoading)
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      '尚未读取课程，请同步后重试。',
                      style: Journal.of(context).metadata,
                    ),
                  ),
                ),
              if (!store.isLoading &&
                  (store.courses.isEmpty || store.error != null))
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => context.push('/sync'),
                      icon: const Icon(Icons.sync),
                      label: const Text('查看同步状态'),
                    ),
                  ),
                ),
              if (store.courses.isNotEmpty)
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < store.courses.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            indent: 14,
                            endIndent: 14,
                            color: Journal.of(context).rule,
                          ),
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                          secondary: Icon(
                            Icons.menu_book_outlined,
                            color: Journal.of(context).ink,
                          ),
                          title: Text(
                            store.courses[i].name,
                            style: Journal.of(context)
                                .entryTitle
                                .copyWith(fontSize: 16),
                          ),
                          subtitle: Text(
                            '班级 ${store.courses[i].clazzId}',
                            style: Journal.of(context).metadata,
                          ),
                          value: store.follows(store.courses[i].key),
                          onChanged: (v) =>
                              store.followCourse(store.courses[i].key, v),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
}

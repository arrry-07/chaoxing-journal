import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/journal.dart';
import '../services/assignment_store.dart';
import 'widgets/journal_grouped_card.dart';

class CourseListScreen extends StatelessWidget {
  const CourseListScreen({super.key, required this.store});
  final AssignmentStore store;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final journal = Journal.of(context);
          final nameCounts = <String, int>{};
          for (final c in store.courses) {
            final trimmed = c.name.trim();
            nameCounts[trimmed] = (nameCounts[trimmed] ?? 0) + 1;
          }

          return Scaffold(
            backgroundColor: journal.paper,
            appBar: AppBar(
              backgroundColor: journal.paper,
              title: const Text('我的课程'),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: [
                Text(
                  '关注课程影响首页、日历、提醒、小组件和统计；所有记录仍可在本地记录查看。',
                  style: journal.metadata,
                ),
                const SizedBox(height: 14),
                if (store.isLoading) ...[
                  JournalGroupedCard(
                    padding: const EdgeInsets.all(14),
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const LinearProgressIndicator(
                            semanticsLabel: '正在处理学习数据',
                          ),
                          const SizedBox(height: 8),
                          Text('正在处理学习数据，请稍候。', style: journal.metadata),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (store.error case final message?) ...[
                  JournalGroupedCard(
                    backgroundColor: journal.berryBg,
                    padding: const EdgeInsets.all(14),
                    children: [
                      Text(
                        '当前提示：$message',
                        style: journal.metadata.copyWith(color: journal.berry),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (store.courses.isEmpty && !store.isLoading)
                  JournalGroupedCard(
                    padding: const EdgeInsets.all(18),
                    children: [
                      Text('尚未读取课程，请同步后重试。', style: journal.metadata),
                    ],
                  ),
                if (!store.isLoading &&
                    (store.courses.isEmpty || store.error != null))
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => context.push('/sync'),
                        icon: const Icon(Icons.sync_rounded),
                        label: const Text('查看同步状态'),
                      ),
                    ),
                  ),
                if (store.courses.isNotEmpty)
                  JournalGroupedCard(
                    dividerIndent: 52,
                    children: [
                      for (final course in store.courses)
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 2,
                          ),
                          secondary: CourseMark(course.name, size: 28),
                          title: Text(course.name, style: journal.entryTitle),
                          subtitle: (nameCounts[course.name.trim()] ?? 0) > 1 &&
                                  course.clazzId.isNotEmpty
                              ? Text(
                                  '班级 ${course.clazzId}',
                                  style: journal.metadata,
                                )
                              : null,
                          value: store.follows(course.key),
                          onChanged: (v) => store.followCourse(course.key, v),
                        ),
                    ],
                  ),
              ],
            ),
          );
        },
      );
}

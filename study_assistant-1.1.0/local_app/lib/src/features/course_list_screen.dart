import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/journal.dart';
import '../models/course.dart';
import '../services/assignment_store.dart';
import 'widgets/journal_grouped_card.dart';

class CourseListScreen extends StatefulWidget {
  const CourseListScreen({super.key, required this.store});
  final AssignmentStore store;

  @override
  State<CourseListScreen> createState() => _CourseListScreenState();
}

class _CourseListScreenState extends State<CourseListScreen> {
  final _searchController = TextEditingController();
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(CourseRef course, String q) {
    if (q.isEmpty) return true;
    if (course.name.toLowerCase().contains(q)) return true;
    if (course.clazzId.toLowerCase().contains(q)) return true;
    if (course.teacherNames.any((t) => t.toLowerCase().contains(q))) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final store = widget.store;
          final journal = Journal.of(context);
          final nameCounts = <String, int>{};
          for (final c in store.courses) {
            final trimmed = c.name.trim();
            nameCounts[trimmed] = (nameCounts[trimmed] ?? 0) + 1;
          }
          final q = _query.trim().toLowerCase();
          final filtered = _searching
              ? store.courses
                  .where((c) => _matches(c, q))
                  .toList(growable: false)
              : store.courses;

          return Scaffold(
            backgroundColor: journal.paper,
            appBar: AppBar(
              backgroundColor: journal.paper,
              title: const Text('我的课程'),
              actions: [
                if (store.courses.isNotEmpty)
                  IconButton(
                    key: const ValueKey('course-list-search-toggle'),
                    tooltip: _searching ? '关闭搜索' : '搜索课程或教师',
                    icon: Icon(
                      _searching ? Icons.close_rounded : Icons.search_rounded,
                    ),
                    onPressed: () {
                      setState(() {
                        _searching = !_searching;
                        if (!_searching) {
                          _searchController.clear();
                          _query = '';
                        }
                      });
                    },
                  ),
              ],
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
                if (store.courses.isNotEmpty) ...[
                  if (_searching) ...[
                    TextField(
                      key: const ValueKey('course-list-search'),
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                      style: journal.entryTitle.copyWith(fontSize: 14.5),
                      decoration: InputDecoration(
                        hintText: '搜索课程或教师...',
                        hintStyle: journal.metadata,
                        filled: true,
                        fillColor: journal.parchment,
                        isDense: true,
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 19,
                          color: journal.muted,
                        ),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                tooltip: '清空',
                                icon: Icon(Icons.close_rounded,
                                    size: 17, color: journal.muted),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              BorderSide(color: journal.accent, width: 1.1),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (filtered.isEmpty)
                    JournalGroupedCard(
                      padding: const EdgeInsets.all(18),
                      children: [
                        Text('没有匹配的课程或教师，请调整关键词后重试。', style: journal.metadata),
                      ],
                    )
                  else
                    JournalGroupedCard(
                      dividerIndent: 52,
                      children: [
                        for (final course in filtered)
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 2,
                            ),
                            secondary: CourseMark(course.name, size: 28),
                            title: Text(course.name, style: journal.entryTitle),
                            subtitle: _buildCourseSubtitle(
                              course: course,
                              duplicateName:
                                  (nameCounts[course.name.trim()] ?? 0) > 1,
                              journal: journal,
                            ),
                            value: store.follows(course.key),
                            onChanged: store.isLoading
                                ? null
                                : (v) => store.followCourse(course.key, v),
                          ),
                      ],
                    ),
                ],
              ],
            ),
          );
        },
      );

  Widget? _buildCourseSubtitle({
    required CourseRef course,
    required bool duplicateName,
    required JournalPalette journal,
  }) {
    final parts = <String>[
      if (duplicateName && course.clazzId.isNotEmpty) '班级 ${course.clazzId}',
      if (course.teacherNames.isNotEmpty) course.teacherLabel,
    ];
    if (parts.isEmpty) return null;
    return Text(
      parts.join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: journal.metadata,
    );
  }
}

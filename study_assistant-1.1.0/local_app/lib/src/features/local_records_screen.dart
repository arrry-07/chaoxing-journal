import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/assignment.dart';
import '../services/assignment_grouping.dart';
import '../services/assignment_store.dart';

class LocalRecordsScreen extends StatefulWidget {
  const LocalRecordsScreen({super.key, required this.store});
  final AssignmentStore store;
  @override
  State<LocalRecordsScreen> createState() => _LocalRecordsScreenState();
}

class _LocalRecordsScreenState extends State<LocalRecordsScreen> {
  int category = 0;
  String search = '';
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final groups = category == 2
            ? widget.store.hiddenCourseworkGroups
            : category == 0
                ? widget.store.localCourseTaskGroups
                : const <CourseworkGroup>[];
        final records = category == 1
            ? widget.store.assignments
                .where((a) => !a.hasCourseTaskIdentity)
                .where((a) => '${a.title} ${a.courseName}'.contains(search))
                .toList()
            : groups
                .where((group) =>
                    '${group.primary.title} ${group.primary.courseName}'
                        .contains(search))
                .toList();
        return Scaffold(
            appBar: AppBar(title: const Text('本地记录')),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              TextField(
                  onChanged: (v) => setState(() => search = v),
                  decoration: const InputDecoration(
                      labelText: '搜索标题或课程', prefixIcon: Icon(Icons.search))),
              Wrap(spacing: 8, children: [
                for (var i = 0; i < 3; i++)
                  ChoiceChip(
                      label: Text(['作业与任务', '历史与其他来源', '已隐藏'][i]),
                      selected: category == i,
                      onSelected: (_) => setState(() => category = i))
              ]),
              Text('${records.length} 条记录'),
              if (category == 1)
                for (final a in records.cast<Assignment>())
                  Card(
                      child: ListTile(
                          title: Text(a.title),
                          subtitle: Text(
                              '${a.courseName}\n来源：${a.source.name}\n最后读取：${DateFormat('yyyy-MM-dd HH:mm').format(a.lastSyncedAt)}'),
                          onTap: () => context.push(
                              '/assignments/${Uri.encodeComponent(a.id)}')))
              else
                for (final group in records.cast<CourseworkGroup>())
                  Card(
                      child: ListTile(
                          title: Text(group.primary.title),
                          subtitle: Text(
                              '${group.primary.courseName}\n来源：${group.sourceLabel}\n最后读取：${DateFormat('yyyy-MM-dd HH:mm').format(group.primary.lastSyncedAt)}'),
                          onTap: category == 2
                              ? null
                              : () => context.push(
                                  '/assignments/${Uri.encodeComponent(group.primary.id)}'),
                          trailing: category == 2
                              ? TextButton(
                                  onPressed: () => widget.store
                                      .setCourseworkGroupHidden(group, false),
                                  child: const Text('恢复'))
                              : null))
            ]));
      });
}

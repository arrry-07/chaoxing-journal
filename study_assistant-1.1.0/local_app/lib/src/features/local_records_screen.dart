import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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
        final records = (category == 2
                ? widget.store.hiddenAssignments
                : widget.store.assignments
                    .where((a) => category == 0 ? a.isFormal : !a.isFormal))
            .where((a) => '${a.title} ${a.courseName}'.contains(search))
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
                      label: Text(['正式作业', '历史与其他来源', '已隐藏'][i]),
                      selected: category == i,
                      onSelected: (_) => setState(() => category = i))
              ]),
              Text('${records.length} 条记录'),
              for (final a in records)
                Card(
                    child: ListTile(
                        title: Text(a.title),
                        subtitle: Text(
                            '${a.courseName}\n来源：${a.source.name}\n最后读取：${DateFormat('yyyy-MM-dd HH:mm').format(a.lastSyncedAt)}'),
                        onTap: category == 2
                            ? null
                            : () => context.push(
                                '/assignments/${Uri.encodeComponent(a.id)}'),
                        trailing: category == 2
                            ? TextButton(
                                onPressed: () =>
                                    widget.store.updateCompletion(a.id, false),
                                child: const Text('恢复'))
                            : null))
            ]));
      });
}

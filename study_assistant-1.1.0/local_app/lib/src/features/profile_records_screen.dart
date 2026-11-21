import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/journal.dart';
import '../services/assignment_store.dart';
import 'widgets/journal_grouped_card.dart';

class ProfileRecordsScreen extends StatelessWidget {
  const ProfileRecordsScreen({super.key, required this.store});

  final AssignmentStore store;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Scaffold(
      backgroundColor: journal.paper,
      appBar: AppBar(
        backgroundColor: journal.paper,
        title: const Text('学习记录'),
      ),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            JournalGroupedCard(
              dividerIndent: 52,
              children: [
                JournalGroupTile(
                  icon: Icons.inventory_2_outlined,
                  title: '学期归档',
                  subtitle: '保存与回看本机学期快照',
                  onTap: () => context.push('/terms'),
                ),
                JournalGroupTile(
                  icon: Icons.storage_outlined,
                  title: '本地记录',
                  subtitle: '${store.localRecordGroups.length} 项课业记录保存在本机',
                  onTap: () => context.push('/records'),
                ),
                JournalGroupTile(
                  icon: Icons.visibility_off_outlined,
                  title: '已隐藏作业',
                  subtitle: '${store.hiddenCourseworkGroups.length} 项，可恢复到作业清单',
                  onTap: () => context.push('/records?status=hidden'),
                ),
                JournalGroupTile(
                  icon: Icons.history_rounded,
                  title: '作业变化',
                  subtitle: '${store.changes.length} 条最近变化',
                  onTap: () => context.push('/changes'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/journal.dart';
import '../services/assignment_store.dart';
import 'widgets/journal_grouped_card.dart';

class ProfileArrangementsScreen extends StatelessWidget {
  const ProfileArrangementsScreen({super.key, required this.store});

  final AssignmentStore store;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Scaffold(
      backgroundColor: journal.paper,
      appBar: AppBar(
        backgroundColor: journal.paper,
        title: const Text('个人安排'),
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
                  icon: Icons.event_note_rounded,
                  title: '个人待办与考试',
                  subtitle: '手动安排，独立于学习通作业',
                  onTap: () => context.push('/agenda'),
                ),
                JournalGroupTile(
                  icon: Icons.checklist_rounded,
                  title: '每日计划',
                  subtitle: '个人安排与预计耗时，不改变提交状态',
                  onTap: () => context.push('/plan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

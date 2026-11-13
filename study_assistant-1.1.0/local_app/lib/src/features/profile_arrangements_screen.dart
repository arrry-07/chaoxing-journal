import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/assignment_store.dart';
import 'widgets/profile_menu.dart';

class ProfileArrangementsScreen extends StatelessWidget {
  const ProfileArrangementsScreen({super.key, required this.store});

  final AssignmentStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('个人安排')),
        body: AnimatedBuilder(
          animation: store,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(18),
            children: [
              ProfileMenuCard(
                title: '个人安排',
                children: [
                  ProfileMenuTile(
                    icon: Icons.event_note_outlined,
                    title: '个人待办与考试',
                    subtitle: '手动安排，独立于学习通作业',
                    onTap: () => context.push('/agenda'),
                  ),
                  ProfileMenuTile(
                    icon: Icons.checklist,
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

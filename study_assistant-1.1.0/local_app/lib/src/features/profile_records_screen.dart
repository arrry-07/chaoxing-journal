import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/assignment_store.dart';
import 'widgets/profile_menu.dart';

class ProfileRecordsScreen extends StatelessWidget {
  const ProfileRecordsScreen({super.key, required this.store});

  final AssignmentStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('学习记录')),
        body: AnimatedBuilder(
          animation: store,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(18),
            children: [
              ProfileMenuCard(
                title: '本机与历史',
                children: [
                  ProfileMenuTile(
                    icon: Icons.inventory_2_outlined,
                    title: '学期归档',
                    subtitle: '保存与回看本机学期快照',
                    onTap: () => context.push('/terms'),
                  ),
                  ProfileMenuTile(
                    icon: Icons.storage_outlined,
                    title: '本地记录',
                    subtitle: '${store.assignments.length} 条作业记录保存在本机',
                    onTap: () => context.push('/records'),
                  ),
                  ProfileMenuTile(
                    icon: Icons.visibility_off_outlined,
                    title: '已隐藏作业',
                    subtitle: '${store.hiddenAssignments.length} 条，可恢复到作业清单',
                    onTap: () => _showHiddenAssignments(context),
                  ),
                  ProfileMenuTile(
                    icon: Icons.history,
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

  void _showHiddenAssignments(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: AnimatedBuilder(
          animation: store,
          builder: (context, _) => Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('已隐藏作业'),
              ),
              if (store.error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(store.error!),
                ),
              Expanded(
                child: store.hiddenAssignments.isEmpty
                    ? const Center(child: Text('暂无隐藏作业'))
                    : ListView.builder(
                        itemCount: store.hiddenAssignments.length,
                        itemBuilder: (context, index) {
                          final item = store.hiddenAssignments[index];
                          return ListTile(
                            title: Text(item.title),
                            subtitle: Text(item.courseName),
                            trailing: TextButton(
                              onPressed: store.isLoading
                                  ? null
                                  : () =>
                                      store.updateCompletion(item.id, false),
                              child: const Text('恢复'),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

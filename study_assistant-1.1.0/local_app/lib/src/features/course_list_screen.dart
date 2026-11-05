import 'package:flutter/material.dart';
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
            if (store.courses.isEmpty) const Text('尚未读取课程，请同步后重试。'),
            for (final c in store.courses)
              SwitchListTile(
                  title: Text(c.name),
                  subtitle: Text('班级 ${c.clazzId}'),
                  value: store.follows(c.key),
                  onChanged: (v) => store.followCourse(c.key, v))
          ])));
}

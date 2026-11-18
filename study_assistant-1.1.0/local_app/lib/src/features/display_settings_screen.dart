import 'package:flutter/material.dart';

import '../app/journal.dart';
import '../models/display_preferences.dart';
import '../services/assignment_store.dart';

class DisplaySettingsScreen extends StatefulWidget {
  const DisplaySettingsScreen({super.key, required this.store});
  final AssignmentStore store;
  @override
  State<DisplaySettingsScreen> createState() => _DisplaySettingsScreenState();
}

class _DisplaySettingsScreenState extends State<DisplaySettingsScreen> {
  bool saving = false;

  Future<void> save(DisplayPreferences next) async {
    setState(() => saving = true);
    try {
      await widget.store.saveDisplay(next);
      if (mounted && widget.store.error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(widget.store.error!)));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final d = widget.store.display;
          return Scaffold(
            backgroundColor: Journal.paper,
            appBar: AppBar(
              backgroundColor: Journal.paper,
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                const JournalHeading(
                  '显示与小组件',
                  eyebrow: 'CAMPUS JOURNAL   /   DISPLAY',
                ),
                const SizedBox(height: 8),
                const Text('调整课业时间轴密度与桌面小组件展示范围。', style: Journal.metadata),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('首页显示', style: Journal.entryTitle),
                        const SizedBox(height: 4),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('紧凑密度'),
                          subtitle: const Text(
                            '缩小作业间距，保留文字与操作大小',
                            style: Journal.metadata,
                          ),
                          value: d.compact,
                          onChanged: saving
                              ? null
                              : (v) => save(DisplayPreferences(
                                  compact: v,
                                  countdown: d.countdown,
                                  widgetRange: d.widgetRange)),
                        ),
                        const Divider(height: 1, color: Journal.rule),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('显示倒计时'),
                          subtitle: const Text(
                            '关闭时按日期显示；待确认截止仍保留提示',
                            style: Journal.metadata,
                          ),
                          value: d.countdown,
                          onChanged: saving
                              ? null
                              : (v) => save(DisplayPreferences(
                                  compact: d.compact,
                                  countdown: v,
                                  widgetRange: d.widgetRange)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('桌面小组件', style: Journal.entryTitle),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<WidgetRange>(
                          key: ValueKey('${d.widgetRange.name}-$saving'),
                          initialValue: d.widgetRange,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: '桌面小组件范围',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: WidgetRange.all,
                              child: Text('全部未完成'),
                            ),
                            DropdownMenuItem(
                              value: WidgetRange.today,
                              child: Text('今天剩余'),
                            ),
                            DropdownMenuItem(
                              value: WidgetRange.week,
                              child: Text('未来7天（含今天）'),
                            ),
                          ],
                          onChanged: saving
                              ? null
                              : (v) {
                                  if (v != null) {
                                    save(DisplayPreferences(
                                      compact: d.compact,
                                      countdown: d.countdown,
                                      widgetRange: v,
                                    ));
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '桌面小组件会按网格高度自动显示前 2、4 或 6 条已关注课程的未完成课业，并在标题栏显示当前范围总数，不跟随首页课程筛选。今天与未来7天仅包含可信且尚未截止或开考的项目；全部范围保留待确认与逾期项目。时间按北京时间，范围会在保存设置、同步或后台检查后自动更新。',
                          style: Journal.metadata,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '显示偏好保存在此设备，不改变同步、提醒或课程关注。',
                  style: Journal.metadata,
                ),
              ],
            ),
          );
        },
      );
}

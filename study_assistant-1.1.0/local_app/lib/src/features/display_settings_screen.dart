import 'package:flutter/material.dart';
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
            appBar: AppBar(title: const Text('显示与小组件')),
            body: ListView(padding: const EdgeInsets.all(20), children: [
              const Text('首页显示'),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('紧凑密度'),
                  subtitle: const Text('缩小作业间距，保留文字与操作大小'),
                  value: d.compact,
                  onChanged: saving
                      ? null
                      : (v) => save(DisplayPreferences(
                          compact: v,
                          countdown: d.countdown,
                          widgetRange: d.widgetRange))),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('显示倒计时'),
                  subtitle: const Text('关闭时按日期显示；待确认截止仍保留提示'),
                  value: d.countdown,
                  onChanged: saving
                      ? null
                      : (v) => save(DisplayPreferences(
                          compact: d.compact,
                          countdown: v,
                          widgetRange: d.widgetRange))),
              const Divider(height: 32),
              DropdownButtonFormField<WidgetRange>(
                  key: ValueKey('${d.widgetRange.name}-$saving'),
                  initialValue: d.widgetRange,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '桌面小组件范围'),
                  items: const [
                    DropdownMenuItem(
                        value: WidgetRange.all, child: Text('全部未完成')),
                    DropdownMenuItem(
                        value: WidgetRange.today, child: Text('今天剩余')),
                    DropdownMenuItem(
                        value: WidgetRange.week, child: Text('未来7天（含今天）'))
                  ],
                  onChanged: saving
                      ? null
                      : (v) {
                          if (v != null) {
                            save(DisplayPreferences(
                                compact: d.compact,
                                countdown: d.countdown,
                                widgetRange: v));
                          }
                        }),
              const SizedBox(height: 16),
              const Text(
                  '当前桌面小组件显示前2条已关注课程的未完成作业，不跟随首页课程筛选。今天与未来7天仅包含可信且尚未截止的作业；全部范围保留待确认和逾期项目。时间按北京时间；范围在保存设置或同步时更新。'),
              const SizedBox(height: 16),
              const Text('显示偏好保存在此设备，不改变同步、提醒或课程关注。'),
            ]));
      });
}

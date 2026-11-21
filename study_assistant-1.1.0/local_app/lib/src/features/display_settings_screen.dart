import 'package:flutter/material.dart';

import '../app/journal.dart';
import '../models/display_preferences.dart';
import '../services/assignment_store.dart';
import '../services/interaction_feedback_service.dart';

class DisplaySettingsScreen extends StatefulWidget {
  const DisplaySettingsScreen({super.key, required this.store});
  final AssignmentStore store;
  @override
  State<DisplaySettingsScreen> createState() => _DisplaySettingsScreenState();
}

class _DisplaySettingsScreenState extends State<DisplaySettingsScreen> {
  bool saving = false;

  Future<void> save(
    DisplayPreferences next, {
    bool previewSound = false,
    bool previewHaptics = false,
  }) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await widget.store.saveDisplay(next);
      if (!mounted) return;
      if ((previewSound || previewHaptics) &&
          identical(widget.store.display, next)) {
        InteractionFeedback.trigger(next.copyWith(
          soundEnabled: previewSound,
          hapticsEnabled: previewHaptics,
        ));
      }
      if (widget.store.error != null) {
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
          final journal = Journal.of(context);
          final d = widget.store.display;
          return Scaffold(
            backgroundColor: journal.paper,
            appBar: AppBar(
              backgroundColor: journal.paper,
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                const JournalHeading(
                  '显示与小组件',
                  eyebrow: 'CAMPUS JOURNAL   /   DISPLAY',
                ),
                const SizedBox(height: 8),
                Text('调整课业时间轴密度与桌面小组件展示范围。', style: journal.metadata),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('外观主题', style: journal.entryTitle),
                        const SizedBox(height: 12),
                        SegmentedButton<JournalThemeMode>(
                          key: const ValueKey('display-theme-mode-selector'),
                          direction: JournalLayout.isLargeText(context)
                              ? Axis.vertical
                              : Axis.horizontal,
                          expandedInsets: EdgeInsets.zero,
                          showSelectedIcon: false,
                          segments: [
                            for (final mode in JournalThemeMode.values)
                              ButtonSegment(
                                  value: mode, label: Text(mode.label)),
                          ],
                          selected: {d.themeMode},
                          onSelectionChanged: saving
                              ? null
                              : (modes) =>
                                  save(d.copyWith(themeMode: modes.single)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('首页显示', style: journal.entryTitle),
                        const SizedBox(height: 4),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('紧凑密度'),
                          subtitle: Text(
                            '缩小作业间距，保留文字与操作大小',
                            style: journal.metadata,
                          ),
                          value: d.compact,
                          onChanged: saving
                              ? null
                              : (v) => save(d.copyWith(compact: v)),
                        ),
                        Divider(height: 1, color: journal.rule),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('显示倒计时'),
                          subtitle: Text(
                            '关闭时按日期显示；待确认截止仍保留提示',
                            style: journal.metadata,
                          ),
                          value: d.countdown,
                          onChanged: saving
                              ? null
                              : (v) => save(d.copyWith(countdown: v)),
                        ),
                        Divider(height: 1, color: journal.rule),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          enableFeedback: false,
                          title: const Text('交互音效'),
                          subtitle: Text(
                            '点击、置顶、同步和计划完成时播放轻提示音，静音或振动模式下自动停用',
                            style: journal.metadata,
                          ),
                          value: d.soundEnabled,
                          onChanged: saving
                              ? null
                              : (v) => save(d.copyWith(soundEnabled: v),
                                  previewSound: v),
                        ),
                        Divider(height: 1, color: journal.rule),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          enableFeedback: false,
                          title: const Text('触感反馈'),
                          subtitle:
                              Text('关键操作时提供轻微振动', style: journal.metadata),
                          value: d.hapticsEnabled,
                          onChanged: saving
                              ? null
                              : (v) => save(d.copyWith(hapticsEnabled: v),
                                  previewHaptics: v),
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
                        Text('桌面小组件', style: journal.entryTitle),
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
                                    save(d.copyWith(widgetRange: v));
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '桌面小组件会按网格高度自动显示前 2、4 或 6 条已关注课程的未完成课业，并在标题栏显示当前范围总数，不跟随首页课程筛选。今天与未来7天仅包含可信且尚未截止或开考的项目；全部范围保留待确认与逾期项目。时间按北京时间，范围会在保存设置、同步或后台检查后自动更新。',
                          style: journal.metadata,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '显示偏好保存在此设备，不改变同步、提醒或课程关注。',
                  style: journal.metadata,
                ),
              ],
            ),
          );
        },
      );
}

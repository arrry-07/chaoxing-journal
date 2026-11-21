import 'package:flutter/material.dart';

import '../app/journal.dart';
import '../models/display_preferences.dart';
import '../services/assignment_store.dart';
import 'widgets/appearance_controls.dart';
import 'widgets/journal_grouped_card.dart';
import 'widgets/journal_picker_sheet.dart';

class DisplaySettingsScreen extends StatelessWidget {
  const DisplaySettingsScreen({super.key, required this.store});
  final AssignmentStore store;

  String _rangeLabel(WidgetRange range) => switch (range) {
        WidgetRange.all => '全部未完成',
        WidgetRange.today => '今天剩余',
        WidgetRange.week => '未来7天（含今天）',
      };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final journal = Journal.of(context);
          final d = store.display;
          return Scaffold(
            backgroundColor: journal.paper,
            appBar: AppBar(
              backgroundColor: journal.paper,
              title: const Text('显示与小组件'),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                JournalGroupedCard(
                  title: '首页显示',
                  dividerIndent: 16,
                  children: [
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 2),
                      title: Text('紧凑密度', style: journal.entryTitle),
                      subtitle: Text(
                        '缩小作业间距，保留文字与操作大小',
                        style: journal.metadata,
                      ),
                      value: d.compact,
                      onChanged: (v) => saveDisplaySetting(
                        context,
                        store,
                        store.display.copyWith(compact: v),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 2),
                      title: Text('显示倒计时', style: journal.entryTitle),
                      subtitle: Text(
                        '关闭时按日期显示；待确认截止仍保留提示',
                        style: journal.metadata,
                      ),
                      value: d.countdown,
                      onChanged: (v) => saveDisplaySetting(
                        context,
                        store,
                        store.display.copyWith(countdown: v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                JournalGroupedCard(
                  title: '桌面小组件',
                  infoTitle: '桌面小组件规则说明',
                  infoItems: const [
                    '桌面小组件按网格高度自动展示前 2、4 或 6 条已关注课程的未完成课业，不跟随首页课程筛选。',
                    '“今天剩余”与“未来7天”仅包含时间可信且尚未截止或开考的项目；“全部未完成”保留待确认与逾期项。',
                    '时间均以北京时间为准，在保存设置、同步或后台检查后自动更新。',
                  ],
                  children: [
                    JournalGroupTile(
                      key: ValueKey('widget-range-${d.widgetRange.name}'),
                      icon: Icons.widgets_outlined,
                      title: '桌面小组件范围',
                      trailingText: _rangeLabel(d.widgetRange),
                      onTap: () async {
                        final picked =
                            await showJournalPickerSheet<WidgetRange>(
                          context,
                          title: '桌面小组件范围',
                          selectedValue: d.widgetRange,
                          searchable: false,
                          displayPrefs: d,
                          options: const [
                            JournalPickerOption(
                              value: WidgetRange.all,
                              label: '全部未完成',
                              subtitle: '保留待确认与已逾期项目',
                            ),
                            JournalPickerOption(
                              value: WidgetRange.today,
                              label: '今天剩余',
                              subtitle: '仅含今天内未截止或未开考的可信项目',
                            ),
                            JournalPickerOption(
                              value: WidgetRange.week,
                              label: '未来7天（含今天）',
                              subtitle: '仅含 7 天内可信且尚未截止的项目',
                            ),
                          ],
                        );
                        if (picked != null && context.mounted) {
                          await saveDisplaySetting(
                            context,
                            store,
                            store.display.copyWith(widgetRange: picked),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
}

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
                        '单行标题并收紧卡片与分组间距，一屏展示更多课业',
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
                const SizedBox(height: 8),
                _DensityPreview(compact: d.compact),
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

class _DensityPreview extends StatelessWidget {
  const _DensityPreview({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final titleStyle = journal.entryTitle.copyWith(
      fontSize: compact ? 14.5 : 15.5,
      height: compact ? 1.25 : 1.38,
    );
    final metaStyle = journal.metadata.copyWith(
      fontSize: compact ? 11 : 12,
      height: compact ? 1.3 : 1.4,
    );

    Widget previewRow(String clock, String title) => Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 3 : 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                clock,
                style: metaStyle.copyWith(
                  color: journal.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                    SizedBox(height: compact ? 1 : 3),
                    Text(
                      compact ? '今天 23:59' : '今天 23:59 · 课程作业',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: metaStyle,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

    return Semantics(
      container: true,
      liveRegion: true,
      label: compact ? '紧凑密度示意：单行标题，间距更紧' : '标准密度示意：标题最多两行',
      child: Container(
        key: const ValueKey('compact-density-preview'),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Color.lerp(journal.sheet, journal.parchment, 0.28),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: journal.cardBorder, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '密度示意',
                    style: journal.metadata.copyWith(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  compact ? '紧凑' : '标准',
                  style: journal.metadata.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: compact ? journal.accent : journal.muted,
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 3 : 6),
            previewRow('09:00', '高等数学 · 第三章习题与课堂笔记'),
            previewRow('14:30', '大学物理 · 实验报告'),
          ],
        ),
      ),
    );
  }
}

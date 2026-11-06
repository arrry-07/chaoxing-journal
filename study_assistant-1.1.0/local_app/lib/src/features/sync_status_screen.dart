import 'package:flutter/material.dart';
import '../models/sync_report.dart';
import 'package:go_router/go_router.dart';
import '../app/journal.dart';
import 'package:intl/intl.dart';

import '../services/assignment_store.dart';

class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({super.key, required this.store});

  final AssignmentStore store;

  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  final _customSyncController = TextEditingController();
  final _customSyncFocus = FocusNode();

  AssignmentStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _customSyncController.text = store.autoSyncIntervalMinutes == 0
        ? ''
        : store.autoSyncIntervalMinutes.toString();
  }

  @override
  void dispose() {
    _customSyncController.dispose();
    _customSyncFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final lastSyncAt = store.lastSyncAt;
        final stale = lastSyncAt == null ||
            DateTime.now().difference(lastSyncAt).inHours >= 24;
        final selectedInterval =
            _isPresetInterval(store.autoSyncIntervalMinutes)
                ? store.autoSyncIntervalMinutes
                : -1;
        return Scaffold(
            appBar: AppBar(
                leading: IconButton(
                    tooltip: '返回我的',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go('/profile'))),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const JournalHeading(
                  '作业数据同步',
                  eyebrow: 'CAMPUS JOURNAL   /   SYNC',
                ),
                const SizedBox(height: 8),
                Text(
                  '账号凭证保存在本机安全存储中。登录和同步时，应用直接连接学习通。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '刷新时会用已保存的账号信息获取学习通作业，并重新安排提醒。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: Icon(
                      stale ? Icons.warning_amber : Icons.check_circle_outline,
                    ),
                    title: Text(store.syncSummary),
                    subtitle: Text(
                      lastSyncAt == null
                          ? '尚无完整同步记录'
                          : '最近完整同步：${DateFormat('M月d日 HH:mm', 'zh_CN').format(lastSyncAt)}',
                    ),
                  ),
                ),
                if (store.chaoxingClient.requestTimings.isNotEmpty)
                  ExpansionTile(
                      title: const Text('本机临时请求采样'),
                      subtitle: const Text(
                          '完整读取或会话重置时清空，单课读取追加；累计请求处理耗时包含本地解析，不代表纯网络或整体同步耗时'),
                      children: [
                        for (final e
                            in store.chaoxingClient.requestTimings.entries)
                          ListTile(
                              title: Text(e.key),
                              subtitle: Text(
                                  '${e.value.count}次 · 累计${e.value.elapsedMs}毫秒 · 网络/HTTP失败${e.value.httpFailures}次')),
                      ]),
                if (store.syncReport.attemptedAt != null)
                  Text(
                      '最后尝试：${DateFormat('M月d日 HH:mm').format(store.syncReport.attemptedAt!)}'),
                if (store.syncReport.lastDataSuccessAt != null)
                  Text(
                      '最近数据成功：${DateFormat('M月d日 HH:mm').format(store.syncReport.lastDataSuccessAt!)}'),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.update,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '自动同步',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'App 运行或重新打开时会按间隔同步作业和截止时间，提醒会跟着新截止时间更新。',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '同步间隔设置过短会增加耗电量和网络请求次数，建议不要低于 15 分钟。',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _SyncIntervalOption(
                              key: const ValueKey('auto-sync-option-15'),
                              label: '15 分钟',
                              selected: selectedInterval == 15,
                              enabled: !store.isLoading,
                              onTap: () => _selectPresetInterval(15),
                            ),
                            _SyncIntervalOption(
                              key: const ValueKey('auto-sync-option-30'),
                              label: '30 分钟',
                              selected: selectedInterval == 30,
                              enabled: !store.isLoading,
                              onTap: () => _selectPresetInterval(30),
                            ),
                            _SyncIntervalOption(
                              key: const ValueKey('auto-sync-option-60'),
                              label: '1 小时',
                              selected: selectedInterval == 60,
                              enabled: !store.isLoading,
                              onTap: () => _selectPresetInterval(60),
                            ),
                            _SyncIntervalOption(
                              key: const ValueKey('auto-sync-option-custom'),
                              label: '自定义',
                              selected: selectedInterval == -1,
                              enabled: !store.isLoading,
                              onTap: () => _customSyncFocus.requestFocus(),
                            ),
                            _SyncIntervalOption(
                              key: const ValueKey('auto-sync-option-off'),
                              label: '关闭',
                              selected: selectedInterval == 0,
                              enabled: !store.isLoading,
                              onTap: () => _selectPresetInterval(0),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _customSyncController,
                                focusNode: _customSyncFocus,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  hintText: '自定义分钟数',
                                  prefixIcon: Icon(Icons.timer_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: store.isLoading
                                  ? null
                                  : _saveCustomSyncInterval,
                              child: const Text('保存'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: store.isLoading ? null : store.syncAssignments,
                  icon: const Icon(Icons.sync),
                  label: Text(store.isLoading ? '正在刷新...' : '刷新作业数据'),
                ),
                if (store.syncReport.issues.any((i) =>
                    i.kind == SyncIssueKind.verificationRequired ||
                    i.kind == SyncIssueKind.schemaChanged))
                  FilledButton.icon(
                      onPressed: store.isLoading
                          ? null
                          : () async {
                              try {
                                final continued = await store.chaoxingClient
                                    .verifyInBrowser();
                                if (continued) await store.syncAssignments();
                              } catch (_) {
                                if (context.mounted) {
                                  _showMessage('验证页面未能打开，请稍后重试');
                                }
                              }
                            },
                      icon: const Icon(Icons.verified_user_outlined),
                      label: const Text('完成安全验证')),
                if (store.syncReport.issues.isNotEmpty)
                  ExpansionTile(
                      title: Text('问题明细（${store.syncReport.issues.length}）'),
                      children: [
                        for (final issue in store.syncReport.issues)
                          ListTile(
                              title: Text(issue.message),
                              subtitle:
                                  Text('${issue.stage} · ${issue.kind.name}'))
                      ]),
                if (store.error != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(store.error!)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ));
      },
    );
  }

  Future<void> _saveCustomSyncInterval() async {
    final value = int.tryParse(_customSyncController.text.trim());
    if (value == null || value <= 0) {
      _showMessage('请输入大于 0 的分钟数');
      return;
    }
    final normalized = AssignmentStore.normalizeAutoSyncIntervalMinutes(value);
    await store.saveAutoSyncIntervalMinutes(normalized);
    if (!mounted) {
      return;
    }
    _customSyncController.text = normalized.toString();
    _showMessage('自动同步时间已保存');
  }

  Future<void> _selectPresetInterval(int minutes) async {
    if (store.isLoading) {
      return;
    }
    await store.saveAutoSyncIntervalMinutes(minutes);
    if (!mounted) {
      return;
    }
    _customSyncController.text = minutes == 0 ? '' : minutes.toString();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _isPresetInterval(int minutes) {
    return minutes == 0 || minutes == 15 || minutes == 30 || minutes == 60;
  }
}

class _SyncIntervalOption extends StatelessWidget {
  const _SyncIntervalOption({
    super.key,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground =
        selected ? colorScheme.onPrimaryContainer : colorScheme.onSurface;
    return Semantics(
      label: label,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      enabled: enabled,
      button: true,
      onTap: enabled ? onTap : null,
      excludeSemantics: true,
      child: SizedBox(
        width: 140,
        child: Material(
          color: selected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: selected ? colorScheme.primary : Journal.rule,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: selected
                        ? Icon(
                            Icons.check,
                            key: const ValueKey('selected'),
                            size: 18,
                            color: foreground,
                          )
                        : const SizedBox(
                            key: ValueKey('unselected'),
                            width: 18,
                            height: 18,
                          ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: foreground,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

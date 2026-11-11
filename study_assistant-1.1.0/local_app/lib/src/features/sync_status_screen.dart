import 'package:flutter/material.dart';
import '../models/sync_report.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../app/journal.dart';

import '../services/assignment_store.dart';

class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({super.key, required this.store});

  final AssignmentStore store;

  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  AssignmentStore get store => widget.store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final lastSyncAt = store.lastSyncAt;
        final stale = lastSyncAt == null ||
            DateTime.now().difference(lastSyncAt).inHours >= 24;
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
                              Icons.nightlight_round,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '白天后台检查',
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
                          store.backgroundCheckEnabled
                              ? '已开启，每 ${store.backgroundCheckIntervalMinutes ~/ 60} 小时在 08:00—次日 00:00 内检查。实际执行由系统调度，不承诺整点。'
                              : '已关闭；手动刷新、通知监听（如开启）和已有缓存截止提醒不受影响。',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (store.nextBackgroundCheckAt != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '下次目标：${DateFormat('M月d日 HH:mm').format(store.nextBackgroundCheckAt!)}',
                          ),
                        ],
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () => context.push('/reminders'),
                            icon: const Icon(Icons.tune),
                            label: const Text('调整后台检查与提醒'),
                          ),
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

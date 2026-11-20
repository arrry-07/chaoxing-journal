import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/sync_report.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../app/journal.dart';
import '../local/chaoxing_local_client.dart';

import '../services/assignment_store.dart';
import '../services/sync_issue_presentation.dart';

class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({
    super.key,
    required this.store,
    this.expandIssues = false,
  });

  final AssignmentStore store;
  final bool expandIssues;

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
        final issues = store.syncReport.issues;
        final needsVerification = issues
            .any((issue) => issue.kind == SyncIssueKind.verificationRequired);
        // Other read errors also use coursePage. The report preserves the
        // diagnostic text, with an optional course label prepended.
        final canInspectCoursePage = issues.any((issue) =>
            issue.kind == SyncIssueKind.schemaChanged &&
            issue.stage == 'coursePage' &&
            issue.message.endsWith('课程页未生成作业读取凭证，可在应用内检查访问'));
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
                if ((store.syncReport.failedCourses > 0 ||
                        store.syncReport.incompleteExamSourceCount > 0) &&
                    lastSyncAt != null &&
                    store.hadCacheBeforeLastSync)
                  Card(
                    key: const ValueKey('sync-cached-record-status'),
                    child: ListTile(
                      leading: const Icon(Icons.history_rounded),
                      title: const Text('当前保留上次完整同步记录'),
                      subtitle: Text(
                          '完整读取时间：${DateFormat('M月d日 HH:mm', 'zh_CN').format(lastSyncAt)}'),
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
                Builder(builder: (context) {
                  final phases =
                      store.chaoxingClient.diagnostics.phaseElapsedMs;
                  if (phases.isEmpty) return const SizedBox.shrink();
                  const labels = {
                    'courseList': '课程索引',
                    'formalWork': '正式作业',
                    'classroomTasks': '课堂任务',
                    'exams': '考试与通知',
                    'taskEnginePlan': '课程任务计划探测',
                  };
                  return ExpansionTile(
                    title: const Text('本机同步阶段采样'),
                    subtitle: const Text('仅本次客户端采集阶段，不含保存、提醒重排和界面耗时'),
                    children: [
                      for (final entry in phases.entries)
                        ListTile(
                          title: Text(labels[entry.key] ?? entry.key),
                          trailing: Text('${entry.value} 毫秒'),
                        ),
                    ],
                  );
                }),
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
                if (needsVerification || canInspectCoursePage)
                  FilledButton.icon(
                      onPressed: store.isLoading
                          ? null
                          : () async {
                              try {
                                final continued = await store.chaoxingClient
                                    .verifyInBrowser(
                                        courseInspection: !needsVerification);
                                if (continued) await store.syncAssignments();
                              } on VerificationTargetUnavailable {
                                if (context.mounted) {
                                  _showMessage(needsVerification
                                      ? '请先刷新作业数据，再完成安全验证'
                                      : '请先刷新作业数据，再检查访问');
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  _showMessage(needsVerification
                                      ? '验证页面未能打开，请稍后重试'
                                      : '检查访问页面未能打开，请稍后重试');
                                }
                              }
                            },
                      icon: const Icon(Icons.verified_user_outlined),
                      label: Text(needsVerification ? '完成安全验证' : '在应用内检查访问')),
                if (store.syncReport.sourceResults.isNotEmpty)
                  ExpansionTile(title: const Text('读取来源'), children: [
                    for (final source in store.syncReport.sourceResults)
                      ListTile(
                          title: Text(const {
                                'courseWork': '正式作业',
                                'classroomActivity:35': '个人与分组任务',
                                'classroomActivity:42': '随堂练习',
                                'classroomActivity:77': 'AI 实践',
                                'exam': '课程考试',
                                'examAccount': '账号考试',
                                'examNotice': '考试通知',
                                'courseNotice': '课程通知',
                                'taskEnginePlan': '课程任务计划探测',
                                'groupHistory': '课程群补充',
                              }[source.source] ??
                              '其他来源'),
                          subtitle: Text('${switch (source.phase) {
                            SyncSourcePhase.success => '读取完成',
                            SyncSourcePhase.partial => '部分信息待重试',
                            SyncSourcePhase.failed => '读取失败',
                            SyncSourcePhase.notEnabled => '尚未启用',
                          }} · ${source.recordCount} 条 · ${source.unconfirmedCount} 条待确认'
                              '${source.reasonCodes.isEmpty ? '' : '\n原因：${source.reasonCodes.map(_reasonLabel).join('、')}'}')),
                  ]),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final report = store.exportSanitizedSyncDiagnostics();
                    await Clipboard.setData(ClipboardData(text: report));
                    if (context.mounted) {
                      _showMessage('已复制脱敏诊断摘要（不含账号与课程隐私）');
                    }
                  },
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('复制脱敏同步诊断摘要'),
                ),
                if (store.syncReport.issues.isNotEmpty) ...[
                  Builder(builder: (context) {
                    final groups = groupSyncIssues(store.syncReport.issues);
                    final names = {
                      for (final course in store.chaoxingClient.courses)
                        '${course.courseId}:${course.clazzId}':
                            course.courseName,
                      for (final course in store.courses)
                        course.key: course.name,
                      for (final assignment in store.courseAssignments)
                        if (assignment.courseKey case final key?)
                          key: assignment.courseName,
                    };
                    String courseLabel(SyncIssue issue) {
                      final key = issue.courseKey;
                      if (key == null) return '来源级问题';
                      return names[key] ?? '课程信息待刷新';
                    }

                    return ExpansionTile(
                        key: const ValueKey('sync-issue-groups'),
                        initiallyExpanded: widget.expandIssues,
                        title: Text(
                            '问题明细（${groups.length} 组，共 ${store.syncReport.issues.length} 条）'),
                        children: [
                          for (var groupIndex = 0;
                              groupIndex < groups.length;
                              groupIndex++)
                            Builder(builder: (context) {
                              final group = groups[groupIndex];
                              final courses = group.issues
                                  .map(courseLabel)
                                  .toSet()
                                  .toList();
                              final courseSummary = courses.length > 3
                                  ? '${courses.take(3).join('、')} 等 ${courses.length} 项'
                                  : courses.join('、');
                              return ExpansionTile(
                                  key: ValueKey('sync-issue-group-$groupIndex'),
                                  title: Text(group.message),
                                  subtitle: Text(
                                      '${syncIssueStageLabel(group.stage)} · '
                                      '${syncIssueKindLabel(group.kind)} · '
                                      '${group.count} 条\n涉及：$courseSummary'),
                                  children: [
                                    ListTile(
                                      title: Text(
                                          '下一步：${syncIssueNextAction(group.kind)}'),
                                    ),
                                    ExpansionTile(
                                      key: ValueKey(
                                          'sync-issue-raw-$groupIndex'),
                                      title: Text(
                                          '查看原始条目（${group.issues.length}）'),
                                      children: [
                                        for (final issue in group.issues)
                                          ListTile(
                                            title: Text(
                                                '${courseLabel(issue)} · '
                                                '${syncIssueKindLabel(issue.kind)}'),
                                            subtitle: Text(
                                                '${syncIssueStageLabel(issue.stage)} · '
                                                '${issue.kind.name}'
                                                '${issue.httpStatus == null ? '' : ' · HTTP ${issue.httpStatus}'}'
                                                '${issue.elapsedMs == null ? '' : ' · ${issue.elapsedMs}ms'}'),
                                          ),
                                      ],
                                    ),
                                  ]);
                            }),
                        ]);
                  }),
                  const SizedBox(height: 12),
                ],
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

  String _reasonLabel(String code) => switch (code) {
        'examPcSupplementUnavailable' => '部分课程 PC 考试补充时间未取得，已保留手机端记录',
        'accountExamRowSkippedNoId' => '部分历史账号考试缺少唯一标识已跳过',
        'examAccountTimeConflict' => '账号考试与课程考试时间不一致，已保留课程时间',
        'unfinishedPlanDetected' => '存在待核对课程补充任务计划',
        'listOrMetadataUnavailable' => '列表或元数据暂不可用',
        'identityConflict' => '存在重复关联待核对',
        _ => code,
      };

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

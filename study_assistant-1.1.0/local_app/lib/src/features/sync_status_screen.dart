import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../app/journal.dart';
import '../app/transient_feedback.dart';
import '../local/chaoxing_local_client.dart';
import '../models/sync_report.dart';
import '../services/assignment_store.dart';
import '../services/interaction_feedback_service.dart';
import '../services/sync_issue_presentation.dart';
import 'widgets/journal_buttons.dart';
import 'widgets/journal_expansion_tile.dart';
import 'widgets/journal_grouped_card.dart';

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
  bool _savingBackground = false;

  Future<void> _saveBackgroundCheckEnabled(bool value) async {
    if (_savingBackground || store.isLoading) return;
    setState(() => _savingBackground = true);
    final ok = await store.saveBackgroundCheckEnabled(value);
    if (!mounted) return;
    setState(() => _savingBackground = false);
    if (!ok) {
      showJournalMessage(
        context,
        store.operationError ?? '保存后台检查设置失败，请稍后重试',
      );
      return;
    }
    showJournalMessage(context, value ? '已开启白天后台检查' : '已关闭白天后台检查');
  }

  Future<void> _saveBackgroundInterval(int minutes) async {
    if (_savingBackground ||
        store.isLoading ||
        !store.backgroundCheckEnabled ||
        store.backgroundCheckIntervalMinutes == minutes) {
      return;
    }
    setState(() => _savingBackground = true);
    final ok = await store.saveBackgroundCheckIntervalMinutes(minutes);
    if (!mounted) return;
    setState(() => _savingBackground = false);
    if (!ok) {
      showJournalMessage(
        context,
        store.operationError ?? '保存检查频率失败，请稍后重试',
      );
      return;
    }
    showJournalMessage(context, '已调整为每 ${minutes ~/ 60} 小时检查一次');
  }

  Future<void> _runSync() async {
    final before = store.syncReport;
    final epoch = store.accountEpoch;
    await store.syncAssignments();
    if (!mounted) return;
    InteractionFeedback.triggerSyncDoneIfReady(
      prefs: store.display,
      before: before,
      after: store.syncReport,
      beforeEpoch: epoch,
      afterEpoch: store.accountEpoch,
      operationError: store.operationError,
    );
  }

  Future<void> _runAllTermsSync() async {
    final before = store.syncReport;
    final epoch = store.accountEpoch;
    await store.syncAllTerms();
    if (!mounted) return;
    InteractionFeedback.triggerSyncDoneIfReady(
      prefs: store.display,
      before: before,
      after: store.syncReport,
      beforeEpoch: epoch,
      afterEpoch: store.accountEpoch,
      operationError: store.operationError,
    );
  }

  Future<void> _runVerificationRetry() async {
    final before = store.syncReport;
    final epoch = store.accountEpoch;
    await store.retryLastSyncAfterVerification();
    if (!mounted) return;
    InteractionFeedback.triggerSyncDoneIfReady(
      prefs: store.display,
      before: before,
      after: store.syncReport,
      beforeEpoch: epoch,
      afterEpoch: store.accountEpoch,
      operationError: store.operationError,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final journal = Journal.of(context);
        final lastSyncAt = store.lastSyncAt;
        final currentSyncAt = store.syncReport.lastCurrentSuccessAt;
        final effectiveSyncAt = currentSyncAt ?? lastSyncAt;
        final stale = effectiveSyncAt == null ||
            DateTime.now().difference(effectiveSyncAt).inHours >= 24;
        final issues = store.syncReport.issues;
        final needsVerification = issues
            .any((issue) => issue.kind == SyncIssueKind.verificationRequired);
        final canInspectCoursePage = issues.any((issue) =>
            issue.kind == SyncIssueKind.schemaChanged &&
            issue.stage == 'coursePage' &&
            issue.message.endsWith('课程页未生成作业读取凭证，可在应用内检查访问'));

        return Scaffold(
          backgroundColor: journal.paper,
          appBar: AppBar(
            backgroundColor: journal.paper,
            leading: IconButton(
              tooltip: '返回我的',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/profile'),
            ),
            title: const Text('作业数据同步'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: [
              Text(
                '账号凭据保存在本机安全存储中，同步时直连超星学习通并更新提醒。',
                style: journal.metadata,
              ),
              const SizedBox(height: 12),
              JournalGroupedCard(
                dividerIndent: 52,
                children: [
                  ListTile(
                    leading: Icon(
                      stale
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline_rounded,
                      color: stale ? journal.berry : journal.ink,
                    ),
                    title: Text(store.syncSummary, style: journal.entryTitle),
                    subtitle: Text(
                      [
                        lastSyncAt == null
                            ? '尚无完整同步记录'
                            : '最近完整同步：${DateFormat('M月d日 HH:mm', 'zh_CN').format(lastSyncAt.toLocal())}',
                        if (currentSyncAt != null &&
                            currentSyncAt != lastSyncAt)
                          '最近本学期同步：${DateFormat('M月d日 HH:mm', 'zh_CN').format(currentSyncAt.toLocal())}',
                        if (store.syncReport.plannedCourses > 0 ||
                            store.syncReport.skippedCourses > 0)
                          '本次范围：${store.syncReport.syncScope.label} · '
                              '已扫描 ${store.syncReport.plannedCourses} 门'
                              '${store.syncReport.skippedCourses > 0 ? '，跳过往期/归档 ${store.syncReport.skippedCourses} 门' : ''}',
                        if (store.syncReport.attemptedAt != null)
                          '最后尝试：${DateFormat('M月d日 HH:mm').format(store.syncReport.attemptedAt!.toLocal())}',
                        if (store.syncReport.lastDataSuccessAt != null)
                          '最近数据成功：${DateFormat('M月d日 HH:mm').format(store.syncReport.lastDataSuccessAt!.toLocal())}',
                      ].join('\n'),
                      style: journal.metadata,
                    ),
                  ),
                  if ((store.syncReport.failedCourses > 0 ||
                          store.syncReport.incompleteExamSourceCount > 0) &&
                      lastSyncAt != null &&
                      store.hadCacheBeforeLastSync)
                    ListTile(
                      key: const ValueKey('sync-cached-record-status'),
                      leading: const Icon(Icons.history_rounded),
                      title: Text('当前保留上次完整同步记录', style: journal.entryTitle),
                      subtitle: Text(
                        '完整读取时间：${DateFormat('M月d日 HH:mm', 'zh_CN').format(lastSyncAt.toLocal())}',
                        style: journal.metadata,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              JournalGroupedCard(
                padding: const EdgeInsets.all(14),
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        key: const ValueKey('sync-background-check-switch'),
                        contentPadding: EdgeInsets.zero,
                        title: Text('白天后台检查', style: journal.section),
                        subtitle: Text(
                          '08:00 至次日 00:00 低频检查，实际执行由系统调度',
                          style: journal.metadata,
                        ),
                        value: store.backgroundCheckEnabled,
                        onChanged: store.isLoading || _savingBackground
                            ? null
                            : _saveBackgroundCheckEnabled,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final minutes in const [120, 240, 360])
                            ChoiceChip(
                              key:
                                  ValueKey('sync-background-interval-$minutes'),
                              label: Text('每 ${minutes ~/ 60} 小时'),
                              selected: store.backgroundCheckIntervalMinutes ==
                                  minutes,
                              onSelected: store.isLoading ||
                                      _savingBackground ||
                                      !store.backgroundCheckEnabled
                                  ? null
                                  : (_) => _saveBackgroundInterval(minutes),
                            ),
                        ],
                      ),
                      if (store.nextBackgroundCheckAt != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '下次目标：${DateFormat('M月d日 HH:mm').format(store.nextBackgroundCheckAt!.toLocal())}',
                          style: journal.metadata.copyWith(color: journal.ink),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: JournalSecondaryButton(
                          expanded: false,
                          height: 40,
                          icon: Icons.tune_rounded,
                          label: '通知触发与提醒设置',
                          onPressed: () => context.push('/reminders'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              JournalPrimaryButton(
                icon: Icons.sync_rounded,
                label: store.isLoading ? '正在刷新...' : '刷新作业数据',
                loading: store.isLoading,
                onPressed: store.isLoading ? null : _runSync,
              ),
              const SizedBox(height: 10),
              JournalSecondaryButton(
                key: const ValueKey('sync-all-terms-button'),
                icon: Icons.manage_search_rounded,
                label: '全量扫描全部学期',
                onPressed: store.isLoading ? null : _runAllTermsSync,
              ),
              if (needsVerification || canInspectCoursePage) ...[
                const SizedBox(height: 10),
                JournalPrimaryButton(
                  icon: Icons.verified_user_outlined,
                  label: needsVerification ? '完成安全验证' : '在应用内检查访问',
                  onPressed: store.isLoading
                      ? null
                      : () async {
                          try {
                            final continued = await store.chaoxingClient
                                .verifyInBrowser(
                                    courseInspection: !needsVerification);
                            if (continued) await _runVerificationRetry();
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
                ),
              ],
              const SizedBox(height: 10),
              JournalSecondaryButton(
                icon: Icons.copy_all_outlined,
                label: '复制脱敏同步诊断摘要',
                onPressed: () async {
                  final report = store.exportSanitizedSyncDiagnostics();
                  await Clipboard.setData(ClipboardData(text: report));
                  if (context.mounted) {
                    _showMessage('已复制脱敏诊断摘要（不含账号与课程隐私）');
                  }
                },
              ),
              if (store.chaoxingClient.requestTimings.isNotEmpty ||
                  store.chaoxingClient.diagnostics.phaseElapsedMs.isNotEmpty ||
                  store.syncReport.sourceResults.isNotEmpty ||
                  store.syncReport.issues.isNotEmpty) ...[
                const SizedBox(height: 14),
                JournalGroupedCard(
                  dividerIndent: 16,
                  children: [
                    if (store.syncReport.sourceResults.isNotEmpty)
                      JournalExpansionTile(
                        title: Text('读取来源', style: journal.entryTitle),
                        children: [
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
                                  '${source.reasonCodes.isEmpty ? '' : '\n原因：${source.reasonCodes.map(_reasonLabel).join('、')}'}'),
                            ),
                        ],
                      ),
                    if (store.syncReport.issues.isNotEmpty)
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

                        return JournalExpansionTile(
                          key: const ValueKey('sync-issue-groups'),
                          initiallyExpanded: widget.expandIssues,
                          title: Text(
                            '问题明细（${groups.length} 组，共 ${store.syncReport.issues.length} 条）',
                            style: journal.entryTitle,
                          ),
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
                                return JournalExpansionTile(
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
                                    JournalExpansionTile(
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
                                  ],
                                );
                              }),
                          ],
                        );
                      }),
                    if (store.chaoxingClient.requestTimings.isNotEmpty)
                      JournalExpansionTile(
                        title: Text('本机临时请求采样', style: journal.entryTitle),
                        subtitle: Text(
                          '完整读取或会话重置时清空，累计耗时包含本地解析',
                          style: journal.metadata,
                        ),
                        children: [
                          for (final e
                              in store.chaoxingClient.requestTimings.entries)
                            ListTile(
                              title: Text(e.key),
                              subtitle: Text(
                                  '${e.value.count}次 · 累计${e.value.elapsedMs}毫秒 · 网络/HTTP失败${e.value.httpFailures}次'),
                            ),
                        ],
                      ),
                    if (store
                        .chaoxingClient.diagnostics.phaseElapsedMs.isNotEmpty)
                      JournalExpansionTile(
                        title: Text('本机同步阶段采样', style: journal.entryTitle),
                        subtitle:
                            Text('仅客户端采集阶段，不含保存与提醒重排', style: journal.metadata),
                        children: [
                          for (final entry in store.chaoxingClient.diagnostics
                              .phaseElapsedMs.entries)
                            ListTile(
                              title: Text(const {
                                    'courseList': '课程索引',
                                    'formalWork': '正式作业',
                                    'classroomTasks': '课堂任务',
                                    'exams': '考试与通知',
                                    'taskEnginePlan': '课程任务计划探测',
                                  }[entry.key] ??
                                  entry.key),
                              trailing: Text('${entry.value} 毫秒'),
                            ),
                        ],
                      ),
                  ],
                ),
              ],
              if (store.error != null) ...[
                const SizedBox(height: 12),
                JournalGroupedCard(
                  backgroundColor: journal.berryBg,
                  padding: const EdgeInsets.all(14),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 20,
                          color: journal.berry,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            store.error!,
                            style:
                                journal.metadata.copyWith(color: journal.berry),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _reasonLabel(String code) => switch (code) {
        'examPhoneListFailed' => '手机考试列表未完整读取',
        'examCourseEntryFailed' => '考试补查所需的课程入口未读取',
        'examPcListFailed' => 'PC 考试列表未完整读取',
        'examCircuitPaused' => '考试请求连续失败，本轮已暂停该类请求',
        'verificationPaused' => '学习通要求人工验证，已暂停读取',
        'examPcSupplementUnavailable' => '部分课程 PC 考试补充时间未取得，已保留手机端记录',
        'accountExamRowSkippedNoId' => '部分历史账号考试缺少唯一标识已跳过',
        'examAccountTimeConflict' => '账号考试与课程考试时间不一致，已保留课程时间',
        'unfinishedPlanDetected' => '存在待核对课程补充任务计划',
        'listOrMetadataUnavailable' => '列表或元数据暂不可用',
        'identityConflict' => '存在重复关联待核对',
        _ => code,
      };

  void _showMessage(String message) {
    showJournalMessage(context, message);
  }
}

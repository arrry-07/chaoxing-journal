import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../app/journal.dart';
import '../app/journal_motion.dart';
import '../models/reminder_history.dart';
import '../services/assignment_store.dart';
import 'widgets/journal_grouped_card.dart';

const reminderCategoryLabels = <String, String>{
  'newAssignment': '新增课业',
  'deadline': '截止提醒',
  'examStart': '考试开考',
  'personal': '个人日程',
  'summary': '每日摘要',
  'backgroundCheck': '后台检查',
};

const reminderStageLabels = <String, String>{
  'scheduled': '已安排',
  'deferred': '已延后',
  'submitted': '提交后系统可见检查通过',
  'cancelled': '已撤销',
  'blocked': '受阻',
  'scheduleFailed': '安排失败',
  'cancelFailed': '撤销失败',
  'recoveryPending': '等待恢复',
  'unconfirmed': '结果未确认',
};

const reminderReasonLabels = <String, String>{
  'completed': '已提交、已结束或已完成',
  'hidden': '已隐藏',
  'unfollowed': '课程未关注',
  'outOfScope': '不在当前课业范围',
  'statusUnknown': '提交状态未确认',
  'examNoticeOnly': '仅为考试通知',
  'examUnavailable': '考试信息不完整',
  'deadlineUnknown': '截止或开考时间未确认',
  'deadlineReadFailed': '截止时间读取失败',
  'noDeadline': '确认没有截止时间',
  'anchorPassed': '截止或开考时间已过',
  'offsetWindowPassed': '提前提醒时间已过',
  'reminderDisabled': '提醒已关闭',
  'baselinePending': '新增提醒基线尚未建立',
  'alreadyKnown': '已纳入已有课业',
  'alreadySubmitted': '新增提醒已提交',
  'newReminderDisabled': '新增提醒已关闭',
  'outsideWindow': '当前不在白天提醒窗口',
  'cooldown': '提醒冷却中',
  'notificationPermissionOff': '系统通知权限已关闭',
  'channelOff': '通知渠道已关闭',
  'permissionUnknown': '系统通知权限未知',
  'channelUnknown': '通知渠道状态未知',
  'recoveryPending': '提醒恢复尚未完成',
  'scheduleUnconfirmed': '排期证据未确认',
  'queryFailed': '查询失败',
  'inexactFallback': '使用系统允许的近似时间',
  'removed': '事项已从本机删除',
  'snapshotPending': '提醒快照正在恢复',
  'legacyMigrationPending': '旧提醒迁移未完成',
  'invalid': '事项已失效',
  'staleSession': '旧账号或旧会话',
  'deadlinePassed': '截止或开考时间已过',
  'accountChanged': '账号已变化',
  'privacyCleanup': '隐私清理',
  'scheduleBatchFailed': '提醒批次安排失败',
  'backgroundCheckFailed': '后台检查未成功',
  'notificationChannelMissing': '通知渠道尚未创建',
  'notificationUnknown': '系统通知状态未知',
  'notificationNotVisible': '系统未接受或未展示通知',
  'notificationFailure': '通知提交失败',
  'scheduleReplaced': '提醒时间已调整',
};

class ReminderHistoryScreen extends StatefulWidget {
  const ReminderHistoryScreen({super.key, required this.store});

  final AssignmentStore store;

  @override
  State<ReminderHistoryScreen> createState() => _ReminderHistoryScreenState();
}

class _ReminderHistoryScreenState extends State<ReminderHistoryScreen> {
  List<ReminderHistoryItem> _items = [];
  String? _category;
  int? _snapshotMaxId;
  int? _nextBeforeId;
  DateTime? _checkedAt;
  String? _error;
  bool _loading = false;
  bool _loadedOnce = false;
  int _requestToken = 0;
  String? _accountHash;
  int _accountEpoch = 0;
  int _nativeEpoch = 0;
  int _historyGeneration = 0;

  (String?, int, int, int) _currentIdentity() => (
        widget.store.accountHash,
        widget.store.accountEpoch,
        widget.store.nativeSessionEpoch,
        widget.store.reminderHistoryGeneration,
      );

  @override
  void initState() {
    super.initState();
    final id = _currentIdentity();
    _accountHash = id.$1;
    _accountEpoch = id.$2;
    _nativeEpoch = id.$3;
    _historyGeneration = id.$4;
    widget.store.addListener(_handleStoreChanged);
    _load(reset: true);
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStoreChanged);
    super.dispose();
  }

  void _handleStoreChanged() {
    final next = _currentIdentity();
    if (next ==
        (_accountHash, _accountEpoch, _nativeEpoch, _historyGeneration)) {
      return;
    }
    _accountHash = next.$1;
    _accountEpoch = next.$2;
    _nativeEpoch = next.$3;
    _historyGeneration = next.$4;
    if (!mounted) return;
    setState(() {
      _items = [];
      _snapshotMaxId = null;
      _nextBeforeId = null;
      _checkedAt = null;
      _error = null;
      _loadedOnce = false;
    });
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (!reset && _loading) return;
    final token = ++_requestToken;
    final startIdentity = _currentIdentity();
    setState(() {
      _loading = true;
      if (reset) _error = null;
    });
    try {
      final page = await widget.store.loadReminderHistory(
        snapshotMaxId: reset ? null : _snapshotMaxId,
        beforeId: reset ? null : _nextBeforeId,
        category: _category,
      );
      if (!mounted ||
          token != _requestToken ||
          startIdentity != _currentIdentity()) {
        return;
      }
      final merged = reset ? <ReminderHistoryItem>[] : [..._items];
      for (final item in page.items) {
        final previous = merged.isEmpty ? null : merged.last;
        final oldScheduled = previous?.scheduledAt;
        final newScheduled = item.scheduledAt;
        final sameSchedule = oldScheduled == null
            ? newScheduled == null
            : newScheduled != null &&
                oldScheduled.isAtSameMomentAs(newScheduled);
        final same = previous != null &&
            previous.logicalKey == item.logicalKey &&
            previous.category == item.category &&
            previous.stage == item.stage &&
            previous.reasonCode == item.reasonCode &&
            sameSchedule;
        if (!same) merged.add(item);
      }
      setState(() {
        _items = merged;
        _snapshotMaxId = page.snapshotMaxId;
        _nextBeforeId = page.nextBeforeId;
        _checkedAt = page.checkedAt;
        _loadedOnce = true;
        _error = null;
      });
    } on ReminderHistoryException catch (error) {
      if (!mounted ||
          token != _requestToken ||
          startIdentity != _currentIdentity()) {
        return;
      }
      final stale = error.code == 'stale_session' ||
          error.code == 'stale_history_generation';
      setState(() {
        _error = switch (error.code) {
          'stale_session' => '账号或会话已变化，请返回后重新打开记录',
          'stale_history_generation' => '提醒记录已因退出登录清理，请刷新',
          'history_unavailable' => '提醒记录当前不可用或仍在清理',
          _ => error.message,
        };
        if (stale) {
          _items = [];
          _snapshotMaxId = null;
          _nextBeforeId = null;
          _checkedAt = null;
        }
        _loadedOnce = true;
      });
    } catch (error) {
      if (!mounted ||
          token != _requestToken ||
          startIdentity != _currentIdentity()) {
        return;
      }
      setState(() {
        _error = '提醒记录读取失败：$error';
        _loadedOnce = true;
      });
    } finally {
      if (mounted && token == _requestToken) {
        setState(() => _loading = false);
      }
    }
  }

  void _selectCategory(String? value) {
    if (_category == value) return;
    setState(() {
      _category = value;
      _items = [];
      _snapshotMaxId = null;
      _nextBeforeId = null;
    });
    _load(reset: true);
  }

  String _subjectTitle(ReminderHistoryItem item) {
    final id = item.subjectId;
    if (id == null) {
      return item.subjectKind == 'account' ? '后台提醒检查' : '本机提醒';
    }
    final assignment = widget.store.courseworkGroupFor(id)?.primary;
    if (assignment != null) {
      return [
        if (assignment.courseName.trim().isNotEmpty)
          assignment.courseName.trim(),
        if (assignment.title.trim().isNotEmpty) assignment.title.trim(),
      ].join(' · ');
    }
    if (item.subjectKind == 'manual') {
      final entry =
          widget.store.notebook.entries.where((entry) => entry.id == id);
      if (entry.isNotEmpty) return entry.first.title;
      return '已删除的个人安排';
    }
    if (item.subjectKind == 'summary') return '每日课业摘要';
    return item.subjectKind == 'assignment' ? '已移除的课业' : '本机提醒';
  }

  String _line(ReminderHistoryItem item) {
    final stage = reminderStageLabels[item.stage] ?? '未知状态';
    final reason = item.reasonCode == null
        ? null
        : reminderReasonLabels[item.reasonCode] ?? '其他原因';
    final at = item.scheduledAt == null
        ? null
        : '目标 ${DateFormat('M月d日 HH:mm').format(item.scheduledAt!.toLocal())}';
    return [
      stage,
      if (at != null) at,
      if (reason != null) reason,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Scaffold(
      backgroundColor: journal.paper,
      appBar: AppBar(
        backgroundColor: journal.paper,
        title: const Text('提醒记录'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : () => _load(reset: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Row(
              children: [
                _HistoryCategoryPill(
                  label: '全部',
                  selected: _category == null,
                  onTap: () => _selectCategory(null),
                ),
                for (final entry in reminderCategoryLabels.entries) ...[
                  const SizedBox(width: 8),
                  _HistoryCategoryPill(
                    label: entry.value,
                    selected: _category == entry.key,
                    onTap: () => _selectCategory(entry.key),
                  ),
                ],
              ],
            ),
          ),
          if (_checkedAt != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '查询时间 ${DateFormat('yyyy-MM-dd HH:mm:ss').format(_checkedAt!.toLocal())}',
                  style: journal.metadata.copyWith(fontSize: 12),
                ),
              ),
            ),
          if (_error != null && _items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: JournalGroupedCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style:
                                journal.metadata.copyWith(color: journal.berry),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _loading ? null : () => _load(reset: true),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Expanded(
            child: !_loadedOnce || (_loading && _items.isEmpty)
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty && _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: JournalGroupedCard(
                            padding: const EdgeInsets.all(20),
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      _error!,
                                      textAlign: TextAlign.center,
                                      style: journal.metadata
                                          .copyWith(color: journal.berry),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton(
                                    onPressed: _loading
                                        ? null
                                        : () => _load(reset: true),
                                    child: const Text('重试'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                    : _items.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                '最近 30 天没有符合条件的提醒记录',
                                style: journal.metadata,
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () => _load(reset: true),
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                8,
                                16,
                                28,
                              ),
                              children: [
                                JournalGroupedCard(
                                  children: [
                                    for (final item in _items)
                                      _buildHistoryTile(context, journal, item),
                                  ],
                                ),
                                if (_nextBeforeId != null) ...[
                                  const SizedBox(height: 12),
                                  OutlinedButton(
                                    onPressed: _loading
                                        ? null
                                        : () => _load(reset: false),
                                    child: Text(_loading ? '正在加载…' : '加载更多'),
                                  ),
                                ],
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTile(
    BuildContext context,
    JournalPalette journal,
    ReminderHistoryItem item,
  ) {
    final canOpen = item.subjectKind != 'account' &&
        (item.subjectId != null || item.subjectKind == 'summary');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      title: Text(_subjectTitle(item), style: journal.entryTitle),
      subtitle: Text(
        '${DateFormat('yyyy-MM-dd HH:mm:ss').format(item.observedAt.toLocal())}\n${_line(item)}',
        style: journal.metadata,
      ),
      isThreeLine: true,
      trailing: canOpen
          ? Icon(Icons.chevron_right_rounded, size: 20, color: journal.muted)
          : null,
      onTap: canOpen
          ? () => context.push(
                '/reminder-status/${Uri.encodeComponent(item.subjectKind)}/'
                '${Uri.encodeComponent(item.subjectId ?? '0')}',
              )
          : null,
    );
  }
}

class _HistoryCategoryPill extends StatelessWidget {
  const _HistoryCategoryPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Material(
      color: selected ? journal.sage : journal.parchment,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? journal.sageBorder : Colors.transparent,
          width: 0.9,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AnimatedPadding(
          duration: JournalMotion.duration(
            context,
            const Duration(milliseconds: 140),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: journal.pillLabel.copyWith(
              color: selected
                  ? (journal.isDark ? journal.accent : journal.ink)
                  : journal.muted,
            ),
          ),
        ),
      ),
    );
  }
}

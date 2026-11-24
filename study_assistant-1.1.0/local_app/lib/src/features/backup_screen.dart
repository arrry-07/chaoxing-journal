import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/journal.dart';
import '../models/backup_snapshot.dart';
import '../services/assignment_store.dart';
import '../services/backup_service.dart';
import 'widgets/journal_buttons.dart';
import 'widgets/journal_grouped_card.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, required this.store, this.service});
  final AssignmentStore store;
  final BackupService? service;
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  BackupSnapshot? _preview;
  String? _previewAccount, _message;
  DateTime? _previewAt;
  bool _busy = false;
  int _accountEpoch = 0;
  String? _lastAccount;
  bool _lastAuthenticated = false;
  BackupService get _service => widget.service ?? BackupService();

  @override
  void initState() {
    super.initState();
    _lastAccount = widget.store.account;
    _lastAuthenticated = widget.store.isAuthenticated;
    widget.store.addListener(_storeChanged);
  }

  void _storeChanged() {
    if (_lastAccount == widget.store.account &&
        _lastAuthenticated == widget.store.isAuthenticated) {
      return;
    }
    _lastAccount = widget.store.account;
    _lastAuthenticated = widget.store.isAuthenticated;
    _accountEpoch++;
    if (mounted) {
      setState(() {
        _preview = null;
        _previewAt = null;
      });
    }
  }

  String _account() {
    final account = widget.store.account;
    if (!widget.store.isAuthenticated || account == null || account.isEmpty) {
      throw StateError('请先登录要备份或恢复的账号');
    }
    return account;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = switch (error) {
            PlatformException() => '备份操作未完成，请检查文件或口令后重试。',
            FormatException() => '备份文件损坏、超出上限或版本不受支持。',
            StateError() => error.message.toString(),
            ArgumentError() => error.message?.toString() ?? '请检查口令。',
            _ => '备份操作未完成，请重试。',
          };
        });
      }
    } finally {
      if (mounted) {
        _password.clear();
        _confirmation.clear();
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _export() => _run(() async {
        final account = _account();
        final epoch = _accountEpoch;
        final password = _password.text;
        if (password.trim().length < 8 || password != _confirmation.text) {
          throw ArgumentError('口令至少8个非首尾空白字符，并在确认栏输入相同口令');
        }
        final snapshot =
            await widget.store.repository.createBackupSnapshot(account);
        if (widget.store.recoveryWarning != null) {
          throw StateError('检测到本机数据恢复警告，当前数据不完整，已阻止导出。原始损坏数据仍保留在本机。');
        }
        final envelope = await _service.encrypt(snapshot, password);
        if (!mounted || _account() != account || _accountEpoch != epoch) {
          throw StateError('账号已变化，请重新导出');
        }
        final saved = await _service.save(envelope,
            suggestedName:
                '课业手记-${DateTime.now().toIso8601String().substring(0, 10)}.xxtbackup');
        if (mounted && saved) setState(() => _message = '加密备份已保存。请单独妥善保管口令。');
      });

  Future<void> _import() => _run(() async {
        final account = _account();
        final epoch = _accountEpoch;
        setState(() {
          _preview = null;
          _previewAt = null;
        });
        final password = _password.text;
        if (password.isEmpty) throw ArgumentError('请先填写此备份的口令');
        final envelope = await _service.pick();
        if (envelope == null) return;
        final snapshot = await _service.decrypt(envelope, password);
        if (!mounted) return;
        if (_account() != account ||
            _accountEpoch != epoch ||
            snapshot.owner != BackupSnapshot.ownerFor(account)) {
          throw StateError('此备份不属于当前账号，请切换到备份所属账号后重试');
        }
        await widget.store.repository.validateBackupOwner(snapshot, account);
        if (mounted && _accountEpoch == epoch) {
          setState(() {
            _preview = snapshot;
            _previewAccount = account;
            _previewAt = DateTime.now();
          });
        }
      });

  Future<void> _restore() => _run(() async {
        final snapshot = _preview;
        if (snapshot == null ||
            _account() != _previewAccount ||
            _previewAt == null ||
            DateTime.now().difference(_previewAt!) >
                const Duration(minutes: 10)) {
          setState(() => _preview = null);
          throw StateError('预览已失效，请重新选择备份文件');
        }
        final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                  title: const Text('确认恢复本机记录？'),
                  content: const Text('只补入本机缺少的记录；已有记录保留。新增课业需同步后再安排提醒。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('确认恢复'))
                  ],
                ));
        if (confirmed != true || !mounted) return;
        if (_account() != _previewAccount ||
            _previewAt == null ||
            DateTime.now().difference(_previewAt!) >
                const Duration(minutes: 10)) {
          throw StateError('预览已失效，请重新选择备份文件');
        }
        if (!await widget.store.restoreLocalBackup(snapshot)) {
          throw StateError('恢复未完成，请检查当前账号后重试');
        }
        if (mounted) {
          setState(() {
            _preview = null;
            _message = '本机记录已补入，请同步学习通以确认状态和截止时间。';
          });
        }
      });

  @override
  void dispose() {
    widget.store.removeListener(_storeChanged);
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Scaffold(
      backgroundColor: journal.paper,
      appBar: AppBar(
        backgroundColor: journal.paper,
        title: const Text('加密备份'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            JournalGroupedCard(
              title: '备份口令与操作',
              infoTitle: '加密备份包含范围',
              infoItems: const [
                '导出当前账号的作业、课程、计划、个人清单备注、待办/考试文字与日程（保持旧版本可读兼容）、学期快照、资料链接与提醒设置。',
                '不包含本地待办图片与文件附件、登录凭据、个人资料、作业访问签名、说明正文及本地文件授权关联。',
                '口令仅用于本次加解密，不会保存到设备；忘记口令无法找回。',
              ],
              padding: const EdgeInsets.all(16),
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '导出会保留待办文字与日程（兼容旧版本读取），不包含本地图片与文件附件。',
                      style: journal.metadata,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      enabled: !_busy,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: '备份口令',
                        helperText: '导出至少 8 个字符；口令只用于本次操作，不会保存。',
                        helperMaxLines: 2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _confirmation,
                      obscureText: true,
                      enabled: !_busy,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: '确认口令',
                        helperText: '仅导出时填写，须与上方口令相同。',
                        helperMaxLines: 2,
                      ),
                    ),
                    const SizedBox(height: 18),
                    JournalPrimaryButton(
                      icon: Icons.lock_outline_rounded,
                      label: '导出加密备份',
                      loading: _busy,
                      onPressed: _busy ? null : _export,
                    ),
                    const SizedBox(height: 10),
                    JournalSecondaryButton(
                      icon: Icons.folder_open_rounded,
                      label: '选择备份并预览',
                      onPressed: _busy ? null : _import,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '忘记口令无法恢复。请将备份文件与口令分开保管。',
                      style: journal.metadata.copyWith(color: journal.ink),
                    ),
                  ],
                ),
              ],
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: JournalGroupedCard(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Text(
                      _message!,
                      semanticsLabel: _message,
                      style: journal.entryTitle.copyWith(fontSize: 14.5),
                    ),
                  ],
                ),
              ),
            if (_preview case final snapshot?) ...[
              const SizedBox(height: 14),
              JournalGroupedCard(
                title: '恢复预览',
                padding: const EdgeInsets.all(16),
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '所属账号：$_previewAccount（已核对）\n'
                        '备份时间：${snapshot.createdAt.toLocal().toString().substring(0, 19)}\n'
                        '作业 ${snapshot.records.length} 条 · 隐藏 ${snapshot.hidden.length} 条 · 课程 ${snapshot.courses.length} 门',
                        style: journal.metadata.copyWith(color: journal.ink),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '提醒：${snapshot.reminderOffsets.map((m) => "$m 分钟前").join("、")}\n'
                        '个人备注 ${snapshot.personal.work.length} 份 · 计划 ${snapshot.personal.plans.length} 项 · 手动安排 ${snapshot.notebook.entries.length} 项 · 学期快照 ${snapshot.notebook.terms.length} 份',
                        style: journal.metadata,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '现有记录与自动同步设置保持不变；补入作业需同步后再安排提醒（预览 10 分钟后失效）。',
                        style: journal.metadata,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              JournalPrimaryButton(
                label: '恢复缺少的记录',
                onPressed: _busy ? null : _restore,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

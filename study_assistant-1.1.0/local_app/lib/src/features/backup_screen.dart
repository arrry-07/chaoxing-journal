import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/journal.dart';
import '../models/backup_snapshot.dart';
import '../services/assignment_store.dart';
import '../services/backup_service.dart';

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
        // Check the active local owner as well as the login displayed by the UI.
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
                  content: const Text(
                      '只补入本机缺少的作业和课程；已有记录保留。新增记录的提交状态和截止时间需重新同步确认。提醒和关注设置仅在本机未设置时补入。'),
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
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Journal.paper,
        appBar: AppBar(title: const Text('加密备份')),
        body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('给课业记录留一份副本', style: Journal.section),
          const SizedBox(height: 8),
          const Text(
              '备份当前账号的作业、课程、计划、个人清单备注、手动安排、学期快照与提醒设置。登录凭据、个人资料、作业访问签名、说明正文和本地文件关联不导出；手动添加的资料链接会随加密备份保存。',
              style: Journal.metadata),
          const SizedBox(height: 24),
          TextField(
              controller: _password,
              obscureText: true,
              enabled: !_busy,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                  labelText: '备份口令',
                  helperText: '导出至少8个字符；口令只用于本次操作，不会保存。',
                  helperMaxLines: 3)),
          const SizedBox(height: 16),
          TextField(
              controller: _confirmation,
              obscureText: true,
              enabled: !_busy,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                  labelText: '确认口令',
                  helperText: '仅导出时填写，须与上方口令相同。',
                  helperMaxLines: 3)),
          const SizedBox(height: 20),
          FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.lock_outline),
              label: const Text('导出加密备份')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.folder_open),
              label: const Text('选择备份并预览')),
          const SizedBox(height: 12),
          const Text('忘记口令无法恢复。请将备份文件与口令分开保管。', style: Journal.metadata),
          if (_busy)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator()),
          if (_message != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(_message!, semanticsLabel: _message)),
          if (_preview case final snapshot?) ...[
            const Divider(height: 40),
            const Text('恢复预览', style: Journal.section),
            const SizedBox(height: 8),
            Text(
                '所属账号：$_previewAccount（已与本机核对）\n备份日期：${snapshot.createdAt.toLocal().toString().substring(0, 19)}\n作业 ${snapshot.records.length} 条 · 隐藏 ${snapshot.hidden.length} 条\n课程 ${snapshot.courses.length} 门 · 不关注 ${snapshot.unfollowed.length} 门',
                style: Journal.metadata),
            const SizedBox(height: 12),
            Text(
                '提醒：${snapshot.reminderOffsets.map((m) => "$m 分钟前").join("、")}\n备份的自动同步间隔：${snapshot.autoSyncIntervalMinutes == 0 ? "关闭" : "${snapshot.autoSyncIntervalMinutes} 分钟"}。恢复保留本机自动同步设置。',
                style: Journal.metadata),
            const SizedBox(height: 12),
            Text(
                '个人备注 ${snapshot.personal.work.length} 份 · 计划 ${snapshot.personal.plans.length} 项。手动安排 ${snapshot.notebook.entries.length} 项 · 学期快照 ${snapshot.notebook.terms.length} 份。个人记录仅补缺，摘要设置保持本机当前值；文件关联不迁移。',
                style: Journal.metadata),
            const Text('现有记录保持不变。补入的作业需同步确认状态与截止时间，确认前不会安排提醒。预览10分钟后失效。',
                style: Journal.metadata),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: _busy ? null : _restore,
                child: const Text('恢复缺少的记录')),
          ],
        ])),
      );
}

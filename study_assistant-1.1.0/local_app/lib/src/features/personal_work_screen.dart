import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../app/unsaved_edit_guard.dart';
import '../models/personal_workspace.dart';
import '../services/assignment_store.dart';
import '../services/external_link_service.dart';
import '../services/personal_file_service.dart';

class PersonalWorkScreen extends StatefulWidget {
  const PersonalWorkScreen(
      {super.key, required this.store, required this.assignmentId});
  final AssignmentStore store;
  final String assignmentId;
  @override
  State<PersonalWorkScreen> createState() => _PersonalWorkState();
}

class _PersonalWorkState extends State<PersonalWorkScreen> {
  late final int epoch;
  late final TextEditingController note;
  late List<PersonalStep> steps;
  late List<PersonalLink> links, files;
  bool busy = false;
  bool _dirty = false;
  bool _saving = false;
  UnsavedEditGuard? _leaveGuard;
  String? message;
  @override
  void initState() {
    super.initState();
    epoch = widget.store.accountEpoch;
    final data =
        widget.store.personal.work[widget.assignmentId] ?? const PersonalWork();
    note = TextEditingController(text: data.note);
    note.addListener(_markDirty);
    steps = [...data.steps];
    links = [...data.links];
    files = [...data.files];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final guard = UnsavedEditGuardScope.maybeOf(context);
    if (identical(guard, _leaveGuard)) return;
    _leaveGuard?.unregister(this);
    _leaveGuard = guard;
    _leaveGuard?.register(
      this,
      hasUnsavedChanges: () => _dirty || _saving,
      confirmDiscard: _confirmDiscard,
      isStale: () =>
          !widget.store.isAuthenticated || widget.store.accountEpoch != epoch,
    );
  }

  Future<bool> _requestLeave() async {
    final guard = _leaveGuard;
    if (guard != null) return guard.confirmLeave();
    return _confirmDiscard();
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  Future<bool> _confirmDiscard() async {
    if (_saving) {
      setState(() => message = '个人记录正在保存，请稍候再离开');
      return false;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('放弃未保存的修改？'),
        content: const Text('备注、清单、链接或文件关联的修改尚未保存。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('继续编辑')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('放弃修改')),
        ],
      ),
    );
    return result == true;
  }

  @override
  void dispose() {
    _leaveGuard?.unregister(this);
    note.removeListener(_markDirty);
    note.dispose();
    super.dispose();
  }

  Future<List<String>?> input(String title, List<String> labels,
      {List<String>? initial}) async {
    final controllers = [
      for (var i = 0; i < labels.length; i++)
        TextEditingController(text: initial?[i])
    ];
    String? validationError;
    final result = await showDialog<List<String>>(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, setDialogState) => AlertDialog(
                    title: Text(title),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      for (var i = 0; i < labels.length; i++)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: TextField(
                                controller: controllers[i],
                                onChanged: (_) {
                                  if (validationError != null) {
                                    setDialogState(
                                        () => validationError = null);
                                  }
                                },
                                maxLength: i == 0 ? 200 : 4096,
                                decoration:
                                    InputDecoration(labelText: labels[i]))),
                      if (validationError != null)
                        Semantics(
                            liveRegion: true,
                            child: Text(validationError!,
                                style: TextStyle(
                                    color: Theme.of(c).colorScheme.error)))
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () {
                            final values =
                                controllers.map((v) => v.text.trim()).toList();
                            final missing = values.indexWhere((v) => v.isEmpty);
                            if (missing >= 0) {
                              setDialogState(() =>
                                  validationError = '请填写${labels[missing]}');
                              return;
                            }
                            if (values.length == 2 &&
                                !PersonalWorkspace.validUrl(values[1])) {
                              setDialogState(() =>
                                  validationError = '请输入不含账号信息的 HTTPS 链接');
                              return;
                            }
                            Navigator.pop(c, values);
                          },
                          child: const Text('添加'))
                    ])));
    // Controllers belong to dialog fields until their exit animation completes.
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      for (final c in controllers) {
        c.dispose();
      }
    });
    return result;
  }

  Future<void> save() async {
    if (busy) return;
    final editorRoute = ModalRoute.of(context);
    setState(() {
      busy = true;
      _saving = true;
      message = null;
    });
    final value = PersonalWork(
        note: note.text,
        steps: [...steps],
        links: [...links],
        files: [...files]);
    final saved = await widget.store
        .savePersonal((w) => w.withWork(widget.assignmentId, value), epoch);
    // Store notifications also refresh GoRouter. Let that refresh settle before
    // popping, otherwise its pending parse can restore the page just popped.
    if (saved) await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (saved) {
      _saving = false;
      _dirty = false;
      if (editorRoute?.isCurrent == false) {
        setState(() {
          busy = false;
          message = '个人记录已保存';
        });
        return;
      }
      // Shell routes use a nested navigator; let the router pop its own stack.
      final router = GoRouter.maybeOf(context);
      if (router != null && router.canPop()) {
        router.pop();
      } else if (router == null && Navigator.of(context).canPop()) {
        Navigator.pop(context);
      } else {
        setState(() {
          busy = false;
          message = '个人记录已保存';
        });
      }
      return;
    }
    setState(() {
      busy = false;
      _saving = false;
      message = '未能保存，输入仍保留。账号变化时请返回后重新编辑。';
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || (!_dirty && !_saving)) return;
        final leave = await _requestLeave();
        if (!leave || !context.mounted) return;
        final router = GoRouter.maybeOf(context);
        if (router != null && router.canPop()) {
          router.pop();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
          appBar: AppBar(title: const Text('个人清单与备注')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Text(
                widget.store.findAssignment(widget.assignmentId)?.title ??
                    '本机个人记录',
                style: Theme.of(context).textTheme.titleLarge),
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('这里的勾选只表示个人进度，不代表学习通已提交。更改后请保存。')),
            TextField(
                controller: note,
                maxLength: 10000,
                minLines: 3,
                maxLines: 8,
                enabled: !busy,
                decoration: const InputDecoration(labelText: '我的备注')),
            Text('个人清单 · ${steps.where((s) => s.done).length}/${steps.length}',
                style: Theme.of(context).textTheme.titleMedium),
            for (var i = 0; i < steps.length; i++)
              Row(children: [
                // An interactive secondary inside CheckboxListTile is merged into
                // its toggle semantics. Keep removal independently accessible.
                IconButton(
                    tooltip: '移除清单项：${steps[i].text}',
                    onPressed: busy
                        ? null
                        : () => setState(() {
                              steps.removeAt(i);
                              _dirty = true;
                            }),
                    icon: const Icon(Icons.close)),
                Expanded(
                    child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: steps[i].done,
                        onChanged: busy
                            ? null
                            : (v) => setState(() {
                                  steps[i] = PersonalStep(steps[i].text,
                                      done: v ?? false);
                                  _dirty = true;
                                }),
                        title: Text(steps[i].text))),
              ]),
            TextButton.icon(
                onPressed: busy || steps.length >= 50
                    ? null
                    : () async {
                        final v = await input('添加清单项', ['要做的事']);
                        if (mounted && v != null) {
                          setState(() {
                            steps.add(PersonalStep(v[0]));
                            _dirty = true;
                          });
                        }
                      },
                icon: const Icon(Icons.add),
                label: const Text('添加清单项')),
            const Divider(height: 24),
            Text('资料链接', style: Theme.of(context).textTheme.titleMedium),
            for (var i = 0; i < links.length; i++)
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(links[i].label),
                  subtitle: Text(links[i].url,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: busy
                      ? null
                      : () async {
                          final ok = await ExternalLinkService()
                              .openBrowser(links[i].url);
                          if (mounted && !ok) {
                            setState(() => message = '未能打开浏览器，请重试');
                          }
                        },
                  trailing: IconButton(
                      tooltip: '移除链接',
                      onPressed: busy
                          ? null
                          : () => setState(() {
                                links.removeAt(i);
                                _dirty = true;
                              }),
                      icon: const Icon(Icons.close))),
            TextButton.icon(
                onPressed: busy || links.length >= 20
                    ? null
                    : () async {
                        final v = await input('添加资料链接', ['名称', 'HTTPS 地址']);
                        if (mounted && v != null) {
                          setState(() {
                            links.add(PersonalLink(v[0], v[1]));
                            _dirty = true;
                          });
                        }
                      },
                icon: const Icon(Icons.link),
                label: const Text('添加资料链接')),
            const Divider(height: 24),
            Text('本地文件', style: Theme.of(context).textTheme.titleMedium),
            const Text('只关联本设备的文件授权，不复制或上传；加密备份不包含文件及其关联。文件移走或授权失效时请重新选择。'),
            for (var i = 0; i < files.length; i++)
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(files[i].label),
                  leading: const Icon(Icons.attach_file),
                  onTap: busy
                      ? null
                      : () async {
                          final ok =
                              await PersonalFileService().open(files[i].url);
                          if (mounted && !ok) {
                            setState(() => message = '文件已失效或没有可用的打开应用，请重新关联。');
                          }
                        },
                  trailing: IconButton(
                      tooltip: '移除文件关联',
                      onPressed: busy
                          ? null
                          : () => setState(() {
                                files.removeAt(i);
                                _dirty = true;
                              }),
                      icon: const Icon(Icons.close))),
            TextButton.icon(
                onPressed: busy || files.length >= 10
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          final file = await PersonalFileService().pick();
                          if (mounted &&
                              file != null &&
                              !files.any((f) => f.url == file.url)) {
                            setState(() {
                              files.add(file);
                              _dirty = true;
                            });
                          }
                        } catch (error) {
                          if (mounted) {
                            setState(() => message =
                                error is PlatformException &&
                                        error.code == 'file_access'
                                    ? '系统未授予持久读取权限，请在文件选择器的“内部存储”中重选本机文件。'
                                    : '文件未能关联，请重试');
                          }
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                icon: const Icon(Icons.folder_open),
                label: const Text('关联本地文件')),
            if (message != null)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(message!)),
            FilledButton(
                onPressed: busy ? null : save,
                child: Text(busy ? '正在处理…' : '保存个人记录')),
          ])));
}

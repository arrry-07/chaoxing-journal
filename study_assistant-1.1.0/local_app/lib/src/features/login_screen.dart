import 'package:flutter/material.dart';
import '../app/journal.dart';
import '../app/app_deep_links.dart';
import 'package:go_router/go_router.dart';

import '../services/assignment_store.dart';
import 'agreement_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.store,
    this.returnTo,
  });

  final AssignmentStore store;
  final String? returnTo;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _chaoxingAccount = TextEditingController();
  final _chaoxingPassword = TextEditingController();
  bool _accepted = false;

  @override
  void dispose() {
    _chaoxingAccount.dispose();
    _chaoxingPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final canLogin = _chaoxingAccount.text.trim().isNotEmpty &&
            _chaoxingPassword.text.isNotEmpty &&
            _accepted &&
            !widget.store.isLoading;

        return Scaffold(
          backgroundColor: Journal.paper,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(32, 64, 32, 24),
              children: [
                Text(
                  '学习通登录',
                  style: Journal.section.copyWith(fontSize: 26),
                ),
                const SizedBox(height: 8),
                Text(
                  '使用学习通账号同步课程作业和截止时间。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Journal.muted,
                      ),
                ),
                const SizedBox(height: 18),
                _ChaoxingForm(
                  account: _chaoxingAccount,
                  password: _chaoxingPassword,
                  onChanged: () => setState(() {}),
                ),
                if (widget.store.error != null) ...[
                  const SizedBox(height: 18),
                  _LoginErrorCard(message: widget.store.error!),
                ],
                const SizedBox(height: 22),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: canLogin ? Journal.ink : Journal.sage,
                      foregroundColor: Journal.sheet,
                      disabledBackgroundColor: Journal.sage,
                      disabledForegroundColor: Journal.muted,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: canLogin ? _login : null,
                    child: widget.store.isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            '登录学习通',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 22),
                _AgreementPanel(
                  accepted: _accepted,
                  enabled: !widget.store.isLoading,
                  onChanged: (value) => setState(() => _accepted = value),
                  onOpen: (kind) =>
                      Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => AgreementScreen(kind: kind),
                  )),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _login() async {
    await widget.store.loginChaoxing(
      account: _chaoxingAccount.text,
      password: _chaoxingPassword.text,
      agreementAccepted: _accepted,
    );
    if (!mounted) return;
    if (widget.store.isAuthenticated && widget.store.error == null) {
      context.go(loginSuccessLocation(widget.returnTo));
    }
  }
}

class _AgreementPanel extends StatelessWidget {
  const _AgreementPanel({
    required this.accepted,
    required this.enabled,
    required this.onChanged,
    required this.onOpen,
  });

  final bool accepted;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final ValueChanged<AgreementKind> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 16),
      decoration: BoxDecoration(
        color: Journal.sheet,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Journal.ink.withValues(alpha: 0.055),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                container: true,
                child: Checkbox(
                  value: accepted,
                  semanticLabel: '我已阅读并同意服务协议和隐私协议',
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  visualDensity: VisualDensity.standard,
                  shape: const CircleBorder(),
                  checkColor: Journal.sheet,
                  fillColor: WidgetStateProperty.resolveWith((states) =>
                      states.contains(WidgetState.selected)
                          ? Journal.ink
                          : Journal.sage),
                  side: BorderSide(
                    color: Journal.rule,
                    width: 1,
                  ),
                  onChanged:
                      enabled ? (value) => onChanged(value ?? false) : null,
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '我已阅读并同意',
                        style: Journal.metadata.copyWith(
                          color: Journal.ink,
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 7,
                        runSpacing: 1,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _link(AgreementKind.service),
                          Text(
                            '·',
                            style: Journal.metadata.copyWith(
                              color: Journal.muted,
                              fontSize: 15,
                              height: 1,
                            ),
                          ),
                          _link(AgreementKind.privacy),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 0),
            child: Text(
              '课程作业数据保存在本机，账号密码保存在本机安全存储中。\n'
              '登录与同步直接连接学习通，不经过开发者服务器。',
              style: Journal.metadata.copyWith(
                fontSize: 13.5,
                height: 1.58,
                color: Journal.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _link(AgreementKind kind) => TextButton(
        style: TextButton.styleFrom(
          foregroundColor: Journal.ink,
          minimumSize: const Size(48, 36),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          textStyle: Journal.metadata.copyWith(
            color: Journal.ink,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            decoration: TextDecoration.underline,
            decorationColor: Journal.ink.withValues(alpha: 0.72),
            decorationThickness: 1,
          ),
        ),
        onPressed: enabled ? () => onOpen(kind) : null,
        child: Text(kind.title),
      );
}

class _LoginErrorCard extends StatelessWidget {
  const _LoginErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChaoxingForm extends StatelessWidget {
  const _ChaoxingForm({
    required this.account,
    required this.password,
    required this.onChanged,
  });

  final TextEditingController account;
  final TextEditingController password;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: account,
          onChanged: (_) => onChanged(),
          textInputAction: TextInputAction.next,
          decoration: _fieldDecoration('账号'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: password,
          onChanged: (_) => onChanged(),
          obscureText: true,
          decoration: _fieldDecoration('密码'),
        ),
      ],
    );
  }
}

InputDecoration _fieldDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: Journal.metadata,
    filled: true,
    fillColor: Journal.sheet,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );
}

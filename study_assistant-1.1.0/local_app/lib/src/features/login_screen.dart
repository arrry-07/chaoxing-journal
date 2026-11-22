import 'package:flutter/material.dart';
import '../app/journal.dart';
import '../app/app_deep_links.dart';
import 'package:go_router/go_router.dart';

import '../services/assignment_store.dart';
import 'agreement_screen.dart';
import 'widgets/journal_buttons.dart';

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
        final journal = Journal.of(context);
        final horizontalPadding =
            MediaQuery.sizeOf(context).width < 360 ? 20.0 : 32.0;
        final canLogin = _chaoxingAccount.text.trim().isNotEmpty &&
            _chaoxingPassword.text.isNotEmpty &&
            _accepted &&
            !widget.store.isLoading;

        return Scaffold(
          backgroundColor: journal.paper,
          body: SafeArea(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                64,
                horizontalPadding,
                24,
              ),
              children: [
                Text(
                  '学习通登录',
                  style: journal.section.copyWith(fontSize: 26),
                ),
                const SizedBox(height: 8),
                Text(
                  '使用学习通账号同步课程作业和截止时间。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: journal.muted,
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
                JournalPrimaryButton(
                  label: '登录学习通',
                  loading: widget.store.isLoading,
                  onPressed: canLogin ? _login : null,
                ),
                const SizedBox(height: 22),
                _AgreementPanel(
                  accepted: _accepted,
                  enabled: !widget.store.isLoading,
                  onChanged: (value) => setState(() => _accepted = value),
                  onOpen: (kind) => Navigator.of(context, rootNavigator: true)
                      .push(MaterialPageRoute<void>(
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
    final journal = Journal.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
      decoration: BoxDecoration(
        color: journal.sheet,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: journal.cardBorder, width: 0.8),
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
                  checkColor: journal.sheet,
                  fillColor: WidgetStateProperty.resolveWith((states) =>
                      states.contains(WidgetState.selected)
                          ? Journal.of(context).ink
                          : Journal.of(context).sage),
                  side: BorderSide(
                    color: journal.rule,
                    width: 1,
                  ),
                  onChanged:
                      enabled ? (value) => onChanged(value ?? false) : null,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: Wrap(
                    spacing: 0,
                    runSpacing: 0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 13.5),
                        child: Text(
                          '我已阅读并同意',
                          style: journal.metadata.copyWith(
                            color: journal.ink,
                            fontWeight: FontWeight.w600,
                            fontSize: 14.5,
                            height: 1.45,
                          ),
                        ),
                      ),
                      _link(context, AgreementKind.service),
                      _link(context, AgreementKind.privacy),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 12, 0, 0),
            child: Text(
              '课程与作业数据保存在本机。',
              style: journal.metadata.copyWith(
                fontSize: 13.5,
                height: 1.58,
                color: journal.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _link(BuildContext context, AgreementKind kind) => Semantics(
        container: true,
        button: true,
        link: true,
        label: '查看《${kind.title}》',
        onTap: enabled ? () => onOpen(kind) : null,
        child: ExcludeSemantics(
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Journal.of(context).ink,
              minimumSize: const Size(48, 48),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.standard,
              textStyle: Journal.of(context).metadata.copyWith(
                    color: Journal.of(context).ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                    height: 1.45,
                    decoration: TextDecoration.underline,
                    decorationColor:
                        Journal.of(context).ink.withValues(alpha: 0.72),
                    decorationThickness: 1,
                  ),
            ),
            onPressed: enabled ? () => onOpen(kind) : null,
            child: Text('《${kind.title}》'),
          ),
        ),
      );
}

class _LoginErrorCard extends StatelessWidget {
  const _LoginErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Container(
      decoration: BoxDecoration(
        color: journal.berryBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: journal.berry.withValues(alpha: 0.25),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              color: journal.berry,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: journal.berry),
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
          decoration: _fieldDecoration(context, '账号'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: password,
          onChanged: (_) => onChanged(),
          obscureText: true,
          decoration: _fieldDecoration(context, '密码'),
        ),
      ],
    );
  }
}

InputDecoration _fieldDecoration(BuildContext context, String hint) {
  final journal = Journal.of(context);
  return InputDecoration(
    hintText: hint,
    hintStyle: journal.metadata,
    filled: true,
    fillColor: journal.sheet,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: journal.cardBorder, width: 0.8),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: journal.cardBorder, width: 0.8),
    ),
  );
}

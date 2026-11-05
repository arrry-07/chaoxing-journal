import 'package:flutter/material.dart';
import '../app/journal.dart';
import 'package:go_router/go_router.dart';

import '../services/assignment_store.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.store,
  });

  final AssignmentStore store;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _chaoxingAccount = TextEditingController();
  final _chaoxingPassword = TextEditingController();
  bool _accepted = true;

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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _accepted = !_accepted),
                      child: Icon(
                        _accepted
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: _accepted ? Journal.ink : Journal.muted,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: '我已阅读并同意 ',
                          children: [
                            TextSpan(
                              text: '服务协议',
                              style: TextStyle(color: Journal.ink),
                            ),
                            TextSpan(text: ' 和 '),
                            TextSpan(
                              text: '隐私协议',
                              style: TextStyle(color: Journal.ink),
                            ),
                          ],
                        ),
                        style: TextStyle(
                          color: Journal.muted,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
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
      context.go('/assignments');
    }
  }
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

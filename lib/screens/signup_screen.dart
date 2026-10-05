import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../logic/password_rules.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/liquid_glass.dart';

final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Port of components/SignupScreen.tsx: email + password (with a live rule
/// checklist) + confirmation.
class SignupScreen extends StatefulWidget {
  final AppTheme theme;
  final void Function(AuthUser user) onAuthenticated;
  final VoidCallback onBack;

  const SignupScreen({
    super.key,
    required this.theme,
    required this.onAuthenticated,
    required this.onBack,
  });

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  bool _visible = false;
  bool _busy = false;
  String _message = '';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (!_emailRe.hasMatch(email)) {
      setState(() => _message = '올바른 이메일 주소를 입력해 주세요.');
      return;
    }
    if (!isStrongPassword(password)) {
      setState(() => _message = '비밀번호 조건을 모두 충족해 주세요.');
      return;
    }
    if (password != _confirmController.text) {
      setState(() => _message = '비밀번호가 일치하지 않습니다.');
      _confirmFocus.requestFocus();
      return;
    }
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      final user = await AuthService.instance.register(email, password);
      if (!mounted) return;
      _passwordController.clear();
      _confirmController.clear();
      widget.onAuthenticated(user);
    } catch (error) {
      if (!mounted) return;
      setState(
        () =>
            _message = error is AuthException ? error.message : '회원가입하지 못했습니다.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final blue = CupertinoColors.activeBlue.resolveFrom(context);
    final password = _passwordController.text;
    final confirmation = _confirmController.text;
    return Scaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: LayoutBuilder(
              builder: (context, viewport) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (viewport.maxHeight - 56).clamp(
                      0,
                      double.infinity,
                    ),
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: LiquidGlass(
                            useNative: false,
                            radius: 22,
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: _busy ? null : widget.onBack,
                                child: Icon(
                                  CupertinoIcons.chevron_back,
                                  color: blue,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Text(
                          '회원가입',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: CupertinoColors.label.resolveFrom(context),
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.8,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '이메일과 안전한 비밀번호로\n계정을 만들어 주세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: CupertinoColors.secondaryLabel.resolveFrom(
                              context,
                            ),
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 32),
                        LiquidGlass(
                          useNative: false,
                          radius: 20,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '이메일',
                                  style: TextStyle(
                                    color: theme.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  autocorrect: false,
                                  enabled: !_busy,
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) =>
                                      _passwordFocus.requestFocus(),
                                  onChanged: (_) =>
                                      setState(() => _message = ''),
                                  style: TextStyle(color: theme.text),
                                  decoration: const InputDecoration(
                                    hintText: 'example@email.com',
                                    filled: false,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '비밀번호',
                                  style: TextStyle(
                                    color: theme.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _passwordController,
                                  focusNode: _passwordFocus,
                                  obscureText: !_visible,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  enabled: !_busy,
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) =>
                                      _confirmFocus.requestFocus(),
                                  onChanged: (_) =>
                                      setState(() => _message = ''),
                                  style: TextStyle(color: theme.text),
                                  decoration: InputDecoration(
                                    filled: false,
                                    hintText: '비밀번호를 입력해 주세요',
                                    suffixIcon: TextButton(
                                      onPressed: () =>
                                          setState(() => _visible = !_visible),
                                      child: Text(
                                        _visible ? '숨기기' : '보기',
                                        style: TextStyle(
                                          color: theme.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 4,
                                  children: [
                                    for (final rule in passwordRules)
                                      Builder(
                                        builder: (context) {
                                          final passed = rule.test(password);
                                          return Text(
                                            '${passed ? '✓' : '○'} ${rule.label}',
                                            style: TextStyle(
                                              color: passed
                                                  ? blue
                                                  : theme.textMuted,
                                              fontSize: 12,
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '비밀번호 확인',
                                  style: TextStyle(
                                    color: theme.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _confirmController,
                                  focusNode: _confirmFocus,
                                  obscureText: !_visible,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  enabled: !_busy,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _submit(),
                                  onChanged: (_) =>
                                      setState(() => _message = ''),
                                  style: TextStyle(color: theme.text),
                                  decoration: InputDecoration(
                                    filled: false,
                                    hintText: '비밀번호를 다시 입력해 주세요',
                                    enabledBorder:
                                        confirmation.isNotEmpty &&
                                            confirmation != password
                                        ? OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            borderSide: BorderSide(
                                              color: theme.danger,
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                                if (confirmation.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    confirmation == password
                                        ? '✓ 비밀번호가 일치합니다.'
                                        : '비밀번호가 일치하지 않습니다.',
                                    style: TextStyle(
                                      color: confirmation == password
                                          ? blue
                                          : theme.danger,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (_message.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _message,
                            style: TextStyle(color: theme.danger, fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 12),
                        LiquidGlass(
                          useNative: false,
                          radius: 18,
                          child: SizedBox(
                            width: double.infinity,
                            child: CupertinoButton(
                              color: _busy
                                  ? null
                                  : blue.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(14),
                              padding: const EdgeInsets.symmetric(vertical: 17),
                              onPressed: _busy ? null : _submit,
                              child: Text(
                                _busy ? '가입 중…' : '회원가입',
                                style: TextStyle(
                                  color: _busy
                                      ? CupertinoColors.secondaryLabel
                                            .resolveFrom(context)
                                      : blue,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : widget.onBack,
                          child: Text(
                            '이미 계정이 있나요? 로그인',
                            style: TextStyle(
                              color: theme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

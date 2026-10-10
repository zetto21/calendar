import 'dart:convert' show base64Url, utf8;
import 'dart:math' show Random;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../logic/security_urls.dart';
import '../services/auth_service.dart';
import '../services/oauth_browser.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_marks.dart';
import '../widgets/macos_login_brand.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/server_connection_monitor.dart';

final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

enum _ProviderStatus { loading, ready, error }

/// Email/password form and social login via a browser session that redirects
/// back to the calendar:// scheme (ASWebAuthenticationSession / Custom Tabs).
class LoginScreen extends StatefulWidget {
  final AppTheme theme;
  final void Function(AuthUser user) onAuthenticated;
  final VoidCallback onSignup;

  const LoginScreen({
    super.key,
    required this.theme,
    required this.onAuthenticated,
    required this.onSignup,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  late final AnimationController _entranceController;
  bool _motionInitialized = false;
  bool _passwordVisible = false;
  bool _emailFormVisible = false;
  bool _busy = false;
  String _message = '';
  bool _checkingConnection = false;

  List<SocialProvider> _enabledProviders = [];
  _ProviderStatus _providerStatus = _ProviderStatus.loading;
  SocialProvider? _socialBusy;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    ServerConnectionMonitor.available.addListener(_onConnectionChanged);
    _loadProviders();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionInitialized) return;
    _motionInitialized = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _entranceController.value = 1;
    } else {
      _entranceController.forward();
    }
  }

  void _onConnectionChanged() {
    if (ServerConnectionMonitor.available.value == true) _loadProviders();
  }

  Future<void> _loadProviders() async {
    if (!mounted || _checkingConnection) return;
    _checkingConnection = true;
    try {
      final providers = await AuthService.instance.enabledSocialProviders();
      if (!mounted) return;
      setState(() {
        _enabledProviders = providers;
        _providerStatus = _ProviderStatus.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enabledProviders = [];
        _providerStatus = _ProviderStatus.error;
      });
    } finally {
      _checkingConnection = false;
    }
  }

  bool get _isAuthenticating => _busy || _socialBusy != null;

  void _showLoginFailure(String message) {
    if (!mounted) return;
    setState(() => _message = message);
  }

  /// iOS and macOS use the system Sign in with Apple sheet instead of a
  /// browser; other platforms keep the server's web OAuth flow.
  bool get _useNativeAppleSignIn =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Returns null when the user dismisses the Apple sheet.
  Future<AuthUser?> _nativeAppleLogin() async {
    final random = Random.secure();
    final rawNonce = base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) return null;
      throw AuthException('Apple 로그인에 실패했습니다.');
    }
    final identityToken = credential.identityToken;
    if (identityToken == null) {
      throw AuthException('Apple 인증 정보를 받지 못했습니다.');
    }
    // Apple only shares the name on the very first authorization. Korean
    // names read family-first without a space ("홍길동"), others "John Smith".
    final family = credential.familyName?.trim() ?? '';
    final given = credential.givenName?.trim() ?? '';
    final korean = RegExp(r'[가-힣]').hasMatch(family + given);
    final name = korean
        ? '$family$given'
        : [given, family].where((part) => part.isNotEmpty).join(' ');
    return AuthService.instance.signInWithAppleNative(
      identityToken: identityToken,
      nonce: rawNonce,
      name: name,
    );
  }

  Future<void> _socialLogin(SocialProvider provider) async {
    if (_isAuthenticating || !_enabledProviders.contains(provider)) return;
    setState(() {
      _socialBusy = provider;
      _message = '';
    });
    try {
      if (provider == SocialProvider.apple && _useNativeAppleSignIn) {
        final user = await _nativeAppleLogin();
        if (user == null || !mounted) return;
        widget.onAuthenticated(user);
        return;
      }
      // Bind the one-time login code to this app's authentication attempt.
      // A code injected by another browser or custom-scheme handler cannot
      // be exchanged without this verifier.
      final random = Random.secure();
      final clientVerifier = base64Url
          .encode(List<int>.generate(32, (_) => random.nextInt(256)))
          .replaceAll('=', '');
      final clientChallenge = base64Url
          .encode(sha256.convert(utf8.encode(clientVerifier)).bytes)
          .replaceAll('=', '');
      final result = await authenticateOAuthBrowser(
        url: AuthService.instance.socialLoginStartURL(
          provider,
          codeChallenge: clientChallenge,
        ),
      );
      final callback = parseSocialAuthCallback(
        result,
        webOrigin: kIsWeb ? Uri.base : null,
      );
      final error = callback.error;
      if (error != null) throw AuthException(error);
      final user = await AuthService.instance.exchangeSocialCode(
        callback.code!,
        clientVerifier: clientVerifier,
      );
      if (!mounted) return;
      widget.onAuthenticated(user);
    } catch (error) {
      if (!mounted) return;
      _showLoginFailure(
        error is AuthException
            ? error.message
            : error is PlatformException
            ? (error.code.toLowerCase() == 'canceled'
                  ? '로그인이 취소되었습니다.'
                  : error.message ?? '간편 로그인에 실패했습니다.')
            : '간편 로그인에 실패했습니다.',
      );
    } finally {
      if (mounted) setState(() => _socialBusy = null);
    }
  }

  @override
  void dispose() {
    ServerConnectionMonitor.available.removeListener(_onConnectionChanged);
    _entranceController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isAuthenticating) return;
    final email = _emailController.text.trim();
    if (!_emailRe.hasMatch(email)) {
      setState(() => _message = '올바른 이메일 주소를 입력해 주세요.');
      return;
    }
    if (_passwordController.text.isEmpty) {
      setState(() => _message = '비밀번호를 입력해 주세요.');
      _passwordFocus.requestFocus();
      return;
    }
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      final user = await AuthService.instance.login(
        email,
        _passwordController.text,
      );
      if (!mounted) return;
      _passwordController.clear();
      widget.onAuthenticated(user);
    } catch (error) {
      if (!mounted) return;
      _showLoginFailure(
        error is AuthException ? error.message : '로그인하지 못했습니다.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static bool get _isDesktop =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  Widget build(BuildContext context) {
    // Windows and web share the macOS email and social sign-in layout.
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows) {
      final login = _buildMacLogin();
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(0.9)),
          child: login,
        );
      }
      return login;
    }
    final form = _emailFormVisible
        ? _buildEmailLogin(context)
        : _buildLoginOptions(context, desktop: _isDesktop);
    if (!_isDesktop) return form;
    return Scaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      body: LayoutBuilder(
        builder: (context, viewport) {
          final wide = viewport.maxWidth >= 860;
          return Row(
            children: [
              if (wide) Expanded(flex: 5, child: _buildDesktopBrandPanel()),
              Expanded(
                flex: 4,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: form,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMacLogin() {
    final theme = widget.theme;
    return Scaffold(
      backgroundColor: theme.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            // The web shows only the sign-in form, without the brand panel.
            final wide = !kIsWeb && viewport.maxWidth >= 900;
            return Row(
              children: [
                if (wide) Expanded(child: MacosLoginBrand(theme: theme)),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: viewport.maxWidth < 420 ? 24 : 48,
                      vertical: 36,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: (viewport.maxHeight - 72).clamp(
                          0,
                          double.infinity,
                        ),
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: AutofillGroup(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Align(
                                  alignment: Alignment.center,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Image.asset(
                                      'assets/login/app-icon.png',
                                      width: 56,
                                      height: 56,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  '나의 하루를 차곡차곡',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: theme.accent,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  '일상 캘린더에 오신 것을 환영해요',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: theme.text,
                                    fontSize: 27,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -1.2,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '로그인하고 나의 하루를 이어가세요.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: theme.textSecondary,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 30),
                                TextField(
                                  controller: _emailController,
                                  enabled: !_isAuthenticating,
                                  autofillHints: const [
                                    AutofillHints.username,
                                    AutofillHints.email,
                                  ],
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autocorrect: false,
                                  onSubmitted: (_) =>
                                      _passwordFocus.requestFocus(),
                                  onChanged: (_) =>
                                      setState(() => _message = ''),
                                  decoration: const InputDecoration(
                                    labelText: '이메일',
                                    hintText: 'example@email.com',
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _passwordController,
                                  focusNode: _passwordFocus,
                                  enabled: !_isAuthenticating,
                                  autofillHints: const [AutofillHints.password],
                                  obscureText: !_passwordVisible,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) {
                                    if (!_isAuthenticating) _submit();
                                  },
                                  onChanged: (_) =>
                                      setState(() => _message = ''),
                                  decoration: InputDecoration(
                                    labelText: '비밀번호',
                                    suffixIcon: IconButton(
                                      tooltip: _passwordVisible
                                          ? '비밀번호 숨기기'
                                          : '비밀번호 보기',
                                      onPressed: () => setState(
                                        () => _passwordVisible =
                                            !_passwordVisible,
                                      ),
                                      icon: Icon(
                                        _passwordVisible
                                            ? CupertinoIcons.eye_slash
                                            : CupertinoIcons.eye,
                                        size: 19,
                                      ),
                                    ),
                                  ),
                                ),
                                if (_message.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      _message,
                                      style: TextStyle(
                                        color: theme.danger,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 20),
                                SizedBox(
                                  height: 48,
                                  child: FilledButton(
                                    onPressed: _isAuthenticating
                                        ? null
                                        : _submit,
                                    child: _busy
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text('로그인'),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: _isAuthenticating
                                      ? null
                                      : widget.onSignup,
                                  child: const Text('처음이신가요? 회원가입'),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    const Expanded(child: Divider()),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: Text(
                                        '또는 간편 로그인',
                                        style: TextStyle(
                                          color: theme.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const Expanded(child: Divider()),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    for (final id in [
                                      if (kIsWeb ||
                                          defaultTargetPlatform !=
                                              TargetPlatform.windows)
                                        SocialProvider.apple,
                                      SocialProvider.google,
                                      if (!kIsWeb &&
                                          defaultTargetPlatform ==
                                              TargetPlatform.windows)
                                        SocialProvider.apple,
                                      SocialProvider.kakao,
                                      SocialProvider.naver,
                                      SocialProvider.facebook,
                                    ])
                                      Tooltip(
                                        message:
                                            '${socialProviders.firstWhere((p) => p.id == id).label} 계정으로 로그인',
                                        child: _buildCompactSocialButton(
                                          socialProviders.firstWhere(
                                            (p) => p.id == id,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                if (_providerStatus ==
                                        _ProviderStatus.loading ||
                                    _socialBusy != null) ...[
                                  const SizedBox(height: 12),
                                  const Center(
                                    child: CupertinoActivityIndicator(),
                                  ),
                                ],
                                if (_providerStatus ==
                                    _ProviderStatus.error) ...[
                                  const SizedBox(height: 8),
                                  TextButton(
                                    onPressed: _checkingConnection
                                        ? null
                                        : _loadProviders,
                                    child: const Text(
                                      '간편 로그인을 불러오지 못했어요. 다시 시도',
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDesktopBrandPanel() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4F8CFF), Color(0xFF2456D6)],
        ),
      ),
      padding: const EdgeInsets.all(56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'assets/login/app-icon.png',
              width: 96,
              height: 96,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            '일상 캘린더',
            style: TextStyle(
              color: Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.5,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '나의 하루를 차곡차곡',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginOptions(BuildContext context, {bool desktop = false}) {
    final apple = socialProviders.firstWhere(
      (provider) => provider.id == SocialProvider.apple,
    );
    final google = socialProviders.firstWhere(
      (provider) => provider.id == SocialProvider.google,
    );
    final appleEnabled = _isSocialProviderEnabled(apple.id);
    final googleEnabled = _isSocialProviderEnabled(google.id);
    final blue = CupertinoColors.activeBlue.resolveFrom(context);
    const darkButton = Color(0xFF1C1C1E);
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final appleButton = _buildOptionButton(
      label: 'Apple 계정으로 계속 진행',
      icon: const Icon(Icons.apple, color: Colors.white, size: 31),
      color: darkButton,
      enabled: appleEnabled,
      onPressed: _isAuthenticating || !appleEnabled
          ? null
          : () => _socialLogin(apple.id),
    );
    final googleButton = _buildOptionButton(
      label: 'Google 계정으로 계속 진행',
      icon: SizedBox(width: 29, height: 29, child: google.mark(context)),
      color: Colors.white,
      foregroundColor: const Color(0xFF1F1F1F),
      enabled: googleEnabled,
      onPressed: _isAuthenticating || !googleEnabled
          ? null
          : () => _socialLogin(google.id),
    );
    return Scaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            // Short, square-ish screens (e.g. foldables like iPhone Duo)
            // don't have room for the tall Spacer-based layout below.
            final compact = viewport.maxHeight < 700;
            final buttons = [
              _enter(
                order: 1,
                child: _buildOptionButton(
                  label: '이메일로 계속 진행',
                  icon: Icon(CupertinoIcons.envelope, color: blue, size: 27),
                  color: blue.withValues(alpha: 0.16),
                  foregroundColor: blue,
                  onPressed: _isAuthenticating
                      ? null
                      : () => setState(() => _emailFormVisible = true),
                ),
              ),
              SizedBox(height: compact ? 10 : 14),
              _enter(order: 2, child: isAndroid ? googleButton : appleButton),
              SizedBox(height: compact ? 10 : 14),
              _enter(order: 3, child: isAndroid ? appleButton : googleButton),
              SizedBox(height: compact ? 14 : 20),
              _enter(order: 4, child: _buildOtherSocialSection()),
            ];
            if (compact && !desktop) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 20, 32, 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (viewport.maxHeight - 36).clamp(
                      0,
                      double.infinity,
                    ),
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _enter(
                          order: 0,
                          child: _buildBrandHero(context, compact: true),
                        ),
                        const SizedBox(height: 18),
                        ...buttons,
                      ],
                    ),
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (desktop) ...[
                    const Spacer(),
                    Text(
                      '로그인',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: CupertinoColors.label.resolveFrom(context),
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 32),
                  ] else ...[
                    const Spacer(flex: 5),
                    _enter(order: 0, child: _buildBrandHero(context)),
                    const Spacer(flex: 6),
                  ],
                  ...buttons,
                  if (desktop) const Spacer(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _enter({required int order, required Widget child}) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final start = order * 0.1;
    final animation = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(
        start,
        (start + 0.45).clamp(0, 1),
        curve: Curves.easeOutCubic,
      ),
    );
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final value = animation.value;
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildBrandHero(BuildContext context, {bool compact = false}) {
    final logoSize = compact ? 76.0 : 112.0;
    return Column(
      children: [
        SizedBox(
          width: logoSize,
          height: logoSize,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(compact ? 20 : 28),
            child: Image.asset('assets/login/app-icon.png', fit: BoxFit.cover),
          ),
        ),
        SizedBox(height: compact ? 16 : 26),
        Text(
          '일상 캘린더',
          style: TextStyle(
            color: CupertinoColors.label.resolveFrom(context),
            fontSize: compact ? 26 : 32,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.1,
          ),
        ),
        SizedBox(height: compact ? 8 : 14),
        Text(
          '나의 하루를 차곡차곡',
          style: TextStyle(
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
            fontSize: compact ? 15 : 17,
          ),
        ),
      ],
    );
  }

  Widget _buildOtherSocialSection() {
    final providers = socialProviders.where(
      (provider) =>
          provider.id != SocialProvider.apple &&
          provider.id != SocialProvider.google,
    );
    return Column(
      children: [
        const Text(
          '다른 SNS로 계속',
          style: TextStyle(color: Color(0xFF77777D), fontSize: 13),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final provider in providers)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: _buildCompactSocialButton(provider),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompactSocialButton(SocialProviderSpec provider) {
    final enabled = _isSocialProviderEnabled(provider.id);
    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: SizedBox(
        width: 50,
        height: 50,
        child: ClipOval(
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(25),
            color: provider.background,
            disabledColor: provider.background,
            onPressed: _isAuthenticating || !enabled
                ? null
                : () => _socialLogin(provider.id),
            child: provider.mark(context),
          ),
        ),
      ),
    );
  }

  bool _isSocialProviderEnabled(SocialProvider provider) =>
      _providerStatus == _ProviderStatus.ready &&
      _enabledProviders.contains(provider);

  Widget _buildOptionButton({
    required String label,
    required Widget icon,
    required Color color,
    required VoidCallback? onPressed,
    Color foregroundColor = Colors.white,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: SizedBox(
        height: 56,
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          borderRadius: BorderRadius.circular(16),
          color: color,
          disabledColor: color,
          onPressed: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmailLogin(BuildContext context) {
    final theme = widget.theme;
    final blue = CupertinoColors.activeBlue.resolveFrom(context);
    return Scaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: LayoutBuilder(
              builder: (context, viewport) {
                return SingleChildScrollView(
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
                                  onPressed: _isAuthenticating
                                      ? null
                                      : () => setState(
                                          () => _emailFormVisible = false,
                                        ),
                                  child: Icon(
                                    CupertinoIcons.chevron_back,
                                    color: blue,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Column(
                            children: [
                              Text(
                                '로그인',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: CupertinoColors.label.resolveFrom(
                                    context,
                                  ),
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.8,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                '등록한 이메일로 로그인해 주세요.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: CupertinoColors.secondaryLabel
                                      .resolveFrom(context),
                                  fontSize: 16,
                                  height: 1.5,
                                ),
                              ),
                            ],
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
                                    textInputAction: TextInputAction.next,
                                    enabled: !_isAuthenticating,
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
                                  const SizedBox(height: 14),
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
                                    obscureText: !_passwordVisible,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    textInputAction: TextInputAction.go,
                                    enabled: !_isAuthenticating,
                                    onSubmitted: (_) => _submit(),
                                    onChanged: (_) =>
                                        setState(() => _message = ''),
                                    style: TextStyle(color: theme.text),
                                    decoration: InputDecoration(
                                      hintText: '비밀번호를 입력해 주세요',
                                      filled: false,
                                      suffixIcon: TextButton(
                                        onPressed: () => setState(
                                          () => _passwordVisible =
                                              !_passwordVisible,
                                        ),
                                        child: Text(
                                          _passwordVisible ? '숨기기' : '보기',
                                          style: TextStyle(
                                            color: theme.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_message.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              _message,
                              style: TextStyle(
                                color: theme.danger,
                                fontSize: 13,
                              ),
                            ),
                          ],
                          LiquidGlass(
                            useNative: false,
                            radius: 18,
                            child: SizedBox(
                              width: double.infinity,
                              child: CupertinoButton(
                                color: _isAuthenticating
                                    ? null
                                    : blue.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(14),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 17,
                                ),
                                onPressed: _isAuthenticating ? null : _submit,
                                child: Text(
                                  _busy ? '로그인 중…' : '이메일로 로그인',
                                  style: TextStyle(
                                    color: _isAuthenticating
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
                            onPressed: _isAuthenticating
                                ? null
                                : widget.onSignup,
                            child: Text(
                              '계정이 없나요? 회원가입',
                              style: TextStyle(
                                color: theme.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

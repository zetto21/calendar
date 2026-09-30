import '../widgets/app_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import '../widgets/liquid_glass.dart';

class ConsentScreen extends StatefulWidget {
  static const storageKey = 'usage_consent_v1';
  static const marketingStorageKey = 'marketing_consent_v1';
  final AppTheme theme;
  final VoidCallback onAccepted;

  const ConsentScreen({super.key, required this.theme, required this.onAccepted});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _age = false;
  bool _terms = false;
  bool _privacy = false;
  bool _marketing = false;
  bool _saving = false;
  bool get _required => _age && _terms && _privacy;
  bool get _all => _required && _marketing;

  void _showDocument(String title) {
    Navigator.of(context).push(CupertinoPageRoute<void>(
      builder: (context) => CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text(title)),
        child: const SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Text('문서가 아직 등록되지 않았습니다.'),
          ),
        ),
      ),
    ));
  }

  Future<void> _continue() async {
    if (!_required || _saving) return;
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final marketingSaved = await prefs.setBool(ConsentScreen.marketingStorageKey, _marketing);
      if (!marketingSaved) throw StateError('Marketing preference was not saved');
      final saved = await prefs.setString(
        ConsentScreen.storageKey,
        DateTime.now().toUtc().toIso8601String(),
      );
      if (!saved) throw StateError('Consent was not saved');
      if (mounted) widget.onAccepted();
    } catch (_) {
      if (!mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => AppDialog(
          title: const Text('동의 내용을 저장하지 못했습니다'),
          content: const Text('잠시 후 다시 시도해 주세요.'),
          actions: [
            AppDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _item(String title, bool value, ValueChanged<bool> change,
      {bool document = false, bool all = false}) {
    final blue = CupertinoColors.activeBlue.resolveFrom(context);
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10),
          child: CupertinoCheckbox(
            value: value,
            activeColor: blue,
            semanticLabel: title,
            onChanged: _saving ? null : (checked) => setState(() => change(checked ?? false)),
          ),
        ),
        Expanded(
          child: CupertinoButton(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
            onPressed: _saving ? null : () => setState(() => change(!value)),
            child: Text(title,
                style: TextStyle(
                  color: CupertinoColors.label.resolveFrom(context),
                  fontSize: 16,
                  fontWeight: all ? FontWeight.w600 : FontWeight.w400,
                )),
          ),
        ),
        if (document)
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            onPressed: () => _showDocument(title.replaceFirst('[필수] ', '')),
            child: Semantics(
              label: '$title 보기',
              child: Icon(CupertinoIcons.chevron_forward,
                  size: 16, color: CupertinoColors.tertiaryLabel.resolveFrom(context)),
            ),
          ),
      ],
    );
  }

  Widget _card(List<Widget> children) => LiquidGlass(
    useNative: false,
    radius: 20,
    child: Column(children: children),
  );

  Widget _separator() => Padding(
    padding: const EdgeInsets.only(left: 55),
    child: Container(height: 0.5, color: CupertinoColors.separator.resolveFrom(context)),
  );

  @override
  Widget build(BuildContext context) {
    final blue = CupertinoColors.activeBlue.resolveFrom(context);
    return DefaultTextStyle(
      style: TextStyle(
        fontFamily: '.SF Pro Text',
        fontSize: 16,
        color: CupertinoColors.label.resolveFrom(context),
        decoration: TextDecoration.none,
      ),
      child: CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: LayoutBuilder(builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: (constraints.maxHeight - 56).clamp(0, double.infinity)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('이용 전에\n확인해 주세요', textAlign: TextAlign.center,
                                style: TextStyle(color: CupertinoColors.label.resolveFrom(context),
                                    fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.8, height: 1.2)),
                            const SizedBox(height: 14),
                            Text('일상 캘린더를 시작하기 위해\n아래 필수 항목에 동의해 주세요.', textAlign: TextAlign.center,
                                style: TextStyle(color: CupertinoColors.secondaryLabel.resolveFrom(context), fontSize: 16, height: 1.5)),
                            const SizedBox(height: 32),
                            _card([_item('모두 동의합니다', _all, (value) {
                              _age = _terms = _privacy = _marketing = value;
                            }, all: true)]),
                            const SizedBox(height: 20),
                            _card([
                              _item('[필수] 만 14세 이상입니다', _age, (value) => _age = value),
                              _separator(),
                              _item('[필수] 이용약관 동의', _terms, (value) => _terms = value, document: true),
                              _separator(),
                              _item('[필수] 개인정보처리방침 동의', _privacy, (value) => _privacy = value, document: true),
                              _separator(),
                              _item('[선택] 광고성 정보 수신 동의', _marketing, (value) => _marketing = value),
                            ]),
                            const SizedBox(height: 10),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text('선택 항목에 동의하지 않아도 서비스를 이용할 수 있습니다.',
                                  style: TextStyle(color: CupertinoColors.secondaryLabel.resolveFrom(context), fontSize: 12, height: 1.4)),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 32),
                          child: LiquidGlass(
                            useNative: false,
                            radius: 18,
                            child: SizedBox(
                              width: double.infinity,
                              child: CupertinoButton(
                            color: _required ? blue.withValues(alpha: 0.16) : null,
                            key: const ValueKey('consentContinue'),
                            borderRadius: BorderRadius.circular(14),
                            padding: const EdgeInsets.symmetric(vertical: 17),
                            onPressed: _required && !_saving ? _continue : null,
                            child: Text(_saving ? '저장 중…' : '동의하고 계속하기',
                                style: TextStyle(
                                  color: _required && !_saving ? blue : CupertinoColors.secondaryLabel.resolveFrom(context),
                                  fontSize: 17, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

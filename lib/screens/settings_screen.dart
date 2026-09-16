import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/liquid_glass.dart';

class SettingsScreen extends StatelessWidget {
  final AppTheme theme;
  final String accountLabel;
  final VoidCallback? onLiveActivities;

  const SettingsScreen({
    super.key,
    required this.theme,
    required this.accountLabel,
    this.onLiveActivities,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: theme.bg,
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: const Text('설정'),
      centerTitle: true,
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        LiquidGlass(
          useNative: false,
          radius: 18,
          child: _card(context, [
            _header('계정'),
            ListTile(
              leading: const Icon(CupertinoIcons.person_circle),
              title: const Text('로그인 계정'),
              subtitle: Text(accountLabel),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        if (onLiveActivities != null) ...[
          const SizedBox(height: 14),
          LiquidGlass(
            useNative: false,
            radius: 18,
            child: _card(context, [
              _header('실시간 현황'),
              ListTile(
                leading: const Icon(CupertinoIcons.bolt_fill),
                title: const Text('Live Activity 요청 보내기'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onLiveActivities,
              ),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        LiquidGlass(
          useNative: false,
          radius: 18,
          child: _card(context, [
            _header('법률 정보 및 이용 약관'),
            ListTile(
              leading: const Icon(CupertinoIcons.doc_text),
              title: const Text('이용약관'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showInfo(
                context,
                '이용약관',
                '캘린더 서비스 이용에 관한 약관입니다. 서비스 이용 전 내용을 확인해 주세요.',
              ),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.lock_shield),
              title: const Text('개인정보 처리방침'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showInfo(
                context,
                '개인정보 처리방침',
                '서비스 제공에 필요한 정보만 처리하며, 개인정보 보호 관련 내용을 안내합니다.',
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        LiquidGlass(
          useNative: false,
          radius: 18,
          child: _card(context, [
            _header('프로그램 정보'),
            const ListTile(
              leading: Icon(CupertinoIcons.calendar),
              title: Text('캘린더'),
              subtitle: Text('버전 1.0.0'),
            ),
          ]),
        ),
      ],
    ),
  );

  void _showInfo(BuildContext context, String title, String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  );
  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
    child: Text(
      text,
      style: TextStyle(
        color: theme.accent,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
    ),
  );
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/liquid_glass.dart';

class SettingsScreen extends StatelessWidget {
  final AppTheme theme;
  final String accountLabel;
  final bool showHolidays, showLunar, showSolarTerms, showAnniversaries;
  final ValueChanged<bool> onHolidaysChanged,
      onLunarChanged,
      onSolarTermsChanged,
      onAnniversariesChanged;
  final VoidCallback onManageCalendars;
  final VoidCallback? onLiveActivities;

  const SettingsScreen({
    super.key,
    required this.theme,
    required this.accountLabel,
    required this.showHolidays,
    required this.showLunar,
    required this.showSolarTerms,
    required this.showAnniversaries,
    required this.onHolidaysChanged,
    required this.onLunarChanged,
    required this.onSolarTermsChanged,
    required this.onAnniversariesChanged,
    required this.onManageCalendars,
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
        LiquidGlass(
          useNative: false,
          radius: 18,
          child: _card(context, [
            _header('캘린더'),
            ListTile(
              leading: const Icon(CupertinoIcons.calendar_badge_plus),
              title: const Text('캘린더 연동'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onManageCalendars,
            ),
          ]),
        ),
        const SizedBox(height: 14),
        LiquidGlass(
          useNative: false,
          radius: 18,
          child: _card(context, [
            _header('기능 표시'),
            _toggle('공휴일', showHolidays, onHolidaysChanged),
            _toggle('음력', showLunar, onLunarChanged),
            _toggle('절기', showSolarTerms, onSolarTermsChanged),
            _toggle('기념일', showAnniversaries, onAnniversariesChanged),
          ]),
        ),
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
      ],
    ),
  );

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
  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
        title: Text(label),
        value: value,
        onChanged: onChanged,
        activeThumbColor: CupertinoColors.activeBlue,
      );
}

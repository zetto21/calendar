import 'package:flutter/material.dart';

import '../services/windows_event_reminders.dart';
import '../widgets/app_dialog.dart';

Future<void> showWindowsReminderSettings(
  BuildContext context, {
  required String account,
  required Future<void> Function() onChanged,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ReminderSettings(account: account, onChanged: onChanged),
);

class _ReminderSettings extends StatefulWidget {
  const _ReminderSettings({required this.account, required this.onChanged});
  final String account;
  final Future<void> Function() onChanged;

  @override
  State<_ReminderSettings> createState() => _ReminderSettingsState();
}

class _ReminderSettingsState extends State<_ReminderSettings> {
  bool? _enabled;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WindowsEventReminders.enabled(widget.account).then((value) {
      if (mounted) setState(() => _enabled = value);
    });
  }

  Future<void> _change(bool value) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await WindowsEventReminders.setEnabled(widget.account, value);
      if (value) {
        await widget.onChanged();
      } else {
        await WindowsEventReminders.clear();
      }
      if (mounted) setState(() => _enabled = value);
    } catch (_) {
      if (mounted) setState(() => _message = '알림 설정을 변경하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await WindowsEventReminders.test();
      if (mounted) {
        setState(
          () => _message = '테스트 알림을 보냈습니다. 보이지 않으면 Windows 알림 설정을 확인해 주세요.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = '테스트 알림을 보내지 못했습니다. Windows 알림 설정을 확인해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: const Text('일정 알림'),
    icon: Icons.notifications_active_outlined,
    maxWidth: 420,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('일정 시작 10분 전 알림'),
          subtitle: const Text('이 PC에서 사용하는 현재 계정에 적용'),
          value: _enabled ?? true,
          onChanged: _enabled == null || _busy ? null : _change,
        ),
        const SizedBox(height: 12),
        const Text('시간이 지정된 일정과 반복 일정에 알림을 보냅니다. 하루 종일 일정은 제외합니다.'),
        const SizedBox(height: 12),
        const Text(
          '앞으로 7일간의 알림을 예약합니다. 예약된 알림은 앱을 닫아도 표시되며, 알림에서 5분 뒤 다시 알림을 선택할 수 있습니다.',
        ),
        const SizedBox(height: 12),
        const Text('앱이 닫혀 있는 동안 다른 기기에서 변경한 일정은 앱을 다시 열면 반영됩니다.'),
        if (_message != null) ...[const SizedBox(height: 12), Text(_message!)],
      ],
    ),
    actions: [
      TextButton(onPressed: _busy ? null : _test, child: const Text('알림 테스트')),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('완료'),
      ),
    ],
  );
}

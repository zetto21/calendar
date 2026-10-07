import 'app_dialog.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/kbo_schedule.dart';

class SubscriptionDialog extends StatefulWidget {
  const SubscriptionDialog({
    super.key,
    required this.existingTeamCodes,
    required this.onToggle,
  });

  final Set<String> existingTeamCodes;
  final Future<void> Function(KboTeam team, bool enabled) onToggle;

  @override
  State<SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends State<SubscriptionDialog> {
  static const _accent = AppDialogStyle.accent;
  late final Set<String> _selected = {...widget.existingTeamCodes};
  String? _pending;
  String? _error;

  Future<void> _toggle(KboTeam team, bool enabled) async {
    if (_pending != null) return;
    setState(() {
      _pending = team.code;
      _error = null;
    });
    try {
      await widget.onToggle(team, enabled);
      if (!mounted) return;
      setState(() {
        if (enabled) {
          _selected.add(team.code);
        } else {
          _selected.remove(team.code);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '${team.displayName} 구독을 변경하지 못했습니다. 다시 시도해 주세요.';
        });
      }
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  Widget _teamRow(KboTeam team, Color foreground) => ConstrainedBox(
    constraints: BoxConstraints(
      minHeight: MediaQuery.sizeOf(context).width < 600 ? 64 : 72,
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/kbo/${team.code}.png',
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            team.displayName,
            style: TextStyle(color: foreground, fontSize: 15),
          ),
        ),
        const SizedBox(width: 10),
        if (_pending == team.code)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 15),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
            ),
          )
        else
          Semantics(
            label: '${team.displayName} 구독',
            child: CupertinoSwitch(
              key: ValueKey('subscription-${team.code}'),
              value: _selected.contains(team.code),
              activeTrackColor: _accent,
              onChanged: _pending == null
                  ? (value) => _toggle(team, value)
                  : null,
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? const Color(0xFFE9E9ED) : const Color(0xFF242427);
    final muted = dark ? const Color(0xFF96969F) : const Color(0xFF73737D);
    final border = dark ? const Color(0xFF333338) : const Color(0xFFE7E7EB);
    return PopScope(
      canPop: _pending == null,
      child: AppDialog(
        title: Text(
          '캘린더 구독하기',
          style: mobile ? const TextStyle(fontSize: 18) : null,
        ),
        icon: mobile ? null : CupertinoIcons.calendar,
        insetPadding: EdgeInsets.symmetric(
          horizontal: mobile ? 12 : 20,
          vertical: mobile ? 16 : 24,
        ),
        contentPadding: mobile
            ? const EdgeInsets.fromLTRB(16, 0, 16, 16)
            : AppDialogStyle.bodyPadding,
        maxHeight: mobile ? MediaQuery.sizeOf(context).height : 700,
        actions: mobile
            ? [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _pending == null
                        ? () => Navigator.of(context).pop()
                        : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('완료'),
                  ),
                ),
              ]
            : const [],
        maxWidth: 880,
        busy: _pending != null,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mobile) ...[
              Row(
                children: [
                  Text('스포츠', style: TextStyle(color: muted, fontSize: 14)),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, size: 16, color: muted),
                  const SizedBox(width: 8),
                  Text('야구', style: TextStyle(color: foreground, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 16),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: foreground, width: 2),
                  ),
                ),
                child: Text(
                  '스포츠',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ),
              Divider(height: 1, color: border),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: foreground,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  '야구',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: dark ? const Color(0xFF202023) : Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Divider(height: 1, color: border),
              const SizedBox(height: 20),
            ],
            Text(
              'KBO',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
            SizedBox(height: mobile ? 6 : 14),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 580) {
                  return Column(
                    children: [
                      for (final team in kboTeams) _teamRow(team, foreground),
                    ],
                  );
                }
                return Column(
                  children: [
                    for (var i = 0; i < kboTeams.length; i += 2)
                      Row(
                        children: [
                          Expanded(child: _teamRow(kboTeams[i], foreground)),
                          const SizedBox(width: 64),
                          Expanded(
                            child: i + 1 < kboTeams.length
                                ? _teamRow(kboTeams[i + 1], foreground)
                                : const SizedBox(),
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: muted, size: 17),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '네이버 스포츠의 경기 일정을 제공합니다. 스위치를 켜면 내 캘린더에 추가됩니다.',
                    style: TextStyle(color: muted, fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

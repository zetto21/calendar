import 'package:flutter/material.dart';

import 'liquid_glass.dart';

Future<void> showKeyboardShortcuts(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) {
    final theme = Theme.of(context);
    const sections = <String, List<(String, String)>>{
      '기본 동작': [
        ('⌘ N / C', '일정 추가'),
        ('⌘ F', '일정 검색'),
        ('⌘ K / /', '명령 검색'),
        ('⌘ R', '일정 새로고침'),
        ('⌘ T / T', '오늘로 이동'),
        ('⌘ ,', '설정 열기'),
      ],
      '보기 전환': [
        ('⌘ 1 / M', '월간'),
        ('⌘ 2 / W', '주간'),
        ('⌘ 3 / D', '일간'),
        ('⌘ 4 / L', '목록'),
      ],
      '이동 및 선택': [
        ('⌘ ← / K', '이전 기간'),
        ('⌘ → / J', '다음 기간'),
        ('← ↑ ↓ →', '월간에서 날짜 선택 이동'),
        ('← / →', '주간·일간에서 이전 / 다음'),
        ('Return', '선택한 날짜에 일정 추가'),
      ],
      '선택한 일정': [
        ('⌘ D', '일정 복제'),
        ('⌥ ← / →', '하루 이전 / 이후로 이동'),
        ('⌥ ↑ / ↓', '1시간 이전 / 이후로 이동'),
        ('⌥ ⇧ ← / →', '1주 이전 / 이후로 이동'),
        ('⌥ ⇧ ↑ / ↓', '15분 이전 / 이후로 이동'),
      ],
      '일정 추가·수정': [('⌘ Return', '저장'), ('Esc', '닫기')],
    };
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: SizedBox(
          width: 520,
          child: LiquidGlass(
            useNative: false,
            radius: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '키보드 단축키',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '⌘ Command · ⌥ Option · ⇧ Shift\n문자 입력 중에는 글자·방향키 단축키가 적용되지 않습니다.\n일정 이동·복제는 마우스로 가리키거나 마지막으로 선택한 일정에 적용됩니다.',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                        for (final section in sections.entries) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 24, bottom: 8),
                            child: Text(
                              section.key,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          for (final shortcut in section.value)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 160,
                                    child: Text(
                                      shortcut.$1,
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurface,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      shortcut.$2,
                                      style: TextStyle(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  },
);

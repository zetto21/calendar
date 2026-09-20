import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A decorative calendar preview for the desktop welcome screen.
class MacosLoginBrand extends StatelessWidget {
  const MacosLoginBrand({super.key, required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month).weekday % 7;
    final days = DateTime(now.year, now.month + 1, 0).day;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: theme.isDark
              ? const [Color(0xFF1B2942), Color(0xFF18202E)]
              : const [Color(0xFFEAF2FF), Color(0xFFF3F5FC)],
        ),
        border: Border(right: BorderSide(color: theme.border)),
      ),
      child: LayoutBuilder(
        builder: (context, viewport) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(48),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (viewport.maxHeight - 96).clamp(0, double.infinity),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '일상 캘린더',
                    style: TextStyle(
                      color: theme.accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '나의 하루를\n차곡차곡.',
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 44,
                      height: 1.22,
                      letterSpacing: -2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '바쁜 일정부터 소중한 약속까지,\n일상의 모든 순간을 한곳에 담아보세요.',
                    style: TextStyle(
                      color: theme.textSecondary,
                      fontSize: 15,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 36),
                  ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: theme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: theme.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${now.year}년 ${now.month}월',
                            style: TextStyle(
                              color: theme.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              for (final day in [
                                '일',
                                '월',
                                '화',
                                '수',
                                '목',
                                '금',
                                '토',
                              ])
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      day,
                                      style: TextStyle(
                                        color: theme.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          for (
                            var week = 0;
                            week < ((first + days) / 7).ceil();
                            week++
                          )
                            Row(
                              children: [
                                for (var weekday = 0; weekday < 7; weekday++)
                                  Expanded(
                                    child: SizedBox(
                                      height: 36,
                                      child: Center(
                                        child: _date(
                                          week * 7 + weekday - first + 1,
                                          days,
                                          now.day,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: theme.accent.withValues(alpha: 0.09),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.wb_sunny_outlined,
                                  color: theme.accent,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    '오늘도 나만의 속도로',
                                    style: TextStyle(
                                      color: theme.accent,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _date(int day, int days, int today) {
    if (day < 1 || day > days) return const SizedBox.shrink();
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: day == today ? theme.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '$day',
        style: TextStyle(
          color: day == today ? Colors.white : theme.text,
          fontSize: 12,
        ),
      ),
    );
  }
}

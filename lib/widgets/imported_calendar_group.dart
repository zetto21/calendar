import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../storage/imported_events.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// A service expands to the actual calendars imported from that service.
class ImportedCalendarGroup extends StatelessWidget {
  const ImportedCalendarGroup({
    super.key,
    required this.theme,
    required this.imports,
    required this.provider,
  });

  final AppTheme theme;
  final ImportedEvents imports;
  final String provider;

  bool get _mac => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  String get label => switch (provider) {
    'kakao' => '톡캘린더',
    'google' => 'Google 캘린더',
    'apple' => 'Apple 캘린더',
    'naver' => '네이버 캘린더',
    'notion' => 'Notion',
    _ => provider,
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: imports,
    builder: (context, _) {
      final calendars = imports.sources[provider] ?? const [];
      if (calendars.isEmpty) return const SizedBox.shrink();
      return Material(
        type: MaterialType.transparency,
        child: ExpansionTile(
          key: PageStorageKey('imported-calendars-$provider'),
          initiallyExpanded: true,
          dense: _mac,
          visualDensity: _mac ? VisualDensity.compact : null,
          maintainState: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: EdgeInsets.only(left: _mac ? 8 : 12, bottom: 4),
          shape: const Border(),
          collapsedShape: const Border(),
          iconColor: theme.textMuted,
          collapsedIconColor: theme.textMuted,
          title: Text(
            label,
            style: TextStyle(
              color: theme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [
            if (provider != 'kakao')
              for (final calendar in calendars) _calendarRow(calendar)
            else ...[
              for (final calendar in calendars.where(
                (item) => item.category == 'primary' || item.category.isEmpty,
              ))
                _calendarRow(calendar),
              for (final group in const {
                'user': '서브 캘린더',
                'shared': '공유 캘린더',
                'subscription': '구독 캘린더',
              }.entries)
                if (calendars.any((item) => item.category == group.key))
                  ExpansionTile(
                    key: PageStorageKey('kakao-${group.key}'),
                    initiallyExpanded: true,
                    dense: _mac,
                    visualDensity: _mac ? VisualDensity.compact : null,
                    maintainState: true,
                    tilePadding: const EdgeInsets.only(left: 24, right: 8),
                    childrenPadding: EdgeInsets.only(left: _mac ? 16 : 8),
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: Text(
                      group.value,
                      style: TextStyle(
                        color: theme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    children: [
                      for (final calendar in calendars.where(
                        (item) => item.category == group.key,
                      ))
                        _calendarRow(calendar),
                    ],
                  ),
            ],
          ],
        ),
      );
    },
  );

  Widget _calendarRow(ImportCalendar calendar) => CheckboxListTile(
    key: ValueKey('$provider|${calendar.id}'),
    dense: true,
    visualDensity: _mac ? VisualDensity.compact : null,
    contentPadding: const EdgeInsets.only(left: 4, right: 12),
    controlAffinity: ListTileControlAffinity.leading,
    activeColor: colorFromHex(calendar.color),
    title: Text(
      calendar.title,
      maxLines: _mac ? 2 : null,
      overflow: _mac ? TextOverflow.ellipsis : null,
      style: TextStyle(color: theme.text, fontSize: 13),
    ),
    subtitle: calendar.nameUnavailable
        ? Text(
            '카카오에서 이름을 제공하지 않는 캘린더',
            style: TextStyle(color: theme.textMuted, fontSize: 11),
          )
        : null,
    value: imports.isVisible(provider, calendar.id),
    onChanged: (value) => imports.setVisible(provider, calendar.id, value!),
  );
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timezone/timezone.dart' as tz;

import '../logic/recurrence.dart';
import '../models/calendar_event.dart';
import '../storage/event_store.dart';
import '../storage/imported_events.dart';
import '../theme/app_theme.dart';
import '../widgets/liquid_glass.dart';
import 'list_view.dart';

class SearchScreen extends StatefulWidget {
  final String rangeFrom, rangeTo;
  final tz.Location deviceZone;
  final ValueChanged<CalendarEvent> onEventPress;

  const SearchScreen({
    super.key,
    required this.rangeFrom,
    required this.rangeTo,
    required this.deviceZone,
    required this.onEventPress,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).brightness == Brightness.dark
        ? darkTheme
        : lightTheme;
    final store = context.watch<EventStore>();
    final imported = context.watch<ImportedEvents?>();
    final query = _controller.text.trim().toLowerCase();
    final terms = query.split(RegExp(r'\s+'));
    final candidates = <String, List<CalendarEvent>>{};
    if (query.isNotEmpty) {
      for (final source in [
        store.events,
        if (imported != null) imported.events,
      ]) {
        for (final entry in source.entries) {
          for (final event in entry.value) {
            final text = [
              event.title,
              event.location ?? '',
              event.description ?? '',
            ].join(' ').toLowerCase();
            if (terms.every(text.contains)) {
              (candidates[entry.key] ??= []).add(event);
            }
          }
        }
      }
    }
    final matches = candidates.isEmpty
        ? <String, List<CalendarEvent>>{}
        : expandEvents(
            candidates,
            widget.rangeFrom,
            widget.rangeTo,
            widget.deviceZone,
          );
    final count = matches.values.fold(
      0,
      (count, events) => count + events.length,
    );

    Widget message(IconData icon, String title, String detail) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: theme.textMuted),
            const SizedBox(height: 18),
            Text(
              title,
              style: TextStyle(
                color: theme.text,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: theme.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      LiquidGlass(
                        radius: 24,
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(
                            CupertinoIcons.chevron_left,
                            color: theme.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '일정 검색',
                        style: TextStyle(
                          color: theme.text,
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  LiquidGlass(
                    radius: 28,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      autofocus: true,
                      style: TextStyle(color: theme.text, fontSize: 16),
                      textInputAction: TextInputAction.search,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _focus.unfocus(),
                      decoration: InputDecoration(
                        hintText: '제목, 장소, 메모 검색',
                        hintStyle: TextStyle(color: theme.textMuted),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 18,
                          horizontal: 20,
                        ),
                        prefixIcon: Icon(
                          CupertinoIcons.search,
                          color: theme.textSecondary,
                        ),
                        suffixIcon: _controller.text.isEmpty
                            ? null
                            : IconButton(
                                icon: Icon(
                                  CupertinoIcons.xmark_circle_fill,
                                  color: theme.textMuted,
                                ),
                                onPressed: () {
                                  setState(_controller.clear);
                                  _focus.requestFocus();
                                },
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (query.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '검색 결과 $count개',
                        style: TextStyle(
                          color: theme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
                    child: query.isEmpty
                        ? message(
                            CupertinoIcons.search,
                            '어떤 일정을 찾으시나요?',
                            '제목이나 장소, 메모를 입력해 주세요',
                          )
                        : count == 0
                        ? message(
                            CupertinoIcons.calendar,
                            '검색 결과가 없습니다',
                            '다른 검색어로 다시 찾아보세요',
                          )
                        : LiquidGlass(
                            radius: 24,
                            child: EventListView(
                              theme: theme,
                              events: matches,
                              showPastEvents: true,
                              onEventPress: (event) {
                                _focus.unfocus();
                                Navigator.of(context).pop();
                                widget.onEventPress(event);
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

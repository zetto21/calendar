import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timezone/timezone.dart' as tz;

import '../logic/recurrence.dart';
import '../models/calendar_event.dart';
import '../storage/event_store.dart';
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).brightness == Brightness.dark
        ? darkTheme
        : lightTheme;
    final store = context.watch<EventStore>();
    final query = _controller.text.trim().toLowerCase();
    // Match stored series before expanding their occurrences. Empty searches
    // show a prompt and need no recurrence calculation at all.
    final candidates = <String, List<CalendarEvent>>{};
    if (query.isNotEmpty) {
      for (final entry in store.events.entries) {
        final matching = entry.value
            .where((event) => event.title.toLowerCase().contains(query))
            .toList();
        if (matching.isNotEmpty) candidates[entry.key] = matching;
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('일정 검색'),
        leading: BackButton(color: theme.text),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: LiquidGlass(
                radius: 20,
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  decoration: InputDecoration(
                    hintText: '일정 제목으로 검색',
                    labelText: '검색어',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '검색어 지우기',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(_controller.clear),
                          ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${widget.rangeFrom} ~ ${widget.rangeTo}',
                  style: TextStyle(color: theme.textMuted, fontSize: 12),
                ),
              ),
            ),
            Expanded(
              child: query.isEmpty
                  ? Center(
                      child: Text(
                        '찾으려는 일정 제목을 입력해 주세요',
                        style: TextStyle(color: theme.textSecondary),
                      ),
                    )
                  : count == 0
                  ? Center(
                      child: Text(
                        '검색 결과가 없습니다',
                        style: TextStyle(color: theme.textSecondary),
                      ),
                    )
                  : EventListView(
                      theme: theme,
                      events: matches,
                      onEventPress: (event) {
                        FocusScope.of(context).unfocus();
                        widget.onEventPress(event);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

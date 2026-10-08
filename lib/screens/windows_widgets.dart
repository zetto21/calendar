import 'dart:async';

import 'package:flutter/material.dart';

import '../native/windows_widgets.dart';

const _modes = {'today': '오늘 일정', 'month': '월간 달력', 'upcoming': '다가오는 일정'};

Future<void> showWindowsWidgets(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Windows 위젯'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '바탕화면 미니 창',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          for (final mode in _modes.entries)
            ListTile(
              leading: Icon(
                mode.key == 'month'
                    ? Icons.calendar_month
                    : Icons.view_agenda_outlined,
              ),
              title: Text(mode.value),
              trailing: const Icon(Icons.open_in_new),
              onTap: () async {
                try {
                  await WindowsWidgets.launch(mode.key);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('미니 창을 열지 못했습니다.')),
                    );
                  }
                }
              },
            ),
          const Divider(height: 28),
          const Text(
            'Windows 공식 위젯',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text('Win+W → 위젯 추가에서 “일상 캘린더”를 선택하세요. 위젯 패키지가 설치되어 있어야 합니다.'),
          const SizedBox(height: 12),
          const Text(
            '앱에서 마지막으로 동기화한 일정을 표시합니다. 앱에서 일정을 수정하면 자동으로 반영됩니다.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('닫기'),
      ),
    ],
  ),
);

class WindowsMiniApp extends StatelessWidget {
  const WindowsMiniApp({super.key, required this.mode});
  final String mode;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff547be8)),
      fontFamily: 'Malgun Gothic',
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff8caaff),
        brightness: Brightness.dark,
      ),
      fontFamily: 'Malgun Gothic',
    ),
    home: _MiniView(mode: _modes.containsKey(mode) ? mode : 'today'),
  );
}

class _MiniView extends StatefulWidget {
  const _MiniView({required this.mode});
  final String mode;
  @override
  State<_MiniView> createState() => _MiniViewState();
}

class _MiniViewState extends State<_MiniView> {
  Timer? _timer;
  Map<String, dynamic> _snapshot = {'signedIn': false, 'events': []};
  bool _pinned = false;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = DateTime.now();
  String? _error;
  bool _reading = false;
  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_reading) return;
    _reading = true;
    try {
      final snapshot = await WindowsWidgets.read();
      if (mounted) {
        setState(() {
          _snapshot = snapshot;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _snapshot = {'signedIn': false, 'events': []};
          _error = '일정을 불러오지 못했습니다.';
        });
      }
    } finally {
      _reading = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _key(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  List<Map<String, dynamic>> get _events {
    if (_snapshot['signedIn'] != true) return [];
    final list = (_snapshot['events'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    list.sort(
      (a, b) => '${a['date']} ${a['time'] ?? ''}'.compareTo(
        '${b['date']} ${b['time'] ?? ''}',
      ),
    );
    return list;
  }

  Future<void> _open() async {
    try {
      await WindowsWidgets.openCalendar();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('캘린더를 열지 못했습니다.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = _key(DateTime.now());
    final events = _events
        .where(
          (e) => widget.mode == 'upcoming'
              ? (e['date'] as String).compareTo(today) >= 0
              : e['date'] == (widget.mode == 'month' ? _key(_selected) : today),
        )
        .take(20)
        .toList();
    final signedIn = _snapshot['signedIn'] == true;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _modes[widget.mode]!,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _pinned ? '항상 위 해제' : '항상 위에 표시',
                    isSelected: _pinned,
                    icon: const Icon(Icons.push_pin_outlined),
                    selectedIcon: const Icon(Icons.push_pin),
                    onPressed: () async {
                      try {
                        await WindowsWidgets.pin(!_pinned);
                        if (mounted) setState(() => _pinned = !_pinned);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('창 고정 상태를 바꾸지 못했습니다.'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                  IconButton(
                    tooltip: '새로고침',
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
                ],
              ),
              if (widget.mode != 'month')
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    '${DateTime.now().month}월 ${DateTime.now().day}일',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              if (widget.mode == 'month') _calendar(),
              Expanded(
                child: !signedIn
                    ? Center(
                        child: Text(
                          _error ?? '캘린더 앱에서 로그인하면\n일정이 여기에 표시됩니다.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : events.isEmpty
                    ? const Center(child: Text('등록된 일정이 없습니다.'))
                    : ListView.separated(
                        itemCount: events.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final event = events[index];
                          final hex = (event['color'] as String? ?? '')
                              .replaceFirst('#', '');
                          final color = hex.length == 6
                              ? Color(
                                  0xff000000 |
                                      (int.tryParse(hex, radix: 16) ??
                                          0x547be8),
                                )
                              : Theme.of(context).colorScheme.primary;
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 3,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        event['title'] as String? ?? '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${widget.mode == 'upcoming' ? '${event['date']} · ' : ''}${event['time'] ?? '하루 종일'}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '앱에서 마지막으로 동기화한 일정',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                  TextButton(onPressed: _open, child: const Text('캘린더 열기')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _calendar() {
    final first = DateTime(_month.year, _month.month);
    final offset = first.weekday % 7;
    final count = DateTime(first.year, first.month + 1, 0).day;
    final occupied = _events.map((e) => e['date']).toSet();
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '이전 달',
              onPressed: () => setState(() {
                _month = DateTime(first.year, first.month - 1);
                _selected = _month;
              }),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${first.year}년 ${first.month}월',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: '다음 달',
              onPressed: () => setState(() {
                _month = DateTime(first.year, first.month + 1);
                _selected = _month;
              }),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(
          children: [
            for (final day in ['일', '월', '화', '수', '목', '금', '토'])
              Expanded(
                child: Text(
                  day,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var week = 0; week < (offset + count + 6) ~/ 7; week++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final day = week * 7 + col - offset + 1;
                      if (day < 1 || day > count) {
                        return const SizedBox(height: 24);
                      }
                      final date = DateTime(first.year, first.month, day);
                      final selected = _key(date) == _key(_selected);
                      final current = _key(date) == _key(DateTime.now());
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => _selected = date),
                        child: Container(
                          height: 24,
                          decoration: BoxDecoration(
                            color: selected
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$day',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: current
                                      ? FontWeight.w800
                                      : FontWeight.normal,
                                ),
                              ),
                              SizedBox(
                                height: 4,
                                child: occupied.contains(_key(date))
                                    ? Icon(
                                        Icons.circle,
                                        size: 3,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        const SizedBox(height: 10),
      ],
    );
  }
}

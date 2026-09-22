/// Notion-Calendar-style quick entry: "내일 오후 3시 팀 회의 1시간" -> event fields.
class QuickEvent {
  final DateTime? date;
  final String? time; // "HH:MM"; null = all-day
  final int duration; // minutes
  final String title;
  final bool hasDate, hasTime;

  const QuickEvent({
    required this.date,
    required this.time,
    required this.duration,
    required this.title,
    required this.hasDate,
    required this.hasTime,
  });
}

const _weekdayChars = '일월화수목금토';

/// Returns null when [input] contains no date, time or duration words.
QuickEvent? parseQuickEvent(String input, DateTime now) {
  var s = ' ${input.trim()} ';
  if (s.trim().isEmpty) return null;
  final today = DateTime(now.year, now.month, now.day);

  String take(RegExp pattern, void Function(RegExpMatch m) onMatch) {
    final match = pattern.firstMatch(s);
    if (match == null) return s;
    onMatch(match);
    return s.replaceRange(match.start, match.end, ' ');
  }

  // --- all day / duration ---
  var allDay = false;
  s = take(RegExp(r'하루\s*종일|종일'), (_) => allDay = true);

  int? duration;
  s = take(RegExp(r'(\d+)\s*시간(?:\s*(\d+)\s*분)?'), (m) {
    duration = int.parse(m[1]!) * 60 + (int.tryParse(m[2] ?? '') ?? 0);
  });
  s = take(RegExp(r'반\s*시간'), (_) => duration = 30);

  // --- time of day ---
  String? time;
  int adjustHour(int hour, String? period) {
    switch (period) {
      case '오후':
      case '저녁':
      case '밤':
        if (period == '밤' && hour == 12) return 0;
        return hour < 12 ? hour + 12 : hour;
      case '오전':
      case '새벽':
      case '아침':
        return hour == 12 ? 0 : hour;
      case '낮':
        return hour < 12 && hour < 7 ? hour + 12 : hour;
      default:
        // Working-hours guess: "3시" means 15:00, "9시" means 09:00.
        return hour >= 1 && hour <= 6 ? hour + 12 : hour;
    }
  }

  String hhmm(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  final colon = RegExp(r'(오전|오후|아침|낮|저녁|밤|새벽)?\s*(\d{1,2}):(\d{2})');
  final korean = RegExp(
    r'(오전|오후|아침|낮|저녁|밤|새벽)?\s*(\d{1,2})\s*시(?!간)(?:\s*(\d{1,2})\s*분|\s*(반))?',
  );
  final english = RegExp(r'(\d{1,2})\s*(am|pm)', caseSensitive: false);
  if (colon.hasMatch(s)) {
    s = take(colon, (m) {
      final h = int.parse(m[2]!);
      if (h < 24) time = hhmm(adjustHourColon(h, m[1]), int.parse(m[3]!));
    });
  } else if (korean.hasMatch(s)) {
    s = take(korean, (m) {
      final h = int.parse(m[2]!);
      final minute = m[4] != null ? 30 : (int.tryParse(m[3] ?? '') ?? 0);
      if (h <= 24 && minute < 60) {
        time = hhmm(adjustHour(h, m[1]) % 24, minute);
      }
    });
  } else if (english.hasMatch(s)) {
    s = take(english, (m) {
      var h = int.parse(m[1]!) % 12;
      if (m[2]!.toLowerCase() == 'pm') h += 12;
      time = hhmm(h, 0);
    });
  }
  s = take(RegExp(r'(\d+)\s*분'), (m) => duration = int.parse(m[1]!));

  // --- date ---
  DateTime? date;
  s = take(RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})'), (m) {
    date = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  });
  if (date == null) {
    s = take(RegExp(r'(?:(\d{4})년\s*)?(\d{1,2})월\s*(\d{1,2})일'), (m) {
      final month = int.parse(m[2]!), day = int.parse(m[3]!);
      var year = int.tryParse(m[1] ?? '') ?? today.year;
      var candidate = DateTime(year, month, day);
      if (m[1] == null && candidate.isBefore(today)) {
        candidate = DateTime(year + 1, month, day);
      }
      date = candidate;
    });
  }
  if (date == null) {
    s = take(RegExp(r'(?<!\d)(\d{1,2})/(\d{1,2})(?!\d)'), (m) {
      var candidate = DateTime(today.year, int.parse(m[1]!), int.parse(m[2]!));
      if (candidate.isBefore(today)) {
        candidate = DateTime(today.year + 1, candidate.month, candidate.day);
      }
      date = candidate;
    });
  }
  if (date == null) {
    final relative = {'오늘': 0, '내일': 1, '모레': 2, '글피': 3};
    s = take(RegExp(r'오늘|내일|모레|글피'), (m) {
      date = today.add(Duration(days: relative[m[0]]!));
    });
  }
  if (date == null) {
    s = take(RegExp(r'(다다음\s*주|다음\s*주|담주|이번\s*주)?\s*([일월화수목금토])요일'), (m) {
      final target = _weekdayChars.indexOf(m[2]!);
      final weekStart = today.subtract(Duration(days: today.weekday % 7));
      final prefix = (m[1] ?? '').replaceAll(RegExp(r'\s'), '');
      if (prefix.isEmpty) {
        final ahead = (target - today.weekday % 7 + 7) % 7;
        date = today.add(Duration(days: ahead));
      } else {
        final weeks = switch (prefix) {
          '이번주' => 0,
          '다다음주' => 2,
          _ => 1,
        };
        date = weekStart.add(Duration(days: weeks * 7 + target));
      }
    });
  }
  if (date == null) {
    s = take(RegExp(r'(?<!\d)(\d{1,2})일(?!\s*간)'), (m) {
      final day = int.parse(m[1]!);
      var candidate = DateTime(today.year, today.month, day);
      if (candidate.isBefore(today)) {
        candidate = DateTime(today.year, today.month + 1, day);
      }
      date = candidate;
    });
  }

  final title = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  final hasDate = date != null;
  final hasTime = time != null;
  if (!hasDate && !hasTime && duration == null && !allDay) return null;

  return QuickEvent(
    date: date ?? (hasTime || allDay || duration != null ? today : null),
    time: allDay ? null : time,
    duration: allDay ? 1440 : (duration ?? 60),
    title: title,
    hasDate: hasDate,
    hasTime: hasTime && !allDay,
  );
}

int adjustHourColon(int hour, String? period) {
  switch (period) {
    case '오후':
    case '저녁':
    case '밤':
      return hour < 12 ? hour + 12 : hour;
    case '오전':
    case '새벽':
    case '아침':
      return hour == 12 ? 0 : hour;
    default:
      return hour;
  }
}

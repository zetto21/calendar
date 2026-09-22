import 'package:flutter_test/flutter_test.dart';

import 'package:calendar_app_flutter/logic/quick_add.dart';

void main() {
  // 2026-09-22 is a Tuesday.
  final now = DateTime(2026, 9, 22, 10);

  test('relative day with a working-hours time and title', () {
    final q = parseQuickEvent('내일 3시 팀 회의', now)!;
    expect(q.date, DateTime(2026, 9, 23));
    expect(q.time, '15:00');
    expect(q.title, '팀 회의');
    expect(q.duration, 60);
  });

  test('explicit period, minutes and duration', () {
    final q = parseQuickEvent('오전 9시 30분 스탠드업 30분', now)!;
    expect(q.time, '09:30');
    expect(q.duration, 30);
    expect(q.title, '스탠드업');
  });

  test('weekday and hours duration', () {
    final q = parseQuickEvent('다음주 금요일 저녁 7시 저녁식사 2시간', now)!;
    expect(q.date, DateTime(2026, 10, 2));
    expect(q.time, '19:00');
    expect(q.duration, 120);
    expect(q.title, '저녁식사');
  });

  test('month/day date only becomes an all-day event', () {
    final q = parseQuickEvent('10월 3일 개천절 휴무', now)!;
    expect(q.date, DateTime(2026, 10, 3));
    expect(q.time, isNull);
    expect(q.title, '개천절 휴무');
  });

  test('plain text is not an event', () {
    expect(parseQuickEvent('회의 준비', now), isNull);
  });

  test('colon time', () {
    final q = parseQuickEvent('오늘 14:30 치과', now)!;
    expect(q.time, '14:30');
    expect(q.title, '치과');
  });
}

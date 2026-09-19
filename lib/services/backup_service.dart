import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/calendar_event.dart';
import '../storage/display_settings.dart';
import '../storage/event_store.dart';

class BackupService {
  BackupService._();
  static const _exportChannel = MethodChannel('calendar_app/file_export');

  /// Creates the portable files before presenting the system save picker.
  static Future<List<String>> exportData(
    EventStore events, {
    ValueChanged<double>? onProgress,
  }) async {
    onProgress?.call(0.05);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final rawEvents = events.exportBackup()['events'] as List<dynamic>;
    final calendarEvents = rawEvents
        .map(
          (value) =>
              CalendarEvent.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList();
    final directory = await getApplicationDocumentsDirectory();
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final icsFile = File('${directory.path}/calendar-backup-$date.ics');
    final csvFile = File('${directory.path}/calendar-backup-$date.csv');
    await icsFile.writeAsString(_toIcs(calendarEvents));
    onProgress?.call(0.50);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await csvFile.writeAsString(_toCsv(calendarEvents));
    onProgress?.call(0.90);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    onProgress?.call(1.0);
    return [icsFile.path, csvFile.path];
  }

  /// Opens Files only after Flutter's progress alert is gone.
  static Future<bool> saveExportedFiles(List<String> paths) async =>
      (await _exportChannel.invokeMethod<bool>('exportFiles', {
        'paths': paths,
      })) ??
      false;

  static String _toIcs(List<CalendarEvent> events) {
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Calendar App//KO',
      'CALSCALE:GREGORIAN',
      ...events.expand((event) {
        final start = _eventStart(event);
        final end = start.add(Duration(minutes: event.duration));
        final allDay = event.isAllDay;
        return [
          'BEGIN:VEVENT',
          'UID:${_escapeIcs(event.uid ?? event.id)}',
          allDay
              ? 'DTSTART;VALUE=DATE:${_icsDate(start)}'
              : 'DTSTART:${_icsDateTime(start)}',
          allDay
              ? 'DTEND;VALUE=DATE:${_icsDate(end)}'
              : 'DTEND:${_icsDateTime(end)}',
          'SUMMARY:${_escapeIcs(event.title)}',
          if (event.location?.isNotEmpty == true)
            'LOCATION:${_escapeIcs(event.location!)}',
          if (event.description?.isNotEmpty == true)
            'DESCRIPTION:${_escapeIcs(event.description!)}',
          if (event.url?.isNotEmpty == true) 'URL:${_escapeIcs(event.url!)}',
          'END:VEVENT',
        ];
      }),
      'END:VCALENDAR',
      '',
    ];
    return lines.join('\r\n');
  }

  static String _toCsv(List<CalendarEvent> events) {
    final rows = <List<String>>[
      [
        'id',
        'date',
        'title',
        'time',
        'durationMinutes',
        'color',
        'location',
        'description',
        'url',
      ],
      ...events.map(
        (event) => [
          event.id,
          event.date,
          event.title,
          event.time ?? '',
          '${event.duration}',
          event.color,
          event.location ?? '',
          event.description ?? '',
          event.url ?? '',
        ],
      ),
    ];
    return '${rows.map((row) => row.map(_escapeCsv).join(',')).join('\r\n')}\r\n';
  }

  static DateTime _eventStart(CalendarEvent event) {
    final date = DateTime.parse(event.date);
    if (event.time == null) return date;
    final parts = event.time!.split(':');
    return DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  static String _icsDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}${value.month.toString().padLeft(2, '0')}${value.day.toString().padLeft(2, '0')}';
  static String _icsDateTime(DateTime value) =>
      '${_icsDate(value)}T${value.hour.toString().padLeft(2, '0')}${value.minute.toString().padLeft(2, '0')}00';
  static String _escapeIcs(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\n', '\\n');
  static String _escapeCsv(String value) => '"${value.replaceAll('"', '""')}"';

  static Future<bool> restoreData(EventStore events) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ics', 'csv', 'json'],
    );
    if (picked.isEmpty) return false;
    final selected = picked.single;
    final bytes = await selected.readAsBytes();
    final content = utf8.decode(bytes, allowMalformed: true);
    final extension =
        (selected.extension ?? selected.name.split('.').last).toLowerCase();

    if (extension == 'ics') {
      await events.restoreBackup(_fromIcs(content));
      return true;
    }
    if (extension == 'csv') {
      await events.restoreBackup(_fromCsv(content));
      return true;
    }

    final decoded = jsonDecode(content);
    if (decoded is! Map || decoded['format'] != 'calendar-backup') {
      throw const FormatException('.ics, .csv 또는 캘린더 백업 파일을 선택해 주세요.');
    }
    final rawEvents = decoded['events'];
    if (rawEvents is! List) throw const FormatException('일정 데이터가 없습니다.');
    await events.restoreBackup(rawEvents);
    final settings = decoded['displaySettings'];
    if (settings is Map) {
      await DisplaySettings.instance.restoreBackup(
        Map<String, dynamic>.from(settings),
      );
    }
    return true;
  }

  static List<Map<String, dynamic>> _fromIcs(String source) {
    final unfolded = source
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\n[ \t]'), '')
        .split('\n');
    final raw = <Map<String, dynamic>>[];
    Map<String, String>? event;
    var index = 0;
    for (final line in unfolded) {
      if (line == 'BEGIN:VEVENT') {
        event = <String, String>{};
      } else if (line == 'END:VEVENT' && event != null) {
        final start = event['DTSTART'];
        if (start != null) {
          final end = event['DTEND'];
          final startValue = _parseIcsDate(start);
          final endValue = end == null ? null : _parseIcsDate(end);
          final isAllDay = start.length == 8;
          raw.add({
            'id':
                event['UID'] ??
                'import-${DateTime.now().microsecondsSinceEpoch}-${index++}',
            'uid': event['UID'],
            'date':
                '${startValue.year.toString().padLeft(4, '0')}-${startValue.month.toString().padLeft(2, '0')}-${startValue.day.toString().padLeft(2, '0')}',
            'title': _unescapeIcs(event['SUMMARY'] ?? '제목 없음'),
            if (!isAllDay)
              'time':
                  '${startValue.hour.toString().padLeft(2, '0')}:${startValue.minute.toString().padLeft(2, '0')}',
            'duration': endValue == null
                ? 60
                : endValue.difference(startValue).inMinutes.clamp(1, 24 * 60),
            'color': '#0A84FF',
            if (event['LOCATION'] != null)
              'location': _unescapeIcs(event['LOCATION']!),
            if (event['DESCRIPTION'] != null)
              'description': _unescapeIcs(event['DESCRIPTION']!),
            if (event['URL'] != null) 'url': _unescapeIcs(event['URL']!),
          });
        }
        event = null;
      } else if (event != null) {
        final separator = line.indexOf(':');
        if (separator > 0) {
          final key = line.substring(0, separator).split(';').first;
          event[key] = line.substring(separator + 1);
        }
      }
    }
    if (raw.isEmpty) throw const FormatException('복원할 일정이 없는 .ics 파일입니다.');
    return raw;
  }

  static DateTime _parseIcsDate(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 8) throw const FormatException('날짜 형식이 올바르지 않습니다.');
    return DateTime(
      int.parse(digits.substring(0, 4)),
      int.parse(digits.substring(4, 6)),
      int.parse(digits.substring(6, 8)),
      digits.length >= 12 ? int.parse(digits.substring(8, 10)) : 0,
      digits.length >= 12 ? int.parse(digits.substring(10, 12)) : 0,
    );
  }

  static String _unescapeIcs(String value) => value
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\,', ',')
      .replaceAll(r'\;', ';')
      .replaceAll(r'\\', r'\');

  static List<Map<String, dynamic>> _fromCsv(String source) {
    final rows = _parseCsv(source);
    if (rows.length < 2) throw const FormatException('복원할 일정이 없는 .csv 파일입니다.');
    final headers = rows.first;
    final required = [
      'id',
      'date',
      'title',
      'time',
      'durationMinutes',
      'color',
    ];
    if (!required.every(headers.contains)) {
      throw const FormatException('캘린더에서 만든 .csv 파일을 선택해 주세요.');
    }
    final raw = <Map<String, dynamic>>[];
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (row.every((value) => value.isEmpty)) continue;
      String field(String name) {
        final index = headers.indexOf(name);
        return index >= 0 && index < row.length ? row[index] : '';
      }

      final date = field('date');
      final title = field('title');
      if (date.isEmpty || title.isEmpty) continue;
      raw.add({
        'id': field('id').isEmpty
            ? 'import-${DateTime.now().microsecondsSinceEpoch}-$rowIndex'
            : field('id'),
        'date': date,
        'title': title,
        if (field('time').isNotEmpty) 'time': field('time'),
        'duration': int.tryParse(field('durationMinutes')) ?? 60,
        'color': field('color').isEmpty ? '#0A84FF' : field('color'),
        if (field('location').isNotEmpty) 'location': field('location'),
        if (field('description').isNotEmpty)
          'description': field('description'),
        if (field('url').isNotEmpty) 'url': field('url'),
      });
    }
    if (raw.isEmpty) throw const FormatException('복원할 일정이 없는 .csv 파일입니다.');
    return raw;
  }

  static List<List<String>> _parseCsv(String source) {
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;
    for (var index = 0; index < source.length; index++) {
      final char = source[index];
      if (char == '"') {
        if (quoted && index + 1 < source.length && source[index + 1] == '"') {
          field.write('"');
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        row.add(field.toString());
        field = StringBuffer();
      } else if ((char == '\n' || char == '\r') && !quoted) {
        if (char == '\r' &&
            index + 1 < source.length &&
            source[index + 1] == '\n') {
          index++;
        }
        row.add(field.toString());
        if (row.any((value) => value.isNotEmpty)) rows.add(row);
        row = <String>[];
        field = StringBuffer();
      } else {
        field.write(char);
      }
    }
    row.add(field.toString());
    if (row.any((value) => value.isNotEmpty)) rows.add(row);
    return rows;
  }
}

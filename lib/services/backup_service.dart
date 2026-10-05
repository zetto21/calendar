import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/calendar_event.dart';
import '../storage/account_preferences.dart';
import '../storage/display_settings.dart';
import '../storage/event_store.dart';

class BackupService {
  BackupService._();
  static const _exportChannel = MethodChannel('calendar_app/file_export');
  static const maxImportBytes = 8 * 1024 * 1024;
  static const _maxExportBytes = 20 * 1024 * 1024;

  /// Creates the portable files before presenting the system save picker.
  static Future<List<String>> exportData(
    EventStore events, {
    ValueChanged<double>? onProgress,
  }) async {
    final generation = events.accountGeneration;
    final rawEvents = events.exportBackup()['events'] as List<dynamic>;
    onProgress?.call(0.05);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (generation != events.accountGeneration) {
      throw StateError('계정이 변경되었습니다. 다시 시도해 주세요.');
    }
    final calendarEvents = rawEvents
        .map(
          (value) =>
              CalendarEvent.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList();
    final temporary = await getTemporaryDirectory();
    final parent = await Directory('${temporary.path}/calendar-exports')
        .create(recursive: true);
    final directory = await parent.createTemp('backup-');
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final icsFile = File('${directory.path}/calendar-backup-$date.ics');
    final csvFile = File('${directory.path}/calendar-backup-$date.csv');
    final ics = _toIcs(calendarEvents);
    final csv = _toCsv(calendarEvents);
    if (utf8.encode(ics).length > _maxExportBytes ||
        utf8.encode(csv).length > _maxExportBytes) {
      await directory.delete(recursive: true);
      throw const FormatException('내보낼 백업 파일이 너무 큽니다.');
    }
    try {
      await icsFile.writeAsString(ics);
      onProgress?.call(0.50);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await csvFile.writeAsString(csv);
      onProgress?.call(0.90);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (generation != events.accountGeneration) {
        throw StateError('계정이 변경되었습니다. 다시 시도해 주세요.');
      }
      onProgress?.call(1.0);
      return [icsFile.path, csvFile.path];
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
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
        'textEncoding',
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
          'apostrophe-v1',
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
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\n', '\\n');
  static bool _isSpreadsheetFormula(String value) =>
      RegExp(r'^[\s\x00-\x1f]*[=+\-@]').hasMatch(value) ||
      value.startsWith('\t') ||
      value.startsWith('\r') ||
      value.startsWith('\n');
  static String _escapeCsv(String value) {
    final safe = _isSpreadsheetFormula(value) ? "'$value" : value;
    return '"${safe.replaceAll('"', '""')}"';
  }

  @visibleForTesting
  static String encodeCsv(List<CalendarEvent> events) => _toCsv(events);

  @visibleForTesting
  static String encodeIcs(List<CalendarEvent> events) => _toIcs(events);

  static Future<bool> restoreData(EventStore events) async {
    final generation = events.accountGeneration;
    final selected = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['ics', 'csv', 'json'],
    );
    if (selected == null) return false;
    final length = selected.lengthSync();
    if (length != null && length > maxImportBytes) {
      throw const FormatException('백업 파일은 8MB까지 복원할 수 있습니다.');
    }
    final bytes = await readBackupBytes(selected.readAsByteStream());
    final content = utf8.decode(bytes);
    final extension = (selected.extension ?? selected.name.split('.').last)
        .toLowerCase();

    await restoreContent(
      events,
      content,
      extension,
      expectedAccountGeneration: generation,
    );
    return true;
  }

  /// Enforce limits while reading, including files with missing/wrong metadata.
  static Future<Uint8List> readBackupBytes(Stream<List<int>> stream) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > maxImportBytes) {
        throw const FormatException('백업 파일은 8MB까지 복원할 수 있습니다.');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  static Future<void> restoreContent(
    EventStore events,
    String content,
    String extension, {
    int? expectedAccountGeneration,
  }) async {
    final generation = expectedAccountGeneration ?? events.accountGeneration;
    final preferencesGeneration = AccountPreferences.instance.accountGeneration;
    if (utf8.encode(content).length > maxImportBytes) {
      throw const FormatException('백업 파일은 8MB까지 복원할 수 있습니다.');
    }
    if (extension == 'ics' || extension == 'csv') {
      await events.restoreBackup(
        extension == 'ics' ? _fromIcs(content) : _fromCsv(content),
        expectedAccountGeneration: generation,
      );
      return;
    }
    if (extension != 'json') {
      throw const FormatException('.ics, .csv 또는 캘린더 백업 파일을 선택해 주세요.');
    }
    _checkJsonNesting(content);

    final decoded = jsonDecode(content);
    if (decoded is! Map || decoded['format'] != 'calendar-backup') {
      throw const FormatException('.ics, .csv 또는 캘린더 백업 파일을 선택해 주세요.');
    }
    final rawEvents = decoded['events'];
    if (rawEvents is! List) throw const FormatException('일정 데이터가 없습니다.');
    await events.restoreBackup(
      rawEvents,
      expectedAccountGeneration: generation,
    );
    final settings = decoded['displaySettings'];
    if (settings is Map) {
      for (final setting in DisplaySetting.values) {
        if (generation != events.accountGeneration ||
            preferencesGeneration !=
                AccountPreferences.instance.accountGeneration) {
          return;
        }
        final value = settings[setting.name];
        if (value is bool) {
          await DisplaySettings.instance.setEnabled(setting, value);
        }
      }
    }
  }

  static void _checkJsonNesting(String source) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (final unit in source.codeUnits) {
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (unit == 92) {
          escaped = true;
        } else if (unit == 34) {
          inString = false;
        }
      } else if (unit == 34) {
        inString = true;
      } else if (unit == 91 || unit == 123) {
        if (++depth > 32) {
          throw const FormatException('백업 데이터가 너무 깊게 중첩되었습니다.');
        }
      } else if (unit == 93 || unit == 125) {
        depth--;
      }
    }
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
      if (line.length > 16 * 1024) {
        throw const FormatException('일정 항목이 너무 큽니다.');
      }
      if (line == 'BEGIN:VEVENT') {
        if (event != null) throw const FormatException('ICS 일정 구조가 올바르지 않습니다.');
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
          if (raw.length > 10000) {
            throw const FormatException('백업 일정은 10,000개까지 복원할 수 있습니다.');
          }
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
    if (event != null) throw const FormatException('ICS 일정이 완성되지 않았습니다.');
    if (raw.isEmpty) throw const FormatException('복원할 일정이 없는 .ics 파일입니다.');
    return raw;
  }

  static DateTime _parseIcsDate(String value) {
    if (!RegExp(r'^\d{8}(?:T\d{6}Z?)?$').hasMatch(value)) {
      throw const FormatException('날짜 형식이 올바르지 않습니다.');
    }
    final date =
        '${value.substring(0, 4)}-${value.substring(4, 6)}-${value.substring(6, 8)}';
    final time = value.length == 8
        ? null
        : '${value.substring(9, 11)}:${value.substring(11, 13)}';
    if (!isValidCalendarDate(date) ||
        (time != null &&
            (!isValidCalendarTime(time) ||
                int.parse(value.substring(13, 15)) > 59))) {
      throw const FormatException('날짜 형식이 올바르지 않습니다.');
    }
    return DateTime(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(4, 6)),
      int.parse(value.substring(6, 8)),
      time == null ? 0 : int.parse(value.substring(9, 11)),
      time == null ? 0 : int.parse(value.substring(11, 13)),
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
    if (!required.every(headers.contains) ||
        headers.toSet().length != headers.length) {
      throw const FormatException('캘린더에서 만든 .csv 파일을 선택해 주세요.');
    }
    final raw = <Map<String, dynamic>>[];
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (row.every((value) => value.isEmpty)) continue;
      String field(String name) {
        final index = headers.indexOf(name);
        final value = index >= 0 && index < row.length ? row[index] : '';
        final encodingIndex = headers.indexOf('textEncoding');
        if (encodingIndex >= 0 &&
            encodingIndex < row.length &&
            row[encodingIndex] == 'apostrophe-v1' &&
            value.startsWith("'") &&
            _isSpreadsheetFormula(value.substring(1))) {
          return value.substring(1);
        }
        return value;
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
      if (raw.length > 10000) {
        throw const FormatException('백업 일정은 10,000개까지 복원할 수 있습니다.');
      }
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
        if (row.length > 32) throw const FormatException('CSV 열이 너무 많습니다.');
        field = StringBuffer();
      } else if ((char == '\n' || char == '\r') && !quoted) {
        if (char == '\r' &&
            index + 1 < source.length &&
            source[index + 1] == '\n') {
          index++;
        }
        row.add(field.toString());
        if (row.any((value) => value.isNotEmpty)) rows.add(row);
        if (rows.length > 10001) throw const FormatException('CSV 행이 너무 많습니다.');
        row = <String>[];
        field = StringBuffer();
      } else {
        field.write(char);
        if (field.length > 16 * 1024) {
          throw const FormatException('CSV 항목이 너무 큽니다.');
        }
      }
    }
    if (quoted) throw const FormatException('CSV 따옴표가 완성되지 않았습니다.');
    row.add(field.toString());
    if (row.any((value) => value.isNotEmpty)) rows.add(row);
    return rows;
  }
}

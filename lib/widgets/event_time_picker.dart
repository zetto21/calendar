import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_dialog.dart';

/// Edits the event date and time range atomically in one dialog.
class EventTimePicker extends StatefulWidget {
  const EventTimePicker({
    super.key,
    required this.start,
    required this.durationMinutes,
    this.selectEnd = false,
  });

  final DateTime start;
  final int durationMinutes;
  final bool selectEnd;

  @override
  State<EventTimePicker> createState() => _EventTimePickerState();
}

class _EventTimePickerState extends State<EventTimePicker> {
  late DateTime _start = widget.start;
  late int _duration = widget.durationMinutes;
  late bool _selectEnd = widget.selectEnd;
  DateTime get _end => _start.add(Duration(minutes: _duration));

  @override
  Widget build(BuildContext context) {
    final selected = _selectEnd ? _end : _start;
    return AppDialog(
      title: const Text('날짜 및 시간'),
      maxWidth: 440,
      maxHeight: MediaQuery.sizeOf(context).height,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CalendarDatePicker(
            initialDate: _start,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
            onDateChanged: (date) => setState(() {
              _start = DateTime(
                date.year,
                date.month,
                date.day,
                _start.hour,
                _start.minute,
              );
            }),
          ),
          CupertinoSlidingSegmentedControl<bool>(
            groupValue: _selectEnd,
            children: {
              false: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '시작 ${TimeOfDay.fromDateTime(_start).format(context)}',
                ),
              ),
              true: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '종료 ${TimeOfDay.fromDateTime(_end).format(context)}',
                ),
              ),
            },
            onValueChanged: (value) {
              if (value != null) setState(() => _selectEnd = value);
            },
          ),
          SizedBox(
            height: 160,
            child: CupertinoDatePicker(
              key: ValueKey(_selectEnd),
              mode: CupertinoDatePickerMode.time,
              initialDateTime: selected,
              use24hFormat: MediaQuery.alwaysUse24HourFormatOf(context),
              onDateTimeChanged: (time) => setState(() {
                if (_selectEnd) {
                  final startMinutes = _start.hour * 60 + _start.minute;
                  var endMinutes = time.hour * 60 + time.minute;
                  if (endMinutes <= startMinutes) endMinutes += 24 * 60;
                  _duration = endMinutes - startMinutes;
                } else {
                  _start = DateTime(
                    _start.year,
                    _start.month,
                    _start.day,
                    time.hour,
                    time.minute,
                  );
                }
              }),
            ),
          ),
          if (_end.day != _start.day ||
              _end.month != _start.month ||
              _end.year != _start.year)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('종료 시간은 다음 날입니다.', textAlign: TextAlign.center),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, (start: _start, duration: _duration)),
          child: const Text('완료'),
        ),
      ],
    );
  }
}

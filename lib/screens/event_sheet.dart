import '../widgets/app_dialog.dart';
import '../widgets/event_time_picker.dart';
import '../widgets/calendar_date_picker.dart';
import '../widgets/calendar_time_picker.dart';
import '../widgets/glass_delete_dialog.dart';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../logic/date_utils.dart' as date_utils;
import '../models/calendar_event.dart';
import '../theme/app_theme.dart';
import '../widgets/liquid_glass.dart';
import '../platform.dart';

/// Core-fields port of components/EventSheet.tsx + EventOptions.tsx +
/// EventDetailFields.tsx: title, location, all-day, start/end date+time,
/// color, recurrence (frequency + until), notes, url. Travel time, invitees,
/// and attachments are Phase 2.
class EventSheet extends StatefulWidget {
  final bool embedded;
  final VoidCallback? onClose;
  final AppTheme theme;
  final CalendarEvent? draft;
  final bool isEditing;
  final DateTime initialDate;
  final String? initialTime;
  final void Function(CalendarEvent event) onSave;
  final Future<void> Function()? onDelete;

  const EventSheet({
    super.key,
    this.embedded = false,
    this.onClose,
    required this.theme,
    required this.draft,
    required this.isEditing,
    required this.initialDate,
    required this.initialTime,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends State<EventSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _locationController;
  late final TextEditingController _urlController;
  late final TextEditingController _descriptionController;
  late DateTime _date;
  late bool _isAllDay;
  late TimeOfDay _startTime;
  late int _durationMinutes;
  late String _color;
  RepeatFrequency? _frequency;
  DateTime? _until;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    final draft = widget.draft;
    _titleController = TextEditingController(text: draft?.title ?? '');
    _locationController = TextEditingController(text: draft?.location ?? '');
    _urlController = TextEditingController(text: draft?.url ?? '');
    _descriptionController = TextEditingController(
      text: draft?.description ?? '',
    );
    _date = draft != null
        ? date_utils.parseDateKey(draft.date)
        : widget.initialDate;
    final time = draft?.time ?? widget.initialTime;
    _isAllDay = time == null;
    _startTime = time != null
        ? TimeOfDay(
            hour: int.parse(time.split(':')[0]),
            minute: int.parse(time.split(':')[1]),
          )
        : TimeOfDay.now();
    _durationMinutes = draft?.duration ?? 60;
    _color = draft?.color ?? colorToHex(palette[0].value);
    _frequency = draft?.recurrence?.frequency;
    _until = draft?.recurrence?.until != null
        ? date_utils.parseDateKey(draft!.recurrence!.until!)
        : null;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _titleController.dispose();
    _locationController.dispose();
    _urlController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  TimeOfDay get _endTime {
    final totalStart = _startTime.hour * 60 + _startTime.minute;
    final wrapped = (totalStart + _durationMinutes) % (24 * 60);
    return TimeOfDay(hour: wrapped ~/ 60, minute: wrapped % 60);
  }

  Future<void> _pickDate() async {
    if (_usesAppleDatePicker) {
      final picked = await _showAppleDatePicker(
        mode: CupertinoDatePickerMode.date,
        initialDateTime: _date,
      );
      if (picked != null) {
        setState(() => _date = DateTime(picked.year, picked.month, picked.day));
      }
      return;
    }
    final picked = await showCalendarDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickStartTime() async {
    if (_usesAppleDatePicker) {
      final picked = await _showAppleDatePicker(
        mode: CupertinoDatePickerMode.time,
        initialDateTime: _dateAt(_startTime),
      );
      if (picked != null) {
        setState(() => _startTime = TimeOfDay.fromDateTime(picked));
      }
      return;
    }
    final picked = await showCalendarTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked == null) return;
    setState(() => _startTime = picked);
  }

  Future<void> _pickDateTimeRange({bool selectEnd = false}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showDialog<({DateTime start, int duration})>(
      context: context,
      builder: (_) => EventTimePicker(
        start: _dateAt(_startTime),
        durationMinutes: _durationMinutes,
        selectEnd: selectEnd,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _startTime = TimeOfDay.fromDateTime(picked.start);
      _durationMinutes = picked.duration;
    });
  }

  Future<void> _pickStartDateTime() async {
    if (!_desktop && !_usesAppleDatePicker) {
      await _pickDateTimeRange();
      return;
    }
    if (_usesAppleDatePicker) {
      final picked = await _showAppleDatePicker(
        mode: CupertinoDatePickerMode.dateAndTime,
        initialDateTime: _dateAt(_startTime),
      );
      if (picked != null) {
        setState(() {
          _date = DateTime(picked.year, picked.month, picked.day);
          _startTime = TimeOfDay.fromDateTime(picked);
        });
      }
      return;
    }
    await _pickStartTime();
  }

  Future<void> _pickEndTime() async {
    if (!_desktop && !_usesAppleDatePicker) {
      await _pickDateTimeRange(selectEnd: true);
      return;
    }
    if (_usesAppleDatePicker) {
      final picked = await _showAppleDatePicker(
        mode: CupertinoDatePickerMode.time,
        initialDateTime: _dateAt(_endTime),
      );
      if (picked == null) return;
      _setEndTime(TimeOfDay.fromDateTime(picked));
      return;
    }
    final picked = await showCalendarTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked == null) return;
    _setEndTime(picked);
  }

  bool get _usesAppleDatePicker =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  DateTime _dateAt(TimeOfDay time) =>
      DateTime(_date.year, _date.month, _date.day, time.hour, time.minute);

  void _setEndTime(TimeOfDay picked) {
    final totalStart = _startTime.hour * 60 + _startTime.minute;
    var totalEnd = picked.hour * 60 + picked.minute;
    if (totalEnd <= totalStart) totalEnd += 24 * 60;
    setState(() => _durationMinutes = totalEnd - totalStart);
  }

  Future<DateTime?> _showAppleDatePicker({
    required CupertinoDatePickerMode mode,
    required DateTime initialDateTime,
  }) async {
    var picked = initialDateTime;
    return showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (sheetContext) => CupertinoPopupSurface(
        blurSigma: 0,
        isSurfacePainted: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: CupertinoColors.systemBackground.resolveFrom(sheetContext),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 270,
              child: Column(
                children: [
                  SizedBox(
                    height: 44,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text('취소'),
                        ),
                        const SizedBox(width: 48),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(picked),
                          child: const Text('완료'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: CupertinoDatePicker(
                      mode: mode,
                      // CupertinoDatePicker is otherwise transparent. Give the
                      // wheel its own opaque system surface so colors from the
                      // calendar behind the sheet cannot bleed through its fade.
                      backgroundColor: CupertinoColors.systemBackground
                          .resolveFrom(sheetContext),
                      initialDateTime: initialDateTime,
                      minimumDate: mode == CupertinoDatePickerMode.time
                          ? null
                          : DateTime(2000),
                      maximumDate: mode == CupertinoDatePickerMode.time
                          ? null
                          : DateTime(2100),
                      use24hFormat: MediaQuery.alwaysUse24HourFormatOf(context),
                      onDateTimeChanged: (value) => picked = value,
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

  Future<void> _pickRepeat() async {
    RepeatFrequency? tempFreq = _frequency;
    DateTime? tempUntil = _until;
    final theme = widget.theme;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => AppDialog(
          title: const Text('반복'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RepeatOptionTile(
                label: '안함',
                selected: tempFreq == null,
                onTap: () => setSheetState(() {
                  tempFreq = null;
                  tempUntil = null;
                }),
                theme: theme,
              ),
              for (final freq in RepeatFrequency.values)
                _RepeatOptionTile(
                  label: _frequencyLabel(freq),
                  selected: tempFreq == freq,
                  onTap: () => setSheetState(() => tempFreq = freq),
                  theme: theme,
                ),
              if (tempFreq != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '반복 종료',
                    style: TextStyle(color: theme.textSecondary),
                  ),
                  trailing: Text(
                    tempUntil != null ? date_utils.toDateKey(tempUntil!) : '없음',
                    style: TextStyle(color: theme.text),
                  ),
                  onTap: () async {
                    final picked = await showCalendarDatePicker(
                      context: sheetContext,
                      initialDate: tempUntil ?? _date,
                      firstDate: _date,
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setSheetState(() => tempUntil = picked);
                    }
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(sheetContext, {
                'freq': tempFreq,
                'until': tempUntil,
              }),
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _frequency = result['freq'] as RepeatFrequency?;
        _until = result['until'] as DateTime?;
      });
    }
  }

  Future<void> _pickColor() async {
    final theme = widget.theme;
    final result = await showDialog<String>(
      context: context,
      builder: (sheetContext) => AppDialog(
        title: const Text('색상'),
        content: Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final entry in palette)
              GestureDetector(
                onTap: () =>
                    Navigator.pop(sheetContext, colorToHex(entry.value)),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: entry.value,
                    shape: BoxShape.circle,
                    border: _color.toUpperCase() == colorToHex(entry.value)
                        ? Border.all(color: theme.text, width: 2)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (result != null) setState(() => _color = result);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => _macGlass
          ? const GlassDeleteDialog()
          : AppDialog(
              title: const Text('일정 삭제'),
              content: const Text('이 일정을 삭제하시겠어요?'),
              actions: [
                AppDialogAction(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('취소'),
                ),
                AppDialogAction(
                  isDestructiveAction: true,
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('삭제'),
                ),
              ],
            ),
    );
    if (confirmed != true) return;
    await widget.onDelete?.call();
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final timeString = _isAllDay
        ? null
        : '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}';
    final event = CalendarEvent(
      id: widget.draft?.id ?? '',
      date: date_utils.toDateKey(_date),
      title: title,
      location: _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
      url: _urlController.text.trim().isEmpty
          ? null
          : _urlController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      time: timeString,
      duration: _isAllDay ? 24 * 60 : _durationMinutes,
      color: _color,
      recurrence: _frequency != null
          ? EventRecurrence(
              frequency: _frequency!,
              until: _until != null ? date_utils.toDateKey(_until!) : null,
            )
          : null,
      systemEventId: widget.draft?.systemEventId,
      systemCalendarId: widget.draft?.systemCalendarId,
      uid: widget.draft?.uid,
      createdAt: widget.draft?.createdAt,
    );
    widget.onSave(event);
  }

  String _shortDateLabel(DateTime d) =>
      '${(d.year % 100).toString().padLeft(2, '0')}. ${d.month}. ${d.day}. '
      '(${date_utils.weekdays[d.weekday % 7]})';

  Widget _tappable({required Widget child, required VoidCallback onTap}) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: child,
      ),
    );
  }

  Widget _rowDivider() {
    return Divider(height: 1, thickness: 1, color: widget.theme.border);
  }

  Widget _iconRow({
    required IconData icon,
    required String label,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final theme = widget.theme;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: theme.textSecondary, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: theme.text, fontSize: 15),
            ),
          ),
          ...?(trailing == null ? null : [trailing]),
        ],
      ),
    );
    return onTap != null ? _tappable(onTap: onTap, child: content) : content;
  }

  Widget _iconFieldRow({
    required IconData icon,
    required TextEditingController controller,
    required String hint,
    int minLines = 1,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    final theme = widget.theme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Icon(icon, color: theme.textSecondary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: CupertinoTextField.borderless(
              controller: controller,
              minLines: minLines,
              maxLines: maxLines,
              keyboardType: keyboardType,
              style: TextStyle(color: theme.text, fontSize: 15),
              padding: const EdgeInsets.symmetric(vertical: 12),
              placeholder: hint,
              placeholderStyle: TextStyle(color: theme.textMuted, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateTimeSection(AppTheme theme) {
    if (_isAllDay) {
      return _tappable(
        onTap: _pickDate,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              const SizedBox(width: 36),
              Text(
                '날짜',
                style: TextStyle(color: theme.textSecondary, fontSize: 13),
              ),
              const Spacer(),
              Text(
                _shortDateLabel(_date),
                style: TextStyle(
                  color: theme.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Stack(
      children: [
        Row(
          children: [
            const SizedBox(width: 36),
            Expanded(child: _timeBlock(_pickStartDateTime, _startTime, theme)),
            Expanded(child: _timeBlock(_pickEndTime, _endTime, theme)),
          ],
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Align(
              // The separator belongs between the two time values, not in the
              // centre of the start/end columns (which include their dates).
              alignment: const Alignment(0, 0.38),
              child: Icon(Icons.chevron_right, color: theme.textMuted),
            ),
          ),
        ),
      ],
    );
  }

  Widget _timeBlock(VoidCallback onTap, TimeOfDay time, AppTheme theme) {
    return _tappable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _shortDateLabel(_date),
              style: TextStyle(color: theme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              time.format(context),
              style: TextStyle(
                color: theme.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.pop(context);
    }
  }

  bool get _desktop => useDesktopLayout;
  bool get _macGlass =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  Widget _glassAction(Widget child) =>
      LiquidGlass(useNative: false, radius: 20, child: child);

  Widget _chip(String label, VoidCallback onTap, {bool strong = false}) {
    final theme = widget.theme;
    final chip = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(_macGlass ? 18 : 6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: _macGlass ? Colors.transparent : theme.bgSecondary,
            borderRadius: BorderRadius.circular(_macGlass ? 18 : 6),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: theme.text,
              fontSize: 13,
              fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
    return _macGlass ? _glassAction(chip) : chip;
  }

  Widget _desktopRow(IconData icon, Widget child, {bool top = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: top
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              child: Padding(
                padding: EdgeInsets.only(top: top ? 8 : 0),
                child: Icon(icon, size: 17, color: widget.theme.textMuted),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      );

  Widget _desktopField(
    IconData icon,
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) => _desktopRow(
    icon,
    TextField(
      controller: controller,
      minLines: 1,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: TextStyle(color: widget.theme.text, fontSize: 14),
      decoration: InputDecoration(hintText: hint),
    ),
    top: maxLines > 1,
  );

  Widget _buildSidebar(BuildContext context) {
    final theme = widget.theme;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_macGlass)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.isEditing ? '일정 편집' : '일정 추가',
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _glassAction(
                  IconButton(
                    tooltip: '닫기',
                    onPressed: _close,
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ),
              ],
            ),
          )
        else
          AppDialogHeader(
            title: Text(widget.isEditing ? '일정 편집' : '일정 추가'),
            onClose: _close,
          ),
        Divider(height: 1, color: theme.border),
        Expanded(
          child: SingleChildScrollView(
            padding: AppDialogStyle.bodyPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _titleController,
                  autofocus: !widget.isEditing,
                  minLines: 1,
                  maxLines: 3,
                  style: TextStyle(color: theme.text, fontSize: 14),
                  decoration: const InputDecoration(hintText: '일정 제목'),
                ),
                const SizedBox(height: 16),
                _desktopRow(
                  CupertinoIcons.calendar,
                  Wrap(
                    spacing: 6,
                    runSpacing: 8,
                    children: [
                      _chip(_shortDateLabel(_date), _pickDate, strong: true),
                      _chip(
                        _isAllDay ? '종일 ✓' : '종일',
                        () => setState(() => _isAllDay = !_isAllDay),
                      ),
                    ],
                  ),
                ),
                if (!_isAllDay) ...[
                  _desktopRow(
                    CupertinoIcons.time,
                    Wrap(
                      spacing: 6,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _chip(_startTime.format(context), _pickStartDateTime),
                        Icon(
                          CupertinoIcons.arrow_right,
                          size: 12,
                          color: theme.textMuted,
                        ),
                        _chip(_endTime.format(context), _pickEndTime),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 28, top: 2, bottom: 8),
                    child: Text(
                      date_utils.formatDurationLabel(_durationMinutes),
                      style: TextStyle(color: theme.textMuted, fontSize: 12),
                    ),
                  ),
                ],
                _desktopRow(
                  CupertinoIcons.repeat,
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _chip(
                      _frequency == null
                          ? '반복 안 함'
                          : _frequencyLabel(_frequency!),
                      _pickRepeat,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: theme.border),
                ),
                _desktopField(
                  CupertinoIcons.location,
                  _locationController,
                  '장소 추가',
                ),
                _desktopField(
                  CupertinoIcons.link,
                  _urlController,
                  'URL 추가',
                  keyboardType: TextInputType.url,
                ),
                _desktopField(
                  CupertinoIcons.text_alignleft,
                  _descriptionController,
                  '설명 추가',
                  maxLines: 5,
                ),
                const SizedBox(height: 12),
                _desktopRow(
                  CupertinoIcons.paintbrush,
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final entry in [
                        ...palette.skip(6).take(6),
                        ...palette.take(6),
                      ])
                        Tooltip(
                          message: entry.name,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => setState(
                              () => _color = colorToHex(entry.value),
                            ),
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: Center(
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: entry.value,
                                    shape: BoxShape.circle,
                                    border:
                                        _color.toUpperCase() ==
                                            colorToHex(entry.value)
                                        ? Border.all(
                                            color: theme.text,
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
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
        Divider(height: 1, color: theme.border),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Row(
              children: [
                if (widget.isEditing && widget.onDelete != null)
                  IconButton(
                    tooltip: '삭제',
                    onPressed: _confirmDelete,
                    icon: const Icon(
                      CupertinoIcons.trash,
                      size: 18,
                      color: CupertinoColors.destructiveRed,
                    ),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _close,
                  child: Text(
                    '취소',
                    style: TextStyle(color: theme.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                if (_macGlass)
                  _glassAction(
                    TextButton(
                      onPressed: _save,
                      style: TextButton.styleFrom(
                        foregroundColor: theme.text,
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      child: const Text('저장'),
                    ),
                  )
                else
                  FilledButton(onPressed: _save, child: const Text('저장')),
              ],
            ),
          ),
        ),
      ],
    );
    if (!_macGlass) {
      return ColoredBox(
        color: AppDialogStyle.background(context),
        child: content,
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: LiquidGlass(useNative: false, radius: 24, child: content),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final theme = widget.theme;
    final swatches = [...palette.skip(6).take(6), ...palette.take(6)];
    final durationLabel = date_utils.formatDurationLabel(_durationMinutes);
    return AppDialog(
      title: Text(widget.isEditing ? '일정 편집' : '일정 추가'),
      maxWidth: 580,
      onClose: _close,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _titleController,
                  autofocus: !widget.isEditing,
                  minLines: 1,
                  maxLines: 3,
                  style: TextStyle(color: theme.text, fontSize: 14),
                  decoration: const InputDecoration(hintText: '일정 제목'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _desktopRow(
            CupertinoIcons.time,
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _chip(_shortDateLabel(_date), _pickDate, strong: true),
                if (!_isAllDay) ...[
                  _chip(_startTime.format(context), _pickStartDateTime),
                  Icon(
                    CupertinoIcons.arrow_right,
                    size: 13,
                    color: theme.textMuted,
                  ),
                  _chip(_endTime.format(context), _pickEndTime),
                  Text(
                    durationLabel,
                    style: TextStyle(color: theme.textMuted, fontSize: 12),
                  ),
                ],
                _chip(
                  _isAllDay ? '종일 ✓' : '종일',
                  () => setState(() => _isAllDay = !_isAllDay),
                ),
              ],
            ),
          ),
          _desktopRow(
            CupertinoIcons.repeat,
            Align(
              alignment: Alignment.centerLeft,
              child: _chip(
                _frequency == null ? '반복 안 함' : _frequencyLabel(_frequency!),
                _pickRepeat,
              ),
            ),
          ),
          _desktopField(CupertinoIcons.location, _locationController, '장소 추가'),
          _desktopField(
            CupertinoIcons.link,
            _urlController,
            'URL 추가',
            keyboardType: TextInputType.url,
          ),
          _desktopField(
            CupertinoIcons.text_alignleft,
            _descriptionController,
            '설명 추가',
            maxLines: 5,
          ),
          _desktopRow(
            CupertinoIcons.paintbrush,
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in swatches)
                  GestureDetector(
                    onTap: () =>
                        setState(() => _color = colorToHex(entry.value)),
                    child: Tooltip(
                      message: entry.name,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: entry.value,
                          shape: BoxShape.circle,
                          border:
                              _color.toUpperCase() == colorToHex(entry.value)
                              ? Border.all(color: theme.text, width: 2)
                              : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (widget.isEditing && widget.onDelete != null)
          TextButton.icon(
            onPressed: _confirmDelete,
            icon: const Icon(CupertinoIcons.trash, size: 16),
            label: const Text('삭제'),
            style: TextButton.styleFrom(foregroundColor: theme.danger),
          ),
        TextButton(onPressed: _close, child: const Text('취소')),
        FilledButton(onPressed: _save, child: const Text('저장')),
      ],
    );
  }

  /// Cmd+Enter saves and Esc closes, even after focus left the text fields
  /// (e.g. after picking a color).
  bool _onKey(KeyEvent event) {
    if (!_desktop || event is! KeyDownEvent || !mounted) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        HardwareKeyboard.instance.isMetaPressed) {
      _save();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_desktop) {
      return Theme(
        data: _macGlass && widget.embedded
            ? AppDialogStyle.theme(context).copyWith(
                inputDecorationTheme: AppDialogStyle.theme(context)
                    .inputDecorationTheme
                    .copyWith(
                      fillColor: widget.theme.text.withValues(alpha: .04),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: widget.theme.text.withValues(alpha: .10),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: widget.theme.text.withValues(alpha: .10),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: widget.theme.accent),
                      ),
                    ),
              )
            : AppDialogStyle.theme(context),
        child: Material(
          type: MaterialType.transparency,
          child: widget.embedded
              ? _buildSidebar(context)
              : _buildDesktop(context),
        ),
      );
    }
    final theme = widget.theme;
    const blue = Color(0xFF3B82F6);
    final media = MediaQuery.of(context);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        bottom: media.viewInsets.bottom == 0,
        child: LiquidGlass(
          // This sheet presents pickers and alerts, so keep the glass effect in
          // Flutter instead of embedding the native platform view underneath it.
          useNative: false,
          radius: 20,
          child: Container(
            decoration: BoxDecoration(
              color: theme.surface.withValues(alpha: 0.72),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(context).colorScheme
                    .copyWith(primary: blue, secondary: blue),
                textSelectionTheme: const TextSelectionThemeData(
                  cursorColor: blue,
                  selectionColor: Color(0x663B82F6),
                  selectionHandleColor: blue,
                ),
              ),
              child: CupertinoTheme(
                data: CupertinoTheme.of(context).copyWith(primaryColor: blue),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(44, 44),
                          onPressed: _close,
                          child: Icon(
                            CupertinoIcons.xmark,
                            color: theme.text,
                            size: 26,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '일정',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.text,
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (widget.isEditing && widget.onDelete != null)
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(44, 44),
                            onPressed: _confirmDelete,
                            child: Icon(
                              CupertinoIcons.trash,
                              color: CupertinoColors.destructiveRed,
                              size: 26,
                            ),
                          ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(44, 44),
                          onPressed: _save,
                          child: Icon(
                            CupertinoIcons.check_mark,
                            color: theme.text,
                            size: 27,
                          ),
                        ),
                      ],
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: _pickColor,
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: colorFromHex(_color),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: CupertinoTextField.borderless(
                                    controller: _titleController,
                                    autofocus: !widget.isEditing,
                                    style: TextStyle(
                                      color: theme.text,
                                      fontSize: 20,
                                    ),
                                    placeholder: '일정을 입력하세요.',
                                    placeholderStyle: TextStyle(
                                      color: theme.textMuted,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 28),
                            _iconRow(
                              icon: Icons.access_time_rounded,
                              label: '종일',
                              trailing: CupertinoSwitch(
                                value: _isAllDay,
                                onChanged: (value) =>
                                    setState(() => _isAllDay = value),
                              ),
                            ),
                            _dateTimeSection(theme),
                            _rowDivider(),
                            _iconRow(
                              icon: Icons.repeat,
                              label: '반복',
                              onTap: _pickRepeat,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_frequency != null)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: Text(
                                        _frequencyLabel(_frequency!),
                                        style: TextStyle(
                                          color: theme.textSecondary,
                                        ),
                                      ),
                                    ),
                                  Icon(
                                    Icons.chevron_right,
                                    color: theme.textMuted,
                                  ),
                                ],
                              ),
                            ),
                            _rowDivider(),
                            _iconFieldRow(
                              icon: Icons.location_on_outlined,
                              controller: _locationController,
                              hint: '장소',
                            ),
                            _rowDivider(),
                            _iconFieldRow(
                              icon: Icons.notes,
                              controller: _descriptionController,
                              hint: '설명',
                              minLines: 2,
                              maxLines: 4,
                            ),
                            _rowDivider(),
                            _iconFieldRow(
                              icon: Icons.link,
                              controller: _urlController,
                              hint: 'URL',
                              keyboardType: TextInputType.url,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _frequencyLabel(RepeatFrequency freq) {
    switch (freq) {
      case RepeatFrequency.daily:
        return '매일';
      case RepeatFrequency.weekly:
        return '매주';
      case RepeatFrequency.biweekly:
        return '격주';
      case RepeatFrequency.monthly:
        return '매월';
      case RepeatFrequency.yearly:
        return '매년';
    }
  }
}

class _RepeatOptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppTheme theme;
  const _RepeatOptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: theme.text, fontSize: 15),
                ),
              ),
              if (selected) Icon(Icons.check, color: theme.accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

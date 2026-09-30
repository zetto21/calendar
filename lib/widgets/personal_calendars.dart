import 'app_dialog.dart';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PersonalCalendar {
  const PersonalCalendar({
    required this.id,
    required this.title,
    required this.color,
  });
  final String id;
  final String title;
  final String color;

  static const initial = PersonalCalendar(
    id: 'personal',
    title: '내 캘린더',
    color: '#3B82F6',
  );

  factory PersonalCalendar.fromJson(Map<String, dynamic> json) =>
      PersonalCalendar(
        id: json['id'] as String,
        title: json['title'] as String,
        color: json['color'] as String,
      );

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'color': color};
}

class PersonalCalendars extends StatelessWidget {
  const PersonalCalendars({
    super.key,
    required this.calendars,
    required this.onSave,
    required this.onDelete,
    required this.personalVisible,
    required this.onPersonalVisibilityChanged,
  });
  final List<PersonalCalendar> calendars;
  final Future<void> Function(PersonalCalendar) onSave;
  final Future<void> Function(PersonalCalendar) onDelete;
  final bool personalVisible;
  final ValueChanged<bool> onPersonalVisibilityChanged;

  Future<void> _edit(BuildContext context, [PersonalCalendar? calendar]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CalendarEditor(calendar: calendar, onSave: onSave),
    );
  }

  Future<void> _showMenu(
    BuildContext context,
    PersonalCalendar calendar,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = overlay.globalToLocal(globalPosition);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromSize(position & Size.zero, overlay.size),
      color: AppDialogStyle.background(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppDialogStyle.border(context)),
      ),
      items: [
        const PopupMenuItem(value: 'edit', child: Text('수정')),
        PopupMenuItem(
          value: 'delete',
          enabled: calendar.id != 'personal',
          child: Text(
            calendar.id == 'personal' ? '삭제 불가 · 기본 캘린더' : '삭제',
            style: calendar.id == 'personal'
                ? null
                : TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
    if (!context.mounted) return;
    if (action == 'edit') {
      await _edit(context, calendar);
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: const Text('캘린더 삭제'),
          content: Text('‘${calendar.title}’ 캘린더를 목록에서 삭제할까요?'),
          actions: [
            TextButton(
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
      if (confirmed != true || !context.mounted) return;
      try {
        await onDelete(calendar);
      } catch (_) {
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AppDialog(
            title: const Text('캘린더 삭제 실패'),
            content: const Text('삭제하지 못했습니다. 다시 시도해 주세요.'),
            actions: [
              AppDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final calendar in calendars)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPressStart: (details) =>
              _showMenu(context, calendar, details.globalPosition),
          onSecondaryTapDown: (details) =>
              _showMenu(context, calendar, details.globalPosition),
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 12, right: 4),
            leading: calendar.id == 'personal'
                ? Checkbox(
                    value: personalVisible,
                    activeColor: colorFromHex(calendar.color),
                    onChanged: (value) => onPersonalVisibilityChanged(value!),
                  )
                : Icon(
                    Icons.circle,
                    color: colorFromHex(calendar.color),
                    size: 16,
                  ),
            title: Text(
              calendar.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      ListTile(
        dense: true,
        leading: const Icon(Icons.add, size: 20),
        title: const Text('캘린더 추가', style: TextStyle(fontSize: 13)),
        onTap: () => _edit(context),
      ),
    ],
  );
}

class _CalendarEditor extends StatefulWidget {
  const _CalendarEditor({this.calendar, required this.onSave});
  final PersonalCalendar? calendar;
  final Future<void> Function(PersonalCalendar) onSave;
  @override
  State<_CalendarEditor> createState() => _CalendarEditorState();
}

class _CalendarEditorState extends State<_CalendarEditor> {
  late final _title = TextEditingController(text: widget.calendar?.title ?? '');
  late String _color = widget.calendar?.color ?? '#3B82F6';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _title.text.trim().isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        PersonalCalendar(
          id:
              widget.calendar?.id ??
              'personal-${DateTime.now().microsecondsSinceEpoch}',
          title: _title.text.trim(),
          color: _color,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '저장하지 못했습니다. 다시 시도해 주세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selectedColor = colorFromHex(_color);
    final selectedName = palette
        .firstWhere(
          (item) => colorToHex(item.value) == _color,
          orElse: () => palette[6],
        )
        .name;
    return PopScope(
      canPop: !_saving,
      child: AppDialog(
        title: Text(widget.calendar == null ? '캘린더 추가' : '캘린더 편집'),
        icon: Icons.calendar_today_outlined,
        busy: _saving,
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: selectedColor.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selectedColor.withValues(alpha: .2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: selectedColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.calendar_month_rounded,
                          color:
                              ThemeData.estimateBrightnessForColor(
                                    selectedColor,
                                  ) ==
                                  Brightness.light
                              ? Colors.black87
                              : Colors.white,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _title.text.trim().isEmpty
                                  ? '새 캘린더'
                                  : _title.text.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              selectedName,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '제목',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _title,
                  autofocus: true,
                  enabled: !_saving,
                  maxLength: 50,
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(hintText: '예: 개인, 업무, 가족'),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 12),
                const Text(
                  '색상',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                for (var group = 0; group < 3; group++) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      ['진한 색상', '기본 색상', '연한 색상'][group],
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final color in palette.skip(group * 6).take(6))
                        Semantics(
                          selected: _color == colorToHex(color.value),
                          child: Tooltip(
                            message: color.name,
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: InkResponse(
                                radius: 22,
                                onTap: _saving
                                    ? null
                                    : () => setState(
                                        () => _color = colorToHex(color.value),
                                      ),
                                child: Center(
                                  child: AnimatedContainer(
                                    duration:
                                        MediaQuery.disableAnimationsOf(context)
                                        ? Duration.zero
                                        : const Duration(milliseconds: 150),
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: color.value,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: _color == colorToHex(color.value)
                                            ? colors.onSurface
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: _color == colorToHex(color.value)
                                        ? Icon(
                                            Icons.check_rounded,
                                            size: 18,
                                            color:
                                                ThemeData.estimateBrightnessForColor(
                                                      color.value,
                                                    ) ==
                                                    Brightness.light
                                                ? Colors.black87
                                                : Colors.white,
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
                  if (group < 2) const SizedBox(height: 8),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: TextStyle(color: colors.error)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: _saving || _title.text.trim().isEmpty ? null : _save,
            child: Text(_saving ? '저장 중…' : '저장'),
          ),
        ],
      ),
    );
  }
}

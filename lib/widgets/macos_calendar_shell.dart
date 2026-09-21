import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/date_utils.dart' as dates;
import '../models/calendar_event.dart';
import '../theme/app_theme.dart';

class MacosCalendarShell extends StatelessWidget {
  const MacosCalendarShell({
    super.key,
    required this.theme,
    required this.title,
    required this.account,
    this.userName = '',
    required this.view,
    required this.onViewChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onCreate,
    required this.onSearch,
    required this.onManage,
    required this.child,
    this.selectedDate,
    this.onDateSelected,
    this.calendarControls = const [],
    this.featureControls = const [],
    this.importedControls = const [],
    this.onConnect,
    this.onSettings,
  });
  final AppTheme theme;
  final String title, account, userName;
  final ViewMode view;
  final ValueChanged<ViewMode> onViewChanged;
  final VoidCallback onPrevious, onNext, onToday, onCreate, onSearch, onManage;
  final VoidCallback? onConnect, onSettings;
  final DateTime? selectedDate;
  final ValueChanged<DateTime>? onDateSelected;
  final List<Widget> calendarControls;
  final List<Widget> featureControls;
  final List<Widget> importedControls;
  final Widget child;
  static const labels = {
    ViewMode.month: '월간',
    ViewMode.week: '주간',
    ViewMode.day: '일간',
    ViewMode.list: '목록',
  };

  Widget _icon(String tooltip, IconData icon, VoidCallback action) =>
      IconButton(
        tooltip: tooltip,
        onPressed: action,
        style: IconButton.styleFrom(
          minimumSize: const Size(32, 32),
          padding: const EdgeInsets.all(6),
        ),
        icon: Icon(icon, size: 18, color: theme.text),
      );

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
    child: Text(
      title,
      style: TextStyle(
        color: theme.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  List<Widget> _displayControls({bool dialog = false}) => [
    _sectionTitle('표시할 캘린더'),
    for (final control in calendarControls)
      if (dialog && control is CheckboxListTile)
        _CalendarToggle(control: control)
      else
        control,
    if (calendarControls.isEmpty)
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: Icon(CupertinoIcons.calendar, color: theme.accent, size: 18),
        title: const Text('내 일정'),
        onTap: () => onViewChanged(ViewMode.month),
      ),
    if (importedControls.isNotEmpty) ...[
      const SizedBox(height: 8),
      for (final control in importedControls)
        if (dialog && control is CheckboxListTile)
          _CalendarToggle(control: control)
        else
          control,
    ],
    if (featureControls.isNotEmpty) ...[
      const SizedBox(height: 8),
      _sectionTitle('기능 표시'),
      for (final control in featureControls)
        if (dialog && control is CheckboxListTile)
          _CalendarToggle(control: control)
        else
          control,
    ],
  ];

  void _showCalendars(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: theme.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360, maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '내 캘린더',
                        style: TextStyle(
                          color: theme.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _icon(
                      '닫기',
                      CupertinoIcons.xmark,
                      () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _displayControls(dialog: true),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    (onConnect ?? onManage)();
                  },
                  icon: const Icon(CupertinoIcons.add, size: 18),
                  label: const Text('캘린더 연결'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _views() => Container(
    decoration: BoxDecoration(
      color: theme.bgSecondary,
      border: Border.all(color: theme.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final mode in labels.keys)
            Semantics(
              selected: view == mode,
              child: Tooltip(
                message:
                    '${labels[mode]!} · ⌘${labels.keys.toList().indexOf(mode) + 1}',
                child: InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: () => onViewChanged(mode),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    alignment: Alignment.center,
                    width: 48,
                    height: 28,
                    decoration: BoxDecoration(
                      color: view == mode ? theme.text : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      labels[mode]!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: view == mode
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: view == mode ? theme.bg : theme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _sidebar() {
    final date = selectedDate ?? DateTime.now();
    final cells = dates.getMonthMatrix(date.year, date.month - 1);
    return Container(
      key: const ValueKey('macos-calendar-sidebar'),
      width: 248,
      decoration: BoxDecoration(
        color: theme.bgSecondary,
        border: Border(right: BorderSide(color: theme.border)),
      ),
      child: Material(
        color: theme.bgSecondary,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      userName.isEmpty ? '캘린더' : '$userName의 캘린더',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _icon('캘린더 연결', CupertinoIcons.add, onConnect ?? onManage),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Text(
                      account,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: theme.textMuted, fontSize: 11),
                    ),
                  ),
                  ..._displayControls(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    dates.formatMonthTitle(date),
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final label in dates.weekdays)
                        Expanded(
                          child: Center(
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.textMuted,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 7,
                    mainAxisExtent: 25,
                    children: [
                      for (final cell in cells)
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => onDateSelected?.call(cell.date),
                          child: Center(
                            child: Container(
                              width: 23,
                              height: 23,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: dates.isSameDay(cell.date, date)
                                    ? theme.border
                                    : null,
                              ),
                              child: Text(
                                '${cell.date.day}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: dates.isSameDay(cell.date, date)
                                      ? theme.text
                                      : theme.text.withValues(
                                          alpha: cell.inMonth ? 1 : 0.3,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: const Icon(CupertinoIcons.gear, size: 18),
              title: const Text('설정', style: TextStyle(fontSize: 12)),
              onTap: onSettings ?? onManage,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.digit1, meta: true): () =>
          onViewChanged(ViewMode.month),
      const SingleActivator(LogicalKeyboardKey.digit2, meta: true): () =>
          onViewChanged(ViewMode.week),
      const SingleActivator(LogicalKeyboardKey.digit3, meta: true): () =>
          onViewChanged(ViewMode.day),
      const SingleActivator(LogicalKeyboardKey.digit4, meta: true): () =>
          onViewChanged(ViewMode.list),
      const SingleActivator(LogicalKeyboardKey.keyN, meta: true): onCreate,
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true): onSearch,
      const SingleActivator(LogicalKeyboardKey.keyT, meta: true): onToday,
      const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true):
          onPrevious,
      const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true): onNext,
    },
    child: Theme(
      data: Theme.of(context).copyWith(
        visualDensity: VisualDensity.compact,
        listTileTheme: Theme.of(context).listTileTheme.copyWith(
          dense: true,
          minVerticalPadding: 4,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final sidebar = constraints.maxWidth >= 1000;
            return ColoredBox(
              color: theme.bg,
              child: Row(
                children: [
                  if (sidebar) _sidebar(),
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: theme.bgSecondary,
                            border: Border(
                              bottom: BorderSide(color: theme.border),
                            ),
                          ),
                          child: Row(
                            children: [
                              if (!sidebar)
                                _icon(
                                  '캘린더 표시',
                                  CupertinoIcons.sidebar_left,
                                  () => _showCalendars(context),
                                ),
                              _icon('일정 추가 · ⌘N', CupertinoIcons.add, onCreate),
                              const Spacer(),
                              _views(),
                              const Spacer(),
                              _icon(
                                '일정 검색 · ⌘F',
                                CupertinoIcons.search,
                                onSearch,
                              ),
                              if (!sidebar)
                                _icon(
                                  '설정',
                                  CupertinoIcons.gear,
                                  onSettings ?? onManage,
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: theme.text,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.7,
                                  ),
                                ),
                              ),
                              _icon(
                                '이전 · ⌘←',
                                CupertinoIcons.chevron_left,
                                onPrevious,
                              ),
                              TextButton(
                                onPressed: onToday,
                                style: TextButton.styleFrom(
                                  foregroundColor: theme.text,
                                ),
                                child: const Text('오늘'),
                              ),
                              _icon(
                                '다음 · ⌘→',
                                CupertinoIcons.chevron_right,
                                onNext,
                              ),
                            ],
                          ),
                        ),
                        Expanded(child: child),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _CalendarToggle extends StatefulWidget {
  const _CalendarToggle({required this.control});
  final CheckboxListTile control;

  @override
  State<_CalendarToggle> createState() => _CalendarToggleState();
}

class _CalendarToggleState extends State<_CalendarToggle> {
  late bool? value = widget.control.value;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    dense: true,
    controlAffinity: ListTileControlAffinity.leading,
    title: widget.control.title,
    activeColor: widget.control.activeColor,
    value: value,
    onChanged: widget.control.onChanged == null
        ? null
        : (next) {
            widget.control.onChanged!(next);
            setState(() => value = next);
          },
  );
}

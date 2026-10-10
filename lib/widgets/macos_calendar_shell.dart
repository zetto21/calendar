import 'app_dialog.dart';
import 'liquid_glass.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/date_utils.dart' as dates;
import '../models/calendar_event.dart';
import '../platform.dart';
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
    this.visibleDays,
    this.onDateSelected,
    this.calendarControls = const [],
    this.featureControls = const [],
    this.importedControls = const [],
    this.subscriptionControls = const [],
    this.onConnect,
    this.onSettings,
    this.onNavigate,
    this.onPalette,
    this.onActivate,
    this.onNudge,
    this.onDuplicate,
    this.onRefresh,
    this.eventEditorOpen = false,
  });
  final AppTheme theme;
  final String title, account, userName;
  final ViewMode view;
  final ValueChanged<ViewMode> onViewChanged;
  final VoidCallback onPrevious, onNext, onToday, onCreate, onSearch, onManage;
  final VoidCallback? onConnect,
      onSettings,
      onActivate,
      onDuplicate,
      onPalette,
      onRefresh;
  final bool eventEditorOpen;
  final void Function(int dx, int dy)? onNavigate;
  final void Function(int days, int minutes)? onNudge;
  final DateTime? selectedDate;
  final List<DateTime>? visibleDays;
  final ValueChanged<DateTime>? onDateSelected;
  final List<Widget> calendarControls;
  final List<Widget> featureControls;
  final List<Widget> importedControls;
  final List<Widget> subscriptionControls;
  final Widget child;
  static const labels = {
    ViewMode.month: '월간',
    ViewMode.week: '주간',
    ViewMode.day: '일간',
    ViewMode.list: '목록',
  };

  Widget _icon(String tooltip, IconData icon, VoidCallback action) =>
      LiquidGlass(
        useNative: false,
        radius: 16,
        child: IconButton(
          tooltip: tooltip,
          onPressed: action,
          style: IconButton.styleFrom(
            minimumSize: const Size(32, 32),
            padding: const EdgeInsets.all(6),
          ),
          icon: Icon(icon, size: 18, color: theme.text),
        ),
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
    _sectionTitle('내 캘린더'),
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
    if (subscriptionControls.isNotEmpty) ...[
      const SizedBox(height: 8),
      _sectionTitle('구독'),
      for (final control in subscriptionControls)
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
      builder: (context) => AppDialog(
        title: const Text('내 캘린더'),
        icon: CupertinoIcons.calendar,
        maxWidth: 400,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: _displayControls(dialog: true),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              (onSettings ?? onManage)();
            },
            icon: const Icon(CupertinoIcons.gear, size: 18),
            label: const Text('설정'),
          ),
        ],
      ),
    );
  }

  Widget _views() => LiquidGlass(
    useNative: false,
    radius: 18,
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final mode in labels.keys)
            Semantics(
              selected: view == mode,
              child: Tooltip(
                message: labels[mode]!,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onViewChanged(mode),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    alignment: Alignment.center,
                    width: 48,
                    height: 28,
                    decoration: BoxDecoration(
                      color: view == mode ? theme.text : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
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

  Widget _miniCalendarDay(dates.MonthCell cell, DateTime anchor) {
    final focused = dates.isSameDay(cell.date, anchor);
    final today = dates.isSameDay(cell.date, DateTime.now());
    final visible = visibleDays != null
        ? visibleDays!.any((day) => dates.isSameDay(day, cell.date))
        : view == ViewMode.week
        ? dates.isSameDay(
            dates.startOfWeek(cell.date),
            dates.startOfWeek(anchor),
          )
        : focused;
    final band = visible && view == ViewMode.week;
    final radius = BorderRadius.horizontal(
      left: Radius.circular(
        cell.date.weekday == DateTime.sunday ||
                (visibleDays != null &&
                    dates.isSameDay(cell.date, visibleDays!.first))
            ? 12
            : 0,
      ),
      right: Radius.circular(
        cell.date.weekday == DateTime.saturday ||
                (visibleDays != null &&
                    dates.isSameDay(cell.date, visibleDays!.last))
            ? 12
            : 0,
      ),
    );
    return Semantics(
      key: ValueKey('mini-calendar-${dates.toDateKey(cell.date)}'),
      selected: visible,
      button: true,
      label: '${cell.date.year}년 ${cell.date.month}월 ${cell.date.day}일',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onDateSelected?.call(cell.date),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: band
                ? theme.accent.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: radius,
          ),
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 23,
            height: 23,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: focused ? theme.accent : Colors.transparent,
              border: today && !focused
                  ? Border.all(color: theme.accent)
                  : null,
            ),
            child: Text(
              '${cell.date.day}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: visible || today
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: focused
                    ? Colors.white
                    : visible || today
                    ? theme.accent.withValues(alpha: cell.inMonth ? 1 : 0.5)
                    : theme.text.withValues(alpha: cell.inMonth ? 1 : 0.3),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sidebar({bool showCreate = true}) {
    final date = selectedDate ?? DateTime.now();
    final cells = dates.getMonthMatrix(date.year, date.month - 1);
    // Always include the next month's first week, even in six-row months.
    var lastRequired = DateTime(date.year, date.month + 1, 7);
    if (visibleDays != null) {
      for (final day in visibleDays!) {
        if (day.isAfter(lastRequired)) lastRequired = day;
      }
    }
    while (cells.length < 42 ||
        cells.last.date.isBefore(lastRequired) ||
        cells.length % 7 != 0) {
      final next = dates.addDays(cells.last.date, 1);
      cells.add(
        dates.MonthCell(
          next,
          next.month == date.month && next.year == date.year,
        ),
      );
    }
    return Container(
      key: const ValueKey('macos-calendar-sidebar'),
      width: 248,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: LiquidGlass(
        useNative: false,
        radius: 24,
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
                  if (showCreate) ...[
                    _icon('일정 추가', CupertinoIcons.add, onCreate),
                    const SizedBox(width: 8),
                  ],
                  _icon('일정 검색', CupertinoIcons.search, onSearch),
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
                      for (final cell in cells) _miniCalendarDay(cell, date),
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

  /// Whether the focused widget is a text input. Single-letter shortcuts
  /// below must stand down while typing, or every matching keystroke (e.g.
  /// "c" while naming an event) fires the shortcut instead of the letter.
  ///
  /// `primaryFocus.context` is the `Focus` widget `EditableText` wraps its
  /// own `FocusNode` in internally — it is never the `EditableText` widget
  /// itself, so checking `context.widget is EditableText` never matches.
  /// Walking up for an `EditableText` ancestor instead does.
  static bool _isEditingText() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  static VoidCallback _unlessTyping(VoidCallback action) => () {
    if (!_isEditingText()) action();
  };

  static VoidCallback? _unlessTypingOrNull(VoidCallback? action) =>
      action == null ? null : _unlessTyping(action);

  static SingleActivator _primaryShortcut(LogicalKeyboardKey key) =>
      SingleActivator(
        key,
        control: useControlShortcuts,
        meta: !useControlShortcuts,
      );

  Map<ShortcutActivator, VoidCallback> get _navigationBindings => {
    if (onNavigate != null) ...{
      const _CalendarNavigationActivator(LogicalKeyboardKey.arrowLeft):
          _unlessTyping(() => onNavigate!(-1, 0)),
      const _CalendarNavigationActivator(LogicalKeyboardKey.arrowRight):
          _unlessTyping(() => onNavigate!(1, 0)),
      const _CalendarNavigationActivator(LogicalKeyboardKey.arrowUp):
          _unlessTyping(() => onNavigate!(0, -1)),
      const _CalendarNavigationActivator(LogicalKeyboardKey.arrowDown):
          _unlessTyping(() => onNavigate!(0, 1)),
    },
  };

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: eventEditorOpen
        ? _navigationBindings
        : {
            _primaryShortcut(LogicalKeyboardKey.digit1): () =>
                onViewChanged(ViewMode.month),
            _primaryShortcut(LogicalKeyboardKey.digit2): () =>
                onViewChanged(ViewMode.week),
            _primaryShortcut(LogicalKeyboardKey.digit3): () =>
                onViewChanged(ViewMode.day),
            _primaryShortcut(LogicalKeyboardKey.digit4): () =>
                onViewChanged(ViewMode.list),
            _primaryShortcut(LogicalKeyboardKey.keyN): onCreate,
            _primaryShortcut(LogicalKeyboardKey.keyK): ?_unlessTypingOrNull(
              onPalette,
            ),
            const SingleActivator(LogicalKeyboardKey.slash):
                ?_unlessTypingOrNull(onPalette),
            const SingleActivator(LogicalKeyboardKey.keyT): _unlessTyping(
              onToday,
            ),
            const SingleActivator(LogicalKeyboardKey.keyJ): _unlessTyping(
              onNext,
            ),
            const SingleActivator(LogicalKeyboardKey.keyK): _unlessTyping(
              onPrevious,
            ),
            const SingleActivator(LogicalKeyboardKey.keyC): _unlessTyping(
              onCreate,
            ),
            const SingleActivator(LogicalKeyboardKey.keyM): _unlessTyping(
              () => onViewChanged(ViewMode.month),
            ),
            const SingleActivator(LogicalKeyboardKey.keyW): _unlessTyping(
              () => onViewChanged(ViewMode.week),
            ),
            const SingleActivator(LogicalKeyboardKey.keyD): _unlessTyping(
              () => onViewChanged(ViewMode.day),
            ),
            const SingleActivator(LogicalKeyboardKey.keyL): _unlessTyping(
              () => onViewChanged(ViewMode.list),
            ),
            ..._navigationBindings,
            const SingleActivator(LogicalKeyboardKey.enter):
                ?_unlessTypingOrNull(onActivate),
            _primaryShortcut(LogicalKeyboardKey.keyD): ?onDuplicate,
            if (onNudge != null) ...{
              const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
                  _unlessTyping(() => onNudge!(-1, 0)),
              const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
                  _unlessTyping(() => onNudge!(1, 0)),
              const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
                  _unlessTyping(() => onNudge!(0, -60)),
              const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
                  _unlessTyping(() => onNudge!(0, 60)),
              const SingleActivator(
                LogicalKeyboardKey.arrowLeft,
                alt: true,
                shift: true,
              ): _unlessTyping(
                () => onNudge!(-7, 0),
              ),
              const SingleActivator(
                LogicalKeyboardKey.arrowRight,
                alt: true,
                shift: true,
              ): _unlessTyping(
                () => onNudge!(7, 0),
              ),
              const SingleActivator(
                LogicalKeyboardKey.arrowUp,
                alt: true,
                shift: true,
              ): _unlessTyping(
                () => onNudge!(0, -15),
              ),
              const SingleActivator(
                LogicalKeyboardKey.arrowDown,
                alt: true,
                shift: true,
              ): _unlessTyping(
                () => onNudge!(0, 15),
              ),
            },
            _primaryShortcut(LogicalKeyboardKey.keyF): onSearch,
            _primaryShortcut(LogicalKeyboardKey.keyR): ?_unlessTypingOrNull(
              onRefresh,
            ),
            _primaryShortcut(LogicalKeyboardKey.keyT): onToday,
            _primaryShortcut(LogicalKeyboardKey.arrowLeft): onPrevious,
            _primaryShortcut(LogicalKeyboardKey.arrowRight): onNext,
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
            final monthAgenda =
                view == ViewMode.month &&
                constraints.maxWidth - (sidebar ? 248 : 0) >= 760;
            final showCreate =
                view != ViewMode.week && view != ViewMode.day && !monthAgenda;
            return ColoredBox(
              color: theme.bg,
              child: Row(
                children: [
                  if (sidebar) _sidebar(showCreate: showCreate),
                  Expanded(
                    child: Column(
                      children: [
                        if (!sidebar)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              child: Row(
                                children: [
                                  if (!sidebar)
                                    _icon(
                                      '캘린더 표시',
                                      CupertinoIcons.sidebar_left,
                                      () => _showCalendars(context),
                                    ),
                                  const Spacer(),
                                  _views(),
                                  if (!sidebar) ...[
                                    const SizedBox(width: 6),
                                    if (showCreate)
                                      _icon(
                                        '일정 추가',
                                        CupertinoIcons.add,
                                        onCreate,
                                      ),
                                    const SizedBox(width: 8),
                                    _icon(
                                      '일정 검색',
                                      CupertinoIcons.search,
                                      onSearch,
                                    ),
                                  ],
                                  const Spacer(),
                                  if (!sidebar)
                                    _icon(
                                      '설정',
                                      CupertinoIcons.gear,
                                      onSettings ?? onManage,
                                    ),
                                ],
                              ),
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
                                    fontSize: view == ViewMode.list ? 20 : 24,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.7,
                                  ),
                                ),
                              ),
                              if (sidebar) ...[_views(), const Spacer()],
                              _icon(
                                '이전',
                                CupertinoIcons.chevron_left,
                                onPrevious,
                              ),
                              if (view != ViewMode.list)
                                TextButton(
                                  onPressed: onToday,
                                  style: TextButton.styleFrom(
                                    foregroundColor: theme.text,
                                  ),
                                  child: const Text('오늘'),
                                ),
                              _icon('다음', CupertinoIcons.chevron_right, onNext),
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

// Let text fields handle arrows through Flutter's text-editing shortcuts.
class _CalendarNavigationActivator extends SingleActivator {
  const _CalendarNavigationActivator(super.trigger);

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) =>
      !MacosCalendarShell._isEditingText() && super.accepts(event, state);
}

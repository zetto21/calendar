import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

class PaletteItem {
  final String label;
  final String? detail;
  final String? shortcut;
  final IconData icon;
  final VoidCallback run;
  const PaletteItem({
    required this.label,
    required this.icon,
    required this.run,
    this.detail,
    this.shortcut,
  });
}

/// Cmd+K launcher: type to search commands and events, or write a quick event.
Future<void> showCommandPalette(
  BuildContext context, {
  required AppTheme theme,
  required List<PaletteItem> Function(String query) itemsFor,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '명령 팔레트 닫기',
    barrierColor: Colors.black.withValues(alpha: 0.18),
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (dialogContext, _, _) => Align(
      alignment: const Alignment(0, -0.5),
      child: _CommandPalette(theme: theme, itemsFor: itemsFor),
    ),
  );
}

class _CommandPalette extends StatefulWidget {
  final AppTheme theme;
  final List<PaletteItem> Function(String query) itemsFor;
  const _CommandPalette({required this.theme, required this.itemsFor});

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  var _index = 0;

  List<PaletteItem> get _items => widget.itemsFor(_controller.text.trim());

  void _move(int delta) {
    final count = _items.length;
    if (count == 0) return;
    setState(() => _index = (_index + delta) % count);
    final offset = (_index * 44.0 - 88).clamp(0.0, double.infinity);
    if (_scroll.hasClients) {
      _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
    }
  }

  void _run(PaletteItem item) {
    Navigator.of(context).pop();
    item.run();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final items = _items;
    if (_index >= items.length) _index = 0;
    return Material(
      color: Colors.transparent,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).pop(),
        },
        child: Container(
          width: 560,
          constraints: const BoxConstraints(maxHeight: 460),
          decoration: BoxDecoration(
            color: theme.bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.border),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 30),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  style: TextStyle(color: theme.text, fontSize: 16),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: '명령, 일정 검색 또는 "내일 3시 회의 1시간"',
                    hintStyle: TextStyle(color: theme.textMuted),
                  ),
                  onChanged: (_) => setState(() => _index = 0),
                  onSubmitted: (_) {
                    if (items.isNotEmpty) _run(items[_index]);
                  },
                ),
              ),
              Divider(height: 1, color: theme.border),
              Flexible(
                child: items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          '결과가 없습니다',
                          style: TextStyle(color: theme.textMuted),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: items.length,
                        itemExtent: 44,
                        itemBuilder: (context, i) {
                          final item = items[i];
                          final selected = i == _index;
                          return InkWell(
                            onTap: () => _run(item),
                            onHover: (hover) {
                              if (hover && _index != i) {
                                setState(() => _index = i);
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                color: selected ? theme.bgSecondary : null,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    item.icon,
                                    size: 18,
                                    color: theme.textSecondary,
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      item.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: theme.text,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  if (item.detail != null) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      item.detail!,
                                      style: TextStyle(
                                        color: theme.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                  const Spacer(),
                                  if (item.shortcut != null)
                                    Text(
                                      item.shortcut!,
                                      style: TextStyle(
                                        color: theme.textMuted,
                                        fontSize: 12,
                                      ),
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
        ),
      ),
    );
  }
}

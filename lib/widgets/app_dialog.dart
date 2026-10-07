import 'package:flutter/material.dart';

/// Shared appearance for calendar dialogs and the embedded event editor.
abstract final class AppDialogStyle {
  static const accent = Color(0xFF7657FF);
  static const radius = 18.0;
  static const bodyPadding = EdgeInsets.fromLTRB(28, 8, 28, 24);
  static Color background(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF202023)
      : Colors.white;
  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF333338)
      : const Color(0xFFE7E7EB);

  static ThemeData theme(BuildContext context) {
    final base = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    return base.copyWith(
      datePickerTheme: DatePickerThemeData(
        backgroundColor: background(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: border(context)),
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: background(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: border(context)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(88, 40),
          shape: shape,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: base.colorScheme.onSurfaceVariant,
          minimumSize: const Size(72, 40),
          shape: shape,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: base.colorScheme.onSurface,
          minimumSize: const Size(88, 40),
          shape: shape,
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: base.brightness == Brightness.dark
            ? const Color(0xFF29292D)
            : const Color(0xFFF6F6F8),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accent),
        ),
      ),
    );
  }
}

class AppDialogHeader extends StatelessWidget {
  const AppDialogHeader({
    super.key,
    required this.title,
    this.icon,
    this.onClose,
    this.showClose = true,
  });
  final Widget title;
  final IconData? icon;
  final VoidCallback? onClose;
  final bool showClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 20, 16, 16),
    child: Row(
      children: [
        if (icon != null) ...[
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppDialogStyle.accent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 19, color: Colors.white),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Semantics(
            namesRoute: true,
            header: true,
            child: DefaultTextStyle(
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              child: title,
            ),
          ),
        ),
        if (showClose)
          IconButton(
            tooltip: '닫기',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 21),
          ),
      ],
    ),
  );
}

class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
    this.icon,
    this.maxWidth = 440,
    this.maxHeight = 700,
    this.contentPadding = AppDialogStyle.bodyPadding,
    this.insetPadding = const EdgeInsets.symmetric(
      horizontal: 20,
      vertical: 24,
    ),
    this.showClose = true,
    this.busy = false,
    this.scrollContent = true,
    this.onClose,
  });
  final Widget title, content;
  final List<Widget> actions;
  final IconData? icon;
  final double maxWidth, maxHeight;
  final EdgeInsetsGeometry contentPadding;
  final EdgeInsets insetPadding;
  final bool showClose, busy, scrollContent;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Theme(
    data: AppDialogStyle.theme(context),
    child: Dialog(
      backgroundColor: AppDialogStyle.background(context),
      surfaceTintColor: Colors.transparent,
      insetPadding: insetPadding,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDialogStyle.radius),
        side: BorderSide(color: AppDialogStyle.border(context)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: SizedBox(
          width: maxWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDialogHeader(
                title: title,
                icon: icon,
                showClose: showClose,
                onClose: busy
                    ? null
                    : (onClose ?? () => Navigator.of(context).pop()),
              ),
              Flexible(
                child: scrollContent
                    ? SingleChildScrollView(
                        padding: contentPadding,
                        child: content,
                      )
                    : Padding(padding: contentPadding, child: content),
              ),
              if (actions.isNotEmpty) ...[
                Divider(height: 1, color: AppDialogStyle.border(context)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 20),
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    overflowSpacing: 8,
                    children: actions,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class AppDialogAction extends StatelessWidget {
  const AppDialogAction({
    super.key,
    required this.child,
    this.onPressed,
    this.isDefaultAction = false,
    this.isDestructiveAction = false,
  });
  final Widget child;
  final VoidCallback? onPressed;
  final bool isDefaultAction, isDestructiveAction;

  @override
  Widget build(BuildContext context) {
    if (isDestructiveAction || isDefaultAction) {
      return FilledButton(
        style: isDestructiveAction
            ? FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              )
            : null,
        onPressed: onPressed,
        child: child,
      );
    }
    return TextButton(onPressed: onPressed, child: child);
  }
}

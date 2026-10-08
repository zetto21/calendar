import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool get useWindowsCalendarMotion =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

Widget calendarFadeTransition(Widget child, Animation<double> animation) =>
    AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final outgoing = animation.status == AnimationStatus.reverse;
        return IgnorePointer(
          ignoring: outgoing,
          child: ExcludeFocus(
            excluding: outgoing,
            child: ExcludeSemantics(
              excluding: outgoing,
              child: FadeTransition(opacity: animation, child: child),
            ),
          ),
        );
      },
    );

/// Retain the previous view during the transition so the calendar never blanks.
/// Outgoing views cannot receive pointer, keyboard or accessibility focus.
class CalendarViewTransition extends StatelessWidget {
  const CalendarViewTransition({
    super.key,
    required this.viewKey,
    required this.child,
  });

  final Object viewKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: calendarFadeTransition,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: RepaintBoundary(key: ValueKey(viewKey), child: child),
    ),
  );
}

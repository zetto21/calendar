import 'package:flutter/material.dart';

class PaletteColor {
  final String name;
  final Color value;
  const PaletteColor(this.name, this.value);
}

const List<PaletteColor> palette = [
  // 진한 색상
  PaletteColor('진한 블루', Color(0xFF1D4ED8)),
  PaletteColor('진한 코랄', Color(0xFFC2410C)),
  PaletteColor('진한 그린', Color(0xFF15803D)),
  PaletteColor('진한 옐로우', Color(0xFFB45309)),
  PaletteColor('진한 퍼플', Color(0xFF6D28D9)),
  PaletteColor('진한 핑크', Color(0xFFBE185D)),
  // 기본 색상
  PaletteColor('블루', Color(0xFF3B82F6)),
  PaletteColor('코랄', Color(0xFFF0654F)),
  PaletteColor('그린', Color(0xFF2FA36B)),
  PaletteColor('옐로우', Color(0xFFE8A100)),
  PaletteColor('퍼플', Color(0xFF8B5CF6)),
  PaletteColor('핑크', Color(0xFFEC4899)),
  // 연한 색상
  PaletteColor('연한 블루', Color(0xFF93C5FD)),
  PaletteColor('연한 코랄', Color(0xFFFDBA9A)),
  PaletteColor('연한 그린', Color(0xFF86EFAC)),
  PaletteColor('연한 옐로우', Color(0xFFFDE68A)),
  PaletteColor('연한 퍼플', Color(0xFFC4B5FD)),
  PaletteColor('연한 핑크', Color(0xFFF9A8D4)),
];

class AppTheme {
  final Color bg;
  final Color bgSecondary;
  final Color surface;
  final Color text;
  final Color textSecondary;
  final Color textMuted;
  final Color border;
  final Color accent;
  final Color danger;
  final bool isDark;

  const AppTheme({
    required this.bg,
    required this.bgSecondary,
    required this.surface,
    required this.text,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.accent,
    required this.danger,
    required this.isDark,
  });
}

const lightTheme = AppTheme(
  bg: Color(0xFFFFFFFF),
  bgSecondary: Color(0xFFF7F7F5),
  surface: Color(0xFFFFFFFF),
  text: Color(0xFF37352F),
  textSecondary: Color(0xFF787774),
  textMuted: Color(0xFF9B9A97),
  border: Color(0xFFEDECEA),
  accent: Color(0xFF3B82F6),
  danger: Color(0xFFEB5757),
  isDark: false,
);

const darkTheme = AppTheme(
  bg: Color(0xFF191919),
  bgSecondary: Color(0xFF202020),
  surface: Color(0xFF252525),
  text: Color(0xFFE9E9E7),
  textSecondary: Color(0xFF9B9A97),
  textMuted: Color(0xFF6F6E69),
  border: Color(0xFF2F2F2F),
  accent: Color(0xFF5B9BFF),
  danger: Color(0xFFFF6B6B),
  isDark: true,
);

Color withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

/// Maps our flat AppTheme tokens onto Flutter's ThemeData, overriding every
/// component theme that would otherwise inject default Material chrome
/// (elevated app bars, stadium buttons, outlined chips, underlined inputs) —
/// the RN app has none of that, so neither should this port.
ThemeData buildMaterialTheme(AppTheme theme) {
  final scheme = theme.isDark
      ? ColorScheme.fromSeed(seedColor: theme.accent, brightness: Brightness.dark, surface: theme.surface)
      : ColorScheme.fromSeed(seedColor: theme.accent, brightness: Brightness.light, surface: theme.surface);

  return ThemeData(
    useMaterial3: true,
    brightness: theme.isDark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: theme.bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: theme.border,
    appBarTheme: AppBarTheme(backgroundColor: theme.bg, foregroundColor: theme.text, elevation: 0, scrolledUnderElevation: 0),
    iconTheme: IconThemeData(color: theme.textSecondary),
    textTheme: Typography.blackMountainView.apply(bodyColor: theme.text, displayColor: theme.text),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: theme.bgSecondary,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: theme.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: theme.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: theme.accent)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: TextStyle(color: theme.textMuted),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? Colors.white : theme.textMuted),
      trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? theme.accent : theme.border),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: theme.bgSecondary,
      selectedColor: withAlpha(theme.accent, 0.16),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      labelStyle: TextStyle(color: theme.text, fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      showCheckmark: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: theme.accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: theme.accent)),
    listTileTheme: ListTileThemeData(textColor: theme.text, iconColor: theme.textSecondary, contentPadding: EdgeInsets.zero),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: theme.isDark ? const Color(0xFF59595C) : const Color(0xFF3D3D3F),
      foregroundColor: Colors.white,
      elevation: 4,
      shape: const CircleBorder(),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: theme.surface, surfaceTintColor: Colors.transparent),
    canvasColor: theme.surface,
  );
}

class EventTone {
  final Color background;
  final Color title;
  final Color detail;
  const EventTone({required this.background, required this.title, required this.detail});
}

// Opaque pastel fills keep the timetable rules from showing through event cards.
final Map<int, EventTone> _eventTones = {
  0xFF3B82F6: const EventTone(background: Color(0xFFE1EDFF), title: Color(0xFF315C87), detail: Color(0xFF6784A3)),
  0xFFF0654F: const EventTone(background: Color(0xFFFFE7DF), title: Color(0xFF974C3E), detail: Color(0xFFAA7468)),
  0xFF2FA36B: const EventTone(background: Color(0xFFDFF7DF), title: Color(0xFF28606A), detail: Color(0xFF668E87)),
  0xFFE8A100: const EventTone(background: Color(0xFFFFF3CE), title: Color(0xFF82641E), detail: Color(0xFF97814D)),
  0xFF8B5CF6: const EventTone(background: Color(0xFFEEE5FF), title: Color(0xFF654887), detail: Color(0xFF8A76A2)),
  0xFFEC4899: const EventTone(background: Color(0xFFFCE2EF), title: Color(0xFF8E416A), detail: Color(0xFFA7738D)),
};

EventTone eventCardTone(Color color, AppTheme theme) {
  if (theme.isDark) {
    return EventTone(background: withAlpha(color, 0.25), title: theme.text, detail: theme.textSecondary);
  }
  final tone = _eventTones[color.toARGB32()];
  if (tone != null) return tone;
  return EventTone(background: withAlpha(color, 0.16), title: theme.text, detail: theme.textSecondary);
}

Color colorFromHex(String hex) {
  final value = hex.replaceFirst('#', '');
  return Color(int.parse('FF$value', radix: 16));
}

String colorToHex(Color color) => '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

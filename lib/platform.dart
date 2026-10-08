import 'package:flutter/foundation.dart';

/// The wide, keyboard-and-mouse layout (sidebar, drag, shortcuts) is shared by
/// the macOS and Windows apps and the web build.
bool get useDesktopLayout =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows;

bool get useControlShortcuts => defaultTargetPlatform == TargetPlatform.windows;

String get desktopShortcutLabel => useControlShortcuts ? 'Ctrl+' : '⌘';

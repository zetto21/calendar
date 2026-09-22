import 'package:flutter/foundation.dart';

/// The wide, keyboard-and-mouse layout (sidebar, drag, shortcuts) is shared by
/// the macOS app and the web build.
bool get useDesktopLayout =>
    kIsWeb || defaultTargetPlatform == TargetPlatform.macOS;

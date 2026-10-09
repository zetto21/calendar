import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NativeGlassAction {
  final IconData icon;
  final String label, symbol;
  final VoidCallback onPressed;
  const NativeGlassAction({
    required this.icon,
    required this.label,
    required this.symbol,
    required this.onPressed,
  });
}

/// The complete control lives in UIKit, including touch down, drag and release.
class NativeGlassButtons extends StatefulWidget {
  final List<NativeGlassAction> actions;
  final Color color;
  final bool dark;
  final double itemWidth, height, iconSize;
  const NativeGlassButtons({
    super.key,
    required this.actions,
    required this.color,
    required this.dark,
    this.itemWidth = 44,
    this.height = 44,
    this.iconSize = 20,
  });
  @override
  State<NativeGlassButtons> createState() => _NativeGlassButtonsState();
}

class _NativeGlassButtonsState extends State<NativeGlassButtons> {
  MethodChannel? _channel;
  Map<String, Object> get _configuration => {
    'color': widget.color.toARGB32(),
    'dark': widget.dark,
    'itemWidth': widget.itemWidth,
    'iconSize': widget.iconSize,
    'actions': [
      for (final action in widget.actions)
        {
          'codePoint': action.icon.codePoint,
          'font': action.icon.fontFamily == 'CupertinoIcons'
              ? 'cupertino'
              : 'material',
          'label': action.label,
          'symbol': action.symbol,
        },
    ],
  };
  void _created(int id) {
    final channel = MethodChannel('calendar_app/native_glass_buttons/$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (!mounted || call.method != 'press') return;
      final index = call.arguments;
      if (index is int && index >= 0 && index < widget.actions.length) {
        widget.actions[index].onPressed();
      }
    });
    channel.invokeMethod<void>('configure', _configuration);
  }

  @override
  void didUpdateWidget(covariant NativeGlassButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    _channel?.invokeMethod<void>('configure', _configuration);
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.itemWidth * widget.actions.length,
    height: widget.height,
    child: UiKitView(
      viewType: 'calendar_app/native_glass_buttons',
      creationParams: _configuration,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _created,
      gestureRecognizers: {
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      },
    ),
  );
}

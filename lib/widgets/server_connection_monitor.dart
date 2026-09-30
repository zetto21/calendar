import 'app_dialog.dart';

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Keeps connection monitoring alive across all app pages and routes.
class ServerConnectionMonitor extends StatefulWidget {
  final Widget child;
  final Future<bool> Function()? checkConnection;
  const ServerConnectionMonitor({
    super.key,
    required this.child,
    this.checkConnection,
  });

  static final available = ValueNotifier<bool?>(null);

  @override
  State<ServerConnectionMonitor> createState() =>
      _ServerConnectionMonitorState();
}

class _ServerConnectionMonitorState extends State<ServerConnectionMonitor>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _checking = false;
  bool _foreground = true;
  bool? _lastAvailability;
  bool _connectionAlertVisible = false;
  Route<bool>? _connectionRoute;

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// Web gets a quiet banner. Native apps show an in-app popup.
  bool get _quiet => kIsWeb;

  OverlayEntry? _banner;
  bool _bannerDismissed = false;

  void _showBanner() {
    if (_banner != null || _bannerDismissed) return;
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    if (overlay == null) return;
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        top: 12,
        left: 0,
        right: 0,
        child: Align(
          alignment: Alignment.topCenter,
          child: Material(
            elevation: 4,
            color: const Color(0xFF37352F),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CupertinoIcons.wifi_slash,
                    size: 16,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '서버에 연결할 수 없습니다. 연결되면 자동으로 다시 시도해요.',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  TextButton(
                    onPressed: _checkConnection,
                    child: const Text('다시 시도'),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _bannerDismissed = true;
                      _hideBanner();
                    },
                    icon: const Icon(
                      CupertinoIcons.xmark,
                      size: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    _banner = entry;
    overlay.insert(entry);
  }

  void _hideBanner() {
    _banner?.remove();
    _banner = null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _checkConnection();
    });
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: _quiet ? 5 : 1),
      (_) => _checkConnection(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _startTimer();
      _checkConnection();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _checkConnection() async {
    if (!mounted || !_foreground || _checking) return;
    _checking = true;
    try {
      final connected =
          await (widget.checkConnection ??
              AuthService.instance.checkConnection)();
      if (!mounted) return;
      if (!connected) throw ServerConnectionException();
      _lastAvailability = true;
      ServerConnectionMonitor.available.value = true;
      if (!mounted) return;
      _bannerDismissed = false;
      _hideBanner();
      final route = _connectionRoute;
      if (route != null && route.isActive) route.navigator?.removeRoute(route);
    } on ServerConnectionException {
      if (!mounted) return;
      final wasConnected = _lastAvailability != false;
      _lastAvailability = false;
      ServerConnectionMonitor.available.value = false;
      if (!mounted) return;
      if (_foreground && wasConnected) {
        _quiet ? _showBanner() : _showConnectionAlert();
      }
    } catch (_) {
      // Provider configuration errors do not imply a connection outage.
    } finally {
      _checking = false;
    }
  }

  Future<void> _showConnectionAlert() async {
    if (!mounted || _connectionAlertVisible) return;
    _connectionAlertVisible = true;
    final route = _isAndroid
        ? DialogRoute<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AppDialog(
              showClose: false,
              title: const Text('서버에 연결할 수 없습니다'),
              content: const Text('인터넷 연결을 확인한 후 새로고침해 주세요.'),
              actions: [
                TextButton(
                  onPressed: _checkConnection,
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('다시 연결 시도'),
                ),
              ],
            ),
          )
        : CupertinoDialogRoute<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AppDialog(
              showClose: false,
              title: const Text('서버에 연결할 수 없습니다'),
              content: const Text('인터넷 연결을 확인한 후 새로고침해 주세요.'),
              actions: [
                AppDialogAction(
                  isDefaultAction: true,
                  onPressed: _checkConnection,
                  child: Text(
                    '다시 연결 시도',
                    style: TextStyle(
                      color: CupertinoColors.systemRed.resolveFrom(
                        dialogContext,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
    _connectionRoute = route;
    final refresh = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(route);
    _connectionRoute = null;
    _connectionAlertVisible = false;
    if (mounted && refresh == true) _checkConnection();
  }

  @override
  void dispose() {
    _hideBanner();
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

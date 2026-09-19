import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/server_connection_notifications.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      unawaited(ServerConnectionNotifications.initialize());
      _checkConnection();
    });
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkConnection(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _checkConnection();
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
      final wasUnavailable = _lastAvailability == false;
      _lastAvailability = true;
      ServerConnectionMonitor.available.value = true;
      if (wasUnavailable) {
        await ServerConnectionNotifications.showReconnected();
      }
      final route = _connectionRoute;
      if (route != null && route.isActive) route.navigator?.removeRoute(route);
    } on ServerConnectionException {
      if (!mounted) return;
      final wasConnected = _lastAvailability != false;
      _lastAvailability = false;
      ServerConnectionMonitor.available.value = false;
      if (wasConnected) {
        await ServerConnectionNotifications.showDisconnected();
      }
      if (_foreground) _showConnectionAlert();
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
            builder: (dialogContext) => AlertDialog(
              title: const Text('서버에 연결할 수 없습니다'),
              content: const Text('인터넷 연결을 확인한 후 새로고침해 주세요.'),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('새로고침'),
                ),
              ],
            ),
          )
        : CupertinoDialogRoute<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => CupertinoAlertDialog(
              title: const Text('서버에 연결할 수 없습니다'),
              content: const Text('인터넷 연결을 확인한 후 새로고침해 주세요.'),
              actions: [
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(
                    '새로고침',
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
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

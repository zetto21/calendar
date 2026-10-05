import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/consent_screen.dart';
import '../theme/app_theme.dart';

/// Loads installation consent before mounting login or starting API requests.
class ConsentGate extends StatefulWidget {
  final Widget child;
  const ConsentGate({super.key, required this.child});

  @override
  State<ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends State<ConsentGate> {
  bool? _accepted;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      final recorded = prefs.getString(ConsentScreen.storageKey);
      final accepted = recorded != null && DateTime.tryParse(recorded) != null;
      if (mounted) setState(() => _accepted = accepted);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted == true) return widget.child;
    if (_accepted == false) {
      return ConsentScreen(
        theme: Theme.of(context).brightness == Brightness.dark
            ? darkTheme
            : lightTheme,
        onAccepted: () => setState(() => _accepted = true),
      );
    }
    return Scaffold(
      body: Center(
        child: _failed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('시작 정보를 불러오지 못했습니다.'),
                  TextButton(onPressed: _load, child: const Text('다시 시도')),
                ],
              )
            : const CupertinoActivityIndicator(),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'liquid_glass.dart';

Future<void> showDisplayNameDialog(
  BuildContext context, {
  required String initialName,
  required Future<void> Function(String) onSave,
}) => showDialog<void>(
  context: context,
  builder: (_) => _DisplayNameDialog(initialName: initialName, onSave: onSave),
);

class _DisplayNameDialog extends StatefulWidget {
  const _DisplayNameDialog({required this.initialName, required this.onSave});
  final String initialName;
  final Future<void> Function(String) onSave;

  @override
  State<_DisplayNameDialog> createState() => _DisplayNameDialogState();
}

class _DisplayNameDialogState extends State<_DisplayNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _controller.text.trim();
    if (name.isEmpty || name.runes.length > 40) {
      setState(() => _error = '이름은 1~40자로 입력해 주세요.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(name);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = error is AuthException
              ? error.message
              : '이름을 저장하지 못했습니다. 다시 시도해 주세요.';
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: LiquidGlass(
          radius: 24,
          useNative: false,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '이름 · 별명',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  '캘린더에 표시할 이름을 입력해 주세요.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  enabled: !_saving,
                  maxLength: 40,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    hintText: '이름 또는 별명',
                    counterText: '',
                    errorText: _error,
                    errorMaxLines: 3,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('취소'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? '저장 중…' : '저장'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

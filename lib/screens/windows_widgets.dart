import 'package:flutter/material.dart';

Future<void> showWindowsWidgets(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('공식 Windows 위젯'),
    content: const SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Win+W → 위젯 추가에서 “일상 캘린더”를 선택하세요.'),
          SizedBox(height: 12),
          Text('오늘 일정 · 월간 달력 · 다가오는 일정을 지원합니다.'),
          SizedBox(height: 12),
          Text(
            '앱에서 마지막으로 동기화한 일정을 표시합니다. 앱에서 일정을 수정하면 자동으로 반영됩니다.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('닫기'),
      ),
    ],
  ),
);

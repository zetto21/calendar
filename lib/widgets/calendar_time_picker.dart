import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_dialog.dart';
import 'liquid_glass.dart';

Future<TimeOfDay?> showCalendarTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
    return showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) =>
          Theme(data: AppDialogStyle.theme(context), child: child!),
    );
  }
  var selected = initialTime;
  return showDialog<TimeOfDay>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return Dialog(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 360,
          child: LiquidGlass(
            useNative: false,
            radius: 24,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '시간 선택',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    CupertinoTheme(
                      data: CupertinoThemeData(
                        brightness: theme.brightness,
                        primaryColor: AppDialogStyle.accent,
                        textTheme: CupertinoTextThemeData(
                          dateTimePickerTextStyle: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 21,
                          ),
                        ),
                      ),
                      child: SizedBox(
                        height: 200,
                        child: CupertinoDatePicker(
                          mode: CupertinoDatePickerMode.time,
                          initialDateTime: DateTime(
                            2026,
                            1,
                            1,
                            initialTime.hour,
                            initialTime.minute,
                          ),
                          use24hFormat: MediaQuery.alwaysUse24HourFormatOf(
                            context,
                          ),
                          onDateTimeChanged: (date) =>
                              selected = TimeOfDay.fromDateTime(date),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('취소'),
                        ),
                        const SizedBox(width: 8),
                        LiquidGlass(
                          useNative: false,
                          radius: 20,
                          child: TextButton(
                            onPressed: () => Navigator.pop(context, selected),
                            style: TextButton.styleFrom(
                              foregroundColor: theme.colorScheme.onSurface,
                            ),
                            child: const Text('확인'),
                          ),
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
    },
  );
}

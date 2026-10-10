import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_dialog.dart';
import 'liquid_glass.dart';

Future<DateTime?> showCalendarDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) =>
          Theme(data: AppDialogStyle.theme(context), child: child!),
    );
  }
  var selected = DateUtils.dateOnly(initialDate);
  return showDialog<DateTime>(
    context: context,
    builder: (context) {
      final base = Theme.of(context);
      return Theme(
        data: base.copyWith(
          colorScheme: base.colorScheme.copyWith(
            primary: AppDialogStyle.accent,
          ),
        ),
        child: Dialog(
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
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '날짜 선택',
                          style: TextStyle(
                            color: base.colorScheme.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      CalendarDatePicker(
                        initialDate: selected,
                        firstDate: firstDate,
                        lastDate: lastDate,
                        onDateChanged: (date) => selected = date,
                      ),
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
                                foregroundColor: base.colorScheme.onSurface,
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
        ),
      );
    },
  );
}

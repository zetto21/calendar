import 'package:calendar_app_flutter/widgets/native_glass_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'native action dispatch follows current callbacks and ignores invalid indices',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      MethodChannel? nativeChannel;
      final configurations = <Map<Object?, Object?>>[];
      messenger.setMockMethodCallHandler(
        const MethodChannel('flutter/platform_views'),
        (call) async {
          if (call.method == 'create') {
            nativeChannel = MethodChannel(
              'calendar_app/native_glass_buttons/${(call.arguments as Map)['id']}',
            );
            messenger.setMockMethodCallHandler(nativeChannel!, (call) async {
              if (call.method == 'configure') {
                configurations.add(call.arguments as Map<Object?, Object?>);
              }
              return null;
            });
          }
          return null;
        },
      );
      var searches = 0, views = 0;
      Widget host({bool updated = false}) => MaterialApp(
        home: Center(
          child: NativeGlassButtons(
            color: Colors.white,
            dark: true,
            actions: [
              NativeGlassAction(
                icon: Icons.search,
                label: '일정 검색',
                symbol: 'magnifyingglass',
                onPressed: () => searches++,
              ),
              NativeGlassAction(
                icon: updated ? Icons.list : Icons.calendar_month,
                label: updated ? '목록형' : '월간',
                symbol: 'calendar',
                onPressed: () => views += updated ? 10 : 1,
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(nativeChannel, isNotNull);
      expect(configurations, isNotEmpty);
      final channel = nativeChannel!;
      Future<void> press(int index) async {
        final done = <bool>[];
        messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('press', index),
          ),
          (_) => done.add(true),
        );
        await tester.pump();
        expect(done, isNotEmpty);
      }

      await press(0);
      await press(1);
      await press(-1);
      await press(2);
      expect(searches, 1);
      expect(views, 1);
      await tester.pumpWidget(host(updated: true));
      await tester.pump();
      await press(1);
      expect(views, 11);
      final actions = configurations.last['actions'] as List;
      expect((actions[1] as Map)['label'], '목록형');
      expect((actions[1] as Map)['codePoint'], Icons.list.codePoint);
      await tester.pumpWidget(const SizedBox());
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(
        const MethodChannel('flutter/platform_views'),
        null,
      );
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );
}

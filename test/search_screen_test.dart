import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:calendar_app_flutter/screens/search_screen.dart';
import 'package:calendar_app_flutter/storage/event_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:timezone/timezone.dart' as tz;

class _SearchStore extends EventStore {
  @override
  EventMap get events => {
    '2020-01-01': [
      const CalendarEvent(
        id: 'past',
        date: '2020-01-01',
        title: '팀 회의',
        location: '서울',
        description: '기획 검토',
        duration: 60,
        color: '#3B82F6',
      ),
    ],
  };
}

void main() {
  for (final width in [380.0, 1200.0]) {
    testWidgets(
      'search at width $width shows past location matches without overflow',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ChangeNotifierProvider<EventStore>(
            create: (_) => _SearchStore(),
            child: MaterialApp(
              home: SearchScreen(
                rangeFrom: '2026-10-01',
                rangeTo: '2026-11-01',
                deviceZone: tz.UTC,
                onEventPress: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('어떤 일정을 찾으시나요?'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '서울 검토');
        await tester.pump();
        expect(find.text('검색 결과 1개'), findsOneWidget);
        expect(find.text('팀 회의'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.enterText(find.byType(TextField), '없는 일정');
        await tester.pump();
        expect(find.text('검색 결과가 없습니다'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

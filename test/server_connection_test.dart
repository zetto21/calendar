import 'dart:async';

import 'package:calendar_app_flutter/services/auth_service.dart';
import 'package:calendar_app_flutter/widgets/server_connection_monitor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class ClosingClient extends MockClient {
  ClosingClient(super.fn);
  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  test('Android loopback keeps the scheme and port', () {
    for (final host in ['localhost', '127.0.0.1']) {
      expect(
        AuthService.resolveApiBase('http://$host:3001/', isAndroid: true),
        'http://10.0.2.2:3001',
      );
    }
    expect(
      AuthService.resolveApiBase('https://localhost/api', isAndroid: true),
      'https://10.0.2.2/api',
    );
    for (final base in [
      'https://localhost.example.com',
      'http://192.168.0.2:3001',
    ]) {
      expect(AuthService.resolveApiBase(base, isAndroid: true), base);
    }
    expect(
      AuthService.resolveApiBase('http://localhost:3001', isAndroid: false),
      'http://localhost:3001',
    );
  });

  test(
    'reachability does not depend on OAuth JSON or provider names',
    () async {
      for (final status in [200, 204, 401, 404, 500, 503]) {
        final client = ClosingClient(
          (_) async => http.Response('not JSON', status),
        );
        expect(
          await AuthService.instance.checkConnection(client: client),
          status < 500,
        );
        expect(client.closed, isTrue);
      }
    },
  );

  test(
    'timeout reports unavailable and closes the outstanding request',
    () async {
      final client = ClosingClient((_) => Completer<http.Response>().future);
      expect(
        await AuthService.instance.checkConnection(
          client: client,
          timeout: const Duration(milliseconds: 10),
        ),
        isFalse,
      );
      expect(client.closed, isTrue);
    },
  );

  testWidgets('foreground detects outage and recovery on consecutive ticks', (
    tester,
  ) async {
    var connected = true;
    var checks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ServerConnectionMonitor(
          checkConnection: () async {
            checks++;
            return connected;
          },
          child: const Scaffold(body: Text('Calendar')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(ServerConnectionMonitor.available.value, isTrue);
    connected = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(ServerConnectionMonitor.available.value, isFalse);
    expect(find.text('서버에 연결할 수 없습니다'), findsOneWidget);
    connected = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(ServerConnectionMonitor.available.value, isTrue);
    expect(find.text('서버에 연결할 수 없습니다'), findsNothing);
    expect(checks, greaterThanOrEqualTo(3));
    await tester.pumpWidget(const SizedBox());
  });
}

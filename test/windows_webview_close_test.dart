import 'package:desktop_webview_window/src/webview_impl.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('programmatic close completes without an OS close event', () async {
    const channel = MethodChannel('calendar/test-webview-close');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'close');
      expect(call.arguments, {'viewId': 7});
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final view = WebviewImpl(7, channel);
    view.close();
    await view.onClose.timeout(const Duration(seconds: 1));
    // A later native close event must not complete the same future twice.
    expect(view.onClosed, returnsNormally);
  });
}

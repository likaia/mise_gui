import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mise_gui/services/desktop_window_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('toggleMaximize invokes the desktop window channel', () async {
    const channel = MethodChannel('mise_gui/window_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const service = MethodChannelDesktopWindowService(channel: channel);

    await service.toggleMaximize();

    expect(calls.single.method, 'toggleMaximize');
  });
}

import 'package:flutter/services.dart';

abstract class DesktopWindowService {
  Future<void> toggleMaximize();
}

class MethodChannelDesktopWindowService implements DesktopWindowService {
  const MethodChannelDesktopWindowService({
    MethodChannel channel = const MethodChannel('mise_gui/window'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<void> toggleMaximize() async {
    try {
      await _channel.invokeMethod<void>('toggleMaximize');
    } on MissingPluginException {
      // Window controls are a desktop-only enhancement; ignore unsupported
      // platforms and test environments.
    }
  }
}

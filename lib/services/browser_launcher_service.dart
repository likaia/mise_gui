import 'dart:io';

abstract class BrowserLauncherService {
  Future<bool> openUrl(String url);
}

class SystemBrowserLauncherService implements BrowserLauncherService {
  const SystemBrowserLauncherService();

  @override
  Future<bool> openUrl(String url) async {
    try {
      ProcessResult result;
      if (Platform.isMacOS) {
        result = await Process.run('open', [url], runInShell: false);
      } else if (Platform.isWindows) {
        result = await Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isLinux) {
        result = await Process.run('xdg-open', [url], runInShell: false);
      } else {
        return false;
      }
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/services/config_service.dart';

void main() {
  test('runtime settings display TOML strings without quotes', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'mise-config-service-',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final configFile = File('${tempDirectory.path}/config.toml');
    await configFile.writeAsString(
      '[settings]\n'
      'http_timeout = "45s"\n'
      'http_retries = 5\n'
      'offline = false\n',
    );

    final service = LiveConfigService(globalConfigPath: configFile.path);
    final workspace = await service.fetchWorkspace(includeProjectConfig: false);
    final runtimeSettings = workspace.runtimeSettings!;

    expect(
      runtimeSettings.settings
          .firstWhere((setting) => setting.key == 'http_timeout')
          .value,
      '45s',
    );
    expect(
      runtimeSettings.settings
          .firstWhere((setting) => setting.key == 'http_retries')
          .value,
      '5',
    );
    expect(
      workspace.sections
          .firstWhere((section) => section.title == '运行时设置')
          .items
          .first
          .value,
      '45s',
    );
  });

  test('previews runtime setting changes as TOML updates', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'mise-config-service-',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final configFile = File('${tempDirectory.path}/config.toml');
    await configFile.writeAsString(
      '[tools]\n'
      'node = "20"\n'
      '\n'
      '[settings]\n'
      'http_timeout = "30s"\n'
      'http_retries = 3\n'
      'idiomatic_version_file_enable = false\n',
    );

    final service = LiveConfigService(globalConfigPath: configFile.path);
    final workspace = await service.fetchWorkspace(includeProjectConfig: false);
    final preview = await service.previewRuntimeSettingsSave(
      update: ConfigRuntimeSettingsUpdate(
        document: workspace.runtimeSettings!.document,
        values: const {
          'http_timeout': '60s',
          'fetch_remote_versions_timeout': '25s',
          'http_retries': '0',
          'offline': 'true',
          'terminal_progress': null,
        },
      ),
    );

    expect(preview.hasChanges, isTrue);
    expect(preview.nextContent, contains('http_timeout = "60s"'));
    expect(
      preview.nextContent,
      contains('fetch_remote_versions_timeout = "25s"'),
    );
    expect(preview.nextContent, contains('http_retries = 0'));
    expect(preview.nextContent, contains('offline = true'));
    expect(
      preview.nextContent,
      contains('idiomatic_version_file_enable = false'),
    );
    expect(preview.nextContent, contains('[tools]\nnode = "20"'));
  });

  test('previews proxy setting changes as env updates', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'mise-config-service-',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final configFile = File('${tempDirectory.path}/config.toml');
    await configFile.writeAsString(
      '[tools]\n'
      'node = "20"\n'
      '\n'
      '[env]\n'
      'FOO = "bar"\n'
      'http_proxy = "http://127.0.0.1:7890"\n',
    );

    final service = LiveConfigService(globalConfigPath: configFile.path);
    final workspace = await service.fetchWorkspace(includeProjectConfig: false);
    final proxySettings = workspace.proxySettings!;

    expect(
      proxySettings.settings
          .firstWhere((setting) => setting.key == 'http_proxy')
          .value,
      'http://127.0.0.1:7890',
    );

    final preview = await service.previewProxySettingsSave(
      update: ConfigProxySettingsUpdate(
        document: proxySettings.document,
        values: const {
          'http_proxy': 'http://127.0.0.1:1087',
          'https_proxy': 'http://127.0.0.1:1087',
          'all_proxy': null,
          'no_proxy': 'localhost,127.0.0.1',
        },
      ),
    );

    expect(preview.hasChanges, isTrue);
    expect(preview.nextContent, contains('FOO = "bar"'));
    expect(
      preview.nextContent,
      contains('http_proxy = "http://127.0.0.1:1087"'),
    );
    expect(
      preview.nextContent,
      contains('HTTP_PROXY = "http://127.0.0.1:1087"'),
    );
    expect(
      preview.nextContent,
      contains('https_proxy = "http://127.0.0.1:1087"'),
    );
    expect(
      preview.nextContent,
      contains('HTTPS_PROXY = "http://127.0.0.1:1087"'),
    );
    expect(preview.nextContent, contains('no_proxy = "localhost,127.0.0.1"'));
    expect(preview.nextContent, contains('NO_PROXY = "localhost,127.0.0.1"'));
    expect(preview.nextContent, contains('[tools]\nnode = "20"'));
  });
}

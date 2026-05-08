import 'package:flutter_test/flutter_test.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/services/mise_cli_service.dart';
import 'package:mise_gui/services/mise_process_service.dart';
import 'package:mise_gui/services/mise_query_service.dart';

class _FakeProcessService implements MiseProcessService {
  const _FakeProcessService(
    this.result, {
    this.windowsShimPathStatus = const WindowsShimPathStatus(
      source: WindowsShimPathSource.unsupported,
    ),
  });

  final ShellEnvironmentLoadResult result;
  final WindowsShimPathStatus windowsShimPathStatus;

  @override
  Future<ShellEnvironmentLoadResult> inspectShellEnvironment() async => result;

  @override
  Future<WindowsShimPathStatus> inspectWindowsShimPath() async =>
      windowsShimPathStatus;

  @override
  Future<MiseCommandResult> run(MiseCommandRequest request) {
    throw UnimplementedError();
  }
}

class _FakeQueryService implements MiseQueryService {
  const _FakeQueryService();

  @override
  Future<List<MiseCurrentToolRef>> fetchCurrentTools({
    String? workingDirectory,
  }) async => const [
    MiseCurrentToolRef(tool: 'node', version: '20.16.0', rawLine: 'node 20.16.0'),
  ];

  @override
  Future<Map<String, dynamic>> fetchEnvironment({
    String? workingDirectory,
  }) async => const {
    'PATH': '/Users/demo/.local/share/mise/installs/node/20.16.0/bin:/usr/bin',
    'JAVA_HOME': '/Users/demo/.local/share/mise/installs/java/21',
  };

  @override
  Future<Map<String, dynamic>> fetchSettings({String? workingDirectory}) async =>
      const {
        'settings': {
          'idiomatic_version_file_enable': {'source': '~/.config/mise/config.toml'},
        },
      };

  @override
  Future<MiseResolvedExecutableRef> fetchExecutable(
    String subject, {
    String? workingDirectory,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, List<MiseInstalledToolVersionRef>>> fetchInstalledTools({
    String? workingDirectory,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> fetchOutdated({String? workingDirectory}) {
    throw UnimplementedError();
  }

  @override
  Future<List<MiseRemoteToolVersionRef>> fetchRemoteVersions(
    String tool, {
    String? workingDirectory,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MiseResolvedExecutableRef> fetchShellExecutable(
    String subject, {
    String? workingDirectory,
  }) {
    throw UnimplementedError();
  }
}

class _JavaRemoteQueryService extends _FakeQueryService {
  const _JavaRemoteQueryService();

  @override
  Future<List<MiseRemoteToolVersionRef>> fetchRemoteVersions(
    String tool, {
    String? workingDirectory,
  }) async {
    if (tool != 'java') {
      return const [];
    }

    return const [
      MiseRemoteToolVersionRef(
        tool: 'java',
        version: '21.0.2',
        rolling: false,
      ),
      MiseRemoteToolVersionRef(
        tool: 'java',
        version: 'temurin-21.0.11+9.0.LTS',
        rolling: false,
      ),
      MiseRemoteToolVersionRef(
        tool: 'java',
        version: 'temurin-22.0.1+8',
        rolling: false,
      ),
    ];
  }
}

void main() {
  test('compares segmented tool versions numerically', () {
    expect(
      compareToolVersions('temurin-21.0.10+7.0.LTS', '21.0.2'),
      greaterThan(0),
    );
    expect(compareToolVersions('3.11.10', '3.11.9'), greaterThan(0));
    expect(compareToolVersions('20.16.0', '20.16'), 0);
  });

  test('adds a gentle fallback signal when shell environment falls back', () async {
    const service = LiveMiseCliService(
      queryService: _FakeQueryService(),
      processService: _FakeProcessService(
        ShellEnvironmentLoadResult(
          source: ShellEnvironmentSource.desktopFallback,
          detail: '未能可靠读取登录 shell 环境，已回退到桌面进程环境。',
        ),
      ),
    );

    final signals = await service.fetchEnvironmentSignals();

    expect(signals.first.title, 'Shell 环境');
    expect(signals.first.value, '已回退');
    expect(signals.first.level, HealthLevel.info);
    expect(signals.first.detail, contains('已回退到桌面进程环境'));
  });

  test('prefers newer java vendor versions over older plain versions', () async {
    const service = LiveMiseCliService(
      queryService: _JavaRemoteQueryService(),
      processService: _FakeProcessService(
        ShellEnvironmentLoadResult(source: ShellEnvironmentSource.shell),
      ),
    );

    const tool = ToolRecord(
      id: 'java',
      name: 'Java',
      category: 'Java 版本管理',
      description: 'Java toolchain',
      activeVersion: 'temurin-21.0.10+7.0.LTS',
      requestedVersion: 'java@21',
      source: '全局',
      strategy: 'global',
      latestStableVersion: '待同步',
      latestPreviewVersion: '待同步',
      installedVersions: [],
      remoteVersions: [],
      projectImpacts: [],
      quickActions: [],
      commandPreview: 'mise current java',
      level: HealthLevel.info,
      remoteState: ToolRemoteState.pending,
    );

    final hydrated = await service.hydrateToolRemoteState(tool);

    expect(hydrated.latestStableVersion, 'temurin-21.0.11+9.0.LTS');
    expect(hydrated.updateVersion, 'temurin-21.0.11+9.0.LTS');
    expect(
      hydrated.remoteVersions.map((version) => version.version).first,
      'temurin-21.0.11+9.0.LTS',
    );
  });

  test('adds a windows shim PATH notice when shims are missing from PATH', () async {
    const service = LiveMiseCliService(
      queryService: _JavaRemoteQueryService(),
      processService: _FakeProcessService(
        ShellEnvironmentLoadResult(source: ShellEnvironmentSource.unsupported),
        windowsShimPathStatus: WindowsShimPathStatus(
          source: WindowsShimPathSource.missing,
          shimPath: r'C:\Users\demo\AppData\Local\mise\shims',
          detail: '当前系统 PATH 里还没有 mise shims 目录。',
          commandPreview: r'$shimDir = "C:\Users\demo\AppData\Local\mise\shims"',
        ),
      ),
    );

    const tool = ToolRecord(
      id: 'go',
      name: 'Go',
      category: 'Go 版本管理',
      description: 'Go toolchain',
      activeVersion: '1.26.3',
      requestedVersion: '1.26',
      source: '全局',
      strategy: 'global',
      latestStableVersion: '待同步',
      latestPreviewVersion: '待同步',
      installedVersions: [],
      remoteVersions: [],
      projectImpacts: [],
      quickActions: [],
      commandPreview: 'mise current go',
      level: HealthLevel.info,
      remoteState: ToolRemoteState.pending,
    );

    final hydrated = await service.hydrateToolRemoteState(tool);

    expect(
      hydrated.notices.any((notice) => notice.title.contains('Windows 终端尚未接入 mise shims')),
      isTrue,
    );
    expect(
      hydrated.notices.any(
        (notice) =>
            notice.commandPreview?.contains(r'mise\shims') ?? false,
      ),
      isTrue,
    );
  });
}

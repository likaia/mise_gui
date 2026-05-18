import 'dart:async';

import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/services/mise_process_service.dart';
import 'package:mise_gui/services/mise_query_service.dart';

class _RemoteVersionLoadResult {
  const _RemoteVersionLoadResult({
    required this.versions,
    this.notice,
    this.latestStableVersion,
  });

  final List<MiseRemoteToolVersionRef> versions;
  final InlineNotice? notice;
  final String? latestStableVersion;
}

abstract class MiseCliService {
  Future<List<ToolRecord>> fetchTools();
  Future<List<EnvironmentSignal>> fetchEnvironmentSignals();
  Future<DashboardToolSummary> fetchDashboardToolSummary();
  Future<ToolRecord> hydrateToolRemoteState(ToolRecord tool);
}

class LiveMiseCliService implements MiseCliService {
  const LiveMiseCliService({
    required MiseQueryService queryService,
    required MiseProcessService processService,
  }) : _queryService = queryService,
       _processService = processService;

  final MiseQueryService _queryService;
  final MiseProcessService _processService;

  @override
  Future<List<EnvironmentSignal>> fetchEnvironmentSignals() async {
    try {
      final shellEnvironment = await _processService.inspectShellEnvironment();
      final currentTools = await _queryService.fetchCurrentTools();
      final environment = await _queryService.fetchEnvironment();
      final settings = await _queryService.fetchSettings();

      final activeSummary = currentTools.isEmpty
          ? '当前目录还没有解析出活跃工具。'
          : currentTools
                .map((tool) => '${tool.tool} ${tool.version}')
                .join(' / ');

      final exportedPath = environment['PATH']?.toString() ?? '';
      final pathEntries = exportedPath
          .split(':')
          .where((entry) => entry.isNotEmpty)
          .toList();
      final miseInstallEntries = pathEntries
          .where((entry) => entry.contains('/.local/share/mise/installs/'))
          .length;

      final javaHome = environment['JAVA_HOME']?.toString();
      final settingSources = _collectSettingSources(settings);

      return [
        if (shellEnvironment.source == ShellEnvironmentSource.desktopFallback)
          EnvironmentSignal(
            title: 'Shell 环境',
            value: '已回退',
            detail:
                shellEnvironment.detail ??
                '未能可靠读取登录 shell 环境，已回退到桌面进程环境。PATH 与 JAVA_HOME 判断会更保守，但基础功能仍可继续使用。',
            level: HealthLevel.info,
          ),
        EnvironmentSignal(
          title: '活跃工具链',
          value: '${currentTools.length} 个活跃项',
          detail: activeSummary,
          level: currentTools.isEmpty
              ? HealthLevel.warning
              : HealthLevel.healthy,
        ),
        EnvironmentSignal(
          title: 'PATH 导出',
          value: '$miseInstallEntries 段路径',
          detail: miseInstallEntries == 0
              ? 'mise env -J 没有导出任何安装目录，后续命令解析很可能不稳定。'
              : '当前 PATH 已注入 $miseInstallEntries 段 mise 安装目录，界面可以据此解释命令来源。',
          level: miseInstallEntries == 0
              ? HealthLevel.warning
              : HealthLevel.healthy,
        ),
        EnvironmentSignal(
          title: 'JAVA_HOME',
          value: javaHome == null || javaHome.isEmpty ? '未导出' : '已导出',
          detail: javaHome == null || javaHome.isEmpty
              ? '当前环境没有导出 JAVA_HOME，Java 相关构建可能依赖额外 shell 配置。'
              : javaHome,
          level: javaHome == null || javaHome.isEmpty
              ? HealthLevel.warning
              : HealthLevel.healthy,
        ),
        EnvironmentSignal(
          title: '配置来源',
          value: settingSources.isEmpty ? '未发现' : '已读取',
          detail: settingSources.isEmpty
              ? '暂时没有从 settings 命令读到显式配置来源，后续会继续补全 config 读取。'
              : '当前设置来源: ${settingSources.join(' / ')}',
          level: settingSources.isEmpty ? HealthLevel.info : HealthLevel.info,
        ),
      ];
    } catch (error) {
      if (isMiseCommandUnavailable(error)) {
        final installCommand = recommendedMiseInstallCommand();
        return [
          const EnvironmentSignal(
            title: 'mise CLI',
            value: '未检测到',
            detail: '当前桌面应用没有找到可执行的 mise 命令，因此无法读取当前环境信息。',
            level: HealthLevel.critical,
          ),
          const EnvironmentSignal(
            title: '首次安装状态',
            value: '需初始化',
            detail: '这更像首次启动引导场景，不应该继续展示模拟的工具链状态。',
            level: HealthLevel.warning,
          ),
          EnvironmentSignal(
            title: '下一步',
            value: '先安装 mise',
            detail: '建议先执行 `$installCommand`，然后重新打开应用或点击刷新。',
            level: HealthLevel.info,
          ),
          const EnvironmentSignal(
            title: '验证命令',
            value: 'mise --version',
            detail: '安装完成后先确认 CLI 能运行，再继续检查 PATH、shim 和项目配置。',
            level: HealthLevel.info,
          ),
        ];
      }
      return [
        const EnvironmentSignal(
          title: '环境信号读取失败',
          value: '暂不可用',
          detail: '这次没有成功从 mise CLI 读取环境信息，请稍后重试。',
          level: HealthLevel.warning,
        ),
        const EnvironmentSignal(
          title: '建议动作',
          value: '重新刷新',
          detail: '可以先点击刷新环境数据；如果仍然失败，再查看错误输出定位问题。',
          level: HealthLevel.info,
        ),
      ];
    }
  }

  @override
  Future<DashboardToolSummary> fetchDashboardToolSummary() async {
    try {
      final installedTools = await _queryService.fetchInstalledTools();
      var activeToolCount = 0;

      for (final versions in installedTools.values) {
        if (versions.any((version) => version.active)) {
          activeToolCount += 1;
        }
      }

      return DashboardToolSummary(
        activeToolCount: activeToolCount,
        installedToolCount: installedTools.length,
        commandPreview: 'mise ls --json\nmise current',
      );
    } catch (error) {
      if (isMiseCommandUnavailable(error)) {
        return const DashboardToolSummary(
          activeToolCount: 0,
          installedToolCount: 0,
          commandPreview: 'mise --version',
        );
      }
      return const DashboardToolSummary(
        activeToolCount: 0,
        installedToolCount: 0,
        commandPreview: 'mise ls --json\nmise current',
      );
    }
  }

  @override
  Future<List<ToolRecord>> fetchTools() async {
    final installedTools = await _queryService.fetchInstalledTools();
    final tools = <ToolRecord>[];

    for (final entry in installedTools.entries) {
      final tool = entry.key;
      final versions = entry.value;
      final active = _resolveActiveVersion(versions);
      if (active == null) continue;

      tools.add(
        ToolRecord(
          id: tool,
          name: _toolName(tool),
          category: '${_toolName(tool)} 版本管理',
          description: _toolDescription(tool),
          activeVersion: active.version,
          requestedVersion: active.requestedVersion ?? active.version,
          source: _formatSource(active.source),
          strategy: _strategyDescription(active.source),
          latestStableVersion: '待同步',
          latestPreviewVersion: active.version,
          installedVersions: versions
              .map(
                (version) => ToolVersionRecord(
                  version: version.version,
                  channel: version.active ? '当前生效' : '已安装',
                  note: _installedNote(version),
                  commandPreview: _useCommandForSource(
                    tool,
                    version.version,
                    active.source,
                  ),
                  level: version.active
                      ? HealthLevel.healthy
                      : HealthLevel.info,
                  isInstalled: version.installed,
                  isActive: version.active,
                ),
              )
              .toList(),
          remoteVersions: const [],
          projectImpacts: _buildProjectImpacts(active),
          quickActions: _buildQuickActions(
            tool: tool,
            activeVersion: active.version,
            updateVersion: null,
            source: active.source,
          ),
          commandPreview: _buildCommandPreview(
            tool: tool,
            activeVersion: active.version,
            updateVersion: null,
            source: active.source,
          ),
          level: HealthLevel.info,
          updateVersion: null,
          remoteState: ToolRemoteState.pending,
        ),
      );
    }

    tools.sort((a, b) => a.name.compareTo(b.name));
    return tools;
  }

  @override
  Future<ToolRecord> hydrateToolRemoteState(ToolRecord tool) async {
    final remoteLoad = await _safeFetchRemoteVersions(
      tool.id,
      activeVersion: tool.activeVersion,
    );
    final windowsShimPath = await _processService.inspectWindowsShimPath();
    final miseExecutable = await _safeFetchMiseExecutable(tool.id);
    final shellExecutable = await _safeFetchShellExecutable(tool.id);
    final selectedRemoteVersions = _selectRemoteCandidates(
      tool: tool.id,
      activeVersion: tool.activeVersion,
      requestedVersion: tool.requestedVersion,
      versions: remoteLoad.versions,
    );
    final updateVersion = _resolveUpdateVersion(
      activeVersion: tool.activeVersion,
      remoteVersions: selectedRemoteVersions,
      outdatedEntry: remoteLoad.latestStableVersion == null
          ? null
          : <String, dynamic>{'latest': remoteLoad.latestStableVersion},
    );
    final resolvedLatestStableVersion =
        updateVersion ??
        (selectedRemoteVersions.isNotEmpty
            ? selectedRemoteVersions.first.version
            : remoteLoad.latestStableVersion ?? tool.activeVersion);
    final resolvedLatestPreviewVersion = selectedRemoteVersions.isNotEmpty
        ? selectedRemoteVersions.last.version
        : remoteLoad.latestStableVersion ?? tool.activeVersion;
    final pathConflictNotice = _buildPathConflictNotice(
      tool: tool.id,
      miseExecutable: miseExecutable,
      shellExecutable: shellExecutable,
    );
    final notices = <InlineNotice>[
      if (remoteLoad.notice != null) remoteLoad.notice!,
      if (windowsShimPath.isMissing)
        _buildWindowsShimPathNotice(tool.id, windowsShimPath),
      if (pathConflictNotice != null) pathConflictNotice,
    ];

    return tool.copyWith(
      latestStableVersion: resolvedLatestStableVersion,
      latestPreviewVersion: resolvedLatestPreviewVersion,
      remoteVersions: selectedRemoteVersions
          .map(
            (version) => ToolVersionRecord(
              version: version.version,
              channel: version.rolling ? '滚动版本' : '远端版本',
              note: _remoteNote(version.version, tool.requestedVersion),
              commandPreview: version.version == updateVersion
                  ? _installAndUseCommandForSource(
                      tool.id,
                      version.version,
                      _resolveSourceRefFromLabel(tool.source),
                    )
                  : _installCommand(tool.id, version.version),
              level: version.version == updateVersion
                  ? HealthLevel.healthy
                  : HealthLevel.info,
              isRecommended: version.version == updateVersion,
            ),
          )
          .toList(),
      quickActions: _buildQuickActions(
        tool: tool.id,
        activeVersion: tool.activeVersion,
        updateVersion: updateVersion,
        source: _resolveSourceRefFromLabel(tool.source),
      ),
      commandPreview: _buildCommandPreview(
        tool: tool.id,
        activeVersion: tool.activeVersion,
        updateVersion: updateVersion,
        source: _resolveSourceRefFromLabel(tool.source),
      ),
      level: pathConflictNotice != null
          ? HealthLevel.warning
          : (updateVersion == null ? HealthLevel.info : HealthLevel.healthy),
      notices: notices,
      updateVersion: updateVersion,
      remoteState:
          remoteLoad.versions.isNotEmpty ||
              remoteLoad.latestStableVersion != null
          ? ToolRemoteState.ready
          : ToolRemoteState.unavailable,
    );
  }

  Future<_RemoteVersionLoadResult> _safeFetchRemoteVersions(
    String tool, {
    required String activeVersion,
  }) async {
    if (_prefersOutdatedLatestLookup(tool)) {
      final latestVersion = await _safeFetchOutdatedLatestVersion(
        tool,
        activeVersion: activeVersion,
      );
      return _RemoteVersionLoadResult(
        versions: _remoteVersionsFromLatest(
          tool: tool,
          activeVersion: activeVersion,
          latestVersion: latestVersion,
        ),
        latestStableVersion: latestVersion,
      );
    }

    try {
      return _RemoteVersionLoadResult(
        versions: await _queryService.fetchRemoteVersions(tool),
      );
    } catch (error) {
      final fallbackLatestVersion = await _safeFetchOutdatedLatestVersion(
        tool,
        activeVersion: activeVersion,
      );
      final fallbackVersions =
          fallbackLatestVersion != null &&
              fallbackLatestVersion != activeVersion
          ? <MiseRemoteToolVersionRef>[
              MiseRemoteToolVersionRef(
                tool: tool,
                version: fallbackLatestVersion,
                rolling: false,
              ),
            ]
          : const <MiseRemoteToolVersionRef>[];

      return _RemoteVersionLoadResult(
        versions: fallbackVersions,
        latestStableVersion: fallbackLatestVersion,
        notice: InlineNotice(
          title: '${_toolName(tool)} 远端目录暂时不可用',
          message: fallbackLatestVersion == null
              ? '已回退到本地已安装版本视图，当前激活版本和来源信息仍然可靠。可以稍后重试同步远端版本。'
              : '直接远端列表暂时不可用，已改用 mise outdated 兜底当前版本线的最新稳定版。',
          level: HealthLevel.warning,
          commandPreview: 'mise ls-remote --json $tool\n$error',
        ),
      );
    }
  }

  bool _prefersOutdatedLatestLookup(String tool) {
    return tool == 'python';
  }

  List<MiseRemoteToolVersionRef> _remoteVersionsFromLatest({
    required String tool,
    required String activeVersion,
    required String? latestVersion,
  }) {
    if (latestVersion == null || latestVersion == activeVersion) {
      return const <MiseRemoteToolVersionRef>[];
    }

    return <MiseRemoteToolVersionRef>[
      MiseRemoteToolVersionRef(
        tool: tool,
        version: latestVersion,
        rolling: false,
      ),
    ];
  }

  Future<String?> _safeFetchOutdatedLatestVersion(
    String tool, {
    required String activeVersion,
  }) async {
    try {
      final outdated = await _queryService.fetchOutdated();
      final entry = outdated[tool];
      if (entry is Map<String, dynamic>) {
        final latest = entry['latest']?.toString().trim();
        if (latest != null &&
            latest.isNotEmpty &&
            compareToolVersions(latest, activeVersion) > 0) {
          return latest;
        }
      }
      return activeVersion;
    } catch (_) {
      return null;
    }
  }

  Future<MiseResolvedExecutableRef?> _safeFetchMiseExecutable(
    String tool,
  ) async {
    try {
      return await _queryService.fetchExecutable(tool);
    } catch (_) {
      return null;
    }
  }

  Future<MiseResolvedExecutableRef?> _safeFetchShellExecutable(
    String tool,
  ) async {
    try {
      return await _queryService.fetchShellExecutable(tool);
    } catch (_) {
      return null;
    }
  }

  InlineNotice? _buildPathConflictNotice({
    required String tool,
    required MiseResolvedExecutableRef? miseExecutable,
    required MiseResolvedExecutableRef? shellExecutable,
  }) {
    final misePath = miseExecutable?.resolvedPath;
    final shellPath = shellExecutable?.resolvedPath;
    if (misePath == null || shellPath == null || misePath == shellPath) {
      return null;
    }

    final shellOwner = _runtimeOwnerLabel(shellPath);

    return InlineNotice(
      title: '${_toolName(tool)} 当前 shell 仍命中其他版本管理器',
      message:
          'mise 解析到的是 `$misePath`，但当前 shell 实际执行的是 `$shellPath`。'
          '${shellOwner == null ? '' : ' 这更像 `$shellOwner` 抢在了 mise 前面。'} '
          '这不是安装失败，而是 PATH 优先级冲突。',
      level: HealthLevel.warning,
      commandPreview:
          'mise current $tool\n'
          'mise which $tool\n'
          'which $tool\n'
          'echo \$PATH',
    );
  }

  InlineNotice _buildWindowsShimPathNotice(
    String tool,
    WindowsShimPathStatus status,
  ) {
    return InlineNotice(
      title: '检测到 Windows 终端尚未接入 mise shims',
      message:
          status.detail ??
          '${_toolName(tool)} 已由 mise 管理，但新的 cmd / PowerShell 会话里还不能直接调用。执行下面的命令后，重新打开终端即可生效。',
      level: HealthLevel.warning,
      commandPreview: status.commandPreview,
    );
  }

  String? _runtimeOwnerLabel(String path) {
    if (path.contains('/.nvm/')) {
      return 'nvm';
    }
    if (path.contains('/.volta/')) {
      return 'Volta';
    }
    if (path.contains('/.asdf/')) {
      return 'asdf';
    }
    if (path.contains('/.local/share/fnm/')) {
      return 'fnm';
    }
    return null;
  }

  MiseInstalledToolVersionRef? _resolveActiveVersion(
    List<MiseInstalledToolVersionRef> versions,
  ) {
    for (final version in versions) {
      if (version.active) {
        return version;
      }
    }
    return versions.isEmpty ? null : versions.first;
  }

  List<MiseRemoteToolVersionRef> _selectRemoteCandidates({
    required String tool,
    required String activeVersion,
    required String requestedVersion,
    required List<MiseRemoteToolVersionRef> versions,
  }) {
    final normalizedRequested = requestedVersion.trim();
    final requestedMajor = _leadingMajor(normalizedRequested);
    final scopedVersions = _filterRemoteCandidateScope(
      tool: tool,
      requestedMajor: requestedMajor,
      versions: versions,
    ).toList();

    final upgradeCandidates =
        scopedVersions
            .where(
              (version) =>
                  compareToolVersions(version.version, activeVersion) > 0,
            )
            .toList()
          ..sort(
            (left, right) => compareToolVersions(left.version, right.version),
          );

    if (upgradeCandidates.isNotEmpty) {
      return _latestRemoteCandidates(upgradeCandidates);
    }

    final installableCandidates =
        scopedVersions
            .where((version) => version.version != activeVersion)
            .toList()
          ..sort(
            (left, right) => compareToolVersions(left.version, right.version),
          );

    return _latestRemoteCandidates(installableCandidates);
  }

  Iterable<MiseRemoteToolVersionRef> _filterRemoteCandidateScope({
    required String tool,
    required String? requestedMajor,
    required List<MiseRemoteToolVersionRef> versions,
  }) {
    final nonRolling = versions.where((version) => !version.rolling);

    if (tool == 'java' && requestedMajor != null) {
      return nonRolling.where(
        (version) =>
            _leadingMajor(version.version) == requestedMajor &&
            !_isJavaRuntimeOnlyVersion(version.version),
      );
    }

    if (tool == 'flutter') {
      final stableVersions = nonRolling
          .where((version) => version.version.contains('stable'))
          .toList();
      return stableVersions.isNotEmpty ? stableVersions : nonRolling;
    }

    if (requestedMajor != null) {
      return nonRolling.where(
        (version) => version.version.startsWith('$requestedMajor.'),
      );
    }

    return nonRolling;
  }

  bool _isJavaRuntimeOnlyVersion(String version) {
    final normalized = version.toLowerCase();
    return normalized.contains('-jre') || normalized.contains('+jre');
  }

  List<MiseRemoteToolVersionRef> _latestRemoteCandidates(
    List<MiseRemoteToolVersionRef> sortedVersions,
  ) {
    if (sortedVersions.isEmpty) {
      return const [];
    }

    final tail = sortedVersions.length <= 4
        ? sortedVersions
        : sortedVersions.sublist(sortedVersions.length - 4);
    return tail.reversed.toList();
  }

  String? _resolveUpdateVersion({
    required String activeVersion,
    required List<MiseRemoteToolVersionRef> remoteVersions,
    required dynamic outdatedEntry,
  }) {
    if (outdatedEntry is Map<String, dynamic>) {
      final latest = outdatedEntry['latest'] as String?;
      if (latest != null && compareToolVersions(latest, activeVersion) > 0) {
        return latest;
      }
    }

    if (remoteVersions.isEmpty) {
      return null;
    }

    return compareToolVersions(remoteVersions.first.version, activeVersion) > 0
        ? remoteVersions.first.version
        : null;
  }

  List<ToolProjectImpact> _buildProjectImpacts(
    MiseInstalledToolVersionRef active,
  ) {
    final source = active.source;
    if (source?.path == null) {
      return const [];
    }

    final path = source!.path!;
    final isGlobal = path.contains('/.config/mise/config.toml');

    return [
      ToolProjectImpact(
        projectName: isGlobal ? '全局配置' : _basename(path),
        path: path,
        requestedVersion: active.requestedVersion ?? active.version,
        resolvedVersion: active.version,
        reason: isGlobal
            ? '当前版本来自全局配置文件，未被项目级 mise.toml 覆盖。'
            : '当前版本由该配置文件直接声明并在当前工作目录生效。',
        level: isGlobal ? HealthLevel.info : HealthLevel.healthy,
      ),
    ];
  }

  List<ToolCommandAction> _buildQuickActions({
    required String tool,
    required String activeVersion,
    required String? updateVersion,
    required MiseSourceRef? source,
  }) {
    return [
      if (updateVersion != null)
        ToolCommandAction(
          label: '升级到推荐版本',
          summary: '安装并切换到 $updateVersion。',
          command: _installAndUseCommandForSource(tool, updateVersion, source),
          level: HealthLevel.healthy,
        ),
      ToolCommandAction(
        label: '查看当前来源',
        summary: '确认当前生效版本和来源文件。',
        command: 'mise ls --json\nmise which $tool',
        level: HealthLevel.info,
      ),
      ToolCommandAction(
        label: '回看当前版本',
        summary: '查看 $activeVersion 在当前目录的生效状态。',
        command: 'mise current $tool',
        level: HealthLevel.info,
      ),
    ];
  }

  String _buildCommandPreview({
    required String tool,
    required String activeVersion,
    required String? updateVersion,
    required MiseSourceRef? source,
  }) {
    final commands = <String>[
      'mise current $tool',
      'mise ls --json',
      if (updateVersion != null) _installCommand(tool, updateVersion),
      if (updateVersion != null)
        _useCommandForSource(tool, updateVersion, source),
      'mise which $tool',
    ];

    return commands.join('\n');
  }

  String _toolName(String tool) => switch (tool) {
    'go' => 'Go',
    'java' => 'Java',
    'python' => 'Python',
    'flutter' => 'Flutter',
    _ => tool[0].toUpperCase() + tool.substring(1),
  };

  String _toolDescription(String tool) => switch (tool) {
    'go' => '用于本地后端与 CLI 工具链构建，通常由全局默认版本托底。',
    'java' => '需要关注版本与发行版组合，尤其适合在界面中直观看来源。',
    'python' => '常用于脚本、工具链和数据处理，项目覆盖关系很容易产生分歧。',
    'flutter' => '当前项目的核心工具包，最需要明确显示项目级锁定与实际安装版本。',
    _ => '通过 mise 管理的本地开发工具版本。',
  };

  String _formatSource(MiseSourceRef? source) {
    if (source == null) {
      return '未知';
    }

    return switch (source.type) {
      'mise.toml' =>
        (source.path?.contains('/.config/mise/') ?? false) ? '全局' : '项目',
      _ => source.type,
    };
  }

  MiseSourceRef? _resolveSourceRefFromLabel(String source) {
    return switch (source) {
      '全局' => const MiseSourceRef(
        type: 'mise.toml',
        path: '/.config/mise/config.toml',
      ),
      '项目' => const MiseSourceRef(
        type: 'mise.toml',
        path: '/workspace/mise.toml',
      ),
      _ => null,
    };
  }

  String _strategyDescription(MiseSourceRef? source) {
    if (source?.path == null) {
      return '当前版本来自本地已安装列表，但还没有显式来源信息。';
    }

    if (source!.path!.contains('/.config/mise/')) {
      return '当前版本由全局 config.toml 或全局 mise.toml 决定，项目未覆盖时会直接继承。';
    }

    return '当前版本由项目级 mise.toml 决定，优先级高于全局默认版本。';
  }

  String _installedNote(MiseInstalledToolVersionRef version) {
    if (version.active) {
      return '这是当前工作目录实际生效的版本。';
    }
    if (version.source?.path != null) {
      return '已安装，可在需要时切换；最近一次来源文件来自 ${version.source!.path}.';
    }
    return '已安装但当前未激活。';
  }

  String _remoteNote(String version, String requestedVersion) {
    return '远端可用版本，可根据当前请求版本 $requestedVersion 决定是否安装。';
  }

  String _installCommand(String tool, String version) =>
      'mise install $tool@$version';

  String _useCommand(String tool, String version) => 'mise use $tool@$version';

  String _useCommandForSource(
    String tool,
    String version,
    MiseSourceRef? source,
  ) {
    if (source?.path != null && source!.path!.contains('/.config/mise/')) {
      return 'mise use --global $tool@$version';
    }
    return _useCommand(tool, version);
  }

  String _installAndUseCommandForSource(
    String tool,
    String version,
    MiseSourceRef? source,
  ) {
    return [
      _installCommand(tool, version),
      _useCommandForSource(tool, version, source),
    ].join('\n');
  }

  String? _leadingMajor(String input) {
    final match = RegExp(r'(\d+)').firstMatch(input);
    return match?.group(1);
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  List<String> _collectSettingSources(Map<String, dynamic> settings) {
    final sources = <String>{};

    void visit(dynamic node) {
      if (node is Map<String, dynamic>) {
        final source = node['source']?.toString();
        if (source != null && source.isNotEmpty) {
          sources.add(source);
        }
        for (final value in node.values) {
          visit(value);
        }
      }
    }

    visit(settings);
    return sources.toList()..sort();
  }
}

int compareToolVersions(String left, String right) {
  final leftTokens = _VersionToken.parse(left);
  final rightTokens = _VersionToken.parse(right);
  final limit = leftTokens.length > rightTokens.length
      ? leftTokens.length
      : rightTokens.length;

  for (var index = 0; index < limit; index += 1) {
    if (index >= leftTokens.length) {
      return _remainingTokenWeight(rightTokens, index) == 0 ? 0 : -1;
    }
    if (index >= rightTokens.length) {
      return _remainingTokenWeight(leftTokens, index) == 0 ? 0 : 1;
    }

    final compared = leftTokens[index].compareTo(rightTokens[index]);
    if (compared != 0) {
      return compared;
    }
  }

  return 0;
}

int _remainingTokenWeight(List<_VersionToken> tokens, int startIndex) {
  for (var index = startIndex; index < tokens.length; index += 1) {
    final token = tokens[index];
    if (token is _NumericVersionToken && token.value == 0) {
      continue;
    }
    return 1;
  }
  return 0;
}

sealed class _VersionToken {
  const _VersionToken();

  factory _VersionToken.numeric(int value) = _NumericVersionToken;
  factory _VersionToken.text(String value) = _TextVersionToken;

  static List<_VersionToken> parse(String input) {
    final matches = RegExp(r'\d+|[A-Za-z]+').allMatches(input);
    return matches
        .map((match) {
          final value = match.group(0)!;
          final numeric = int.tryParse(value);
          if (numeric != null) {
            return _VersionToken.numeric(numeric);
          }
          return _VersionToken.text(value.toLowerCase());
        })
        .toList(growable: false);
  }

  int compareTo(_VersionToken other);
}

final class _NumericVersionToken extends _VersionToken {
  const _NumericVersionToken(this.value);

  final int value;

  @override
  int compareTo(_VersionToken other) {
    return switch (other) {
      _NumericVersionToken(:final value) => this.value.compareTo(value),
      _TextVersionToken() => -1,
    };
  }
}

final class _TextVersionToken extends _VersionToken {
  const _TextVersionToken(this.value);

  final String value;

  @override
  int compareTo(_VersionToken other) {
    return switch (other) {
      _NumericVersionToken() => 1,
      _TextVersionToken(:final value) => this.value.compareTo(value),
    };
  }
}

class MockMiseCliService implements MiseCliService {
  const MockMiseCliService();

  @override
  Future<List<EnvironmentSignal>> fetchEnvironmentSignals() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));

    return const [
      EnvironmentSignal(
        title: 'Shell 激活',
        value: '已激活',
        detail: 'zsh 已注入 mise hook，当前会话能正确解析 shim。',
        level: HealthLevel.healthy,
      ),
      EnvironmentSignal(
        title: 'PATH 顺序',
        value: '1 项提醒',
        detail: 'Homebrew bin 在部分项目 shell 中优先于 shim，建议保持 shim 靠前。',
        level: HealthLevel.warning,
      ),
      EnvironmentSignal(
        title: 'Shim 状态',
        value: '稳定',
        detail: 'node、python、java 的 shim 已命中当前激活版本。',
        level: HealthLevel.healthy,
      ),
      EnvironmentSignal(
        title: '代理与源配置',
        value: '待确认',
        detail: 'cargo 镜像与 Java 下载源还没有统一到界面配置入口。',
        level: HealthLevel.info,
      ),
    ];
  }

  @override
  Future<DashboardToolSummary> fetchDashboardToolSummary() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));

    return const DashboardToolSummary(
      activeToolCount: 4,
      installedToolCount: 6,
      commandPreview: 'mise ls --json\nmise current',
    );
  }

  @override
  Future<ToolRecord> hydrateToolRemoteState(ToolRecord tool) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    return tool.copyWith(
      latestStableVersion: tool.activeVersion,
      latestPreviewVersion: tool.activeVersion,
      remoteState: ToolRemoteState.ready,
    );
  }

  @override
  Future<List<ToolRecord>> fetchTools() async {
    await Future<void>.delayed(const Duration(milliseconds: 180));

    return const [
      ToolRecord(
        id: 'node',
        name: 'Node.js',
        category: 'JavaScript 运行时',
        description: '前端与全栈项目最常用的运行时，当前主要来自全局版本策略。',
        activeVersion: '20.16.0',
        requestedVersion: '20',
        source: '全局',
        strategy: '全局默认版本，项目未声明时直接继承。',
        latestStableVersion: '20.17.0',
        latestPreviewVersion: '23.0.0-rc.1',
        installedVersions: [
          ToolVersionRecord(
            version: '18.20.4',
            channel: '长期支持',
            note: '仍被老项目引用，适合作为兼容兜底。',
            commandPreview: 'mise use node@18.20.4',
            level: HealthLevel.info,
            isInstalled: true,
          ),
          ToolVersionRecord(
            version: '20.16.0',
            channel: '当前生效',
            note: '当前 shell 与多数项目的解析结果。',
            commandPreview: 'mise use --global node@20.16.0',
            level: HealthLevel.healthy,
            isInstalled: true,
            isActive: true,
          ),
          ToolVersionRecord(
            version: '22.3.0',
            channel: '当前分支',
            note: '已下载但尚未进入默认策略。',
            commandPreview: 'mise use node@22.3.0',
            level: HealthLevel.info,
            isInstalled: true,
          ),
        ],
        remoteVersions: [
          ToolVersionRecord(
            version: '20.17.0',
            channel: '稳定版',
            note: '建议升级目标，与现有项目兼容性最好。',
            commandPreview:
                'mise install node@20.17.0\nmise use --global node@20.17.0',
            level: HealthLevel.healthy,
            isRecommended: true,
          ),
          ToolVersionRecord(
            version: '22.4.1',
            channel: '当前分支',
            note: '适合新项目试用，但需要重新验证部分依赖。',
            commandPreview: 'mise install node@22.4.1',
            level: HealthLevel.info,
          ),
          ToolVersionRecord(
            version: '23.0.0-rc.1',
            channel: '预览版',
            note: '预览版，仅建议在隔离项目中验证。',
            commandPreview: 'mise install node@23.0.0-rc.1',
            level: HealthLevel.warning,
          ),
        ],
        projectImpacts: [
          ToolProjectImpact(
            projectName: 'mise_gui',
            path: '~/Documents/FlutterProject/mise_gui',
            requestedVersion: '20',
            resolvedVersion: '20.16.0',
            reason: '当前项目没有单独覆盖 Node，直接继承全局版本。',
            level: HealthLevel.healthy,
          ),
          ToolProjectImpact(
            projectName: 'infra-dashboard',
            path: '~/Workspaces/infra-dashboard',
            requestedVersion: '18',
            resolvedVersion: '18.20.4',
            reason: '项目锁定旧版 Node，升级全局不会影响它。',
            level: HealthLevel.info,
          ),
        ],
        quickActions: [
          ToolCommandAction(
            label: '升级到稳定版',
            summary: '安装并切换到 Node 20.17.0。',
            command:
                'mise install node@20.17.0\nmise use --global node@20.17.0',
            level: HealthLevel.healthy,
          ),
          ToolCommandAction(
            label: '查看来源',
            summary: '确认当前 shell 究竟命中了哪一层版本。',
            command: 'mise current node\nmise where node',
            level: HealthLevel.info,
          ),
        ],
        commandPreview:
            'mise use --global node@20.16.0\nmise install node@20.17.0',
        level: HealthLevel.healthy,
        updateVersion: '20.17.0',
      ),
      ToolRecord(
        id: 'python',
        name: 'Python',
        category: '脚本运行时',
        description: '兼顾项目脚本和工具链依赖，当前版本被多个项目覆盖。',
        activeVersion: '3.11.9',
        requestedVersion: '3.11',
        source: '项目覆盖',
        strategy: '项目优先于全局，当前工作目录覆盖了默认 Python。',
        latestStableVersion: '3.12.5',
        latestPreviewVersion: '3.13.0b2',
        installedVersions: [
          ToolVersionRecord(
            version: '3.10.14',
            channel: '旧版本',
            note: '被老脚本链路保留，建议逐步淘汰。',
            commandPreview: 'mise use python@3.10.14',
            level: HealthLevel.warning,
            isInstalled: true,
          ),
          ToolVersionRecord(
            version: '3.11.9',
            channel: '当前生效',
            note: '当前项目命中的解释器版本。',
            commandPreview: 'mise use python@3.11.9',
            level: HealthLevel.healthy,
            isInstalled: true,
            isActive: true,
          ),
          ToolVersionRecord(
            version: '3.12.4',
            channel: '全局默认',
            note: '全局默认版本，但在当前目录被覆盖。',
            commandPreview: 'mise use --global python@3.12.4',
            level: HealthLevel.info,
            isInstalled: true,
          ),
        ],
        remoteVersions: [
          ToolVersionRecord(
            version: '3.11.10',
            channel: '补丁版',
            note: '最稳妥的升级路径，可先在当前项目尝试。',
            commandPreview: 'mise use python@3.11.10',
            level: HealthLevel.healthy,
            isRecommended: true,
          ),
          ToolVersionRecord(
            version: '3.12.5',
            channel: '稳定版',
            note: '适合准备切回全局统一策略时使用。',
            commandPreview: 'mise install python@3.12.5',
            level: HealthLevel.info,
          ),
          ToolVersionRecord(
            version: '3.13.0b2',
            channel: '预览版',
            note: '仅建议用于兼容性验证。',
            commandPreview: 'mise install python@3.13.0b2',
            level: HealthLevel.warning,
          ),
        ],
        projectImpacts: [
          ToolProjectImpact(
            projectName: 'api-gateway',
            path: '~/Workspaces/api-gateway',
            requestedVersion: '3.11',
            resolvedVersion: '3.11.9',
            reason: '项目明确锁定 Python 3.11，升级全局不会直接影响它。',
            level: HealthLevel.healthy,
          ),
          ToolProjectImpact(
            projectName: 'data-lab',
            path: '~/Workspaces/data-lab',
            requestedVersion: '3.12',
            resolvedVersion: '3.12.4',
            reason: '该项目依赖全局 3.12 分支，切换全局前需要先校验。',
            level: HealthLevel.warning,
          ),
        ],
        quickActions: [
          ToolCommandAction(
            label: '升级当前项目',
            summary: '仅把当前目录升级到 3.11.10。',
            command: 'mise use python@3.11.10',
            level: HealthLevel.healthy,
          ),
          ToolCommandAction(
            label: '回看覆盖关系',
            summary: '确认是哪个 mise.toml 覆盖了全局 Python。',
            command: 'mise ls --current python\ncat mise.toml',
            level: HealthLevel.info,
          ),
        ],
        commandPreview: 'mise use python@3.11.9\nmise ls python',
        level: HealthLevel.warning,
        updateVersion: '3.11.10',
      ),
      ToolRecord(
        id: 'java',
        name: 'Java',
        category: 'Java 工具链',
        description: '需要展示发行版、别名和版本来源，是界面里最值得做透的工具之一。',
        activeVersion: 'temurin-21.0.3',
        requestedVersion: 'java@21',
        source: '配置别名',
        strategy: '通过别名与发行版策略把 java@21 解析到 temurin。',
        latestStableVersion: 'temurin-21.0.4',
        latestPreviewVersion: 'temurin-22.0.2',
        installedVersions: [
          ToolVersionRecord(
            version: 'zulu-17.52.17',
            channel: '旧版发行商',
            note: '历史项目仍依赖 Zulu 17，不能直接删除。',
            commandPreview: 'mise use java@zulu-17.52.17',
            level: HealthLevel.warning,
            isInstalled: true,
          ),
          ToolVersionRecord(
            version: 'temurin-21.0.3',
            channel: '当前别名',
            note: '当前别名解析到的默认 JDK。',
            commandPreview: 'mise use --global java@temurin-21.0.3',
            level: HealthLevel.healthy,
            isInstalled: true,
            isActive: true,
            isAlias: true,
          ),
        ],
        remoteVersions: [
          ToolVersionRecord(
            version: 'temurin-21.0.4',
            channel: '稳定版',
            note: '推荐补丁升级，能保持别名策略不变。',
            commandPreview: 'mise install java@temurin-21.0.4',
            level: HealthLevel.healthy,
            isRecommended: true,
          ),
          ToolVersionRecord(
            version: 'temurin-22.0.2',
            channel: '下一大版本',
            note: '需要评估 Maven/Gradle 项目兼容性后再升级。',
            commandPreview: 'mise install java@temurin-22.0.2',
            level: HealthLevel.info,
          ),
        ],
        projectImpacts: [
          ToolProjectImpact(
            projectName: 'legacy-jvm',
            path: '~/Archives/legacy-jvm',
            requestedVersion: '17',
            resolvedVersion: 'zulu-17.52.17',
            reason: '老项目依赖 Zulu 17，当前别名策略不会影响它。',
            level: HealthLevel.warning,
          ),
          ToolProjectImpact(
            projectName: 'infra-dashboard',
            path: '~/Workspaces/infra-dashboard',
            requestedVersion: '21',
            resolvedVersion: 'temurin-21.0.3',
            reason: '项目直接跟随别名策略，可无缝接受补丁升级。',
            level: HealthLevel.healthy,
          ),
        ],
        quickActions: [
          ToolCommandAction(
            label: '升级 Temurin',
            summary: '保留别名语义，只升级发行版的具体版本。',
            command:
                'mise install java@temurin-21.0.4\nmise use --global java@temurin-21.0.4',
            level: HealthLevel.healthy,
          ),
          ToolCommandAction(
            label: '检查别名',
            summary: '查看 java@21 当前究竟解析到哪里。',
            command: 'mise alias ls java\nmise current java',
            level: HealthLevel.info,
          ),
        ],
        commandPreview:
            'mise settings set java.vendor temurin\nmise use --global java@temurin-21.0.3',
        level: HealthLevel.info,
        updateVersion: 'temurin-21.0.4',
      ),
      ToolRecord(
        id: 'bun',
        name: 'Bun',
        category: 'JavaScript 运行时',
        description: '作为更快的 JS 工具链补充，当前仅在个别项目启用。',
        activeVersion: '1.1.17',
        requestedVersion: '1',
        source: '全局',
        strategy: '默认不进入所有项目，只在明确启用的仓库中激活。',
        latestStableVersion: '1.1.19',
        latestPreviewVersion: '1.1.19',
        installedVersions: [
          ToolVersionRecord(
            version: '1.1.17',
            channel: '当前生效',
            note: '当前默认 Bun 版本，尚未广泛推广到所有项目。',
            commandPreview: 'mise use bun@1.1.17',
            level: HealthLevel.healthy,
            isInstalled: true,
            isActive: true,
          ),
        ],
        remoteVersions: [
          ToolVersionRecord(
            version: '1.1.18',
            channel: '补丁版',
            note: '轻量补丁升级，可先在单个项目验证。',
            commandPreview: 'mise install bun@1.1.18',
            level: HealthLevel.info,
          ),
          ToolVersionRecord(
            version: '1.1.19',
            channel: '稳定版',
            note: '当前建议升级目标。',
            commandPreview: 'mise install bun@1.1.19\nmise use bun@1.1.19',
            level: HealthLevel.healthy,
            isRecommended: true,
          ),
        ],
        projectImpacts: [
          ToolProjectImpact(
            projectName: 'frontend-spike',
            path: '~/Sandbox/frontend-spike',
            requestedVersion: '1.1',
            resolvedVersion: '1.1.17',
            reason: '仅实验项目使用 Bun，适合先在这里试升级。',
            level: HealthLevel.info,
          ),
        ],
        quickActions: [
          ToolCommandAction(
            label: '升级 Bun',
            summary: '把默认 Bun 升到 1.1.19。',
            command: 'mise install bun@1.1.19\nmise use bun@1.1.19',
            level: HealthLevel.healthy,
          ),
          ToolCommandAction(
            label: '查看覆盖范围',
            summary: '确认到底哪些项目在使用 Bun。',
            command: 'mise ls bun\nmise current bun',
            level: HealthLevel.info,
          ),
        ],
        commandPreview: 'mise install bun@1.1.19\nmise use bun@1.1.19',
        level: HealthLevel.healthy,
        updateVersion: '1.1.19',
      ),
    ];
  }
}

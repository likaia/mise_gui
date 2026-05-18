import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mise_gui/app/bootstrap/app.dart';
import 'package:mise_gui/app/bootstrap/dependencies.dart';
import 'package:mise_gui/app/router/app_destination.dart';
import 'package:mise_gui/app/theme/app_theme.dart';
import 'package:mise_gui/features/dashboard/application/dashboard_provider.dart';
import 'package:mise_gui/features/tools/presentation/tools_page.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/services/app_release_service.dart';
import 'package:mise_gui/services/app_update_service.dart';
import 'package:mise_gui/services/history_service.dart';
import 'package:mise_gui/services/mise_cli_service.dart';
import 'package:mise_gui/services/mise_process_service.dart';
import 'package:mise_gui/services/project_scan_service.dart';

class _FakeAppReleaseService implements AppReleaseService {
  const _FakeAppReleaseService();

  @override
  Future<AppVersionInfo> load() async => const AppVersionInfo(
    appName: 'mise_gui',
    packageName: 'dev.test.mise_gui',
    version: '1.0.0',
    buildNumber: '1',
  );
}

class _MissingMiseProcessService implements MiseProcessService {
  const _MissingMiseProcessService();

  @override
  Future<ShellEnvironmentLoadResult> inspectShellEnvironment() async {
    return const ShellEnvironmentLoadResult(
      source: ShellEnvironmentSource.desktopFallback,
      detail: '未能可靠读取登录 shell 环境，已回退到桌面进程环境。',
    );
  }

  @override
  Future<WindowsShimPathStatus> inspectWindowsShimPath() async {
    return const WindowsShimPathStatus(
      source: WindowsShimPathSource.unsupported,
    );
  }

  @override
  Future<MiseCommandResult> run(MiseCommandRequest request) async {
    throw MiseProcessException(
      message: 'Unable to launch mise CLI from the desktop app',
      result: MiseCommandResult(
        request: request,
        stdout: '',
        stderr: 'No such file or directory',
        exitCode: 2,
        duration: Duration.zero,
      ),
    );
  }

  @override
  Future<String> resolveExecutablePath() {
    throw UnimplementedError();
  }
}

class _NoopAppUpdateService implements AppUpdateService {
  const _NoopAppUpdateService();

  @override
  Future<AppUpdateInfo?> checkForUpdate({
    required String currentVersion,
  }) async {
    return null;
  }
}

class _HasUpdateAppUpdateService implements AppUpdateService {
  const _HasUpdateAppUpdateService();

  @override
  Future<AppUpdateInfo?> checkForUpdate({
    required String currentVersion,
  }) async {
    return const AppUpdateInfo(
      currentVersion: '1.0.0',
      latestVersion: '1.0.1',
      tagName: 'v1.0.1',
      releaseNotes: '修复若干启动和安装问题',
      releaseUrl: 'https://github.com/likaia/mise_gui/releases/tag/v1.0.1',
    );
  }
}

class _FlakyToolDetailMiseCliService extends MockMiseCliService {
  var hydrateAttempts = 0;

  @override
  Future<ToolRecord> hydrateToolRemoteState(ToolRecord tool) async {
    hydrateAttempts += 1;
    if (hydrateAttempts == 1) {
      throw StateError('detail failed');
    }
    return super.hydrateToolRemoteState(tool);
  }
}

class _RemoteNoticeRetryMiseCliService extends MockMiseCliService {
  var hydrateAttempts = 0;

  @override
  Future<ToolRecord> hydrateToolRemoteState(ToolRecord tool) async {
    hydrateAttempts += 1;
    if (hydrateAttempts == 1) {
      return tool.copyWith(
        latestStableVersion: tool.activeVersion,
        remoteVersions: const [],
        notices: const [
          InlineNotice(
            title: 'Node.js 远端目录暂时不可用',
            message: '直接远端列表暂时不可用，已改用 mise outdated 兜底当前版本线的最新稳定版。',
            level: HealthLevel.warning,
            commandPreview: 'mise ls-remote --json node',
          ),
        ],
        remoteState: ToolRemoteState.unavailable,
      );
    }
    return super.hydrateToolRemoteState(tool);
  }
}

const _dashboardSnapshot = DashboardSnapshot(
  title: '环境总览',
  subtitle: '',
  metrics: [
    SummaryMetric(
      label: '当前系统',
      value: 'macOS 26.4.1',
      caption:
          'Build 25E253\narm64 架构\nApple M5 Pro\n内存 48 GB\n磁盘 557 GB 可用 / 926 GB 总计',
      level: HealthLevel.info,
    ),
    SummaryMetric(
      label: '已装工具',
      value: '5 个',
      caption: '当前已纳入 mise 管理的本地工具。',
      level: HealthLevel.healthy,
    ),
    SummaryMetric(
      label: '项目覆盖',
      value: '1 个项目',
      caption: '已扫描 1 个项目，发现 1 处覆盖。',
      level: HealthLevel.warning,
    ),
    SummaryMetric(
      label: 'Mise 版本',
      value: '2026.1.0',
      caption: 'mise is available',
      level: HealthLevel.healthy,
    ),
  ],
  signals: [],
  toolSummary: DashboardToolSummary(
    activeToolCount: 3,
    installedToolCount: 5,
    commandPreview: 'mise current',
  ),
  recentHistory: [],
  riskHighlights: [],
);

void main() {
  Future<void> pumpMiseGuiApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appReleaseServiceProvider.overrideWithValue(
            const _FakeAppReleaseService(),
          ),
          appUpdateServiceProvider.overrideWithValue(
            const _NoopAppUpdateService(),
          ),
          miseAvailableProvider.overrideWith((ref) => true),
          dashboardProvider.overrideWith((ref) => _dashboardSnapshot),
          miseCliServiceProvider.overrideWithValue(const MockMiseCliService()),
          historyServiceProvider.overrideWithValue(const MockHistoryService()),
          projectScanServiceProvider.overrideWithValue(
            const MockProjectScanService(),
          ),
        ],
        child: const MiseGuiApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('loads dashboard shell', (WidgetTester tester) async {
    await pumpMiseGuiApp(tester);

    expect(find.text('总览'), findsWidgets);
    expect(find.text('工具'), findsWidgets);
    expect(find.text('项目'), findsWidgets);
  });

  testWidgets('dashboard system metric groups device details', (
    WidgetTester tester,
  ) async {
    await pumpMiseGuiApp(tester);

    expect(find.text('macOS 26.4.1'), findsOneWidget);
    expect(find.text('Build'), findsOneWidget);
    expect(find.text('25E253'), findsOneWidget);
    expect(find.text('架构'), findsOneWidget);
    expect(find.text('arm64'), findsOneWidget);
    expect(find.text('处理器'), findsOneWidget);
    expect(find.text('Apple M5 Pro'), findsOneWidget);
    expect(find.text('内存'), findsOneWidget);
    expect(find.text('48 GB'), findsOneWidget);
    expect(find.text('磁盘'), findsOneWidget);
    expect(find.text('557 GB 可用 / 926 GB 总计'), findsOneWidget);
  });

  testWidgets('dashboard installed tools metric opens tools tab', (
    WidgetTester tester,
  ) async {
    await pumpMiseGuiApp(tester);
    final router = GoRouter.of(
      tester.element(find.byKey(const ValueKey('dashboard-metric-tools'))),
    );

    await tester.tap(find.byKey(const ValueKey('dashboard-metric-tools')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      router.routeInformationProvider.value.uri.path,
      AppDestination.tools.path,
    );
  });

  testWidgets('dashboard project coverage metric opens projects tab', (
    WidgetTester tester,
  ) async {
    await pumpMiseGuiApp(tester);
    final router = GoRouter.of(
      tester.element(find.byKey(const ValueKey('dashboard-metric-projects'))),
    );

    await tester.tap(find.byKey(const ValueKey('dashboard-metric-projects')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      router.routeInformationProvider.value.uri.path,
      AppDestination.projects.path,
    );
  });

  testWidgets('tools detail failure shows retry and removes command shortcut', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final miseCliService = _FlakyToolDetailMiseCliService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          miseCliServiceProvider.overrideWithValue(miseCliService),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ToolsPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    await tester.tap(find.text('Node.js').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('Node.js 详情读取失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('最新: 读取失败'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();

    expect(miseCliService.hydrateAttempts, 2);
    expect(find.text('Node.js 详情读取失败'), findsNothing);
    expect(find.text('18.20.4'), findsOneWidget);
    expect(find.byTooltip('查看命令'), findsNothing);
    expect(find.text('查看命令'), findsNothing);
  });

  testWidgets('tools remote notice can retry detail refresh', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final miseCliService = _RemoteNoticeRetryMiseCliService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          miseCliServiceProvider.overrideWithValue(miseCliService),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ToolsPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    await tester.tap(find.text('Node.js').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('Node.js 远端目录暂时不可用'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('查看命令'), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();

    expect(miseCliService.hydrateAttempts, 2);
    expect(find.text('Node.js 远端目录暂时不可用'), findsNothing);
  });

  testWidgets('shows install guidance when mise is unavailable', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appReleaseServiceProvider.overrideWithValue(
            const _FakeAppReleaseService(),
          ),
          appUpdateServiceProvider.overrideWithValue(
            const _NoopAppUpdateService(),
          ),
          miseProcessServiceProvider.overrideWithValue(
            const _MissingMiseProcessService(),
          ),
          miseCliServiceProvider.overrideWithValue(const MockMiseCliService()),
          historyServiceProvider.overrideWithValue(const MockHistoryService()),
          projectScanServiceProvider.overrideWithValue(
            const MockProjectScanService(),
          ),
        ],
        child: const MiseGuiApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('这台电脑还没有安装 mise'), findsOneWidget);
    expect(find.text(recommendedMiseInstallCommand()), findsOneWidget);
  });

  testWidgets('keeps short missing-mise layout free of footer bubble', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1314, 758);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appReleaseServiceProvider.overrideWithValue(
            const _FakeAppReleaseService(),
          ),
          appUpdateServiceProvider.overrideWithValue(
            const _NoopAppUpdateService(),
          ),
          miseProcessServiceProvider.overrideWithValue(
            const _MissingMiseProcessService(),
          ),
          miseCliServiceProvider.overrideWithValue(const MockMiseCliService()),
          historyServiceProvider.overrideWithValue(const MockHistoryService()),
          projectScanServiceProvider.overrideWithValue(
            const MockProjectScanService(),
          ),
        ],
        child: const MiseGuiApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('这台电脑还没有安装 mise'), findsOneWidget);
    expect(find.text('安装完成后你会立刻看到'), findsNothing);
  });

  testWidgets('shows update dialog when a newer release is available', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appReleaseServiceProvider.overrideWithValue(
            const _FakeAppReleaseService(),
          ),
          appUpdateServiceProvider.overrideWithValue(
            const _HasUpdateAppUpdateService(),
          ),
          miseCliServiceProvider.overrideWithValue(const MockMiseCliService()),
          historyServiceProvider.overrideWithValue(const MockHistoryService()),
          projectScanServiceProvider.overrideWithValue(
            const MockProjectScanService(),
          ),
        ],
        child: const MiseGuiApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('1.0.1'), findsWidgets);
    expect(find.text('修复若干启动和安装问题'), findsOneWidget);
  });
}

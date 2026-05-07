import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mise_gui/app/bootstrap/app.dart';
import 'package:mise_gui/app/bootstrap/dependencies.dart';
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

void main() {
  testWidgets('loads dashboard shell', (WidgetTester tester) async {
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

    expect(find.text('总览'), findsWidgets);
    expect(find.text('工具'), findsWidgets);
    expect(find.text('项目'), findsWidgets);
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
    expect(find.text('brew install mise'), findsOneWidget);
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

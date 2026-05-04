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
}

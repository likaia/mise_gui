import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/repositories/config_repository.dart';
import 'package:mise_gui/repositories/dashboard_repository.dart';
import 'package:mise_gui/repositories/projects_repository.dart';
import 'package:mise_gui/repositories/tools_repository.dart';
import 'package:mise_gui/services/app_release_service.dart';
import 'package:mise_gui/services/app_update_service.dart';
import 'package:mise_gui/services/browser_launcher_service.dart';
import 'package:mise_gui/services/config_service.dart';
import 'package:mise_gui/services/config_watch_service.dart';
import 'package:mise_gui/services/history_service.dart';
import 'package:mise_gui/services/mise_action_service.dart';
import 'package:mise_gui/services/mise_cli_service.dart';
import 'package:mise_gui/services/mise_process_service.dart';
import 'package:mise_gui/services/mise_query_service.dart';
import 'package:mise_gui/services/project_scan_service.dart';
import 'package:mise_gui/services/scan_directory_service.dart';

enum AppThemePreference { system, light, dark }

ThemeMode resolveSystemThemeMode() {
  try {
    final brightness = PlatformDispatcher.instance.platformBrightness;
    return brightness == Brightness.light ? ThemeMode.light : ThemeMode.dark;
  } catch (_) {
    return ThemeMode.dark;
  }
}

final systemThemeModeProvider = StateProvider<ThemeMode>(
  (ref) => resolveSystemThemeMode(),
);

final themePreferenceProvider = StateProvider<AppThemePreference>(
  (ref) => AppThemePreference.system,
);

final themeModeProvider = Provider<ThemeMode>((ref) {
  final preference = ref.watch(themePreferenceProvider);
  final systemThemeMode = ref.watch(systemThemeModeProvider);

  return switch (preference) {
    AppThemePreference.system => systemThemeMode,
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
  };
});

final appReleaseServiceProvider = Provider<AppReleaseService>(
  (ref) => const PackageInfoAppReleaseService(),
);

final appVersionInfoProvider = FutureProvider<AppVersionInfo>(
  (ref) => ref.watch(appReleaseServiceProvider).load(),
);

final appUpdateServiceProvider = Provider<AppUpdateService>(
  (ref) => const GitHubAppUpdateService(),
);

final browserLauncherServiceProvider = Provider<BrowserLauncherService>(
  (ref) => const SystemBrowserLauncherService(),
);

final miseAvailableProvider = FutureProvider<bool>((ref) async {
  final processService = ref.watch(miseProcessServiceProvider);

  try {
    await processService.run(
      const MiseCommandRequest(
        arguments: ['--version'],
        timeout: Duration(seconds: 5),
      ),
    );
    return true;
  } catch (error) {
    if (isMiseCommandUnavailable(error)) {
      return false;
    }
    rethrow;
  }
});

final miseProcessServiceProvider = Provider<MiseProcessService>(
  (ref) => const LocalMiseProcessService(),
);

final miseQueryServiceProvider = Provider<MiseQueryService>(
  (ref) => CliMiseQueryService(ref.watch(miseProcessServiceProvider)),
);

final miseActionServiceProvider = Provider<MiseActionService>(
  (ref) => LocalMiseActionService(ref.watch(miseProcessServiceProvider)),
);

final miseCliServiceProvider = Provider<MiseCliService>(
  (ref) =>
      LiveMiseCliService(queryService: ref.watch(miseQueryServiceProvider)),
);

final configServiceProvider = Provider<ConfigService>(
  (ref) => const LiveConfigService(),
);

final configWatchServiceProvider = Provider<ConfigWatchService>(
  (ref) => const LocalConfigWatchService(),
);

final projectScanServiceProvider = Provider<ProjectScanService>(
  (ref) =>
      LiveProjectScanService(queryService: ref.watch(miseQueryServiceProvider)),
);

final scanDirectoryServiceProvider = Provider<ScanDirectoryService>(
  (ref) => const LocalScanDirectoryService(),
);

final historyServiceProvider = Provider<HistoryService>(
  (ref) => const LocalHistoryService(),
);

final toolsRepositoryProvider = Provider<ToolsRepository>(
  (ref) => ToolsRepository(ref.watch(miseCliServiceProvider)),
);

final projectsRepositoryProvider = Provider<ProjectsRepository>(
  (ref) => ProjectsRepository(
    ref.watch(projectScanServiceProvider),
    ref.watch(scanDirectoryServiceProvider),
  ),
);

final configRepositoryProvider = Provider<ConfigRepository>(
  (ref) => ConfigRepository(ref.watch(configServiceProvider)),
);

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(
    miseCliService: ref.watch(miseCliServiceProvider),
    projectsRepository: ref.watch(projectsRepositoryProvider),
    processService: ref.watch(miseProcessServiceProvider),
    historyService: ref.watch(historyServiceProvider),
  ),
);

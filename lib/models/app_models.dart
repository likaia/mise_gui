class SummaryMetric {
  const SummaryMetric({
    required this.label,
    required this.value,
    required this.caption,
    required this.level,
  });

  final String label;
  final String value;
  final String caption;
  final HealthLevel level;
}

class AppVersionInfo {
  const AppVersionInfo({
    required this.appName,
    required this.packageName,
    required this.version,
    required this.buildNumber,
  });

  final String appName;
  final String packageName;
  final String version;
  final String buildNumber;

  String get shortLabel => 'v$version';

  String get fullLabel =>
      buildNumber.isEmpty ? shortLabel : '$shortLabel+$buildNumber';
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.tagName,
    required this.releaseNotes,
    required this.releaseUrl,
  });

  final String currentVersion;
  final String latestVersion;
  final String tagName;
  final String releaseNotes;
  final String releaseUrl;
}

class EnvironmentSignal {
  const EnvironmentSignal({
    required this.title,
    required this.value,
    required this.detail,
    required this.level,
  });

  final String title;
  final String value;
  final String detail;
  final HealthLevel level;
}

class HistoryEntry {
  const HistoryEntry({
    required this.command,
    required this.timestamp,
    required this.detail,
    required this.level,
    this.status = HistoryStatus.success,
    this.exitCode,
    this.durationMs,
    this.stdout,
    this.stderr,
    this.stdoutSnippet,
    this.stderrSnippet,
  });

  final String command;
  final String timestamp;
  final String detail;
  final HealthLevel level;
  final HistoryStatus status;
  final int? exitCode;
  final int? durationMs;
  final String? stdout;
  final String? stderr;
  final String? stdoutSnippet;
  final String? stderrSnippet;

  bool get isFailure =>
      status == HistoryStatus.failure || (exitCode != null && exitCode != 0);

  String? get metaLabel {
    final parts = <String>[];
    parts.add(outcomeLabel);
    if (exitCode != null) {
      parts.add('exit $exitCode');
    }
    if (durationMs != null) {
      parts.add('${durationMs}ms');
    }
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' / ');
  }

  String get outcomeLabel {
    return switch (status) {
      HistoryStatus.canceled => '用户取消',
      HistoryStatus.failure when exitCode == -1 => '执行异常',
      HistoryStatus.failure => 'CLI 失败',
      HistoryStatus.success => '执行成功',
    };
  }

  String? get stdoutPreview => _resolvePreview(stdoutSnippet, stdout);

  String? get stderrPreview => _resolvePreview(stderrSnippet, stderr);

  static String? _resolvePreview(String? preview, String? full) {
    final previewValue = preview?.trim();
    if (previewValue != null && previewValue.isNotEmpty) {
      return previewValue;
    }

    final fullValue = full?.trim();
    if (fullValue == null || fullValue.isEmpty) {
      return null;
    }

    final lines = fullValue.split('\n');
    return lines.take(3).join('\n');
  }
}

enum HistoryStatus {
  success('成功'),
  failure('失败'),
  canceled('取消');

  const HistoryStatus(this.label);

  final String label;
}

class ToolVersionRecord {
  const ToolVersionRecord({
    required this.version,
    required this.channel,
    required this.note,
    required this.commandPreview,
    required this.level,
    this.isInstalled = false,
    this.isActive = false,
    this.isRecommended = false,
    this.isAlias = false,
  });

  final String version;
  final String channel;
  final String note;
  final String commandPreview;
  final HealthLevel level;
  final bool isInstalled;
  final bool isActive;
  final bool isRecommended;
  final bool isAlias;
}

class ToolProjectImpact {
  const ToolProjectImpact({
    required this.projectName,
    required this.path,
    required this.requestedVersion,
    required this.resolvedVersion,
    required this.reason,
    required this.level,
  });

  final String projectName;
  final String path;
  final String requestedVersion;
  final String resolvedVersion;
  final String reason;
  final HealthLevel level;
}

class ToolCommandAction {
  const ToolCommandAction({
    required this.label,
    required this.summary,
    required this.command,
    required this.level,
  });

  final String label;
  final String summary;
  final String command;
  final HealthLevel level;
}

class InlineNotice {
  const InlineNotice({
    required this.title,
    required this.message,
    required this.level,
    this.commandPreview,
  });

  final String title;
  final String message;
  final HealthLevel level;
  final String? commandPreview;
}

enum ToolRemoteState { pending, ready, unavailable }

class ToolRecord {
  const ToolRecord({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.activeVersion,
    required this.requestedVersion,
    required this.source,
    required this.strategy,
    required this.latestStableVersion,
    required this.latestPreviewVersion,
    required this.installedVersions,
    required this.remoteVersions,
    required this.projectImpacts,
    required this.quickActions,
    required this.commandPreview,
    required this.level,
    this.notices = const [],
    this.updateVersion,
    this.remoteState = ToolRemoteState.ready,
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final String activeVersion;
  final String requestedVersion;
  final String source;
  final String strategy;
  final String latestStableVersion;
  final String latestPreviewVersion;
  final List<ToolVersionRecord> installedVersions;
  final List<ToolVersionRecord> remoteVersions;
  final List<ToolProjectImpact> projectImpacts;
  final List<ToolCommandAction> quickActions;
  final String commandPreview;
  final HealthLevel level;
  final List<InlineNotice> notices;
  final String? updateVersion;
  final ToolRemoteState remoteState;

  bool get hasUpdate => updateVersion != null;

  int get installedCount => installedVersions.length;

  int get projectImpactCount => projectImpacts.length;

  ToolRecord copyWith({
    String? latestStableVersion,
    String? latestPreviewVersion,
    List<ToolVersionRecord>? remoteVersions,
    List<ToolCommandAction>? quickActions,
    String? commandPreview,
    HealthLevel? level,
    List<InlineNotice>? notices,
    String? updateVersion,
    ToolRemoteState? remoteState,
  }) {
    return ToolRecord(
      id: id,
      name: name,
      category: category,
      description: description,
      activeVersion: activeVersion,
      requestedVersion: requestedVersion,
      source: source,
      strategy: strategy,
      latestStableVersion: latestStableVersion ?? this.latestStableVersion,
      latestPreviewVersion: latestPreviewVersion ?? this.latestPreviewVersion,
      installedVersions: installedVersions,
      remoteVersions: remoteVersions ?? this.remoteVersions,
      projectImpacts: projectImpacts,
      quickActions: quickActions ?? this.quickActions,
      commandPreview: commandPreview ?? this.commandPreview,
      level: level ?? this.level,
      notices: notices ?? this.notices,
      updateVersion: updateVersion ?? this.updateVersion,
      remoteState: remoteState ?? this.remoteState,
    );
  }
}

class ProjectToolBinding {
  const ProjectToolBinding({
    required this.name,
    required this.projectVersion,
    required this.globalVersion,
    required this.source,
    this.declaredInProject = false,
    this.declaredInGlobal = false,
  });

  final String name;
  final String projectVersion;
  final String globalVersion;
  final String source;
  final bool declaredInProject;
  final bool declaredInGlobal;

  bool get overridesGlobal =>
      declaredInProject && declaredInGlobal && projectVersion != globalVersion;
}

class ProjectRecord {
  const ProjectRecord({
    required this.name,
    required this.path,
    required this.scanRootPath,
    required this.configPath,
    required this.environment,
    required this.lastScan,
    required this.commandPreview,
    required this.bindings,
    required this.level,
    required this.notes,
  });

  final String name;
  final String path;
  final String scanRootPath;
  final String configPath;
  final String environment;
  final String lastScan;
  final String commandPreview;
  final List<ProjectToolBinding> bindings;
  final HealthLevel level;
  final String notes;

  int get declaredToolCount =>
      bindings.where((binding) => binding.declaredInProject).length;

  int get overrideCount =>
      bindings.where((binding) => binding.overridesGlobal).length;

  int get projectOnlyToolCount => bindings
      .where(
        (binding) => binding.declaredInProject && !binding.declaredInGlobal,
      )
      .length;

  bool get hasOverrideRisk =>
      bindings.any((binding) => binding.overridesGlobal);
}

class ScanDirectoryRecord {
  const ScanDirectoryRecord({required this.path, this.enabled = true});

  final String path;
  final bool enabled;

  String get name {
    var normalized = path.replaceAll('\\', '/');
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  ScanDirectoryRecord copyWith({String? path, bool? enabled}) {
    return ScanDirectoryRecord(
      path: path ?? this.path,
      enabled: enabled ?? this.enabled,
    );
  }
}

class ProjectCoverageSnapshot {
  const ProjectCoverageSnapshot({
    required this.scanDirectories,
    required this.projects,
  });

  final List<ScanDirectoryRecord> scanDirectories;
  final List<ProjectRecord> projects;

  int get enabledDirectoryCount =>
      scanDirectories.where((directory) => directory.enabled).length;

  int get overrideProjectCount =>
      projects.where((project) => project.hasOverrideRisk).length;

  int get overrideBindingCount => projects
      .expand((project) => project.bindings)
      .where((binding) => binding.overridesGlobal)
      .length;
}

class ConfigItem {
  const ConfigItem({
    required this.label,
    required this.value,
    required this.detail,
    required this.level,
    required this.isEditable,
  });

  final String label;
  final String value;
  final String detail;
  final HealthLevel level;
  final bool isEditable;
}

class ConfigSectionData {
  const ConfigSectionData({
    required this.title,
    required this.description,
    required this.rawSnippet,
    required this.items,
  });

  final String title;
  final String description;
  final String rawSnippet;
  final List<ConfigItem> items;
}

class ConfigDocumentData {
  const ConfigDocumentData({
    required this.id,
    required this.title,
    required this.path,
    required this.content,
    required this.description,
    required this.commandPreview,
    required this.exists,
  });

  final String id;
  final String title;
  final String path;
  final String content;
  final String description;
  final String commandPreview;
  final bool exists;

  String get fileName {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }
}

class ConfigSavePreview {
  const ConfigSavePreview({
    required this.document,
    required this.nextContent,
    required this.diffPreview,
    required this.commandPreview,
    required this.hasChanges,
    required this.createsFile,
  });

  final ConfigDocumentData document;
  final String nextContent;
  final String diffPreview;
  final String commandPreview;
  final bool hasChanges;
  final bool createsFile;
}

class ConfigWorkspaceData {
  const ConfigWorkspaceData({required this.sections, required this.documents});

  final List<ConfigSectionData> sections;
  final List<ConfigDocumentData> documents;
}

class DiagnoseCheck {
  const DiagnoseCheck({
    required this.title,
    required this.area,
    required this.detail,
    required this.recommendation,
    required this.commandPreview,
    required this.level,
  });

  final String title;
  final String area;
  final String detail;
  final String recommendation;
  final String commandPreview;
  final HealthLevel level;
}

class DiagnoseReport {
  const DiagnoseReport({
    required this.score,
    required this.summary,
    required this.blockers,
    required this.checks,
  });

  final int score;
  final String summary;
  final List<String> blockers;
  final List<DiagnoseCheck> checks;
}

class DashboardToolSummary {
  const DashboardToolSummary({
    required this.activeToolCount,
    required this.installedToolCount,
    required this.commandPreview,
  });

  final int activeToolCount;
  final int installedToolCount;
  final String commandPreview;
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.title,
    required this.subtitle,
    required this.metrics,
    required this.signals,
    required this.toolSummary,
    required this.recentHistory,
    required this.riskHighlights,
    this.notices = const [],
  });

  final String title;
  final String subtitle;
  final List<SummaryMetric> metrics;
  final List<EnvironmentSignal> signals;
  final DashboardToolSummary toolSummary;
  final List<HistoryEntry> recentHistory;
  final List<String> riskHighlights;
  final List<InlineNotice> notices;
}

enum HealthLevel { healthy, info, warning, critical }

extension HealthLevelPresentation on HealthLevel {
  String get label => switch (this) {
    HealthLevel.healthy => '正常',
    HealthLevel.info => '提示',
    HealthLevel.warning => '注意',
    HealthLevel.critical => '风险',
  };
}

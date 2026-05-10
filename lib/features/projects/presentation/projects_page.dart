import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mise_gui/app/bootstrap/dependencies.dart';
import 'package:mise_gui/app/theme/app_theme.dart';
import 'package:mise_gui/features/dashboard/application/dashboard_provider.dart';
import 'package:mise_gui/features/projects/application/projects_provider.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/services/mise_process_service.dart';
import 'package:mise_gui/shared/ui/app_page_scaffold.dart';
import 'package:mise_gui/shared/ui/app_panel.dart';
import 'package:mise_gui/shared/ui/async_state_view.dart';
import 'package:mise_gui/shared/ui/status_badge.dart';

class ProjectsPage extends ConsumerStatefulWidget {
  const ProjectsPage({super.key});

  @override
  ConsumerState<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends ConsumerState<ProjectsPage> {
  static const _refreshDebounce = Duration(seconds: 1);

  DateTime? _lastRefreshAt;
  var _refreshing = false;

  Future<void> _handleRefresh() async {
    if (_refreshing) {
      _showFeedback('正在扫描目录，请稍候。');
      return;
    }

    final now = DateTime.now();
    if (_lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < _refreshDebounce) {
      _showFeedback('点击过于频繁，请 1 秒后再试。');
      return;
    }

    _lastRefreshAt = now;
    setState(() => _refreshing = true);

    try {
      await _reloadData();
      await ref
          .read(historyServiceProvider)
          .appendEntry(
            HistoryEntry(
              command: 'mise ls --json',
              timestamp: _formatNow(),
              detail: '用户手动刷新了项目覆盖扫描结果。',
              level: HealthLevel.info,
              status: HistoryStatus.success,
              exitCode: 0,
            ),
          );
      _showFeedback('扫描结果已刷新。');
    } catch (error) {
      _showFeedback(_formatRefreshError(error));
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _handleAddDirectory() async {
    final existingDirectories = await ref
        .read(projectsRepositoryProvider)
        .loadScanDirectories();
    if (!mounted) {
      return;
    }
    final path = await showDialog<String>(
      context: context,
      builder: (context) => const _AddScanDirectoryDialog(),
    );
    if (path == null || path.trim().isEmpty || !mounted) {
      return;
    }

    final normalizedPath = _normalizePath(path);
    final exists = await Directory(normalizedPath).exists();
    if (!exists) {
      _showFeedback('目录不存在，先确认路径再添加。');
      return;
    }

    final sameDirectory = existingDirectories
        .where((directory) => directory.path == normalizedPath)
        .toList(growable: false);
    if (sameDirectory.isNotEmpty && sameDirectory.first.enabled) {
      _showFeedback('这个扫描目录已经存在。');
      return;
    }

    final coveredByAncestor = existingDirectories
        .where(
          (directory) =>
              directory.enabled &&
              directory.path != normalizedPath &&
              _containsPath(directory.path, normalizedPath),
        )
        .toList(growable: false);
    if (coveredByAncestor.isNotEmpty) {
      _showFeedback('这个目录已经被 ${coveredByAncestor.first.path} 包含，不再重复添加。');
      return;
    }

    final coveredChildren = existingDirectories
        .where(
          (directory) =>
              directory.enabled &&
              directory.path != normalizedPath &&
              _containsPath(normalizedPath, directory.path),
        )
        .toList(growable: false);

    await ref.read(projectsRepositoryProvider).addScanDirectory(normalizedPath);
    await _reloadData();
    if (sameDirectory.isNotEmpty && !sameDirectory.first.enabled) {
      _showFeedback('已重新启用扫描目录。');
      return;
    }
    if (coveredChildren.isNotEmpty) {
      _showFeedback('已添加扫描目录，并自动去重 ${coveredChildren.length} 个被包含的子目录。');
      return;
    }
    _showFeedback('已添加扫描目录。');
  }

  Future<void> _handleRemoveDirectory(ScanDirectoryRecord directory) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = AppTheme.colorsOf(dialogContext);
        return AlertDialog(
          title: const Text('删除扫描目录'),
          content: Text('不再扫描 ${directory.path}？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    await ref
        .read(projectsRepositoryProvider)
        .removeScanDirectory(directory.path);
    await _reloadData();
    _showFeedback('扫描目录已删除。');
  }

  Future<void> _handleToggleDirectory(
    ScanDirectoryRecord directory,
    bool enabled,
  ) async {
    await ref
        .read(projectsRepositoryProvider)
        .setScanDirectoryEnabled(directory.path, enabled);
    await _reloadData();
  }

  Future<void> _reloadData() async {
    await Future.wait([
      ref.refresh(projectCoverageProvider.future),
      ref.refresh(projectsProvider.future),
      ref.refresh(dashboardProvider.future),
    ]);
  }

  String _formatRefreshError(Object error) {
    if (isMiseCommandUnavailable(error)) {
      return '扫描失败：未检测到 mise CLI。';
    }
    return '扫描失败，请稍后重试。';
  }

  void _showFeedback(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  String _normalizePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final home = Platform.environment['HOME'];
    final expanded = trimmed.startsWith('~/') && home != null && home.isNotEmpty
        ? '$home/${trimmed.substring(2)}'
        : trimmed;
    var normalized = Directory(expanded).absolute.path;
    final rootPrefix = Platform.isWindows ? RegExp(r'^[A-Za-z]:/$') : null;
    while (normalized.length > 1 &&
        normalized.endsWith(Platform.pathSeparator) &&
        !(rootPrefix?.hasMatch(normalized) ?? false)) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  bool _containsPath(String parent, String child) {
    final normalizedParent = _normalizeComparablePath(parent);
    final normalizedChild = _normalizeComparablePath(child);
    return normalizedChild == normalizedParent ||
        normalizedChild.startsWith('$normalizedParent/');
  }

  String _normalizeComparablePath(String path) {
    var normalized = path.replaceAll('\\', '/');
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  @override
  Widget build(BuildContext context) {
    final coverageValue = ref.watch(projectCoverageProvider);

    return AsyncStateView(
      value: coverageValue,
      builder: (snapshot) {
        return AppPageScaffold(
          title: '项目覆盖',
          description: '管理扫描目录，只显示覆盖了全局版本的项目和版本差异。',
          actions: [
            FilledButton.icon(
              onPressed: _handleRefresh,
              icon: _refreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(_refreshing ? '扫描中...' : '重新扫描'),
            ),
          ],
          child: _ProjectCoverageLayout(
            snapshot: snapshot,
            watchPaths: _watchPaths(snapshot),
            onAddDirectory: _handleAddDirectory,
            onRemoveDirectory: _handleRemoveDirectory,
            onToggleDirectory: _handleToggleDirectory,
          ),
        );
      },
    );
  }

  List<String> _watchPaths(ProjectCoverageSnapshot snapshot) {
    final paths = <String>{};
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      paths.add('$home/.config/mise/config.toml');
    }
    for (final project in snapshot.projects) {
      paths.add(project.configPath);
    }
    return paths.toList()..sort();
  }

  String _formatNow() {
    final now = DateTime.now();
    final hours = now.hour.toString().padLeft(2, '0');
    final minutes = now.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }
}

class _ProjectCoverageLayout extends StatelessWidget {
  const _ProjectCoverageLayout({
    required this.snapshot,
    required this.watchPaths,
    required this.onAddDirectory,
    required this.onRemoveDirectory,
    required this.onToggleDirectory,
  });

  final ProjectCoverageSnapshot snapshot;
  final List<String> watchPaths;
  final VoidCallback onAddDirectory;
  final ValueChanged<ScanDirectoryRecord> onRemoveDirectory;
  final Future<void> Function(ScanDirectoryRecord directory, bool enabled)
  onToggleDirectory;

  @override
  Widget build(BuildContext context) {
    final overrides = _buildOverrideRows(snapshot.projects);

    return Column(
      children: [
        _ProjectsAutoRefresh(paths: watchPaths),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 1180;
            if (stacked) {
              return Column(
                children: [
                  _ScanDirectoriesPanel(
                    directories: snapshot.scanDirectories,
                    projects: snapshot.projects,
                    onAddDirectory: onAddDirectory,
                    onRemoveDirectory: onRemoveDirectory,
                    onToggleDirectory: onToggleDirectory,
                  ),
                  const SizedBox(height: 18),
                  _OverridesPanel(
                    directories: snapshot.scanDirectories,
                    projectCount: snapshot.projects.length,
                    overrideRows: overrides,
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 350,
                  child: _ScanDirectoriesPanel(
                    directories: snapshot.scanDirectories,
                    projects: snapshot.projects,
                    onAddDirectory: onAddDirectory,
                    onRemoveDirectory: onRemoveDirectory,
                    onToggleDirectory: onToggleDirectory,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: _OverridesPanel(
                    directories: snapshot.scanDirectories,
                    projectCount: snapshot.projects.length,
                    overrideRows: overrides,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ScanDirectoriesPanel extends StatelessWidget {
  const _ScanDirectoriesPanel({
    required this.directories,
    required this.projects,
    required this.onAddDirectory,
    required this.onRemoveDirectory,
    required this.onToggleDirectory,
  });

  final List<ScanDirectoryRecord> directories;
  final List<ProjectRecord> projects;
  final VoidCallback onAddDirectory;
  final ValueChanged<ScanDirectoryRecord> onRemoveDirectory;
  final Future<void> Function(ScanDirectoryRecord directory, bool enabled)
  onToggleDirectory;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.all(18),
      radius: 20,
      backgroundAlpha: 0.58,
      borderAlpha: 0.42,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ScanDirectoriesHeader(
            directoryCount: directories.length,
            onAddDirectory: onAddDirectory,
          ),
          const SizedBox(height: 18),
          if (directories.isEmpty)
            _ScanDirectoriesEmptyState(onAddDirectory: onAddDirectory)
          else
            Column(
              children: [
                for (var index = 0; index < directories.length; index++) ...[
                  Builder(
                    builder: (context) {
                      final directory = directories[index];
                      final projectsForDirectory = projects
                          .where(
                            (project) =>
                                _directoryContainsProject(directory, project),
                          )
                          .toList(growable: false);
                      projectsForDirectory.sort(
                        (a, b) => a.path.toLowerCase().compareTo(
                          b.path.toLowerCase(),
                        ),
                      );
                      final projectCount = projectsForDirectory.length;
                      final overrideProjectCount = projectsForDirectory
                          .where((project) => project.hasOverrideRisk)
                          .length;

                      return _ScanDirectoryCard(
                        key: ValueKey(directory.path),
                        directory: directory,
                        projects: projectsForDirectory,
                        projectCount: projectCount,
                        overrideProjectCount: overrideProjectCount,
                        onRemove: () => onRemoveDirectory(directory),
                        onToggle: (value) =>
                            onToggleDirectory(directory, value),
                      );
                    },
                  ),
                  if (index != directories.length - 1)
                    const SizedBox(height: 10),
                ],
              ],
            ),
        ],
      ),
    );
  }

  bool _directoryContainsProject(
    ScanDirectoryRecord directory,
    ProjectRecord project,
  ) {
    final directoryPath = _normalizeDirectoryPath(directory.path);
    final projectPath = _normalizeDirectoryPath(project.path);
    return projectPath == directoryPath ||
        projectPath.startsWith('$directoryPath/');
  }

  String _normalizeDirectoryPath(String path) {
    var normalized = path.replaceAll('\\', '/');
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}

class _ScanDirectoriesHeader extends StatelessWidget {
  const _ScanDirectoriesHeader({
    required this.directoryCount,
    required this.onAddDirectory,
  });

  final int directoryCount;
  final VoidCallback onAddDirectory;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('扫描范围', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '添加工作区目录后，应用会在其中查找 mise 项目和项目级版本覆盖。',
              style: TextStyle(color: colors.textMuted, height: 1.45),
            ),
          ],
        );
        final actions = Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (directoryCount > 0)
              _DirectoryCountPill(directoryCount: directoryCount),
            FilledButton.icon(
              onPressed: onAddDirectory,
              icon: const Icon(Icons.create_new_folder_rounded, size: 18),
              label: const Text('添加目录'),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [titleBlock, const SizedBox(height: 14), actions],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 18),
            actions,
          ],
        );
      },
    );
  }
}

class _DirectoryCountPill extends StatelessWidget {
  const _DirectoryCountPill({required this.directoryCount});

  final int directoryCount;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_copy_rounded,
            size: 16,
            color: colors.textMuted.withValues(alpha: 0.92),
          ),
          const SizedBox(width: 8),
          Text(
            '$directoryCount 个目录',
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanDirectoriesEmptyState extends StatelessWidget {
  const _ScanDirectoriesEmptyState({required this.onAddDirectory});

  final VoidCallback onAddDirectory;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final icon = Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: colors.info.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.info.withValues(alpha: 0.24)),
          ),
          child: Icon(Icons.folder_open_rounded, color: colors.info),
        );
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '还没有扫描目录',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '添加一个工作区目录后，就可以开始扫描项目覆盖。',
              style: TextStyle(color: colors.textMuted, height: 1.45),
            ),
          ],
        );
        final button = OutlinedButton.icon(
          onPressed: onAddDirectory,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('添加第一个目录'),
        );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.panelRaised.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border.withValues(alpha: 0.34)),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(height: 12),
                    copy,
                    const SizedBox(height: 14),
                    button,
                  ],
                )
              : Row(
                  children: [
                    icon,
                    const SizedBox(width: 14),
                    Expanded(child: copy),
                    const SizedBox(width: 14),
                    button,
                  ],
                ),
        );
      },
    );
  }
}

class _ScanDirectoryCard extends StatelessWidget {
  const _ScanDirectoryCard({
    super.key,
    required this.directory,
    required this.projects,
    required this.projectCount,
    required this.overrideProjectCount,
    required this.onRemove,
    required this.onToggle,
  });

  final ScanDirectoryRecord directory;
  final List<ProjectRecord> projects;
  final int projectCount;
  final int overrideProjectCount;
  final VoidCallback onRemove;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final summary = _DirectoryScanSummary(
      enabled: directory.enabled,
      projectCount: projectCount,
      overrideProjectCount: overrideProjectCount,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border.withValues(alpha: 0.34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      directory.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      directory.path,
                      style: TextStyle(
                        color: colors.textMuted,
                        fontFamily: 'FiraCode',
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _DirectoryStatusLabel(enabled: directory.enabled),
            ],
          ),
          const SizedBox(height: 12),
          _DirectorySummaryBanner(summary: summary),
          if (projectCount > 0) ...[
            const SizedBox(height: 10),
            _DirectoryProjectDetails(
              directoryPath: directory.path,
              projects: projects,
              projectCount: projectCount,
              overrideProjectCount: overrideProjectCount,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => onToggle(!directory.enabled),
                icon: Icon(
                  directory.enabled
                      ? Icons.remove_circle_outline_rounded
                      : Icons.add_circle_outline_rounded,
                  size: 18,
                ),
                label: Text(directory.enabled ? '暂停扫描' : '启用扫描'),
              ),
              const Spacer(),
              _DangerIconButton(tooltip: '删除扫描目录', onPressed: onRemove),
            ],
          ),
        ],
      ),
    );
  }
}

class _DangerIconButton extends StatelessWidget {
  const _DangerIconButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: const Icon(Icons.delete_outline_rounded),
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(colors.danger),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return colors.danger.withValues(alpha: 0.24);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return colors.danger.withValues(alpha: 0.18);
          }
          return colors.danger.withValues(alpha: 0.1);
        }),
        side: WidgetStateProperty.resolveWith((states) {
          final alpha =
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
              ? 0.62
              : 0.38;
          return BorderSide(color: colors.danger.withValues(alpha: alpha));
        }),
        minimumSize: const WidgetStatePropertyAll(Size.square(38)),
        fixedSize: const WidgetStatePropertyAll(Size.square(38)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      ),
    );
  }
}

class _DirectoryProjectDetails extends StatelessWidget {
  const _DirectoryProjectDetails({
    required this.directoryPath,
    required this.projects,
    required this.projectCount,
    required this.overrideProjectCount,
  });

  final String directoryPath;
  final List<ProjectRecord> projects;
  final int projectCount;
  final int overrideProjectCount;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey<String>('scan-directory-$directoryPath'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.border.withValues(alpha: 0.32)),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.border.withValues(alpha: 0.36)),
        ),
        backgroundColor: colors.panelRaised.withValues(alpha: 0.2),
        collapsedBackgroundColor: colors.panelRaised.withValues(alpha: 0.14),
        visualDensity: VisualDensity.compact,
        title: const Text(
          '查看项目明细',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          overrideProjectCount > 0
              ? '$projectCount 个 mise 项目，$overrideProjectCount 个存在覆盖'
              : '$projectCount 个 mise 项目，暂无版本覆盖',
          style: TextStyle(
            color: overrideProjectCount > 0 ? colors.warning : colors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          Divider(height: 1, color: colors.border.withValues(alpha: 0.36)),
          ...List.generate(projects.length, (index) {
            final project = projects[index];
            return _ScannedProjectRow(project: project);
          }),
        ],
      ),
    );
  }
}

class _DirectorySummaryBanner extends StatelessWidget {
  const _DirectorySummaryBanner({required this.summary});

  final _DirectoryScanSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final color = summary.level == HealthLevel.warning
        ? colors.warning
        : summary.level == HealthLevel.healthy
        ? colors.accent
        : colors.textMuted;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(summary.icon, color: color, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              summary.message,
              style: TextStyle(
                color: summary.level == HealthLevel.info
                    ? colors.textMuted
                    : colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectoryScanSummary {
  factory _DirectoryScanSummary({
    required bool enabled,
    required int projectCount,
    required int overrideProjectCount,
  }) {
    if (!enabled) {
      return const _DirectoryScanSummary._paused();
    }

    if (projectCount == 0) {
      return const _DirectoryScanSummary._empty();
    }

    if (overrideProjectCount > 0) {
      return _DirectoryScanSummary._warning(
        '发现 $projectCount 个 mise 项目，其中 $overrideProjectCount 个存在版本覆盖。',
      );
    }

    return _DirectoryScanSummary._healthy('发现 $projectCount 个 mise 项目，暂无版本覆盖。');
  }

  const _DirectoryScanSummary._paused()
    : message = '已暂停扫描，保留上次扫描结果。',
      icon = Icons.pause_circle_outline_rounded,
      level = HealthLevel.info;

  const _DirectoryScanSummary._empty()
    : message = '未发现 mise 项目。',
      icon = Icons.search_off_rounded,
      level = HealthLevel.info;

  const _DirectoryScanSummary._healthy(this.message)
    : icon = Icons.check_circle_outline_rounded,
      level = HealthLevel.healthy;

  const _DirectoryScanSummary._warning(this.message)
    : icon = Icons.warning_amber_rounded,
      level = HealthLevel.warning;

  final String message;
  final IconData icon;
  final HealthLevel level;
}

class _DirectoryStatusLabel extends StatelessWidget {
  const _DirectoryStatusLabel({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final color = enabled ? colors.accent : colors.textMuted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          enabled ? '扫描中' : '已暂停',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ScannedProjectRow extends StatelessWidget {
  const _ScannedProjectRow({required this.project});

  final ProjectRecord project;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  project.path,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '复制路径',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: project.path));
              if (!context.mounted) {
                return;
              }
              final messenger = ScaffoldMessenger.of(context);
              messenger.removeCurrentSnackBar();
              messenger.showSnackBar(const SnackBar(content: Text('项目路径已复制。')));
            },
            icon: const Icon(Icons.content_copy_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

class _OverridesPanel extends StatelessWidget {
  const _OverridesPanel({
    required this.directories,
    required this.projectCount,
    required this.overrideRows,
  });

  final List<ScanDirectoryRecord> directories;
  final int projectCount;
  final List<_OverrideRowData> overrideRows;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('覆盖项目', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      '只列出项目版本和全局版本不一致的条目。',
                      style: TextStyle(color: colors.textMuted, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (overrideRows.isNotEmpty)
                StatusBadge(
                  label: '${overrideRows.length} 项',
                  level: HealthLevel.warning,
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (directories.isEmpty)
            const _OverridesEmptyState(message: '暂无项目覆盖全局版本')
          else if (overrideRows.isEmpty)
            _OverridesEmptyState(
              message: projectCount > 0 ? '暂无项目覆盖全局版本' : '暂无项目覆盖全局版本',
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                children: [
                  const _OverridesTableHeader(),
                  const SizedBox(height: 12),
                  for (var index = 0; index < overrideRows.length; index++) ...[
                    _OverridesTableRow(row: overrideRows[index]),
                    if (index != overrideRows.length - 1)
                      const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _OverridesEmptyState extends StatelessWidget {
  const _OverridesEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.backgroundSoft.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Text(message, style: TextStyle(color: colors.textMuted)),
    );
  }
}

class _OverridesTableHeader extends StatelessWidget {
  const _OverridesTableHeader();

  static const double _tableContentWidth = 980;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.backgroundSoft.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: const SizedBox(
        width: _tableContentWidth,
        child: Row(
          children: [
            _TableHeaderCell(label: '项目', width: 260),
            _TableHeaderCell(label: '工具', width: 120),
            _TableHeaderCell(label: '项目版本', width: 170),
            _TableHeaderCell(label: '全局版本', width: 170),
            _TableHeaderCell(label: '扫描目录', width: 260),
          ],
        ),
      ),
    );
  }
}

class _OverridesTableRow extends StatelessWidget {
  const _OverridesTableRow({required this.row});

  static const double _tableContentWidth = 980;

  final _OverrideRowData row;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.warning.withValues(alpha: 0.25)),
      ),
      child: SizedBox(
        width: _tableContentWidth,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProjectCell(
              width: 260,
              title: row.projectName,
              subtitle: row.projectPath,
            ),
            _ValueCell(width: 120, value: row.tool),
            _ValueCell(width: 170, value: row.projectVersion, emphasized: true),
            _ValueCell(width: 170, value: row.globalVersion),
            _ProjectCell(
              width: 260,
              title: row.scanRootName,
              subtitle: row.scanRootPath,
            ),
          ],
        ),
      ),
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  const _TableHeaderCell({required this.label, required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return SizedBox(
      width: width,
      child: Text(
        label,
        style: TextStyle(
          color: colors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ProjectCell extends StatelessWidget {
  const _ProjectCell({
    required this.width,
    required this.title,
    required this.subtitle,
  });

  final double width;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ValueCell extends StatelessWidget {
  const _ValueCell({
    required this.width,
    required this.value,
    this.emphasized = false,
  });

  final double width;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return SizedBox(
      width: width,
      child: Text(
        value,
        style: TextStyle(
          color: emphasized ? colors.warning : colors.textPrimary,
          fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _ProjectsAutoRefresh extends ConsumerStatefulWidget {
  const _ProjectsAutoRefresh({required this.paths});

  final List<String> paths;

  @override
  ConsumerState<_ProjectsAutoRefresh> createState() =>
      _ProjectsAutoRefreshState();
}

class _ProjectsAutoRefreshState extends ConsumerState<_ProjectsAutoRefresh> {
  StreamSubscription<void>? _subscription;

  @override
  void initState() {
    super.initState();
    _bindWatcher();
  }

  @override
  void didUpdateWidget(covariant _ProjectsAutoRefresh oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.paths, widget.paths)) {
      _bindWatcher();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _bindWatcher() {
    _subscription?.cancel();
    _subscription = ref
        .read(configWatchServiceProvider)
        .watchPaths(widget.paths)
        .listen((_) {
          ref.invalidate(projectCoverageProvider);
          ref.invalidate(projectsProvider);
          ref.invalidate(dashboardProvider);
        });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _AddScanDirectoryDialog extends StatefulWidget {
  const _AddScanDirectoryDialog();

  @override
  State<_AddScanDirectoryDialog> createState() =>
      _AddScanDirectoryDialogState();
}

class _AddScanDirectoryDialogState extends State<_AddScanDirectoryDialog> {
  late final TextEditingController _controller;
  var _selecting = false;

  Future<void> _handleBrowse() async {
    setState(() => _selecting = true);
    try {
      final path = await _pickDirectory();
      if (!mounted || path == null || path.trim().isEmpty) {
        return;
      }
      _controller.text = path;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    } on PlatformException catch (error) {
      debugPrint('Directory picker channel failed: $error');
      _showFeedback('目录选择器暂时不可用，请手动输入路径。');
    } catch (error) {
      debugPrint('Directory picker failed: $error');
      _showFeedback('打开目录选择器失败，请手动输入路径。');
    } finally {
      if (mounted) {
        setState(() => _selecting = false);
      }
    }
  }

  Future<String?> _pickDirectory() async {
    final initialDirectory = _controller.text.trim().isEmpty
        ? Directory.current.path
        : _controller.text.trim();

    try {
      return await getDirectoryPath(
        confirmButtonText: '选择目录',
        initialDirectory: initialDirectory,
      );
    } on PlatformException {
      if (!Platform.isMacOS) {
        rethrow;
      }
    }

    return _pickDirectoryWithMacOsScript(initialDirectory);
  }

  Future<String?> _pickDirectoryWithMacOsScript(String initialDirectory) async {
    final sanitizedDirectory = initialDirectory
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"');
    final script =
        '''
set defaultFolder to POSIX file "$sanitizedDirectory"
set chosenFolder to choose folder with prompt "选择要扫描的目录" default location defaultFolder
POSIX path of chosenFolder
''';

    final result = await Process.run('osascript', ['-e', script]);
    if (result.exitCode == 0) {
      final selectedPath = (result.stdout as String).trim();
      return selectedPath.isEmpty ? null : selectedPath;
    }

    final stderr = (result.stderr as String).trim();
    if (stderr.contains('User canceled') || stderr.contains('(-128)')) {
      return null;
    }

    throw PlatformException(
      code: 'macos-directory-picker-failed',
      message: stderr.isEmpty ? 'macOS 目录选择器执行失败。' : stderr,
    );
  }

  void _showFeedback(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加扫描目录'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('输入要扫描的目录路径。应用会在目录内递归查找 `mise.toml`。'),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '目录路径',
                hintText: '/Users/you/Projects',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _selecting ? null : _handleBrowse,
                  icon: _selecting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_rounded),
                  label: Text(_selecting ? '打开中...' : '浏览本地目录'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('添加'),
        ),
      ],
    );
  }
}

List<_OverrideRowData> _buildOverrideRows(List<ProjectRecord> projects) {
  final rows = <_OverrideRowData>[];
  for (final project in projects) {
    for (final binding in project.bindings) {
      if (!binding.overridesGlobal) {
        continue;
      }
      rows.add(
        _OverrideRowData(
          projectName: project.name,
          projectPath: project.path,
          tool: binding.name,
          projectVersion: binding.projectVersion,
          globalVersion: binding.globalVersion,
          scanRootPath: project.scanRootPath,
        ),
      );
    }
  }

  rows.sort((a, b) {
    final projectCompare = a.projectName.toLowerCase().compareTo(
      b.projectName.toLowerCase(),
    );
    if (projectCompare != 0) {
      return projectCompare;
    }
    return a.tool.toLowerCase().compareTo(b.tool.toLowerCase());
  });
  return rows;
}

class _OverrideRowData {
  const _OverrideRowData({
    required this.projectName,
    required this.projectPath,
    required this.tool,
    required this.projectVersion,
    required this.globalVersion,
    required this.scanRootPath,
  });

  final String projectName;
  final String projectPath;
  final String tool;
  final String projectVersion;
  final String globalVersion;
  final String scanRootPath;

  String get scanRootName {
    final normalized = scanRootPath.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? scanRootPath : parts.last;
  }
}

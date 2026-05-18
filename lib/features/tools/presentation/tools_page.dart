import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mise_gui/app/bootstrap/dependencies.dart';
import 'package:mise_gui/app/theme/app_theme.dart';
import 'package:mise_gui/features/dashboard/application/dashboard_provider.dart';
import 'package:mise_gui/features/tools/application/tools_provider.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/services/mise_action_service.dart';
import 'package:mise_gui/services/mise_cli_service.dart';
import 'package:mise_gui/services/mise_process_service.dart';
import 'package:mise_gui/services/mise_query_service.dart';
import 'package:mise_gui/shared/ui/action_preview_dialog.dart';
import 'package:mise_gui/shared/ui/app_page_scaffold.dart';
import 'package:mise_gui/shared/ui/app_panel.dart';
import 'package:mise_gui/shared/ui/async_state_view.dart';
import 'package:mise_gui/shared/ui/history_entry_dialog.dart';
import 'package:mise_gui/shared/ui/inline_notice_bar.dart';

List<String> selectVersionSuggestions(List<MiseRemoteToolVersionRef> versions) {
  final stableVersions = versions
      .where(
        (version) =>
            !version.rolling &&
            !(version.tool == 'java' &&
                _isJavaRuntimeOnlySuggestion(version.version)),
      )
      .toList();
  final source = stableVersions.isNotEmpty ? stableVersions : versions;
  if (source.isEmpty) {
    return const [];
  }

  final latestByMajor = <String, String>{};
  for (final version in source) {
    final value = version.version.trim();
    if (value.isEmpty) {
      continue;
    }

    final majorKey = _majorVersionKey(value);
    final current = latestByMajor[majorKey];
    if (current == null || compareToolVersions(value, current) > 0) {
      latestByMajor[majorKey] = value;
    }
  }

  final selected = latestByMajor.values.toList()
    ..sort((left, right) => compareToolVersions(right, left));
  return selected.take(5).toList(growable: false);
}

String _majorVersionKey(String input) {
  final match = RegExp(r'(\d+)').firstMatch(input);
  return match?.group(1) ?? input;
}

bool _isJavaRuntimeOnlySuggestion(String version) {
  final normalized = version.toLowerCase();
  return normalized.contains('-jre') || normalized.contains('+jre');
}

class ToolsPage extends ConsumerStatefulWidget {
  const ToolsPage({super.key});

  @override
  ConsumerState<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends ConsumerState<ToolsPage> {
  String? _selectedToolId;
  final Set<String> _requestedToolIds = <String>{};
  final Set<String> _loadingToolIds = <String>{};
  final Set<String> _failedToolIds = <String>{};
  final Map<String, ToolRecord> _hydratedTools = <String, ToolRecord>{};
  var _refreshing = false;

  void _showFeedback(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadToolDetail(
    String toolId, {
    bool forceRefresh = false,
  }) async {
    if (_loadingToolIds.contains(toolId)) {
      return;
    }

    setState(() {
      _requestedToolIds.add(toolId);
      _loadingToolIds.add(toolId);
      _failedToolIds.remove(toolId);
    });

    try {
      final detail = forceRefresh
          ? await ref.refresh(toolDetailProvider(toolId).future)
          : await ref.read(toolDetailProvider(toolId).future);
      if (!mounted) {
        return;
      }
      setState(() {
        _hydratedTools[toolId] = detail;
        _failedToolIds.remove(toolId);
      });
    } catch (error) {
      _showFeedback('读取版本详情失败，请稍后重试。');
      if (!mounted) {
        return;
      }
      setState(() {
        _failedToolIds.add(toolId);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingToolIds.remove(toolId);
        });
      }
    }
  }

  Future<void> _refreshTools() async {
    if (_refreshing) {
      _showFeedback('工具数据正在刷新，请稍候。');
      return;
    }

    setState(() {
      _refreshing = true;
      _hydratedTools.clear();
      _requestedToolIds.clear();
      _loadingToolIds.clear();
      _failedToolIds.clear();
    });

    try {
      final _ = await ref.refresh(toolsProvider.future);
      final selectedToolId = _selectedToolId;
      if (selectedToolId != null) {
        await _loadToolDetail(selectedToolId, forceRefresh: true);
      }
      _showFeedback('工具状态已刷新。');
    } catch (_) {
      _showFeedback('刷新工具状态失败，请稍后重试。');
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final toolsValue = ref.watch(toolsProvider);

    return AsyncStateView(
      value: toolsValue,
      builder: (tools) {
        final displayTools = tools
            .map((tool) => _hydratedTools[tool.id] ?? tool)
            .toList(growable: false);

        return AppPageScaffold(
          title: '工具版本',
          description: '按工具查看当前版本，并在需要时升级或卸载。',
          actions: [
            OutlinedButton.icon(
              onPressed: _refreshing ? null : _refreshTools,
              icon: _refreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(_refreshing ? '刷新中...' : '刷新状态'),
            ),
            FilledButton.icon(
              onPressed: () => _openInstallToolFlow(context),
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text('安装工具'),
            ),
          ],
          child: _ToolList(
            tools: displayTools,
            selectedToolId: _selectedToolId,
            hydratedTools: _hydratedTools,
            loadingToolIds: _loadingToolIds,
            requestedToolIds: _requestedToolIds,
            failedToolIds: _failedToolIds,
            onSelected: _selectTool,
            onRetryDetail: _retryToolDetail,
            onOpenPreview: _openToolActionPreview,
          ),
        );
      },
    );
  }

  void _selectTool(String id) {
    if (_selectedToolId == id) {
      setState(() {
        _selectedToolId = null;
      });
      return;
    }

    setState(() {
      _selectedToolId = id;
      _requestedToolIds.add(id);
    });

    if (!_loadingToolIds.contains(id) &&
        !_hydratedTools.containsKey(id) &&
        !_failedToolIds.contains(id)) {
      unawaited(_loadToolDetail(id));
    }
  }

  void _retryToolDetail(String id) {
    unawaited(_loadToolDetail(id, forceRefresh: true));
  }

  Future<void> _openInstallToolFlow(BuildContext context) async {
    final request = await showDialog<_InstallToolRequest>(
      context: context,
      builder: (dialogContext) => const _InstallToolDialog(),
    );
    if (request == null || !mounted || !context.mounted) {
      return;
    }

    final installCommand = 'mise install ${request.tool}@${request.version}';
    final useCommand = 'mise use --global ${request.tool}@${request.version}';

    await _openToolActionPreview(
      context,
      ActionPreviewDialogData(
        title: '安装 ${request.tool}@${request.version}',
        summary: '会先安装这个版本，再把它写成全局默认版本。',
        command: '$installCommand\n$useCommand',
        level: HealthLevel.info,
        affectedFiles: [_globalConfigPath(), 'mise 安装缓存 / 已安装版本'],
        impactScope: ['会改变全局默认工具版本。', '安装完成后会自动刷新工具页与总览页数据。'],
        riskNotes: const [
          '安装时需要访问网络，过程可能会持续一段时间。',
          '如果版本号无效，安装会失败，失败结果会记录到最近操作。',
        ],
        confirmLabel: '确认安装',
      ),
    );
  }

  Future<void> _openToolActionPreview(
    BuildContext context,
    ActionPreviewDialogData data,
  ) async {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showActionPreviewDialog(context, data: data);
    if (!confirmed) {
      if (data.requiresConfirmation) {
        await ref
            .read(historyServiceProvider)
            .appendEntry(
              HistoryEntry(
                command: data.command,
                timestamp: _formatNow(),
                detail: '用户取消了 ${data.title}。',
                level: HealthLevel.info,
                status: HistoryStatus.canceled,
              ),
            );
      }
      return;
    }

    if (!mounted || !context.mounted || !data.requiresConfirmation) {
      return;
    }

    final progressState = ValueNotifier<_ActionProgressState>(
      _ActionProgressState.initial(title: data.title, command: data.command),
    );
    _showRunningDialog(context, progressState: progressState);
    HistoryEntry? failureEntryToShow;
    String? snackMessage;
    try {
      final result = await ref
          .read(miseActionServiceProvider)
          .runScript(
            data.command,
            onProgress: (event) {
              progressState.value = progressState.value.apply(event);
            },
          );
      if (!mounted || !context.mounted) {
        return;
      }

      final success = result.isSuccess;
      final diagnosis = success
          ? null
          : diagnoseMiseCommandFailure(
              command: data.command,
              stdout: result.stdout,
              stderr: result.stderr,
            );
      final historyEntry = HistoryEntry(
        command: data.command,
        timestamp: _formatNow(),
        detail: success
            ? '已通过界面执行 ${data.title}。'
            : _appendLockfileCleanupDetail(
                diagnosis?.detail ?? '${data.title} 执行失败，已保留实际 CLI 和错误输出。',
                result.lockfileCleanupReport.detail,
              ),
        level: success ? data.level : HealthLevel.warning,
        status: success ? HistoryStatus.success : HistoryStatus.failure,
        exitCode: result.exitCode,
        durationMs: result.duration.inMilliseconds,
        stdout: result.stdout,
        stderr: result.stderr,
        stdoutSnippet: result.stdoutSnippet,
        stderrSnippet: result.stderrSnippet,
      );
      await ref.read(historyServiceProvider).appendEntry(historyEntry);

      if (success) {
        final affectedToolIds = _extractAffectedToolIds(data.command);
        if (mounted) {
          setState(() {
            if (affectedToolIds.isEmpty) {
              _hydratedTools.clear();
              _requestedToolIds.clear();
              _loadingToolIds.clear();
              _failedToolIds.clear();
            } else {
              for (final toolId in affectedToolIds) {
                _hydratedTools.remove(toolId);
                _requestedToolIds.remove(toolId);
                _loadingToolIds.remove(toolId);
                _failedToolIds.remove(toolId);
              }
            }
          });
        }

        ref.invalidate(toolsProvider);
        await ref.read(toolsProvider.future);
        ref.invalidate(dashboardProvider);

        if (!mounted) {
          return;
        }

        for (final toolId in affectedToolIds) {
          if (toolId == _selectedToolId) {
            unawaited(_loadToolDetail(toolId, forceRefresh: true));
          }
        }
      } else {
        ref.invalidate(dashboardProvider);
      }

      snackMessage = _actionSnackMessage(
        title: data.title,
        success: success,
        diagnosis: diagnosis,
        cleanedLockfiles: result.lockfileCleanupReport.removedPaths.isNotEmpty,
      );
      if (!success) {
        failureEntryToShow = historyEntry;
      }
    } catch (error) {
      final historyEntry = HistoryEntry(
        command: data.command,
        timestamp: _formatNow(),
        detail: '${data.title} 执行异常，界面已拦截并保留错误信息。',
        level: HealthLevel.warning,
        status: HistoryStatus.failure,
        exitCode: -1,
        stderr: error.toString(),
        stderrSnippet: error.toString(),
      );
      await ref.read(historyServiceProvider).appendEntry(historyEntry);
      snackMessage = '${data.title} 执行异常，已打开错误详情。';
      failureEntryToShow = historyEntry;
    } finally {
      if (rootNavigator.mounted && rootNavigator.canPop()) {
        rootNavigator.pop();
      }
      progressState.dispose();
    }

    if (!mounted || !context.mounted) {
      return;
    }

    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(snackMessage)));

    if (failureEntryToShow != null) {
      await showHistoryEntryDialog(context, entry: failureEntryToShow);
    }
  }

  void _showRunningDialog(
    BuildContext context, {
    required ValueNotifier<_ActionProgressState> progressState,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: _ActionProgressDialog(progressState: progressState),
      ),
    );
  }

  String _formatNow() {
    final now = DateTime.now();
    final hours = now.hour.toString().padLeft(2, '0');
    final minutes = now.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  String _appendLockfileCleanupDetail(String detail, String? cleanupDetail) {
    final value = cleanupDetail?.trim();
    if (value == null || value.isEmpty) {
      return detail;
    }
    return '$detail\n\n$value';
  }

  String _actionSnackMessage({
    required String title,
    required bool success,
    required MiseFailureDiagnosis? diagnosis,
    required bool cleanedLockfiles,
  }) {
    if (success) {
      return '$title 已执行完成。';
    }
    if (cleanedLockfiles) {
      return '$title 执行失败，已清理残留锁文件。';
    }
    if (diagnosis == null) {
      return '$title 执行失败，已打开错误详情。';
    }
    return '$title 执行失败：${diagnosis.summary}';
  }

  String _globalConfigPath() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      return '~/.config/mise/config.toml';
    }
    return '$home/.config/mise/config.toml';
  }

  Set<String> _extractAffectedToolIds(String command) {
    final toolIds = <String>{};
    final matcher = RegExp(
      r'mise\s+install\s+([a-zA-Z0-9._-]+)|mise\s+uninstall\s+(?:--all\s+)?([a-zA-Z0-9._-]+)|mise\s+use\s+(?:--global\s+)?(?:--remove\s+)?([a-zA-Z0-9._-]+)',
      caseSensitive: false,
    );

    for (final match in matcher.allMatches(command)) {
      final toolId = (match.group(1) ?? match.group(2) ?? match.group(3))
          ?.trim();
      if (toolId != null && toolId.isNotEmpty) {
        toolIds.add(toolId);
      }
    }

    return toolIds;
  }
}

class _ActionProgressState {
  const _ActionProgressState({
    required this.title,
    required this.totalCommands,
    required this.completedCommands,
    required this.currentCommandIndex,
    required this.currentCommand,
    required this.status,
    required this.logs,
  });

  final String title;
  final int totalCommands;
  final int completedCommands;
  final int currentCommandIndex;
  final String currentCommand;
  final String status;
  final List<String> logs;

  factory _ActionProgressState.initial({
    required String title,
    required String command,
  }) {
    final commands = _parseProgressCommands(command);
    return _ActionProgressState(
      title: title,
      totalCommands: commands.length,
      completedCommands: 0,
      currentCommandIndex: 0,
      currentCommand: commands.isEmpty ? command.trim() : commands.first,
      status: '准备执行',
      logs: const [],
    );
  }

  double? get progressValue {
    if (totalCommands == 0) {
      return null;
    }
    final runningOffset = currentCommandIndex > completedCommands ? 0.35 : 0;
    final value = (completedCommands + runningOffset) / totalCommands;
    return value.clamp(0, 1).toDouble();
  }

  String get stepLabel {
    if (totalCommands == 0) {
      return '准备中';
    }
    final index = currentCommandIndex == 0 ? 1 : currentCommandIndex;
    return '$index/$totalCommands';
  }

  _ActionProgressState apply(MiseActionProgressEvent event) {
    return switch (event.type) {
      MiseActionProgressEventType.commandStarted => _copyWith(
        currentCommandIndex: event.commandIndex,
        currentCommand: event.command,
        status: '正在执行 ${event.commandIndex}/${event.totalCommands}',
        logs: _appendLogLines(logs, '\$ ${event.command}'),
      ),
      MiseActionProgressEventType.output => _copyWith(
        currentCommandIndex: event.commandIndex,
        currentCommand: event.command,
        status: '正在执行 ${event.commandIndex}/${event.totalCommands}',
        logs: _appendLogLines(logs, event.output ?? ''),
      ),
      MiseActionProgressEventType.commandFinished => _copyWith(
        completedCommands: event.exitCode == 0
            ? event.commandIndex
            : completedCommands,
        currentCommandIndex: event.commandIndex,
        currentCommand: event.command,
        status: event.exitCode == 0
            ? '已完成 ${event.commandIndex}/${event.totalCommands}'
            : '执行失败，正在整理结果',
        logs: _appendLogLines(logs, 'exit ${event.exitCode ?? -1}'),
      ),
      MiseActionProgressEventType.lockfileCleanup => _copyWith(
        status: '已处理异常状态',
        logs: _appendLogLines(logs, event.lockfileCleanupReport?.detail ?? ''),
      ),
    };
  }

  _ActionProgressState _copyWith({
    int? completedCommands,
    int? currentCommandIndex,
    String? currentCommand,
    String? status,
    List<String>? logs,
  }) {
    return _ActionProgressState(
      title: title,
      totalCommands: totalCommands,
      completedCommands: completedCommands ?? this.completedCommands,
      currentCommandIndex: currentCommandIndex ?? this.currentCommandIndex,
      currentCommand: currentCommand ?? this.currentCommand,
      status: status ?? this.status,
      logs: logs ?? this.logs,
    );
  }

  static List<String> _parseProgressCommands(String command) {
    return const LineSplitter()
        .convert(command)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toList();
  }

  static List<String> _appendLogLines(List<String> current, String output) {
    final normalized = output.replaceAll('\r', '\n');
    final nextLines = normalized
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty)
        .toList();
    if (nextLines.isEmpty) {
      return current;
    }

    final next = <String>[...current, ...nextLines];
    if (next.length <= 80) {
      return next;
    }
    return next.sublist(next.length - 80);
  }
}

class _ActionProgressDialog extends StatelessWidget {
  const _ActionProgressDialog({required this.progressState});

  final ValueNotifier<_ActionProgressState> progressState;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: ValueListenableBuilder<_ActionProgressState>(
        valueListenable: progressState,
        builder: (context, state, _) {
          return Semantics(
            liveRegion: true,
            label: '${state.title} ${state.status}',
            child: Container(
              width: 620,
              constraints: const BoxConstraints(maxHeight: 560),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: colors.panel,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.borderStrong),
                boxShadow: [
                  BoxShadow(
                    color: colors.backgroundDeep.withValues(alpha: 0.18),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.3),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              state.status,
                              style: TextStyle(color: colors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        state.stepLabel,
                        style: TextStyle(
                          color: colors.textMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      value: state.progressValue,
                      backgroundColor: colors.panelMuted,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _CurrentCommandView(command: state.currentCommand),
                  const SizedBox(height: 14),
                  Flexible(child: _ActionLogView(logs: state.logs)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CurrentCommandView extends StatelessWidget {
  const _CurrentCommandView({required this.command});

  final String command;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.panelMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        command,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.textPrimary,
          fontFamily: 'monospace',
          fontSize: 12.5,
          height: 1.35,
        ),
      ),
    );
  }
}

class _ActionLogView extends StatelessWidget {
  const _ActionLogView({required this.logs});

  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      height: 260,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.backgroundDeep.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.42 : 0.06,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: logs.isEmpty
          ? Align(
              alignment: Alignment.topLeft,
              child: Text(
                '等待 mise 输出...',
                style: TextStyle(color: colors.textMuted),
              ),
            )
          : ListView.builder(
              reverse: true,
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final line = logs[logs.length - index - 1];
                return Text(
                  line,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.42,
                  ),
                );
              },
            ),
    );
  }
}

class _ToolWorkspaceLoading extends StatelessWidget {
  const _ToolWorkspaceLoading({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return AppPanel(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 2.6),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: TextStyle(color: colors.textMuted, height: 1.55),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolWorkspaceError extends StatelessWidget {
  const _ToolWorkspaceError({required this.toolName, required this.onRetry});

  final String toolName;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return AppPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.warning.withValues(alpha: 0.24)),
            ),
            child: Icon(Icons.refresh_rounded, color: colors.warning, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$toolName 详情读取失败',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  '可能是远端版本同步暂时不可用，或者当前网络无法访问 mise 数据源。',
                  style: TextStyle(color: colors.textMuted, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          OutlinedButton.icon(
            key: ValueKey('retry-tool-detail-$toolName'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

class _InstallToolRequest {
  const _InstallToolRequest({required this.tool, required this.version});

  final String tool;
  final String version;
}

class _InstallToolDialog extends ConsumerStatefulWidget {
  const _InstallToolDialog();

  @override
  ConsumerState<_InstallToolDialog> createState() => _InstallToolDialogState();
}

class _InstallToolDialogState extends ConsumerState<_InstallToolDialog> {
  final TextEditingController _toolController = TextEditingController();
  final TextEditingController _versionController = TextEditingController();
  final FocusNode _versionFocusNode = FocusNode();
  Timer? _lookupDebounce;
  var _loadingVersions = false;
  List<String> _versionSuggestions = const [];
  String? _lookupMessage;
  int _lookupToken = 0;

  @override
  void initState() {
    super.initState();
    _toolController.addListener(_scheduleVersionLookup);
    _versionFocusNode.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _toolController.removeListener(_scheduleVersionLookup);
    _toolController.dispose();
    _versionController.dispose();
    _versionFocusNode.dispose();
    super.dispose();
  }

  void _scheduleVersionLookup() {
    final tool = _toolController.text.trim();
    final scheduledToken = ++_lookupToken;

    _lookupDebounce?.cancel();
    if (mounted) {
      setState(() {
        _versionSuggestions = const [];
        _lookupMessage = tool.isEmpty ? null : '正在读取远端版本...';
        _loadingVersions = tool.isNotEmpty;
      });
    }
    _lookupDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _loadRemoteVersions(scheduledToken),
    );
  }

  Future<void> _loadRemoteVersions(int token) async {
    final tool = _toolController.text.trim();

    if (tool.isEmpty) {
      if (mounted && token == _lookupToken) {
        setState(() {
          _loadingVersions = false;
          _versionSuggestions = const [];
          _lookupMessage = null;
        });
      }
      return;
    }

    setState(() {
      _loadingVersions = true;
      _lookupMessage = null;
    });

    try {
      final versions = await ref
          .read(miseQueryServiceProvider)
          .fetchRemoteVersions(tool);
      if (!mounted || token != _lookupToken) {
        return;
      }
      final selected = selectVersionSuggestions(versions);

      setState(() {
        _loadingVersions = false;
        _versionSuggestions = selected;
        _lookupMessage = selected.isEmpty ? '没有拉到可选版本，仍可手动输入。' : null;
      });
    } catch (error) {
      if (!mounted || token != _lookupToken) {
        return;
      }
      setState(() {
        _loadingVersions = false;
        _versionSuggestions = const [];
        _lookupMessage = '远端版本读取失败，仍可手动输入版本号。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: colors.borderStrong),
          boxShadow: [
            BoxShadow(
              color: colors.backgroundDeep.withValues(alpha: 0.14),
              blurRadius: 32,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('安装新工具', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 10),
            Text(
              '输入要安装的工具名和版本，随后会进入执行前预览与确认。',
              style: TextStyle(color: colors.textMuted, height: 1.55),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _toolController,
              decoration: const InputDecoration(
                labelText: 'Tool',
                hintText: '例如: node / python / go / php',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _versionController,
              focusNode: _versionFocusNode,
              decoration: const InputDecoration(
                labelText: 'Version',
                hintText: '例如: 20 或 20.19.0 / 3.12 或 3.12.9 / latest',
              ),
            ),
            if (_versionFocusNode.hasFocus &&
                (_loadingVersions ||
                    _versionSuggestions.isNotEmpty ||
                    _lookupMessage != null)) ...[
              const SizedBox(height: 10),
              _VersionSuggestionList(
                loading: _loadingVersions,
                versions: _versionSuggestions,
                message: _lookupMessage,
                selectedVersion: _versionController.text.trim(),
                onSelected: (version) {
                  _versionController.text = version;
                  _versionController.selection = TextSelection.collapsed(
                    offset: version.length,
                  );
                  _versionFocusNode.unfocus();
                  setState(() {});
                },
              ),
            ],
            const SizedBox(height: 18),
            Text(
              '安装后会直接写成全局默认版本。',
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('继续预览'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final tool = _toolController.text.trim();
    final version = _versionController.text.trim();
    if (tool.isEmpty || version.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先填写工具名和版本号。')));
      return;
    }

    Navigator.of(
      context,
    ).pop(_InstallToolRequest(tool: tool, version: version));
  }
}

class _VersionSuggestionList extends StatelessWidget {
  const _VersionSuggestionList({
    required this.loading,
    required this.versions,
    required this.message,
    required this.selectedVersion,
    required this.onSelected,
  });

  final bool loading;
  final List<String> versions;
  final String? message;
  final String selectedVersion;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: loading
          ? const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(minHeight: 3),
            )
          : versions.isNotEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
                  child: Text(
                    '远端可选版本（各大版本最新发行版）',
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (var index = 0; index < versions.length; index++)
                  _VersionSuggestionRow(
                    version: versions[index],
                    selected: versions[index] == selectedVersion,
                    isFirst: index == 0,
                    onTap: () => onSelected(versions[index]),
                  ),
              ],
            )
          : Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                message ?? '没有拉到可选版本，仍可手动输入。',
                style: TextStyle(color: colors.textMuted, height: 1.45),
              ),
            ),
    );
  }
}

class _VersionSuggestionRow extends StatelessWidget {
  const _VersionSuggestionRow({
    required this.version,
    required this.selected,
    required this.isFirst,
    required this.onTap,
  });

  final String version;
  final bool selected;
  final bool isFirst;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? colors.info.withValues(alpha: 0.12)
            : colors.panel.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTapDown: (_) => onTap(),
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          hoverColor: colors.hover,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    version,
                    style: const TextStyle(
                      fontFamily: 'FiraCode',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isFirst)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '最新',
                      style: TextStyle(
                        color: colors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_rounded, size: 18, color: colors.info),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolList extends StatelessWidget {
  const _ToolList({
    required this.tools,
    required this.selectedToolId,
    required this.hydratedTools,
    required this.loadingToolIds,
    required this.requestedToolIds,
    required this.failedToolIds,
    required this.onSelected,
    required this.onRetryDetail,
    required this.onOpenPreview,
  });

  final List<ToolRecord> tools;
  final String? selectedToolId;
  final Map<String, ToolRecord> hydratedTools;
  final Set<String> loadingToolIds;
  final Set<String> requestedToolIds;
  final Set<String> failedToolIds;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onRetryDetail;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('已安装', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '按工具查看当前版本，并按需加载可升级信息。',
            style: TextStyle(color: colors.textMuted, height: 1.5),
          ),
          const SizedBox(height: 18),
          for (final tool in tools)
            KeyedSubtree(
              key: ValueKey('tool-accordion-${tool.id}'),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ToolAccordionItem(
                  tool: tool,
                  hydratedTool: hydratedTools[tool.id],
                  expanded: tool.id == selectedToolId,
                  detailLoading: loadingToolIds.contains(tool.id),
                  detailRequested: requestedToolIds.contains(tool.id),
                  detailFailed: failedToolIds.contains(tool.id),
                  onTap: () => onSelected(tool.id),
                  onRetryDetail: () => onRetryDetail(tool.id),
                  onOpenPreview: onOpenPreview,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolAccordionItem extends StatelessWidget {
  const _ToolAccordionItem({
    required this.tool,
    required this.hydratedTool,
    required this.expanded,
    required this.detailLoading,
    required this.detailRequested,
    required this.detailFailed,
    required this.onTap,
    required this.onRetryDetail,
    required this.onOpenPreview,
  });

  final ToolRecord tool;
  final ToolRecord? hydratedTool;
  final bool expanded;
  final bool detailLoading;
  final bool detailRequested;
  final bool detailFailed;
  final VoidCallback onTap;
  final VoidCallback onRetryDetail;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final detail = _resolveDetail();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ToolListItem(
          tool: tool,
          selected: expanded,
          detailLoading: detailLoading,
          detailRequested: detailRequested,
          detailFailed: detailFailed,
          onTap: onTap,
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return SizeTransition(
              sizeFactor: animation,
              axisAlignment: -1,
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: detail,
        ),
      ],
    );
  }

  Widget _resolveDetail() {
    if (!expanded) {
      return const SizedBox.shrink(key: ValueKey('collapsed-detail'));
    }

    if (detailLoading && hydratedTool == null) {
      return _AccordionDetailShell(
        key: ValueKey('loading-detail-${tool.id}'),
        child: _ToolWorkspaceLoading(
          title: '正在读取 ${tool.name} 的详情',
          message: '远端版本和详细信息返回后，会在这里展开。',
        ),
      );
    }

    final detailTool = hydratedTool;
    if (detailTool == null) {
      if (detailFailed) {
        return _AccordionDetailShell(
          key: ValueKey('failed-detail-${tool.id}'),
          child: _ToolWorkspaceError(
            toolName: tool.name,
            onRetry: onRetryDetail,
          ),
        );
      }
      return const SizedBox.shrink(key: ValueKey('empty-detail'));
    }

    return _AccordionDetailShell(
      key: ValueKey('ready-detail-${tool.id}-${detailTool.activeVersion}'),
      child: _ToolWorkspace(
        tool: detailTool,
        onRetryDetail: onRetryDetail,
        onOpenPreview: onOpenPreview,
      ),
    );
  }
}

class _AccordionDetailShell extends StatelessWidget {
  const _AccordionDetailShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 20),
      child: child,
    );
  }
}

class _ToolListItem extends StatelessWidget {
  const _ToolListItem({
    required this.tool,
    required this.selected,
    required this.detailLoading,
    required this.detailRequested,
    required this.detailFailed,
    required this.onTap,
  });

  final ToolRecord tool;
  final bool selected;
  final bool detailLoading;
  final bool detailRequested;
  final bool detailFailed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final hasActiveVersion = tool.installedVersions.any(
      (version) => version.isActive,
    );
    final latestValue = switch ((
      detailLoading,
      detailRequested,
      detailFailed,
      tool.remoteState,
    )) {
      (true, _, _, _) => '加载中...',
      (false, _, true, _) => '读取失败',
      (false, false, _, _) => '点击查看',
      (false, true, _, ToolRemoteState.unavailable) => '未获取',
      _ => tool.latestStableVersion,
    };

    return Material(
      color: selected
          ? colors.info.withValues(alpha: 0.10)
          : colors.panelRaised.withValues(alpha: 0.84),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        hoverColor: colors.hover,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tool.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(tool.category, style: TextStyle(color: colors.textMuted)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniFact(
                    label: hasActiveVersion ? '当前' : '已装',
                    value: tool.activeVersion,
                  ),
                  _MiniFact(label: '最新', value: latestValue),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolWorkspace extends StatelessWidget {
  const _ToolWorkspace({
    required this.tool,
    required this.onRetryDetail,
    required this.onOpenPreview,
  });

  final ToolRecord tool;
  final VoidCallback onRetryDetail;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ToolHeroPanel(
          tool: tool,
          onRetryDetail: onRetryDetail,
          onOpenPreview: onOpenPreview,
        ),
        const SizedBox(height: 18),
        _VersionInventoryPanel(
          title: '本机版本',
          subtitle: '已安装到本机，可直接切换。',
          toolId: tool.id,
          toolName: tool.name,
          inventoryType: _VersionInventoryType.installed,
          versions: tool.installedVersions,
          emptyState: const _PanelEmptyStateData(
            icon: Icons.inventory_2_outlined,
            title: '当前还没有本地版本库存',
            message: '安装过至少一个版本后，这里会显示完整的本机版本列表。',
            level: HealthLevel.info,
          ),
          onOpenPreview: onOpenPreview,
        ),
        const SizedBox(height: 18),
        _VersionInventoryPanel(
          title: '远端版本',
          subtitle: '可安装或升级的远端版本。',
          toolId: tool.id,
          toolName: tool.name,
          inventoryType: _VersionInventoryType.remote,
          versions: tool.remoteVersions,
          emptyState: const _PanelEmptyStateData(
            icon: Icons.cloud_off_rounded,
            title: '暂时没有拉到远端版本',
            message: '可以稍后重试同步，或者先使用上面的本机版本库存继续切换。',
            level: HealthLevel.warning,
          ),
          onOpenPreview: onOpenPreview,
        ),
      ],
    );
  }
}

class _ToolHeroPanel extends StatelessWidget {
  const _ToolHeroPanel({
    required this.tool,
    required this.onRetryDetail,
    required this.onOpenPreview,
  });

  final ToolRecord tool;
  final VoidCallback onRetryDetail;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final recommendedVersion = _recommendedVersion(tool);
    final latestLabel = switch (tool.remoteState) {
      ToolRemoteState.pending => '读取中',
      ToolRemoteState.unavailable => '未获取',
      ToolRemoteState.ready => tool.latestStableVersion,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border.withValues(alpha: 0.36)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 14,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      '当前 ${tool.activeVersion}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontFamily: 'FiraCode',
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '最新稳定版 $latestLabel',
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 13,
                        fontFamily: 'FiraCode',
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (tool.hasUpdate && recommendedVersion != null)
                    FilledButton.icon(
                      onPressed: () => onOpenPreview(
                        context,
                        ActionPreviewDialogData(
                          title:
                              '升级 ${tool.name} 到 ${recommendedVersion.version}',
                          summary: '会先安装新版本，再切换到这个版本。',
                          command: recommendedVersion.commandPreview,
                          level: HealthLevel.healthy,
                          affectedFiles: _affectedFilesForToolCommand(
                            recommendedVersion.commandPreview,
                          ),
                          impactScope: const ['会新增本地已安装版本。', '默认使用的版本会切换到新版本。'],
                          riskNotes: const ['升级时需要访问网络，过程可能会持续一段时间。'],
                          confirmLabel: '确认升级',
                        ),
                      ),
                      icon: const Icon(Icons.upgrade_rounded),
                      label: Text('升级到 ${recommendedVersion.version}'),
                    ),
                  TextButton.icon(
                    onPressed: () => onOpenPreview(
                      context,
                      ActionPreviewDialogData(
                        title: '卸载 ${tool.name}',
                        summary: '会先从全局配置里移除这个工具，再删除本机上这个工具的所有已安装版本。',
                        command:
                            'mise use --global --remove ${tool.id}\n'
                            'mise uninstall --all ${tool.id}',
                        level: HealthLevel.warning,
                        affectedFiles: _affectedFilesForToolCommand(
                          'mise use --global --remove ${tool.id}\n'
                          'mise uninstall --all ${tool.id}',
                        ),
                        impactScope: const [
                          '全局默认配置里不再声明这个工具。',
                          '这个工具的所有本地已安装版本都会被移除。',
                          '如果其他配置仍然依赖这个工具，相关命令仍可能报缺失。',
                        ],
                        riskNotes: const ['卸载前请确认没有其他配置还在依赖这个工具。'],
                        confirmLabel: '确认卸载',
                      ),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('卸载工具'),
                  ),
                ],
              ),
            ],
          ),
          if (tool.notices.isNotEmpty) ...[
            const SizedBox(height: 18),
            Column(
              children: [
                for (final notice in tool.notices) ...[
                  InlineNoticeBar(
                    notice: notice,
                    actionLabel: _canRetryRemoteNotice(notice) ? '重试' : null,
                    actionIcon: _canRetryRemoteNotice(notice)
                        ? Icons.refresh_rounded
                        : null,
                    onAction: _canRetryRemoteNotice(notice)
                        ? onRetryDetail
                        : null,
                  ),
                  if (notice != tool.notices.last) const SizedBox(height: 12),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool _canRetryRemoteNotice(InlineNotice notice) {
    return tool.remoteState == ToolRemoteState.unavailable &&
        notice.title.contains('远端目录暂时不可用');
  }

  ToolVersionRecord? _recommendedVersion(ToolRecord tool) {
    for (final version in tool.remoteVersions) {
      if (version.isRecommended) {
        return version;
      }
    }
    return null;
  }
}

enum _VersionInventoryType { installed, remote }

class _VersionInventoryPanel extends StatelessWidget {
  const _VersionInventoryPanel({
    required this.title,
    required this.subtitle,
    required this.toolId,
    required this.toolName,
    required this.inventoryType,
    required this.versions,
    this.emptyState,
    required this.onOpenPreview,
  });

  final String title;
  final String subtitle;
  final String toolId;
  final String toolName;
  final _VersionInventoryType inventoryType;
  final List<ToolVersionRecord> versions;
  final _PanelEmptyStateData? emptyState;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ToolSectionHeader(
            title: title,
            subtitle: subtitle,
            badgeLabel: versions.length > 1 ? '${versions.length} 条' : null,
          ),
          const SizedBox(height: 18),
          if (versions.isEmpty)
            _PanelEmptyStateCard(
              data:
                  emptyState ??
                  const _PanelEmptyStateData(
                    icon: Icons.info_outline_rounded,
                    title: '当前没有可展示的数据',
                    message: '稍后可以重新同步，或先使用当前本机版本继续操作。',
                    level: HealthLevel.info,
                  ),
              onOpenPreview: onOpenPreview,
            )
          else
            Column(
              children: [
                for (var index = 0; index < versions.length; index++) ...[
                  _VersionCard(
                    toolId: toolId,
                    toolName: toolName,
                    version: versions[index],
                    inventoryType: inventoryType,
                    onOpenPreview: onOpenPreview,
                  ),
                  if (index != versions.length - 1)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: colors.border.withValues(alpha: 0.46),
                    ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({
    required this.toolId,
    required this.toolName,
    required this.version,
    required this.inventoryType,
    required this.onOpenPreview,
  });

  final String toolId;
  final String toolName;
  final ToolVersionRecord version;
  final _VersionInventoryType inventoryType;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final statusLabel = _statusLabel();
    final statusLevel = _statusLevel();

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 520;
        final actionRow = _VersionActions(
          toolId: toolId,
          toolName: toolName,
          version: version,
          inventoryType: inventoryType,
          onOpenPreview: onOpenPreview,
        );

        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              version.version,
              style: TextStyle(
                color: colors.textPrimary,
                fontFamily: 'FiraCode',
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (statusLabel != null) ...[
              const SizedBox(height: 6),
              _VersionStateLabel(label: statusLabel, level: statusLevel),
            ],
          ],
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 14),
              info,
              const SizedBox(height: 12),
              actionRow,
              const SizedBox(height: 14),
            ],
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: info),
              const SizedBox(width: 16),
              actionRow,
            ],
          ),
        );
      },
    );
  }

  String? _statusLabel() {
    if (version.isActive) {
      return '当前使用';
    }
    if (version.isRecommended) {
      return '推荐升级';
    }
    if (version.isAlias) {
      return '别名映射';
    }
    return null;
  }

  HealthLevel _statusLevel() {
    if (version.isActive) {
      return HealthLevel.healthy;
    }
    if (version.isRecommended) {
      return HealthLevel.info;
    }
    return version.level;
  }
}

class _VersionActions extends StatelessWidget {
  const _VersionActions({
    required this.toolId,
    required this.toolName,
    required this.version,
    required this.inventoryType,
    required this.onOpenPreview,
  });

  final String toolId;
  final String toolName;
  final ToolVersionRecord version;
  final _VersionInventoryType inventoryType;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!version.isActive && version.isInstalled)
          TextButton(
            onPressed: () => onOpenPreview(
              context,
              ActionPreviewDialogData(
                title: '切换到 ${version.version}',
                summary: '这个版本已经在本机安装，确认后会开始版本切换。',
                command: version.commandPreview,
                level: version.level,
                affectedFiles: _affectedFilesForToolCommand(
                  version.commandPreview,
                ),
                impactScope: const ['当前工具的默认激活版本会变化。', '相关项目的解析结果可能随之更新。'],
                riskNotes: const ['切换前请先确认是否有项目级版本覆盖。'],
                confirmLabel: '确认切换',
              ),
            ),
            child: const Text('切换'),
          )
        else if (!version.isInstalled)
          TextButton(
            onPressed: () => onOpenPreview(
              context,
              ActionPreviewDialogData(
                title: '安装 ${version.version}',
                summary: '这个版本还没安装到本机，确认后会开始安装。',
                command: version.commandPreview,
                level: version.level,
                affectedFiles: _affectedFilesForToolCommand(
                  version.commandPreview,
                ),
                impactScope: const ['会新增本地已安装版本记录。', '如果接着激活，当前版本来源也可能改变。'],
                riskNotes: const ['安装时会访问网络，并更新本地缓存。'],
                confirmLabel: version.isRecommended ? '确认升级' : '确认安装',
              ),
            ),
            child: Text(version.isRecommended ? '升级' : '安装'),
          ),
        if (inventoryType == _VersionInventoryType.installed &&
            version.isInstalled)
          TextButton.icon(
            onPressed: () => onOpenPreview(
              context,
              ActionPreviewDialogData(
                title: '卸载 $toolName ${version.version}',
                summary: version.isActive
                    ? '这个版本当前正在使用。卸载只会删除本机安装目录，不会修改全局或项目配置。'
                    : '会删除本机这个已安装版本，不会修改全局或项目配置。',
                command: 'mise uninstall $toolId@${version.version}',
                level: HealthLevel.warning,
                affectedFiles: _affectedFilesForToolCommand(
                  'mise uninstall $toolId@${version.version}',
                ),
                impactScope: const ['只移除这个具体版本的本地安装记录。', '全局和项目配置不会被自动修改。'],
                riskNotes: version.isActive
                    ? const [
                        '当前生效版本被删除后，如果配置仍引用它，后续命令可能提示缺失。',
                        '卸载前请确认已经切换到其他版本，或准备重新安装。',
                      ]
                    : const ['如果其他项目配置仍引用这个版本，进入项目后可能需要重新安装。'],
                confirmLabel: '确认卸载版本',
              ),
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('卸载'),
          ),
      ],
    );
  }
}

class _VersionStateLabel extends StatelessWidget {
  const _VersionStateLabel({required this.label, required this.level});

  final String label;
  final HealthLevel level;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final color = switch (level) {
      HealthLevel.healthy => colors.accent,
      HealthLevel.info => colors.info,
      HealthLevel.warning => colors.warning,
      HealthLevel.critical => colors.danger,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ToolSectionHeader extends StatelessWidget {
  const _ToolSectionHeader({
    required this.title,
    required this.subtitle,
    this.badgeLabel,
  });

  final String title;
  final String subtitle;
  final String? badgeLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(color: colors.textMuted, height: 1.5),
                  ),
                ],
              ),
            ),
            if (badgeLabel != null) ...[
              const SizedBox(width: 12),
              _SectionCountLabel(label: badgeLabel!),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Container(
          height: 1,
          width: double.infinity,
          color: colors.border.withValues(alpha: 0.8),
        ),
      ],
    );
  }
}

class _SectionCountLabel extends StatelessWidget {
  const _SectionCountLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Text(
      label,
      style: TextStyle(
        color: colors.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _PanelEmptyStateData {
  const _PanelEmptyStateData({
    required this.icon,
    required this.title,
    required this.message,
    required this.level,
  });

  final IconData icon;
  final String title;
  final String message;
  final HealthLevel level;
}

class _PanelEmptyStateCard extends StatelessWidget {
  const _PanelEmptyStateCard({required this.data, this.onOpenPreview});

  final _PanelEmptyStateData data;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )?
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: switch (data.level) {
                    HealthLevel.healthy => colors.accent.withValues(
                      alpha: 0.14,
                    ),
                    HealthLevel.info => colors.info.withValues(alpha: 0.14),
                    HealthLevel.warning => colors.warning.withValues(
                      alpha: 0.14,
                    ),
                    HealthLevel.critical => colors.danger.withValues(
                      alpha: 0.14,
                    ),
                  },
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  data.icon,
                  color: switch (data.level) {
                    HealthLevel.healthy => colors.accent,
                    HealthLevel.info => colors.info,
                    HealthLevel.warning => colors.warning,
                    HealthLevel.critical => colors.danger,
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.message,
                      style: TextStyle(color: colors.textMuted, height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniFact extends StatelessWidget {
  const _MiniFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.backgroundSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: colors.textMuted,
          fontSize: 12,
          fontFamily: 'FiraCode',
        ),
      ),
    );
  }
}

List<String> _affectedFilesForToolCommand(String command) {
  final normalized = command.toLowerCase();
  final files = <String>[];
  final home = Platform.environment['HOME'];

  if (normalized.contains('mise use --global ')) {
    if (home != null && home.isNotEmpty) {
      files.add('$home/.config/mise/config.toml');
    } else {
      files.add('~/.config/mise/config.toml');
    }
  } else if (normalized.contains('mise use ')) {
    files.add('${Directory.current.path}/mise.toml');
  }

  if (normalized.contains('mise install ')) {
    files.add('mise 安装缓存 / 已安装版本');
  }

  if (normalized.contains('mise uninstall ')) {
    files.add('mise 安装缓存 / 已安装版本');
  }

  return files;
}

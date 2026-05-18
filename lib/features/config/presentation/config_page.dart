import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mise_gui/app/bootstrap/dependencies.dart';
import 'package:mise_gui/app/theme/app_theme.dart';
import 'package:mise_gui/features/config/application/config_provider.dart';
import 'package:mise_gui/features/projects/application/projects_provider.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/shared/ui/app_page_scaffold.dart';
import 'package:mise_gui/shared/ui/app_panel.dart';
import 'package:mise_gui/shared/ui/async_state_view.dart';
import 'package:mise_gui/shared/ui/status_badge.dart';

const Map<String, String> javaAliasDefaults = {
  '8': 'corretto-8',
  '11': 'corretto-11',
  '17': 'corretto-17',
  '18': 'corretto-18',
  '19': 'corretto-19',
  '20': 'corretto-20',
  '21': 'corretto-21',
  '22': 'corretto-22',
  '23': 'corretto-23',
  '24': 'corretto-24',
  '25': 'corretto-25',
};

String buildJavaAliasesConfigContent({
  required String currentContent,
  required bool enabled,
  required Map<String, String> aliases,
}) {
  final normalized = _normalizeEditorContent(currentContent);
  final lines = normalized.isEmpty
      ? <String>[]
      : const LineSplitter().convert(normalized);
  final sectionStart = _findTomlSectionStart(lines, 'tool_alias.java.versions');
  final nextLines = <String>[];

  if (sectionStart == -1) {
    nextLines.addAll(lines);
  } else {
    final sectionEnd = _findTomlSectionEnd(lines, sectionStart);
    nextLines
      ..addAll(lines.take(sectionStart))
      ..addAll(lines.skip(sectionEnd));
  }

  if (enabled && aliases.isNotEmpty) {
    while (nextLines.isNotEmpty && nextLines.last.trim().isEmpty) {
      nextLines.removeLast();
    }
    if (nextLines.isNotEmpty) {
      nextLines.add('');
    }
    nextLines.add('[tool_alias.java.versions]');
    for (final entry in aliases.entries) {
      nextLines.add('${entry.key} = "${_escapeTomlString(entry.value)}"');
    }
  }

  return _normalizeEditorContent(nextLines.join('\n'));
}

String _formatJavaAliasAssignments(Map<String, String> aliases) {
  return aliases.entries
      .map((entry) => '${entry.key} = "${_escapeTomlString(entry.value)}"')
      .join('\n');
}

Map<String, String> _parseJavaAliasAssignments(String content) {
  final result = <String, String>{};
  final lines = content.split('\n');

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith('[')) {
      continue;
    }
    final separatorIndex = trimmed.indexOf('=');
    if (separatorIndex == -1) {
      continue;
    }
    final key = trimmed.substring(0, separatorIndex).trim().replaceAll('"', '');
    final value = _stripTomlQuotes(trimmed.substring(separatorIndex + 1));
    if (key.isEmpty || value.isEmpty) {
      continue;
    }
    result[key] = value;
  }

  return result;
}

String? _extractTomlSection(String content, String sectionName) {
  final normalized = _normalizeEditorContent(content);
  if (normalized.isEmpty) {
    return null;
  }

  final lines = const LineSplitter().convert(normalized);
  final sectionStart = _findTomlSectionStart(lines, sectionName);
  if (sectionStart == -1) {
    return null;
  }
  final sectionEnd = _findTomlSectionEnd(lines, sectionStart);
  return lines.sublist(sectionStart, sectionEnd).join('\n');
}

int _findTomlSectionStart(List<String> lines, String sectionName) {
  final header = '[$sectionName]';
  for (var index = 0; index < lines.length; index++) {
    if (lines[index].trim() == header) {
      return index;
    }
  }
  return -1;
}

int _findTomlSectionEnd(List<String> lines, int sectionStart) {
  for (var index = sectionStart + 1; index < lines.length; index++) {
    final trimmed = lines[index].trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      return index;
    }
  }
  return lines.length;
}

String _stripTomlQuotes(String value) {
  final trimmed = value.trim();
  if (trimmed.length < 2) {
    return trimmed;
  }
  final quote = trimmed[0];
  if ((quote != '"' && quote != "'") || trimmed[trimmed.length - 1] != quote) {
    return trimmed;
  }
  return trimmed.substring(1, trimmed.length - 1).replaceAll(r'\"', '"');
}

String _escapeTomlString(String value) {
  return value.replaceAll('\\', r'\\').replaceAll('"', r'\"');
}

String _normalizeEditorContent(String value) {
  final normalized = value.replaceAll('\r\n', '\n').trimRight();
  return normalized.isEmpty ? '' : '$normalized\n';
}

class ConfigPage extends ConsumerStatefulWidget {
  const ConfigPage({super.key});

  @override
  ConsumerState<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends ConsumerState<ConfigPage> {
  static const _refreshDebounce = Duration(seconds: 1);

  DateTime? _lastRefreshAt;
  var _refreshing = false;

  Future<void> _handleRefresh() async {
    if (_refreshing) {
      _showFeedback('正在刷新配置，请稍候。');
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
      final refreshed = ref.refresh(configProvider.future);
      await refreshed;
      _showFeedback('配置数据已刷新。');
    } catch (_) {
      _showFeedback('刷新失败，请稍后重试。');
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
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
  Widget build(BuildContext context) {
    final configValue = ref.watch(configProvider);
    final projectOptions = ref
        .watch(projectsProvider)
        .maybeWhen(
          data: (items) => items,
          orElse: () => const <ProjectRecord>[],
        );
    final selectedProject = ref.watch(selectedConfigProjectProvider);

    return AsyncStateView(
      value: configValue,
      builder: (workspace) {
        ConfigDocumentData? globalDocument;
        for (final document in workspace.documents) {
          if (document.id == 'global') {
            globalDocument = document;
            break;
          }
        }

        return AppPageScaffold(
          title: '配置管理',
          description: '管理全局和项目配置，保存前先查看差异。',
          child: Column(
            children: [
              _ConfigAutoRefresh(
                paths: workspace.documents
                    .map((document) => document.path)
                    .toList(),
              ),
              _DocumentStrip(
                documents: workspace.documents,
                projectOptions: projectOptions,
                selectedProject: selectedProject,
                onSelectProject: (path) {
                  ref.read(selectedConfigProjectPathProvider.notifier).state =
                      path;
                },
                refreshing: _refreshing,
                onRefresh: _handleRefresh,
                onEditDocument: (document) => _openDocumentEditor(
                  context: context,
                  ref: ref,
                  document: document,
                ),
              ),
              if (workspace.runtimeSettings case final runtimeSettings?) ...[
                const SizedBox(height: 18),
                _RuntimeSettingsPanel(
                  data: runtimeSettings,
                  onEdit: () => _openRuntimeSettingsEditor(
                    context: context,
                    ref: ref,
                    data: runtimeSettings,
                  ),
                ),
              ],
              if (workspace.proxySettings case final proxySettings?) ...[
                const SizedBox(height: 18),
                _ProxySettingsPanel(
                  data: proxySettings,
                  onEdit: () => _openProxySettingsEditor(
                    context: context,
                    ref: ref,
                    data: proxySettings,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              for (final section in workspace.sections)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: _ConfigSection(
                    section: section,
                    onEditProxy:
                        section.title == '运行时设置' &&
                            workspace.proxySettings != null
                        ? () => _openProxySettingsEditor(
                            context: context,
                            ref: ref,
                            data: workspace.proxySettings!,
                          )
                        : null,
                    onEditJavaAliases:
                        section.title == 'Java 别名' && globalDocument != null
                        ? () => _openJavaAliasesEditor(
                            context: context,
                            ref: ref,
                            document: globalDocument!,
                          )
                        : null,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openDocumentEditor({
    required BuildContext context,
    required WidgetRef ref,
    required ConfigDocumentData document,
  }) async {
    final didSave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          _ConfigDocumentEditorDialog(document: document),
    );

    if (didSave == true && context.mounted) {
      ref.invalidate(configProvider);
      final messenger = ScaffoldMessenger.of(context);
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('${document.title} 已写回 ${document.fileName}')),
      );
    }
  }

  Future<void> _openRuntimeSettingsEditor({
    required BuildContext context,
    required WidgetRef ref,
    required ConfigRuntimeSettingsData data,
  }) async {
    final didSave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _RuntimeSettingsEditorDialog(data: data),
    );

    if (didSave == true && context.mounted) {
      ref.invalidate(configProvider);
      final messenger = ScaffoldMessenger.of(context);
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('运行时设置已写回全局配置。')));
    }
  }

  Future<void> _openProxySettingsEditor({
    required BuildContext context,
    required WidgetRef ref,
    required ConfigProxySettingsData data,
  }) async {
    final didSave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ProxySettingsEditorDialog(data: data),
    );

    if (didSave == true && context.mounted) {
      ref.invalidate(configProvider);
      final messenger = ScaffoldMessenger.of(context);
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('代理设置已写回全局配置。')));
    }
  }

  Future<void> _openJavaAliasesEditor({
    required BuildContext context,
    required WidgetRef ref,
    required ConfigDocumentData document,
  }) async {
    final didSave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _JavaAliasesEditorDialog(document: document),
    );

    if (didSave == true && context.mounted) {
      ref.invalidate(configProvider);
      final messenger = ScaffoldMessenger.of(context);
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('Java 别名已写回全局配置。')));
    }
  }
}

class _ConfigAutoRefresh extends ConsumerStatefulWidget {
  const _ConfigAutoRefresh({required this.paths});

  final List<String> paths;

  @override
  ConsumerState<_ConfigAutoRefresh> createState() => _ConfigAutoRefreshState();
}

class _ConfigAutoRefreshState extends ConsumerState<_ConfigAutoRefresh> {
  StreamSubscription<void>? _subscription;

  @override
  void initState() {
    super.initState();
    _bindWatcher();
  }

  @override
  void didUpdateWidget(covariant _ConfigAutoRefresh oldWidget) {
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
          ref.invalidate(configProvider);
        });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _DocumentStrip extends StatelessWidget {
  const _DocumentStrip({
    required this.documents,
    required this.projectOptions,
    required this.selectedProject,
    required this.onSelectProject,
    required this.refreshing,
    required this.onRefresh,
    required this.onEditDocument,
  });

  final List<ConfigDocumentData> documents;
  final List<ProjectRecord> projectOptions;
  final ProjectRecord? selectedProject;
  final ValueChanged<String?> onSelectProject;
  final bool refreshing;
  final VoidCallback onRefresh;
  final ValueChanged<ConfigDocumentData> onEditDocument;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    ConfigDocumentData? globalDocument;
    ConfigDocumentData? projectDocument;
    for (final document in documents) {
      if (document.id == 'global') {
        globalDocument = document;
      } else if (document.id == 'workspace') {
        projectDocument = document;
      }
    }

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '配置文件',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton.icon(
                onPressed: refreshing ? null : onRefresh,
                icon: refreshing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(refreshing ? '刷新中...' : '刷新'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '先确认当前有哪些配置文件，再选择要查看的项目配置。',
            style: TextStyle(color: colors.textMuted, height: 1.45),
          ),
          if (globalDocument != null) ...[
            const SizedBox(height: 18),
            _GlobalDocumentBar(
              document: globalDocument,
              onEdit: () => onEditDocument(globalDocument!),
            ),
            if (projectOptions.isNotEmpty || projectDocument != null) ...[
              const SizedBox(height: 18),
              Divider(
                height: 1,
                thickness: 1,
                color: colors.border.withValues(alpha: 0.9),
              ),
            ],
          ],
          if (projectOptions.isNotEmpty) ...[
            const SizedBox(height: 18),
            _ProjectSelector(
              projectOptions: projectOptions,
              selectedProject: selectedProject,
              onSelectProject: onSelectProject,
            ),
          ],
          if (projectDocument != null) ...[
            if (projectOptions.isNotEmpty) ...[
              const SizedBox(height: 18),
              Divider(
                height: 1,
                thickness: 1,
                color: colors.border.withValues(alpha: 0.9),
              ),
            ],
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: _DocumentCard(
                document: projectDocument,
                onEdit: () => onEditDocument(projectDocument!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GlobalDocumentBar extends StatelessWidget {
  const _GlobalDocumentBar({required this.document, required this.onEdit});

  final ConfigDocumentData document;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '全局默认配置',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '这里定义项目默认继承的基线版本和基础设置。',
                style: TextStyle(color: colors.textMuted, height: 1.45),
              ),
              const SizedBox(height: 12),
              _DocumentPathLine(document: document),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onEdit,
            icon: Icon(
              document.exists ? Icons.edit_note_rounded : Icons.add_rounded,
            ),
            label: Text(document.exists ? '编辑全局' : '创建全局'),
          ),
        ),
      ],
    );
  }
}

class _ProjectSelector extends StatelessWidget {
  const _ProjectSelector({
    required this.projectOptions,
    required this.selectedProject,
    required this.onSelectProject,
  });

  final List<ProjectRecord> projectOptions;
  final ProjectRecord? selectedProject;
  final ValueChanged<String?> onSelectProject;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final dropdownValue = selectedProject?.path;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '当前配置项目',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 360,
          child: DropdownButtonFormField<String>(
            initialValue: dropdownValue,
            isExpanded: true,
            decoration: const InputDecoration(
              hintText: '选择要查看的项目配置',
              isDense: true,
            ),
            items: [
              for (final project in projectOptions)
                DropdownMenuItem<String>(
                  value: project.path,
                  child: Text(project.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onSelectProject,
          ),
        ),
        if (selectedProject != null) ...[
          const SizedBox(height: 6),
          Text(
            selectedProject!.path,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ],
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.document, required this.onEdit});

  final ConfigDocumentData document;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!document.exists) ...[
          const StatusBadge(label: '待创建', level: HealthLevel.info),
          const SizedBox(height: 12),
        ],
        Text(document.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          document.description,
          style: TextStyle(color: colors.textMuted, height: 1.5),
        ),
        const SizedBox(height: 12),
        _DocumentPathLine(document: document),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onEdit,
            icon: Icon(
              document.exists ? Icons.edit_note_rounded : Icons.add_rounded,
            ),
            label: Text(
              document.id == 'global'
                  ? (document.exists ? '编辑全局' : '创建全局')
                  : (document.exists ? '编辑项目配置' : '创建项目配置'),
            ),
          ),
        ),
      ],
    );
  }
}

class _DocumentPathLine extends StatelessWidget {
  const _DocumentPathLine({required this.document});

  final ConfigDocumentData document;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.description_outlined, size: 16, color: colors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            document.path,
            style: const TextStyle(
              fontFamily: 'FiraCode',
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _RuntimeSettingsPanel extends StatelessWidget {
  const _RuntimeSettingsPanel({required this.data, required this.onEdit});

  final ConfigRuntimeSettingsData data;
  final VoidCallback onEdit;

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
                    Text(
                      '运行时设置',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '常用 mise settings 写入 ${data.document.fileName}。',
                      style: TextStyle(color: colors.textMuted, height: 1.45),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('调整设置'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 920 ? 3 : 2;
              const spacing = 12.0;
              final width =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final setting in data.settings)
                    SizedBox(
                      width: width,
                      child: _RuntimeSettingTile(setting: setting),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RuntimeSettingTile extends StatelessWidget {
  const _RuntimeSettingTile({required this.setting});

  final ConfigRuntimeSetting setting;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final value = setting.isSet ? setting.value : '默认 ${setting.defaultValue}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.panelMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            setting.label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: setting.isSet ? colors.accent : colors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            setting.detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProxySettingsPanel extends StatelessWidget {
  const _ProxySettingsPanel({required this.data, required this.onEdit});

  final ConfigProxySettingsData data;
  final VoidCallback onEdit;

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
                    Text('网络代理', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      '写入 ${data.document.fileName} 的 [env]，GUI 发起的 mise 命令也会读取这些代理变量。',
                      style: TextStyle(color: colors.textMuted, height: 1.45),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.public_rounded),
                label: Text(data.hasProxy ? '调整代理' : '设置代理'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 920 ? 4 : 2;
              const spacing = 12.0;
              final width =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final setting in data.settings)
                    SizedBox(
                      width: width,
                      child: _ProxySettingTile(setting: setting),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProxySettingTile extends StatelessWidget {
  const _ProxySettingTile({required this.setting});

  final ConfigProxySetting setting;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final value = setting.isSet ? setting.value : '未设置';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.panelMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            setting.label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: setting.isSet ? colors.warning : colors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            setting.key,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigSection extends StatelessWidget {
  const _ConfigSection({
    required this.section,
    this.onEditProxy,
    this.onEditJavaAliases,
  });

  final ConfigSectionData section;
  final VoidCallback? onEditProxy;
  final VoidCallback? onEditJavaAliases;

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
                    Text(
                      section.title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      section.description,
                      style: TextStyle(color: colors.textMuted, height: 1.55),
                    ),
                  ],
                ),
              ),
              if (onEditJavaAliases != null) ...[
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: onEditJavaAliases,
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('配置别名'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _ConfigItemGroup(section: section, onEditProxy: onEditProxy),
          const SizedBox(height: 14),
          _ConfigRawPanel(content: section.rawSnippet),
        ],
      ),
    );
  }
}

class _ConfigItemGroup extends StatelessWidget {
  const _ConfigItemGroup({required this.section, this.onEditProxy});

  final ConfigSectionData section;
  final VoidCallback? onEditProxy;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < section.items.length; index++) ...[
          _ConfigItemRow(
            item: section.items[index],
            onEditProxy: section.items[index].label == '代理环境变量'
                ? onEditProxy
                : null,
          ),
          if (index != section.items.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Divider(
                height: 1,
                thickness: 1,
                color: colors.border.withValues(alpha: 0.9),
              ),
            ),
        ],
      ],
    );
  }
}

class _ConfigItemRow extends StatelessWidget {
  const _ConfigItemRow({required this.item, this.onEditProxy});

  final ConfigItem item;
  final VoidCallback? onEditProxy;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              _ConfigItemDetail(item: item),
            ],
          ),
        ),
        const SizedBox(width: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item.value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: _statusColor(context, item.level),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (onEditProxy != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onEditProxy,
                  icon: const Icon(Icons.public_rounded, size: 18),
                  label: Text(item.value == '未配置' ? '设置代理' : '调整代理'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Color _statusColor(BuildContext context, HealthLevel level) {
    final colors = AppTheme.colorsOf(context);
    return switch (level) {
      HealthLevel.healthy => colors.accent,
      HealthLevel.info => colors.info,
      HealthLevel.warning => colors.warning,
      HealthLevel.critical => colors.danger,
    };
  }
}

class _ConfigItemDetail extends StatelessWidget {
  const _ConfigItemDetail({required this.item});

  final ConfigItem item;

  @override
  Widget build(BuildContext context) {
    if (item.label == '已声明工具' && item.detail.contains(' = ')) {
      return _ToolDeclarationsPreview(content: item.detail);
    }

    final colors = AppTheme.colorsOf(context);
    return Text(
      item.detail,
      style: TextStyle(color: colors.textMuted, height: 1.5),
    );
  }
}

class _ToolDeclarationsPreview extends StatelessWidget {
  const _ToolDeclarationsPreview({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final entries = _parseToolDeclarationLines(content);

    if (entries.isEmpty) {
      return Text(
        content,
        style: TextStyle(color: colors.textMuted, height: 1.5),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1060
            ? 3
            : constraints.maxWidth >= 680
            ? 2
            : 1;
        const spacing = 12.0;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final entry in entries)
              SizedBox(
                width: itemWidth,
                child: _ToolDeclarationCard(entry: entry),
              ),
          ],
        );
      },
    );
  }
}

class _ToolDeclarationCard extends StatelessWidget {
  const _ToolDeclarationCard({required this.entry});

  final _ToolDeclarationEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final complex = _isComplexToolValue(entry.value);
    final accent = _toolAccentColor(context, entry.tool);

    return Semantics(
      label: '${entry.tool} 已声明版本 ${entry.value}',
      child: Container(
        constraints: const BoxConstraints(minHeight: 104),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.panelRaised.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border.withValues(alpha: 0.74)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: accent.withValues(alpha: 0.22)),
                  ),
                  child: Icon(_toolIcon(entry.tool), size: 18, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.tool,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'FiraCode',
                      fontSize: 14,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: complex
                        ? colors.info.withValues(alpha: 0.1)
                        : colors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    complex ? '自定义' : '版本',
                    style: TextStyle(
                      color: complex ? colors.info : colors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (complex) ...[
              Text(
                '自定义下载源配置',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              entry.value,
              maxLines: complex ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: complex ? colors.textMuted : colors.textPrimary,
                fontFamily: 'FiraCode',
                fontSize: complex ? 11 : 22,
                fontWeight: complex ? FontWeight.w500 : FontWeight.w800,
                height: complex ? 1.4 : 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolDeclarationEntry {
  const _ToolDeclarationEntry({required this.tool, required this.value});

  final String tool;
  final String value;
}

List<_ToolDeclarationEntry> _parseToolDeclarationLines(String content) {
  final entries = <_ToolDeclarationEntry>[];
  for (final line in content.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final separatorIndex = trimmed.indexOf(' = ');
    if (separatorIndex == -1) {
      continue;
    }
    final tool = trimmed.substring(0, separatorIndex).trim();
    final value = trimmed.substring(separatorIndex + 3).trim();
    if (tool.isEmpty || value.isEmpty) {
      continue;
    }
    entries.add(_ToolDeclarationEntry(tool: tool, value: value));
  }
  return entries;
}

bool _isComplexToolValue(String value) {
  return value.length > 48 || value.contains('{') || value.contains('://');
}

IconData _toolIcon(String tool) {
  return switch (tool.toLowerCase()) {
    'flutter' => Icons.flutter_dash_rounded,
    'java' => Icons.coffee_rounded,
    'node' || 'npm' || 'pnpm' || 'bun' => Icons.code_rounded,
    'python' => Icons.terminal_rounded,
    'go' => Icons.bolt_rounded,
    'rust' => Icons.memory_rounded,
    'maven' => Icons.build_rounded,
    _ => Icons.handyman_rounded,
  };
}

Color _toolAccentColor(BuildContext context, String tool) {
  final colors = AppTheme.colorsOf(context);
  return switch (tool.toLowerCase()) {
    'flutter' => colors.info,
    'java' => colors.warning,
    'python' => colors.info,
    'rust' => colors.danger,
    _ => colors.accent,
  };
}

class _ConfigRawPanel extends StatelessWidget {
  const _ConfigRawPanel({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 12),
        title: const Text(
          '原始配置',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '展开查看这一组对应的 TOML 内容',
          style: TextStyle(color: colors.textMuted, fontSize: 12),
        ),
        children: [_CodePanel(title: 'TOML', content: content, height: 320)],
      ),
    );
  }
}

class _ProxySettingsEditorDialog extends ConsumerStatefulWidget {
  const _ProxySettingsEditorDialog({required this.data});

  final ConfigProxySettingsData data;

  @override
  ConsumerState<_ProxySettingsEditorDialog> createState() =>
      _ProxySettingsEditorDialogState();
}

class _ProxySettingsEditorDialogState
    extends ConsumerState<_ProxySettingsEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final List<_ProxySettingDraft> _drafts;
  ConfigSavePreview? _preview;
  bool _loadingPreview = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _drafts = [
      for (final setting in widget.data.settings)
        _ProxySettingDraft(setting: setting),
    ];
    for (final draft in _drafts) {
      draft.controller.addListener(_handleChanged);
    }
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.controller.removeListener(_handleChanged);
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final size = MediaQuery.sizeOf(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      backgroundColor: Colors.transparent,
      child: Container(
        width: size.width * 0.72,
        constraints: BoxConstraints(
          maxWidth: 880,
          maxHeight: size.height * 0.82,
        ),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.borderStrong),
          boxShadow: [
            BoxShadow(
              blurRadius: 28,
              color: colors.backgroundDeep.withValues(alpha: 0.22),
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _preview == null ? '设置网络代理' : '确认保存网络代理',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              widget.data.document.path,
              style: TextStyle(
                color: colors.textMuted,
                fontFamily: 'FiraCode',
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: _preview == null
                  ? _buildForm(colors)
                  : _CodePanel(
                      title: '差异预览',
                      content: _preview!.diffPreview,
                      expand: true,
                    ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.end,
              children: [
                if (_preview != null)
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() {
                              _preview = null;
                            });
                          },
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('返回编辑'),
                  ),
                OutlinedButton(
                  onPressed: _loadingPreview || _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                if (_preview == null)
                  FilledButton(
                    onPressed: _loadingPreview || !_hasChanges
                        ? null
                        : _generatePreview,
                    child: Text(_loadingPreview ? '预览中...' : '预览变更'),
                  ),
                if (_preview != null)
                  FilledButton(
                    onPressed: _saving ? null : _saveSettings,
                    child: Text(_saving ? '保存中...' : '保存代理'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(AppPalette colors) {
    return Form(
      key: _formKey,
      child: ListView.separated(
        itemCount: _drafts.length,
        separatorBuilder: (context, index) =>
            Divider(height: 24, color: colors.border.withValues(alpha: 0.9)),
        itemBuilder: (context, index) =>
            _ProxySettingField(draft: _drafts[index]),
      ),
    );
  }

  Future<void> _generatePreview() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _loadingPreview = true;
    });

    try {
      final preview = await ref
          .read(configRepositoryProvider)
          .previewProxySettingsSave(
            update: ConfigProxySettingsUpdate(
              document: widget.data.document,
              values: _collectValues(),
            ),
          );
      if (!mounted) {
        return;
      }
      if (!preview.hasChanges) {
        _showFeedback('没有变更，无需预览。');
        return;
      }
      setState(() {
        _preview = preview;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingPreview = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    final preview = _preview;
    if (preview == null || !preview.hasChanges || !mounted) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final stopwatch = Stopwatch()..start();
      await ref
          .read(configRepositoryProvider)
          .saveDocument(
            document: preview.document,
            nextContent: preview.nextContent,
          );
      stopwatch.stop();
      await ref
          .read(historyServiceProvider)
          .appendEntry(
            HistoryEntry(
              command: preview.commandPreview,
              timestamp: _formatNow(),
              detail: '已通过界面调整 mise 代理设置。',
              level: HealthLevel.info,
              status: HistoryStatus.success,
              exitCode: 0,
              durationMs: stopwatch.elapsedMilliseconds,
              stdout: preview.document.path,
              stdoutSnippet: preview.document.path,
            ),
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Map<String, String?> _collectValues() {
    return {
      for (final draft in _drafts)
        draft.setting.key: draft.controller.text.trim().isEmpty
            ? null
            : draft.controller.text.trim(),
    };
  }

  bool get _hasChanges {
    for (final draft in _drafts) {
      final original = draft.setting.isSet ? draft.setting.value : '';
      if (draft.controller.text.trim() != original) {
        return true;
      }
    }
    return false;
  }

  String _formatNow() {
    final now = DateTime.now();
    final hours = now.hour.toString().padLeft(2, '0');
    final minutes = now.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  void _showFeedback(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _handleChanged() {
    if (!mounted || _preview != null) {
      return;
    }
    setState(() {});
  }
}

class _ProxySettingDraft {
  _ProxySettingDraft({required this.setting})
    : controller = TextEditingController(text: setting.value);

  final ConfigProxySetting setting;
  final TextEditingController controller;

  void dispose() {
    controller.dispose();
  }
}

class _ProxySettingField extends StatelessWidget {
  const _ProxySettingField({required this.draft});

  final _ProxySettingDraft draft;

  static final RegExp _proxyUriPattern = RegExp(
    r'^[A-Za-z][A-Za-z0-9+.-]*://\S+$',
  );

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final setting = draft.setting;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                setting.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                setting.detail,
                style: TextStyle(color: colors.textMuted, height: 1.45),
              ),
              const SizedBox(height: 4),
              Text(
                setting.key,
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        SizedBox(
          width: 320,
          child: TextFormField(
            controller: draft.controller,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: setting.key,
              hintText: setting.placeholder,
              isDense: true,
            ),
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              if (trimmed.isEmpty) {
                return null;
              }
              if (trimmed.contains(RegExp(r'\s'))) {
                return '不能包含空白字符';
              }
              if (setting.requiresUri && !_proxyUriPattern.hasMatch(trimmed)) {
                return '需要包含协议，例如 ${setting.placeholder}';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }
}

class _RuntimeSettingsEditorDialog extends ConsumerStatefulWidget {
  const _RuntimeSettingsEditorDialog({required this.data});

  final ConfigRuntimeSettingsData data;

  @override
  ConsumerState<_RuntimeSettingsEditorDialog> createState() =>
      _RuntimeSettingsEditorDialogState();
}

class _RuntimeSettingsEditorDialogState
    extends ConsumerState<_RuntimeSettingsEditorDialog> {
  late final List<_RuntimeSettingDraft> _drafts;
  ConfigSavePreview? _preview;
  bool _loadingPreview = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _drafts = [
      for (final setting in widget.data.settings)
        _RuntimeSettingDraft(setting: setting),
    ];
    for (final draft in _drafts) {
      draft.controller.addListener(_handleChanged);
    }
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.controller.removeListener(_handleChanged);
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final size = MediaQuery.sizeOf(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      backgroundColor: Colors.transparent,
      child: Container(
        width: size.width * 0.72,
        constraints: BoxConstraints(
          maxWidth: 880,
          maxHeight: size.height * 0.82,
        ),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.borderStrong),
          boxShadow: [
            BoxShadow(
              blurRadius: 28,
              color: colors.backgroundDeep.withValues(alpha: 0.22),
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _preview == null ? '调整运行时设置' : '确认保存运行时设置',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              widget.data.document.path,
              style: TextStyle(
                color: colors.textMuted,
                fontFamily: 'FiraCode',
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: _preview == null
                  ? _buildForm(colors)
                  : _CodePanel(
                      title: '差异预览',
                      content: _preview!.diffPreview,
                      expand: true,
                    ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.end,
              children: [
                if (_preview != null)
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() {
                              _preview = null;
                            });
                          },
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('返回编辑'),
                  ),
                OutlinedButton(
                  onPressed: _loadingPreview || _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                if (_preview == null)
                  FilledButton(
                    onPressed: _loadingPreview || !_hasChanges
                        ? null
                        : _generatePreview,
                    child: Text(_loadingPreview ? '预览中...' : '预览变更'),
                  ),
                if (_preview != null)
                  FilledButton(
                    onPressed: _saving ? null : _saveSettings,
                    child: Text(_saving ? '保存中...' : '保存设置'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(AppPalette colors) {
    return ListView.separated(
      itemCount: _drafts.length,
      separatorBuilder: (context, index) =>
          Divider(height: 24, color: colors.border.withValues(alpha: 0.9)),
      itemBuilder: (context, index) {
        final draft = _drafts[index];
        return _RuntimeSettingField(
          draft: draft,
          onBooleanChanged: (value) {
            setState(() {
              draft.booleanValue = value ?? '';
              _preview = null;
            });
          },
        );
      },
    );
  }

  Future<void> _generatePreview() async {
    final values = _collectValues();
    if (values == null) {
      return;
    }

    setState(() {
      _loadingPreview = true;
    });

    try {
      final preview = await ref
          .read(configRepositoryProvider)
          .previewRuntimeSettingsSave(
            update: ConfigRuntimeSettingsUpdate(
              document: widget.data.document,
              values: values,
            ),
          );
      if (!mounted) {
        return;
      }
      if (!preview.hasChanges) {
        _showFeedback('没有变更，无需预览。');
        return;
      }
      setState(() {
        _preview = preview;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingPreview = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    final preview = _preview;
    if (preview == null || !preview.hasChanges || !mounted) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final stopwatch = Stopwatch()..start();
      await ref
          .read(configRepositoryProvider)
          .saveDocument(
            document: preview.document,
            nextContent: preview.nextContent,
          );
      stopwatch.stop();
      await ref
          .read(historyServiceProvider)
          .appendEntry(
            HistoryEntry(
              command: preview.commandPreview,
              timestamp: _formatNow(),
              detail: '已通过界面调整 mise 运行时设置。',
              level: HealthLevel.info,
              status: HistoryStatus.success,
              exitCode: 0,
              durationMs: stopwatch.elapsedMilliseconds,
              stdout: preview.document.path,
              stdoutSnippet: preview.document.path,
            ),
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Map<String, String?>? _collectValues() {
    final values = <String, String?>{};
    for (final draft in _drafts) {
      final setting = draft.setting;
      if (setting.type == ConfigRuntimeSettingType.boolean) {
        values[setting.key] = draft.booleanValue.isEmpty
            ? null
            : draft.booleanValue;
        continue;
      }

      final value = draft.controller.text.trim();
      if (value.isEmpty) {
        values[setting.key] = null;
        continue;
      }
      if (setting.type == ConfigRuntimeSettingType.integer &&
          int.tryParse(value) == null) {
        _showFeedback('${setting.label} 需要填写整数。');
        return null;
      }
      if (setting.type == ConfigRuntimeSettingType.integer &&
          int.parse(value) < 0) {
        _showFeedback('${setting.label} 不能小于 0。');
        return null;
      }
      if (setting.type == ConfigRuntimeSettingType.string &&
          value.contains(RegExp(r'\s'))) {
        _showFeedback('${setting.label} 不能包含空白字符。');
        return null;
      }
      values[setting.key] = value;
    }
    return values;
  }

  bool get _hasChanges {
    for (final draft in _drafts) {
      if (draft.setting.type == ConfigRuntimeSettingType.boolean) {
        final original = draft.setting.isSet ? draft.setting.value : '';
        if (draft.booleanValue != original) {
          return true;
        }
        continue;
      }
      final original = draft.setting.isSet ? draft.setting.value : '';
      if (draft.controller.text.trim() != original) {
        return true;
      }
    }
    return false;
  }

  String _formatNow() {
    final now = DateTime.now();
    final hours = now.hour.toString().padLeft(2, '0');
    final minutes = now.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  void _showFeedback(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _handleChanged() {
    if (!mounted || _preview != null) {
      return;
    }
    setState(() {});
  }
}

class _RuntimeSettingDraft {
  _RuntimeSettingDraft({required this.setting})
    : controller = TextEditingController(
        text: setting.type == ConfigRuntimeSettingType.boolean
            ? ''
            : setting.value,
      ),
      booleanValue =
          setting.type == ConfigRuntimeSettingType.boolean && setting.isSet
          ? setting.value
          : '';

  final ConfigRuntimeSetting setting;
  final TextEditingController controller;
  String booleanValue;

  void dispose() {
    controller.dispose();
  }
}

class _RuntimeSettingField extends StatelessWidget {
  const _RuntimeSettingField({
    required this.draft,
    required this.onBooleanChanged,
  });

  final _RuntimeSettingDraft draft;
  final ValueChanged<String?> onBooleanChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final setting = draft.setting;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                setting.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                setting.detail,
                style: TextStyle(color: colors.textMuted, height: 1.45),
              ),
              const SizedBox(height: 4),
              Text(
                '默认 ${setting.defaultValue}',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        SizedBox(width: 240, child: _buildInput(context, setting)),
      ],
    );
  }

  Widget _buildInput(BuildContext context, ConfigRuntimeSetting setting) {
    if (setting.type == ConfigRuntimeSettingType.boolean) {
      return DropdownButtonFormField<String>(
        initialValue: draft.booleanValue,
        isExpanded: true,
        decoration: InputDecoration(labelText: setting.key, isDense: true),
        items: const [
          DropdownMenuItem<String>(value: '', child: Text('未设置')),
          DropdownMenuItem<String>(value: 'true', child: Text('true')),
          DropdownMenuItem<String>(value: 'false', child: Text('false')),
        ],
        onChanged: onBooleanChanged,
      );
    }

    return TextField(
      controller: draft.controller,
      keyboardType: setting.type == ConfigRuntimeSettingType.integer
          ? TextInputType.number
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: setting.key,
        hintText: setting.isSet ? null : setting.defaultValue,
        isDense: true,
      ),
    );
  }
}

class _ConfigDocumentEditorDialog extends ConsumerStatefulWidget {
  const _ConfigDocumentEditorDialog({required this.document});

  final ConfigDocumentData document;

  @override
  ConsumerState<_ConfigDocumentEditorDialog> createState() =>
      _ConfigDocumentEditorDialogState();
}

class _ConfigDocumentEditorDialogState
    extends ConsumerState<_ConfigDocumentEditorDialog> {
  late final TextEditingController _controller;
  ConfigSavePreview? _preview;
  bool _loadingPreview = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.document.content);
    _controller.addListener(_handleContentChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleContentChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final size = MediaQuery.sizeOf(context);
    final hasPendingChanges = _hasPendingChanges;

    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      backgroundColor: Colors.transparent,
      child: Container(
        width: size.width * 0.82,
        height: size.height * 0.82,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: colors.borderStrong),
          boxShadow: [
            BoxShadow(
              blurRadius: 32,
              color: colors.backgroundDeep.withValues(alpha: 0.24),
              offset: const Offset(0, 18),
            ),
          ],
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
                        _preview == null
                            ? '编辑 ${widget.document.title}'
                            : '确认保存 ${widget.document.title}',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      if (_preview == null) ...[
                        const SizedBox(height: 10),
                        Text(
                          '正在编辑 ${widget.document.path}',
                          style: TextStyle(
                            color: colors.textMuted,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.backgroundSoft,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.border),
              ),
              child: SelectableText(
                widget.document.path,
                style: const TextStyle(
                  fontFamily: 'FiraCode',
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: _preview == null
                  ? _buildEditor(colors)
                  : _buildPreview(colors, _preview!),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.end,
              children: [
                if (_preview != null)
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() {
                              _preview = null;
                            });
                          },
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('返回编辑'),
                  ),
                OutlinedButton(
                  onPressed: _loadingPreview || _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                if (_preview == null)
                  if (hasPendingChanges)
                    FilledButton(
                      onPressed: _loadingPreview ? null : _generatePreview,
                      child: Text(_loadingPreview ? '预览中...' : '预览变更'),
                    ),
                if (_preview != null)
                  FilledButton(
                    onPressed: _saving ? null : _saveDocument,
                    child: Text(_saving ? '保存中...' : '保存更改'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(AppPalette colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.border),
      ),
      child: TextField(
        controller: _controller,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(
          fontFamily: 'FiraCode',
          fontSize: 13,
          height: 1.6,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(18),
          hintText: '# 在这里编辑 TOML',
        ),
      ),
    );
  }

  Widget _buildPreview(AppPalette colors, ConfigSavePreview preview) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _CodePanel(
            title: '差异预览',
            content: preview.diffPreview,
            expand: true,
          ),
        ),
      ],
    );
  }

  Future<void> _generatePreview() async {
    setState(() {
      _loadingPreview = true;
    });

    try {
      final preview = await ref
          .read(configRepositoryProvider)
          .previewSave(
            document: widget.document,
            nextContent: _controller.text,
          );
      if (!mounted) {
        return;
      }
      if (!preview.hasChanges) {
        _showFeedback('没有变更，无需预览。');
        return;
      }
      setState(() {
        _preview = preview;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingPreview = false;
        });
      }
    }
  }

  Future<void> _saveDocument() async {
    final preview = _preview;
    if (preview == null || !preview.hasChanges) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final stopwatch = Stopwatch()..start();
      await ref
          .read(configRepositoryProvider)
          .saveDocument(
            document: widget.document,
            nextContent: preview.nextContent,
          );
      stopwatch.stop();
      await ref
          .read(historyServiceProvider)
          .appendEntry(
            HistoryEntry(
              command: preview.commandPreview,
              timestamp: _formatNow(),
              detail: preview.createsFile
                  ? '已通过界面创建并写入 ${widget.document.fileName}。'
                  : '已通过界面直接编辑并写回 ${widget.document.fileName}。',
              level: preview.createsFile
                  ? HealthLevel.info
                  : HealthLevel.warning,
              status: HistoryStatus.success,
              exitCode: 0,
              durationMs: stopwatch.elapsedMilliseconds,
              stdout: widget.document.path,
              stdoutSnippet: widget.document.path,
            ),
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String _formatNow() {
    final now = DateTime.now();
    final hours = now.hour.toString().padLeft(2, '0');
    final minutes = now.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  void _showFeedback(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _hasPendingChanges =>
      _normalizeEditorContent(_controller.text) !=
      _normalizeEditorContent(widget.document.content);

  String _normalizeEditorContent(String value) {
    final normalized = value.replaceAll('\r\n', '\n');
    if (normalized.trim().isEmpty) {
      return '';
    }
    return normalized.endsWith('\n') ? normalized : '$normalized\n';
  }

  void _handleContentChanged() {
    if (!mounted || _preview != null) {
      return;
    }
    setState(() {});
  }
}

class _JavaAliasesEditorDialog extends ConsumerStatefulWidget {
  const _JavaAliasesEditorDialog({required this.document});

  final ConfigDocumentData document;

  @override
  ConsumerState<_JavaAliasesEditorDialog> createState() =>
      _JavaAliasesEditorDialogState();
}

class _JavaAliasesEditorDialogState
    extends ConsumerState<_JavaAliasesEditorDialog> {
  late bool _enabled;
  late final TextEditingController _controller;
  ConfigSavePreview? _preview;
  bool _loadingPreview = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final section = _extractTomlSection(
      widget.document.content,
      'tool_alias.java.versions',
    );
    final aliases = _parseJavaAliasAssignments(section ?? '');
    _enabled = section != null;
    _controller = TextEditingController(
      text: aliases.isEmpty
          ? _formatJavaAliasAssignments(javaAliasDefaults)
          : _formatJavaAliasAssignments(aliases),
    );
    _controller.addListener(_handleChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final size = MediaQuery.sizeOf(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      backgroundColor: Colors.transparent,
      child: Container(
        width: size.width * 0.72,
        constraints: BoxConstraints(
          maxWidth: 880,
          maxHeight: size.height * 0.82,
        ),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.borderStrong),
          boxShadow: [
            BoxShadow(
              blurRadius: 28,
              color: colors.backgroundDeep.withValues(alpha: 0.22),
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _preview == null ? '配置 Java 别名' : '确认保存 Java 别名',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              widget.document.path,
              style: TextStyle(
                color: colors.textMuted,
                fontFamily: 'FiraCode',
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: _preview == null
                  ? _buildForm(colors)
                  : _CodePanel(
                      title: '差异预览',
                      content: _preview!.diffPreview,
                      expand: true,
                    ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.end,
              children: [
                if (_preview != null)
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() {
                              _preview = null;
                            });
                          },
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('返回编辑'),
                  ),
                OutlinedButton(
                  onPressed: _loadingPreview || _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                if (_preview == null)
                  FilledButton(
                    onPressed: _loadingPreview || !_hasChanges
                        ? null
                        : _generatePreview,
                    child: Text(_loadingPreview ? '预览中...' : '预览变更'),
                  ),
                if (_preview != null)
                  FilledButton(
                    onPressed: _saving ? null : _saveAliases,
                    child: Text(_saving ? '保存中...' : '保存别名'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(AppPalette colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          value: _enabled,
          contentPadding: EdgeInsets.zero,
          title: const Text('启用 Java 默认别名'),
          subtitle: Text(
            '关闭时不会写入 [tool_alias.java.versions]；打开后可以编辑具体映射。',
            style: TextStyle(color: colors.textMuted, height: 1.4),
          ),
          onChanged: (value) {
            setState(() {
              _enabled = value;
              _preview = null;
              if (value && _controller.text.trim().isEmpty) {
                _controller.text = _formatJavaAliasAssignments(
                  javaAliasDefaults,
                );
              }
            });
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                '每行一个映射，例如 21 = "corretto-21"。',
                style: TextStyle(color: colors.textMuted, height: 1.45),
              ),
            ),
            OutlinedButton.icon(
              onPressed: !_enabled
                  ? null
                  : () {
                      setState(() {
                        _controller.text = _formatJavaAliasAssignments(
                          javaAliasDefaults,
                        );
                        _preview = null;
                      });
                    },
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('重置默认值'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Opacity(
            opacity: _enabled ? 1 : 0.55,
            child: Container(
              decoration: BoxDecoration(
                color: colors.backgroundSoft,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.border),
              ),
              child: TextField(
                enabled: _enabled,
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(
                  fontFamily: 'FiraCode',
                  fontSize: 13,
                  height: 1.55,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                  hintText: '21 = "corretto-21"',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _generatePreview() async {
    final aliases = _collectAliases();
    if (aliases == null) {
      return;
    }

    setState(() {
      _loadingPreview = true;
    });

    try {
      final nextContent = buildJavaAliasesConfigContent(
        currentContent: widget.document.content,
        enabled: _enabled,
        aliases: aliases,
      );
      final preview = await ref
          .read(configRepositoryProvider)
          .previewSave(document: widget.document, nextContent: nextContent);
      if (!mounted) {
        return;
      }
      if (!preview.hasChanges) {
        _showFeedback('没有变更，无需预览。');
        return;
      }
      setState(() {
        _preview = preview;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingPreview = false;
        });
      }
    }
  }

  Future<void> _saveAliases() async {
    final preview = _preview;
    if (preview == null || !preview.hasChanges || !mounted) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final stopwatch = Stopwatch()..start();
      await ref
          .read(configRepositoryProvider)
          .saveDocument(
            document: preview.document,
            nextContent: preview.nextContent,
          );
      stopwatch.stop();
      await ref
          .read(historyServiceProvider)
          .appendEntry(
            HistoryEntry(
              command: preview.commandPreview,
              timestamp: _formatNow(),
              detail: _enabled ? '已启用并写回 Java 别名。' : '已关闭 Java 别名配置。',
              level: HealthLevel.info,
              status: HistoryStatus.success,
              exitCode: 0,
              durationMs: stopwatch.elapsedMilliseconds,
              stdout: preview.document.path,
              stdoutSnippet: preview.document.path,
            ),
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Map<String, String>? _collectAliases() {
    if (!_enabled) {
      return const {};
    }

    final aliases = _parseJavaAliasAssignments(_controller.text);
    if (aliases.isEmpty) {
      _showFeedback('启用后至少需要保留一个 Java 别名。');
      return null;
    }

    return aliases;
  }

  bool get _hasChanges {
    final aliases = _enabled
        ? _parseJavaAliasAssignments(_controller.text)
        : const <String, String>{};
    final nextContent = buildJavaAliasesConfigContent(
      currentContent: widget.document.content,
      enabled: _enabled,
      aliases: aliases,
    );
    return _normalizeEditorContent(nextContent) !=
        _normalizeEditorContent(widget.document.content);
  }

  String _formatNow() {
    final now = DateTime.now();
    final hours = now.hour.toString().padLeft(2, '0');
    final minutes = now.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  void _showFeedback(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _handleChanged() {
    if (!mounted || _preview != null) {
      return;
    }
    setState(() {});
  }
}

class _CodePanel extends StatelessWidget {
  const _CodePanel({
    required this.title,
    required this.content,
    this.height,
    this.expand = false,
  });

  final String title;
  final String content;
  final double? height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    final panel = Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.backgroundSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          content,
          style: const TextStyle(
            fontFamily: 'FiraCode',
            fontSize: 13,
            height: 1.6,
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'FiraCode',
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        if (expand) Expanded(child: panel) else panel,
      ],
    );
  }
}

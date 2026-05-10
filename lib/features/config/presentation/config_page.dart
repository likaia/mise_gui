import 'dart:async';

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
      builder: (workspace) => AppPageScaffold(
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
            const SizedBox(height: 18),
            for (final section in workspace.sections)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: _ConfigSection(section: section),
              ),
          ],
        ),
      ),
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

class _ConfigSection extends StatelessWidget {
  const _ConfigSection({required this.section});

  final ConfigSectionData section;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
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
          const SizedBox(height: 16),
          _ConfigItemGroup(section: section),
          const SizedBox(height: 14),
          _ConfigRawPanel(content: section.rawSnippet),
        ],
      ),
    );
  }
}

class _ConfigItemGroup extends StatelessWidget {
  const _ConfigItemGroup({required this.section});

  final ConfigSectionData section;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < section.items.length; index++) ...[
          _ConfigItemRow(item: section.items[index]),
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
  const _ConfigItemRow({required this.item});

  final ConfigItem item;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

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
              Text(
                item.detail,
                style: TextStyle(color: colors.textMuted, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            item.value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: _statusColor(context, item.level),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
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

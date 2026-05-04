import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mise_gui/app/bootstrap/dependencies.dart';
import 'package:mise_gui/app/router/app_router.dart';
import 'package:mise_gui/app/theme/app_theme.dart';
import 'package:mise_gui/models/app_models.dart';

class MiseGuiApp extends ConsumerStatefulWidget {
  const MiseGuiApp({super.key});

  @override
  ConsumerState<MiseGuiApp> createState() => _MiseGuiAppState();
}

class _MiseGuiAppState extends ConsumerState<MiseGuiApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncThemeWithSystem();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    _syncThemeWithSystem();
    super.didChangePlatformBrightness();
  }

  void _syncThemeWithSystem() {
    ref.read(systemThemeModeProvider.notifier).state = resolveSystemThemeMode();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'mise_gui',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) =>
          _AppUpdateGate(child: child ?? const SizedBox.shrink()),
    );
  }
}

class _AppUpdateGate extends ConsumerStatefulWidget {
  const _AppUpdateGate({required this.child});

  final Widget child;

  @override
  ConsumerState<_AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends ConsumerState<_AppUpdateGate> {
  var _checkedForUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForUpdate());
    });
  }

  Future<void> _checkForUpdate() async {
    if (_checkedForUpdate || !mounted) {
      return;
    }

    final dialogContext = ref.read(rootNavigatorKeyProvider).currentContext;
    if (dialogContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_checkForUpdate());
        }
      });
      return;
    }

    _checkedForUpdate = true;

    try {
      final versionInfo = await ref.read(appVersionInfoProvider.future);
      final updateInfo = await ref
          .read(appUpdateServiceProvider)
          .checkForUpdate(currentVersion: versionInfo.version);
      if (!mounted || updateInfo == null) {
        return;
      }

      await showDialog<void>(
        context: dialogContext,
        barrierDismissible: true,
        builder: (dialogContext) => _AppUpdateDialog(updateInfo: updateInfo),
      );
    } catch (_) {
      // Best-effort only. Startup should not fail when update checks fail.
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _AppUpdateDialog extends ConsumerWidget {
  const _AppUpdateDialog({required this.updateInfo});

  final AppUpdateInfo updateInfo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppTheme.colorsOf(context);
    final noteLines = _releaseNoteLines(updateInfo.releaseNotes);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colors.panelRaised.withValues(alpha: 0.98),
              colors.panel.withValues(alpha: 0.98),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: colors.borderStrong.withValues(alpha: 0.7)),
          boxShadow: [
            BoxShadow(
              color: colors.backgroundDeep.withValues(alpha: 0.35),
              blurRadius: 42,
              offset: const Offset(0, 24),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: -36,
              right: -20,
              child: IgnorePointer(
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        colors.accent.withValues(alpha: 0.18),
                        colors.accent.withValues(alpha: 0.02),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: colors.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: colors.accent.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Icon(
                          Icons.system_update_alt_rounded,
                          color: colors.accent,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '发现新版本',
                              style: theme.textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '当前版本 ${updateInfo.currentVersion}，建议升级到 ${updateInfo.latestVersion}。',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.textMuted,
                                height: 1.55,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      _UpdateTagBadge(tagName: updateInfo.tagName),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _VersionTransitionPanel(updateInfo: updateInfo),
                  const SizedBox(height: 22),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    decoration: BoxDecoration(
                      color: colors.backgroundSoft.withValues(alpha: 0.56),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: colors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('更新内容', style: theme.textTheme.titleLarge),
                            const Spacer(),
                            Text(
                              'GitHub Release',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.textMuted,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final line in noteLines) ...[
                                  _ReleaseNoteRow(text: line),
                                  if (line != noteLines.last)
                                    const SizedBox(height: 12),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('稍后再说'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: () async {
                          final opened = await ref
                              .read(browserLauncherServiceProvider)
                              .openUrl(updateInfo.releaseUrl);
                          if (!context.mounted) {
                            return;
                          }
                          if (!opened) {
                            await Clipboard.setData(
                              ClipboardData(text: updateInfo.releaseUrl),
                            );
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('打开浏览器失败，更新链接已复制到剪贴板。'),
                              ),
                            );
                          }
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('前往GitHub下载'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateTagBadge extends StatelessWidget {
  const _UpdateTagBadge({required this.tagName});

  final String tagName;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.panel.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.borderStrong.withValues(alpha: 0.45)),
      ),
      child: Text(
        tagName,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colors.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _VersionTransitionPanel extends StatelessWidget {
  const _VersionTransitionPanel({required this.updateInfo});

  final AppUpdateInfo updateInfo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: colors.heroGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.borderStrong.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _VersionValueCard(
              label: '当前版本',
              value: updateInfo.currentVersion,
              accent: colors.info,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colors.panelRaised.withValues(alpha: 0.72),
                shape: BoxShape.circle,
                border: Border.all(color: colors.borderStrong),
              ),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: colors.textPrimary,
                size: 24,
              ),
            ),
          ),
          Expanded(
            child: _VersionValueCard(
              label: '最新版本',
              value: updateInfo.latestVersion,
              accent: colors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionValueCard extends StatelessWidget {
  const _VersionValueCard({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppTheme.colorsOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: colors.panel.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReleaseNoteRow extends StatelessWidget {
  const _ReleaseNoteRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 7),
          decoration: BoxDecoration(
            color: colors.accent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SelectableText(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ),
      ],
    );
  }
}

List<String> _releaseNoteLines(String raw) {
  final normalized = raw.replaceAll('\r\n', '\n').trim();
  if (normalized.isEmpty) {
    return const <String>['本次更新包含若干优化与修复，可前往 GitHub 查看完整说明。'];
  }

  final lines = normalized
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map((line) => line.replaceFirst(RegExp(r'^[-*]\s*'), ''))
      .toList(growable: false);

  return lines.isEmpty
      ? const <String>['本次更新包含若干优化与修复，可前往 GitHub 查看完整说明。']
      : lines;
}

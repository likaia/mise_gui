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
  var _checkedForUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncThemeWithSystem();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForUpdate());
    });
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

  Future<void> _checkForUpdate() async {
    if (_checkedForUpdate || !mounted) {
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
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => _AppUpdateDialog(updateInfo: updateInfo),
      );
    } catch (_) {
      // Best-effort only. Startup should not fail when update checks fail.
    }
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
    );
  }
}

class _AppUpdateDialog extends ConsumerWidget {
  const _AppUpdateDialog({required this.updateInfo});

  final AppUpdateInfo updateInfo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('发现新版本'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _VersionPill(
                  label: '当前版本',
                  value: updateInfo.currentVersion,
                  color: colorScheme.secondary,
                ),
                _VersionPill(
                  label: '最新版本',
                  value: updateInfo.latestVersion,
                  color: colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Tag: ${updateInfo.tagName}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text('更新内容', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 260),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  updateInfo.releaseNotes,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('稍后再说'),
        ),
        FilledButton(
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
                const SnackBar(content: Text('打开浏览器失败，更新链接已复制到剪贴板。')),
              );
            }
            Navigator.of(context).pop();
          },
          child: const Text('去更新'),
        ),
      ],
    );
  }
}

class _VersionPill extends StatelessWidget {
  const _VersionPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

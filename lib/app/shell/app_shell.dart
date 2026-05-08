import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:mise_gui/app/bootstrap/dependencies.dart';
import 'package:mise_gui/app/router/app_destination.dart';
import 'package:mise_gui/app/theme/app_theme.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/shared/ui/app_backdrop.dart';
import 'package:mise_gui/shared/ui/app_panel.dart';
import 'package:mise_gui/shared/ui/status_badge.dart';
import 'package:mise_gui/services/mise_process_service.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destination = AppDestination.values[navigationShell.currentIndex];
    final colors = AppTheme.colorsOf(context);
    final miseAvailableValue = ref.watch(miseAvailableProvider);
    final isMissingMise = miseAvailableValue.maybeWhen(
      data: (value) => !value,
      orElse: () => false,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 980;
        final expandedSidebar = constraints.maxWidth >= 1280;
        final immersiveMacDesktop =
            !compact &&
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.macOS;

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: compact
              ? AppBar(
                  title: Text(isMissingMise ? '安装 mise' : destination.label),
                  actions: const [
                    Padding(
                      padding: EdgeInsets.only(right: 16),
                      child: Center(child: _TopMetaRow(compact: true)),
                    ),
                  ],
                )
              : null,
          drawer: compact
              ? Drawer(
                  backgroundColor: colors.panel,
                  child: SafeArea(
                    child: _Sidebar(
                      currentIndex: navigationShell.currentIndex,
                      expanded: true,
                      locked: isMissingMise,
                      onSelect: (index) {
                        if (isMissingMise) {
                          return;
                        }
                        Navigator.of(context).pop();
                        navigationShell.goBranch(index);
                      },
                    ),
                  ),
                )
              : null,
          body: Stack(
            children: [
              const AppBackdrop(),
              SafeArea(
                top: !immersiveMacDesktop,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 24,
                    compact ? 16 : (immersiveMacDesktop ? 10 : 24),
                    compact ? 16 : 24,
                    compact ? 16 : 24,
                  ),
                  child: compact
                      ? _ContentPanel(
                          child: miseAvailableValue.when(
                            data: (available) => available
                                ? navigationShell
                                : const _MissingMiseExperience(),
                            loading: () => const _ShellLoadingView(),
                            error: (error, stackTrace) => navigationShell,
                          ),
                        )
                      : Column(
                          children: [
                            if (immersiveMacDesktop)
                              const _DesktopChromeBar()
                            else
                              const _TopBar(),
                            SizedBox(height: immersiveMacDesktop ? 14 : 20),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _Sidebar(
                                    currentIndex: navigationShell.currentIndex,
                                    expanded: expandedSidebar,
                                    locked: isMissingMise,
                                    onSelect: isMissingMise
                                        ? (_) {}
                                        : navigationShell.goBranch,
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: _ContentPanel(
                                      child: miseAvailableValue.when(
                                        data: (available) => available
                                            ? navigationShell
                                            : const _MissingMiseExperience(),
                                        loading: () =>
                                            const _ShellLoadingView(),
                                        error: (error, stackTrace) =>
                                            navigationShell,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DesktopChromeBar extends StatelessWidget {
  const _DesktopChromeBar();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.only(left: 92),
        child: _TopMetaRow(compact: false),
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.currentIndex,
    required this.expanded,
    required this.locked,
    required this.onSelect,
  });

  final int currentIndex;
  final bool expanded;
  final bool locked;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppTheme.colorsOf(context);
    final appVersion = ref.watch(appVersionInfoProvider);
    final sidebarWidth = expanded ? 280.0 : 112.0;
    final sidebarPadding = expanded ? 18.0 : 12.0;
    final brandPadding = expanded ? 16.0 : 10.0;
    final compactBrandSize = expanded ? 92.0 : 54.0;

    return SizedBox(
      width: sidebarWidth,
      child: AppPanel(
        padding: EdgeInsets.all(sidebarPadding),
        radius: 24,
        backgroundAlpha: 0.72,
        borderAlpha: 0.48,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              crossAxisAlignment: expanded
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: expanded
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.fromLTRB(
                            brandPadding,
                            brandPadding,
                            brandPadding,
                            expanded ? 14 : brandPadding,
                          ),
                          decoration: BoxDecoration(
                            gradient: expanded
                                ? LinearGradient(
                                    colors: [
                                      colors.panelRaised.withValues(alpha: 0.2),
                                      colors.accent.withValues(alpha: 0.07),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: expanded
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const _BrandBadge(size: 92),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Mise GUI',
                                      style: TextStyle(
                                        fontFamily: 'FiraCode',
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '本地环境统一管理',
                                      style: TextStyle(color: colors.textMuted),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      '集中管理常用语言、工具链和项目版本差异。',
                                      style: TextStyle(
                                        color: colors.textMuted,
                                        fontSize: 13,
                                        height: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    const Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _RuntimePill(label: 'Java'),
                                        _RuntimePill(label: 'Python'),
                                        _RuntimePill(label: 'Go'),
                                        _RuntimePill(label: 'Node'),
                                        _RuntimePill(label: 'Flutter'),
                                        _RuntimePill(label: '更多工具链'),
                                      ],
                                    ),
                                    if (locked) ...[
                                      const SizedBox(height: 14),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colors.warning.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: colors.warning.withValues(
                                              alpha: 0.26,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.lock_outline_rounded,
                                              size: 16,
                                              color: colors.warning,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                '先安装 mise，左侧导航会自动解锁。',
                                                style: TextStyle(
                                                  color: colors.textPrimary,
                                                  fontSize: 12,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                )
                              : Center(
                                  child: _BrandBadge(size: compactBrandSize),
                                ),
                        ),
                        const SizedBox(height: 20),
                        for (final destination in AppDestination.values)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _SidebarDestination(
                              destination: destination,
                              expanded: expanded,
                              selected:
                                  !locked && currentIndex == destination.index,
                              locked: locked,
                              onTap: () => onSelect(destination.index),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _SidebarFooter(
                  expanded: expanded,
                  compactWidth: constraints.maxWidth,
                  versionLabel: appVersion.maybeWhen(
                    data: (value) => value.shortLabel,
                    orElse: () => 'v1.0.0',
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({
    required this.expanded,
    required this.compactWidth,
    required this.versionLabel,
  });

  final bool expanded;
  final double compactWidth;
  final String versionLabel;

  @override
  Widget build(BuildContext context) {
    if (expanded) {
      return Align(
        alignment: Alignment.centerLeft,
        child: StatusBadge(label: versionLabel, level: HealthLevel.info),
      );
    }

    return Center(
      child: Container(
        width: compactWidth,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.colorsOf(context).info.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppTheme.colorsOf(context).info.withValues(alpha: 0.35),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            versionLabel,
            maxLines: 1,
            style: TextStyle(
              color: AppTheme.colorsOf(context).info,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarDestination extends StatelessWidget {
  const _SidebarDestination({
    required this.destination,
    required this.expanded,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final AppDestination destination;
  final bool expanded;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = selected ? destination.selectedIcon : destination.icon;
    final colors = AppTheme.colorsOf(context);

    return Tooltip(
      message: destination.label,
      child: Material(
        color: selected
            ? colors.accent.withValues(alpha: 0.14)
            : locked
            ? colors.panelMuted.withValues(alpha: 0.34)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: locked ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          hoverColor: locked ? Colors.transparent : colors.hover,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 14 : 8,
              vertical: 14,
            ),
            child: Row(
              mainAxisAlignment: expanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: expanded ? 42 : 40,
                  height: expanded ? 42 : 40,
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.accent.withValues(alpha: 0.18)
                        : locked
                        ? colors.panel.withValues(alpha: 0.62)
                        : colors.panelRaised.withValues(alpha: 0.58),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: selected
                          ? colors.accent.withValues(alpha: 0.45)
                          : locked
                          ? colors.borderStrong.withValues(alpha: 0.26)
                          : colors.border.withValues(alpha: 0.34),
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: selected
                        ? colors.accent
                        : locked
                        ? colors.textMuted
                        : colors.textPrimary,
                  ),
                ),
                if (expanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          destination.label,
                          style: TextStyle(
                            color: locked
                                ? colors.textMuted
                                : colors.textPrimary,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          destination.description,
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (locked)
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: colors.textMuted,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContentPanel extends StatelessWidget {
  const _ContentPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: colors.panel.withValues(alpha: 0.24),
        child: child,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerRight,
      child: _TopMetaRow(compact: false),
    );
  }
}

class _TopMetaRow extends ConsumerWidget {
  const _TopMetaRow({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = compact ? 8.0 : 12.0;

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.end,
      children: const [_ToolbarGlassGroup()],
    );
  }
}

class _ToolbarGlassGroup extends ConsumerWidget {
  const _ToolbarGlassGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themePreference = ref.watch(themePreferenceProvider);

    return _ToolbarGlassPanel(
      padding: const EdgeInsets.all(6),
      child: SegmentedButton<AppThemePreference>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment<AppThemePreference>(
            value: AppThemePreference.system,
            icon: Icon(Icons.brightness_auto_rounded),
            label: Text('系统'),
          ),
          ButtonSegment<AppThemePreference>(
            value: AppThemePreference.light,
            icon: Icon(Icons.light_mode_rounded),
            label: Text('浅色'),
          ),
          ButtonSegment<AppThemePreference>(
            value: AppThemePreference.dark,
            icon: Icon(Icons.dark_mode_rounded),
            label: Text('深色'),
          ),
        ],
        selected: {themePreference},
        onSelectionChanged: (selection) {
          final nextPreference = selection.first;
          ref.read(themePreferenceProvider.notifier).state = nextPreference;
        },
      ),
    );
  }
}

class _ToolbarGlassPanel extends StatelessWidget {
  const _ToolbarGlassPanel({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colors.panelRaised.withValues(alpha: isDark ? 0.58 : 0.76),
                colors.backgroundSoft.withValues(alpha: isDark ? 0.48 : 0.62),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colors.borderStrong.withValues(
                alpha: isDark ? 0.34 : 0.22,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: colors.backgroundDeep.withValues(
                  alpha: isDark ? 0.16 : 0.06,
                ),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _BrandBadge extends StatelessWidget {
  const _BrandBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SvgPicture.asset(
        'assets/branding/mise_gui_logo.svg',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _RuntimePill extends StatelessWidget {
  const _RuntimePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.borderStrong.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _ShellLoadingView extends StatelessWidget {
  const _ShellLoadingView();

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 18),
          Text('正在检查 mise 是否可用', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '稍等一下，我们先确认当前设备能否直接调用 mise CLI。',
            style: TextStyle(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _MissingMiseExperience extends ConsumerStatefulWidget {
  const _MissingMiseExperience();

  @override
  ConsumerState<_MissingMiseExperience> createState() =>
      _MissingMiseExperienceState();
}

class _MissingMiseExperienceState
    extends ConsumerState<_MissingMiseExperience> {
  static const _retryDebounce = Duration(seconds: 1);

  DateTime? _lastRetryAt;
  var _retrying = false;

  Future<void> _handleRetry() async {
    if (_retrying) {
      _showFeedback('正在重新检测，请稍候。');
      return;
    }

    final now = DateTime.now();
    if (_lastRetryAt != null &&
        now.difference(_lastRetryAt!) < _retryDebounce) {
      _showFeedback('点击过于频繁，请 1 秒后再试。');
      return;
    }

    _lastRetryAt = now;
    setState(() => _retrying = true);

    try {
      final available = await ref.refresh(miseAvailableProvider.future);
      _showFeedback(available ? '已检测到 mise CLI。' : '还没有检测到 mise CLI。');
    } catch (_) {
      _showFeedback('重新检测失败，请稍后重试。');
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
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
    final colors = AppTheme.colorsOf(context);
    final installCommand = recommendedMiseInstallCommand();
    final platformLabel = _currentPlatformLabel();

    return LayoutBuilder(
      builder: (context, viewport) {
        final targetHeight = viewport.maxHeight.isFinite
            ? (viewport.maxHeight - 56).clamp(720.0, 1600.0)
            : 760.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 28, 34, 28),
          child: SizedBox(
            height: targetHeight,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colors.panelRaised.withValues(alpha: 0.98),
                    colors.backgroundSoft.withValues(alpha: 0.92),
                    colors.accent.withValues(alpha: 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: colors.borderStrong),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 1040;
                  final hero = _MissingHeroText(platformLabel: platformLabel);
                  final commandCard = _InstallCommandCard(
                    installCommand: installCommand,
                    onCopy: () async {
                      await Clipboard.setData(
                        ClipboardData(text: installCommand),
                      );
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('安装命令已复制到剪贴板。')),
                      );
                    },
                    onRetry: _handleRetry,
                    retrying: _retrying,
                  );

                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        hero,
                        const SizedBox(height: 24),
                        commandCard,
                        const SizedBox(height: 24),
                        const _MissingMiseFooterBand(),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: hero),
                          const SizedBox(width: 22),
                          Expanded(
                            flex: 5,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 34),
                              child: commandCard,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      const _MissingMiseFooterBand(),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MissingHeroText extends StatelessWidget {
  const _MissingHeroText({required this.platformLabel});

  final String platformLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('这台电脑还没有安装 mise', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 14),
        Text(
          'Mise GUI 依赖可用的 mise CLI 才能读取工具版本、项目覆盖关系和全局配置。先完成安装，右侧这些功能就会自动解锁。',
          style: TextStyle(color: colors.textMuted, fontSize: 16, height: 1.65),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.panel.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colors.accent.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Icon(Icons.terminal_rounded, color: colors.accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$platformLabel 推荐安装方式',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '先安装，再点击右侧“重新检测”，应用就会进入正常视图。',
                          style: TextStyle(
                            color: colors.textMuted,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const _StepRow(
                index: '01',
                title: '执行安装命令',
                description: '使用右侧命令在当前系统安装 mise。',
              ),
              const SizedBox(height: 12),
              const _StepRow(
                index: '02',
                title: '确认 CLI 可用',
                description: '安装完成后，先运行 `mise --version` 验证命令是否生效。',
              ),
              const SizedBox(height: 12),
              const _StepRow(
                index: '03',
                title: '回到应用重新检测',
                description: '安装完成后点击“重新检测”，左侧导航和完整页面会自动恢复。',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InstallCommandCard extends StatelessWidget {
  const _InstallCommandCard({
    required this.installCommand,
    required this.onCopy,
    required this.onRetry,
    required this.retrying,
  });

  final String installCommand;
  final VoidCallback onCopy;
  final VoidCallback onRetry;
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return AppPanel(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
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
                    Text('安装命令', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      '复制后在终端执行。安装完成后，不需要重新配置这个页面。',
                      style: TextStyle(color: colors.textMuted, height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: colors.backgroundDeep.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.54
                    : 0.82,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colors.borderStrong),
            ),
            child: SelectableText(
              installCommand,
              style: TextStyle(
                fontFamily: 'FiraCode',
                fontSize: 14,
                height: 1.55,
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '安装完成后建议再执行一次：`mise --version`',
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.content_copy_rounded),
                label: const Text('复制安装命令'),
              ),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: retrying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(retrying ? '检测中...' : '重新检测'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MissingMiseFooterBand extends StatelessWidget {
  const _MissingMiseFooterBand();

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.panel.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('安装完成后你会立刻看到', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '环境总览、工具版本和全局配置都会自动接入，不需要再额外配置页面。',
            style: TextStyle(color: colors.textMuted, height: 1.55),
          ),
          const SizedBox(height: 18),
          const Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              SizedBox(
                width: 280,
                child: _FooterFeatureTile(
                  icon: Icons.space_dashboard_rounded,
                  title: '环境总览',
                  description: '活跃工具、PATH 导出和整体健康评分会直接显示。',
                ),
              ),
              SizedBox(
                width: 280,
                child: _FooterFeatureTile(
                  icon: Icons.handyman_rounded,
                  title: '工具版本',
                  description: '已安装版本、当前生效版本和来源关系会自动读出。',
                ),
              ),
              SizedBox(
                width: 320,
                child: _FooterFeatureTile(
                  icon: Icons.tune_rounded,
                  title: '全局配置',
                  description: '当前默认版本和配置文件内容会直接读出。',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FooterFeatureTile extends StatelessWidget {
  const _FooterFeatureTile({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.backgroundSoft.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border.withValues(alpha: 0.9)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.info.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: colors.info, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(color: colors.textMuted, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.index,
    required this.title,
    required this.description,
  });

  final String index;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.accent.withValues(alpha: 0.24)),
          ),
          alignment: Alignment.center,
          child: Text(
            index,
            style: TextStyle(
              color: colors.accent,
              fontFamily: 'FiraCode',
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(color: colors.textMuted, height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _currentPlatformLabel() {
  if (Platform.isMacOS) {
    return 'macOS';
  }
  if (Platform.isWindows) {
    return 'Windows';
  }
  if (Platform.isLinux) {
    return 'Linux';
  }
  return '当前系统';
}

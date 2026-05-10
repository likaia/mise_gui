import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mise_gui/app/router/app_destination.dart';
import 'package:mise_gui/app/theme/app_theme.dart';
import 'package:mise_gui/features/dashboard/application/dashboard_provider.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/services/mise_process_service.dart';
import 'package:mise_gui/shared/ui/app_page_scaffold.dart';
import 'package:mise_gui/shared/ui/app_panel.dart';
import 'package:mise_gui/shared/ui/async_state_view.dart';
import 'package:mise_gui/shared/ui/recent_history_dialog.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage>
    with WidgetsBindingObserver {
  static const _refreshDebounce = Duration(seconds: 1);
  static const _autoRefreshInterval = Duration(seconds: 5);

  DateTime? _lastRefreshAt;
  var _refreshing = false;
  var _backgroundRefreshing = false;
  Timer? _autoRefreshTimer;
  var _pageVisible = false;
  AppLifecycleState? _lifecycleState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (_pageVisible == visible) {
      return;
    }
    _pageVisible = visible;
    _syncAutoRefreshTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _syncAutoRefreshTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAutoRefreshTimer();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    if (_refreshing) {
      _showFeedback('正在刷新环境数据，请稍候。');
      return;
    }

    final now = DateTime.now();
    if (_lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < _refreshDebounce) {
      _showFeedback('点击过于频繁，请 1 秒后再试。');
      return;
    }

    _lastRefreshAt = now;
    await _refreshDashboard(silent: false);
  }

  Future<void> _refreshDashboard({required bool silent}) async {
    if (!mounted) {
      return;
    }
    if (silent) {
      if (_refreshing || _backgroundRefreshing) {
        return;
      }
      _backgroundRefreshing = true;
    } else {
      if (_refreshing) {
        return;
      }
      setState(() => _refreshing = true);
    }

    try {
      final refreshed = ref.refresh(dashboardProvider.future);
      await refreshed;
      if (!silent) {
        _showFeedback('环境数据已刷新。');
      }
    } catch (error) {
      if (!silent) {
        _showFeedback(_formatRefreshError(error));
      }
    } finally {
      if (silent) {
        _backgroundRefreshing = false;
      } else if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  bool get _shouldAutoRefresh {
    final active =
        _lifecycleState == null || _lifecycleState == AppLifecycleState.resumed;
    return _pageVisible && active;
  }

  void _syncAutoRefreshTimer() {
    if (_shouldAutoRefresh) {
      _startAutoRefreshTimer();
      return;
    }
    _stopAutoRefreshTimer();
  }

  void _startAutoRefreshTimer() {
    _autoRefreshTimer ??= Timer.periodic(_autoRefreshInterval, (_) {
      _refreshDashboard(silent: true);
    });
  }

  void _stopAutoRefreshTimer() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  String _formatRefreshError(Object error) {
    if (isMiseCommandUnavailable(error)) {
      return '刷新失败：未检测到 mise CLI。';
    }
    return '刷新失败，请稍后重试。';
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
    final snapshot = ref.watch(dashboardProvider);

    return AsyncStateView(
      value: snapshot,
      builder: (data) => AppPageScaffold(
        title: '环境总览',
        description: '',
        actions: [
          OutlinedButton.icon(
            onPressed: _handleRefresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(_refreshing ? '刷新中...' : '刷新环境数据'),
          ),
        ],
        child: _DashboardOverview(snapshot: data),
      ),
    );
  }
}

class _DashboardOverview extends StatelessWidget {
  const _DashboardOverview({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DashboardMetricGrid(metrics: snapshot.metrics),
        const SizedBox(height: 28),
        _RecentHistoryPanel(entries: snapshot.recentHistory),
      ],
    );
  }
}

class _DashboardMetricGrid extends StatelessWidget {
  const _DashboardMetricGrid({required this.metrics});

  final List<SummaryMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 20.0;
        final twoColumns = constraints.maxWidth >= 980;
        final cardWidth = twoColumns
            ? (constraints.maxWidth - spacing) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: cardWidth,
                child: _DashboardMetricCard(metric: metric),
              ),
          ],
        );
      },
    );
  }
}

class _RecentHistoryPanel extends StatelessWidget {
  const _RecentHistoryPanel({required this.entries});

  final List<HistoryEntry> entries;

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
                  Text('最近活动', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    '查看最近通过界面执行过的操作结果。',
                    style: TextStyle(color: colors.textMuted, height: 1.5),
                  ),
                ],
              ),
            ),
            if (entries.isNotEmpty)
              TextButton.icon(
                onPressed: () => showRecentHistoryDialog(context),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('查看全部'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (entries.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: colors.panel.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border.withValues(alpha: 0.38)),
            ),
            child: Text(
              '当前还没有最近操作记录。',
              style: TextStyle(color: colors.textMuted),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return RecentHistoryListTile(entry: entry);
            },
          ),
      ],
    );
  }
}

class _DashboardMetricCard extends StatelessWidget {
  const _DashboardMetricCard({required this.metric});

  final SummaryMetric metric;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final destination = _destinationFor(metric.label);
    final accent = switch (metric.level) {
      HealthLevel.healthy => colors.accent,
      HealthLevel.info => colors.info,
      HealthLevel.warning => colors.warning,
      HealthLevel.critical => colors.danger,
    };

    const cardRadius = 20.0;
    final panel = AppPanel(
      key: _keyFor(metric.label),
      padding: const EdgeInsets.all(22),
      radius: cardRadius,
      backgroundAlpha: 0.74,
      borderAlpha: 0.5,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 178),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(_iconFor(metric.label), color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    metric.label,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (destination != null)
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: colors.textMuted,
                    size: 20,
                  ),
              ],
            ),
            const SizedBox(height: 26),
            Text(
              metric.value,
              style: Theme.of(
                context,
              ).textTheme.displaySmall?.copyWith(color: accent, height: 1),
            ),
            if (metric.caption.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                metric.caption,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (destination == null) {
      return panel;
    }

    return Tooltip(
      message: '打开${destination.description}',
      child: Semantics(
        button: true,
        label: '打开${metric.label}',
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(cardRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(cardRadius),
            onTap: () => context.go(destination.path),
            child: panel,
          ),
        ),
      ),
    );
  }

  AppDestination? _destinationFor(String label) {
    switch (label) {
      case '已装工具':
        return AppDestination.tools;
      case '项目覆盖':
        return AppDestination.projects;
      default:
        return null;
    }
  }

  Key? _keyFor(String label) {
    switch (label) {
      case '已装工具':
        return const ValueKey('dashboard-metric-tools');
      case '项目覆盖':
        return const ValueKey('dashboard-metric-projects');
      default:
        return null;
    }
  }

  IconData _iconFor(String label) {
    switch (label) {
      case '当前系统':
        return Icons.desktop_windows_rounded;
      case '已装工具':
        return Icons.extension_rounded;
      case '项目覆盖':
        return Icons.account_tree_rounded;
      case 'Mise 版本':
        return Icons.verified_rounded;
      default:
        return Icons.data_usage_rounded;
    }
  }
}

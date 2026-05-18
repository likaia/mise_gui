import 'package:flutter/material.dart';
import 'package:mise_gui/app/theme/app_theme.dart';
import 'package:mise_gui/models/app_models.dart';

class InlineNoticeBar extends StatelessWidget {
  const InlineNoticeBar({
    super.key,
    required this.notice,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final InlineNotice notice;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final accent = switch (notice.level) {
      HealthLevel.healthy => colors.accent,
      HealthLevel.info => colors.info,
      HealthLevel.warning => colors.warning,
      HealthLevel.critical => colors.danger,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.info_outline_rounded, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  notice.message,
                  style: TextStyle(color: colors.textMuted, height: 1.45),
                ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: Icon(actionIcon ?? Icons.open_in_new_rounded),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

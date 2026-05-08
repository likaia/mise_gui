import 'package:flutter/material.dart';
import 'package:mise_gui/app/theme/app_theme.dart';

class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.showShadow = true,
    this.radius = 22,
    this.backgroundAlpha,
    this.borderAlpha,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool showShadow;
  final double radius;
  final double? backgroundAlpha;
  final double? borderAlpha;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: padding,
      decoration: BoxDecoration(
        color: colors.panel.withValues(alpha: backgroundAlpha ?? 0.84),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: colors.border.withValues(alpha: borderAlpha ?? 0.58),
        ),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0x24000000)
                      : const Color(0x0F0F172A),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

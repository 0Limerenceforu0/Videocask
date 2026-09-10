import 'package:flutter/material.dart';

/// 详情页强调色（播放器控制条等）；跟随全局主题主色。
Color detailAccentColor(BuildContext context) =>
    Theme.of(context).colorScheme.primary;

/// 设计参考页等仍使用的固定强调色；详情 UI 应优先 [detailAccentColor]。
const Color kDetailAccentColor = Color(0xFF00AEEC);

/// 详情页信息区（播放器下方 / 侧栏）主题色，与 [MaterialApp] 主题同步。
@immutable
class DetailPageColors {
  const DetailPageColors({
    required this.onSurface,
    required this.muted,
    required this.card,
    required this.scaffold,
    required this.accent,
    required this.divider,
    required this.chipBackground,
    required this.onAccent,
    required this.surfaceTint,
    required this.faint,
  });

  final Color onSurface;
  final Color muted;
  final Color card;
  final Color scaffold;
  final Color accent;
  final Color divider;
  final Color chipBackground;
  final Color onAccent;
  final Color surfaceTint;
  final Color faint;

  factory DetailPageColors.of(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return DetailPageColors(
      onSurface: cs.onSurface,
      muted: theme.textTheme.bodySmall?.color ?? cs.onSurfaceVariant,
      card: theme.cardColor,
      scaffold: theme.scaffoldBackgroundColor,
      accent: cs.primary,
      divider: theme.dividerColor,
      chipBackground: isDark
          ? Colors.white.withValues(alpha: 0.08)
          : cs.surfaceContainerHighest,
      onAccent: cs.onPrimary,
      surfaceTint: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : cs.surfaceContainerHigh,
      faint: cs.onSurface.withValues(alpha: isDark ? 0.38 : 0.45),
    );
  }
}

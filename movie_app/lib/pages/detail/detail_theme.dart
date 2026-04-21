import 'package:flutter/material.dart';
import '../../utils/torrent_title_display.dart';

/// 详情页颜色配置（从 Theme 获取，支持明暗切换）
class DetailPageColors {
  DetailPageColors._();

  static DetailPageColorsData of(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return DetailPageColorsData(
      bgColor: isDark ? const Color(0xFF17181A) : theme.colorScheme.surface,
      cardColor: isDark
          ? const Color(0xFF222325)
          : theme.colorScheme.surfaceContainerHighest,
      dividerColor: isDark ? const Color(0xFF2E2F31) : theme.dividerColor,
      textColor: isDark ? const Color(0xFFE6E6E6) : theme.colorScheme.onSurface,
      subTextColor:
          isDark ? const Color(0xFF999999) : theme.colorScheme.onSurfaceVariant,
      accentColor: theme.colorScheme.primary,
      accentLightColor:
          isDark ? const Color(0xFF1A3A4A) : theme.colorScheme.primaryContainer,
      starColor: const Color(0xFFFFB800),
    );
  }
}

class DetailPageColorsData {
  final Color bgColor;
  final Color cardColor;
  final Color dividerColor;
  final Color textColor;
  final Color subTextColor;
  final Color accentColor;
  final Color accentLightColor;
  final Color starColor;

  const DetailPageColorsData({
    required this.bgColor,
    required this.cardColor,
    required this.dividerColor,
    required this.textColor,
    required this.subTextColor,
    required this.accentColor,
    required this.accentLightColor,
    required this.starColor,
  });
}

/// 磁力标题：主行 + 互补语言副行（中英）
Widget detailTorrentNameTwoLinesWidget({
  required String rawName,
  required Color primaryColor,
  required Color secondaryColor,
  double primarySize = 13,
}) {
  final lines = splitTorrentDisplayTitle(rawName);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        lines.primary,
        style: TextStyle(
          color: primaryColor,
          fontSize: primarySize,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      if (lines.secondary != null && lines.secondary!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            lines.secondary!,
            style: TextStyle(
              color: secondaryColor,
              fontSize: primarySize - 1,
              height: 1.25,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
  );
}

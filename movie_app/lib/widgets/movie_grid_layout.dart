import 'package:flutter/material.dart';

/// 影视海报网格的响应式列数、间距与宽高比（首页、频道等共用）。
class MovieGridLayout {
  MovieGridLayout._();

  static const double posterHeightFactor = 1.4;

  /// 封面下方：间距 + 年份/地区（+ 可选来源行），与 [MovieCard] 网格模式一致。
  static const double metaBelowPosterHeight = 48;

  /// [contentWidth] 为网格区域可用宽度（通常为屏宽减去左右 padding）。
  static MovieGridMetrics metricsForWidth(
    double contentWidth, {
    bool dense = false,
  }) {
    if (contentWidth <= 0) {
      return const MovieGridMetrics(
        crossAxisCount: 2,
        childAspectRatio: 0.58,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      );
    }

    final crossAxisSpacing = dense
        ? (contentWidth < 400 ? 6.0 : 8.0)
        : (contentWidth < 400 ? 8.0 : 10.0);
    final minCardWidth = dense ? 92.0 : 100.0;
    final maxCardWidth = dense ? 128.0 : 148.0;

    var count =
        ((contentWidth + crossAxisSpacing) / (minCardWidth + crossAxisSpacing))
            .floor();
    count = count.clamp(2, 14);

    while (count < 14) {
      final cardW = (contentWidth - crossAxisSpacing * (count - 1)) / count;
      if (cardW <= maxCardWidth) {
        break;
      }
      count++;
    }

    final cardWidth = (contentWidth - crossAxisSpacing * (count - 1)) / count;
    final cellHeight = cardWidth * posterHeightFactor + metaBelowPosterHeight;
    final childAspectRatio = cardWidth / cellHeight;

    final mainAxisSpacing = contentWidth < 600 ? 8.0 : (dense ? 10.0 : 12.0);

    return MovieGridMetrics(
      crossAxisCount: count,
      childAspectRatio: childAspectRatio,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
    );
  }

  static MovieGridMetrics metricsForContext(
    BuildContext context, {
    double horizontalPadding = 24,
    bool dense = false,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    return metricsForWidth(width - horizontalPadding, dense: dense);
  }
}

class MovieGridMetrics {
  const MovieGridMetrics({
    required this.crossAxisCount,
    required this.childAspectRatio,
    required this.crossAxisSpacing,
    required this.mainAxisSpacing,
  });

  final int crossAxisCount;
  final double childAspectRatio;
  final double crossAxisSpacing;
  final double mainAxisSpacing;

  SliverGridDelegateWithFixedCrossAxisCount get sliverDelegate =>
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
      );
}

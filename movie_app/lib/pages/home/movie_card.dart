import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../utils/web_http_stub.dart'
    if (dart.library.html) '../../utils/web_http.dart' as web_http;
import 'package:provider/provider.dart';
import '../../models/movie.dart';
import '../../config/routes.dart';
import '../../providers/source_provider.dart';
import '../../widgets/movie_grid_layout.dart';

String _displayYear(Movie movie) {
  final y = movie.year.trim();
  if (y.isEmpty || y == '0') return '';
  return y;
}

/// 影视卡片组件
///
/// B站风格设计：圆角8px + 底部半透明渐变（黑→透明）+ 标题在渐变上显示白色文字
class MovieCard extends StatelessWidget {
  final Movie movie;
  final double? width;
  final double? height;
  final bool showRating;
  final bool showStatus;

  /// 多源聚合时展示数据来源（可选）
  final String? originLabel;
  final VoidCallback? onTap;

  const MovieCard({
    super.key,
    required this.movie,
    this.width,
    this.height,
    this.showRating = true,
    this.showStatus = true,
    this.originLabel,
    this.onTap,
  });

  /// 获取评分对应的颜色（使用主题色系）
  static Color _ratingColor(BuildContext context, double rating) {
    final theme = Theme.of(context);
    if (rating >= 8.0) return theme.colorScheme.primary;
    if (rating >= 6.0) return theme.colorScheme.tertiary;
    return theme.colorScheme.outline;
  }

  @override
  Widget build(BuildContext context) {
    if (width != null) {
      return _buildCard(
        context,
        cardWidth: width!,
        cardHeight: height ?? width! * MovieGridLayout.posterHeightFactor,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : 120.0;
        const metaH = MovieGridLayout.metaBelowPosterHeight;
        final cardHeight = height ??
            (constraints.maxHeight.isFinite && constraints.maxHeight > metaH
                ? constraints.maxHeight - metaH
                : cardWidth * MovieGridLayout.posterHeightFactor);
        return _buildCard(
          context,
          cardWidth: cardWidth,
          cardHeight: cardHeight,
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required double cardWidth,
    required double cardHeight,
  }) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap ??
          () => AppRoutes.toDetail(
                context,
                id: movie.id,
                sourceId: movie.sourceId,
                movie: movie,
              ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面图 - B站风格圆角8px
          Container(
            width: cardWidth,
            height: cardHeight,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 封面图片
                _buildCoverImage(theme),

                // B站风格底部渐变遮罩（黑→透明）
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 90,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.75),
                        ],
                      ),
                    ),
                  ),
                ),

                // 评分标签 - 右上角圆角8px
                if (showRating && movie.rating > 0)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _ratingColor(context, movie.rating)
                            .withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, size: 10, color: Colors.white),
                          const SizedBox(width: 2),
                          Text(
                            movie.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // B站风格：标题在底部渐变上显示白色文字
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 6,
                  child: Text(
                    movie.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(color: Colors.black54, blurRadius: 4),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // 更新状态 - 左下角
                if (showStatus && movie.updateStatus.isNotEmpty)
                  Positioned(
                    left: 6,
                    bottom: 28,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        movie.updateStatus,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // 年份和地区（在封面下方；忽略无效年份「0」）
          if (_displayYear(movie).isNotEmpty || movie.region.isNotEmpty)
            SizedBox(
              width: cardWidth,
              child: Text(
                '${_displayYear(movie)}${_displayYear(movie).isNotEmpty && movie.region.isNotEmpty ? ' · ' : ''}${movie.region}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (originLabel != null && originLabel!.isNotEmpty)
            SizedBox(
              width: cardWidth,
              child: Text(
                originLabel!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor.withValues(alpha: 0.85),
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCoverImage(ThemeData theme) {
    if (movie.cover.isEmpty) {
      return Center(
        child: Icon(
          Icons.movie_outlined,
          size: 36,
          color: theme.hintColor.withValues(alpha: 0.4),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: web_http.webProxiedImageUrl(movie.cover),
      fit: BoxFit.cover,
      memCacheWidth: 400,
      memCacheHeight: 560,
      placeholder: (context, url) => Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            theme.colorScheme.primary.withValues(alpha: 0.5),
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.movie_outlined,
                size: 32,
                color: theme.hintColor.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  movie.name.isNotEmpty ? movie.name : '加载失败',
                  style: TextStyle(
                    color: theme.hintColor.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 横向影视卡片（用于搜索结果列表 - B站风格左图右文布局）
class MovieCardHorizontal extends StatelessWidget {
  final Movie movie;
  final VoidCallback? onTap;

  const MovieCardHorizontal({
    super.key,
    required this.movie,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sourceProvider = context.watch<SourceProvider>();
    final primarySourceLabel =
        sourceProvider.sourceDisplayName(movie.sourceId) ??
            (movie.sourceId.isEmpty ? 'CMS' : movie.sourceId);

    return GestureDetector(
      onTap: onTap ??
          () => AppRoutes.toDetail(
                context,
                id: movie.id,
                sourceId: movie.sourceId,
                movie: movie,
              ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // 封面 - B站风格圆角8px，竖版比例
            Container(
              width: 90,
              height: 120,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: movie.cover.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: web_http.webProxiedImageUrl(movie.cover),
                      fit: BoxFit.cover,
                      memCacheWidth: 180,
                      memCacheHeight: 240,
                      errorWidget: (context, url, error) => Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.movie_outlined,
                                size: 24,
                                color: theme.hintColor.withValues(alpha: 0.3),
                              ),
                              const SizedBox(height: 4),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  movie.name.isNotEmpty ? movie.name : '加载失败',
                                  style: TextStyle(
                                    color:
                                        theme.hintColor.withValues(alpha: 0.5),
                                    fontSize: 10,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Icon(
                        Icons.movie_outlined,
                        color: theme.hintColor.withValues(alpha: 0.4),
                        size: 30,
                      ),
                    ),
            ),
            const SizedBox(width: 12),

            // 信息区域（B站风格左图右文）
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 标题
                  Text(
                    movie.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer
                              .withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '主源：$primarySourceLabel',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      ...movie.alternateSources.map(
                        (a) => ActionChip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          label: Text(
                            a.sourceDisplayName,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onPressed: () {
                            AppRoutes.toDetail(
                              context,
                              id: a.movieId,
                              sourceId: a.sourceId,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // 评分
                  if (movie.rating > 0)
                    Row(
                      children: [
                        Icon(
                          Icons.star,
                          size: 14,
                          color: MovieCard._ratingColor(context, movie.rating),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          movie.rating.toStringAsFixed(1),
                          style: TextStyle(
                            color:
                                MovieCard._ratingColor(context, movie.rating),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  // 年份和类型
                  Text(
                    '${movie.year}${movie.year.isNotEmpty ? ' · ' : ''}${movie.genres.take(3).join(" / ")}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // 更新状态
                  if (movie.updateStatus.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      movie.updateStatus,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

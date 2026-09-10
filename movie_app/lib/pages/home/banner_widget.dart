import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../utils/web_http_stub.dart'
    if (dart.library.html) '../../utils/web_http.dart' as web_http;
import '../../models/movie.dart';
import '../../config/routes.dart';

/// 轮播Banner组件（Netflix/爱奇艺风格）
///
/// 布局：背景模糊放大填充 + 海报居中清晰展示 + 底部渐变信息区
class BannerWidget extends StatefulWidget {
  /// 轮播影片列表
  final List<Movie> movies;

  /// 点击回调
  final void Function(Movie movie)? onTap;

  const BannerWidget({
    super.key,
    required this.movies,
    this.onTap,
  });

  @override
  State<BannerWidget> createState() => _BannerWidgetState();
}

class _BannerWidgetState extends State<BannerWidget> {
  /// 当前页码
  int _currentIndex = 0;

  /// 轮播控制器
  final CarouselSliderController _controller = CarouselSliderController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final placeholderHeight = screenHeight * 0.22;

    if (widget.movies.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: placeholderHeight.clamp(120.0, 220.0),
            width: double.infinity,
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.movie_outlined,
                  size: 40,
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 10),
                Text(
                  '暂无轮播推荐',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '可尝试切换数据源或下拉刷新',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        // 轮播图
        CarouselSlider(
          carouselController: _controller,
          options: CarouselOptions(
            height: screenHeight * 0.38,
            autoPlay: true,
            autoPlayInterval: const Duration(milliseconds: 4000),
            autoPlayAnimationDuration: const Duration(milliseconds: 800),
            viewportFraction: 1.0,
            enlargeCenterPage: false,
            onPageChanged: (index, reason) {
              setState(() {
                _currentIndex = index;
              });
            },
          ),
          items: widget.movies.map((movie) {
            return GestureDetector(
              onTap: () {
                if (widget.onTap != null) {
                  widget.onTap!(movie);
                } else {
                  AppRoutes.toDetail(
                    context,
                    id: movie.id,
                    sourceId: movie.sourceId,
                    movie: movie,
                  );
                }
              },
              child: _buildBannerItem(context, movie, theme),
            );
          }).toList(),
        ),

        const SizedBox(height: 8),

        // 指示器
        _buildIndicator(theme),
      ],
    );
  }

  /// 构建轮播项（Netflix风格：背景模糊 + 海报居中 + 底部信息）
  Widget _buildBannerItem(BuildContext context, Movie movie, ThemeData theme) {
    final imageUrl = movie.cover.isNotEmpty ? movie.cover : movie.backdrop;

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 第一层：背景模糊放大图（营造氛围）
          if (imageUrl.isNotEmpty) _buildBlurredBackground(imageUrl),

          // 第二层：整体渐变遮罩（从上到下渐暗）
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.3),
                  Colors.black.withValues(alpha: 0.1),
                  Colors.black.withValues(alpha: 0.7),
                ],
                stops: const [0.0, 0.4, 1.0],
              ),
            ),
          ),

          // 第三层：海报居中清晰展示
          if (imageUrl.isNotEmpty)
            Positioned(
              right: 24,
              top: 16,
              bottom: 70,
              child: _buildPoster(imageUrl),
            ),

          // 第四层：底部影片信息
          Positioned(
            left: 20,
            right: 20,
            bottom: 16,
            child: _buildMovieInfo(movie),
          ),
        ],
      ),
    );
  }

  /// 构建背景模糊图
  Widget _buildBlurredBackground(String imageUrl) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
      child: CachedNetworkImage(
        imageUrl: web_http.webProxiedImageUrl(imageUrl),
        fit: BoxFit.cover,
        memCacheWidth: 600,
        memCacheHeight: 900,
        placeholder: (context, url) => Container(color: Colors.grey[900]),
        errorWidget: (context, url, error) =>
            Container(color: Colors.grey[900]),
      ),
    );
  }

  /// 构建居中海报（清晰、无模糊）
  Widget _buildPoster(String imageUrl) {
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: web_http.webProxiedImageUrl(imageUrl),
        fit: BoxFit.contain,
        memCacheWidth: (400 * devicePixelRatio).round(),
        memCacheHeight: (600 * devicePixelRatio).round(),
        placeholder: (context, url) => Container(
          width: 120,
          color: Colors.grey[800],
          child: const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white54,
            ),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          width: 120,
          color: Colors.grey[800],
          child:
              const Icon(Icons.movie_outlined, color: Colors.white54, size: 48),
        ),
      ),
    );
  }

  /// 构建影片信息
  Widget _buildMovieInfo(Movie movie) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 影片名称
        Text(
          movie.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(color: Colors.black54, blurRadius: 4),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),

        // 类型、评分、状态
        Row(
          children: [
            // 类型标签
            if (movie.genres.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  movie.genres.first,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            if (movie.genres.isNotEmpty) const SizedBox(width: 8),

            // 评分
            if (movie.rating > 0)
              Row(
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 14),
                  const SizedBox(width: 2),
                  Text(
                    movie.rating.toStringAsFixed(1),
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

            const Spacer(),

            // 更新状态
            if (movie.updateStatus.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  movie.updateStatus,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
          ],
        ),

        // 简介（如果有）
        if (movie.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            movie.description,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  /// 构建指示器
  Widget _buildIndicator(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: widget.movies.asMap().entries.map((entry) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: _currentIndex == entry.key ? 20 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: _currentIndex == entry.key
                ? theme.colorScheme.primary
                : theme.colorScheme.primary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }).toList(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/web_http_stub.dart'
    if (dart.library.html) '../../utils/web_http.dart' as web_http;
import 'package:go_router/go_router.dart';
import '../../config/routes.dart';
import '../../providers/history_provider.dart';
import '../../providers/favorite_provider.dart';

/// 观影统计页面
///
/// 展示用户的观影数据统计，包括：
/// - 总观影数、总观影时长、收藏数
/// - 类型偏好分布
/// - 观影活跃度（最近30天）
/// - 最常观看的影片TOP5
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final historyProvider = context.watch<HistoryProvider>();
    final favoriteProvider = context.watch<FavoriteProvider>();
    final histories = historyProvider.histories;
    final favorites = favoriteProvider.favorites;

    final bgColor = isDark ? const Color(0xFF17181A) : const Color(0xFFF4F4F4);
    final cardColor = isDark ? const Color(0xFF222325) : Colors.white;
    final textColor =
        isDark ? const Color(0xFFE6E6E6) : const Color(0xFF212121);
    final subTextColor =
        isDark ? const Color(0xFF999999) : const Color(0xFF999999);

    // ===== 计算统计数据 =====

    // 总观影数（去重，按影片ID）
    final uniqueMovieIds = <String>{};
    for (final h in histories) {
      uniqueMovieIds.add('${h.sourceId}_${h.movieId}');
    }
    final totalMovies = uniqueMovieIds.length;

    // 总观影时长
    final totalWatchCount =
        histories.fold<int>(0, (sum, h) => sum + h.watchCount);
    final estimatedHours = (totalWatchCount * 1.5);

    // 类型偏好统计
    final genreCount = <String, int>{};
    for (final f in favorites) {
      for (final genre in f.genres) {
        if (genre.isNotEmpty) {
          genreCount[genre] = (genreCount[genre] ?? 0) + 1;
        }
      }
    }
    final sortedGenres = genreCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 最近30天观影活跃度
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final recentHistories = histories.where((h) {
      return h.lastWatchTime.isAfter(thirtyDaysAgo);
    }).toList();
    final dailyCounts = <String, int>{};
    for (final h in recentHistories) {
      final dayKey = '${h.lastWatchTime.month}-${h.lastWatchTime.day}';
      dailyCounts[dayKey] = (dailyCounts[dayKey] ?? 0) + 1;
    }

    // 最常观看的影片TOP5
    final movieWatchCounts = <String, _MovieWatchInfo>{};
    for (final h in histories) {
      final key = '${h.sourceId}_${h.movieId}';
      if (movieWatchCounts.containsKey(key)) {
        movieWatchCounts[key]!.watchCount += h.watchCount;
      } else {
        movieWatchCounts[key] = _MovieWatchInfo(
          movieName: h.movieName,
          movieCover: h.movieCover,
          watchCount: h.watchCount,
        );
      }
    }
    final topMovies = movieWatchCounts.values.toList()
      ..sort((a, b) => b.watchCount.compareTo(a.watchCount));
    final top5Movies = topMovies.take(5).toList();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('观影统计'),
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (totalMovies == 0)
            _buildStatsEmptyCallout(
              context,
              cardColor: cardColor,
              textColor: textColor,
              subTextColor: subTextColor,
            ),
          if (totalMovies == 0) const SizedBox(height: 12),

          // ===== 总览数据 =====
          _buildBiliOverviewCard(
            context,
            theme: theme,
            cardColor: cardColor,
            textColor: textColor,
            subTextColor: subTextColor,
            totalMovies: totalMovies,
            estimatedHours: estimatedHours,
            favoriteCount: favorites.length,
          ),
          const SizedBox(height: 12),

          // ===== 类型偏好 =====
          if (sortedGenres.isNotEmpty)
            _buildBiliGenreDistribution(
              context,
              theme: theme,
              cardColor: cardColor,
              textColor: textColor,
              subTextColor: subTextColor,
              sortedGenres: sortedGenres,
              totalCount: genreCount.values.fold(0, (a, b) => a + b),
            ),
          const SizedBox(height: 12),

          // ===== 观影活跃度 =====
          _buildBiliActivityCard(
            context,
            theme: theme,
            cardColor: cardColor,
            textColor: textColor,
            subTextColor: subTextColor,
            recentCount: recentHistories.length,
            dailyCounts: dailyCounts,
          ),
          const SizedBox(height: 12),

          // ===== 最常观看TOP5 =====
          if (top5Movies.isNotEmpty)
            _buildBiliTopMoviesCard(
              context,
              theme: theme,
              cardColor: cardColor,
              textColor: textColor,
              subTextColor: subTextColor,
              topMovies: top5Movies,
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 无观影记录时的引导区
  Widget _buildStatsEmptyCallout(
    BuildContext context, {
    required Color cardColor,
    required Color textColor,
    required Color subTextColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.insights_outlined, size: 44, color: subTextColor),
          const SizedBox(height: 12),
          Text(
            '还没有观影记录',
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '观看影片后，这里会展示时长、类型偏好与最常看的内容。',
            textAlign: TextAlign.center,
            style: TextStyle(color: subTextColor, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              FilledButton(
                onPressed: () => context.go(AppRoutes.home),
                child: const Text('去首页'),
              ),
              OutlinedButton(
                onPressed: () => AppRoutes.toSearch(context),
                child: const Text('去搜索'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建B站风格总览数据卡片（大数字+标签）
  Widget _buildBiliOverviewCard(
    BuildContext context, {
    required ThemeData theme,
    required Color cardColor,
    required Color textColor,
    required Color subTextColor,
    required int totalMovies,
    required double estimatedHours,
    required int favoriteCount,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '观影总览',
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildBiliStatBlock(
                  context,
                  value: '$totalMovies',
                  label: '部影片',
                  icon: Icons.movie,
                  iconColor: const Color(0xFF4FC3F7),
                  textColor: textColor,
                  subTextColor: subTextColor,
                ),
              ),
              Expanded(
                child: _buildBiliStatBlock(
                  context,
                  value: estimatedHours.toStringAsFixed(0),
                  label: '小时',
                  icon: Icons.schedule,
                  iconColor: const Color(0xFFFFB74D),
                  textColor: textColor,
                  subTextColor: subTextColor,
                ),
              ),
              Expanded(
                child: _buildBiliStatBlock(
                  context,
                  value: '$favoriteCount',
                  label: '收藏',
                  icon: Icons.favorite,
                  iconColor: const Color(0xFFF48FB1),
                  textColor: textColor,
                  subTextColor: subTextColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// B站风格统计块（大数字+标签）
  Widget _buildBiliStatBlock(
    BuildContext context, {
    required String value,
    required String label,
    required IconData icon,
    required Color iconColor,
    required Color textColor,
    required Color subTextColor,
  }) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: textColor,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: subTextColor,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  /// 构建B站风格类型偏好分布（横向柱状图）
  Widget _buildBiliGenreDistribution(
    BuildContext context, {
    required ThemeData theme,
    required Color cardColor,
    required Color textColor,
    required Color subTextColor,
    required List<MapEntry<String, int>> sortedGenres,
    required int totalCount,
  }) {
    final topGenres = sortedGenres.take(5).toList();
    int otherCount = 0;
    if (sortedGenres.length > 5) {
      for (int i = 5; i < sortedGenres.length; i++) {
        otherCount += sortedGenres[i].value;
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '类型偏好',
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...topGenres.asMap().entries.map((entry) {
            final index = entry.key;
            final genre = entry.value;
            final percent = totalCount > 0
                ? (genre.value / totalCount * 100).toStringAsFixed(0)
                : '0';
            final barColors = [
              const Color(0xFF4FC3F7),
              const Color(0xFF81C784),
              const Color(0xFFFFB74D),
              const Color(0xFFCE93D8),
              const Color(0xFFF48FB1),
            ];
            final color = barColors[index % barColors.length];

            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        genre.key,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '$percent%',
                        style: TextStyle(
                          color: subTextColor,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value:
                                totalCount > 0 ? genre.value / totalCount : 0,
                            minHeight: 8,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${genre.value}',
                        style: TextStyle(
                          color: subTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
          if (otherCount > 0) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '其他',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${(otherCount / totalCount * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: subTextColor,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: otherCount / totalCount,
                            minHeight: 8,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$otherCount',
                        style: TextStyle(
                          color: subTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建B站风格观影活跃度卡片
  Widget _buildBiliActivityCard(
    BuildContext context, {
    required ThemeData theme,
    required Color cardColor,
    required Color textColor,
    required Color subTextColor,
    required int recentCount,
    required Map<String, int> dailyCounts,
  }) {
    final activeDays = dailyCounts.length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '观影活跃度（最近30天）',
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color:
                      (recentCount > 0 ? const Color(0xFFFFB74D) : subTextColor)
                          .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.local_fire_department,
                  color:
                      recentCount > 0 ? const Color(0xFFFFB74D) : subTextColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '共观看 $recentCount 部',
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '活跃 $activeDays 天',
                style: TextStyle(
                  color: subTextColor,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildActivityBar(context, theme, dailyCounts),
        ],
      ),
    );
  }

  /// 构建活跃度条形图
  Widget _buildActivityBar(
    BuildContext context,
    ThemeData theme,
    Map<String, int> dailyCounts,
  ) {
    final now = DateTime.now();
    final days = List.generate(30, (index) {
      final date = now.subtract(Duration(days: 29 - index));
      final key = '${date.month}-${date.day}';
      return dailyCounts[key] ?? 0;
    });

    final maxCount =
        days.fold<int>(0, (max, count) => count > max ? count : max);

    return SizedBox(
      height: 40,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: days.map((count) {
          final height = maxCount > 0 ? (count / maxCount * 36.0) : 0.0;
          final hasActivity = count > 0;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              height: hasActivity ? height.clamp(2.0, 36.0) : 2.0,
              decoration: BoxDecoration(
                color: hasActivity
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 构建B站风格最常观看TOP5卡片
  Widget _buildBiliTopMoviesCard(
    BuildContext context, {
    required ThemeData theme,
    required Color cardColor,
    required Color textColor,
    required Color subTextColor,
    required List<_MovieWatchInfo> topMovies,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '最常观看 TOP${topMovies.length}',
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...topMovies.asMap().entries.map((entry) {
            final index = entry.key;
            final movie = entry.value;
            final rankColors = [
              const Color(0xFFFFD54F),
              const Color(0xFFB0BEC5),
              const Color(0xFFFFB74D),
            ];

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: index < 3
                          ? rankColors[index].withValues(alpha: 0.15)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: index < 3 ? rankColors[index] : subTextColor,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 36,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: movie.movieCover.isNotEmpty
                        ? Image.network(
                            web_http.webProxiedImageUrl(movie.movieCover),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.movie_outlined,
                              color: Colors.grey,
                              size: 18,
                            ),
                          )
                        : const Icon(
                            Icons.movie_outlined,
                            color: Colors.grey,
                            size: 18,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      movie.movieName,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${movie.watchCount}次',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// 影片观看信息（内部使用）
class _MovieWatchInfo {
  /// 影片名称
  final String movieName;

  /// 影片封面
  final String movieCover;

  /// 观看次数
  int watchCount;

  _MovieWatchInfo({
    required this.movieName,
    required this.movieCover,
    required this.watchCount,
  });
}

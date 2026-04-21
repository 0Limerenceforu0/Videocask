import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/routes.dart';
import '../../models/movie.dart';
import '../../providers/movie_provider.dart';

/// 排行榜页面
///
/// 包含四个榜单Tab：好评榜、热播榜、最新榜、飙升榜。
/// 数据从 MovieProvider 获取后本地排序，不需要额外API。
class RankingPage extends StatefulWidget {
  const RankingPage({super.key});

  @override
  State<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends State<RankingPage>
    with SingleTickerProviderStateMixin {
  /// Tab控制器
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 获取所有影片数据（合并首页各分区数据并去重）
  List<Movie> _getAllMovies(MovieProvider provider) {
    final allMovies = <String, Movie>{};

    // 合并所有分区的影片数据
    for (final movie in provider.bannerList) {
      allMovies[movie.id] = movie;
    }
    for (final movie in provider.hotMovies) {
      allMovies[movie.id] = movie;
    }
    for (final movie in provider.latestMovies) {
      allMovies[movie.id] = movie;
    }
    for (final movie in provider.topRatedMovies) {
      allMovies[movie.id] = movie;
    }
    for (final movie in provider.classicMovies) {
      allMovies[movie.id] = movie;
    }
    for (final movie in provider.homeMovies) {
      allMovies[movie.id] = movie;
    }

    return allMovies.values.toList();
  }

  /// 好评榜：按评分降序排列
  List<Movie> _getTopRatedList(MovieProvider provider) {
    final movies = _getAllMovies(provider).where((m) => m.rating > 0).toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));
    return movies;
  }

  /// 热播榜：按更新时间排序，有更新状态的优先
  List<Movie> _getHotList(MovieProvider provider) {
    final movies = _getAllMovies(provider).toList()
      ..sort((a, b) {
        // 有更新状态的排在前面
        final aHasUpdate = a.updateStatus.isNotEmpty ? 0 : 1;
        final bHasUpdate = b.updateStatus.isNotEmpty ? 0 : 1;
        if (aHasUpdate != bHasUpdate) return aHasUpdate.compareTo(bHasUpdate);
        // 同等条件下按最后更新时间倒序
        return b.lastUpdate.compareTo(a.lastUpdate);
      });
    return movies;
  }

  /// 最新榜：按年份倒序，同年按名称排序
  List<Movie> _getNewestList(MovieProvider provider) {
    final movies =
        _getAllMovies(provider).where((m) => m.year.isNotEmpty).toList()
          ..sort((a, b) {
            // 先按年份倒序
            final yearCompare = b.year.compareTo(a.year);
            if (yearCompare != 0) return yearCompare;
            // 同年按名称排序
            return a.name.compareTo(b.name);
          });
    return movies;
  }

  /// 飙升榜：最近添加到采集站的影片（按采集站返回顺序，即homeMovies的顺序）
  List<Movie> _getSurgingList(MovieProvider provider) {
    // homeMovies 的顺序就是采集站返回的顺序，直接使用
    return provider.homeMovies.toList();
  }

  /// 根据当前Tab获取排名序号的样式颜色
  ///
  /// 前三名使用特殊颜色（金、银、铜），其余使用普通灰色
  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700); // 金色
      case 2:
        return const Color(0xFFC0C0C0); // 银色
      case 3:
        return const Color(0xFFCD7F32); // 铜色
      default:
        return Colors.grey;
    }
  }

  /// 获取排名序号的图标
  IconData _getRankIcon(int rank) {
    switch (rank) {
      case 1:
        return Icons.emoji_events;
      case 2:
        return Icons.military_tech;
      case 3:
        return Icons.workspace_premium;
      default:
        return Icons.looks_one;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final movieProvider = context.watch<MovieProvider>();

    final bgColor = isDark ? const Color(0xFF17181A) : const Color(0xFFF4F4F4);
    final cardColor = isDark ? const Color(0xFF222325) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('排行榜'),
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '好评榜'),
            Tab(text: '热播榜'),
            Tab(text: '最新榜'),
            Tab(text: '飙升榜'),
          ],
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.hintColor,
          indicatorColor: theme.colorScheme.primary,
          indicatorSize: TabBarIndicatorSize.label,
          indicatorWeight: 3,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRankingList(
            context,
            currentList: _getTopRatedList(movieProvider),
          ),
          _buildRankingList(context, currentList: _getHotList(movieProvider)),
          _buildRankingList(
            context,
            currentList: _getNewestList(movieProvider),
          ),
          _buildRankingList(
            context,
            currentList: _getSurgingList(movieProvider),
          ),
        ],
      ),
    );
  }

  /// 构建排行榜列表
  Widget _buildRankingList(
    BuildContext context, {
    required List<Movie> currentList,
  }) {
    final theme = Theme.of(context);

    if (currentList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inbox_outlined,
                size: 64,
                color: theme.hintColor,
              ),
              const SizedBox(height: 16),
              Text(
                '暂无排行数据',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.hintColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '榜单来自首页已加载的影片库。若首页尚无数据，请先返回首页下拉刷新或检查播放源。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.hintColor.withValues(alpha: 0.85),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: () => AppRoutes.toHome(context),
                child: const Text('去首页'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: currentList.length,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      itemBuilder: (context, index) {
        final movie = currentList[index];
        final rank = index + 1;

        return _buildBiliRankingItem(context, movie: movie, rank: rank);
      },
    );
  }

  /// 构建B站风格排行榜列表项（序号+封面+标题+评分）
  Widget _buildBiliRankingItem(
    BuildContext context, {
    required Movie movie,
    required int rank,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final rankColor = _getRankColor(rank);
    final isTop3 = rank <= 3;
    final cardColor = isDark ? const Color(0xFF222325) : Colors.white;
    final textColor =
        isDark ? const Color(0xFFE6E6E6) : const Color(0xFF212121);
    final subTextColor =
        isDark ? const Color(0xFF999999) : const Color(0xFF999999);

    return GestureDetector(
      onTap: () => AppRoutes.toDetail(
        context,
        id: movie.id,
        sourceId: movie.sourceId,
        movie: movie,
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // 排名序号
            SizedBox(
              width: 32,
              child: isTop3
                  ? Icon(
                      _getRankIcon(rank),
                      color: rankColor,
                      size: 28,
                    )
                  : Text(
                      '$rank',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: subTextColor,
                      ),
                    ),
            ),
            const SizedBox(width: 12),

            // 封面
            Container(
              width: 60,
              height: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: movie.cover.isNotEmpty
                  ? Image.network(
                      movie.cover,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.movie_outlined, color: Colors.grey),
                    )
                  : const Icon(Icons.movie_outlined, color: Colors.grey),
            ),
            const SizedBox(width: 12),

            // 影片信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movie.name,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: isTop3 ? FontWeight.bold : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // 类型/年份
                  if (movie.genres.isNotEmpty || movie.year.isNotEmpty)
                    Text(
                      '${movie.genres.isNotEmpty ? movie.genres.take(2).join('/') : ''}'
                      '${movie.genres.isNotEmpty && movie.year.isNotEmpty ? ' / ' : ''}'
                      '${movie.year}',
                      style: TextStyle(
                        color: subTextColor,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 6),
                  // 评分
                  if (movie.rating > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: movie.rating >= 8.0
                            ? Colors.orange.withValues(alpha: 0.1)
                            : movie.rating >= 6.0
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star,
                            color: movie.rating >= 8.0
                                ? Colors.orange
                                : movie.rating >= 6.0
                                    ? Colors.green
                                    : Colors.grey,
                            size: 14,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            movie.rating.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: movie.rating >= 8.0
                                  ? Colors.orange
                                  : movie.rating >= 6.0
                                      ? Colors.green
                                      : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // 箭头
            Icon(
              Icons.chevron_right,
              size: 20,
              color: subTextColor.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

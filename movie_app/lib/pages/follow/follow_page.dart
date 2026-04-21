import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import '../../providers/favorite_provider.dart';
import '../../providers/history_provider.dart';
import '../../providers/cache_provider.dart';
import '../../models/cache_item.dart';
import '../../models/favorite.dart';
import '../../models/watch_history.dart';
import '../../models/movie.dart';
import '../../config/routes.dart';
import '../../widgets/empty_widget.dart';
import '../../widgets/hifi_wide_constrained_body.dart';

/// 追剧页面（收藏 + 观看历史 + 缓存管理）
class FollowPage extends StatefulWidget {
  const FollowPage({super.key});

  @override
  State<FollowPage> createState() => _FollowPageState();
}

class _FollowPageState extends State<FollowPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('追剧'),
        // B站风格TabBar（选中项粗体+主题色+底部指示器）
        bottom: TabBar(
          controller: _tabController,
          indicatorSize: TabBarIndicatorSize.label,
          indicatorWeight: 3,
          indicatorColor: theme.colorScheme.primary,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.hintColor,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.normal,
            fontSize: 15,
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 16),
          dividerColor: Colors.transparent,
          tabs: [
            Tab(
              child: Consumer<FavoriteProvider>(
                builder: (context, provider, _) {
                  final totalUpdate = provider.totalUpdateCount;
                  if (totalUpdate > 0) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('收藏'),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints: const BoxConstraints(minWidth: 18),
                          child: Text(
                            '$totalUpdate',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    );
                  }
                  return const Text('收藏');
                },
              ),
            ),
            const Tab(text: '历史'),
            const Tab(text: '缓存'),
          ],
        ),
      ),
      body: HiFiWideConstrainedBody(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildFavoritesTab(theme),
            _buildHistoryTab(theme),
            _buildCacheTab(theme),
          ],
        ),
      ),
    );
  }

  /// 收藏列表
  Widget _buildFavoritesTab(ThemeData theme) {
    return Consumer2<FavoriteProvider, HistoryProvider>(
      builder: (
        context,
        FavoriteProvider provider,
        HistoryProvider historyProvider,
        _,
      ) {
        final favorites = provider.favorites;

        if (favorites.isEmpty) {
          return const NoFavoriteWidget();
        }

        // 排序：有更新的影片排到顶部
        final sortedFavorites = List<Favorite>.from(favorites);
        sortedFavorites.sort((a, b) {
          final aHasUpdate =
              provider.hasUpdate(a.movieId, sourceId: a.sourceId);
          final bHasUpdate =
              provider.hasUpdate(b.movieId, sourceId: b.sourceId);
          if (aHasUpdate && !bHasUpdate) return -1;
          if (!aHasUpdate && bHasUpdate) return 1;
          return 0;
        });

        // 找到有更新和无更新的分界点
        int updateBoundary = 0;
        for (int i = 0; i < sortedFavorites.length; i++) {
          if (provider.hasUpdate(
            sortedFavorites[i].movieId,
            sourceId: sortedFavorites[i].sourceId,
          )) {
            updateBoundary = i + 1;
          } else {
            break;
          }
        }

        return ListView.builder(
          itemCount: sortedFavorites.length +
              (updateBoundary > 0 && updateBoundary < sortedFavorites.length
                  ? 1
                  : 0),
          itemBuilder: (context, index) {
            // 在有更新和无更新之间插入分隔线
            if (updateBoundary > 0 &&
                updateBoundary < sortedFavorites.length &&
                index == updateBoundary) {
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: theme.dividerColor,
                        thickness: 1,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '其他收藏',
                        style: TextStyle(
                          color: theme.hintColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: theme.dividerColor,
                        thickness: 1,
                      ),
                    ),
                  ],
                ),
              );
            }

            // 计算实际索引（跳过分隔线位置）
            final actualIndex = index > updateBoundary ? index - 1 : index;
            final fav = sortedFavorites[actualIndex];

            // 查找观看记录
            final history =
                historyProvider.getHistory(fav.movieId, sourceId: fav.sourceId);

            return _buildFavoriteItem(
              context,
              fav: fav,
              history: history,
              provider: provider,
              theme: theme,
            );
          },
        );
      },
    );
  }

  /// B站风格收藏卡片（左图右文布局）
  Widget _buildFavoriteItem(
    BuildContext context, {
    required Favorite fav,
    required WatchHistory? history,
    required FavoriteProvider provider,
    required ThemeData theme,
  }) {
    final hasUpdate = provider.hasUpdate(fav.movieId, sourceId: fav.sourceId);

    return InkWell(
      onTap: () {
        // 点击有更新的影片时，清除该影片的更新计数
        if (hasUpdate) {
          provider.clearUpdateCount('${fav.sourceId}_${fav.movieId}');
        }
        AppRoutes.toDetail(
          context,
          id: fav.movieId,
          sourceId: fav.sourceId,
          movie: Movie(
            id: fav.movieId,
            sourceId: fav.sourceId,
            name: fav.movieName,
            cover: fav.movieCover,
            rating: fav.rating,
            genres: fav.genres,
            updateStatus: fav.updateStatus,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // 左侧封面（B站风格圆角8px）
            Stack(
              children: [
                Container(
                  width: 100,
                  height: 66,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: fav.movieCover.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: fav.movieCover,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const Icon(
                            Icons.movie_outlined,
                            color: Colors.grey,
                          ),
                        )
                      : const Icon(Icons.movie_outlined, color: Colors.grey),
                ),
                // 右上角红色更新角标
                if (hasUpdate)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(8),
                          bottomLeft: Radius.circular(8),
                        ),
                      ),
                      child: Text(
                        '+${provider.getUpdateCount('${fav.sourceId}_${fav.movieId}')}集',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),

            // 右侧信息区域
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 影片名称
                  Text(
                    fav.movieName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // 更新状态
                  Text(
                    fav.updateStatus,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // 观看进度标签（"看到第X集"）
                  if (history != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          history.episodeName.isNotEmpty
                              ? '看到${history.episodeName}'
                              : '看到第${history.episodeIndex + 1}集',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 右侧删除按钮
            IconButton(
              icon: const Icon(Icons.close_outlined, size: 18),
              onPressed: () {
                provider.removeFavorite(fav.movieId, sourceId: fav.sourceId);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 观看历史（B站风格左图右文 + 进度条）
  Widget _buildHistoryTab(ThemeData theme) {
    return Consumer<HistoryProvider>(
      builder: (context, provider, _) {
        final histories = provider.histories;
        if (histories.isEmpty) {
          return const NoHistoryWidget();
        }
        return Column(
          children: [
            if (histories.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => provider.clearAll(),
                    child: const Text('清空历史'),
                  ),
                ),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: histories.length,
                itemBuilder: (context, index) {
                  final history = histories[index];
                  return _buildHistoryItem(
                    context,
                    history: history,
                    theme: theme,
                    provider: provider,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// B站风格历史卡片（左图右文 + 底部进度条）
  Widget _buildHistoryItem(
    BuildContext context, {
    required WatchHistory history,
    required ThemeData theme,
    required HistoryProvider provider,
  }) {
    return InkWell(
      onTap: () {
        AppRoutes.toDetailFromHistory(context, history);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            Row(
              children: [
                // 左侧封面（B站风格圆角8px）
                Container(
                  width: 100,
                  height: 66,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: history.movieCover.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: history.movieCover,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const Icon(
                            Icons.movie_outlined,
                            color: Colors.grey,
                          ),
                        )
                      : const Icon(Icons.movie_outlined, color: Colors.grey),
                ),
                const SizedBox(width: 12),

                // 右侧信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        history.movieName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${history.episodeName.isNotEmpty ? history.episodeName : '第${history.episodeIndex + 1}集'} | ${history.progressPercent.toStringAsFixed(0)}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.hintColor,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // 删除按钮
                IconButton(
                  icon: const Icon(Icons.close_outlined, size: 18),
                  onPressed: () {
                    provider.deleteHistory(
                      history.movieId,
                      sourceId: history.sourceId,
                    );
                  },
                ),
              ],
            ),
            // B站风格底部进度条
            Padding(
              padding: const EdgeInsets.only(left: 112, right: 50, top: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: history.progressPercent,
                  minHeight: 3,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 缓存管理
  Widget _buildCacheTab(ThemeData theme) {
    return Consumer<CacheProvider>(
      builder: (context, cacheProvider, _) {
        return Column(
          children: [
            // 缓存信息栏
            Container(
              padding: const EdgeInsets.all(16),
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '缓存大小: ${cacheProvider.formattedTotalSize}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '已缓存 ${cacheProvider.completedCount} 个视频',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.hintColor),
                      ),
                    ],
                  ),
                  if (cacheProvider.cacheItems.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('清理缓存'),
                            content: const Text('确定要清理所有缓存吗？'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  await cacheProvider.clearAllCache();
                                  if (context.mounted) {
                                    Navigator.of(context).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('缓存已清理')),
                                    );
                                  }
                                },
                                child: const Text(
                                  '清理',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Text('清理全部'),
                    ),
                ],
              ),
            ),
            // 缓存列表
            Expanded(
              child: cacheProvider.cacheItems.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.download_outlined,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text('暂无缓存', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: cacheProvider.cacheItems.length,
                      itemBuilder: (context, index) {
                        final item = cacheProvider.cacheItems[index];
                        final progress = (item.progressPercent * 100).toInt();
                        return Dismissible(
                          key: ValueKey(item.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            child:
                                const Icon(Icons.delete, color: Colors.white),
                          ),
                          onDismissed: (_) =>
                              cacheProvider.deleteCache(item.id),
                          child: ListTile(
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: item.isCompleted
                                  ? const Icon(
                                      Icons.download_done,
                                      color: Colors.green,
                                    )
                                  : item.isDownloading
                                      ? const CircularProgressIndicator(
                                          strokeWidth: 3,
                                        )
                                      : item.isFailed
                                          ? const Icon(
                                              Icons.error_outline,
                                              color: Colors.red,
                                            )
                                          : const Icon(
                                              Icons.download,
                                              color: Colors.grey,
                                            ),
                            ),
                            title: Text(
                              item.movieName,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${item.episodeName} | ${item.quality}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.hintColor,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (!item.isCompleted)
                                  Row(
                                    children: [
                                      Expanded(
                                        child: LinearProgressIndicator(
                                          value: item.progressPercent,
                                          backgroundColor: theme.colorScheme
                                              .surfaceContainerHighest,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            item.isFailed
                                                ? Colors.red
                                                : theme.colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '$progress%',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          fontSize: 11,
                                          color: theme.hintColor,
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  Text(
                                    item.formattedSize,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 11,
                                      color: theme.hintColor,
                                    ),
                                  ),
                              ],
                            ),
                            trailing:
                                _buildCacheAction(context, item, cacheProvider),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCacheAction(
    BuildContext context,
    CacheItem item,
    CacheProvider provider,
  ) {
    if (item.isDownloading) {
      return IconButton(
        icon: const Icon(Icons.pause, size: 20),
        onPressed: () => provider.pauseDownload(item.id),
      );
    } else if (item.isPaused || item.isFailed || item.isWaiting) {
      return IconButton(
        icon: const Icon(Icons.play_arrow, size: 20),
        onPressed: () => provider.resumeDownload(item.id),
      );
    } else if (item.isCompleted) {
      return IconButton(
        icon: const Icon(Icons.play_circle, size: 20, color: Colors.green),
        onPressed: () async {
          final file = File(item.localPath);
          if (await file.exists()) {
            if (!context.mounted) return;
            // 桌面平台使用默认播放器打开
            if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
              if (Platform.isWindows) {
                await Process.run('cmd', ['/c', 'start', '', item.localPath]);
              } else if (Platform.isMacOS) {
                await Process.run('open', [item.localPath]);
              } else if (Platform.isLinux) {
                await Process.run('xdg-open', [item.localPath]);
              }
              if (!context.mounted) return;
            }
          } else {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('缓存文件不存在')),
            );
          }
        },
      );
    }
    return const SizedBox.shrink();
  }
}

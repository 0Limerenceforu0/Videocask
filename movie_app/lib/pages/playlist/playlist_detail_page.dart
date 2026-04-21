import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/routes.dart';
import '../../models/playlist.dart';
import '../../providers/playlist_provider.dart';

/// 播放列表详情页
///
/// 显示列表内影片（竖版卡片网格），支持点击跳转详情、左滑删除、播完自动下一部开关。
class PlaylistDetailPage extends StatefulWidget {
  /// 播放列表ID
  final String playlistId;

  const PlaylistDetailPage({super.key, required this.playlistId});

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  /// 播完自动下一部开关
  bool _autoPlayNext = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final provider = context.watch<PlaylistProvider>();
    final playlist = provider.getPlaylist(widget.playlistId);

    final bgColor = isDark ? const Color(0xFF17181A) : const Color(0xFFF4F4F4);
    final cardColor = isDark ? const Color(0xFF222325) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(playlist?.name ?? '播放列表'),
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          // 播完自动下一部开关
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: theme.colorScheme.onSurface,
            ),
            color: cardColor,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            position: PopupMenuPosition.over,
            onSelected: (value) {
              if (value == 'auto_play') {
                setState(() => _autoPlayNext = !_autoPlayNext);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'auto_play',
                child: Row(
                  children: [
                    Icon(
                      _autoPlayNext ? Icons.toggle_on : Icons.toggle_off,
                      color: _autoPlayNext
                          ? theme.colorScheme.primary
                          : theme.hintColor,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '播完自动下一部',
                      style: TextStyle(
                        color: _autoPlayNext
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: playlist == null || playlist.items.isEmpty
          ? _buildEmptyState(context, theme)
          : _buildMovieGrid(context, theme, playlist),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.video_library_outlined,
            size: 80,
            color: theme.hintColor.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '列表为空',
            style: TextStyle(
              color: theme.hintColor,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '在影片详情页点击「添加到播放列表」来添加影片',
            style: TextStyle(
              color: theme.hintColor.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建影片网格
  Widget _buildMovieGrid(
    BuildContext context,
    ThemeData theme,
    Playlist playlist,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.65,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
      ),
      itemCount: playlist.items.length,
      itemBuilder: (context, index) {
        final item = playlist.items[index];
        return _buildMovieCard(context, theme, item, index);
      },
    );
  }

  /// 构建影片卡片
  Widget _buildMovieCard(
    BuildContext context,
    ThemeData theme,
    PlaylistItem item,
    int index,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final textColor =
        isDark ? const Color(0xFFE6E6E6) : const Color(0xFF212121);
    final subTextColor =
        isDark ? const Color(0xFF999999) : const Color(0xFF999999);

    return Dismissible(
      key: ValueKey('${item.movieId}_${item.sourceId}_$index'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: theme.colorScheme.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              '确认移除',
              style: TextStyle(color: theme.colorScheme.onSurface),
            ),
            content: Text(
              '确定要从播放列表中移除「${item.movieName}」吗？',
              style: TextStyle(color: theme.hintColor),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text('取消', style: TextStyle(color: theme.hintColor)),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('移除'),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) {
        context
            .read<PlaylistProvider>()
            .removeItem(widget.playlistId, item.movieId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已移除「${item.movieName}」')),
        );
      },
      child: GestureDetector(
        onTap: () => AppRoutes.toDetail(
          context,
          id: item.movieId,
          sourceId: item.sourceId,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面图
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(
                aspectRatio: 0.65,
                child: item.coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: item.coverUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 300,
                        memCacheHeight: 462,
                        errorWidget: (_, __, ___) => Center(
                          child: Icon(
                            Icons.movie_outlined,
                            size: 36,
                            color: subTextColor.withValues(alpha: 0.4),
                          ),
                        ),
                      )
                    : Center(
                        child: Icon(
                          Icons.movie_outlined,
                          size: 36,
                          color: subTextColor.withValues(alpha: 0.4),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),

            // 序号 + 影片名称
            Text(
              '${index + 1}. ${item.movieName}',
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

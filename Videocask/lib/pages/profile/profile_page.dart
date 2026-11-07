import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../utils/web_http_stub.dart'
    if (dart.library.html) '../../utils/web_http.dart' as web_http;
import '../../config/routes.dart';
import '../../services/episode_name_normalizer.dart';
import '../../widgets/webdav_config_sheet.dart';
import '../../providers/settings_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/favorite_provider.dart';
import '../../providers/history_provider.dart';
import '../../providers/cache_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../widgets/empty_widget.dart';
import 'dart:async' show unawaited;

/// 个人中心页面
///
/// 显示用户登录状态、数据统计、账号管理、数据同步等功能入口。
/// 支持游客模式和已登录两种状态的不同展示。
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final userProvider = context.watch<UserProvider>();
    final favoriteProvider = context.watch<FavoriteProvider>();
    final historyProvider = context.watch<HistoryProvider>();
    final cacheProvider = context.watch<CacheProvider>();
    final playlistProvider = context.watch<PlaylistProvider>();

    final bgColor = isDark ? const Color(0xFF17181A) : const Color(0xFFF4F4F4);
    final cardColor = isDark ? const Color(0xFF222325) : Colors.white;
    final textColor =
        isDark ? const Color(0xFFE6E6E6) : const Color(0xFF212121);
    final subTextColor =
        isDark ? const Color(0xFF999999) : const Color(0xFF999999);
    final dividerColor =
        isDark ? const Color(0xFF2E2F31) : const Color(0xFFEEEEEE);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('我的'),
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // 仅当本页由路由 push 打开时显示返回（底栏「我的」嵌在主壳内时不可 pop）
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new),
                onPressed: () => context.pop(),
              )
            : null,
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ===== 账号头部：压到一行，功能入口不再被推到第二屏 =====
          _buildUserHeader(context, theme, userProvider, cardColor: cardColor),
          const SizedBox(height: 12),

          // ===== 继续观看（原来 4 张统计卡只留这一张）=====
          _buildContinueWatching(
            context,
            historyProvider,
            cardColor: cardColor,
            textColor: textColor,
            subTextColor: subTextColor,
          ),
          const SizedBox(height: 12),

          // ===== 常用 =====
          _buildBiliSectionHeader(textColor: textColor, title: '常用'),
          _buildBiliSectionCard(
            cardColor: cardColor,
            children: [
              _buildBiliMenuItem(
                context,
                icon: Icons.favorite_border,
                iconBgColor: const Color(0xFFF48FB1),
                title: '我的收藏',
                value: '${favoriteProvider.count} 部',
                textColor: textColor,
                subTextColor: subTextColor,
                onTap: () => _showFavorites(context),
              ),
              _buildBiliCardDivider(dividerColor),
              _buildBiliMenuItem(
                context,
                icon: Icons.download_outlined,
                iconBgColor: const Color(0xFFA5D6A7),
                title: '我的缓存',
                value: cacheProvider.formattedTotalSize,
                textColor: textColor,
                subTextColor: subTextColor,
                onTap: () => AppRoutes.toCacheManager(context),
              ),
              _buildBiliCardDivider(dividerColor),
              _buildBiliMenuItem(
                context,
                icon: Icons.playlist_play,
                iconBgColor: const Color(0xFFCE93D8),
                title: '播放列表',
                value: '${playlistProvider.count} 个列表',
                textColor: textColor,
                subTextColor: subTextColor,
                onTap: () => AppRoutes.toPlaylist(context),
              ),
              _buildBiliCardDivider(dividerColor),
              _buildBiliMenuItem(
                context,
                icon: Icons.bar_chart,
                iconBgColor: const Color(0xFF4FC3F7),
                title: '观影统计',
                value: '查看真实观影数据',
                textColor: textColor,
                subTextColor: subTextColor,
                onTap: () => AppRoutes.toStats(context),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ===== 云备份（原「数据同步」：两个假同步入口已删）=====
          _buildBiliSectionHeader(textColor: textColor, title: '云备份'),
          _buildBiliSectionCard(
            cardColor: cardColor,
            children: [
              _buildBiliMenuItem(
                context,
                icon: Icons.cloud_outlined,
                iconBgColor: const Color(0xFF90CAF9),
                title: 'WebDAV 设置',
                value: context.select<SettingsProvider, bool>(
                        (s) => s.webdavConnected)
                    ? '已连接'
                    : '未配置',
                textColor: textColor,
                subTextColor: subTextColor,
                onTap: () => unawaited(showWebDavConfigSheet(context)),
              ),
              _buildBiliCardDivider(dividerColor),
              _buildBiliMenuItem(
                context,
                icon: Icons.sync_alt_outlined,
                iconBgColor: const Color(0xFFCE93D8),
                title: '更多同步选项',
                value: '上传 / 下载 / 双向同步',
                textColor: textColor,
                subTextColor: subTextColor,
                onTap: () => AppRoutes.toSettings(context, anchor: 'webdav'),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ===== 账号管理（整套账号体系保留，后续接服务端）=====
          _buildBiliSectionHeader(textColor: textColor, title: '账号管理'),
          _buildBiliSectionCard(
            cardColor: cardColor,
            children: [
              _buildBiliMenuItem(
                context,
                icon: Icons.person_outline,
                iconBgColor: const Color(0xFF4FC3F7),
                title: '账号管理',
                value: userProvider.isGuestMode
                    ? '当前为游客模式'
                    : '已登录 - ${userProvider.loginTypeDisplayName}',
                textColor: textColor,
                subTextColor: subTextColor,
                onTap: () => AppRoutes.toLogin(context),
              ),
              if (!userProvider.isGuestMode) ...[
                _buildBiliCardDivider(dividerColor),
                _buildBiliMenuItem(
                  context,
                  icon: Icons.swap_horiz,
                  iconBgColor: const Color(0xFF81C784),
                  title: '切换账号',
                  value: '切换到其他账号登录',
                  textColor: textColor,
                  subTextColor: subTextColor,
                  onTap: () => AppRoutes.toLogin(context),
                ),
                _buildBiliCardDivider(dividerColor),
                _buildBiliMenuItem(
                  context,
                  icon: Icons.logout,
                  iconBgColor: const Color(0xFFE57373),
                  title: '退出登录',
                  value: '退出后切换为游客模式',
                  textColor: const Color(0xFFE57373),
                  subTextColor: subTextColor,
                  onTap: () => _showLogoutConfirmDialog(context, userProvider),
                ),
              ],
            ],
          ),

          const SizedBox(height: 12),

          // ===== 设置（关于 / 播放源管理只在设置里保留一份）=====
          _buildBiliSectionHeader(textColor: textColor, title: '设置'),
          _buildBiliSectionCard(
            cardColor: cardColor,
            children: [
              _buildBiliMenuItem(
                context,
                icon: Icons.settings_outlined,
                iconBgColor: const Color(0xFFB0BEC5),
                title: '设置中心',
                value: '',
                textColor: textColor,
                subTextColor: subTextColor,
                onTap: () => AppRoutes.toSettings(context),
              ),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 构建用户信息头部
  /// 账号头部：一行搞定头像 + 昵称 + 状态，不再占掉首屏大半。
  Widget _buildUserHeader(
    BuildContext context,
    ThemeData theme,
    UserProvider userProvider, {
    required Color cardColor,
  }) {
    final userInfo = userProvider.userInfo;
    final isGuest = userProvider.isGuestMode;
    final subTitle = isGuest
        ? '登录后头像与昵称仅保存在本机'
        : '${userProvider.loginTypeDisplayName} · ID ${userProvider.displayUid}';

    return InkWell(
      onTap: () => AppRoutes.toLogin(context),
      child: Container(
        color: cardColor,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: userInfo.avatar.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: web_http.webProxiedImageUrl(userInfo.avatar),
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          _buildDefaultAvatar(theme, isGuest),
                    )
                  : _buildDefaultAvatar(theme, isGuest),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userInfo.nickname.isNotEmpty
                        ? userInfo.nickname
                        : '游客用户',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subTitle,
                    style: TextStyle(
                      color: theme.hintColor,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.hintColor,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建默认头像
  Widget _buildDefaultAvatar(ThemeData theme, bool isGuest) {
    return Icon(
      isGuest ? Icons.person_outline : Icons.person,
      size: 40,
      color: theme.colorScheme.primary,
    );
  }

  /// 继续观看：唯一保留的统计入口。没有历史时用一行文字，不再摆空卡片。
  Widget _buildContinueWatching(
    BuildContext context,
    HistoryProvider historyProvider, {
    required Color cardColor,
    required Color textColor,
    required Color subTextColor,
  }) {
    final histories = historyProvider.histories;
    if (histories.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          '还没有观看记录',
          style: TextStyle(color: subTextColor, fontSize: 13),
        ),
      );
    }
    final latest = histories.reduce(
      (a, b) => a.lastWatchTime.isAfter(b.lastWatchTime) ? a : b,
    );
    final episode = normalizeEpisodeName(latest.episodeName);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        onTap: () => _showHistory(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 60,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                clipBehavior: Clip.antiAlias,
                child: latest.movieCover.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: web_http.webProxiedImageUrl(
                          latest.movieCover,
                        ),
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const Icon(
                          Icons.movie_outlined,
                          color: Colors.grey,
                        ),
                      )
                    : const Icon(Icons.movie_outlined, color: Colors.grey),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '继续观看',
                      style: TextStyle(color: subTextColor, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      latest.movieName,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${episode.isEmpty ? '第${latest.episodeIndex + 1}集' : episode}'
                      ' · 已看 ${latest.progressPercent.toStringAsFixed(0)}%',
                      style: TextStyle(color: subTextColor, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.play_circle_fill,
                size: 34,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// B站风格区域标题
  Widget _buildBiliSectionHeader({
    required Color textColor,
    required String title,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          color: textColor,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// B站风格分组卡片
  Widget _buildBiliSectionCard({
    required Color cardColor,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }

  /// B站风格卡片内分隔线
  Widget _buildBiliCardDivider(Color dividerColor) {
    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: Divider(height: 1, color: dividerColor),
    );
  }

  /// B站风格菜单项
  Widget _buildBiliMenuItem(
    BuildContext context, {
    required IconData icon,
    required Color iconBgColor,
    required String title,
    required String value,
    required Color textColor,
    required Color subTextColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBgColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconBgColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (value.isNotEmpty)
              Text(
                value,
                style: TextStyle(
                  color: subTextColor,
                  fontSize: 13,
                ),
              ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: subTextColor.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示退出登录确认对话框
  void _showLogoutConfirmDialog(
    BuildContext context,
    UserProvider userProvider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认退出登录'),
        content: const Text('退出登录后将切换为游客模式，您的本地数据不会丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await userProvider.logout();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('确认退出'),
          ),
        ],
      ),
    );
  }

  /// 显示收藏列表
  void _showFavorites(BuildContext context) {
    final favorites = context.read<FavoriteProvider>().favorites;
    final favoriteProvider = context.read<FavoriteProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: favorites.isEmpty
              ? const NoFavoriteWidget()
              : ListView.builder(
                  controller: scrollController,
                  itemCount: favorites.length,
                  itemBuilder: (context, index) {
                    final fav = favorites[index];
                    return ListTile(
                      leading: Stack(
                        children: [
                          Container(
                            width: 48,
                            height: 64,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: fav.movieCover.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: web_http.webProxiedImageUrl(
                                      fav.movieCover,
                                    ),
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => const Icon(
                                      Icons.movie_outlined,
                                      color: Colors.grey,
                                    ),
                                  )
                                : const Icon(
                                    Icons.movie_outlined,
                                    color: Colors.grey,
                                  ),
                          ),
                          // 更新角标
                          if (favoriteProvider.hasUpdate(
                            fav.movieId,
                            sourceId: fav.sourceId,
                          ))
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  '更新',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(fav.movieName),
                      subtitle: Text(
                        fav.updateStatus,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).hintColor),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close_outlined, size: 18),
                        onPressed: () {
                          context.read<FavoriteProvider>().removeFavorite(
                                fav.movieId,
                                sourceId: fav.sourceId,
                              );
                        },
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        AppRoutes.toDetail(
                          context,
                          id: fav.movieId,
                          sourceId: fav.sourceId,
                        );
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  /// 显示观看历史
  void _showHistory(BuildContext context) {
    final histories = context.read<HistoryProvider>().histories;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '观看历史',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (histories.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          context.read<HistoryProvider>().clearAll();
                        },
                        child: const Text('清空'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: histories.isEmpty
                    ? const NoHistoryWidget()
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: histories.length,
                        itemBuilder: (context, index) {
                          final history = histories[index];
                          return ListTile(
                            leading: Container(
                              width: 48,
                              height: 64,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: history.movieCover.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: web_http.webProxiedImageUrl(
                                        history.movieCover,
                                      ),
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => const Icon(
                                        Icons.movie_outlined,
                                        color: Colors.grey,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.movie_outlined,
                                      color: Colors.grey,
                                    ),
                            ),
                            title: Text(history.movieName),
                            subtitle: Text(
                              '${normalizeEpisodeName(history.episodeName)} | ${history.progressPercent.toStringAsFixed(0)}%',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).hintColor,
                                  ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close_outlined, size: 18),
                              onPressed: () {
                                context.read<HistoryProvider>().deleteHistory(
                                      history.movieId,
                                      sourceId: history.sourceId,
                                    );
                              },
                            ),
                            onTap: () {
                              Navigator.of(context).pop();
                              AppRoutes.toDetailFromHistory(context, history);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

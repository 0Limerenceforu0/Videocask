import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:movie_app/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'home/home_page.dart';
import 'follow/follow_page.dart';
import 'profile/profile_page.dart';
import '../providers/player_provider.dart';
import '../config/routes.dart';

/// 主框架页面
///
/// - Android/iOS: 显示底部导航栏（首页/追剧/我的）
/// - Web 或桌面 OS 在宽窗口下：`useWideTopBarShell` 使用顶栏图标；否则仍通过各页 AppBar 进入子页面
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  /// 当前选中的底部导航索引
  int _currentIndex = 0;

  /// 是否显示底部导航栏（仅移动端显示）
  bool get _showBottomNav {
    if (kIsWeb) return false;
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }

  /// 底部导航对应的页面列表
  final List<Widget> _pages = const [
    HomePage(),
    FollowPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    if (_showBottomNav) {
      // Android/iOS: 带底部导航栏
      return Scaffold(
        body: Stack(
          children: [
            IndexedStack(
              index: _currentIndex,
              children: _pages,
            ),
            // 迷你播放器（画中画模式）
            _buildMiniPlayer(context),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() => _currentIndex = index);
          },
          height: 56,
          backgroundColor: theme.bottomNavigationBarTheme.backgroundColor ??
              theme.colorScheme.surface,
          indicatorColor: theme.colorScheme.primaryContainer,
          surfaceTintColor: Colors.transparent,
          animationDuration: const Duration(milliseconds: 300),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: l10n.navHome,
              tooltip: l10n.navHome,
            ),
            NavigationDestination(
              icon: const Icon(Icons.subscriptions_outlined),
              selectedIcon: const Icon(Icons.subscriptions),
              label: l10n.navFollow,
              tooltip: l10n.navFollow,
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: l10n.navProfile,
              tooltip: l10n.navProfile,
            ),
          ],
        ),
      );
    } else {
      // Web/Windows: 直接显示首页（无底部导航栏）
      return Stack(
        children: [
          const HomePage(),
          // 迷你播放器（画中画模式）
          _buildMiniPlayer(context),
        ],
      );
    }
  }

  /// 构建迷你播放器条（画中画模式）
  ///
  /// 使用 Consumer 隔离重建范围，避免 PlayerProvider 变化时重建整个 MainPage。
  Widget _buildMiniPlayer(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, playerProvider, child) {
        if (!playerProvider.isMiniPlayer) return const SizedBox.shrink();

        final theme = Theme.of(context);

        return Positioned(
          left: 0,
          right: 0,
          bottom: _showBottomNav ? 64 : 0,
          child: GestureDetector(
            // 点击迷你播放器跳转回详情页
            onTap: () {
              // 跳转到当前播放影片的详情页
              if (playerProvider.movieId.isNotEmpty) {
                AppRoutes.toDetail(
                  context,
                  id: playerProvider.movieId,
                );
              }
            },
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // 封面缩略图
                  const SizedBox(width: 8),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: playerProvider.movieCover.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: playerProvider.movieCover,
                            fit: BoxFit.cover,
                            memCacheWidth: 80,
                            errorWidget: (context, url, error) => const Icon(
                              Icons.movie_outlined,
                              color: Colors.grey,
                              size: 20,
                            ),
                          )
                        : const Icon(
                            Icons.movie_outlined,
                            color: Colors.grey,
                            size: 20,
                          ),
                  ),
                  const SizedBox(width: 12),
                  // 影片名称
                  Expanded(
                    child: Text(
                      playerProvider.movieName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 播放/暂停按钮
                  IconButton(
                    icon: Icon(
                      playerProvider.isMiniPlayerPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      size: 32,
                      color: theme.colorScheme.primary,
                    ),
                    onPressed: () {
                      playerProvider.toggleMiniPlayerPlayPause();
                    },
                  ),
                  // 关闭按钮
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      playerProvider.exitMiniPlayer();
                    },
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
